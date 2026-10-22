"""检查 VGG 预处理、输入量化和文件导出，无需数据集或 checkpoint。"""
import io
import json
from pathlib import Path
import sys
import struct
import tempfile
from unittest.mock import patch

import torch
from PIL import Image, UnidentifiedImageError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from feature_input import batch_layout, generate_payload, prepare, prepare_batch, prepare_image


def check_payload(preprocessing):
    quant = {"model": "VGG16", "format_version": 1, "input_fraction": 0,
             "preprocessing": preprocessing}
    batch = torch.zeros(1, 3, 224, 224)
    grid = (torch.arange(49).reshape(7, 7) + 1).repeat_interleave(32, 0).repeat_interleave(32, 1)
    batch[0, 0], batch[0, 1] = grid, grid + 50
    batch[0, 2, 0, :4] = torch.tensor([-0.5, 0.5, -40000, 40000])
    with patch("torch.load", side_effect=AssertionError("输入生成不应加载 checkpoint")):
        raw_input = generate_payload(batch, quant)
    assert len(raw_input) == 401408
    pixels = list(struct.iter_unpack("<4h", raw_input))
    assert pixels[0] == (1, 51, -1, 0) and pixels[1] == (1, 51, 1, 0)
    assert pixels[2] == (1, 51, -32768, 0) and pixels[3] == (1, 51, 32767, 0)
    assert pixels[32] == (2, 52, 0, 0) and pixels[32 * 224] == (8, 58, 0, 0)
    assert all(pixel[3] == 0 for pixel in pixels)

    with tempfile.TemporaryDirectory(prefix=".vgg_input_check_", dir=ROOT) as temporary:
        directory = Path(temporary).resolve()
        assert directory.parent == ROOT.resolve()
        bundle = directory / "model"
        bundle.mkdir()
        (bundle / "quantization.json").write_text(json.dumps(quant), encoding="utf-8")
        photo, output = directory / "photo.png", directory / "sample"
        Image.new("RGB", (400, 200), (255, 128, 0)).save(photo)
        with patch("torch.load", side_effect=AssertionError("输入生成不应加载 checkpoint")):
            record = prepare(photo, output, bundle)
        assert record == json.loads((output / "sample.json").read_text(encoding="utf-8"))
        assert "sha256" not in json.dumps(record)
        assert record["files"] == {"input.bin": {"bytes": 401408}}
        assert not {"checkpoint", "int16_logits", "float_prediction", "int16_prediction"} & record.keys()
        assert {file.name for file in output.iterdir()} == {"sample.png", "input.bin", "sample.json"}
        assert struct.unpack("<4h", (output / "input.bin").read_bytes()[:8]) == (2, 0, -2, 0)
        with Image.open(output / "sample.png") as image:
            assert image.size == (400, 200) and image.getpixel((0, 0)) == (255, 128, 0)
        try:
            prepare(directory / "missing.png", output, directory / "missing_model")
        except FileExistsError:
            pass
        else:
            raise AssertionError("必须在读取输入前拒绝覆盖已有目录")
        for invalid in ({**quant, "model": "SimpleCNN"}, {**quant, "format_version": 2}, []):
            (bundle / "quantization.json").write_text(json.dumps(invalid), encoding="utf-8")
            try:
                prepare(directory / "missing.png", directory / "invalid_sample", bundle)
            except ValueError:
                pass
            else:
                raise AssertionError("必须拒绝错误模型或量化格式")
            assert not (directory / "invalid_sample").exists()

    for fraction in (-17, 31, True, 1.5):
        try:
            generate_payload(batch, {**quant, "input_fraction": fraction})
        except ValueError:
            pass
        else:
            raise AssertionError("必须拒绝非法输入小数位数")
    invalid_values = batch.clone()
    invalid_values[0, 0, 0, 0] = float("nan")
    for invalid_batch in (batch[:, :, :112, :112], invalid_values):
        try:
            generate_payload(invalid_batch, quant)
        except ValueError:
            pass
        else:
            raise AssertionError("必须拒绝非法输入形状或非有限数值")


