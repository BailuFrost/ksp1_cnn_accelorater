import hashlib
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
import torchvision

from cnn_model_tiny import ROOT, PREPROCESSING, load_checkpoint, transform
from int16_golden import (
    _max_pool_int16, _quantized_affine, fraction_bits, make_affine_parameter,
    quantize_int16, round_nearest_away,
)
from pool_reference import physical


DATA_DIR = ROOT.parent / "data"
CHECKPOINT_PATH = Path(__file__).resolve().parent / "weight/tiny_mnist.pth"
OUTPUT_DIR = Path(__file__).resolve().parent / "reports/tiny/calibration"  # 与旧评估／黄金样本分开保存。

NAMES = ("conv1", "pool1", "conv2", "pool2", "fc1", "fc2")
SEED = 114514
CALIBRATION_PER_CLASS = 100
ACCEPTANCE = {"max_accuracy_drop_percentage_points": 0.1,
              "require_signed48_safe": True, "require_repeat_exact": True}
POOL = torch.nn.MaxPool2d(2, 2)


def float_layers(model, batch):
    """保留四个仿射层激活前范围，以及硬件六层的逻辑输出。"""
    outputs, ranges = {}, {}
    value = batch
    for name in NAMES:
        if name.startswith("pool"):
            value = POOL(value)
        else:
            if name == "fc1":
                value = value.flatten(1)  # PyTorch CHW；T3 导出时才重排 FC1 权重。
            value = getattr(model, name)(value)
            ranges[name] = {"pre_relu_min": float(value.min()),
                            "pre_relu_max": float(value.max())}
            if name != "fc2":
                value = F.relu(value)
        outputs[name] = value
    return outputs, ranges


def calibration_indices(targets):
    """仅在训练划分中按固定种子每类抽取 100 张，并保存实际编号。"""
    generator = torch.Generator().manual_seed(SEED)
    selected = []
    for label in range(10):
        candidates = (targets == label).nonzero().flatten()
        if len(candidates) < CALIBRATION_PER_CLASS:
            raise ValueError(f"校准类别 {label} 不足 {CALIBRATION_PER_CLASS} 张")
        selected.extend(candidates[torch.randperm(len(candidates), generator=generator)
                                   [:CALIBRATION_PER_CLASS]].tolist())
    return selected


@torch.inference_mode()
def calibrate(model, dataset, indices):
    ranges = {name: {"min": float("inf"), "max": -float("inf")} for name in NAMES}
    input_max = 0.0
    loader = torch.utils.data.DataLoader(torch.utils.data.Subset(dataset, indices), batch_size=64)
    for images, _ in loader:
        input_max = max(input_max, float(images.abs().max()))
        outputs, before_relu = float_layers(model, images)
        for name, value in outputs.items():
            record = ranges[name]
            record["min"] = min(record["min"], float(value.min()))
            record["max"] = max(record["max"], float(value.max()))
            if name in before_relu:
                record["pre_relu_min"] = min(record.get("pre_relu_min", float("inf")),
                                              before_relu[name]["pre_relu_min"])
                record["pre_relu_max"] = max(record.get("pre_relu_max", -float("inf")),
                                              before_relu[name]["pre_relu_max"])
    current_fraction = fraction_bits(torch.tensor(input_max, dtype=torch.float64))
    input_fraction = current_fraction
    parameters = []
    for name in NAMES:
        if name.startswith("pool"):
            parameter = {"name": name, "kind": "maxpool2d", "input_fraction": current_fraction,
                         "output_fraction": current_fraction, "right_shift": 0, "relu": False}
        else:
            module = getattr(model, name)
            maximum = max(abs(ranges[name]["min"]), abs(ranges[name]["max"]))
            parameter = make_affine_parameter(
                name, "conv2d" if name.startswith("conv") else "linear", current_fraction,
                torch.tensor(maximum, dtype=torch.float64), module.weight.double(),
                module.bias.double(), name != "fc2")
        parameter["result_shift"] = parameter["right_shift"]
        parameter["calibration_range"] = ranges[name]
        parameters.append(parameter)
        current_fraction = parameter["output_fraction"]
    return {"format_version": 1, "stage": "T2", "model": "SimpleCNN",
            "input_fraction": input_fraction, "layers": parameters,
            "preprocessing": PREPROCESSING, "acceptance": ACCEPTANCE.copy(),
            "rounding": {"offline": "nearest, ties away from zero",
                         "rtl": "(acc + 2^(shift-1)) arithmetic-right-shift; shift=0 unchanged",
                         "result": "sum all input tiles, add bias once, shift, saturate INT16, ReLU",
                         "pool": "signed max, unchanged fraction, no bias/shift/ReLU"}}


