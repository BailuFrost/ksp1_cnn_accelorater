import json
from pathlib import Path
import sys
import zipfile

import numpy as np
import torch

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
ROOT = SCRIPT_ROOT.parent
sys.path.insert(0, str(SCRIPT_ROOT))
from cnn_model_tiny import CHECKPOINT_PATH, load_checkpoint
from cal_cmd_reference import make_layer
from model_packer import (
    DDR, HEADER, HARDWARE_PROFILE, PACKAGE_VERSION, _report_layer,
    assign_feature_addresses, assign_weight_layout, validate_files, validate_layers,
    write_command_file, write_weight_file,
)
from reference import OUTPUT_DIR as REFERENCE, prepare_parameters, sha256, write_json
from check_tiny_baseline import check_model_structure

DEFAULT_OUTPUT = SCRIPT_ROOT / "generated_tiny"
CHECK_ONLY = False  # True：只读复核已有包；False：生成新包。
CHECKPOINT = CHECKPOINT_PATH

# 保留 V2 权重目录的四个既有层标识，编译时不计算摘要。
LAYER_IDS = {"conv1": bytes.fromhex("4ae47b2b94176a5d"),
             "conv2": bytes.fromhex("0de71918a31335ca"),
             "fc1": bytes.fromhex("cb107ef919596a96"),
             "fc2": bytes.fromhex("45125bb70317d674")}


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def build_layers(config, quantization):
    layers = []
    require(len(config["layers"]) == len(quantization["layers"]) == 6, "必须为六层 TinyCNN")
    for index, (spec, quant) in enumerate(zip(config["layers"], quantization["layers"])):
        require(spec["name"] == quant["name"], "层名／顺序不匹配")
        h, w, c = spec["input_hwc"]
        if index:
            require(spec["input_hwc"] == config["layers"][index - 1]["output_hwc"], "形状不连续")
        layer = make_layer(spec["kernel"], c, spec["output_hwc"][2], h, w,
                           spec["stride"], spec["padding"], spec["opcode"])
        layer.update(name=spec["name"], source=spec["name"], layer_index=index,
                     last=int(index == 5), relu=int(quant["relu"]),
                     input_fraction=quant["input_fraction"],
                     weight_fraction=quant.get("weight_fraction", 0),
                     accumulator_fraction=quant.get("accumulator_fraction", quant["input_fraction"]),
                     output_fraction=quant["output_fraction"], result_shift=quant["result_shift"])
        if spec["name"] in LAYER_IDS:
            layer["name_id"] = LAYER_IDS[spec["name"]]
        require([layer["height_out"], layer["width_out"], layer["cout"]] == spec["output_hwc"],
                "层输出形状不匹配")
        require(bool(layer["relu"]) == spec["relu"], "ReLU 不匹配")
        layers.append(layer)
    assign_feature_addresses(layers)
    layout = assign_weight_layout(layers)
    validate_layers(layers, layout)
    require(layout["file_bytes"] == config["expected_storage"]["weights_and_bias_bytes"], "权重长度不匹配")
    return layers, layout


