"""E-J1：调用 XSDB，复核原始回读文件并生成传输报告。"""

import argparse
import csv
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[2]
SIZES = (4096, 65536, 401408, 1048576, 4194304)
PATTERNS = ("zero", "ones", "alternating_a", "alternating_5", "address", "walking_one", "walking_zero")
ADDRESSES = (0x26000000, 0x28000000, 0x30000000, 0x3FFFF000)


def sha256(path):
    """逐块计算文件摘要，避免把大模型文件放入主机内存。"""
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def bundle_records(bundle, required=None):
    """与 Tcl 入口独立核对配套硬件清单。"""
    records = []
    with (bundle / "artifact_hashes.tsv").open(encoding="utf-8") as source:
        for row in csv.DictReader(source, delimiter="\t"):
            name, expected = row["filename"], row["sha256"]
            if Path(name).name != name or "/" in name or "\\" in name:
                raise ValueError("硬件清单包含非法文件名")
            path = bundle / name
            actual = sha256(path)
            if actual != expected:
                raise ValueError(f"硬件产物摘要不匹配：{name}")
            records.append({"path": str(path), "bytes": path.stat().st_size, "sha256": actual})
    if required is None:
        required = {"e_j0.xsa", "e_j0_system_wrapper.bit", "ps7_init.tcl", "address_map.tcl", "init_checks.tcl",
                    "implementation_summary.json", "simulation_summary.json"}
    if not required.issubset({Path(row["path"]).name for row in records}):
        raise ValueError("硬件哈希清单缺少必需产物")
    return records


def compare_pair(run_dir, input_name, output_name, size):
    """对实际文件长度及 SHA256 独立复核，不仅依赖控制台 PASS。"""
    for name in (input_name, output_name):
        if Path(name).name != name or "/" in name or "\\" in name:
            raise ValueError("回读记录包含非法文件名")
    source, output = run_dir / input_name, run_dir / output_name
    if source.stat().st_size != size or output.stat().st_size != size:
        raise ValueError(f"DDR 文件长度不匹配：{input_name}")
    digest = sha256(source)
    if digest != sha256(output):
        raise ValueError(f"DDR 回读摘要不匹配：{input_name}")
    return {"input": input_name, "output": output_name, "bytes": size, "sha256": digest}


def summarize(run_dir, bundle):
    """只有三轮完整记录及全部二进制回读通过，才接受硬件测试。"""
    if (run_dir / "execution_kind.txt").read_text().strip() != "HARDWARE":
        raise ValueError("离线模拟不能作为板端验收证据")
    result = (run_dir / "result.txt").read_text(encoding="utf-8", errors="replace").strip()
    if result != "PASS E-J1 platform access; no CNN/DataMover verification":
        raise ValueError(f"XSDB 未完成板端测试：{result or 'result.txt 为空'}")
    with (run_dir / "sessions.tsv").open() as source:
        sessions = list(csv.DictReader(source, delimiter="\t"))
    if [int(row["round"]) for row in sessions] != [1, 2, 3]:
        raise ValueError("重复初始化记录不完整")
    if len({row["jtag_hz"] for row in sessions}) != 1:
        raise ValueError("三轮 JTAG 频率不一致，不能合并吞吐数据")
    for row in sessions:
        if int(row["jtag_hz"]) <= 0 or int(row["initialize_us"]) <= 0:
            raise ValueError("初始化或 JTAG 配置计时无效")
        if any(int(row[name], 16) & 0x1005 for name in ("cpu0_sctlr", "cpu1_sctlr")):
            raise ValueError("ARM MMU/cache 未关闭")
        number = row["round"]
        for name in (f"targets_{number}.txt", f"jtag_{number}.txt", f"jtag_supported_{number}.txt"):
            if not (run_dir / name).read_text().strip():
                raise ValueError(f"缺少目标/配置记录：{name}")
    with (run_dir / "transfers.tsv").open() as source:
        transfers = list(csv.DictReader(source, delimiter="\t"))
    expected = {(number, size) for number in (1, 2, 3) for size in SIZES}
    actual = [(int(row["round"]), int(row["bytes"])) for row in transfers]
    if len(actual) != len(expected) or set(actual) != expected:
        raise ValueError("批量传输覆盖不完整或存在重复项")
    pairs = []
    for row in transfers:
        size, number = int(row["bytes"]), int(row["round"])
        if row["kind"] != "address" or int(row["address"], 16) != 0x26000000:
            raise ValueError("批量传输测试地址或模式不符")
        if row["input"] != f"r{number}_bulk_{size}.bin" or row["output"] != f"r{number}_bulk_{size}_readback.bin":
            raise ValueError("批量传输文件与记录不符")
        pairs.append(compare_pair(run_dir, row["input"], row["output"], size))
        for direction in ("write", "read"):
            duration = int(row[f"{direction}_us"])
            if duration <= 0:
                raise ValueError("传输计时必须大于零")
            row[f"{direction}_MiB_s"] = size * 1e6 / duration / (1024 * 1024)
    for number in (1, 2, 3):
        for kind in PATTERNS:
            for address in ADDRESSES:
                stem = f"r{number}_{kind}_{address:08X}"
                pairs.append(compare_pair(run_dir, f"{stem}.bin", f"{stem}_readback.bin", 4096))
    throughput = [
        {"bytes": size, **{
            f"median_{direction}_MiB_s": statistics.median(
                row[f"{direction}_MiB_s"] for row in transfers if int(row["bytes"]) == size)
            for direction in ("write", "read")}}
        for size in SIZES
    ]
    with (run_dir / "platform.tsv").open() as source:
        configuration = dict(csv.reader(source, delimiter="\t"))
    if configuration.get("platform") != "E-J0":
        raise ValueError("本入口只接受 E-J0 最小硬件平台")
    for name in ("csr_base", "expected_build_id", "fclk_hz"):
        int(configuration[name], 0)
    return {"stage": "E-J1", "status": "E_J1_COMPLETE", "board_validation": "PASS",
            "tool_version": (run_dir / "tool_version.txt").read_text().strip(),
            "configuration": configuration,
            "bundle": bundle_records(bundle), "sessions": sessions, "transfers": transfers,
            "verified_pairs": pairs, "throughput": throughput,
            "boundary": "三轮系统复位与 PS 初始化；一次物理断电上电由操作者保证；未验证 CNN/DataMover"}


