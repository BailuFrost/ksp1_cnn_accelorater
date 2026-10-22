# XC7Z020 CNN 加速器

面向 Zynq-7020（`xc7z020clg484-2`）的 INT16 CNN 推理加速器，使用 Verilog 实现计算与控制逻辑，通过 PC-JTAG 装载模型、启动推理并回读结果。当前已完成 **VGG16 部署及 50 张 JPG 图像连续推理的上板验证**：一次初始化并下载指令、权重和全部输入，随后按 batch=1 顺序执行 50 次推理。

## 加速器架构

- **计算阵列**：固定 8 个 CU，共 144 个 DSP；3×3 卷积并行处理 8 个输出通道，1×1／全连接旁路并行度为 72。特征和权重使用 signed INT16，部分和采用 48 位累加。
- **数据通路**：特征缓存、权重缓存、计算阵列、部分和与结果缓存；特征按 HWC 排列，通道补齐到 4，输入通道按 512 分块。
- **控制与搬运**：指令分发器协调特征、权重、计算和输出控制器；AXI DataMover 经 HP0／HP1／HP2 分别读取特征、读取权重和写回结果，CSR 提供启动、状态和性能计数。
- **支持算子**：3×3、2×2、1×1 卷积、全连接、ReLU，以及 2×2／stride 2／无补零最大池化；池化要求输入高宽为偶数。

VGG16 映射为 13 个卷积层、5 个池化层和 3 个全连接层，共 21 层执行指令。网络定义见 [vgg16_model.py](vgg16_model.py)，部署配置见 [vgg16_config.json](hardware/vgg16_config.json)。硬件运行于 **100 MHz**；已有实现记录的 Setup WNS 为 **+0.084 ns**、Hold WHS 为 **+0.050 ns**。

## 目录

| 目录 | 内容 |
| --- | --- |
| `rtl/` | 计算、缓存、指令控制及板级接口 RTL |
| `tb/` | 模块与系统测试平台、固定测试向量 |
| `vgg_reference.py`、`vgg_compiler.py`、`model_packer.py` | VGG16 校准、编译和模型打包 |
| `feature_input.py`、`photo/` | 单图／批量输入生成入口与原始 JPG |
| `cnn_scripts/weight/vgg16.pth`、`cnn_scripts/weight/vgg16/` | checkpoint、量化参数、指令和权重包 |
| `cnn_scripts/inputs/vgg_batch_001/` | 已生成的 50 张合并输入、索引清单及 PNG 图片 |
| `cnn_scripts/scripts/jtag/infer_vgg.py`、`cnn_scripts/scripts/jtag/infer_vgg.tcl` | VGG16 单图／批量部署入口 |
| `hardware/system/` | 配套 bitstream、XSA、PS 初始化文件、DCP 和实现报告 |
| `reports/VGG/board_run_001/` | 已完成的 50 张板测记录、日志及逐图结果 |
| `reports/VGG/board_run_001_analysis/` | 数据完整性核查、性能统计和 FP32 对照 |

## 环境配置

使用 Windows／PowerShell、Vivado **2024.2**、Vitis／XSDB **2024.2**，并安装板卡 JTAG 驱动。上板时需使用与 `hardware/system/` 中 PS／DDR 配置匹配的开发板，设置为 JTAG 启动并连接电源和下载线。

已有环境记录见 [environment.json](cnn_scripts/environment.json)：Python **3.12.15**、PyTorch **2.14.1+cpu**、torchvision **0.29.1+cpu**、NumPy **2.5.2**、Pillow **12.3.0**，不需要 GPU：

```powershell
conda create -n cnn-fpga python=3.12 -y
conda activate cnn-fpga
python -m pip install torch==2.14.1 torchvision==0.29.1 --index-url https://download.pytorch.org/whl/cpu
python -m pip install numpy==2.5.2 Pillow==12.3.0
```

以下命令均在本项目根目录执行，Python 和 XSDB 路径请按本机环境调整。不要使用 Python `-O`／`-OO`，脚本中的断言用于校验部署文件。

## 复现流程

### 1. 准备输入

复用已有 `cnn_scripts/inputs/vgg_batch_001/` 时跳过本步。换图时，将 JPG/JPEG 放入 `photo/`，在 `feature_input.py` 中将 `OUTPUT_DIR` 改为尚不存在的新目录，再执行：

```powershell
& 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B feature_input.py
```