@torch.inference_mode()
def prepare_parameters(model, quantization):
    """冻结整数参数，并用绝对值和界证明所有部分和均在 signed48／float64 精确范围内。"""
    if (quantization["model"] != "SimpleCNN" or quantization["format_version"] != 1
            or quantization["preprocessing"] != PREPROCESSING
            or [p["name"] for p in quantization["layers"]] != list(NAMES)):
        raise ValueError("TinyCNN 量化合同不匹配")
    current = quantization["input_fraction"]
    if type(current) is not int or not -16 <= current <= 30:
        raise ValueError("非法输入小数位数")
    cache, bounds = {}, {}
    for parameter in quantization["layers"]:
        name = parameter["name"]
        output_fraction = parameter["output_fraction"]
        shift = parameter["right_shift"]
        if (parameter["input_fraction"] != current or type(output_fraction) is not int
                or not -16 <= output_fraction <= 30 or type(shift) is not int
                or not 0 <= shift <= 63 or parameter["result_shift"] != shift):
            raise ValueError(f"{name}: 尺度不连续或非法 shift")
        if name.startswith("pool"):
            if (parameter["kind"] != "maxpool2d" or current != output_fraction
                    or shift != 0 or parameter["relu"]):
                raise ValueError(f"{name}: MAXPOOL 不允许额外量化或激活")
        else:
            weight_fraction = parameter["weight_fraction"]
            if (type(weight_fraction) is not int or not -16 <= weight_fraction <= 30
                    or parameter["accumulator_fraction"] != current + weight_fraction
                    or shift != current + weight_fraction - output_fraction
                    or parameter["relu"] != (name != "fc2")
                    or parameter["kind"] != ("conv2d" if name.startswith("conv") else "linear")):
                raise ValueError(f"{name}: 仿射层量化合同错误")
            module = getattr(model, name)
            if not torch.isfinite(module.weight).all() or not torch.isfinite(module.bias).all():
                raise ValueError(f"{name}: 参数含非有限数值")
            weight = quantize_int16(module.weight, weight_fraction)
            bias_float = round_nearest_away(module.bias.double() * 2.0**parameter["accumulator_fraction"])
            if float(bias_float.abs().max()) >= 2**47:
                raise OverflowError(f"{name}: bias 超过 signed48 安全范围")
            bias = bias_float.to(torch.int64)
            # 输入最坏取 -32768，绝对值和也覆盖任意 tile／MAC 顺序与加偏置前的部分和。
            row_bounds = weight.to(torch.int64).flatten(1).abs().sum(1) * 32768 + bias.abs()
            bound = int(row_bounds.max())
            if bound >= 2**47:
                raise OverflowError(f"{name}: 累加上界超过 signed48 安全范围")
            bounds[name] = {"max_abs_partial_sum_bound": bound, "signed48_safe": True,
                            "float64_integer_exact": bound < 2**53,
                            "bias_integer_max_abs": int(bias.abs().max())}
            cache[name] = weight, bias
        current = output_fraction
    return cache, bounds


@torch.inference_mode()
def run_tiny_int16(model, batch, quantization, cache=None):
    if batch.ndim != 4 or list(batch.shape[1:]) != [1, 28, 28] or len(batch) == 0:
        raise ValueError("TinyCNN 输入必须为 N×1×28×28")
    if not torch.isfinite(batch).all():
        raise ValueError("输入含非有限数值")
    if cache is None:
        cache, _ = prepare_parameters(model, quantization)
    value = quantize_int16(batch, quantization["input_fraction"])
    outputs, stats = {}, {}
    for parameter in quantization["layers"]:
        name = parameter["name"]
        saturated = 0
        if name.startswith("pool"):
            value = _max_pool_int16(value, POOL)
        else:
            if name == "fc1":
                value = value.flatten(1)
            value, saturated = _quantized_affine(value, getattr(model, name), parameter, cache)
        outputs[name] = value
        stats[name] = {"saturation_count": saturated, "elements": value.numel(),
                       "min": int(value.min()), "max": int(value.max())}
    return outputs, stats


def physical_bytes(value):
    """一个样本：CHW／C 逻辑值转换为 HWC 小端 INT16，每像素通道补零至四对齐。"""
    if value.dtype != torch.int16 or value.ndim not in (1, 3):
        raise ValueError("物理导出仅接受单样本 INT16 CHW 或 C")
    channels = value.shape[0]
    values = value.permute(1, 2, 0).flatten() if value.ndim == 3 else value
    return physical(values.tolist(), channels)


