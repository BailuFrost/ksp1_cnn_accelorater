# & 'E:/Vitis/2024.2/bin/hw_server.bat' -e 'set jtag-default-frequency 10000000'
# & 'E:/Vitis/2024.2/bin/xsdb.bat'
# connect -url tcp:127.0.0.1:3121
# targets
# & 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B 'E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/cnn_scripts/scripts/jtag/infer_vgg.py'

import json
from pathlib import Path
import shutil
import statistics
import struct
import sys

import torch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "cnn_scripts"))
from check_platform import run_xsdb
from feature_input import batch_layout, generate_payload, prepare_image
from model_packer import DIRECTORY_ENTRY, HEADER, align_up, validate_files
from vgg_compiler import build_layers, check_hardware, load_checkpoint, load_json, require
from vgg_reference import prepare_parameters

MODEL_DIR = ROOT / "cnn_scripts/weight/vgg16"
INPUT_DIR = ROOT / "cnn_scripts/inputs/vgg_batch_001"
BUNDLE = ROOT / "hardware/system"
RUN_DIR = ROOT / "reports/VGG/board_run_001"  # 每次运行使用尚不存在的新目录。
XSDB = Path("E:/Vitis/2024.2/bin/xsdb.bat")
PREPARE_ONLY = False  # 实际上板时改为 False，并指定新的 RUN_DIR。
INFERENCE_TIMEOUT_MS = 600000
HOST_TIMEOUT_SECONDS = 10800
JTAG_FREQUENCY_HZ = 10000000  # 实际 JTAG 频率写入 jtag.txt。

TRANSFERS = {
    "vgg_cmd.bin": {"ddr_address": 0x04000000, "bytes": 1472},
    "vgg_weights.bin": {"ddr_address": 0x12000000, "bytes": 286836800},
    "input.bin": {"ddr_address": 0x05000000, "bytes": 401408},
}
HARDWARE_FILES = (
    "e_j2_system_wrapper.bit", "e_j2.xsa", "ps7_init.tcl",
    "address_map.tcl", "init_checks.tcl", "e_j2_system_bd.tcl",
)


def same_bytes(left, right):
    if left.stat().st_size != right.stat().st_size:
        return False
    with left.open("rb") as a, right.open("rb") as b:
        while True:
            block = a.read(1024 * 1024)
            if block != b.read(1024 * 1024):
                return False
            if not block:
                return True


def check_inputs(input_dir, quant, config, layers):
    if (input_dir / "batch.json").is_file():
        record = load_json(input_dir / "batch.json")
        require(record["model"] == "VGG16" and record["format_version"] == 1
                and record["input_fraction"] == quant["input_fraction"]
                and record["preprocessing"] == quant["preprocessing"], "批量输入与模型量化不匹配")
        samples = record["samples"]
        require(isinstance(samples, list), "批量样本清单必须为列表")
        layout = batch_layout(config, len(samples))
        require(record["layout"] == layout
                and record["files"] == {"input_bin.bin": {"bytes": layout["bytes"]}}, "批量输入布局或长度记录错误")
        base, end = layout["ddr_address"], layout["ddr_address"] + layout["bytes"]
        for layer in layers:
            for address, size in ((layer["feature_addr"], layer["input_bytes"]),
                                  (layer["output_addr"], layer["output_bytes"])):
                require(end <= address or base >= address + size, "批量输入与实际模型工作区重叠")
        path = input_dir / "input_bin.bin"
        require(path.stat().st_size == layout["bytes"], "合并输入文件长度错误")
        with path.open("rb") as stream:
            for index, sample in enumerate(samples):
                require(type(sample["index"]) is int and sample["index"] == index
                        and type(sample["offset"]) is int and sample["offset"] == index * layout["input_bytes"]
                        and type(sample["ddr_address"]) is int
                        and sample["ddr_address"] == base + sample["offset"], "图片顺序、偏移或 DDR 地址错误")
                image = (input_dir / sample["image"]).resolve()
                require(not Path(sample["image"]).is_absolute()
                        and image.is_relative_to(input_dir.resolve()), "图片路径越出输入目录")
                _, batch = prepare_image(image, quant["preprocessing"])
                require(stream.read(layout["input_bytes"]) == generate_payload(batch, quant),
                        f"合并 BIN 与第 {index + 1} 张图片不一致")
            require(stream.read(1) == b"", "合并输入包含额外字节")
        return {"files": {"input_bin.bin": {"ddr_address": base, "bytes": layout["bytes"],
                                             "source": str(path.resolve())}},
                "batch": layout, "samples": samples}
    sample = load_json(input_dir / "sample.json")
    require(sample["model"] == "VGG16" and sample["input_fraction"] == quant["input_fraction"]
            and sample["preprocessing"] == quant["preprocessing"], "输入样本与当前量化参数不一致")
    _, batch = prepare_image(input_dir / "sample.png", quant["preprocessing"])
    path = input_dir / "input.bin"
    require(path.read_bytes() == generate_payload(batch, quant), "输入文件与保存的照片不一致")
    require(sample["files"]["input.bin"]["bytes"] == 401408, "样本记录的输入长度错误")
    return {"sample": sample, "files": {"input.bin": {
        **TRANSFERS["input.bin"], "source": str(path.resolve())}}}