def run_xsdb(xsdb, arguments, log_path, timeout):
    """设置整次运行的主机超时，失败保留日志；只终止本次启动的进程树。"""
    with log_path.open("xb") as log:
        process = subprocess.Popen([str(xsdb), *map(str, arguments)], cwd=PROJECT,
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            process.kill()
            process.wait()
            raise TimeoutError(f"XSDB 超过 {timeout} 秒；请查阅 {log_path}，重新冷启动后再测试")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path, help="新板端运行目录，或 --summarize 对应的已有目录")
    parser.add_argument("--bundle", type=Path, default=PROJECT / "reports/pc_jtag/e_j0")
    parser.add_argument("--xsdb", type=Path, default=Path("E:/Vitis/2024.2/bin/xsdb.bat"))
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--summarize", action="store_true", help="只复核既有原始板端记录")
    args = parser.parse_args()
    run_dir, bundle = args.run_dir.resolve(), args.bundle.resolve()
    owns_run = False
    try:
        if args.timeout <= 0:
            raise ValueError("主机超时必须为正数")
        if not args.summarize:
            if run_dir.exists():
                raise ValueError("运行目录已存在，请选择新目录")
            bundle_records(bundle)
            run_dir.parent.mkdir(parents=True, exist_ok=True)
            owns_run = True
            code = run_xsdb(args.xsdb, [PROJECT / "scripts/jtag/deploy.tcl", "--check-platform", bundle, run_dir],
                            run_dir.with_suffix(".log"), args.timeout)
            if code != 0:
                raise RuntimeError(f"XSDB 返回失败代码 {code}")
        report = summarize(run_dir, bundle)
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(f"FAIL E-J1：{error}", file=sys.stderr)
        if (owns_run or args.summarize) and run_dir.with_suffix(".log").is_file():
            print(f"详细 XSDB 日志：{run_dir.with_suffix('.log')}", file=sys.stderr)
        # 不能将不完整文件或启动器的零退出码当作测试成功。
        if owns_run and run_dir.is_dir():
            report = {"stage": "E-J1", "status": "FAILED", "board_validation": "FAILED", "reason": str(error)}
            (run_dir / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return 1
    (run_dir / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PASS E-J1：{len(report['verified_pairs'])} 对 DDR 文件通过；报告 {run_dir / 'summary.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