脚本按文件名中的数字自然排序。当前 50 张的合并文件为 `input_bin.bin`，每张 401,408 字节，合计 20,070,400 字节；`batch.json` 保存图片顺序、偏移和 DDR 地址，`images/` 保存供输入复核使用的 PNG。生成入口拒绝覆盖已有目录。

### 2. 离线部署检查

在 `cnn_scripts/scripts/jtag/infer_vgg.py` 中配置模型、输入、硬件及新的运行目录。例如：

```python
MODEL_DIR = ROOT / "cnn_scripts/weight/vgg16"
INPUT_DIR = ROOT / "cnn_scripts/inputs/vgg_batch_001"
BUNDLE = ROOT / "hardware/system"
RUN_DIR = ROOT / "reports/VGG/prepare_002"
PREPARE_ONLY = True
XSDB = Path("E:/Vitis/2024.2/bin/xsdb.bat")
```

```powershell
& 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B cnn_scripts/scripts/jtag/infer_vgg.py
```

该模式核对模型、量化、指令、权重及每张图片的输入字节，检查地址范围与工作区重叠，并准备一次载荷和硬件快照；不会连接板卡。

### 3. 上板执行 50 张连续推理

板卡冷启动后，将 `PREPARE_ONLY` 设为 `False`，并将 `RUN_DIR` 改为另一个尚不存在的目录，例如 `reports/VGG/board_run_002`，然后执行同一命令。当前源码保留了已完成板测的配置，直接使用原 `board_run_001` 会被防覆盖检查拒绝；离线准备目录也不能复用。

一次会话下载及校验以下载荷：

| 载荷 | 字节数 | DDR 地址 |
| --- | ---: | --- |
| vgg_cmd.bin | 1472 | 0x04000000 |
| vgg_weights.bin | 286836800 | 0x12000000 |
| input_bin.bin，50 张 | 20070400 | 0x06000000 |

输入库占用 `0x06000000–0x07323FFF`，与当前 VGG16 在 `0x05000000` 和 `0x0B000000` 开始的 A/B 中间特征工作区分离。每张启动前只更新首层输入地址；其余层地址保持不变。下一张之前清 DONE、软复位计算逻辑并等待 ready，权重与输入均不重新下载。

每张的 logits、类别索引及周期保存到独立子目录。全部完成后恢复首层地址，并再次回读整个输入库检查内容未改变。根 `summary.json` 汇总逐图结果和硬件时延统计；错误时停止并保留已完成结果。分类索引由主机对 PL 输出的 1000 个 logits 取 argmax 得到。

单张图片部署、参数说明和故障排查见 [VGG16 使用说明](cnn_scripts/scripts/jtag/README_vgg.md)。模型、量化和硬件未改变时无需重新编译权重；更换模型或重新量化时，须生成匹配的模型包与输入。

## 离线检查

```powershell
& 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B cnn_scripts/scripts/check_vgg_input.py
& 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B cnn_scripts/scripts/jtag/test_infer_vgg.py -v
```

这些检查覆盖输入预处理、量化、拼接顺序、DDR 地址边界、一次模型下载、连续启动和失败记录；模拟 XSDB 的测试不能替代上板验证。

当前精简目录提供 RTL、测试向量和已导出的硬件包；Vivado 完整工程及原构建脚本未随附，上述流程复现的是现有硬件包的部署与推理。

## 验证结果

原始板测见 [board_run_001/summary.json](reports/VGG/board_run_001/summary.json)，逐图结果位于同目录的 `images/0001/` 至 `images/0050/`；核查与 FP32 对照见 [50 张图片结果分析](reports/VGG/board_run_001_analysis/analysis.md)。

| 项目 | 本次结果 |
| --- | --- |
| 模型与输入 | VGG16，224×224 RGB，1000 类输出，INT16 |
| 连续执行 | photo1.jpg 至 photo50.jpg，50/50 执行通过 |
| 完成检查 | 每张 DONE 有效、错误码 0、末层编号 20；CSR 与 DDR 周期记录一致 |
| 输入区检查 | 20,070,400 字节输入在全部推理后保持不变；首层地址恢复为 0x05000000 |
| 计算时钟 | 100 MHz |
| 平均硬件时延 | 7592.4379768 ms/图 |
| 硬件时延范围 | 7592.41788–7592.47695 ms；样本标准差 0.01350545 ms |
| 50 张总硬件时间 | 379.62189884 s |
| 整网有效算力 | 4.075177 GOPS，按 1 MAC=2 operations、Conv/FC 逻辑计算量统计 |
