from __future__ import annotations

import argparse
import gc
import hashlib
import json
import math
import urllib.request
import zlib
from pathlib import Path
from typing import Any

import numpy as np
import torch
import torch.nn.functional as functional
from PIL import Image
from torch import Tensor, nn
from torchvision import transforms
from torchvision.models import (
    ResNet50_Weights,
    ResNet152_Weights,
    VGG16_Weights,
    resnet50,
    resnet152,
    vgg16,
)


IMAGE_SOURCES = {
    "samoyed": "https://github.com/pytorch/hub/raw/master/images/dog.jpg",
    "corgi": "https://raw.githubusercontent.com/pytorch/vision/main/gallery/assets/dog1.jpg",
    "astronaut": "https://raw.githubusercontent.com/pytorch/vision/main/gallery/assets/astronaut.jpg",
}

MODEL_SPECS = {
    "vgg16": (vgg16, VGG16_Weights.IMAGENET1K_V1),
    "resnet50": (resnet50, ResNet50_Weights.IMAGENET1K_V1),
    "resnet152": (resnet152, ResNet152_Weights.IMAGENET1K_V1),
}

PREPROCESS = transforms.Compose(
    [
        transforms.ToTensor(),
        transforms.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
    ]
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def round_nearest_away(value: Tensor) -> Tensor:
    """离线量化：绝对值恰为 0.5 时远离 0。"""
    return torch.where(value >= 0, torch.floor(value + 0.5), torch.ceil(value - 0.5))


def quantize_int16(value: Tensor, fraction_bits: int) -> Tensor:
    scaled = round_nearest_away(value.to(torch.float64) * (2.0**fraction_bits))
    return scaled.clamp(-32768, 32767).to(torch.int16)


def arithmetic_round_right_shift(value: Tensor, shift: int) -> Tensor:
    """RTL 合同：正负数统一先加 2^(shift-1)，再算术右移。"""
    if shift < 0:
        raise ValueError("hardware path does not support left shift")
    if shift == 0:
        return value
    return (value + (1 << (shift - 1))) >> shift


def rounded_signed_divide(value: Tensor, divisor: int) -> Tensor:
    if divisor <= 0:
        raise ValueError("divisor must be positive")
    return torch.div(value + divisor // 2, divisor, rounding_mode="floor")


def fraction_bits(value: Tensor) -> int:
    maximum = float(value.detach().abs().max())
    if maximum == 0.0:
        return 15
    return max(-16, min(30, math.floor(math.log2(32767.0 / maximum))))


def crc32_int16(value: Tensor) -> str:
    tensor = value.detach().cpu()
    if tensor.ndim == 3:
        tensor = tensor.permute(1, 2, 0)
    data = tensor.contiguous().numpy().astype("<i2", copy=False).tobytes()
    return f"{zlib.crc32(data) & 0xFFFFFFFF:08x}"


def _shape_for_report(value: Tensor) -> list[int]:
    shape = list(value.shape)
    if value.ndim == 4:
        return [shape[2], shape[3], shape[1]]
    return shape[1:]


def _download(url: str, target: Path, hash_prefix: str | None = None) -> None:
    if target.exists():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".part")
    if hash_prefix:
        torch.hub.download_url_to_file(url, temporary, hash_prefix=hash_prefix, progress=True)
    else:
        urllib.request.urlretrieve(url, temporary)
    temporary.replace(target)


def prepare_assets(project_root: Path) -> dict[str, Any]:
    image_dir = project_root / "model" / "test_images"
    weight_dir = project_root / "model" / "weights"
    image_dir.mkdir(parents=True, exist_ok=True)
    weight_dir.mkdir(parents=True, exist_ok=True)

    image_records = []
    resize = transforms.Resize(256, interpolation=transforms.InterpolationMode.BILINEAR, antialias=True)
    crop = transforms.CenterCrop(224)
    for image_id, url in IMAGE_SOURCES.items():
        source = image_dir / f"{image_id}_source.jpg"
        fixed = image_dir / f"{image_id}_224.bmp"
        _download(url, source)
        if not fixed.exists():
            with Image.open(source) as image:
                crop(resize(image.convert("RGB"))).save(fixed, format="BMP")
        image_records.append(
            {
                "id": image_id,
                "source_url": url,
                "source_sha256": sha256_file(source),
                "bmp_path": fixed.relative_to(project_root).as_posix(),
                "bmp_sha256": sha256_file(fixed),
            }
        )

    weight_records = []
    for model_name, (_, weights) in MODEL_SPECS.items():
        filename = Path(weights.url).name
        target = weight_dir / filename
        hash_prefix = filename.rsplit("-", 1)[-1].split(".", 1)[0]
        _download(weights.url, target, hash_prefix)
        weight_records.append(
            {
                "model": model_name,
                "url": weights.url,
                "path": target.relative_to(project_root).as_posix(),
                "sha256": sha256_file(target),
            }
        )
    return {"images": image_records, "weights": weight_records}


def load_fixed_batch(project_root: Path) -> tuple[Tensor, list[dict[str, Any]]]:
    records = prepare_assets(project_root)["images"]
    tensors = []
    for record in records:
        with Image.open(project_root / record["bmp_path"]) as image:
            tensors.append(PREPROCESS(image.convert("RGB")))
    return torch.stack(tensors), records


def load_model(model_name: str, project_root: Path) -> tuple[nn.Module, Any, Path]:
    constructor, weights = MODEL_SPECS[model_name]
    weight_path = project_root / "model" / "weights" / Path(weights.url).name
    if not weight_path.exists():
        prepare_assets(project_root)
    model = constructor(weights=None)
    state = torch.load(weight_path, map_location="cpu", weights_only=True)
    model.load_state_dict(state)
    del state
    return model.eval(), weights, weight_path


def folded_conv_parameters(conv: nn.Conv2d, batch_norm: nn.BatchNorm2d | None) -> tuple[Tensor, Tensor]:
    weight = conv.weight.detach().to(torch.float64)
    bias = (
        conv.bias.detach().to(torch.float64)
        if conv.bias is not None
        else torch.zeros(conv.out_channels, dtype=torch.float64)
    )
    if batch_norm is None:
        return weight, bias
    scale = batch_norm.weight.detach().to(torch.float64) / torch.sqrt(
        batch_norm.running_var.detach().to(torch.float64) + batch_norm.eps
    )
    weight = weight * scale[:, None, None, None]
    bias = (bias - batch_norm.running_mean.detach().to(torch.float64)) * scale
    bias += batch_norm.bias.detach().to(torch.float64)
    return weight, bias


def make_affine_parameter(
    name: str,
    kind: str,
    input_fraction: int,
    output: Tensor,
    weight: Tensor,
    bias: Tensor,
    relu: bool,
) -> dict[str, Any]:
    weight_fraction = fraction_bits(weight)
    output_fraction = min(fraction_bits(output), input_fraction + weight_fraction)
    accumulator_fraction = input_fraction + weight_fraction
    bias_integer = round_nearest_away(bias * (2.0**accumulator_fraction))
    max_bias_integer = int(bias_integer.abs().max()) if bias_integer.numel() else 0
    if max_bias_integer >= (1 << 47):
        raise OverflowError(f"{name}: bias does not fit signed 48-bit accumulator")
    return {
        "name": name,
        "kind": kind,
        "input_fraction": input_fraction,
        "weight_fraction": weight_fraction,
        "accumulator_fraction": accumulator_fraction,
        "output_fraction": output_fraction,
        "right_shift": accumulator_fraction - output_fraction,
        "relu": relu,
        "weight_max_abs": float(weight.abs().max()),
        "calibration_output_max_abs": float(output.detach().abs().max()),
        "bias_integer_max_abs": max_bias_integer,
    }


def make_add_parameter(name: str, left_fraction: int, right_fraction: int, output: Tensor) -> dict[str, Any]:
    output_fraction = min(fraction_bits(output), left_fraction, right_fraction)
    return {
        "name": name,
        "kind": "add_relu",
        "left_fraction": left_fraction,
        "right_fraction": right_fraction,
        "output_fraction": output_fraction,
        "src0_rshift": left_fraction - output_fraction,
        "src1_rshift": right_fraction - output_fraction,
        "relu": True,
        "calibration_output_max_abs": float(output.detach().abs().max()),
    }


def _float_fused_conv(value: Tensor, conv: nn.Conv2d, batch_norm: nn.BatchNorm2d | None, relu: bool) -> Tensor:
    value = conv(value)
    if batch_norm is not None:
        value = batch_norm(value)
    return functional.relu(value) if relu else value


def calibrate_vgg(model: nn.Module, batch: Tensor) -> tuple[dict[str, dict[str, Any]], Tensor, int]:
    parameters: dict[str, dict[str, Any]] = {}
    current_fraction = fraction_bits(batch)
    value = batch
    index = 0
    while index < len(model.features):
        module = model.features[index]
        if isinstance(module, nn.Conv2d):
            relu = index + 1 < len(model.features) and isinstance(model.features[index + 1], nn.ReLU)
            value = module(value)
            if relu:
                value = model.features[index + 1](value)
            name = f"features.{index}"
            weight, bias = folded_conv_parameters(module, None)
            parameter = make_affine_parameter(name, "conv2d", current_fraction, value, weight, bias, relu)
            parameters[name] = parameter
            current_fraction = parameter["output_fraction"]
            index += 2 if relu else 1
        else:
            value = module(value)
            index += 1

    value = model.avgpool(value)
    value = torch.flatten(value, 1)
    index = 0
    while index < len(model.classifier):
        module = model.classifier[index]
        if isinstance(module, nn.Linear):
            relu = index + 1 < len(model.classifier) and isinstance(model.classifier[index + 1], nn.ReLU)
            value = module(value)
            if relu:
                value = model.classifier[index + 1](value)
            name = f"classifier.{index}"
            weight = module.weight.detach().to(torch.float64)
            bias = module.bias.detach().to(torch.float64)
            parameter = make_affine_parameter(name, "linear", current_fraction, value, weight, bias, relu)
            parameters[name] = parameter
            current_fraction = parameter["output_fraction"]
            index += 2 if relu else 1
        else:
            value = module(value)
            index += 1
    torch.testing.assert_close(value, model(batch), rtol=0, atol=0)
    return parameters, value, fraction_bits(batch)


def calibrate_resnet(model: nn.Module, batch: Tensor) -> tuple[dict[str, dict[str, Any]], Tensor, int]:
    parameters: dict[str, dict[str, Any]] = {}
    input_fraction = fraction_bits(batch)
    current_fraction = input_fraction
    value = _float_fused_conv(batch, model.conv1, model.bn1, True)
    weight, bias = folded_conv_parameters(model.conv1, model.bn1)
    parameter = make_affine_parameter("stem.conv1", "conv2d", current_fraction, value, weight, bias, True)
    parameters["stem.conv1"] = parameter
    current_fraction = parameter["output_fraction"]
    value = model.maxpool(value)

    for layer_index, layer in enumerate((model.layer1, model.layer2, model.layer3, model.layer4), start=1):
        for block_index, block in enumerate(layer):
            prefix = f"layer{layer_index}.{block_index}"
            identity, identity_fraction = value, current_fraction

            branch = _float_fused_conv(value, block.conv1, block.bn1, True)
            weight, bias = folded_conv_parameters(block.conv1, block.bn1)
            p1 = make_affine_parameter(f"{prefix}.conv1", "conv2d", current_fraction, branch, weight, bias, True)
            parameters[p1["name"]] = p1

            branch = _float_fused_conv(branch, block.conv2, block.bn2, True)
            weight, bias = folded_conv_parameters(block.conv2, block.bn2)
            p2 = make_affine_parameter(f"{prefix}.conv2", "conv2d", p1["output_fraction"], branch, weight, bias, True)
            parameters[p2["name"]] = p2

            branch = _float_fused_conv(branch, block.conv3, block.bn3, False)
            weight, bias = folded_conv_parameters(block.conv3, block.bn3)
            p3 = make_affine_parameter(f"{prefix}.conv3", "conv2d", p2["output_fraction"], branch, weight, bias, False)
            parameters[p3["name"]] = p3

            if block.downsample is not None:
                identity = block.downsample(identity)
                conv, batch_norm = block.downsample[0], block.downsample[1]
                weight, bias = folded_conv_parameters(conv, batch_norm)
                down = make_affine_parameter(
                    f"{prefix}.downsample", "conv2d", identity_fraction, identity, weight, bias, False
                )
                parameters[down["name"]] = down
                identity_fraction = down["output_fraction"]

            value = functional.relu(branch + identity)
            add = make_add_parameter(f"{prefix}.add", p3["output_fraction"], identity_fraction, value)
            parameters[add["name"]] = add
            current_fraction = add["output_fraction"]

    value = model.avgpool(value)
    value = torch.flatten(value, 1)
    value = model.fc(value)
    weight = model.fc.weight.detach().to(torch.float64)
    bias = model.fc.bias.detach().to(torch.float64)
    fc = make_affine_parameter("fc", "linear", current_fraction, value, weight, bias, False)
    parameters["fc"] = fc
    torch.testing.assert_close(value, model(batch), rtol=0, atol=0)
    return parameters, value, input_fraction


def _quantized_affine(
    value: Tensor,
    module: nn.Conv2d | nn.Linear,
    parameter: dict[str, Any],
    cache: dict[str, tuple[Tensor, Tensor]],
    batch_norm: nn.BatchNorm2d | None = None,
) -> tuple[Tensor, int]:
    name = parameter["name"]
    if name not in cache:
        if isinstance(module, nn.Conv2d):
            weight, bias = folded_conv_parameters(module, batch_norm)
        else:
            weight = module.weight.detach().to(torch.float64)
            bias = module.bias.detach().to(torch.float64)
        quantized_weight = quantize_int16(weight, parameter["weight_fraction"])
        quantized_bias = round_nearest_away(
            bias * (2.0 ** parameter["accumulator_fraction"])
        ).to(torch.int64)
        cache[name] = quantized_weight, quantized_bias
    quantized_weight, quantized_bias = cache[name]

    if isinstance(module, nn.Conv2d):
        accumulator_float = functional.conv2d(
            value.to(torch.float64),
            quantized_weight.to(torch.float64),
            quantized_bias.to(torch.float64),
            stride=module.stride,
            padding=module.padding,
            dilation=module.dilation,
            groups=module.groups,
        )
    else:
        accumulator_float = functional.linear(
            value.to(torch.float64), quantized_weight.to(torch.float64), quantized_bias.to(torch.float64)
        )
    rounded_accumulator = torch.round(accumulator_float)
    if not torch.equal(accumulator_float, rounded_accumulator):
        raise ArithmeticError(f"{name}: float64 integer accumulator lost exactness")
    accumulator = rounded_accumulator.to(torch.int64)
    if int(accumulator.abs().max()) >= (1 << 47):
        raise OverflowError(f"{name}: accumulator exceeds signed 48-bit range")
    shifted = arithmetic_round_right_shift(accumulator, parameter["right_shift"])
    saturation_count = int(((shifted < -32768) | (shifted > 32767)).sum())
    result = shifted.clamp(-32768, 32767).to(torch.int16)
    if parameter["relu"]:
        result = torch.clamp_min(result, 0)
    return result, saturation_count


def _max_pool_int16(value: Tensor, module: nn.MaxPool2d) -> Tensor:
    return functional.max_pool2d(
        value.to(torch.int32), module.kernel_size, module.stride, module.padding, module.dilation,
        module.ceil_mode, module.return_indices,
    ).to(torch.int16)


def _record(checkpoints: list[list[dict[str, Any]]], name: str, value: Tensor, fraction: int) -> None:
    for image_index in range(value.shape[0]):
        checkpoints[image_index].append(
            {
                "layer": name,
                "shape": _shape_for_report(value),
                "fraction_bits": fraction,
                "crc32": crc32_int16(value[image_index]),
            }
        )


def run_vgg_int16(
    model: nn.Module, batch: Tensor, parameters: dict[str, dict[str, Any]], input_fraction: int,
    cache: dict[str, tuple[Tensor, Tensor]],
) -> tuple[Tensor, int, list[list[dict[str, Any]]], int]:
    value = quantize_int16(batch, input_fraction)
    current_fraction = input_fraction
    checkpoints = [[] for _ in range(batch.shape[0])]
    _record(checkpoints, "input", value, current_fraction)
    saturation_count = 0

    index = 0
    while index < len(model.features):
        module = model.features[index]
        if isinstance(module, nn.Conv2d):
            name = f"features.{index}"
            value, saturated = _quantized_affine(value, module, parameters[name], cache)
            saturation_count += saturated
            current_fraction = parameters[name]["output_fraction"]
            _record(checkpoints, name, value, current_fraction)
            index += 2 if parameters[name]["relu"] else 1
        elif isinstance(module, nn.MaxPool2d):
            value = _max_pool_int16(value, module)
            _record(checkpoints, f"features.{index}", value, current_fraction)
            index += 1
        else:
            value = module(value)
            index += 1

    if tuple(value.shape[-2:]) != tuple(model.avgpool.output_size):
        raise ValueError("fixed 224x224 VGG input must already reach the 7x7 adaptive-pool size")
    _record(checkpoints, "avgpool", value, current_fraction)
    value = torch.flatten(value, 1)

    index = 0
    while index < len(model.classifier):
        module = model.classifier[index]
        if isinstance(module, nn.Linear):
            name = f"classifier.{index}"
            value, saturated = _quantized_affine(value, module, parameters[name], cache)
            saturation_count += saturated
            current_fraction = parameters[name]["output_fraction"]
            _record(checkpoints, name, value, current_fraction)
            index += 2 if parameters[name]["relu"] else 1
        else:
            index += 1
    return value, current_fraction, checkpoints, saturation_count


def run_resnet_int16(
    model: nn.Module, batch: Tensor, parameters: dict[str, dict[str, Any]], input_fraction: int,
    cache: dict[str, tuple[Tensor, Tensor]],
) -> tuple[Tensor, int, list[list[dict[str, Any]]], int]:
    value = quantize_int16(batch, input_fraction)
    current_fraction = input_fraction
    checkpoints = [[] for _ in range(batch.shape[0])]
    _record(checkpoints, "input", value, current_fraction)
    saturation_count = 0

    value, saturated = _quantized_affine(value, model.conv1, parameters["stem.conv1"], cache, model.bn1)
    saturation_count += saturated
    current_fraction = parameters["stem.conv1"]["output_fraction"]
    _record(checkpoints, "stem.conv1", value, current_fraction)
    value = _max_pool_int16(value, model.maxpool)
    _record(checkpoints, "stem.maxpool", value, current_fraction)

    for layer_index, layer in enumerate((model.layer1, model.layer2, model.layer3, model.layer4), start=1):
        for block_index, block in enumerate(layer):
            prefix = f"layer{layer_index}.{block_index}"
            identity, identity_fraction = value, current_fraction

            p1 = parameters[f"{prefix}.conv1"]
            branch, saturated = _quantized_affine(value, block.conv1, p1, cache, block.bn1)
            saturation_count += saturated
            _record(checkpoints, p1["name"], branch, p1["output_fraction"])

            p2 = parameters[f"{prefix}.conv2"]
            branch, saturated = _quantized_affine(branch, block.conv2, p2, cache, block.bn2)
            saturation_count += saturated
            _record(checkpoints, p2["name"], branch, p2["output_fraction"])

            p3 = parameters[f"{prefix}.conv3"]
            branch, saturated = _quantized_affine(branch, block.conv3, p3, cache, block.bn3)
            saturation_count += saturated
            _record(checkpoints, p3["name"], branch, p3["output_fraction"])

            if block.downsample is not None:
                down = parameters[f"{prefix}.downsample"]
                identity, saturated = _quantized_affine(
                    identity, block.downsample[0], down, cache, block.downsample[1]
                )
                saturation_count += saturated
                identity_fraction = down["output_fraction"]
                _record(checkpoints, down["name"], identity, identity_fraction)

            add = parameters[f"{prefix}.add"]
            left = arithmetic_round_right_shift(branch.to(torch.int64), add["src0_rshift"])
            right = arithmetic_round_right_shift(identity.to(torch.int64), add["src1_rshift"])
            summed = left + right
            saturation_count += int(((summed < -32768) | (summed > 32767)).sum())
            value = torch.clamp_min(summed.clamp(-32768, 32767).to(torch.int16), 0)
            current_fraction = add["output_fraction"]
            _record(checkpoints, add["name"], value, current_fraction)

    area = value.shape[-2] * value.shape[-1]
    value = rounded_signed_divide(value.to(torch.int64).sum(dim=(-2, -1)), area).to(torch.int16)
    _record(checkpoints, "global_avg_pool", value, current_fraction)
    value, saturated = _quantized_affine(value, model.fc, parameters["fc"], cache)
    saturation_count += saturated
    current_fraction = parameters["fc"]["output_fraction"]
    _record(checkpoints, "fc", value, current_fraction)
    return value, current_fraction, checkpoints, saturation_count


def top5(logits: Tensor, fraction: int | None, categories: list[str]) -> list[list[dict[str, Any]]]:
    real_logits = logits.to(torch.float64)
    if fraction is not None:
        real_logits = real_logits / (2.0**fraction)
    probabilities = functional.softmax(real_logits, dim=1)
    scores, indices = probabilities.topk(5, dim=1)
    return [
        [
            {"index": int(index), "label": categories[int(index)], "probability": float(score)}
            for score, index in zip(image_scores, image_indices)
        ]
        for image_scores, image_indices in zip(scores, indices)
    ]


def run_model(model_name: str, project_root: Path, report_root: Path, image_records: list[dict[str, Any]]) -> dict[str, Any]:
    model, weights, weight_path = load_model(model_name, project_root)
    batch, _ = load_fixed_batch(project_root)
    categories = list(weights.meta["categories"])
    with torch.inference_mode():
        if model_name == "vgg16":
            parameters, float_logits, input_fraction = calibrate_vgg(model, batch)
            runner = run_vgg_int16
        else:
            parameters, float_logits, input_fraction = calibrate_resnet(model, batch)
            runner = run_resnet_int16

        quantized_cache: dict[str, tuple[Tensor, Tensor]] = {}
        int_logits, output_fraction, checkpoints, saturation_count = runner(
            model, batch, parameters, input_fraction, quantized_cache
        )
        repeat_logits, repeat_fraction, repeat_checkpoints, repeat_saturation = runner(
            model, batch, parameters, input_fraction, quantized_cache
        )
    if output_fraction != repeat_fraction or saturation_count != repeat_saturation:
        raise AssertionError(f"{model_name}: repeated run metadata differs")
    if not torch.equal(int_logits, repeat_logits) or checkpoints != repeat_checkpoints:
        raise AssertionError(f"{model_name}: repeated INT16 run differs")

    float_predictions = top5(float_logits, None, categories)
    int_predictions = top5(int_logits, output_fraction, categories)
    image_results = []
    for index, image_record in enumerate(image_records):
        float_indices = {item["index"] for item in float_predictions[index]}
        int_indices = {item["index"] for item in int_predictions[index]}
        image_results.append(
            {
                **image_record,
                "float_top5": float_predictions[index],
                "int16_top5": int_predictions[index],
                "top1_matches_float": int_predictions[index][0]["index"] == float_predictions[index][0]["index"],
                "top5_overlap": len(float_indices & int_indices),
                "repeat_identical": True,
                "layer_checksums": checkpoints[index],
            }
        )

    quantization_path = report_root / "quantization" / f"{model_name}.json"
    checksum_path = report_root / "checksums" / f"{model_name}.json"
    quantization_path.parent.mkdir(parents=True, exist_ok=True)
    checksum_path.parent.mkdir(parents=True, exist_ok=True)
    quantization_path.write_text(
        json.dumps(
            {
                "model": model_name,
                "weights_url": weights.url,
                "weights_sha256": sha256_file(weight_path),
                "input_fraction": input_fraction,
                "rounding": {
                    "offline_quantization": "nearest, ties away from zero",
                    "rtl_right_shift": "(signed_value + 2^(shift-1)) >>> shift",
                    "gap_divide": "floor((signed_sum + divisor//2) / divisor)",
                },
                "layers": list(parameters.values()),
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    checksum_path.write_text(
        json.dumps(
            {
                "model": model_name,
                "checksum": "CRC32 over little-endian INT16; HWC byte order for feature maps",
                "output_fraction": output_fraction,
                "saturation_count": saturation_count,
                "images": image_results,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    result = {
        "model": model_name,
        "quantization_file": quantization_path.relative_to(project_root).as_posix(),
        "checksum_file": checksum_path.relative_to(project_root).as_posix(),
        "layer_count": len(parameters),
        "saturation_count": saturation_count,
        "repeat_identical": True,
        "top1_matches": sum(item["top1_matches_float"] for item in image_results),
        "minimum_top5_overlap": min(item["top5_overlap"] for item in image_results),
        "predictions": [
            {
                "image": item["id"],
                "float_top1": item["float_top5"][0]["label"],
                "int16_top1": item["int16_top5"][0]["label"],
            }
            for item in image_results
        ],
    }
    del quantized_cache, model, batch, int_logits, repeat_logits
    gc.collect()
    return result


def run_self_check() -> None:
    values = torch.tensor([-3, -2, -1, 0, 1, 2, 3], dtype=torch.int64)
    assert arithmetic_round_right_shift(values, 1).tolist() == [-1, -1, 0, 0, 1, 1, 2]
    assert rounded_signed_divide(values, 2).tolist() == [-1, -1, 0, 0, 1, 1, 2]
    assert quantize_int16(torch.tensor([-1.5, -0.5, 0.5, 1.5]), 0).tolist() == [-2, -1, 1, 2]
    sample = torch.tensor([[[1, -2], [3, -4]]], dtype=torch.int16)
    assert crc32_int16(sample) == crc32_int16(sample.clone())


def main() -> None:
    parser = argparse.ArgumentParser(description="Build A2 INT16 golden-model artifacts")
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--models", nargs="+", choices=tuple(MODEL_SPECS), default=list(MODEL_SPECS))
    parser.add_argument("--download-only", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    run_self_check()
    if args.check:
        print("A2 INT16 unit self-check: PASS")
        return

    project_root = args.project_root.resolve()
    assets = prepare_assets(project_root)
    if args.download_only:
        print(json.dumps(assets, ensure_ascii=False, indent=2))
        return

    batch, image_records = load_fixed_batch(project_root)
    del batch
    report_root = project_root / "reports" / "a2"
    results = [run_model(name, project_root, report_root, image_records) for name in args.models]
    summary = {
        "status": "PASS",
        "torch": torch.__version__,
        "torchvision_models": list(args.models),
        "preprocess": "RGB -> shorter side 256 bilinear -> center crop 224 -> BMP -> ImageNet mean/std",
        "images": image_records,
        "models": results,
    }
    report_root.mkdir(parents=True, exist_ok=True)
    summary_path = report_root / "a2_summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"A2 INT16 golden model: PASS\n{summary_path}")


if __name__ == "__main__":
    main()