def write_json(path, value):
    with Path(path).open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save_sample(directory, model, image, label, index, quantization, cache):
    directory.mkdir()
    outputs, stats = run_tiny_int16(model, image.unsqueeze(0), quantization, cache)
    # 从相同模型重新创建整数参数，逐层验证冷缓存重复结果。
    repeated, repeated_stats = run_tiny_int16(model, image.unsqueeze(0), quantization)
    if stats != repeated_stats or any(not torch.equal(outputs[n], repeated[n]) for n in NAMES):
        raise AssertionError("INT16 重复前向不一致")
    values = {"input": quantize_int16(image, quantization["input_fraction"]),
              **{name: value[0] for name, value in outputs.items()}}
    files = []
    for name, value in values.items():
        logical = directory / f"{name}_logical.npy"
        np.save(logical, value.numpy().astype("<i2", copy=False), allow_pickle=False)
        payload = physical_bytes(value)
        target = directory / ("input.bin" if name == "input" else f"{name}_physical.bin")
        target.write_bytes(payload)
        files.append({"name": name, "logical_shape": list(value.shape),
                      "logical_file": logical.name, "logical_bytes": logical.stat().st_size,
                      "physical_file": target.name, "physical_bytes": len(payload),
                      "physical_layout": "HWC, C aligned to 4"})
    (directory / "expected.bin").write_bytes(physical_bytes(outputs["fc2"][0]))
    fraction = quantization["layers"][-1]["output_fraction"]
    with torch.inference_mode():
        floats = model(image.unsqueeze(0))[0]
    record = {"split": "MNIST test", "index": index, "label": label,
              "float_logits": floats.tolist(), "int16_logits": outputs["fc2"][0].tolist(),
              "dequantized_logits": (outputs["fc2"][0].double() / 2.0**fraction).tolist(),
              "output_fraction": fraction, "float_prediction": int(floats.argmax()),
              "int16_prediction": int(outputs["fc2"][0].argmax()), "repeat_exact": True,
              "layer_statistics": stats, "files": files,
              "expected_bytes": (directory / "expected.bin").stat().st_size}
    write_json(directory / "sample.json", record)
    return record


@torch.inference_mode()
def evaluate(model, dataset, quantization, cache):
    float_logits, integer_logits, labels = [], [], []
    stats = {name: {"saturation_count": 0, "elements": 0, "min": 32767, "max": -32768}
             for name in NAMES}
    for images, target in torch.utils.data.DataLoader(dataset, batch_size=64, shuffle=False):
        outputs, batch_stats = run_tiny_int16(model, images, quantization, cache)
        float_logits.append(model(images))
        integer_logits.append(outputs["fc2"])
        labels.append(target)
        for name, record in batch_stats.items():
            for key in ("saturation_count", "elements"):
                stats[name][key] += record[key]
            stats[name]["min"] = min(stats[name]["min"], record["min"])
            stats[name]["max"] = max(stats[name]["max"], record["max"])
        if len(labels) % 25 == 0:
            print(f"T2 evaluation: {sum(len(x) for x in labels)}/{len(dataset)}", flush=True)
    return torch.cat(float_logits), torch.cat(integer_logits), torch.cat(labels), stats


def main():
    out = OUTPUT_DIR
    if (out / "quantization.json").exists():
        raise FileExistsError(f"拒绝覆盖已有量化参数：{out}；请修改 OUTPUT_DIR 或复用已有参数")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    model = load_checkpoint(CHECKPOINT_PATH)
    train = torchvision.datasets.MNIST(DATA_DIR, train=True, transform=transform, download=False)
    indices = calibration_indices(train.targets)
    quantization = calibrate(model, train, indices)
    quantization.update({"checkpoint": str(CHECKPOINT_PATH.resolve()),
                         "checkpoint_sha256": sha256(CHECKPOINT_PATH),
                         "data_dir": str(DATA_DIR.resolve()),
                         "calibration": {"split": "MNIST train", "seed": SEED,
                                         "samples_per_class": CALIBRATION_PER_CLASS,
                                         "indices": indices, "labels": train.targets[indices].tolist()}})
    _, bounds = prepare_parameters(model, quantization)
    quantization["accumulator_bounds"] = bounds
    out.mkdir(parents=True, exist_ok=True)
    # 日常入口只生成尺度；完整测试集评估与逐层样本导出不在部署准备路径中。
    write_json(out / "quantization.json", quantization)
    print(f"PASS TinyCNN calibration: {len(indices)} training samples; {out / 'quantization.json'}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
