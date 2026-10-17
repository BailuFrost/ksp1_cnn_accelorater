# TinyCNN：训练后量化、编译与 MNIST 输入生成

当前流程将模型与样本分开保存：模型改变时量化／编译一次，图片改变时只运行 `feature_input.py`。`cnn_model_tiny.py` 保留原训练与 `.pth` 保存逻辑。

| 脚本 | 职责 | 输出 |
| --- | --- | --- |
| `cnn_model_tiny.py` | 训练、保存权重与偏置 | `weight/tiny_mnist.pth` |
| `reference.py` | 使用训练集中的 1000 张样本校准，并提供六层 INT16 黄金推理函数 | `reports/tiny/calibration/quantization.json` |
| `scripts/cnn_compiler.py` | 读取 checkpoint、量化 JSON、网络和硬件配置，打包并检查实际二进制 | `generated_tiny/tiny_weights.bin`、`tiny_cmd.bin`，以及量化副本和部署清单 |
| `scripts/feature_input.py` | 从 MNIST 测试集选择一张原始图片，预处理并运行一次整数黄金推理 | `inputs/test_00000/digit.png`、`input.bin`、`expected.bin`、`sample.json` |
| `scripts/benchmark_cpu.py` | PC CPU 单线程、单张 FP32 前向计时，可读取已有板测结果对比 | 指定的结果 JSON，包含环境、每次耗时及汇总 |

## 如何运行

从工程根目录 `E:\Loongson_SoC\CNN\xc7z020_cnn_accelerator` 执行：

```powershell
# 权重已经训练保存，不必重新训练。
& 'E:\anaconda\conda\envs\cnn-fpga\python.exe' -B cnn_scripts/reference.py
& 'E:\anaconda\conda\envs\cnn-fpga\python.exe' -B cnn_scripts/scripts/cnn_compiler.py
& 'E:\anaconda\conda\envs\cnn-fpga\python.exe' -B cnn_scripts/scripts/feature_input.py
```

量化参数使用新的 `reports/tiny/calibration` 目录，不覆盖旧 `reports/tiny/quantization.json`、`golden/` 或 `t2/`。新参数记录 checkpoint SHA256，编译器拒绝缺少绑定或绑定不同权重的旧参数。现有 `.pth` 可直接用于上述流程。

各生成入口拒绝覆盖已有输出。重复使用同一模型时，跳过量化与编译；重新训练或确实需要重新生成时，在脚本顶部指定新的量化／编译目录，保证 `cnn_compiler.REFERENCE` 与参考输出对应、`feature_input.MODEL_DIR` 与编译输出对应。不要使用 Python `-O/-OO`。

## 选择测试图片

在 `scripts/feature_input.py` 顶部修改：

```python
MNIST_INDEX = 0
```

编号范围为 0～9999；编号 0 的真实标签为 7，编号 3 的标签为 0。输出目录默认随编号变为 `inputs/test_00000`、`inputs/test_00003` 等。

选图代码已放在 `feature_input.prepare()` 内，使用 `MNIST(DATA_DIR, train=False, download=False)`，因此复用本地数据、不联网下载。它先取得原始 28×28 的 L 模式 PIL 图，再调用训练共用的 `transform`，只归一化一次；原始图片保存为该输出目录中的 `digit.png`，无需预先准备根目录的 `digit.png`。

`sample.json` 保存测试编号、真实标签、浮点／INT16 预测、十个 logits、权重／量化摘要及本张输入／黄金文件摘要。换图只需改编号并运行这个脚本，不需要重新训练、校准或编译。

## 解耦后的依赖和检查

- 编译器不读取 `golden/manifest.json`、逐层 NPY／BIN，也不运行样本前向；保留模型图、硬件能力、尺度、signed48 范围、指令反解、全部物理权重／偏置及补零检查。
- `reference.main()` 只生成校准参数，不评估完整 10000 张测试集，不导出十张逐层黄金样本。已有 `evaluate()`／`save_sample()` 函数仍可供开发检查使用，不会在日常入口中自动调用。
- 特征生成不导入编译器，也不读取／扫描权重 BIN；只读取编译清单和量化 JSON，核对 checkpoint／量化摘要，再生成本张输入与黄金结果。缺失匹配关系时要求重新编译。
- 模型清单只记录模型文件、输入／输出的地址和形状合同，不记录某张样本；样本信息单独放在 `sample.json`。

