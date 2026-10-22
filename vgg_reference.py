import json
from pathlib import Path

import torch
import torch.nn.functional as F
import torchvision
from torchvision import transforms

from vgg16_model import VGG16
from cnn_scripts.int16_golden import (
    fraction_bits, make_affine_parameter,quantize_int16, round_nearest_away,
)

NAMES = (
    "features.0", "features.2", "features.4",
    "features.5", "features.7", "features.9",
    "features.10", "features.12", "features.14", "features.16",
    "features.17", "features.19", "features.21", "features.23",
    "features.24", "features.26", "features.28", "features.30",
    "classifier.0", "classifier.3", "classifier.6",
)
SEED = 114514
CALIBRATION_PER_CLASS = 5
DATA_DIR = Path(__file__).resolve().parent.parent / "datasets/mini_imagenet/train"

def load_checkpoint(path):
    state_dict = torch.load(path, map_location="cpu", weights_only=True)
    model = VGG16()
    model.load_state_dict(state_dict, strict=True)
    return model.eval()

def float_layers(model, batch):
    ranges = {}
    value = batch
    for name in NAMES:
        module = model.get_submodule(name)

        if name == "classifier.0":
            value = value.flatten(1)

        value = module(value)

        if isinstance(module, (torch.nn.Conv2d, torch.nn.Linear)):
            if name != "classifier.6":
                value = F.relu(value)
        elif not isinstance(module, torch.nn.MaxPool2d):
            raise TypeError(f"{name}: 不支持的校准层类型")

        ranges[name] = {
            "min": float(value.min()),
            "max": float(value.max()),
        }

    return ranges

def calibration_indices(targets):
    targets = torch.as_tensor(targets)
    if targets.ndim != 1 or targets.numel() == 0:
        raise ValueError("targets 必须是非空的一维类别标签")
    generator = torch.Generator().manual_seed(SEED)
    selected = []
    for label in torch.unique(targets).tolist():
        candidates = (targets == label).nonzero().flatten()
        if len(candidates) < CALIBRATION_PER_CLASS:
            raise ValueError(f"校准类别 {label} 不足 {CALIBRATION_PER_CLASS} 张")
        selected.extend(candidates[torch.randperm(len(candidates), generator=generator)
                                   [:CALIBRATION_PER_CLASS]].tolist())
    return selected

@torch.inference_mode()
def calibrate(model, dataset, indices, preprocessing):
    ranges = {name: {"min": float("inf"), "max": -float("inf")} for name in NAMES}
    input_max = 0.0
    loader = torch.utils.data.DataLoader(
        torch.utils.data.Subset(dataset, indices),
        batch_size=1,
        shuffle=False,
    )
    for images, _ in loader:
        input_max = max(input_max, float(images.abs().max()))

        batch_ranges = float_layers(model, images)

        for name, record in batch_ranges.items():
            ranges[name]["min"] = min(
                ranges[name]["min"], record["min"]
            )
            ranges[name]["max"] = max(
                ranges[name]["max"], record["max"]
            )

    current_fraction = fraction_bits(torch.tensor(input_max, dtype=torch.float64))
    input_fraction = current_fraction
    parameters = []

    for name in NAMES:
        module = model.get_submodule(name)
        if isinstance(module, torch.nn.MaxPool2d):
            parameter = {
                "name": name,
                "kind": "maxpool2d",
                "input_fraction": current_fraction,
                "output_fraction": current_fraction,
                "right_shift": 0,
                "relu": False,
            }
        else:
            maximum = max(
                abs(ranges[name]["min"]),
                abs(ranges[name]["max"]),
            )
            parameter = make_affine_parameter(
                name,
                "conv2d" if isinstance(module, torch.nn.Conv2d)
                else "linear",
                current_fraction,
                torch.tensor(maximum, dtype=torch.float64),
                module.weight.double(),
                module.bias.double(),
                name != "classifier.6",
            )

        parameter["result_shift"] = parameter["right_shift"]
        parameter["calibration_range"] = ranges[name]
        parameters.append(parameter)
        current_fraction = parameter["output_fraction"]
    return {
        "format_version": 1,
        "model": "VGG16",
        "input_fraction": input_fraction,
        "layers": parameters,
        "preprocessing": preprocessing,
    }