def preflight(model_dir, input_dir, bundle):
    require(__debug__, "请勿使用 Python -O/-OO，二进制校验依赖断言")
    config = load_json(ROOT / "hardware/vgg16_config.json")
    require(bundle.resolve() == (ROOT / config["hardware"]["bundle"]).resolve(), "硬件目录与配置不匹配")
    check_hardware(config)
    require(config["hardware"]["fclk_hz"] == 100000000
            and int(config["hardware"]["csr_base"], 0) == 0x43C00000, "VGG16 时钟或 CSR 配置不匹配")
    bd = (bundle / "e_j2_system_bd.tcl").read_text(encoding="utf-8")
    require("CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF}" in bd, "VGG16 权重需要当前 1 GiB DDR 配置")
    quant = load_json(model_dir / "quantization.json")
    require(quant["preprocessing"] == config["preprocessing"], "输入预处理与配置不一致")
    require([p["name"] for p in quant["layers"]] == [s["name"] for s in config["layers"]], "量化层与配置不一致")
    model = load_checkpoint(ROOT / "cnn_scripts/weight/vgg16.pth")
    cache, bounds = prepare_parameters(model, quant)
    require(bounds == quant["accumulator_bounds"], "量化参数的 signed48 累加范围不匹配")
    del cache
    layers, weights = build_layers(config, quant)
    require(len(layers) == 21 and layers[-1]["layer_index"] == 20, "必须使用当前 21 层 VGG16")
    require(layers[0]["feature_addr"] == 0x05000000 and layers[0]["input_bytes"] == 401408
            and layers[-1]["output_addr"] == 0x04200000 and layers[-1]["output_bytes"] == 2000,
            "VGG16 输入／输出地址或长度不匹配")
    layouts = {"weights": weights, "command": {
        "base_offset": HEADER.size,
        "extension_offset": align_up(HEADER.size + len(layers) * 32),
        "file_bytes": align_up(align_up(HEADER.size + len(layers) * 32) + len(layers) * 32),
    }}
    # 目录名称 ID 作为不透明字段保留，部署校验不计算名称哈希。
    with (model_dir / "vgg_weights.bin").open("rb") as stream:
        stream.seek(weights["directory_offset"])
        for layer in (item for item in layers if item["weight_elements"]):
            layer["name_id"] = stream.read(8)
            stream.seek(DIRECTORY_ENTRY.size - 8, 1)
    validate_files(model_dir / "vgg_cmd.bin", model_dir / "vgg_weights.bin", model, layers, layouts)
    inputs = check_inputs(input_dir, quant, config, layers)
    files = {}
    for name, spec in TRANSFERS.items():
        if name == "input.bin":
            continue
        source = model_dir / name
        require(source.stat().st_size == spec["bytes"], f"文件长度错误：{name}")
        files[name] = {**spec, "source": str(source.resolve())}
    files.update(inputs.pop("files"))
    if "batch" in inputs:
        header = HEADER.unpack((model_dir / "vgg_cmd.bin").read_bytes()[:HEADER.size])
        require(header[5] == HEADER.size, "首层指令偏移与当前 V1 格式不匹配")
        inputs["first_input_word"] = TRANSFERS["vgg_cmd.bin"]["ddr_address"] + header[5]
        inputs["original_input_address"] = layers[0]["feature_addr"]
    hardware = {}
    for name in HARDWARE_FILES:
        path = bundle / name
        require(path.is_file() and path.stat().st_size > 0, f"硬件文件缺失或为空：{name}")
        hardware[name] = {"source": str(path.resolve()), "bytes": path.stat().st_size}
    return {"model": "VGG16", "files": files, "hardware_files": hardware, **inputs,
            "fclk_hz": config["hardware"]["fclk_hz"], "output_fraction": quant["layers"][-1]["output_fraction"],
            "board_validation": "NOT_RUN", "numerical_validation": "NOT_PERFORMED"}