实际四个 BIN：指令 **448** 字节、权重和偏置 **1993472** 字节、输入 **6272** 字节、黄金输出 **24** 字节。前三个写入 DDR，`expected.bin` 留在 PC，对照 PL 写回结果。

## 后续单次部署

`scripts/jtag/infer_tiny.py` 已同步新的编译包／输入清单，并修正导入名、checkpoint 和硬件包路径。它不再从模型包中取某张默认输入，必须指定 `--input-dir`：

```powershell
# 只做离线部署准备，不连接板卡；输出目录必须是新的。
& 'E:\anaconda\conda\envs\cnn-fpga\python.exe' -B cnn_scripts/scripts/jtag/infer_tiny.py reports/tiny/prepare_001 --input-dir cnn_scripts/inputs/test_00000 --prepare-only

# 后续实际上板使用另一个新目录，并去掉 --prepare-only。
# 本次没有执行以下命令。
& 'E:\anaconda\conda\envs\cnn-fpga\python.exe' -B cnn_scripts/scripts/jtag/infer_tiny.py reports/tiny/board_001 --input-dir cnn_scripts/inputs/test_00000
```

匹配的 F-J0 完整硬件包和 `model/tiny_model_config.json` 仍在工程原处。日常流程不运行池化小例、十轮重复、复位验收或 RTL 仿真。

修改后的离线检查及四 BIN 示例见 [检查记录](../reports/cnn_scripts_decoupled_20261017/修改与验证.md)。该检查记录形成时尚未上板；随后单次板测结果见 [板测记录](../reports/tiny/board_run_001/summary.json)。

## PC CPU 推理耗时对比

从工程根目录运行，结果文件必须是新的：

```powershell
& 'E:\anaconda\conda\envs\cnn-fpga\python.exe' -B cnn_scripts/scripts/benchmark_cpu.py reports/tiny/cpu_benchmark_002.json --input-dir cnn_scripts/inputs/test_00000 --board-run reports/tiny/board_run_001
```

`--board-run` 可省略，此时只测 CPU。脚本只读取已有文件，不连接板卡。使用与板测相同 checkpoint 和 `digit.png`，复用训练预处理；模型加载、图片读取、预处理、结果验证和文件写入均在计时之外。核对 checkpoint 摘要、浮点预测和板测样本身份，拒绝覆盖已有结果。

CPU 使用 `eval()`、`inference_mode()`，计算线程与算子间线程均为 1，batch=1，预热 50 次，再分别计时 1000 次 `model(batch)`；结果保存全部样本及平均值、中位数、最小／最大值。线程不绑定具体 CPU 核心，系统调度和后台负载会造成波动。当前计时包含 PyTorch 调用开销，表示权重和输入已就绪的重复推理延迟。

CPU 为 **PyTorch FP32**，FPGA 为 **INT16、100 MHz**；这属于相同网络、不同数值精度的实现对比。FPGA 的硬件周期包含取指、板内 DDR 搬运、计算及结果写回，不包含 JTAG 下载和 PC 回读，CPU 计时也不包含文件 I/O。`reference.py` 的校准耗时和带统计检查的黄金推理耗时不作为 CPU 性能基线。

本机首次测量结果见 [CPU 计时记录](../reports/tiny/cpu_benchmark_001.json)：Intel Core Ultra 5 125H，CPU 平均 **0.352900 ms**、中位数 **0.323000 ms**；已有板测为 **1493325 周期 = 14.933250 ms**。`CPU 平均耗时 / FPGA 耗时 = 0.023632`，即当前 CPU 约快 **42.32 倍**，当前 FPGA 实现相对本机没有延迟优势。两边本张图片均预测为 7；FPGA 为单次测量，尚无多次统计。
