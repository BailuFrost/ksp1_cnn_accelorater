from pathlib import Path
import random
import time

import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torchvision import datasets, transforms


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT.parent / "data"
CHECKPOINT_PATH = ROOT / "cnn_scripts/weight/tiny_mnist.pth"

TRAINING = {"seed": 114514, "epochs": 5, "batch_size": 64,
            "optimizer": "SGD", "learning_rate": 0.01, "momentum": 0.9,
            "device": "cpu", "threads": 4}
PREPROCESSING = {"operations": ["ToTensor", "Normalize"], "mean": [0.5], "std": [0.5],
                 "pixel_formula": "(uint8 / 255.0 - 0.5) / 0.5",
                 "resize": False, "augmentation": False}

# 训练与推理共用的预处理
transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize(PREPROCESSING["mean"], PREPROCESSING["std"]),
])

# CNN 模型定义
class SimpleCNN(nn.Module):
    def __init__(self):
        super(SimpleCNN, self).__init__()
        # 定义卷积层
        self.conv1 = nn.Conv2d(1, 32, kernel_size=3, stride=1, padding=1)  # 输入1通道，输出32通道
        self.conv2 = nn.Conv2d(32, 64, kernel_size=3, stride=1, padding=1)  # 输入32通道，输出64通道
        # 定义全连接层
        self.fc1 = nn.Linear(64 * 7 * 7, 128)  # 展平后输入到全连接层
        self.fc2 = nn.Linear(128, 10)  # 10 个类别

    def forward(self, x):
        x = F.relu(self.conv1(x))  # 第一层卷积 + ReLU
        x = F.max_pool2d(x, 2)     # 最大池化
        x = F.relu(self.conv2(x))  # 第二层卷积 + ReLU
        x = F.max_pool2d(x, 2)     # 最大池化
        x = x.view(-1, 64 * 7 * 7) # 展平
        x = F.relu(self.fc1(x))    # 全连接层 + ReLU
        x = self.fc2(x)            # 最后一层输出
        return x

def load_checkpoint(path):
    state_dict = torch.load(path, map_location="cpu", weights_only=True)
    model = SimpleCNN()
    model.load_state_dict(state_dict, strict=True)
    return model.eval()


if __name__ == "__main__":
    random.seed(TRAINING["seed"])
    torch.manual_seed(TRAINING["seed"])
    torch.set_num_threads(TRAINING["threads"])
    torch.use_deterministic_algorithms(True)

    # 1. 加载 MNIST 数据集与数据预处理
    data_dir = DATA_DIR

    train_dataset = datasets.MNIST(data_dir, train=True, transform=transform, download=True)
    test_dataset = datasets.MNIST(data_dir, train=False, transform=transform, download=True)

    generator = torch.Generator().manual_seed(TRAINING["seed"])

    train_loader = torch.utils.data.DataLoader(
        train_dataset, batch_size=TRAINING["batch_size"], shuffle=True, generator=generator)
    test_loader = torch.utils.data.DataLoader(
        test_dataset, batch_size=TRAINING["batch_size"], shuffle=False)
    
    print(f"MNIST train={len(train_dataset)} test={len(test_dataset)}; "
          f"CPU threads={torch.get_num_threads()}; seed={TRAINING['seed']}", flush=True)

    # 2. 创建 CNN 模型
    model = SimpleCNN()

    # 3. 定义损失函数和优化器
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.SGD(model.parameters(), lr=TRAINING["learning_rate"],
                          momentum=TRAINING["momentum"])

    # 4. 模型训练
    for epoch in range(TRAINING["epochs"]):
        model.train()
        total_loss = 0.0
        total = 0
        started = time.perf_counter()
        for images, labels in train_loader:
            optimizer.zero_grad()
            loss = criterion(model(images), labels)
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * labels.size(0)
            total += labels.size(0)
        record = {"epoch": epoch + 1, "samples": total, "mean_loss": total_loss / total,
                  "seconds": time.perf_counter() - started}
        print(f"Epoch [{epoch + 1}/{TRAINING['epochs']}], Loss: {record['mean_loss']:.6f}, "
              f"seconds: {record['seconds']:.1f}", flush=True)

    # 5. 模型测试
    model.eval()
    total_loss = 0.0
    total = correct = 0
    logits = []
    with torch.inference_mode():
        for images, labels in test_loader:
            outputs = model(images)
            total_loss += F.cross_entropy(outputs, labels, reduction="sum").item()
            correct += (outputs.argmax(1) == labels).sum().item()
            total += labels.size(0)
            logits.append(outputs)
    logits = torch.cat(logits)
    evaluation = {"split": "MNIST test", "samples": total, "correct": correct,
                  "accuracy": correct / total, "mean_loss": total_loss / total}
    print(f"Test Accuracy: {100 * evaluation['accuracy']:.2f}%", flush=True)

    # 6. 保存模型权重和偏置
    with CHECKPOINT_PATH.open("xb") as stream:
        torch.save(model.state_dict(), stream)
