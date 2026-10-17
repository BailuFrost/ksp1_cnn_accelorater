`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/14 00:00:00
// Design Name:     cnn_board_top
// Module Name:     cnn_board_top
// Description:     description/cnn_board_top_Design.pdf
// Simulations:     testbench/vivado/2021.1/cnn_board_top
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/cnn_board_top_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/14 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/14       V1.0        Codex             Create cnn_board_top production integration.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月14日
// 设计名称:        cnn_board_top
// 模块名称:        cnn_board_top
// 模块说明:        Description/cnn_board_top_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/cnn_board_top
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/cnn_board_top_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月14日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月14日   V1.0        Codex             创建真实搬运器取消边界

module cnn_board_top
(
	//-----------------用户接口-----------------//
	input i_clk,                                // FCLK_CLK0统一时钟。
	input i_rstn,                               // 低有效异步断言，上游同域同步释放。
	input i_ce,                                 // 用户暂停，仅冻结算法，AXI协议继续记账。

	input [7:0]i_axi_awaddr,                    // 寄存器字节偏移，独立接受AW。
	input i_axi_awvalid,                        // 写地址有效。
	output o_axi_awready,                       // 单个地址缓存可接受。
	input [31:0]i_axi_wdata,                    // 写寄存器载荷。
	input [3:0]i_axi_wstrb,                     // 逐字节写入资格。
	input i_axi_wvalid,                         // 写载荷有效，允许早于AW。
	output o_axi_wready,                        // 单个载荷缓存可接受。
	output [1:0]o_axi_bresp,                    // OKAY/SLVERR/DECERR响应。
	output o_axi_bvalid,                        // 写提交响应，直到BREADY保持。
	input i_axi_bready,                         // 主机接收写响应。
	input [7:0]i_axi_araddr,                    // 读字节偏移。
	input i_axi_arvalid,                        // 读地址有效。
	output o_axi_arready,                       // 单个读响应空闲。
	output [31:0]o_axi_rdata,                   // 接受AR时锁存的寄存器值。
	output [1:0]o_axi_rresp,                    // 读地址和对齐检查响应。
	output o_axi_rvalid,                        // 读值和响应保持至RREADY。
	input i_axi_rready,                         // 主机接收读响应。
	output o_irq,                               // PS电平中断，清粘滞状态后撤销。
	output o_busy,                              // 整网运行或DMA复位等待。
	output o_done,                              // 最终GP成功状态后粘滞完成。
	output o_error,                             // 首整网故障粘滞。
	output [31:0]o_error_code,                  // 首错及来源/控制器诊断，字段与ERROR_CODE一致。
	output [7:0]o_current_layer,                // 当前层调试号。
	output [63:0]o_cycles,                      // 整网真实周期。
	output o_layer_done,                        // 实际OUTPUT末成功响应且计算/结果排空后的单拍。

	output o_gp_read_cmd_valid,                 // 模型头及双表读取资格。
	input i_gp_read_cmd_ready,                  // GP前端接收取指地址。
	output [71:0]o_gp_read_cmd_data,            // 分发器保持的七十二位读指令。
	input i_gp_read_data_valid,                 // 来自DDR的指令word现在可取。
	output o_gp_read_data_ready,                // 基础或扩展记录的当前word入缓存许可。

	input [31:0]i_gp_read_data,                 // 四字节小端取指片段。
	input [3:0]i_gp_read_keep,                  // 取指帧中有效字节必须全部置位。
	input i_gp_read_last,                       // 标记当前头或表的最后word。
	input i_gp_read_status_valid,               // 指令搬运应答现已到达。
	output o_gp_read_status_ready,              // 预取器允许消费本次MM2S诊断。
	input [7:0]i_gp_read_status,                // 头和双表均要求读应答等于80。

	output o_gp_write_cmd_valid,                // 全网计时S2MM事务发布。
	input i_gp_write_cmd_ready,                 // GP后端能够保存统计首址。
	output [71:0]o_gp_write_cmd_data,           // 十六字节运行记录的完整写指令。
	output o_gp_write_data_valid,               // 待回写的周期低高半字及诊断word有效。
	input i_gp_write_data_ready,                // 统计区后端接收当前32位结果。

	output [31:0]o_gp_write_data,               // 冻结的总周期或运行状态字。
	output [3:0]o_gp_write_keep,                // 运行记录完整word的四字节使能。
	output o_gp_write_last,                     // 仅第四个统计word置位结束。
	input i_gp_write_status_valid,              // GP已完成周期记录的DDR提交。
	output o_gp_write_status_ready,             // 分发器检查末次统计写应答。
	input [7:0]i_gp_write_status,               // 最终整网done依赖精确成功写状态。

	output o_feature_cmd_valid,                 // 新扫描或安全覆盖的HP0搬运资格。
	input i_feature_cmd_ready,                  // 三行特征DMA能接收新的HWC地址。
	output [71:0]o_feature_cmd_data,            // 当前真实行向量的物理读取指令。
	input i_feature_data_valid,                 // HP0到达四个INT16原始特征。
	output o_feature_data_ready,                // 缓存写入授权后接收特征beat。

	input [63:0]i_feature_data,                 // 待拆成行bank内容的64位向量。
	input [7:0]i_feature_keep,                  // 特征读要求八字节全有效。
	input i_feature_last,                       // 输入行或向量块的搬运尾标签。
	input i_feature_status_valid,               // HP0扫描搬运状态已返回。
	output o_feature_status_ready,              // 特征控制器核实行数据事务。
	input [7:0]i_feature_status,                // 缓存扫描完成必须有成功HP0诊断。

	output o_weight_cmd_valid,                  // 当前组tile权重或组偏置的HP1装载资格。
	input i_weight_cmd_ready,                   // 私有核DMA准备接受新块首址。
	output [71:0]o_weight_cmd_data,             // CU-major九bank物理布局的装载指令。
	input i_weight_data_valid,                  // HP1返回可拆为两次pair的核参数。
	output o_weight_data_ready,                 // 核bank写通道空闲时接收新参数beat。

	input [63:0]i_weight_data,                  // 低高32位分别形成C2原生pair内容。
	input [7:0]i_weight_keep,                   // 权重装载每次验证全八字节使能。
	input i_weight_last,                        // 当前核块或偏置块已到数据尾。
	input i_weight_status_valid,                // 私有核填充DMA报告传输结果。
	output o_weight_status_ready,               // HP1诊断归属唯一在途装载。
	input [7:0]i_weight_status,                 // 只有精确80状态能放行weight_ready。

	output o_output_cmd_valid,                  // 输出组当前空间位置的HP2回写资格。
	input i_output_cmd_ready,                   // 结果DMA接收当前像素目标地址。
	output [71:0]o_output_cmd_data,             // 按Cout_padded跨度产生的S2MM写指令。
	output o_output_data_valid,                 // 量化四lane向DDR提交的有效拍。
	input i_output_data_ready,                  // HP2后端具备当前结果beat接收容量。

	output [63:0]o_output_data,                 // 尾lane清零后的四个有符号结果。
	output [7:0]o_output_keep,                  // 物理结果存储始终写满八字节。
	output o_output_last,                       // 像素或FC分块的最后数据拍。
	input i_output_status_valid,                // HP2已返回当前写事务状态。
	output o_output_status_ready,               // 输出屏障独立记账当前DDR写响应。
	input [7:0]i_output_status,                 // 只有成功结果写应答能推进层完成。
	input [1:0]i_gp_halted,                     // GP读写两个方向的真实停止应答。
	input [2:0]i_hp_halted,                     // 特征/权重/输出三个方向的真实停止应答。
	output o_gp_halt,                           // 指令读和运行记录写同步停止。
	output o_gp_dma_rstn,                       // GP双向引擎静止后的局部低有效复位。
	output o_hp_halt,                           // 特征、权重与结果主设备共同取消。
	output o_hp_dma_rstn                        // HP三个方向停止后的同步释放复位。
);

	//--------------模块实例化信号--------------//
	//停止应答补齐
	wire [2:0]gp_halted_vector;                 // 指令两个方向加恒真未用通道组成停止向量。

	//-----------------标志信号-----------------//
	wire flag_gp_reset_req;                     // 指令与记录取消的核心授权节点。
	wire flag_gp_reset_done;                    // 主端口双向引擎恢复后可回应生产取指器。
	wire flag_gp_enabled;                       // 指令读写边界当前可以透传任务。
	wire flag_hp_reset_req;                     // 计算故障先关闭三个数据面搬运器。
	wire flag_hp_reset_done;                    // 三个高性能端口均清理结束的恢复许可。
	wire flag_hp_enabled;                       // 特征权重结果的数据流接入许可。
	wire flag_core_gp_read_cmd_valid;           // 边界内侧等待连接的握手节点：模型头及双表读取资格。
	wire flag_core_gp_read_cmd_ready;           // 边界内侧等待连接的握手节点：GP前端接收取指地址。
	wire flag_core_gp_read_data_valid;          // 边界内侧等待连接的握手节点：来自DDR的指令word现在可取。
	wire flag_core_gp_read_data_ready;          // 边界内侧等待连接的握手节点：基础或扩展记录的当前word入缓存许可。
	wire flag_core_gp_read_status_valid;        // 边界内侧等待连接的握手节点：指令搬运应答现已到达。
	wire flag_core_gp_read_status_ready;        // 边界内侧等待连接的握手节点：预取器允许消费本次MM2S诊断。
	wire flag_core_gp_write_cmd_valid;          // 边界内侧等待连接的握手节点：全网计时S2MM事务发布。
	wire flag_core_gp_write_cmd_ready;          // 边界内侧等待连接的握手节点：GP后端能够保存统计首址。
	wire flag_core_gp_write_data_valid;         // 边界内侧等待连接的握手节点：待回写的周期低高半字及诊断word有效。
	wire flag_core_gp_write_data_ready;         // 边界内侧等待连接的握手节点：统计区后端接收当前32位结果。
	wire flag_core_gp_write_status_valid;       // 边界内侧等待连接的握手节点：GP已完成周期记录的DDR提交。
	wire flag_core_gp_write_status_ready;       // 边界内侧等待连接的握手节点：分发器检查末次统计写应答。
	wire flag_core_feature_cmd_valid;           // 边界内侧等待连接的握手节点：新扫描或安全覆盖的HP0搬运资格。
	wire flag_core_feature_cmd_ready;           // 边界内侧等待连接的握手节点：三行特征DMA能接收新的HWC地址。
	wire flag_core_feature_data_valid;          // 边界内侧等待连接的握手节点：HP0到达四个INT16原始特征。
	wire flag_core_feature_data_ready;          // 边界内侧等待连接的握手节点：缓存写入授权后接收特征beat。
	wire flag_core_feature_status_valid;        // 边界内侧等待连接的握手节点：HP0扫描搬运状态已返回。
	wire flag_core_feature_status_ready;        // 边界内侧等待连接的握手节点：特征控制器核实行数据事务。
	wire flag_core_weight_cmd_valid;            // 边界内侧等待连接的握手节点：当前组tile权重或组偏置的HP1装载资格。
	wire flag_core_weight_cmd_ready;            // 边界内侧等待连接的握手节点：私有核DMA准备接受新块首址。
	wire flag_core_weight_data_valid;           // 边界内侧等待连接的握手节点：HP1返回可拆为两次pair的核参数。
	wire flag_core_weight_data_ready;           // 边界内侧等待连接的握手节点：核bank写通道空闲时接收新参数beat。
	wire flag_core_weight_status_valid;         // 边界内侧等待连接的握手节点：私有核填充DMA报告传输结果。
	wire flag_core_weight_status_ready;         // 边界内侧等待连接的握手节点：HP1诊断归属唯一在途装载。
	wire flag_core_output_cmd_valid;            // 边界内侧等待连接的握手节点：输出组当前空间位置的HP2回写资格。
	wire flag_core_output_cmd_ready;            // 边界内侧等待连接的握手节点：结果DMA接收当前像素目标地址。
	wire flag_core_output_data_valid;           // 边界内侧等待连接的握手节点：量化四lane向DDR提交的有效拍。
	wire flag_core_output_data_ready;           // 边界内侧等待连接的握手节点：HP2后端具备当前结果beat接收容量。
	wire flag_core_output_status_valid;         // 边界内侧等待连接的握手节点：HP2已返回当前写事务状态。
	wire flag_core_output_status_ready;         // 边界内侧等待连接的握手节点：输出屏障独立记账当前DDR写响应。

	//-----------------其他信号-----------------//
	//停止应答补齐

	//主端口停止资格
	wire [1:0]gp_halted_pair;                   // GP取消输入两位响应的组合连接。

	//-----------------输出信号-----------------//
	//用户接口
	wire axi_awready_o;                         // 原实例驱动且不另缓存的节点：单个地址缓存可接受。
	wire axi_wready_o;                          // 原实例驱动且不另缓存的节点：单个载荷缓存可接受。
	wire [1:0]axi_bresp_o;                      // 原实例驱动且不另缓存的节点：OKAY/SLVERR/DECERR响应。
	wire axi_bvalid_o;                          // 原实例驱动且不另缓存的节点：写提交响应，直到BREADY保持。
	wire axi_arready_o;                         // 原实例驱动且不另缓存的节点：单个读响应空闲。
	wire [31:0]axi_rdata_o;                     // 原实例驱动且不另缓存的节点：接受AR时锁存的寄存器值。
	wire [1:0]axi_rresp_o;                      // 原实例驱动且不另缓存的节点：读地址和对齐检查响应。
	wire axi_rvalid_o;                          // 原实例驱动且不另缓存的节点：读值和响应保持至RREADY。

	//用户接口
	wire irq_o;                                 // 原实例驱动且不另缓存的节点：PS电平中断，清粘滞状态后撤销。
	wire busy_o;                                // 原实例驱动且不另缓存的节点：整网运行或DMA复位等待。
	wire done_o;                                // 原实例驱动且不另缓存的节点：最终GP成功状态后粘滞完成。
	wire error_o;                               // 原实例驱动且不另缓存的节点：首整网故障粘滞。
	wire [31:0]error_code_o;                    // 原实例驱动且不另缓存的节点：首错及来源/控制器诊断，字段与ERROR_CODE一致。
	wire [7:0]current_layer_o;                  // 原实例驱动且不另缓存的节点：当前层调试号。
	wire [63:0]cycles_o;                        // 原实例驱动且不另缓存的节点：整网真实周期。
	wire layer_done_o;                          // 原实例驱动且不另缓存的节点：实际OUTPUT末成功响应且计算/结果排空后的单拍。

	//用户接口
	wire [71:0]gp_read_cmd_data_o;              // 原实例驱动且不另缓存的节点：分发器保持的七十二位读指令。

	//用户接口
	wire [71:0]gp_write_cmd_data_o;             // 原实例驱动且不另缓存的节点：十六字节运行记录的完整写指令。

	//用户接口
	wire [31:0]gp_write_data_o;                 // 原实例驱动且不另缓存的节点：冻结的总周期或运行状态字。
	wire [3:0]gp_write_keep_o;                  // 原实例驱动且不另缓存的节点：运行记录完整word的四字节使能。
	wire gp_write_last_o;                       // 原实例驱动且不另缓存的节点：仅第四个统计word置位结束。

	//用户接口
	wire [71:0]feature_cmd_data_o;              // 原实例驱动且不另缓存的节点：当前真实行向量的物理读取指令。

	//用户接口
	wire [71:0]weight_cmd_data_o;               // 原实例驱动且不另缓存的节点：CU-major九bank物理布局的装载指令。

	//用户接口
	wire [71:0]output_cmd_data_o;               // 原实例驱动且不另缓存的节点：按Cout_padded跨度产生的S2MM写指令。

	//用户接口
	wire [63:0]output_data_o;                   // 原实例驱动且不另缓存的节点：尾lane清零后的四个有符号结果。
	wire [7:0]output_keep_o;                    // 原实例驱动且不另缓存的节点：物理结果存储始终写满八字节。
	wire output_last_o;                         // 原实例驱动且不另缓存的节点：像素或FC分块的最后数据拍。

	//用户接口
	wire gp_halt_o;                             // 指令和记录完成在途主设备事务的停止控制内部驱动。
	wire gp_dma_rstn_o;                         // 指令和记录满足最小时长的引擎复位控制内部驱动。
	wire hp_halt_o;                             // 数据面三个通路完成在途主设备事务的停止控制内部驱动。
	wire hp_dma_rstn_o;                         // 数据面三个通路满足最小时长的引擎复位控制内部驱动。

	//---------------其他信号连线---------------//
	//用户接口
	assign flag_core_gp_read_cmd_ready = i_gp_read_cmd_ready && flag_gp_enabled; // 仅本组资格开启才向核心交付：GP前端接收取指地址。
	assign flag_core_gp_read_data_valid = i_gp_read_data_valid && flag_gp_enabled; // 仅本组资格开启才向核心交付：来自DDR的指令word现在可取。

	//用户接口
	assign flag_core_gp_read_status_valid = i_gp_read_status_valid && flag_gp_enabled; // 仅本组资格开启才向核心交付：指令搬运应答现已到达。

	//用户接口
	assign flag_core_gp_write_cmd_ready = i_gp_write_cmd_ready && flag_gp_enabled; // 仅本组资格开启才向核心交付：GP后端能够保存统计首址。
	assign flag_core_gp_write_data_ready = i_gp_write_data_ready && flag_gp_enabled; // 仅本组资格开启才向核心交付：统计区后端接收当前32位结果。

	//用户接口
	assign flag_core_gp_write_status_valid = i_gp_write_status_valid && flag_gp_enabled; // 仅本组资格开启才向核心交付：GP已完成周期记录的DDR提交。

	//用户接口
	assign flag_core_feature_cmd_ready = i_feature_cmd_ready && flag_hp_enabled; // 仅本组资格开启才向核心交付：三行特征DMA能接收新的HWC地址。
	assign flag_core_feature_data_valid = i_feature_data_valid && flag_hp_enabled; // 仅本组资格开启才向核心交付：HP0到达四个INT16原始特征。

	//用户接口
	assign flag_core_feature_status_valid = i_feature_status_valid && flag_hp_enabled; // 仅本组资格开启才向核心交付：HP0扫描搬运状态已返回。

	//用户接口
	assign flag_core_weight_cmd_ready = i_weight_cmd_ready && flag_hp_enabled; // 仅本组资格开启才向核心交付：私有核DMA准备接受新块首址。
	assign flag_core_weight_data_valid = i_weight_data_valid && flag_hp_enabled; // 仅本组资格开启才向核心交付：HP1返回可拆为两次pair的核参数。

	//用户接口
	assign flag_core_weight_status_valid = i_weight_status_valid && flag_hp_enabled; // 仅本组资格开启才向核心交付：私有核填充DMA报告传输结果。

	//用户接口
	assign flag_core_output_cmd_ready = i_output_cmd_ready && flag_hp_enabled; // 仅本组资格开启才向核心交付：结果DMA接收当前像素目标地址。
	assign flag_core_output_data_ready = i_output_data_ready && flag_hp_enabled; // 仅本组资格开启才向核心交付：HP2后端具备当前结果beat接收容量。

	//用户接口
	assign flag_core_output_status_valid = i_output_status_valid && flag_hp_enabled; // 仅本组资格开启才向核心交付：HP2已返回当前写事务状态。

	//其他信号连线

	//用户接口
	assign gp_halted_vector = {1'b1, gp_halted_pair}; // GP只需等待低两位真实halt完成。
	assign gp_halted_pair = i_gp_halted;        // 主端口读写的两位停止响应保持原位序。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_axi_awready = axi_awready_o;       // 经过边界原样送达外部接收端：单个地址缓存可接受。
	assign o_axi_wready = axi_wready_o;         // 经过边界原样送达外部接收端：单个载荷缓存可接受。
	assign o_axi_bresp = axi_bresp_o;           // 经过边界原样送达外部接收端：OKAY/SLVERR/DECERR响应。
	assign o_axi_bvalid = axi_bvalid_o;         // 经过边界原样送达外部接收端：写提交响应，直到BREADY保持。
	assign o_axi_arready = axi_arready_o;       // 经过边界原样送达外部接收端：单个读响应空闲。
	assign o_axi_rdata = axi_rdata_o;           // 经过边界原样送达外部接收端：接受AR时锁存的寄存器值。
	assign o_axi_rresp = axi_rresp_o;           // 经过边界原样送达外部接收端：读地址和对齐检查响应。
	assign o_axi_rvalid = axi_rvalid_o;         // 经过边界原样送达外部接收端：读值和响应保持至RREADY。

	//用户接口
	assign o_irq = irq_o;                       // 经过边界原样送达外部接收端：PS电平中断，清粘滞状态后撤销。
	assign o_busy = busy_o;                     // 经过边界原样送达外部接收端：整网运行或DMA复位等待。
	assign o_done = done_o;                     // 经过边界原样送达外部接收端：最终GP成功状态后粘滞完成。
	assign o_error = error_o;                   // 经过边界原样送达外部接收端：首整网故障粘滞。
	assign o_error_code = error_code_o;         // 经过边界原样送达外部接收端：首错及来源/控制器诊断，字段与ERROR_CODE一致。
	assign o_current_layer = current_layer_o;   // 经过边界原样送达外部接收端：当前层调试号。
	assign o_cycles = cycles_o;                 // 经过边界原样送达外部接收端：整网真实周期。
	assign o_layer_done = layer_done_o;         // 经过边界原样送达外部接收端：实际OUTPUT末成功响应且计算/结果排空后的单拍。

	//用户接口
	assign o_gp_read_cmd_valid = flag_gp_enabled ? flag_core_gp_read_cmd_valid : 1'b0; // 取消阶段禁止新提交。模型头及双表读取资格。
	assign o_gp_read_cmd_data = gp_read_cmd_data_o; // 经过边界原样送达外部接收端：分发器保持的七十二位读指令。

	//用户接口
	assign o_gp_read_data_ready = flag_gp_enabled ? flag_core_gp_read_data_ready : 1'b1; // 取消阶段排空并丢弃残留。基础或扩展记录的当前word入缓存许可。

	//用户接口
	assign o_gp_read_status_ready = flag_gp_enabled ? flag_core_gp_read_status_ready : 1'b1; // 取消阶段排空并丢弃残留。预取器允许消费本次MM2S诊断。

	//用户接口
	assign o_gp_write_cmd_valid = flag_gp_enabled ? flag_core_gp_write_cmd_valid : 1'b0; // 取消阶段禁止新提交。全网计时S2MM事务发布。
	assign o_gp_write_cmd_data = gp_write_cmd_data_o; // 经过边界原样送达外部接收端：十六字节运行记录的完整写指令。

	//用户接口
	assign o_gp_write_data_valid = flag_gp_enabled ? flag_core_gp_write_data_valid : 1'b0; // 取消阶段禁止新提交。待回写的周期低高半字及诊断word有效。

	//用户接口
	assign o_gp_write_data = gp_write_data_o;   // 经过边界原样送达外部接收端：冻结的总周期或运行状态字。
	assign o_gp_write_keep = gp_write_keep_o;   // 经过边界原样送达外部接收端：运行记录完整word的四字节使能。
	assign o_gp_write_last = gp_write_last_o;   // 经过边界原样送达外部接收端：仅第四个统计word置位结束。

	//用户接口
	assign o_gp_write_status_ready = flag_gp_enabled ? flag_core_gp_write_status_ready : 1'b1; // 取消阶段排空并丢弃残留。分发器检查末次统计写应答。

	//用户接口
	assign o_feature_cmd_valid = flag_hp_enabled ? flag_core_feature_cmd_valid : 1'b0; // 取消阶段禁止新提交。新扫描或安全覆盖的HP0搬运资格。
	assign o_feature_cmd_data = feature_cmd_data_o; // 经过边界原样送达外部接收端：当前真实行向量的物理读取指令。

	//用户接口
	assign o_feature_data_ready = flag_hp_enabled ? flag_core_feature_data_ready : 1'b1; // 取消阶段排空并丢弃残留。缓存写入授权后接收特征beat。

	//用户接口
	assign o_feature_status_ready = flag_hp_enabled ? flag_core_feature_status_ready : 1'b1; // 取消阶段排空并丢弃残留。特征控制器核实行数据事务。

	//用户接口
	assign o_weight_cmd_valid = flag_hp_enabled ? flag_core_weight_cmd_valid : 1'b0; // 取消阶段禁止新提交。当前组tile权重或组偏置的HP1装载资格。
	assign o_weight_cmd_data = weight_cmd_data_o; // 经过边界原样送达外部接收端：CU-major九bank物理布局的装载指令。

	//用户接口
	assign o_weight_data_ready = flag_hp_enabled ? flag_core_weight_data_ready : 1'b1; // 取消阶段排空并丢弃残留。核bank写通道空闲时接收新参数beat。

	//用户接口
	assign o_weight_status_ready = flag_hp_enabled ? flag_core_weight_status_ready : 1'b1; // 取消阶段排空并丢弃残留。HP1诊断归属唯一在途装载。

	//用户接口
	assign o_output_cmd_valid = flag_hp_enabled ? flag_core_output_cmd_valid : 1'b0; // 取消阶段禁止新提交。输出组当前空间位置的HP2回写资格。
	assign o_output_cmd_data = output_cmd_data_o; // 经过边界原样送达外部接收端：按Cout_padded跨度产生的S2MM写指令。

	//用户接口
	assign o_output_data_valid = flag_hp_enabled ? flag_core_output_data_valid : 1'b0; // 取消阶段禁止新提交。量化四lane向DDR提交的有效拍。

	//用户接口
	assign o_output_data = output_data_o;       // 经过边界原样送达外部接收端：尾lane清零后的四个有符号结果。
	assign o_output_keep = output_keep_o;       // 经过边界原样送达外部接收端：物理结果存储始终写满八字节。
	assign o_output_last = output_last_o;       // 经过边界原样送达外部接收端：像素或FC分块的最后数据拍。

	//用户接口
	assign o_output_status_ready = flag_hp_enabled ? flag_core_output_status_ready : 1'b1; // 取消阶段排空并丢弃残留。输出屏障独立记账当前DDR写响应。
	assign o_gp_halt = gp_halt_o;               // 将指令和记录的完成在途主设备事务的停止控制送入对应IP。
	assign o_gp_dma_rstn = gp_dma_rstn_o;       // 将指令和记录的满足最小时长的引擎复位控制送入对应IP。
	assign o_hp_halt = hp_halt_o;               // 将数据面三个通路的完成在途主设备事务的停止控制送入对应IP。
	assign o_hp_dma_rstn = hp_dma_rstn_o;       // 将数据面三个通路的满足最小时长的引擎复位控制送入对应IP。

	//--------------模块实例化区域--------------//
	// 指令读写独立等待清理，在首故障流程中保持原有先后关系。
	cnn_dma_reset_manager gp_reset_manager(     // 管理指令读写相关引擎的停止和恢复。
		.i_clk(i_clk),                          // 指令读写的管理状态在FCLK域采样。
		.i_rstn(i_rstn),                        // 全局复位初始化指令读写取消进度。
		.i_request(flag_gp_reset_req),          // 核心授权对指令读写发起停止操作。
		.i_halted(gp_halted_vector),            // 收集指令读写各方向完成主端口事务的应答。
		.o_halt(gp_halt_o),                     // 请求指令读写停止发布新的DDR地址。
		.o_dma_rstn(gp_dma_rstn_o),             // 清理指令读写私有FIFO和命令缓存。
		.o_enabled(flag_gp_enabled),            // 指令读写透传资格只在恢复结束后建立。
		.o_done(flag_gp_reset_done)             // 指令读写的本次取消完成反馈给生产核心。
	);

	// 特征核参数结果独立等待清理，在首故障流程中保持原有先后关系。
	cnn_dma_reset_manager hp_reset_manager(     // 管理特征核参数结果相关引擎的停止和恢复。
		.i_clk(i_clk),                          // 特征核参数结果的管理状态在FCLK域采样。
		.i_rstn(i_rstn),                        // 全局复位初始化特征核参数结果取消进度。
		.i_request(flag_hp_reset_req),          // 核心授权对特征核参数结果发起停止操作。
		.i_halted(i_hp_halted),                 // 收集特征核参数结果各方向完成主端口事务的应答。
		.o_halt(hp_halt_o),                     // 请求特征核参数结果停止发布新的DDR地址。
		.o_dma_rstn(hp_dma_rstn_o),             // 清理特征核参数结果私有FIFO和命令缓存。
		.o_enabled(flag_hp_enabled),            // 特征核参数结果透传资格只在恢复结束后建立。
		.o_done(flag_hp_reset_done)             // 特征核参数结果的本次取消完成反馈给生产核心。
	);

	// 复用完整生产核心，保留DDR取指、错误记录和四控制器合同。
	cnn_accelerator_top accelerator(            // 原生产核心唯一实例。
		.i_clk(i_clk),                          // 生产实例的i_clk连接：FCLK_CLK0统一时钟。
		.i_rstn(i_rstn),                        // 生产实例的i_rstn连接：低有效异步断言，上游同域同步释放。
		.i_ce(i_ce),                            // 生产实例的i_ce连接：用户暂停，仅冻结算法，AXI协议继续记账。
		.i_axi_awaddr(i_axi_awaddr),            // 生产实例的i_axi_awaddr连接：寄存器字节偏移，独立接受AW。
		.i_axi_awvalid(i_axi_awvalid),          // 生产实例的i_axi_awvalid连接：写地址有效。
		.o_axi_awready(axi_awready_o),          // 生产实例的o_axi_awready连接：单个地址缓存可接受。
		.i_axi_wdata(i_axi_wdata),              // 生产实例的i_axi_wdata连接：写寄存器载荷。
		.i_axi_wstrb(i_axi_wstrb),              // 生产实例的i_axi_wstrb连接：逐字节写入资格。
		.i_axi_wvalid(i_axi_wvalid),            // 生产实例的i_axi_wvalid连接：写载荷有效，允许早于AW。
		.o_axi_wready(axi_wready_o),            // 生产实例的o_axi_wready连接：单个载荷缓存可接受。
		.o_axi_bresp(axi_bresp_o),              // 生产实例的o_axi_bresp连接：OKAY/SLVERR/DECERR响应。
		.o_axi_bvalid(axi_bvalid_o),            // 生产实例的o_axi_bvalid连接：写提交响应，直到BREADY保持。
		.i_axi_bready(i_axi_bready),            // 生产实例的i_axi_bready连接：主机接收写响应。
		.i_axi_araddr(i_axi_araddr),            // 生产实例的i_axi_araddr连接：读字节偏移。
		.i_axi_arvalid(i_axi_arvalid),          // 生产实例的i_axi_arvalid连接：读地址有效。
		.o_axi_arready(axi_arready_o),          // 生产实例的o_axi_arready连接：单个读响应空闲。
		.o_axi_rdata(axi_rdata_o),              // 生产实例的o_axi_rdata连接：接受AR时锁存的寄存器值。
		.o_axi_rresp(axi_rresp_o),              // 生产实例的o_axi_rresp连接：读地址和对齐检查响应。
		.o_axi_rvalid(axi_rvalid_o),            // 生产实例的o_axi_rvalid连接：读值和响应保持至RREADY。
		.i_axi_rready(i_axi_rready),            // 生产实例的i_axi_rready连接：主机接收读响应。
		.i_gp_reset_done(flag_gp_reset_done),   // 生产实例的i_gp_reset_done连接：GP取消/复位应答，收到请求后同步给出。
		.i_hp_reset_done(flag_hp_reset_done),   // 生产实例的i_hp_reset_done连接：三个HP DataMover共同取消/复位应答。
		.o_gp_reset_req(flag_gp_reset_req),     // 生产实例的o_gp_reset_req连接：软复位或错误记录结束后请求取消GP事务。
		.o_hp_reset_req(flag_hp_reset_req),     // 生产实例的o_hp_reset_req连接：软复位或首错误后立即请求取消三个HP事务。
		.o_irq(irq_o),                          // 生产实例的o_irq连接：PS电平中断，清粘滞状态后撤销。
		.o_busy(busy_o),                        // 生产实例的o_busy连接：整网运行或DMA复位等待。
		.o_done(done_o),                        // 生产实例的o_done连接：最终GP成功状态后粘滞完成。
		.o_error(error_o),                      // 生产实例的o_error连接：首整网故障粘滞。
		.o_error_code(error_code_o),            // 生产实例的o_error_code连接：首错及来源/控制器诊断，字段与ERROR_CODE一致。
		.o_current_layer(current_layer_o),      // 生产实例的o_current_layer连接：当前层调试号。
		.o_cycles(cycles_o),                    // 生产实例的o_cycles连接：整网真实周期。
		.o_layer_done(layer_done_o),            // 生产实例的o_layer_done连接：实际OUTPUT末成功响应且计算/结果排空后的单拍。
		.o_gp_read_cmd_valid(flag_core_gp_read_cmd_valid), // 生产实例的o_gp_read_cmd_valid连接：模型头及双表读取资格。
		.i_gp_read_cmd_ready(flag_core_gp_read_cmd_ready), // 生产实例的i_gp_read_cmd_ready连接：GP前端接收取指地址。
		.o_gp_read_cmd_data(gp_read_cmd_data_o), // 生产实例的o_gp_read_cmd_data连接：分发器保持的七十二位读指令。
		.i_gp_read_data_valid(flag_core_gp_read_data_valid), // 生产实例的i_gp_read_data_valid连接：来自DDR的指令word现在可取。
		.o_gp_read_data_ready(flag_core_gp_read_data_ready), // 生产实例的o_gp_read_data_ready连接：基础或扩展记录的当前word入缓存许可。
		.i_gp_read_data(i_gp_read_data),        // 生产实例的i_gp_read_data连接：四字节小端取指片段。
		.i_gp_read_keep(i_gp_read_keep),        // 生产实例的i_gp_read_keep连接：取指帧中有效字节必须全部置位。
		.i_gp_read_last(i_gp_read_last),        // 生产实例的i_gp_read_last连接：标记当前头或表的最后word。
		.i_gp_read_status_valid(flag_core_gp_read_status_valid), // 生产实例的i_gp_read_status_valid连接：指令搬运应答现已到达。
		.o_gp_read_status_ready(flag_core_gp_read_status_ready), // 生产实例的o_gp_read_status_ready连接：预取器允许消费本次MM2S诊断。
		.i_gp_read_status(i_gp_read_status),    // 生产实例的i_gp_read_status连接：头和双表均要求读应答等于80。
		.o_gp_write_cmd_valid(flag_core_gp_write_cmd_valid), // 生产实例的o_gp_write_cmd_valid连接：全网计时S2MM事务发布。
		.i_gp_write_cmd_ready(flag_core_gp_write_cmd_ready), // 生产实例的i_gp_write_cmd_ready连接：GP后端能够保存统计首址。
		.o_gp_write_cmd_data(gp_write_cmd_data_o), // 生产实例的o_gp_write_cmd_data连接：十六字节运行记录的完整写指令。
		.o_gp_write_data_valid(flag_core_gp_write_data_valid), // 生产实例的o_gp_write_data_valid连接：待回写的周期低高半字及诊断word有效。
		.i_gp_write_data_ready(flag_core_gp_write_data_ready), // 生产实例的i_gp_write_data_ready连接：统计区后端接收当前32位结果。
		.o_gp_write_data(gp_write_data_o),      // 生产实例的o_gp_write_data连接：冻结的总周期或运行状态字。
		.o_gp_write_keep(gp_write_keep_o),      // 生产实例的o_gp_write_keep连接：运行记录完整word的四字节使能。
		.o_gp_write_last(gp_write_last_o),      // 生产实例的o_gp_write_last连接：仅第四个统计word置位结束。
		.i_gp_write_status_valid(flag_core_gp_write_status_valid), // 生产实例的i_gp_write_status_valid连接：GP已完成周期记录的DDR提交。
		.o_gp_write_status_ready(flag_core_gp_write_status_ready), // 生产实例的o_gp_write_status_ready连接：分发器检查末次统计写应答。
		.i_gp_write_status(i_gp_write_status),  // 生产实例的i_gp_write_status连接：最终整网done依赖精确成功写状态。
		.o_feature_cmd_valid(flag_core_feature_cmd_valid), // 生产实例的o_feature_cmd_valid连接：新扫描或安全覆盖的HP0搬运资格。
		.i_feature_cmd_ready(flag_core_feature_cmd_ready), // 生产实例的i_feature_cmd_ready连接：三行特征DMA能接收新的HWC地址。
		.o_feature_cmd_data(feature_cmd_data_o), // 生产实例的o_feature_cmd_data连接：当前真实行向量的物理读取指令。
		.i_feature_data_valid(flag_core_feature_data_valid), // 生产实例的i_feature_data_valid连接：HP0到达四个INT16原始特征。
		.o_feature_data_ready(flag_core_feature_data_ready), // 生产实例的o_feature_data_ready连接：缓存写入授权后接收特征beat。
		.i_feature_data(i_feature_data),        // 生产实例的i_feature_data连接：待拆成行bank内容的64位向量。
		.i_feature_keep(i_feature_keep),        // 生产实例的i_feature_keep连接：特征读要求八字节全有效。
		.i_feature_last(i_feature_last),        // 生产实例的i_feature_last连接：输入行或向量块的搬运尾标签。
		.i_feature_status_valid(flag_core_feature_status_valid), // 生产实例的i_feature_status_valid连接：HP0扫描搬运状态已返回。
		.o_feature_status_ready(flag_core_feature_status_ready), // 生产实例的o_feature_status_ready连接：特征控制器核实行数据事务。
		.i_feature_status(i_feature_status),    // 生产实例的i_feature_status连接：缓存扫描完成必须有成功HP0诊断。
		.o_weight_cmd_valid(flag_core_weight_cmd_valid), // 生产实例的o_weight_cmd_valid连接：当前组tile权重或组偏置的HP1装载资格。
		.i_weight_cmd_ready(flag_core_weight_cmd_ready), // 生产实例的i_weight_cmd_ready连接：私有核DMA准备接受新块首址。
		.o_weight_cmd_data(weight_cmd_data_o),  // 生产实例的o_weight_cmd_data连接：CU-major九bank物理布局的装载指令。
		.i_weight_data_valid(flag_core_weight_data_valid), // 生产实例的i_weight_data_valid连接：HP1返回可拆为两次pair的核参数。
		.o_weight_data_ready(flag_core_weight_data_ready), // 生产实例的o_weight_data_ready连接：核bank写通道空闲时接收新参数beat。
		.i_weight_data(i_weight_data),          // 生产实例的i_weight_data连接：低高32位分别形成C2原生pair内容。
		.i_weight_keep(i_weight_keep),          // 生产实例的i_weight_keep连接：权重装载每次验证全八字节使能。
		.i_weight_last(i_weight_last),          // 生产实例的i_weight_last连接：当前核块或偏置块已到数据尾。
		.i_weight_status_valid(flag_core_weight_status_valid), // 生产实例的i_weight_status_valid连接：私有核填充DMA报告传输结果。
		.o_weight_status_ready(flag_core_weight_status_ready), // 生产实例的o_weight_status_ready连接：HP1诊断归属唯一在途装载。
		.i_weight_status(i_weight_status),      // 生产实例的i_weight_status连接：只有精确80状态能放行weight_ready。
		.o_output_cmd_valid(flag_core_output_cmd_valid), // 生产实例的o_output_cmd_valid连接：输出组当前空间位置的HP2回写资格。
		.i_output_cmd_ready(flag_core_output_cmd_ready), // 生产实例的i_output_cmd_ready连接：结果DMA接收当前像素目标地址。
		.o_output_cmd_data(output_cmd_data_o),  // 生产实例的o_output_cmd_data连接：按Cout_padded跨度产生的S2MM写指令。
		.o_output_data_valid(flag_core_output_data_valid), // 生产实例的o_output_data_valid连接：量化四lane向DDR提交的有效拍。
		.i_output_data_ready(flag_core_output_data_ready), // 生产实例的i_output_data_ready连接：HP2后端具备当前结果beat接收容量。
		.o_output_data(output_data_o),          // 生产实例的o_output_data连接：尾lane清零后的四个有符号结果。
		.o_output_keep(output_keep_o),          // 生产实例的o_output_keep连接：物理结果存储始终写满八字节。
		.o_output_last(output_last_o),          // 生产实例的o_output_last连接：像素或FC分块的最后数据拍。
		.i_output_status_valid(flag_core_output_status_valid), // 生产实例的i_output_status_valid连接：HP2已返回当前写事务状态。
		.o_output_status_ready(flag_core_output_status_ready), // 生产实例的o_output_status_ready连接：输出屏障独立记账当前DDR写响应。
		.i_output_status(i_output_status)       // 生产实例的i_output_status连接：只有成功结果写应答能推进层完成。
	);

endmodule