def prepare(run_dir, request):
    run_dir.mkdir(parents=True, exist_ok=False)
    for folder, records in (("payload", request["files"]), ("hardware", request["hardware_files"])):
        destination = run_dir / folder
        destination.mkdir()
        for name, record in records.items():
            source, target = Path(record["source"]), destination / name
            shutil.copyfile(source, target)
            require(target.stat().st_size == record["bytes"] and same_bytes(source, target), f"准备文件复制不一致：{name}")
    (run_dir / "request.json").write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if "batch" in request:
        layout = request["batch"]
        values = [layout["ddr_address"], layout["bytes"], layout["input_bytes"], layout["count"],
                  request["first_input_word"], request["original_input_address"]]
        (run_dir / "batch.tsv").write_text("\t".join(map(str, values)) + "\n", encoding="ascii")


def summarize_image(run_dir, request):
    execution_result = (run_dir / "result.txt").read_text(encoding="utf-8", errors="replace").strip()
    require(execution_result == "PASS VGG16 execution",
            f"板端执行未完成：{execution_result}；详细日志：{run_dir / 'xsdb.log'}")
    csr = [int(value, 0) for value in (run_dir / "csr.txt").read_text().split()]
    require(len(csr) == 4, "CSR 记录不完整")
    status, error, layer, cycles = csr
    require(status & 0x77 == 2 and error == 0 and layer == 20 and 0 < cycles < 2**64, "VGG16 完成状态错误")
    require((run_dir / "runtime.bin").read_bytes() == struct.pack("<QII", cycles, 20, 1), "DDR／CSR 周期记录不一致")
    output = (run_dir / "output.bin").read_bytes()
    require(len(output) == 2000, "PL 输出必须为 1000 个 INT16 logits")
    logits = list(struct.unpack("<1000h", output))
    return {"status": "PASS", "board_validation": "EXECUTION_AND_DDR_READBACK_PASS",
            "numerical_validation": "NOT_PERFORMED", "start_count": 1,
            "int16_logits": logits, "output_fraction": request["output_fraction"],
            "prediction": max(range(1000), key=logits.__getitem__),
            "prediction_source": "host_argmax_of_PL_logits", "cycles": cycles,
            "fclk_hz": request["fclk_hz"], "latency_ms": cycles * 1000 / request["fclk_hz"],
            "sample": request["sample"]}


