import torch
import torch.nn as nn

class VGG16(nn.Module):
    def __init__(self, num_classes=1000):
        super(VGG16, self).__init__()
        self.features = nn.Sequential(
            # Block 1：2层卷积与1层最大池化
            # 输入：224*224*3，输出：224*224*64
            nn.Conv2d(3, 64, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：224*224*64，输出：224*224*64
            nn.Conv2d(64, 64, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：224*224*64，输出：112*112*64
            nn.MaxPool2d(kernel_size=2, stride=2),

            # Block 2：2层卷积与1层最大池化
            # 输入：112*112*64，输出：112*112*128
            nn.Conv2d(64, 128, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：112*112*128，输出：112*112*128
            nn.Conv2d(128, 128, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：112*112*128，输出：56*56*128
            nn.MaxPool2d(kernel_size=2, stride=2),

            # Block 3：3层卷积与1层最大池化
            # 输入：56*56*128，输出：56*56*256
            nn.Conv2d(128, 256, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：56*56*256，输出：56*56*256
            nn.Conv2d(256, 256, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：56*56*256，输出：56*56*256
            nn.Conv2d(256, 256, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：56*56*256，输出：28*28*256
            nn.MaxPool2d(kernel_size=2, stride=2),

            # Block 4：3层卷积与1层最大池化
            # 输入：28*28*256，输出：28*28*512
            nn.Conv2d(256, 512, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：28*28*512，输出：28*28*512
            nn.Conv2d(512, 512, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：28*28*512，输出：28*28*512
            nn.Conv2d(512, 512, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：28*28*512，输出：14*14*512
            nn.MaxPool2d(kernel_size=2, stride=2),

            # Block 5：3层卷积与1层最大池化
            # 输入：14*14*512，输出：14*14*512
            nn.Conv2d(512, 512, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：14*14*512，输出：14*14*512
            nn.Conv2d(512, 512, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：14*14*512，输出：14*14*512
            nn.Conv2d(512, 512, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            # 输入：14*14*512，输出：7*7*512
            nn.MaxPool2d(kernel_size=2, stride=2)
        )
        # 全连接层部分
        self.classifier = nn.Sequential(
            nn.Linear(512 * 7 * 7, 4096),
            nn.ReLU(inplace=True),
            nn.Dropout(),
            nn.Linear(4096, 4096),
            nn.ReLU(inplace=True),
            nn.Dropout(),
            nn.Linear(4096, num_classes),
        )

    # 前向传播函数
    def forward(self, x):
        x = self.features(x)
        x = torch.flatten(x, 1)
        x = self.classifier(x)
        return x