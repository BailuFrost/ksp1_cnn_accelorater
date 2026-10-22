"""TinyCNN 日常单次部署：装载一个输入、启动一次、保存输出并与 INT16 黄金值比较。"""
import argparse
import json
from pathlib import Path
import shutil
import struct
import sys

from check_platform import PROJECT, bundle_records, run_xsdb, sha256

sys.path.insert(0, str(PROJECT / "scripts"))
from cnn_compiler import ROOT, DEFAULT_OUTPUT, build_layers, load_json, require
from cnn_model_tiny import CHECKPOINT_PATH, load_checkpoint
from model_packer import HARDWARE_PROFILE, align_up, validate_files

BUNDLE = ROOT / "hardware/system"
NAMES = ("tiny_cmd.bin", "tiny_weights.bin", "quantization.json")
REQUIRED = {"e_j2.xsa", "e_j2_system_wrapper.bit", "ps7_init.tcl", "address_map.tcl", "init_checks.tcl"}


def preflight(model_dir, bundle, input_dir=None):
    """只检查本次模型／输入／硬件，不重校准、不跑测试集或历史验收场景。"""
    require(__debug__, "部署校验依赖断言，请勿使用 Python -O/-OO")
    manifest = load_json(model_dir / "deployment_manifest.json")
    config = load_json(ROOT / "hardware/tiny_model_config.json")
    quant = load_json(model_dir / "quantization.json")
    require(all(manifest["hardware_profile"].get(key) == value for key, value in HARDWARE_PROFILE.items())
            and manifest["package_version"] == 2,
            "必须使用当前 8CU INT16 模型包")
    files = {row["filename"]: row for row in manifest["files"]}
    require(len(manifest["files"]) == len(files) == len(NAMES) and set(files) == set(NAMES), "部署文件清单错误")
    for name in NAMES:
        path = model_dir / name
        require(path.stat().st_size == files[name]["bytes"] and sha256(path) == files[name]["sha256"], f"文件改变：{name}")
    checkpoint = CHECKPOINT_PATH
    require(sha256(checkpoint) == manifest["checkpoint_sha256"], "checkpoint 不匹配")
    require(sha256(model_dir / "quantization.json") == manifest["quantization_sha256"], "量化参数改变")
    require(sha256(ROOT / "hardware/tiny_model_config.json") == manifest["sources"]["hardware/tiny_model_config.json"], "模型配置改变")
    layers, weights = build_layers(config, quant)
    layouts = {"weights": weights, "command": {"base_offset": 64,
               "extension_offset": align_up(64 + len(layers) * 32),
               "file_bytes": align_up(align_up(64 + len(layers) * 32) + len(layers) * 32)}}
    validate_files(model_dir / "tiny_cmd.bin", model_dir / "tiny_weights.bin", load_checkpoint(checkpoint), layers, layouts)
    require([int(files[name]["ddr_address"], 0) for name in NAMES[:2]] ==
            [0x04000000, 0x12000000], "模型部署地址不匹配")
    require(int(manifest["input"]["ddr_address"], 0) == 0x05000000 and manifest["input"]["bytes"] == 6272
            and int(manifest["output"]["ddr_address"], 0) == 0x04200000 and manifest["output"]["bytes"] == 24,
            "输入／输出地址或长度不匹配")
    require(layers[-1]["output_bytes"] == 24 and layers[-1]["layer_index"] == 5, "必须为当前六层 TinyCNN")
    records = bundle_records(bundle, REQUIRED)
    pinned = config["hardware"]["pinned_sha256"]
    actual = {Path(row["path"]).name: row["sha256"] for row in records}
    require(all(actual.get(name) == digest for name, digest in pinned.items()), "实际硬件不是匹配的 F-J0 包")
    sizes = {Path(row["path"]).name: row["bytes"] for row in records}
    require(all(sizes.get(Path(row["path"]).name) == row["bytes"]
                for row in manifest["hardware"]["verified_artifacts"]), "硬件清单与模型包不匹配")
    require(input_dir is not None, "请通过 --input-dir 指定 feature_input.py 的输出目录")
    source = input_dir
    sample = load_json(source / "sample.json")
    require(sample["checkpoint_sha256"] == sha256(checkpoint)
            and sample["quantization_sha256"] == sha256(model_dir / "quantization.json"), "输入使用的权重或尺度不同")
    for name in ("input.bin", "expected.bin"):
        require(sha256(source / name) == sample["files"][name]["sha256"]
                and (source / name).stat().st_size == sample["files"][name]["bytes"], "输入／黄金文件改变")
    values = (source / "input.bin").read_bytes()
    expected = (source / "expected.bin").read_bytes()
    require(len(values) == 6272 and len(expected) == 24, "输入／输出长度错误")
    require(all(v == 0 for pixel in struct.iter_unpack("<4h", values) for v in pixel[1:])
            and struct.unpack("<12h", expected)[10:] == (0, 0), "物理通道补零错误")
    return records, source, sample