@torch.inference_mode()
def prepare_parameters(model, quantization):
    if (
        quantization["model"] != "VGG16"
        or quantization["format_version"] != 1
        or [p["name"] for p in quantization["layers"]] != list(NAMES)
    ):
        raise ValueError("VGG16 量化参数与模型不匹配")

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

        module = model.get_submodule(name)
        if isinstance(module, torch.nn.MaxPool2d):
            if (parameter["kind"] != "maxpool2d" or current != output_fraction
                    or shift != 0 or parameter["relu"]):
                raise ValueError(f"{name}: MAXPOOL 不允许额外量化或激活")
        elif isinstance(module, (torch.nn.Conv2d, torch.nn.Linear)):
            weight_fraction = parameter["weight_fraction"]
            expected_kind = (
                "conv2d" if isinstance(module, torch.nn.Conv2d) else "linear"
            )

            if (type(weight_fraction) is not int
                    or not -16 <= weight_fraction <= 30
                    or parameter["accumulator_fraction"] != current + weight_fraction
                    or shift != current + weight_fraction - output_fraction
                    or parameter["relu"] != (name != "classifier.6")
                    or parameter["kind"] != expected_kind):
                raise ValueError(f"{name}: 仿射层量化合同错误")
            
            if not torch.isfinite(module.weight).all() or not torch.isfinite(module.bias).all():
                raise ValueError(f"{name}: 参数含非有限数值")
            weight = quantize_int16(module.weight, weight_fraction)
            bias_float = round_nearest_away(module.bias.double() * 2.0**parameter["accumulator_fraction"])
            if float(bias_float.abs().max()) >= 2**47:
                raise OverflowError(f"{name}: bias 超过 signed48 安全范围")
            bias = bias_float.to(torch.int64)

            bound = 0
            for start in range(0, weight.shape[0], 64):
                rows = weight[start:start + 64].to(torch.int64).flatten(1)
                row_bounds = (
                    rows.abs().sum(1) * 32768
                    + bias[start:start + 64].abs()
                )
                bound = max(bound, int(row_bounds.max()))
            if bound >= 2**47:
                raise OverflowError(f"{name}: 累加上界超过 signed48 安全范围")
            bounds[name] = {"max_abs_partial_sum_bound": bound, "signed48_safe": True,
                            "float64_integer_exact": bound < 2**53,
                            "bias_integer_max_abs": int(bias.abs().max())}
            cache[name] = weight, bias
        current = output_fraction
    return cache, bounds


def write_json(path, value):
    with Path(path).open("w", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")

def main():
    root = Path(__file__).resolve().parent
    out = root / "reports/VGG"
    config = json.loads((root / "hardware/vgg16_config.json").read_text(encoding="utf-8"))
    preprocessing = config["preprocessing"]
    transform = transforms.Compose([
        transforms.Resize(
            preprocessing["resize_shorter_side"],
            interpolation=transforms.InterpolationMode.BILINEAR,
            antialias=preprocessing["antialias"],
        ),
        transforms.CenterCrop(preprocessing["crop_size"]),
        transforms.ToTensor(),
        transforms.Normalize(mean=preprocessing["mean"], std=preprocessing["std"]),
    ])
    calibration_dataset = torchvision.datasets.ImageFolder(
        root=DATA_DIR,
        transform=transform,
    )

    indices = calibration_indices(calibration_dataset.targets)
    model = load_checkpoint(root / "cnn_scripts/weight/vgg16.pth")
    quantization = calibrate(model, calibration_dataset, indices, preprocessing)
    quantization["calibration"] = {
        "dataset": "Mini-ImageNet",
        "split": "train",
        "seed": SEED,
        "samples_per_class": CALIBRATION_PER_CLASS,
        "samples": [Path(calibration_dataset.samples[index][0]).relative_to(DATA_DIR).as_posix()
                    for index in indices],
    }

    _, bounds = prepare_parameters(model, quantization)
    quantization["accumulator_bounds"] = bounds
    out.mkdir(parents=True, exist_ok=True)
    write_json(out / "quantization.json", quantization)
    print(f"PASS VGG calibration: {len(indices)} training samples; {out / 'quantization.json'}", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
