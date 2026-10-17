import json
from pathlib import Path
import sys

import torch
from torchvision.datasets import MNIST

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from cnn_model_tiny import CHECKPOINT_PATH, DATA_DIR, load_checkpoint, transform
from int16_golden import quantize_int16
from reference import physical_bytes, run_tiny_int16, sha256

MNIST_INDEX = 2778 # MNIST 测试集编号，范围 0～9999
OUTPUT_DIR = ROOT / f"inputs/test_{MNIST_INDEX:05d}"  # 必须是尚不存在的新目录。
MODEL_DIR = ROOT / "generated_tiny"  # cnn_compiler.py 生成的模型包。


def prepare(sample_index, output, model_dir):
    if output.exists():
        raise FileExistsError(f"拒绝覆盖已有输入：{output}")
    checkpoint = CHECKPOINT_PATH
    quant_path = model_dir / "quantization.json"
    quant = json.loads(quant_path.read_text(encoding="utf-8"))
    manifest = json.loads((model_dir / "deployment_manifest.json").read_text(encoding="utf-8"))
    checkpoint_hash, quantization_hash = sha256(checkpoint), sha256(quant_path)
    if manifest["checkpoint_sha256"] != checkpoint_hash or manifest["quantization_sha256"] != quantization_hash:
        raise ValueError("当前权重或量化参数与编译包不匹配，请重新编译")
    dataset = MNIST(DATA_DIR, train=False, download=False)
    if type(sample_index) is not int or not 0 <= sample_index < len(dataset):
        raise ValueError(f"MNIST 测试编号必须在 0～{len(dataset) - 1} 范围内")
    image, label = dataset[sample_index]  # 原始灰度 PIL 图，预处理只执行一次。
    if image.mode != "L" or image.size != (28, 28):
        raise ValueError("MNIST 图片格式必须为 28×28 灰度图")
    batch = transform(image).unsqueeze(0)
    model = load_checkpoint(checkpoint)
    outputs, _ = run_tiny_int16(model, batch, quant)
    raw_input = physical_bytes(quantize_int16(batch[0], quant["input_fraction"]))
    expected = physical_bytes(outputs["fc2"][0])
    if len(raw_input) != 6272 or len(expected) != 24:
        raise ValueError("物理输入／输出长度错误")
    output.mkdir(parents=True, exist_ok=False)
    image_path = output / "digit.png"
    image.save(image_path)
    (output / "input.bin").write_bytes(raw_input)
    (output / "expected.bin").write_bytes(expected)
    with torch.inference_mode():
        float_prediction = int(model(batch).argmax(1)[0])
    record = {"split": "MNIST test", "index": sample_index, "label": int(label),
              "image": str(image_path.resolve()), "checkpoint_sha256": checkpoint_hash,
              "quantization_sha256": quantization_hash,
              "int16_logits": outputs["fc2"][0].tolist(), "float_prediction": float_prediction,
              "int16_prediction": int(outputs["fc2"][0].argmax()),
              "output_fraction": quant["layers"][-1]["output_fraction"],
              "files": {name: {"bytes": (output / name).stat().st_size, "sha256": sha256(output / name)}
                        for name in ("input.bin", "expected.bin")}}
    (output / "sample.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return record


def main():
    torch.set_num_threads(4)
    print(json.dumps(prepare(MNIST_INDEX, OUTPUT_DIR, MODEL_DIR), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