def check_hardware(config):
    hardware = {key: value for key, value in config["hardware"].items() if key != "pinned_sha256"}
    bundle = ROOT / hardware["bundle"]
    delivery = load_json(ROOT / hardware["delivery_manifest"])
    require(set(hardware["required_capabilities"]) <= set(delivery["capabilities"]), "硬件能力不足")
    require(delivery["hardware_bundle"] == hardware["bundle"]
            and delivery["build_id"] == hardware["build_id"]
            and delivery["implementation"]["status"] == "PASS", "硬件交付配置不匹配")
    require(all(hardware[key] == value for key, value in HARDWARE_PROFILE.items() if key in hardware)
            and hardware["package_version"] == PACKAGE_VERSION, "硬件布局不匹配")
    names = ("e_j2_system_wrapper.bit", "e_j2.xsa", "ps7_init.tcl", "address_map.tcl")
    records = []
    for name in names:
        path = bundle / name
        require(path.is_file() and path.stat().st_size > 0, f"硬件文件缺失或为空：{name}")
        records.append({"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size})
    with zipfile.ZipFile(bundle / "e_j2.xsa") as archive:
        for name, embedded in (("e_j2_system_wrapper.bit", "e_j2.bit"), ("ps7_init.tcl", "ps7_init.tcl")):
            members = [member for member in archive.namelist() if Path(member).name == embedded]
            require(len(members) == 1 and archive.read(members[0]) == (bundle / name).read_bytes(),
                    f"XSA 内外文件不一致：{name}")
    require("set csr_base " + hardware["csr_base"] in (bundle / "address_map.tcl").read_text(), "CSR 地址不匹配")
    require("CONFIG.PCW_CLK0_FREQ {100000000}" in (bundle / "e_j2_system_bd.tcl").read_text(), "FCLK 配置不匹配")
    return {**hardware, "verified_artifacts": records}


def source_context():
    require(__debug__, "硬件依赖检查使用 assert，请勿使用 Python -O/-OO")
    config = load_json(ROOT / "hardware/tiny_model_config.json")
    check_model_structure(config)
    hardware = check_hardware(config)
    quant = load_json(REFERENCE / "quantization.json")
    # shortcut: 旧量化文件无权重摘要，仅校验累加界；重新校准后使用摘要绑定。
    if "checkpoint_sha256" in quant:
        require(sha256(CHECKPOINT) == quant["checkpoint_sha256"], "量化参数与 checkpoint 不匹配")
    model = load_checkpoint(CHECKPOINT)
    cache, bounds = prepare_parameters(model, quant)
    require(bounds == quant["accumulator_bounds"], "signed48 累加范围不匹配")
    sources = [CHECKPOINT, ROOT / "hardware/tiny_model_config.json", REFERENCE / "quantization.json"]
    return config, quant, model, cache, hardware, sources


def validate_payload(path, layers, parameters):
    """从磁盘读取每个物理块，以源 CHW 索引独立检查全部权重、空 lane 和偏置。"""
    raw = path.read_bytes()
    checked = biases = 0
    occupied = np.zeros(len(raw), dtype=bool)
    occupied[:HEADER.size + len(parameters) * 64] = True
    for layer in layers:
        if not layer["weight_elements"]:
            continue
        weight, bias = (value.numpy().astype(np.int64) for value in parameters[layer["name"]])
        actual = np.frombuffer(raw, dtype="<i2", count=layer["weight_elements"], offset=layer["weight_offset"])
        actual = actual.reshape(layer["output_group_count"], layer["input_tile_count"], 72, 512)
        expected = np.zeros_like(actual)
        for output in range(layer["cout"]):
            group, lane = divmod(output, layer["parallel_outputs"])
            if layer["opcode_name"] == "FC":
                # 从源 CHW 列出发计算目标 HWC 列，不调用导出器的逆映射。
                for source in range(layer["input_elements"]):
                    channel, spatial = divmod(source, layer["height"] * layer["width"])
                    target = spatial * layer["cin"] + channel
                    tile, element = divmod(target, 512)
                    expected[group, tile, lane, element] = weight[output, source]
            else:
                for channel in range(layer["cin"]):
                    tile, element = divmod(channel, 512)
                    for y in range(layer["kernel"]):
                        for x in range(layer["kernel"]):
                            expected[group, tile, lane * 9 + y * 3 + x, element] = weight[output, channel, y, x]
        require(np.array_equal(actual, expected), f"{layer['name']}: 全量权重／补零校验失败")
        actual_bias = np.frombuffer(raw, dtype="<i8", count=layer["bias_elements"], offset=layer["bias_offset"])
        expected_bias = np.zeros_like(actual_bias)
        expected_bias[:layer["cout"]] = bias
        require(np.array_equal(actual_bias, expected_bias), f"{layer['name']}: INT64 偏置／符号扩展错误")
        require(np.all(actual_bias >= -(1 << 47)) and np.all(actual_bias < (1 << 47)), "偏置超出 signed48")
        for kind in ("weight", "bias"):
            offset, size = layer[f"{kind}_offset"], layer[f"{kind}_bytes"]
            occupied[offset:offset + size] = True
        checked += actual.size
        biases += actual_bias.size
    require(not any(raw[i] for i in np.flatnonzero(~occupied)), "权重文件对齐空隙非零")
    return {"physical_weight_elements": checked, "physical_bias_elements": biases,
            "all_padding_zero": True, "signed48_bias_sign_extension": True}


def file_record(path, address=None):
    record = {"filename": path.name, "bytes": path.stat().st_size, "sha256": sha256(path)}
    if address is not None:
        record["ddr_address"] = f"0x{address:08x}"
    return record


def manifest_data(context, layers, layouts, directory):
    config, quant, _, _, hardware, sources = context
    layer_records = []
    for layer, spec in zip(layers, config["layers"]):
        item = _report_layer(layer)
        item["input_physical_hwc"] = [*spec["input_hwc"][:2], (spec["input_hwc"][2] + 3) // 4 * 4]
        item["output_physical_hwc"] = [*spec["output_hwc"][:2], layer["cout_padded"]]
        layer_records.append(item)
    files = [file_record(directory / name, address) for name, address in (
        ("tiny_cmd.bin", DDR["instructions"][0]), ("tiny_weights.bin", DDR["weights"][0]))]
    files.append(file_record(directory / "quantization.json"))
    return {"stage": "T3", "model": "SimpleCNN", "package_version": PACKAGE_VERSION,
            "instruction_layout": "V1", "hardware_profile": HARDWARE_PROFILE,
            "hardware": hardware,
            "sources": {p.relative_to(ROOT).as_posix(): sha256(p) for p in sources},
            "checkpoint_sha256": sha256(CHECKPOINT),
            "quantization_sha256": sha256(directory / "quantization.json"),
            "producer": [p.relative_to(ROOT).as_posix() for p in
                         (Path(__file__), SCRIPT_ROOT / "model_packer.py")],
            "preprocessing": config["preprocessing"],
            "physical_format": config["physical_format"], "files": files,
            "layouts": layouts, "layer_count": len(layers), "layers": layer_records,
            "runtime_record": {"ddr_address": "0x041fffc0", "bytes": 16},
            "input": {"ddr_address": f"0x{layers[0]['feature_addr']:08x}",
                      "bytes": layers[0]["input_bytes"]},
            "output": {"ddr_address": "0x04200000", "bytes": 24, "xsdb_words32": 6,
                       "valid_logits": 10, "padded_channels": 12,
                       "fraction": quant["layers"][-1]["output_fraction"]},
            "input_reload_each_run": True, "board_tested": False}


def check(directory, context=None):
    manifest = load_json(directory / "deployment_manifest.json")
    if context is None:
        context = source_context()
    config, quant, model, parameters, _, _ = context
    layers, weights = build_layers(config, quant)
    count = len(layers)
    layouts = {"weights": weights, "command": {"base_offset": 64,
               "extension_offset": (64 + count * 32 + 63) // 64 * 64,
               "file_bytes": config["expected_storage"]["command_bytes"]}}
    require(manifest == manifest_data(context, layers, layouts, directory), "部署清单／文件长度／地址／依赖不匹配")
    require((directory / "quantization.json").read_bytes() == (REFERENCE / "quantization.json").read_bytes(), "部署尺度不是 T2 尺度")
    samples = validate_files(directory / "tiny_cmd.bin", directory / "tiny_weights.bin", model, layers, layouts)
    payload = validate_payload(directory / "tiny_weights.bin", layers, parameters)
    command = (directory / "tiny_cmd.bin").read_bytes()
    header = HEADER.unpack_from(command)
    require(header[12] <= header[9] - DDR["instructions"][0] and header[9] % 64 == 0, "指令／运行记录重叠或未对齐")
    used_end = header[7] + count * header[8]
    require(not any(command[used_end:]), "指令尾部补零错误")
    return {"stage": "T3", "status": "PASS",
            "layers_decoded": count, "weight_and_bias_samples_verified": samples,
            **payload, "files": manifest["files"], "hardware_files_checked": True,
            "board_tested": False,
            "rtl_simulation_run": False, "full_decoded_network_inference_run": False}


def generate(directory):
    require(not directory.exists(), f"拒绝覆盖已有目录：{directory}")
    context = source_context()
    config, quant, model, _, _, _ = context
    layers, weights = build_layers(config, quant)
    directory.mkdir(parents=True)
    command = write_command_file(directory / "tiny_cmd.bin", layers)
    write_weight_file(directory / "tiny_weights.bin", model, layers, weights)
    (directory / "quantization.json").write_bytes((REFERENCE / "quantization.json").read_bytes())
    write_json(directory / "deployment_manifest.json",
               manifest_data(context, layers, {"command": command, "weights": weights}, directory))
    return check(directory, context)


def main():
    require(__debug__, "硬件依赖检查使用 assert，请勿使用 Python -O/-OO")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    result = check(DEFAULT_OUTPUT) if CHECK_ONLY else generate(DEFAULT_OUTPUT)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