def check_batch(preprocessing):
    config = json.loads((ROOT / "hardware/vgg16_config.json").read_text(encoding="utf-8"))
    assert batch_layout(config, 50)["bytes"] == 20070400
    for count in (0, -1, True, 1000):
        try:
            batch_layout(config, count)
        except ValueError:
            pass
        else:
            raise AssertionError("必须拒绝空批次、非法数量及 DDR 越界")
    with tempfile.TemporaryDirectory(prefix=".vgg_batch_check_", dir=ROOT) as temporary:
        directory = Path(temporary)
        assert directory.resolve().parent == ROOT.resolve()
        photos, model = directory / "photo", directory / "model"
        photos.mkdir()
        model.mkdir()
        quant = {"model": "VGG16", "format_version": 1, "input_fraction": 0,
                 "preprocessing": preprocessing}
        (model / "quantization.json").write_text(json.dumps(quant), encoding="utf-8")
        (photos / "ignored.txt").write_text("not a photo")
        try:
            prepare_batch(photos, directory / "empty", model)
        except ValueError:
            assert not (directory / "empty").exists()
        else:
            raise AssertionError("空图片目录不能生成批次")
        for name, color in (("photo10.jpg", "red"), ("photo2.JPEG", "green"), ("photo1.jpg", "blue")):
            Image.new("RGB", (300, 240), color).save(photos / name)
        output = directory / "batch"
        with patch("torch.load", side_effect=AssertionError("批量输入不应加载 checkpoint")):
            record = prepare_batch(photos, output, model)
        assert record == json.loads((output / "batch.json").read_text(encoding="utf-8"))
        assert [Path(s["source_image"]).name for s in record["samples"]] == ["photo1.jpg", "photo2.JPEG", "photo10.jpg"]
        raw = (output / "input_bin.bin").read_bytes()
        assert len(raw) == 3 * 401408
        for index, sample in enumerate(record["samples"]):
            assert sample["index"] == index and sample["offset"] == index * 401408
            assert sample["ddr_address"] == 0x06000000 + index * 401408
            _, batch = prepare_image(output / sample["image"], preprocessing)
            assert raw[sample["offset"]:sample["offset"] + 401408] == generate_payload(batch, quant)
        assert not list(output.rglob("input.bin"))
        try:
            prepare_batch(photos, output, model)
        except FileExistsError:
            pass
        else:
            raise AssertionError("批量输入必须拒绝覆盖已有目录")


def main():
    torch.set_num_threads(4)
    preprocessing = json.loads((ROOT / "hardware/vgg16_config.json").read_text(encoding="utf-8"))["preprocessing"]

    def prepare(image, **save_options):
        with io.BytesIO() as stream:
            image.save(stream, format="PNG", **save_options)
            stream.seek(0)
            return prepare_image(stream, preprocessing)

    image, batch = prepare(Image.new("RGB", (400, 200), (255, 128, 0)))
    assert image.mode == "RGB" and image.size == (400, 200)
    assert image.getpixel((0, 0)) == (255, 128, 0)
    assert batch.shape == (1, 3, 224, 224) and batch.dtype == torch.float32
    expected = (torch.tensor([1., 128 / 255, 0.]) - torch.tensor(preprocessing["mean"])) / torch.tensor(preprocessing["std"])
    torch.testing.assert_close(batch, expected.view(1, 3, 1, 1).expand_as(batch))

    pattern = Image.new("RGB", (512, 256))
    pattern.paste((255, 255, 255), (144, 16, 368, 240))
    _, batch = prepare(pattern)
    white = (1 - torch.tensor(preprocessing["mean"])) / torch.tensor(preprocessing["std"])
    torch.testing.assert_close(batch, white.view(1, 3, 1, 1).expand_as(batch))

    for mode in ("L", "RGBA"):
        image, batch = prepare(Image.new(mode, (80, 40)))
        assert image.mode == "RGB" and batch.shape == (1, 3, 224, 224)

    exif = Image.Exif()
    exif[274] = 6
    image, _ = prepare(Image.new("RGB", (80, 40)), exif=exif)
    assert image.size == (40, 80) and image.getexif().get(274) is None

    try:
        prepare_image(io.BytesIO(b"invalid image"), preprocessing)
    except UnidentifiedImageError:
        pass
    else:
        raise AssertionError("损坏的图片必须报错")

    for invalid in ({**preprocessing, "crop_size": [112, 112]},
                    {**preprocessing, "mean": [float("nan"), 0., 0.]}):
        with io.BytesIO() as stream:
            Image.new("RGB", (256, 256)).save(stream, format="PNG")
            stream.seek(0)
            try:
                prepare_image(stream, invalid)
            except ValueError:
                pass
            else:
                raise AssertionError("非法形状或非有限数值必须报错")
    check_payload(preprocessing)
    check_batch(preprocessing)
    print("PASS VGG input: single/batch; natural order; concatenated bytes/addresses; DDR bounds; preprocessing/quantization; no-overwrite; no checkpoint/inference/SHA256")


if __name__ == "__main__":
    main()
