"""T0：只读检查 TinyCNN 六层映射、容量和 F-J0 依赖；不训练、不连接板卡。"""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import zipfile

import torch
from torch.nn import functional as F
from torch.fx import symbolic_trace
from torch.fx.passes.shape_prop import ShapeProp
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "cnn_scripts"))
sys.path.insert(0, str(ROOT / "cnn_scripts/scripts/jtag"))
from cal_cmd_reference import make_layer
from cnn_model_tiny import SimpleCNN, transform
from model_packer import (HARDWARE_PROFILE, PACKAGE_VERSION, assign_feature_addresses,
                          assign_weight_layout, validate_layers, write_command_file)
from check_platform import bundle_records, sha256


def check_model_structure(config):
    assert config["model"] == "SimpleCNN"
    model = SimpleCNN().eval()
    graph = symbolic_trace(model)
    nodes = list(graph.graph.nodes)
    expected = [("placeholder", "x"), ("call_module", "conv1"), ("call_function", F.relu),
                ("call_function", F.max_pool2d), ("call_module", "conv2"), ("call_function", F.relu),
                ("call_function", F.max_pool2d), ("call_method", "view"), ("call_module", "fc1"),
                ("call_function", F.relu), ("call_module", "fc2"), ("output", "output")]
    assert [(node.op, node.target) for node in nodes] == expected, "存在未映射运算或拓扑变化"
    assert config["input_nchw"] == [1, 1, 28, 28] and config["inference_batch_size"] == 1
    with torch.no_grad():
        ShapeProp(graph).propagate(torch.zeros(config["input_nchw"]))
    for spec, node in zip(config["layers"], [nodes[i] for i in (2, 3, 5, 6, 9, 10)]):
        h, w, c = spec["output_hwc"]
        expected_shape = [1, c] if spec["opcode"] == "FC" else [1, c, h, w]
        assert list(node.meta["tensor_meta"].shape) == expected_shape, spec["name"]
    for name in ("conv1", "conv2"):
        module = getattr(model, name)
        assert module.kernel_size == (3, 3) and module.stride == (1, 1) and module.padding == (1, 1)
        assert module.groups == 1 and module.dilation == (1, 1) and module.bias is not None
    assert nodes[3].args[1:] == (2,) and nodes[6].args[1:] == (2,)
    assert nodes[3].kwargs == nodes[6].kwargs == dict(stride=None, padding=0, dilation=1, ceil_mode=False, return_indices=False)
    assert nodes[7].args[1:] == (-1, 3136)
    preprocessing = transform
    assert [type(item).__name__ for item in preprocessing.transforms] == config["preprocessing"]["operations"]
    assert list(preprocessing.transforms[1].mean) == config["preprocessing"]["mean"] == [0.5]
    assert list(preprocessing.transforms[1].std) == config["preprocessing"]["std"] == [0.5]
    pixels = Image.frombytes("L", (256, 1), bytes(range(256)))
    torch.testing.assert_close(preprocessing(pixels).flatten(), (torch.arange(256) / 255 - 0.5) / 0.5)
    return {"graph": str(graph.graph), "unmapped_operators": []}


def check_model(config):
    return {**check_model_structure(config),
            "source_sha256": sha256(ROOT / "cnn_scripts/cnn_model_tiny.py")}