def prepare(run_dir, model_dir, records, source, sample):
    run_dir.mkdir(parents=True, exist_ok=False)
    payload = run_dir / "payload"
    payload.mkdir()
    for name in ("tiny_cmd.bin", "tiny_weights.bin"):
        shutil.copyfile(model_dir / name, payload / name)
    for name in ("input.bin", "expected.bin"):
        shutil.copyfile(source / name, payload / name)
    hashes = {path.name: sha256(path) for path in sorted(payload.iterdir())}
    (payload / "artifact_hashes.tsv").write_text("filename\tsha256\n" + "".join(
        f"{name}\t{digest}\n" for name, digest in hashes.items()), encoding="utf-8")
    request = {"hardware": records, "payload_sha256": hashes, "sample": sample, "board_validation": "NOT_RUN"}
    (run_dir / "request.json").write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return request


def summarize(run_dir, bundle, request):
    require((run_dir / "execution_kind.txt").read_text().strip() == "HARDWARE", "MOCK 不能作为板端结果")
    require((run_dir / "result.txt").read_text().strip() == "PASS TinyCNN inference", "单次执行未完成")
    require(bundle_records(bundle, REQUIRED) == request["hardware"], "执行期间硬件包改变")
    for name, digest in request["payload_sha256"].items():
        path = run_dir / "payload" / name
        require(sha256(path) == digest, "执行期间输入文件改变")
        if name != "expected.bin":
            require((run_dir / f"{name}.readback").read_bytes() == path.read_bytes(), f"DDR 回读不符：{name}")
    csr = [int(v, 0) for v in (run_dir / "csr.txt").read_text().split()]
    require(len(csr) == 4, "CSR 记录不完整")
    status, error, layer, cycles = csr
    require(status & 0x77 == 2 and error == 0 and layer == 5 and 0 < cycles < 2**64, "完成状态错误")
    require((run_dir / "runtime.bin").read_bytes() == struct.pack("<QII", cycles, 5, 1), "GP／CSR 记录不符")
    output = (run_dir / "output.bin").read_bytes()
    require(output == (run_dir / "payload/expected.bin").read_bytes(), "PL 输出与 INT16 黄金值不同")
    logits = list(struct.unpack("<12h", output)[:10])
    return {"status": "PASS", "board_validation": "SINGLE_INFERENCE_PASS", "start_count": 1,
            "int16_logits": logits, "prediction": max(range(10), key=logits.__getitem__),
            "cycles": cycles, "mismatch_count": 0, "sample": request["sample"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path, help="新输出目录")
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--input-dir", required=True, type=Path, help="feature_input.py 生成的目录")
    parser.add_argument("--bundle", type=Path, default=BUNDLE)
    parser.add_argument("--prepare-only", action="store_true", help="只准备本次载荷，不连接板卡")
    parser.add_argument("--xsdb", type=Path, default=Path("E:/Vitis/2024.2/bin/xsdb.bat"))
    args = parser.parse_args()
    owns_run = False
    try:
        records, source, sample = preflight(args.model_dir, args.bundle, args.input_dir)
        request = prepare(args.run_dir, args.model_dir, records, source, sample)
        owns_run = True
        if args.prepare_only:
            print(f"Prepared one TinyCNN inference; hardware NOT_RUN: {args.run_dir}")
            return 0
        require(run_xsdb(args.xsdb, [PROJECT / "scripts/jtag/infer_tiny.tcl", args.bundle.resolve(),
                args.run_dir.resolve()], args.run_dir / "xsdb.log", 1800) == 0, "XSDB 失败，请查看 xsdb.log")
        result = summarize(args.run_dir, args.bundle, request)
        (args.run_dir / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"PASS TinyCNN: prediction={result['prediction']} cycles={result['cycles']}")
        return 0
    except (OSError, ValueError, KeyError, AssertionError, RuntimeError, struct.error) as error:
        if owns_run:
            (args.run_dir / "summary.json").write_text(json.dumps({"status": "FAILED", "reason": str(error)},
                ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"FAIL TinyCNN: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
