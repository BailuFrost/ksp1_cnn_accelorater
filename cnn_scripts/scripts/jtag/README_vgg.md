# VGG16 单图与批量上板运行

入口为本目录的 `infer_vgg.py`，使用脚本顶部的路径，不需要命令行参数。输入目录为 `cnn_scripts/inputs/vgg_batch_001`，通过 `PREPARE_ONLY` 切换离线准备和实际上板。它调用 `infer_vgg.tcl`，复用已有 PS/DDR 初始化、缓存检查及 CSR 轮询函数，不修改 RTL 或 bitstream。

## 已完成的板测

当前已完成 VGG16 部署及 `photo1.jpg` 至 `photo50.jpg` 的连续上板推理，原始记录见 [board_run_001/summary.json](../../../reports/VGG/board_run_001/summary.json)，详细核查见 [结果分析](../../../reports/VGG/board_run_001_analysis/analysis.md)。

| 项目 | 本次结果 |
| --- | --- |
| 连续执行 | 50/50 通过；每张错误码 0、末层 20，CSR 与 DDR 周期一致 |
| 模型装载 | 一次初始化，指令、权重和合并输入各下载一次 |
| 输入完整性 | 全部推理后输入库未改变；首层地址已恢复 |
| 硬件时延 | 平均 7592.4379768 ms；50 张合计 379.62189884 s |
| FP32 参照 | Top-1 50/50、Top-5 类别集合 50/50 一致；Top-5 排序 49/50 一致 |

上述时延排除 JTAG 及主机开销。FP32 对照为另外保存的分析结果，不修改原始板测 `numerical_validation: NOT_PERFORMED`；一致性不能解释为有真实标签的分类准确率或整数逐位验证。对照中有 1 个末层输出达到 INT16 上限，具体见结果分析。

当前源码保留本次实测配置：`PREPARE_ONLY = False`，`RUN_DIR` 指向已存在的 `board_run_001`。再次运行前必须指定新目录；需要离线检查时显式设为 `True`。已有板测记录不会被覆盖。

## 批量图片预处理

将 JPG/JPEG 放入项目根目录 `photo/`，从项目根目录执行：

```powershell
& 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B feature_input.py
```

脚本按数字自然顺序处理文件，例如 `photo1.jpg`、`photo2.jpg`、`photo10.jpg`。预处理和 INT16 量化沿用当前模型参数，不加载 checkpoint 或运行分类。输出目录默认是 `cnn_scripts/inputs/vgg_batch_001`，必须尚不存在；需要重新生成时，在脚本顶部指定新的 `OUTPUT_DIR`，并同步部署脚本的 `INPUT_DIR`。

输出包含：

- `input_bin.bin`：只包含依次拼接的输入特征，没有文件头；每张 401408 字节，50 张共 20070400 字节。
- `batch.json`：记录图片顺序、原图路径、预览图路径、字节偏移、DDR 地址、量化及预处理参数。
- `images/0001.png` 等：经过 EXIF 方向处理并转为 RGB 的原尺寸图片，用于部署前重算输入、逐字节核对合并 BIN。

`hardware/vgg16_config.json` 的 `batch_input` 指定存储范围，`limit_address` 为不包含的上界。当前起址 `0x06000000`，上界 `0x0B000000`；50 张的实际范围为 `0x06000000–0x07323FFF`。该输入库避开当前 VGG16 在 `0x05000000` 和 `0x0B000000` 开始的中间特征写区。脚本依据模型输出形状及实际编译层地址检查重叠和容量；模型改变后也必须重新检查。

批次生成中途失败会保留新目录中的已有文件，不生成完整 `batch.json`；该目录不可直接复用。修正图片后使用新的输出目录。

## 部署配置

路径配置示例（已存在的运行目录不能复用）：

```python
MODEL_DIR = ROOT / "cnn_scripts/weight/vgg16"
INPUT_DIR = ROOT / "cnn_scripts/inputs/vgg_batch_001"
BUNDLE = ROOT / "hardware/system"
RUN_DIR = ROOT / "reports/VGG/prepare_002"
PREPARE_ONLY = True
JTAG_FREQUENCY_HZ = 10000000
```

先使用 `PREPARE_ONLY = True` 做离线检查。脚本核对模型图、量化尺度、signed48 上界、指令和权重样本、每张输入与保存图片的一致性，并复制一次模型、合并输入和硬件快照到新运行目录。批次的数字控制参数另写入 `batch.tsv` 供 Tcl 读取。无需 SHA256 清单或 `expected.bin`，不调用浮点或整数网络前向推理。

从工程根目录运行：

```powershell
& 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B cnn_scripts/scripts/jtag/infer_vgg.py
```

实际上板时，将 `PREPARE_ONLY` 改为 `False`，并将 `RUN_DIR` 改为另一个尚不存在的目录，例如 `reports/VGG/board_run_002`；离线检查已使用的目录不能直接复用。板卡需冷启动、设为 JTAG 启动并与现有 1 GiB DDR 硬件配置匹配。

批量下载合同为：