def completed_images(run_dir, request):
    images = []
    for sample in request["samples"]:
        directory = run_dir / "images" / f"{sample['index'] + 1:04d}"
        marker = directory / "result.txt"
        if not marker.is_file() or marker.read_text(encoding="utf-8").strip() != "PASS VGG16 execution":
            continue
        require(int((directory / "input_address.txt").read_text(), 0) == sample["ddr_address"],
                "板端图片输入地址与清单不一致")
        result = summarize_image(directory, {**request, "sample": sample})
        (directory / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        images.append(result)
    return images


def summarize(run_dir, request):
    require((run_dir / "execution_kind.txt").read_text().strip() == "HARDWARE", "离线测试不能作为板端结果")
    require((run_dir / "result.txt").read_text(encoding="utf-8").strip() == "PASS VGG16 execution",
            f"板端执行未完成：{(run_dir / 'result.txt').read_text(encoding='utf-8').strip()}；详细日志：{run_dir / 'xsdb.log'}")
    for name, spec in request["files"].items():
        path = run_dir / "payload" / name
        require(path.stat().st_size == spec["bytes"] and same_bytes(path, run_dir / f"{name}.readback"),
                f"DDR 回读与下载文件不一致：{name}")
    for name, spec in request["hardware_files"].items():
        snapshot = run_dir / "hardware" / name
        require(snapshot.stat().st_size == spec["bytes"] and same_bytes(snapshot, Path(spec["source"])),
                f"硬件文件在执行期间改变：{name}")
    if "batch" not in request:
        return summarize_image(run_dir, request)
    require(same_bytes(run_dir / "payload/input_bin.bin", run_dir / "input_bin.bin.final_readback"),
            "推理后批量输入区发生改变")
    require(int((run_dir / "restored_input_address.txt").read_text(), 0) == request["original_input_address"],
            "首层输入地址未恢复")
    images = completed_images(run_dir, request)
    require(len(images) == request["batch"]["count"] == len(request["samples"]), "批量推理未完成全部图片")
    times = [item["latency_ms"] for item in images]
    return {"status": "PASS", "board_validation": "EXECUTION_AND_DDR_READBACK_PASS",
            "numerical_validation": "NOT_PERFORMED", "start_count": len(images),
            "input_bank_unchanged": True, "images": images,
            "timing_ms": {"total": sum(times), "mean": statistics.mean(times),
                          "median": statistics.median(times), "stdev": statistics.stdev(times) if len(times) > 1 else 0,
                          "min": min(times), "max": max(times)}}


def main():
    torch.set_num_threads(4)
    owns_run = False
    try:
        require(not RUN_DIR.exists(), f"拒绝覆盖已有运行目录：{RUN_DIR}")
        require(INFERENCE_TIMEOUT_MS > 0 and HOST_TIMEOUT_SECONDS > INFERENCE_TIMEOUT_MS / 1000,
                "主机超时应大于推理超时，并留出下载和回读时间")
        require(type(JTAG_FREQUENCY_HZ) is int and JTAG_FREQUENCY_HZ > 0, "JTAG 频率必须为正整数 Hz")
        if not PREPARE_ONLY:
            require(XSDB.is_file(), f"XSDB 不存在：{XSDB}")
        request = preflight(MODEL_DIR, INPUT_DIR, BUNDLE)
        prepare(RUN_DIR, request)
        owns_run = True
        if PREPARE_ONLY:
            (RUN_DIR / "summary.json").write_text(json.dumps({"status": "PREPARED", "board_validation": "NOT_RUN"}, indent=2) + "\n", encoding="utf-8")
            print(f"Prepared VGG16; hardware NOT_RUN: {RUN_DIR}")
            return 0
        script = Path(__file__).resolve().with_suffix(".tcl")
        code = run_xsdb(XSDB, [script, (RUN_DIR / "hardware").resolve(), RUN_DIR.resolve(),
                               INFERENCE_TIMEOUT_MS, JTAG_FREQUENCY_HZ], RUN_DIR / "xsdb.log", HOST_TIMEOUT_SECONDS)
        if code != 0:
            marker = RUN_DIR / "result.txt"
            detail = marker.read_text(encoding="utf-8", errors="replace").strip() if marker.is_file() else "缺少 result.txt"
            raise RuntimeError(f"XSDB 返回 {code}：{detail}；详细日志：{RUN_DIR / 'xsdb.log'}")
        result = summarize(RUN_DIR, request)
        (RUN_DIR / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if "images" in result:
            print(f"PASS VGG16 batch: images={result['start_count']} mean_latency_ms={result['timing_ms']['mean']:.3f}")
        else:
            print(f"PASS VGG16 execution: PL logits top1={result['prediction']} cycles={result['cycles']} latency_ms={result['latency_ms']:.3f}")
        return 0
    except (OSError, ValueError, KeyError, AssertionError, RuntimeError, struct.error) as error:
        if owns_run:
            failure = {"status": "FAILED", "board_validation": "NOT_COMPLETED", "reason": str(error)}
            if "samples" in request and (RUN_DIR / "execution_kind.txt").is_file():
                try:
                    require((RUN_DIR / "execution_kind.txt").read_text().strip() == "HARDWARE", "非板端结果")
                    failure["completed_images"] = completed_images(RUN_DIR, request)
                except (OSError, ValueError, KeyError, struct.error) as partial_error:
                    failure["partial_summary_error"] = str(partial_error)
            (RUN_DIR / "summary.json").write_text(json.dumps(failure, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"FAIL VGG16: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