def check_layers(config):
    layers = []
    for index, spec in enumerate(config["layers"]):
        h, w, c = spec["input_hwc"]
        if index:
            assert spec["input_hwc"] == config["layers"][index - 1]["output_hwc"]
        layer = make_layer(spec["kernel"], c, spec["output_hwc"][2], h, w,
                           spec["stride"], spec["padding"], spec["opcode"])
        layer.update(name=spec["name"], layer_index=index, last=int(index == 5), relu=int(spec["relu"]))
        assert [layer["height_out"], layer["width_out"], layer["cout"]] == spec["output_hwc"]
        layers.append(layer)
    assert len(layers) == 6
    assign_feature_addresses(layers)
    weights = assign_weight_layout(layers)
    validate_layers(layers, weights)
    with tempfile.TemporaryDirectory() as directory:
        command = write_command_file(Path(directory) / "shape_check.bin", layers)
    storage = config["expected_storage"]
    assert command["file_bytes"] == storage["command_bytes"] == 448
    assert weights["file_bytes"] == storage["weights_and_bias_bytes"] == 1993472
    assert [layer["output_bytes"] for layer in layers] == storage["layer_output_bytes"]
    assert max(layer["output_bytes"] for layer in layers) == storage["max_feature_bytes"] == 50176
    assert [(layer["input_tile_count"], layer["output_group_count"]) for layer in layers] == [(1, 4), (0, 0), (1, 8), (0, 0), (7, 2), (1, 1)]
    assert layers[0]["input_bytes"] == config["physical_format"]["input_bytes"] == 6272
    assert layers[-1]["cout_padded"] == 12 and layers[-1]["output_bytes"] == 24
    # FC 编码的 cin_padded 是展平长度；物理 HWC 通道需另行记录。
    for layer, spec in zip(layers, config["layers"]):
        layer["input_hwc_padded"] = [*spec["input_hwc"][:2], (spec["input_hwc"][2] + 3) // 4 * 4]
        layer["output_hwc_padded"] = [*spec["output_hwc"][:2], layer["cout_padded"]]
    return {"layers": layers, "command_layout_estimate": command, "weight_layout_estimate": weights,
            "quantization": "NOT_CALIBRATED; zero scale/shift fields are capacity-check placeholders"}


def check_hardware(config):
    hardware = config["hardware"]
    bundle = ROOT / hardware["bundle"]
    manifest = json.loads((ROOT / hardware["delivery_manifest"]).read_text(encoding="utf-8"))
    assert set(hardware["required_capabilities"]) <= set(manifest["capabilities"])
    assert manifest["hardware_bundle"] == hardware["bundle"] and manifest["build_id"] == hardware["build_id"]
    assert manifest["implementation"]["status"] == "PASS"
    assert all(hardware[key] == value for key, value in HARDWARE_PROFILE.items() if key in hardware)
    assert PACKAGE_VERSION == hardware["package_version"] == 2
    records = bundle_records(bundle, set(hardware["pinned_sha256"]))
    for record in records:
        name = Path(record["path"]).name
        assert record["sha256"] == manifest["artifact_sha256"][name], name
        if name in hardware["pinned_sha256"]:
            assert record["sha256"] == hardware["pinned_sha256"][name], name
        record["path"] = Path(record["path"]).relative_to(ROOT).as_posix()
    with zipfile.ZipFile(bundle / "e_j2.xsa") as archive:
        for name in ("e_j2_system_wrapper.bit", "ps7_init.tcl", "ps7_init.c", "ps7_init.h", "ps7_init.html"):
            embedded_name = "e_j2.bit" if name.endswith(".bit") else name
            members = [member for member in archive.namelist() if Path(member).name == embedded_name]
            assert len(members) == 1, f"XSA member: {name}"
            assert hashlib.sha256(archive.read(members[0])).hexdigest() == sha256(bundle / name), name
    assert "set csr_base " + hardware["csr_base"] in (bundle / "address_map.tcl").read_text()
    assert "CONFIG.PCW_CLK0_FREQ {100000000}" in (bundle / "e_j2_system_bd.tcl").read_text()
    return {"bundle": hardware["bundle"], "artifacts": records, "xsa_embedded_files": "MATCH",
            "pool_capability_evidence": hardware["delivery_manifest"],
            "pool_board_validation": "NOT_RUN", "tiny_board_validation": "NOT_RUN"}


def preserved_records(config):
    files = set()
    for name in config["preserved_paths"]:
        path = ROOT / name
        assert path.exists(), name
        if path.is_dir():
            files.update(item for item in path.rglob("*") if item.is_file())
        else:
            files.add(path)
    return {path.relative_to(ROOT).as_posix(): sha256(path) for path in sorted(files)}


def main():
    if not __debug__:
        raise RuntimeError("本检查使用 assert，请勿使用 Python -O/-OO")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="可选：写入新的检查记录；不覆盖已有记录")
    args = parser.parse_args()
    config_path = ROOT / "model/tiny_model_config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    before = preserved_records(config)
    report = {"stage": "T0", "status": "PASS",
              "checked_at": datetime.now(timezone(timedelta(hours=8))).isoformat(),
              "checker_sha256": sha256(Path(__file__)),
              "config_sha256": sha256(config_path), "torch_version": torch.__version__,
              "model": check_model(config), "capacity": check_layers(config),
              "hardware": check_hardware(config), "preserved_sha256": before}
    assert before == preserved_records(config), "原微网基线发生变化"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        with args.report.open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("PASS T0: 6 layers; input=6272 output=24 command=448 weights=1993472 bytes; F-J0 hashes/XSA match; board NOT_RUN")


if __name__ == "__main__":
    main()