| 文件 | 字节数 | DDR 地址 |
| --- | ---: | --- |
| vgg_cmd.bin | 1472 | 0x04000000 |
| vgg_weights.bin | 286836800 | 0x12000000 |
| input_bin.bin | 图片数 × 401408；50 张为 20070400 | 0x06000000 |

一次 XSDB 会话只初始化一次，并将上述三个文件各下载、回读校验一次。然后逐张执行：更新首层指令中的 `F_ADDR`，回读核对地址，启动推理，保存输出和周期；下一张之前清除 DONE、执行计算逻辑软复位并等待 ready。其余层仍使用原 A/B 工作区，权重不重新下载。DDR 中首层地址更新位置由 Python 核对指令头后确定，当前为 `0x04000040`。

每张结果保存在 `images/0001/` 等子目录，包含 `input_address.txt`、`csr.txt`、`runtime.bin`、`output.bin`、`result.txt`。Python 汇总时生成各张 `summary.json`。下一张开始前已将上一张的输出回读到 PC，因此不会被相同输出地址覆盖。

全部图片完成后恢复原首层地址，并将整个输入库再分块回读一次，与原 BIN 逐字节比较，确认没有被中间特征覆盖。末次回读文件为 `input_bin.bin.final_readback`，该步骤不重新下载输入。

根目录 `summary.json` 包含每张的 logits、类别索引、64 位周期和硬件时延，以及硬件时延总和、均值、中位数、标准差和最小/最大值。这些统计不包含初始化、JTAG 下载或回读。批次中途失败时立即停止，保留已完成图片的文件和可验证的 `completed_images` 汇总；Tcl 记录 `failed_image.txt` 标识失败位置。不会自动重试或继续跳过失败图片。

## 保留的单图模式

将 `feature_input.py` 的 `IMAGE_PATH` 改为单张图片路径，`OUTPUT_DIR` 改为新目录，可继续生成原来的 `input.bin`、`sample.png`、`sample.json`。部署脚本 `INPUT_DIR` 指向该目录即可，仍使用 `0x05000000` 和原指令地址，不生成 `batch.tsv`。

Tcl 按 256 KiB 分块下载并逐块回读，直接比较字节；完整回读文件留在运行目录中。连接 hw_server 后、查找 CPU 和初始化 PS 之前，先将 JTAG 频率设为 10 MHz；支持频率及设置前后的实际值保存到 `jtag.txt`，初始化前目标列表保存为 `targets_before_init.txt`。这与 PL 的 100 MHz 计算时钟分别设置。启动后要求 DONE、错误码为零、末层编号 20，并核对 CSR 与 DDR 的 64 位周期记录。输出从 `0x04200000` 回读 500 个 32 位字，保存为 2000 字节的 `output.bin`。

每张的 `summary.json` 保存 1000 个 PL INT16 logits、输出小数位数、类别索引、周期及计算耗时。类别索引由主机对 PL logits 取 argmax 得到，不表示 PL 已增加 argmax 硬件。耗时由硬件周期和 100 MHz 时钟换算，排除 JTAG 下载和回读。

成功仅表示执行及 DDR 回读检查通过；`numerical_validation` 始终为 `NOT_PERFORMED`，不声称已验证数值精度或分类正确率。失败时保留 `xsdb.log`、可读取的失败 CSR/周期记录和 `summary.json`；终端和汇总保留 Tcl 的原始失败原因。传输失败另外保存 `failure_transfer.txt`，记录文件、块偏移、DDR 地址、已验证长度和下载／回读阶段。

若出现 `Invalid DAP IDCODE` 或 `Invalid DAP ACK`，先查看 `xsdb.log` 和 `failure_transfer.txt`。此前一次运行在权重前 65 MiB 验证通过后发生下载故障，尚未启动推理。1 MHz 和较小分块是排查通信稳定性的设置，不能证明故障源于原频率。重新尝试前冷启动板卡、检查供电和 JTAG 连接、关闭占用同一板卡的调试会话并重启 hw_server，然后将 `RUN_DIR` 改为新目录，例如 `board_run_002`。不自动重试失败块或跳过回读。

若提示找不到 Cortex-A9，先看日志的完整 `TARGETS` 或 `targets_before_init.txt`。仅出现 `whole scan chain (DR shift through all zeroes)` 表示未识别到有效芯片；不应通过放宽 CPU 名称匹配或写死目标编号绕过。检查板卡电源、JTAG 插头方向与连接、GND/VREF 和启动设置；恢复后应能看到 APU、两个 Cortex-A9 及 `xc7z020`。此时还未进行 PS 初始化、下载 bitstream 或 VGG 载荷。

默认每张推理超时 10 分钟、整个 XSDB 进程超时 3 小时。整个批次还包括权重及输入的下载和回读；图片数量或单张耗时增加时，需要相应调整脚本顶部的主机超时常量。

离线测试：

```powershell
& 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B cnn_scripts/scripts/check_vgg_input.py
& 'E:/anaconda/conda/envs/cnn-fpga/python.exe' -B cnn_scripts/scripts/jtag/test_infer_vgg.py -v
```

这些测试使用合成记录和模拟 XSDB 命令，不能作为实际板端验证证据。请勿使用 Python `-O` 或 `-OO`。
