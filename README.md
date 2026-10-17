# XC7Z020 CNN 加速器

面向 Zynq-7020（`xc7z020clg484-2`）的 INT16 CNN 推理加速器，使用 Verilog 实现计算与控制逻辑，通过 PC-JTAG 装载模型、启动推理并回读结果。使用自行编写的微型网络 TinyCNN 进行上板部署。

## 加速器架构

- **计算阵列**：固定 8 个 CU，共 144 个 DSP；3×3 卷积并行处理 8 个输出通道，1×1／全连接旁路并行度为 72。特征和权重使用 signed INT16，部分和采用 48 位累加。
- **数据通路**：特征缓存、权重缓存、计算阵列、部分和与结果缓存；特征按 HWC 排列，通道补齐到 4，输入通道按 512 分块。
- **控制与搬运**：指令分发器协调特征、权重、计算和输出控制器；AXI DataMover 经 HP0／HP1／HP2 分别读取特征、读取权重和写回结果，CSR 提供启动、状态和性能计数。
- **支持算子**：3×3、2×2、1×1 卷积、全连接、ReLU，以及 2×2／stride 2／无补零最大池化；池化要求输入高宽为偶数。

TinyCNN 映射为 `Conv(1→32) → MaxPool → Conv(32→64) → MaxPool → FC(3136→128) → FC(128→10)`，输入为 28×28 灰度图。硬件运行于 **100 MHz**；已有实现记录的 Setup WNS 为 **+0.084 ns**、Hold WHS 为 **+0.050 ns**。

## 目录

| 目录 | 内容 |
| --- | --- |
| `rtl/` | 计算、缓存、指令控制及板级接口 RTL |
| `tb/` | 模块与系统测试平台、固定测试向量 |
| `cnn_scripts/` | TinyCNN 训练、量化、编译、输入生成和 JTAG 部署脚本 |
| `hardware/` | 硬件配置、交付清单，以及配套 bitstream／XSA／PS 初始化文件 |
| `reports/` | 保留的板端验证记录与后续运行输出 |

## 环境配置

使用 Windows／PowerShell、Vivado **2024.2**、Vitis／XSDB **2024.2**，并安装板卡 JTAG 驱动。上板时需使用与 `hardware/system/` 中 PS／DDR 配置匹配的开发板，设置为 JTAG 启动并连接电源和下载线。

 Python 环境为 Python **3.12.15**、PyTorch **2.14.1+cpu**、torchvision **0.29.1+cpu**、NumPy **2.5.2**、Pillow **12.3.0**，不需要 GPU：

```powershell
conda create -n cnn-fpga python=3.12 -y
conda activate cnn-fpga
python -m pip install torch==2.14.1 torchvision==0.29.1 --index-url https://download.pytorch.org/whl/cpu
python -m pip install numpy==2.5.2 Pillow==12.3.0
```

以下命令均在本项目根目录执行。`--xsdb` 请替换为本机 Vitis 的实际路径；不要使用 Python `-O`／`-OO`，脚本中的断言用于校验部署文件。

## 复现命令

### 1. 使用已有模型做离线部署检查

已有 `cnn_scripts/generated_tiny/`、`cnn_scripts/inputs/test_02778/` 和 `hardware/system/` 时，可直接执行，无需重新训练或下载 MNIST：

```powershell
$runId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
python -B cnn_scripts/scripts/jtag/infer_tiny.py "reports/tiny/prepare_$runId" --input-dir cnn_scripts/inputs/test_02778 --prepare-only
```

该命令核对模型、输入、黄金输出及硬件文件的匹配关系，并准备部署载荷，不连接板卡。权重、bitstream、XSA、初始化文件及哈希清单须配套保留。

### 2. 在板上执行一次推理

```powershell
$runId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
python -B cnn_scripts/scripts/jtag/infer_tiny.py "reports/tiny/board_run_$runId" --input-dir cnn_scripts/inputs/test_02778 --xsdb 'E:/Vitis/2024.2/bin/xsdb.bat'
```

脚本下载硬件、初始化 PS／DDR、写入指令和数据、启动推理并比对回读结果。运行目录中的 `summary.json` 保存预测类别、周期数及数值差异，`xsdb.log` 保存部署日志。

### 3. 按需重新生成模型或输入

日常复现可跳过本节。重新训练、校准或换图时，先准备 MNIST；默认数据位置是项目根目录的上一级 `data/MNIST/`：

```powershell
python -c "from torchvision.datasets import MNIST; MNIST('../data', train=True, download=True); MNIST('../data', train=False, download=True)"
```

已有输出受到防覆盖保护。重训练前先备份并迁走 `cnn_scripts/weight/tiny_mnist.pth`；重新量化或编译前，为 `reference.py` 的 `OUTPUT_DIR`、`cnn_compiler.py` 的 `DEFAULT_OUTPUT` 指定新目录，并保持编译器的 `REFERENCE` 与输入脚本的 `MODEL_DIR` 指向对应产物。仅在需要更新相应产物时按顺序运行：

```powershell
# 重新训练时执行；复用已有权重则跳过。
python -B cnn_scripts/cnn_model_tiny.py

# 权重改变后重新量化，再编译模型。
python -B cnn_scripts/reference.py
python -B cnn_scripts/scripts/cnn_compiler.py

# 换图时修改 feature_input.py 的 MNIST_INDEX（0～9999），输出目录须尚不存在。
python -B cnn_scripts/scripts/feature_input.py
```

当前 `MNIST_INDEX=2778` 的输入已提供，直接重复生成会拒绝覆盖。使用新的模型包或样本时，在部署命令中通过 `--model-dir`、`--input-dir` 指定新目录。

当前精简目录提供 RTL、测试向量和已导出的硬件包；Vivado 完整工程及原构建脚本未随附，上述流程复现的是现有硬件包的部署与推理。
