from pathlib import Path
import torch
from torchvision.models import VGG16_Weights

path = Path(
    "cnn_scripts/weight/vgg16_imagenet1k_v1.pth"
)
path.parent.mkdir(parents=True, exist_ok=True)

state_dict = VGG16_Weights.IMAGENET1K_V1.get_state_dict(
    progress=True,
    check_hash=True,
)

# 使用 xb，避免覆盖已经保存的文件。
with path.open("xb") as f:
    torch.save(state_dict, f)

print(f"权重已保存：{path}")