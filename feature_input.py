import json
import re
from pathlib import Path

import torch
from PIL import Image, ImageOps
from torchvision import transforms

from cnn_scripts.int16_golden import quantize_int16
from cnn_scripts.pool_reference import physical

ROOT = Path(__file__).resolve().parent
IMAGE_PATH = ROOT / "photo"  # 目录批量处理 JPG/JPEG；也可指定单张图片。
OUTPUT_DIR = ROOT / "cnn_scripts/inputs/vgg_batch_001"  # 必须是尚不存在的新目录。
MODEL_DIR = ROOT / "cnn_scripts/weight/vgg16"


def load_context(model_dir):
    quant_path = model_dir / "quantization.json"
    quant = json.loads(quant_path.read_text(encoding="utf-8"))
    if not isinstance(quant, dict) or quant.get("model") != "VGG16" or quant.get("format_version") != 1:
        raise ValueError("量化参数必须为 VGG16 format_version=1")
    return quant


def prepare_image(image_path, preprocessing):
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
    with Image.open(image_path) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
    batch = transform(image).unsqueeze(0)
    if batch.shape != (1, 3, 224, 224) or not torch.isfinite(batch).all():
        raise ValueError("VGG16 输入必须是 [1, 3, 224, 224] 且不含 NaN 或 Inf")
    return image, batch


@torch.inference_mode()
def generate_payload(batch, quant):
    if batch.shape != (1, 3, 224, 224) or not torch.isfinite(batch).all():
        raise ValueError("VGG16 输入必须是 [1, 3, 224, 224] 且不含 NaN 或 Inf")
    fraction = quant["input_fraction"]
    if type(fraction) is not int or not -16 <= fraction <= 30:
        raise ValueError("非法输入小数位数")
    quantized_input = quantize_int16(batch[0], fraction)
    raw_input = physical(quantized_input.permute(1, 2, 0).reshape(-1).tolist(), 3)
    if len(raw_input) != 401408:
        raise ValueError("VGG16 物理输入长度错误")
    return raw_input


def save_sample(output, image, raw_input, record):
    output.mkdir(parents=True, exist_ok=False)
    image_path = output / "sample.png"
    image.save(image_path)
    (output / "input.bin").write_bytes(raw_input)
    record["image"] = str(image_path.resolve())
    record["files"] = {"input.bin": {"bytes": (output / "input.bin").stat().st_size}}
    (output / "sample.json").write_text(
        json.dumps(record, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    return record


def prepare(image_path, output, model_dir=MODEL_DIR):
    image_path, output, model_dir = Path(image_path), Path(output), Path(model_dir)
    if output.exists():
        raise FileExistsError(f"拒绝覆盖已有输入：{output}")
    quant = load_context(model_dir)
    image, batch = prepare_image(image_path, quant["preprocessing"])
    raw_input = generate_payload(batch, quant)
    record = {
        "model": "VGG16",
        "source_image": str(image_path.resolve()),
        "model_dir": str(model_dir.resolve()),
        "preprocessing": quant["preprocessing"],
        "input_fraction": quant["input_fraction"],
    }
    return save_sample(output, image, raw_input, record)


def batch_layout(config, count):
    if type(count) is not int or count <= 0:
        raise ValueError("批量输入必须包含至少一张图片")
    size = config["physical_format"]["input_bytes"]
    base = int(config["batch_input"]["ddr_address"], 0)
    limit = int(config["batch_input"]["limit_address"], 0)
    maximum = max(h * w * ((c + 3) // 4 * 4) * 2
                  for h, w, c in (layer["output_hwc"] for layer in config["layers"]))
    if (size != 401408 or base % 64 or limit % 64
            or not 0x05000000 + maximum <= base < limit <= 0x0B000000
            or base + count * size > limit):
        raise ValueError("批量输入越界或与 VGG16 中间特征工作区重叠")
    return {"ddr_address": base, "limit_address": limit,
            "input_bytes": size, "count": count, "bytes": count * size}


@torch.inference_mode()
def prepare_batch(image_dir, output, model_dir=MODEL_DIR):
    image_dir, output, model_dir = Path(image_dir), Path(output), Path(model_dir)
    if output.exists():
        raise FileExistsError(f"拒绝覆盖已有输入：{output}")
    files = sorted(
        (p for p in image_dir.iterdir() if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg")),
        key=lambda p: ([int(s) if s.isdigit() else s.casefold()
                        for s in re.split(r"(\d+)", p.name)], p.name),
    )
    config = json.loads((ROOT / "hardware/vgg16_config.json").read_text(encoding="utf-8"))
    layout = batch_layout(config, len(files))
    quant = load_context(model_dir)
    if quant["preprocessing"] != config["preprocessing"]:
        raise ValueError("量化预处理与硬件模型配置不一致")
    output.mkdir(parents=True, exist_ok=False)
    (output / "images").mkdir()
    samples = []
    with (output / "input_bin.bin").open("xb") as stream:
        for index, path in enumerate(files):
            image, batch = prepare_image(path, quant["preprocessing"])
            raw = generate_payload(batch, quant)
            relative = f"images/{index + 1:04d}.png"
            image.save(output / relative)
            stream.write(raw)
            samples.append({"index": index, "source_image": str(path.resolve()),
                            "image": relative, "offset": index * layout["input_bytes"],
                            "ddr_address": layout["ddr_address"] + index * layout["input_bytes"]})
    record = {"model": "VGG16", "format_version": 1, "layout": layout,
              "model_dir": str(model_dir.resolve()), "preprocessing": quant["preprocessing"],
              "input_fraction": quant["input_fraction"], "samples": samples,
              "files": {"input_bin.bin": {"bytes": layout["bytes"]}}}
    (output / "batch.json").write_text(
        json.dumps(record, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return record


def main():
    torch.set_num_threads(4)
    prepare_input = prepare_batch if IMAGE_PATH.is_dir() else prepare
    print(json.dumps(prepare_input(IMAGE_PATH, OUTPUT_DIR, MODEL_DIR), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

