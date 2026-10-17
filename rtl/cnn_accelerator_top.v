`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/10 00:00:00
// Design Name:     cnn_accelerator_top
// Module Name:     cnn_accelerator_top
// Description:     description/cnn_accelerator_top_Design.pdf
// Simulations:     testbench/vivado/2021.1/cnn_accelerator_top
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/cnn_accelerator_top_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/10 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/10       V1.0        Codex             Create cnn_accelerator_top production integration.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月10日
// 设计名称:        cnn_accelerator_top
// 模块名称:        cnn_accelerator_top
// 模块说明:        Description/cnn_accelerator_top_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/cnn_accelerator_top
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/cnn_accelerator_top_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月10日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月10日   V1.0        Codex             创建微型网络生产集成接口

module cnn_accelerator_top
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
	input i_gp_reset_done,                      // GP取消/复位应答，收到请求后同步给出。
	input i_hp_reset_done,                      // 三个HP DataMover共同取消/复位应答。
	output o_gp_reset_req,                      // 软复位或错误记录结束后请求取消GP事务。
	output o_hp_reset_req,                      // 软复位或首错误后立即请求取消三个HP事务。
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
	output [71:0]o_gp_read_cmd_data,            // 分发器保持的七八位读指令。
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
	input [7:0]i_output_status                  // 只有成功结果写应答能推进层完成。
);

	//--------------模块实例化信号--------------//
	//配置派生连接
	wire [15:0]controller_error_code;           // 四模块局部诊断聚合。

	//用户接口
	wire [31:0]model_base;                      // PS模型头配置。
	wire [31:0]model_bytes;                     // PS实际文件长度配置。

	//用户接口
	wire [7:0]dist_error_code;                  // 模型范围/头/文件/写区/读流/读状态/层配置/依赖/超时/写状态/早写状态。
	wire [3:0]dist_error_source;                // 出错四控制器源；GP/模型错误为零。
	wire [15:0]dist_controller_error_code;      // 首控制器错误发生时锁存完整诊断。
	wire [63:0]dist_layer_cycles;               // 当前层start接受后的实际FCLK，包含暂停。
	wire [255:0]base_instruction;               // 论文基础指令原固定切片。
	wire [255:0]extension;                      // 工程扩展字原固定切片。
	wire [3:0]dist_layer_start;                 // 四模块同沿配置/start广播，只持续一个实际接受周期。

	//用户接口
	wire [3:0]cal_error_code;                   // 一配置二标签三依赖四事件。
	wire [9:0]group_index;                      // CAL当前完整组标签，卷积切组握手。
	wire [8:0]weight_group;                     // 输出组编号，覆盖4096核的空间模式
	wire [7:0]tile_index;                       // 512输入元素tile编号
	wire [15:0]tile_base;                       // 512对齐tile起始通道
	wire [15:0]update_row;                      // 将装入的真实输入行
	wire [11:0]update_col;                      // 输入列及缓存向量位置
	wire [1:0]update_bank;                      // 被授权覆盖的物理bank
	wire [12:0]feature_addr;                    // 双INT16 pair地址
	wire [7:0]weight_addr;                      // 共同读pair地址
	wire [1:0]mode;                             // 00/01为空间，10/11为旁路。
	wire [1:0]row_select;                       // 第一逻辑行的物理bank，3非法
	wire [2:0]row_mask;                         // 三逻辑行的空间有效位
	wire [1:0]pair_mask;                        // 两个逻辑通道有效位
	wire [71:0]lane_mask;                       // 低位连续非空前缀，空间模式至多12lane。
	wire [31:0]spatial_index;                   // 空间位置计数，多tile接B5低八位。
	wire [15:0]pool_post_block_row;             // 池化窗口真实首行。
	wire [7:0]pool_post_block;                  // 全局quad高位形成的通道块标签。
	wire [9:0]pool_post_block_channels;         // 当前尾块有效通道数。
	wire [15:0]pool_post_row;                   // Pool真实读行或流模式输入行。
	wire [11:0]pool_post_col;                   // 当前真实输入列。
	wire [1:0]pool_post_stage;                  // Pool四读阶段，流模式固定零。
	wire [6:0]pool_post_quad;                   // 当前块内四通道索引。
	wire [3:0]pool_post_mask;                   // 当前尾quad有效lane位。

	//用户接口
	wire [9:0]feature_group;                    // 完整十位输出组标签，覆盖卷积最大341与后处理最大1023
	wire [7:0]feature_tile;                     // 当前响应输入tile标签
	wire [1:0]f_bank;                           // 物理bank编号0到2
	wire [11:0]f_addr;                          // 四INT16 word地址
	wire [63:0]f_write_data;                    // 小端四通道写数据

	//用户接口
	wire [8:0]loaded_group;                     // 完成响应当前输出组标签
	wire [7:0]loaded_tile;                      // 完成响应当前输入tile标签
	wire [3455:0]bias_data;                     // 当前bundle每lane对应的48位偏置。
	wire [3:0]weight_error_code;                // 1配置2请求3数据帧4状态5偏置格式
	wire [3:0]w_cu;                             // CU编号0到7
	wire [3:0]w_bank;                           // 核bank编号0到8
	wire [7:0]w_addr;                           // 写pair地址
	wire [31:0]w_write_data;                    // 低到高两个INT16

	//用户接口
	wire [9:0]output_group_index;               // CONV/FC当前完整组标签；后处理固定零，不跟随输入quad。
	wire [3:0]output_error_code;                // 一配置二地址三状态四mask五早响应六依赖七组标签。

	//用户接口
	wire [95:0]feature_data;                    // 三个物理bank双INT16数据

	//用户接口
	wire [2303:0]weight_data;                   // 八份私有288位核参数，低位为CU0。

	//用户接口
	wire [95:0]selected_data;                   // 三行共享的双INT16特征。

	//用户接口
	wire [383:0]cu_zero;                        // 阵列所有空间48位点。
	wire [1151:0]cu_one;                        // 第一核列独立点积集合。
	wire [1151:0]cu_two;                        // 中央核列三lane输入。
	wire [1151:0]cu_three;                      // 末核列的补码打包结果。
	wire [7:0]column_commit;                    // 八个实际缓存列提交事件。
	wire [7:0]row_advance;                      // 共同扫描行末的bank轮换通知。

	//用户接口
	wire [3455:0]bundle_data;                   // CU-major低到高72个signed48点积。
	wire [71:0]concat_mask;                     // lane资格按低位前缀输出。

	//用户接口
	wire [63:0]spatial_data;                    // 空间私有队列64位四lane结果。
	wire [3:0]spatial_mask;                     // 空间私有队列四位参与标签。
	wire [63:0]bypass_data;                     // 旁路私有队列64位四lane结果。
	wire [3:0]bypass_mask;                      // 旁路私有队列四位参与标签。


	//池化读流和既有控制器的互斥所有权
	wire [3:0]pool_error_code;                  // 池化局部诊断复用Feature来源。
	wire [63:0]pool_result_data;                // 原始INT16池化结果。
	wire [3:0]pool_result_mask;                 // 尾quad低lane参与。
	wire [71:0]pool_cmd_data;                   // 池化真实HWC读取地址。
	wire [3:0]conv_error_code;                  // 原D0诊断保持原编码。
	wire [71:0]conv_cmd_data;                   // 原D0真实行扫描地址。
	wire [3455:0]result_bundle;                 // 池化四lane或现有完整CU结果。
	wire [3455:0]result_bias;                   // 池化不加偏置。
	wire [71:0]result_mask;                     // 池化至多四lane或原CONCAT标签。
	wire [1:0]result_mode;                      // 池化固定走空间FIFO。
	wire [5:0]result_quant_shift;               // 池化保持原INT16尺度。

	//-----------------计数信号-----------------//
	wire [31:0]cnt_output_commands;             // 实际命令握手累计，与数据及响应独立。
	wire [31:0]cnt_output_beats;                // HP2实际数据握手累计。
	wire [31:0]cnt_output_status;               // 精确80成功状态累计。
	wire [9:0]cnt_spatial;                      // 空间私有队列零至512的占用。
	wire [9:0]cnt_bypass;                       // 旁路私有队列零至512的占用。

	//----------------寄存器信号----------------//
	reg [95:0]reg_array_features;               // 阵列入口锁存完成行选择和尾lane屏蔽的三行特征。
	reg [2303:0]reg_array_weights;              // 与入口特征同沿捕获的八份私有核pair。
	reg [1:0]reg_array_mode;                    // 当前入口数据所属的计算模式。
	reg [1:0]reg_core_release = 0;              // 核心复位断言寄存、释放经过两个同域边界。

	//-----------------标志信号-----------------//
	//池化流与原HP0控制的互斥握手
	wire flag_pool;                             // 当前层为MAXPOOL，层间屏障后才切换。
	wire flag_pool_start_ready;                 // 池化配置和旧读流已经排空。
	wire flag_pool_busy;                        // 池化准备或HP0事务仍在途。
	wire flag_pool_error;                       // 池化首错误粘滞。
	wire flag_pool_block_ready;                 // 可以锁存真实行和通道块。
	wire flag_pool_block_done;                  // 当前块按需读流上下文已准备。
	wire flag_pool_post_ready;                  // 上一个角点DMA及算术已排空。
	wire flag_pool_post_done;                   // 四lane结果实际交给B5。
	wire flag_pool_result_valid;                // 已成功确认四角的最大值。
	wire flag_pool_cmd_valid;                   // 当前角点HP0命令有效。
	wire flag_pool_data_ready;                  // 池化当前输入beat许可。
	wire flag_pool_status_ready;                // 池化状态独立于CE记账。
	wire flag_conv_start_ready;                 // 原D0层开始许可。
	wire flag_conv_busy;                        // 原D0缓存装载状态。
	wire flag_conv_error;                       // 原D0首错误。
	wire flag_conv_cmd_valid;                   // 原D0的HP0命令。
	wire flag_conv_data_ready;                  // 原D0数据通道许可。
	wire flag_conv_status_ready;                // 原D0成功状态记账。
	wire flag_result_bundle_valid;              // 当前生产者独占B5入口。
	wire flag_result_quant_relu;                // 池化不附加激活。
	wire flag_result_first;                     // 池化绕过跨tile部分和。
	wire flag_result_last;                      // 四角后每个quad独立完成。

	reg flag_array_input_valid;                 // 入口有效标签随统一数据面使能推进。
	reg flag_array_input_first;                 // 首pair标记与锁存特征和权重对应。
	reg flag_array_input_last;                  // 本深度向量的末pair标签延后一拍。
	reg flag_array_input_row_last;              // 末列授权与同一入口数据一起提交阵列。
	//模块间完整数据与标签
	wire flag_ps_soft_reset;                    // PS同步共同复位请求。
	wire flag_ps_clear;                         // PS静止清状态事件。
	wire [3:0]flag_controller_ready;            // 四模块配置资格向量。
	wire [3:0]flag_controller_busy;             // 四模块在途资格向量。
	wire [3:0]flag_controller_error;            // 四模块首错来源向量。
	wire flag_compute_done;                     // CAL单FCLK完成脉冲，暂停也锁存。
	wire flag_packer_busy;                      // packer当前bundle或量化项未排空，不含FIFO占用。
	wire flag_spatial_empty;                    // 空间排空标志，只有没有待消费结果时置位。
	wire flag_bypass_empty;                     // 旁路排空标志，只有没有待消费结果时置位。
	wire flag_dist_start_ready;                 // 空闲且上次结果/工作及粘滞状态已清才允许启动。
	wire flag_dist_busy;                        // 从取头到最终GP写响应均为忙。
	wire flag_dist_runtime_error;               // GP周期记录没有成功提交，PS须读本地状态。
	wire flag_dist_abort;                       // 首错误后停止新层，并由顶层接入正在运行的控制器依赖终止。
	wire flag_core_rstn;                        // 寄存的核心低有效复位。
	wire flag_layer_start;                      // 四控制器同沿广播资格。
	wire flag_cal_start_ready;                  // 空闲接受新层，不覆盖旧任务。
	wire flag_cal_busy;                         // 当前层计算或组排空尚未结束。
	wire flag_cal_error;                        // 配置或依赖错误粘滞。
	wire flag_any_error;                        // 特征/权重首错或全网终止，阻止新计算。
	wire flag_scan_req;                         // 新group/tile三行扫描请求
	wire flag_scan_ready;                       // 扫描请求可接受
	wire flag_feature_ready;                    // 当前扫描初装或更新已成功完成
	wire flag_scan_finish;                      // CAL已消费本次扫描所有结果
	wire flag_scan_done;                        // 扫描消费完成单拍通知
	wire flag_load_req;                         // 当前group/tile完整装载请求
	wire flag_load_ready;                       // 可接受新的权重装载请求
	wire flag_weight_ready;                     // 全部权重pair和组偏置以及成功状态齐备
	wire flag_compute_idle;                     // CAL保证旧缓存读响应及计算流水已排空
	wire flag_update_req;                       // CAL已消费完整向量的覆盖授权
	wire flag_update_ready;                     // 可接收覆盖请求
	wire flag_update_done;                      // 当前覆盖成功完成单拍通知
	wire flag_feature_rd;                       // 同步读请求
	wire flag_feature_rd_ready;                 // 全局推进时接受读取
	wire flag_feature_response;                 // 同步读完成标志
	wire flag_weight_rd;                        // 共同读pair请求
	wire flag_weight_rd_ready;                  // 计算阶段接受条件
	wire flag_weight_response;                  // 同步读完成
	wire flag_datapath_ce;                      // 同步冻结八份完整CU。
	wire flag_pair_valid;                       // 真实缓存响应或虚拟列事件
	wire flag_array_ready;                      // 锁步CU共享运行资格，首CU代表共同许可。
	wire flag_pair_first;                       // tile的首通道对标签。
	wire flag_pair_last;                        // 深度向量末通道对标志。
	wire flag_pair_row_last;                    // 扫描末列的真实行结束标签。
	wire flag_column_valid;                     // 水平列有效位
	wire flag_column_commit;                    // 首CU代表统一实际列提交。
	wire flag_row_advance;                      // 首CU代表实际行尾提交。
	wire flag_cu_valid;                         // 首CU代表八路同拍结果。
	wire flag_bundle_ready;                     // packer空闲且所选队列未满才接受。
	wire flag_fifo_full;                        // busy时按锁存路由，否则按输入模式选择满状态。
	wire flag_group_write_done;                 // D3当前组全部HP2成功响应齐备。
	wire flag_bundle_valid;                     // 当前完整点积bundle有效。
	wire flag_first_tile;                       // 首输入tile覆盖旧部分和。
	wire flag_last_tile;                        // 末输入tile才量化并进入结果队列。
	wire flag_unused_cal_cmd_post_stream_req;   // ADD或GAP一次完整HWC流启动。
	wire flag_pool_post_block_req;              // Pool当前真实行与512通道块请求。
	wire flag_pool_post_valid;                  // 后处理坐标token有效。
	wire [6:0]flag_valid_lanes;                 // 空间合法1至8，旁路合法1至72。
	wire flag_feature_start_ready;              // 空闲可接收层配置
	wire flag_feature_busy;                     // 存在未结束的扫描或DMA
	wire flag_feature_error;                    // 粘滞错误，阻断新事务
	wire flag_f_wr;                             // 写请求有效
	wire flag_f_wr_ready;                       // 授权且无碰撞时接受写入
	wire flag_f_safe;                           // 当前word覆盖授权
	wire flag_weight_start_ready;               // 旧计算排空后可锁存新层
	wire flag_unused_weight_cmd_load_done;      // 本group/tile成功装载的FCLK单拍通知
	wire flag_w_load_enable;                    // 1装载0计算，互斥
	wire flag_weight_busy;                      // 配置检查或DMA及pair写仍在进行
	wire flag_weight_error;                     // 首个错误粘滞并阻断后续层
	wire flag_w_wr;                             // 原生pair写请求
	wire flag_w_wr_ready;                       // 合法装载请求接受条件
	wire flag_output_start_ready;               // 两个FIFO及packer排空后允许新层。
	wire flag_output_busy;                      // 当前层还有写回或完成屏障待处理。
	wire flag_output_group_done;                // CONV/FC本组或后处理整流最后成功状态齐备，保持至切组或新层。
	wire flag_output_error;                     // 首配置或运行错误粘滞。
	wire flag_spatial_valid;                    // 空间私有队列队首有效。
	wire flag_output_spatial_ready;             // 空间私有队列消费者允许队首出队。
	wire flag_bypass_valid;                     // 旁路私有队列队首有效。
	wire flag_output_bypass_ready;              // 旁路私有队列消费者允许队首出队。
	wire flag_selected_valid;                   // 本拍完整输入通道对有效。
	wire [7:0]flag_cu_valid_vector;             // 八份CU共同完成资格。
	wire flag_concat_valid;                     // 全部CU有效且任务至少启用一个lane。
	wire [7:0]flag_packer_spatial_index;        // B5固定空间槽输入。
	wire flag_result_relu;                      // 扩展配置的最终ReLU许可。
	wire flag_unused_result_output_spatial_fifo_full; // 空间私有队列占用512。
	wire flag_unused_result_output_bypass_fifo_full; // 旁路私有队列占用512。
	wire flag_ps_start;                         // PS单拍整网启动。
	wire flag_ps_ready;                         // 分发与核心/DMA全部可启动。
	wire flag_clear_ready;                      // GP/HP已经结束复位且分发器静止。
	wire flag_reset_busy;                       // 核心或DMA尚未完成重启。
	reg flag_reset_pending = 1;                 // 初始和软复位必须等待GP及HP取消应答。
	reg flag_reset_armed = 0;                   // 请求先保持一拍，避免误认上一次取消的高电平应答。
	reg flag_start_pending = 0;                 // 已接受软件启动保留到分发器实际接受，隔离下一拍ce暂停。

	//-----------------其他信号-----------------//
	//算子路由和量化派生数据
	wire [5:0]result_shift;                     // 扩展配置的最终量化右移。
	wire [3:0]feature_error_code;               // 1配置/2扫描/3覆盖/4帧/5状态
	wire [191:0]pool_lane_data;                 // 四个INT16显式符号扩展为B5的signed48。


	//用户接口

	//-----------------输出信号-----------------//
	//用户接口

	//用户接口
	wire axi_awready_o;                         // 对外单个地址缓存可接受。
	wire axi_wready_o;                          // 对外单个载荷缓存可接受。
	wire [1:0]axi_bresp_o;                      // 对外OKAY/SLVERR/DECERR响应。
	wire axi_bvalid_o;                          // 对外写提交响应，直到BREADY保持。
	wire axi_arready_o;                         // 对外单个读响应空闲。
	wire [31:0]axi_rdata_o;                     // 对外接受AR时锁存的寄存器值。
	wire [1:0]axi_rresp_o;                      // 对外读地址和对齐检查响应。
	wire axi_rvalid_o;                          // 对外读值和响应保持至RREADY。

	//用户接口
	wire gp_reset_req_o;                        // 取指通道取消控制的内部布线。
	wire hp_reset_req_o;                        // 数据面三路共同重启的请求节点。
	wire irq_o;                                 // 对外PS电平中断，清粘滞状态后撤销。
	wire busy_o;                                // 整网或同步复位等待。
	wire done_o;                                // 全部层及GP周期记录成功后粘滞完成。
	wire error_o;                               // 首错误粘滞，失败时不宣称done。
	wire [31:0]error_code_o;                    // PS读取的首诊断聚合。
	wire [7:0]current_layer_o;                  // 当前同层配对的基础/扩展缓存索引，含255。
	wire [63:0]cycles_o;                        // 从start接受至进入周期写回的实际FCLK数，包含取指及暂停。
	wire layer_done_o;                          // 最后成功状态及计算/packer/双FIFO屏障齐备的单FCLK通知。

	//用户接口
	wire gp_read_cmd_valid_o;                   // 对外模型头及双表读取资格。
	wire [71:0]gp_read_cmd_data_o;              // 对外分发器保持的七八位读指令。

	//用户接口
	wire gp_read_data_ready_o;                  // 对外基础或扩展记录的当前word入缓存许可。

	//用户接口
	wire gp_read_status_ready_o;                // 对外预取器允许消费本次MM2S诊断。

	//用户接口
	wire gp_write_cmd_valid_o;                  // 对外全网计时S2MM事务发布。
	wire [71:0]gp_write_cmd_data_o;             // 对外十六字节运行记录的完整写指令。

	//用户接口
	wire gp_write_data_valid_o;                 // 对外待回写的周期低高半字及诊断word有效。

	//用户接口
	wire [31:0]gp_write_data_o;                 // 对外冻结的总周期或运行状态字。
	wire [3:0]gp_write_keep_o;                  // 对外运行记录完整word的四字节使能。
	wire gp_write_last_o;                       // 对外仅第四个统计word置位结束。

	//用户接口
	wire gp_write_status_ready_o;               // 对外分发器检查末次统计写应答。

	//用户接口
	wire feature_cmd_valid_o;                   // 对外新扫描或安全覆盖的HP0搬运资格。
	wire [71:0]feature_cmd_data_o;              // 对外当前真实行向量的物理读取指令。

	//用户接口
	wire feature_data_ready_o;                  // 对外缓存写入授权后接收特征beat。

	//用户接口
	wire feature_status_ready_o;                // 对外特征控制器核实行数据事务。

	//用户接口
	wire weight_cmd_valid_o;                    // 对外当前组tile权重或组偏置的HP1装载资格。
	wire [71:0]weight_cmd_data_o;               // 对外CU-major九bank物理布局的装载指令。

	//用户接口
	wire weight_data_ready_o;                   // 对外核bank写通道空闲时接收新参数beat。

	//用户接口
	wire weight_status_ready_o;                 // 对外HP1诊断归属唯一在途装载。

	//用户接口
	wire output_cmd_valid_o;                    // 对外输出组当前空间位置的HP2回写资格。
	wire [71:0]output_cmd_data_o;               // 对外按Cout_padded跨度产生的S2MM写指令。

	//用户接口
	wire output_data_valid_o;                   // 对外量化四lane向DDR提交的有效拍。

	//用户接口
	wire [63:0]output_data_o;                   // 对外尾lane清零后的四个有符号结果。
	wire [7:0]output_keep_o;                    // 对外物理结果存储始终写满八字节。
	wire output_last_o;                         // 对外像素或FC分块的最后数据拍。

	//用户接口
	wire output_status_ready_o;                 // 对外输出屏障独立记账当前DDR写响应。

	//---------------其他信号连线---------------//
	//池化独占HP0，不启动卷积三行缓存和权重DMA。
	assign flag_pool = extension[171:168] == 4'd2; // 分发器在完整层屏障后才替换配置。
	assign flag_feature_start_ready = flag_pool ? flag_pool_start_ready : flag_conv_start_ready; // 层派发等待实际HP0所有者。
	assign flag_feature_busy = flag_conv_busy || flag_pool_busy; // 两条物理通路都排空才允许下一层。
	assign flag_feature_error = flag_conv_error || flag_pool_error; // 任一HP0故障触发统一取消。
	assign feature_error_code = flag_pool_error ? pool_error_code : conv_error_code; // 保持首故障诊断归属。
	assign feature_cmd_valid_o = flag_pool ? flag_pool_cmd_valid : flag_conv_cmd_valid; // 仅选中层可以发布HP0命令。
	assign feature_cmd_data_o = flag_pool ? pool_cmd_data : conv_cmd_data; // 对应所有者的稳定地址和BTT。
	assign feature_data_ready_o = flag_pool ? flag_pool_data_ready : flag_conv_data_ready; // 数据只能交给当前事务。
	assign feature_status_ready_o = flag_pool ? flag_pool_status_ready : flag_conv_status_ready; // 状态与读事务同源。
	assign pool_lane_data = {{32{pool_result_data[63]}},pool_result_data[63:48],{32{pool_result_data[47]}},pool_result_data[47:32],{32{pool_result_data[31]}},pool_result_data[31:16],{32{pool_result_data[15]}},pool_result_data[15:0]}; // 四lane保持signed48含义。
	assign result_bundle = flag_pool ? {3264'd0,pool_lane_data} : bundle_data; // 未使用的68个lane补零。
	assign result_bias = flag_pool ? 3456'd0 : bias_data; // 池化不使用上一层偏置。
	assign result_mask = flag_pool ? {68'd0,pool_result_mask} : lane_mask; // B5只消费真实池化lane。
	assign result_mode = flag_pool ? 2'd0 : mode; // 单quad池化路由到空间FIFO。
	assign flag_result_bundle_valid = flag_pool ? flag_pool_result_valid : flag_bundle_valid; // 各算子不争抢结果入口。
	assign result_quant_shift = flag_pool ? 6'd0 : result_shift; // 最大值不重新量化。
	assign flag_result_quant_relu = !flag_pool && flag_result_relu; // 全负池化窗口保持负值。
	assign flag_result_first = flag_pool || flag_first_tile; // 首末tile同时为一可绕过部分和RAM。
	assign flag_result_last = flag_pool || flag_last_tile; // 每个池化quad立即进入既有输出序列化。

	//用户接口
	assign result_shift = extension[165:160];   // 量化使用本层原工程扩展word。

	//其他信号连线
	assign flag_core_rstn = reg_core_release[1]; // 无组合软复位门，硬断言由该寄存器异步复位实现。
	assign flag_ps_ready = flag_dist_start_ready && flag_core_rstn && !flag_reset_pending && !flag_start_pending && !flag_ps_start; // 旧DMA未取消或已有待启动请求时不得重复提交。
	assign flag_reset_busy = flag_reset_pending || (!flag_core_rstn && !flag_dist_abort); // 错误保持阶段仅error可见，释放等待另作busy。
	assign flag_layer_start = dist_layer_start[0]; // 分发器已经保证四位同时接受。
	assign flag_any_error = flag_feature_error || flag_weight_error || flag_dist_abort; // 首错终止CAL及OUTPUT的新工作。
	assign flag_controller_ready = {flag_output_start_ready, flag_cal_start_ready, flag_weight_start_ready, flag_feature_start_ready}; // 低到高按Feature/Weight/CAL/OUTPUT排列。
	assign flag_controller_busy = {flag_output_busy, flag_cal_busy, flag_weight_busy, flag_feature_busy}; // 分发完成须等待全部模块静止。
	assign flag_controller_error = {flag_output_error, flag_cal_error, flag_weight_error, flag_feature_error}; // 原控制器自己拒绝未知算子配置。
	assign controller_error_code = {output_error_code, cal_error_code, weight_error_code, feature_error_code}; // 首错由分发器保存该完整快照。
	assign flag_column_commit = column_commit[0]; // 八CU统一推进，首事件代表安全覆盖资格。
	assign flag_row_advance = row_advance[0];   // 真实行尾通知传回CAL。
	assign flag_cu_valid = flag_cu_valid_vector[0]; // 完整结果与统一CU标签同拍。
	assign flag_packer_spatial_index = spatial_index[7:0]; // 已由CAL/软件预检限制多tile空间容量。
	assign flag_result_relu = extension[166];   // 每层ReLU只在最终量化之后作用。
	assign flag_group_write_done = flag_output_group_done && (flag_pool || output_group_index == group_index); // CAL仅接受本组所有HP2成功响应。

	//用户接口
	assign busy_o = flag_dist_busy || flag_reset_busy || flag_start_pending || flag_ps_start; // 运行、取消等待或已接受启动均保留软件参数。
	assign error_code_o = {dist_controller_error_code, dist_error_source, 3'd0, flag_dist_runtime_error, dist_error_code}; // 首错与未提交运行记录独立表示。
	assign gp_reset_req_o = flag_reset_pending || (flag_dist_abort && !flag_dist_busy); // GP保留到安全错误记录完成。
	assign hp_reset_req_o = flag_reset_pending || flag_dist_abort; // HP在首故障立即取消。

	//用户接口
	assign flag_clear_ready = !flag_dist_busy && !flag_reset_pending && i_gp_reset_done && i_hp_reset_done; // PS清首错之前要求两个外部复位完成。

	//---------------输出信号连线---------------//
	//用户接口

	//用户接口
	assign o_axi_awready = axi_awready_o;       // 外部单个地址缓存可接受。
	assign o_axi_wready = axi_wready_o;         // 外部单个载荷缓存可接受。
	assign o_axi_bresp = axi_bresp_o;           // 外部OKAY/SLVERR/DECERR响应。
	assign o_axi_bvalid = axi_bvalid_o;         // 外部写提交响应，直到BREADY保持。
	assign o_axi_arready = axi_arready_o;       // 外部单个读响应空闲。
	assign o_axi_rdata = axi_rdata_o;           // 外部接受AR时锁存的寄存器值。
	assign o_axi_rresp = axi_rresp_o;           // 外部读地址和对齐检查响应。
	assign o_axi_rvalid = axi_rvalid_o;         // 外部读值和响应保持至RREADY。

	//用户接口
	assign o_gp_reset_req = gp_reset_req_o;     // 把统计提交后的取消授权送给GP复位管理器。
	assign o_hp_reset_req = hp_reset_req_o;     // 向三个HP引擎广播数据面取消事件。
	assign o_irq = irq_o;                       // 外部PS电平中断，清粘滞状态后撤销。
	assign o_busy = busy_o;                     // 外部整网运行或DMA复位等待。
	assign o_done = done_o;                     // 外部最终GP成功状态后粘滞完成。
	assign o_error = error_o;                   // 外部首整网故障粘滞。
	assign o_error_code = error_code_o;         // 外部首错及来源/控制器诊断，字段与ERROR_CODE一致。
	assign o_current_layer = current_layer_o;   // 外部当前层调试号。
	assign o_cycles = cycles_o;                 // 外部整网真实周期。
	assign o_layer_done = layer_done_o;         // 对外观测DDR成功写屏障的完成边沿。

	//用户接口
	assign o_gp_read_cmd_valid = gp_read_cmd_valid_o; // 外部模型头及双表读取资格。
	assign o_gp_read_cmd_data = gp_read_cmd_data_o; // 外部分发器保持的七八位读指令。

	//用户接口
	assign o_gp_read_data_ready = gp_read_data_ready_o; // 模型缓存接收使能传回取指前端。

	//用户接口
	assign o_gp_read_status_ready = gp_read_status_ready_o; // 外部预取器允许消费本次MM2S诊断。

	//用户接口
	assign o_gp_write_cmd_valid = gp_write_cmd_valid_o; // 外部全网计时S2MM事务发布。
	assign o_gp_write_cmd_data = gp_write_cmd_data_o; // 外部十六字节运行记录的完整写指令。

	//用户接口
	assign o_gp_write_data_valid = gp_write_data_valid_o; // 统计载荷发布资格送往S2MM后端。

	//用户接口
	assign o_gp_write_data = gp_write_data_o;   // 外部冻结的总周期或运行状态字。
	assign o_gp_write_keep = gp_write_keep_o;   // 外部运行记录完整word的四字节使能。
	assign o_gp_write_last = gp_write_last_o;   // 外部仅第四个统计word置位结束。

	//用户接口
	assign o_gp_write_status_ready = gp_write_status_ready_o; // 外部分发器检查末次统计写应答。

	//用户接口
	assign o_feature_cmd_valid = feature_cmd_valid_o; // 外部新扫描或安全覆盖的HP0搬运资格。
	assign o_feature_cmd_data = feature_cmd_data_o; // 外部当前真实行向量的物理读取指令。

	//用户接口
	assign o_feature_data_ready = feature_data_ready_o; // 外部缓存写入授权后接收特征beat。

	//用户接口
	assign o_feature_status_ready = feature_status_ready_o; // 外部特征控制器核实行数据事务。

	//用户接口
	assign o_weight_cmd_valid = weight_cmd_valid_o; // 外部当前组tile权重或组偏置的HP1装载资格。
	assign o_weight_cmd_data = weight_cmd_data_o; // 外部CU-major九bank物理布局的装载指令。

	//用户接口
	assign o_weight_data_ready = weight_data_ready_o; // 外部核bank写通道空闲时接收新参数beat。

	//用户接口
	assign o_weight_status_ready = weight_status_ready_o; // 外部HP1诊断归属唯一在途装载。

	//用户接口
	assign o_output_cmd_valid = output_cmd_valid_o; // 外部输出组当前空间位置的HP2回写资格。
	assign o_output_cmd_data = output_cmd_data_o; // 外部按Cout_padded跨度产生的S2MM写指令。

	//用户接口
	assign o_output_data_valid = output_data_valid_o; // 外部量化四lane向DDR提交的有效拍。

	//用户接口
	assign o_output_data = output_data_o;       // 外部尾lane清零后的四个有符号结果。
	assign o_output_keep = output_keep_o;       // 外部物理结果存储始终写满八字节。
	assign o_output_last = output_last_o;       // 外部像素或FC分块的最后数据拍。

	//用户接口
	assign o_output_status_ready = output_status_ready_o; // 外部输出屏障独立记账当前DDR写响应。

	//-------------主要任务处理区域-------------//
	// 保持总线可用，仅对数据面同步断言复位；外部取消完成后两拍释放。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_reset_pending <= 1; flag_reset_armed <= 0; flag_start_pending <= 0; reg_core_release <= 0; // 硬复位立即撤销所有核心握手资格。
		end else if(flag_ps_soft_reset == 1'b1)begin
			flag_reset_pending <= 1; flag_reset_armed <= 0; flag_start_pending <= 0; reg_core_release <= 0; // 同步PS请求不能产生组合窄复位脉冲。
		end else begin
			if(flag_ps_start == 1'b1)begin
				flag_start_pending <= 1;        // CSR确认提交后不可因随后暂停丢掉启动。
			end else if(flag_start_pending == 1'b1 && flag_dist_start_ready == 1'b1)begin
				flag_start_pending <= 0;        // 分发器沿上真正接受后才释放待启动槽。
			end
			if(flag_reset_pending == 1'b1)begin
				flag_reset_armed <= 1;          // 外部复位管理器至少经历一沿来撤销旧应答或确认本次取消。
			end
			if(flag_reset_pending == 1'b1 && flag_reset_armed == 1'b1 && i_gp_reset_done == 1'b1 && i_hp_reset_done == 1'b1)begin
				flag_reset_pending <= 0;        // 两类DataMover均明确取消旧事务后结束等待。
			end
			if(flag_reset_pending == 1'b1 || flag_dist_abort == 1'b1)begin
				reg_core_release <= 0;          // 首错清核心资格但分发器/CSR仍保留首诊断及GP记录事务。
			end else begin
				reg_core_release <= {reg_core_release[0], 1'b1}; // 当前FCLK连续两沿建立数据面恢复资格。
			end
		end
	end

	// 不复位大宽度载荷，复位资格保证旧入口数据不能进入新计算。
	always@(posedge i_clk)begin
		if(flag_datapath_ce == 1'b1 && flag_selected_valid == 1'b1)begin
			reg_array_features <= selected_data; // 将BRAM及行选择路径截止在DSP乘法之前。
			reg_array_weights <= weight_data;   // 冻结本pair对应的全部私有权重。
			reg_array_mode <= mode;             // 避免模式与暂停中的入口载荷错配。
			flag_array_input_first <= flag_pair_first; // 保存向量首pair累加授权。
			flag_array_input_last <= flag_pair_last; // 保存深度完成标签。
			flag_array_input_row_last <= flag_pair_row_last; // 延迟同一末列的行角色推进标签。
		end
	end

	// 入口与CU共用推进使能；核心复位期间按时钟清除，硬复位立即清除。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_array_input_valid <= 1'b0;     // 硬复位立即撤销延迟载荷资格。
		end else if(flag_core_rstn == 1'b0)begin
			flag_array_input_valid <= 1'b0;     // CU保持复位时清除入口，释放保护期阻止旧pair进入。
		end else if(flag_datapath_ce == 1'b1)begin
			flag_array_input_valid <= flag_selected_valid; // 每个可推进沿保存输入有效或气泡。
		end
	end

	//--------------模块实例化区域--------------//
	//软件控制使用既有独立模块合同。
	cnn_control_regs control_regs(              // 完整连接cnn_control_regs。
		.i_clk(i_clk),                          // 软件控制：FCLK_CLK0统一时钟。
		.i_rstn(i_rstn),                        // 软件控制：低有效异步断言，上游同域同步释放。
		.i_axi_awaddr(i_axi_awaddr),            // 软件控制：寄存器字节偏移，独立接受AW。
		.i_axi_awvalid(i_axi_awvalid),          // 软件控制：写地址有效。
		.o_axi_awready(axi_awready_o),          // 软件控制：单个地址缓存可接受。
		.i_axi_wdata(i_axi_wdata),              // 软件控制：写寄存器载荷。
		.i_axi_wstrb(i_axi_wstrb),              // 软件控制：逐字节写入资格。
		.i_axi_wvalid(i_axi_wvalid),            // 软件控制：写载荷有效，允许早于AW。
		.o_axi_wready(axi_wready_o),            // 软件控制：单个载荷缓存可接受。
		.o_axi_bresp(axi_bresp_o),              // 软件控制：OKAY/SLVERR/DECERR响应。
		.o_axi_bvalid(axi_bvalid_o),            // 软件控制：写提交响应，直到BREADY保持。
		.i_axi_bready(i_axi_bready),            // 软件控制：主机接收写响应。
		.i_axi_araddr(i_axi_araddr),            // 软件控制：读字节偏移。
		.i_axi_arvalid(i_axi_arvalid),          // 软件控制：读地址有效。
		.o_axi_arready(axi_arready_o),          // 软件控制：单个读响应空闲。
		.o_axi_rdata(axi_rdata_o),              // 软件控制：接受AR时锁存的寄存器值。
		.o_axi_rresp(axi_rresp_o),              // 软件控制：读地址和对齐检查响应。
		.o_axi_rvalid(axi_rvalid_o),            // 软件控制：读值和响应保持至RREADY。
		.i_axi_rready(i_axi_rready),            // 软件控制：主机接收读响应。
		.i_start_ready(flag_ps_ready),          // 软件控制：分发器及DMA/核心复位释放后整网接受资格。
		.i_clear_ready(flag_clear_ready),       // 软件控制：DMA复位完成且整网静止才允许清首错。
		.i_busy(busy_o),                        // 软件控制：整网执行或复位应答等待。
		.i_done(done_o),                        // 软件控制：分发器粘滞成功。
		.i_error(error_o),                      // 软件控制：分发器粘滞首错。
		.i_fifo_stall(flag_fifo_full),          // 软件控制：结果FIFO满观测。
		.i_reset_busy(flag_reset_busy),         // 软件控制：DMA或计算核心正在共同复位。
		.i_runtime_error(flag_dist_runtime_error), // 软件控制：GP周期记录未成功提交。
		.i_error_code(error_code_o),            // 软件控制：低8位首错、bit8运行记录错、15:12来源、31:16控制器码。
		.i_current_layer(current_layer_o),      // 软件控制：当前缓存层号。
		.i_cycles(cycles_o),                    // 软件控制：实际整网FCLK计数。
		.o_model_base(model_base),              // 软件控制：PS配置，忙时写拒绝。
		.o_model_bytes(model_bytes),            // 软件控制：PS实际装载文件长度，忙时写拒绝。
		.o_start(flag_ps_start),                // 软件控制：合法CONTROL写提交产生单FCLK启动。
		.o_soft_reset(flag_ps_soft_reset),      // 软件控制：单FCLK软复位，不复位AXI-Lite本身。
		.o_clear_done(flag_ps_clear),           // 软件控制：静止且DMA已复位后清粘滞位。
		.o_irq(irq_o)                           // 软件控制：irq_enable且done/error为真时高电平。
	);

	//自主分发使用既有独立模块合同。
	instruction_distributor dispatcher(         // 完整连接instruction_distributor。
		.i_clk(i_clk),                          // 自主分发：与GP及四控制器共用FCLK。
		.i_rstn(i_rstn),                        // 自主分发：低有效异步复位，上游同域同步释放。
		.i_ce(i_ce),                            // 自主分发：冻结算法准备和分发；已发布GP事务继续握手。
		.i_soft_reset(flag_ps_soft_reset),      // 自主分发：GP及HP静止后与控制器/结果队列共同同步清控制。
		.i_start(flag_start_pending),           // 自主分发：PS仅一次启动整个模型。
		.i_clear_done(flag_ps_clear),           // 自主分发：空闲时清粘滞done/error；故障控制器还须共同复位。
		.i_model_base(model_base),              // 自主分发：64字节对齐的Instructions模型头地址。
		.i_model_bytes(model_bytes),            // 自主分发：PS实际装载的现有命令文件长度，不能取自未经校验的模型头。
		.i_controller_ready(flag_controller_ready), // 自主分发：bit0/1/2/3分别Feature/Weight/CAL/OUTPUT的配置资格。
		.i_controller_busy(flag_controller_busy), // 自主分发：四控制器尚有在途工作，完成层时分别检查。
		.i_controller_error(flag_controller_error), // 自主分发：四控制器粘滞错误源。
		.i_controller_error_code(controller_error_code), // 自主分发：四个四位诊断按Feature至OUTPUT从低到高排列。
		.i_compute_done(flag_compute_done),     // 自主分发：CAL单FCLK完成，跨暂停锁存。
		.i_output_done(layer_done_o),           // 自主分发：OUTPUT最终写成功通知，和compute_done分开锁存。
		.i_packer_busy(flag_packer_busy),       // 自主分发：结果级仍有未入队数据。
		.i_spatial_fifo_empty(flag_spatial_empty), // 自主分发：空间FIFO独立排空资格。
		.i_bypass_fifo_empty(flag_bypass_empty), // 自主分发：旁路FIFO独立排空资格。
		.o_start_ready(flag_dist_start_ready),  // 自主分发：空闲且上次结果/工作及粘滞状态已清才允许启动。
		.o_busy(flag_dist_busy),                // 自主分发：从取头到最终GP写响应均为忙。
		.o_done(done_o),                        // 自主分发：全部层及GP周期记录成功后粘滞完成。
		.o_error(error_o),                      // 自主分发：首错误粘滞，失败时不宣称done。
		.o_error_code(dist_error_code),         // 自主分发：模型范围/头/文件/写区/读流/读状态/层配置/依赖/超时/写状态/早写状态。
		.o_error_source(dist_error_source),     // 自主分发：出错四控制器源；GP/模型错误为零。
		.o_controller_error_code(dist_controller_error_code), // 自主分发：首控制器错误发生时锁存完整诊断。
		.o_runtime_error(flag_dist_runtime_error), // 自主分发：GP周期记录没有成功提交，PS须读本地状态。
		.o_abort(flag_dist_abort),              // 自主分发：首错误后停止新层，并由顶层接入正在运行的控制器依赖终止。
		.o_cycles(cycles_o),                    // 自主分发：从start接受至进入周期写回的实际FCLK数，包含取指及暂停。
		.o_layer_cycles(dist_layer_cycles),     // 自主分发：当前层start接受后的实际FCLK，包含暂停。
		.o_current_layer(current_layer_o),      // 自主分发：当前同层配对的基础/扩展缓存索引，含255。
		.o_base_instruction(base_instruction),  // 自主分发：BRAM同步读并锁存的现有基础配置，执行期间稳定。
		.o_extension(extension),                // 自主分发：同层工程扩展配置，保持原位序。
		.o_layer_start(dist_layer_start),       // 自主分发：四模块同沿配置/start广播，只持续一个实际接受周期。
		.o_read_cmd_valid(gp_read_cmd_valid_o), // 自主分发：GP MM2S命令发布后保持至READY。
		.i_read_cmd_ready(i_gp_read_cmd_ready), // 自主分发：GP MM2S接受命令。
		.o_read_cmd_data(gp_read_cmd_data_o),   // 自主分发：TAG0 Full命令，头64字节，双表各N×32字节。
		.i_read_data_valid(i_gp_read_data_valid), // 自主分发：GP 32位读数据有效。
		.o_read_data_ready(gp_read_data_ready_o), // 自主分发：真实读事务接收资格，不受ce暂停阻断。
		.i_read_data(i_gp_read_data),           // 自主分发：小端32位word；每条记录分别接收8个有效beat。
		.i_read_keep(i_gp_read_keep),           // 自主分发：必须为f。
		.i_read_last(i_gp_read_last),           // 自主分发：仅在当前读命令末beat拉高。
		.i_read_status_valid(i_gp_read_status_valid), // 自主分发：唯一在途GP MM2S状态。
		.o_read_status_ready(gp_read_status_ready_o), // 自主分发：数据发送及状态阶段接收，不受ce限制。
		.i_read_status(i_gp_read_status),       // 自主分发：精确80且晚于末读数据才成功。
		.o_write_cmd_valid(gp_write_cmd_valid_o), // 自主分发：GP S2MM周期记录命令有效，直到READY。
		.i_write_cmd_ready(i_gp_write_cmd_ready), // 自主分发：GP S2MM接受周期记录命令。
		.o_write_cmd_data(gp_write_cmd_data_o), // 自主分发：TAG0/EOF/INCR，写回固定16字节。
		.o_write_data_valid(gp_write_data_valid_o), // 自主分发：4个32位周期记录word，载荷保持至READY。
		.i_write_data_ready(i_gp_write_data_ready), // 自主分发：GP S2MM接受周期记录word。
		.o_write_data(gp_write_data_o),         // 自主分发：word0/1周期低/高，word2层号，word3诊断16位/错误8位/状态8位。
		.o_write_keep(gp_write_keep_o),         // 自主分发：固定f。
		.o_write_last(gp_write_last_o),         // 自主分发：第四个word对应当前命令TLAST。
		.i_write_status_valid(i_gp_write_status_valid), // 自主分发：GP周期记录S2MM状态。
		.o_write_status_ready(gp_write_status_ready_o), // 自主分发：接收实际周期写回状态，暂停也接收。
		.i_write_status(i_gp_write_status)      // 自主分发：精确80且晚于末写数据才提交done。
	);

	//计算调度使用既有独立模块合同。
	cal_cmd cal_control(                        // 完整连接cal_cmd。
		.i_clk(i_clk),                          // 计算调度：CAL与数据通路共用FCLK。
		.i_rstn(flag_core_rstn),                // 计算调度：低有效异步复位，上游同步释放。
		.i_ce(i_ce),                            // 计算调度：用户暂停保持在途坐标。
		.i_soft_reset(1'b0),                    // 计算调度：静止DMA后与CU共同同步复位。
		.i_start(flag_layer_start),             // 计算调度：与start_ready握手锁存现有配置。
		.i_base_instruction(base_instruction),  // 计算调度：基础指令原位序。
		.i_extension(extension),                // 计算调度：现有扩展字原位序。
		.o_start_ready(flag_cal_start_ready),   // 计算调度：空闲接受新层，不覆盖旧任务。
		.o_busy(flag_cal_busy),                 // 计算调度：当前层计算或组排空尚未结束。
		.o_compute_done(flag_compute_done),     // 计算调度：不再产生结果的FCLK单拍通知。
		.o_error(flag_cal_error),               // 计算调度：配置或依赖错误粘滞。
		.o_error_code(cal_error_code),          // 计算调度：一配置二标签三依赖四事件。
		.i_dependency_error(flag_any_error),    // 计算调度：D0、D1及后处理适配器错误汇总。
		.o_scan_req(flag_scan_req),             // 计算调度：D0当前group和tile初装请求。
		.i_scan_ready(flag_scan_ready),         // 计算调度：D0接受新扫描。
		.i_feature_ready(flag_feature_ready),   // 计算调度：当前D0数据和状态已齐备。
		.i_feature_group(feature_group),        // 计算调度：D0十位响应组标签。
		.i_feature_tile(feature_tile),          // 计算调度：D0响应tile标签。
		.o_scan_finish(flag_scan_finish),       // 计算调度：当前tile读与计算均已消费。
		.i_scan_done(flag_scan_done),           // 计算调度：D0结束单拍，暂停期间也锁存。
		.o_load_req(flag_load_req),             // 计算调度：D1当前group和tile装载请求。
		.i_load_ready(flag_load_ready),         // 计算调度：D1接受装载请求。
		.i_weight_ready(flag_weight_ready),     // 计算调度：当前权重和组偏置已齐备。
		.i_weight_group(loaded_group),          // 计算调度：D1仅卷积组标签，最大341。
		.i_weight_tile(loaded_tile),            // 计算调度：私有核载荷对应当前512通道块。
		.o_compute_idle(flag_compute_idle),     // 计算调度：没有读响应或计算流水时的装载授权。
		.o_group_index(group_index),            // 计算调度：卷积512组、后处理1024组完整标签。
		.o_weight_group(weight_group),          // 计算调度：仅CONV及FC接D1，合法最大341。
		.o_tile_index(tile_index),              // 计算调度：当前输入tile，FC最多128块。
		.o_tile_channel_base(tile_base),        // 计算调度：512对齐的tile起始通道。
		.o_update_req(flag_update_req),         // 计算调度：整行排空后逐向量安全覆盖授权。
		.i_update_ready(flag_update_ready),     // 计算调度：D0接受当前覆盖授权。
		.o_update_row(update_row),              // 计算调度：将装载的真实新输入行。
		.o_update_col(update_col),              // 计算调度：被覆盖物理行的真实列。
		.o_update_bank(update_bank),            // 计算调度：完整消费后释放的物理bank。
		.i_update_done(flag_update_done),       // 计算调度：覆盖成功单拍，暂停期间也锁存。
		.o_feature_rd_valid(flag_feature_rd),   // 计算调度：C0共同读请求，虚拟列不读。
		.i_feature_rd_ready(flag_feature_rd_ready), // 计算调度：C0同步读接受许可。
		.o_feature_rd_addr(feature_addr),       // 计算调度：当前tile紧密布局pair地址。
		.i_feature_out_valid(flag_feature_response), // 计算调度：C0与C2对齐的同步读响应。
		.o_weight_rd_valid(flag_weight_rd),     // 计算调度：C2所有bank共同读请求。
		.i_weight_rd_ready(flag_weight_rd_ready), // 计算调度：C2共同读接受许可。
		.o_weight_rd_addr(weight_addr),         // 计算调度：深度通道对零至255。
		.i_weight_out_valid(flag_weight_response), // 计算调度：C2同步读响应有效资格。
		.o_datapath_ce(flag_datapath_ce),       // 计算调度：寄存推进及CU结果holding冻结资格。
		.o_pair_valid(flag_pair_valid),         // 计算调度：同步读响应送C1和CU的输入资格。
		.i_array_ready(flag_array_ready),       // 计算调度：CU共同输入接受资格。
		.o_pair_first(flag_pair_first),         // 计算调度：当前向量首通道对。
		.o_pair_last(flag_pair_last),           // 计算调度：当前tile末通道对。
		.o_pair_row_last(flag_pair_row_last),   // 计算调度：末扫描列的末通道对行尾标签。
		.o_mode(mode),                          // 计算调度：三列、两列、单点或矩阵模式。
		.o_row_select(row_select),              // 计算调度：首逻辑行的物理bank，行内保持。
		.o_row_mask(row_mask),                  // 计算调度：当前纵向窗口真实行有效位。
		.o_column_valid(flag_column_valid),     // 计算调度：虚拟Padding置零但保留MAC事件。
		.o_pair_mask(pair_mask),                // 计算调度：奇数末pair高INT16清零。
		.i_column_commit(flag_column_commit),   // 计算调度：实际CU列缓存提交事件。
		.i_row_advance(flag_row_advance),       // 计算调度：实际CU行末提交事件。
		.i_cu_valid(flag_cu_valid),             // 计算调度：完整CU结果，holding可保持。
		.i_bundle_ready(flag_bundle_ready),     // 计算调度：B5接受当前完整结果的许可。
		.i_packer_busy(flag_packer_busy),       // 计算调度：B5尚未排空，不得切换组。
		.i_fifo_full(flag_fifo_full),           // 计算调度：当前FIFO满，下一拍寄存停顿。
		.i_group_write_done(flag_group_write_done), // 计算调度：D3当前组全部HP2成功响应齐备。
		.o_bundle_valid(flag_bundle_valid),     // 计算调度：命中stride的CU结果送B5。
		.o_lane_mask(lane_mask),                // 计算调度：当前组低位连续有效lane。
		.o_valid_lanes(flag_valid_lanes),       // 计算调度：当前输出组有效lane数，直接公开已寄存数量供生产CONCAT接线。
		.o_spatial_index(spatial_index),        // 计算调度：空间位置计数，多tile接B5低八位。
		.o_first_tile(flag_first_tile),         // 计算调度：首tile覆盖旧部分和。
		.o_last_tile(flag_last_tile),           // 计算调度：末tile才允许量化输出。
		.o_post_stream_req(flag_unused_cal_cmd_post_stream_req), // 计算调度：ADD或GAP一次完整HWC流启动。
		.i_post_stream_ready(1'b0),             // 计算调度：流适配器接受整层开始。
		.i_post_stream_done(1'b0),              // 计算调度：全部输入与DMA成功状态齐备。
		.o_post_block_req(flag_pool_post_block_req), // 计算调度：Pool当前真实行与512通道块请求。
		.i_post_block_ready(flag_pool_block_ready), // 计算调度：Pool缓存适配器接受当前块。
		.i_post_block_done(flag_pool_block_done), // 计算调度：绑定当前块坐标的装载成功单拍。
		.o_post_block_row(pool_post_block_row), // 计算调度：池化窗口真实首行。
		.o_post_block(pool_post_block),         // 计算调度：全局quad高位形成的通道块标签。
		.o_post_block_channels(pool_post_block_channels), // 计算调度：当前尾块有效通道数。
		.o_post_valid(flag_pool_post_valid),    // 计算调度：后处理坐标token有效。
		.i_post_ready(flag_pool_post_ready),    // 计算调度：Pool读接受或ADD双方流共同接受。
		.o_post_row(pool_post_row),             // 计算调度：Pool真实读行或流模式输入行。
		.o_post_col(pool_post_col),             // 计算调度：当前真实输入列。
		.o_post_stage(pool_post_stage),         // 计算调度：Pool四读阶段，流模式固定零。
		.o_post_quad(pool_post_quad),           // 计算调度：当前块内四通道索引。
		.o_post_mask(pool_post_mask),           // 计算调度：当前尾quad有效lane位。
		.i_post_done(flag_pool_post_done)       // 计算调度：Pool或ADD结果接受，GAP归约输出全部结束。
	);

	//特征搬运使用既有独立模块合同。
	feature_cmd feature_control(                // 完整连接feature_cmd。
		.i_clk(i_clk),                          // 特征搬运：所有控制与HP0接口共用FCLK_CLK0
		.i_rstn(flag_core_rstn),                // 特征搬运：低有效异步复位，上游同步释放
		.i_ce(i_ce),                            // 特征搬运：冻结请求、数据、状态和缓存写
		.i_soft_reset(1'b0),                    // 特征搬运：同步清控制；上游先使DataMover静止
		.i_start(flag_layer_start && !flag_pool), // 特征搬运：锁存当前层A3指令
		.i_base_instruction(base_instruction),  // 特征搬运：A3论文基础指令
		.i_extension(extension),                // 特征搬运：A3工程扩展字
		.o_start_ready(flag_conv_start_ready),  // 特征搬运：空闲可接收层配置
		.i_scan_req(flag_scan_req),             // 特征搬运：新group/tile三行扫描请求
		.o_scan_ready(flag_scan_ready),         // 特征搬运：扫描请求可接受
		.i_group_index(group_index),            // 特征搬运：完整十位输出组标签，覆盖卷积最大341与后处理最大1023
		.i_tile_index(tile_index),              // 特征搬运：输入tile标识
		.i_tile_channel_base(tile_base),        // 特征搬运：512对齐tile起始通道
		.i_update_req(flag_update_req),         // 特征搬运：CAL已消费完整向量的覆盖授权
		.o_update_ready(flag_update_ready),     // 特征搬运：可接收覆盖请求
		.i_update_row(update_row),              // 特征搬运：将装入的真实输入行
		.i_update_col(update_col),              // 特征搬运：输入列及缓存向量位置
		.i_update_bank(update_bank),            // 特征搬运：被授权覆盖的物理bank
		.i_scan_finish(flag_scan_finish),       // 特征搬运：CAL已消费本次扫描所有结果
		.o_feature_ready(flag_feature_ready),   // 特征搬运：当前扫描初装或更新已成功完成
		.o_update_done(flag_update_done),       // 特征搬运：当前覆盖成功完成单拍通知
		.o_scan_done(flag_scan_done),           // 特征搬运：扫描消费完成单拍通知
		.o_group_index(feature_group),          // 特征搬运：扫描完成响应携带的已锁存组序号。
		.o_tile_index(feature_tile),            // 特征搬运：当前响应输入tile标签
		.o_busy(flag_conv_busy),                // 特征搬运：存在未结束的扫描或DMA
		.o_error(flag_conv_error),              // 特征搬运：粘滞错误，阻断新事务
		.o_error_code(conv_error_code),         // 特征搬运：1配置/2扫描/3覆盖/4帧/5状态
		.o_cmd_valid(flag_conv_cmd_valid),      // 特征搬运：HP0 Full DataMover命令有效
		.i_cmd_ready(i_feature_cmd_ready && !flag_pool), // 特征搬运：DataMover命令接受
		.o_cmd_data(conv_cmd_data),             // 特征搬运：TAG0/32位SADDR/EOF1/INCR/BTT
		.i_data_valid(i_feature_data_valid && !flag_pool), // 特征搬运：HP0 MM2S数据有效
		.o_data_ready(flag_conv_data_ready),    // 特征搬运：合法状态下根据缓存与ce反压
		.i_data(i_feature_data),                // 特征搬运：四INT16小端DDR数据
		.i_data_keep(i_feature_keep),           // 特征搬运：固定全字节有效
		.i_data_last(i_feature_last),           // 特征搬运：每向量末beat为1
		.i_status_valid(i_feature_status_valid && !flag_pool), // 特征搬运：DataMover8位状态有效
		.o_status_ready(flag_conv_status_ready), // 特征搬运：接受当前唯一未完成命令状态
		.i_status(i_feature_status),            // 特征搬运：OKAY及错误位和TAG
		.o_wr_valid(flag_f_wr),                 // 特征搬运：C0缓存完整word写请求
		.i_wr_ready(flag_f_wr_ready),           // 特征搬运：C0无读写冲突可接受
		.o_wr_safe(flag_f_safe),                // 特征搬运：锁存安全授权，仅用于本次地址
		.o_wr_bank(f_bank),                     // 特征搬运：C0物理bank
		.o_wr_addr(f_addr),                     // 特征搬运：C0四通道word地址
		.o_wr_data(f_write_data)                // 特征搬运：真实通道签名和显式零尾lane
	);

	//私有核装载使用既有独立模块合同。
	weight_cmd weight_control(                  // 完整连接weight_cmd。
		.i_clk(i_clk),                          // 私有核装载：权重控制与HP1接口共用FCLK_CLK0
		.i_rstn(flag_core_rstn),                // 私有核装载：低有效异步清控制，上游同域同步释放
		.i_ce(i_ce),                            // 私有核装载：统一暂停CAL请求、数据、状态和缓存写
		.i_soft_reset(1'b0),                    // 私有核装载：DataMover静止后同步清本地控制
		.i_start(flag_layer_start && !flag_pool), // 私有核装载：锁存当前层完整A3指令
		.o_start_ready(flag_weight_start_ready), // 私有核装载：旧计算排空后可锁存新层
		.i_base_instruction(base_instruction),  // 私有核装载：A3论文256位基础指令
		.i_extension(extension),                // 私有核装载：A3工程256位扩展字
		.i_compute_idle(flag_compute_idle),     // 私有核装载：CAL保证旧缓存读响应及计算流水已排空
		.i_load_req(flag_load_req),             // 私有核装载：当前group/tile完整装载请求
		.o_load_ready(flag_load_ready),         // 私有核装载：可接受新的权重装载请求
		.i_group_index(weight_group),           // 私有核装载：输出组编号，覆盖4096核的空间模式
		.i_tile_index(tile_index),              // 私有核装载：512输入元素tile编号
		.o_weight_ready(flag_weight_ready),     // 私有核装载：全部权重pair和组偏置以及成功状态齐备
		.o_load_done(flag_unused_weight_cmd_load_done), // 私有核装载：本group/tile成功装载的FCLK单拍通知
		.o_group_index(loaded_group),           // 私有核装载：完成响应当前输出组标签
		.o_tile_index(loaded_tile),             // 私有核装载：完成响应当前输入tile标签
		.o_bias_data(bias_data),                // 私有核装载：低到高72个signed48偏置，空间模式仅低8lane有效
		.o_load_enable(flag_w_load_enable),     // 私有核装载：C2装载阶段禁止读，ready后允许计算读
		.o_busy(flag_weight_busy),              // 私有核装载：配置检查或DMA及pair写仍在进行
		.o_error(flag_weight_error),            // 私有核装载：首个错误粘滞并阻断后续层
		.o_error_code(weight_error_code),       // 私有核装载：1配置2请求3数据帧4状态5偏置格式
		.o_cmd_valid(weight_cmd_valid_o),       // 私有核装载：HP1 Full DataMover命令有效
		.i_cmd_ready(i_weight_cmd_ready),       // 私有核装载：HP1命令接受许可
		.o_cmd_data(weight_cmd_data_o),         // 私有核装载：TAG0、32位SADDR、EOF1、INCR及BTT
		.i_data_valid(i_weight_data_valid),     // 私有核装载：HP1 MM2S当前64位word有效
		.o_data_ready(weight_data_ready_o),     // 私有核装载：本地接收缓冲空闲且ce推进
		.i_data(i_weight_data),                 // 私有核装载：小端四INT16权重或一项INT64偏置
		.i_data_keep(i_weight_keep),            // 私有核装载：全word有效字节固定ff
		.i_data_last(i_weight_last),            // 私有核装载：当前权重块或偏置组的最后beat
		.i_status_valid(i_weight_status_valid), // 私有核装载：HP1 DataMover当前命令状态有效
		.o_status_ready(weight_status_ready_o), // 私有核装载：接收当前唯一命令的状态
		.i_status(i_weight_status),             // 私有核装载：TAG0成功须为80，其余锁存错误
		.o_wr_valid(flag_w_wr),                 // 私有核装载：C2原生32位pair写请求
		.i_wr_ready(flag_w_wr_ready),           // 私有核装载：C2接受当前pair写入
		.o_wr_cu(w_cu),                         // 私有核装载：目标CU零至十一
		.o_wr_bank(w_bank),                     // 私有核装载：目标bank零至八
		.o_wr_addr(w_addr),                     // 私有核装载：bank内双通道pair地址零至255
		.o_wr_data(w_write_data)                // 私有核装载：当前低高半word及逻辑边界补零
	);

	//结果写回使用既有独立模块合同。
	output_cmd output_control(                  // 完整连接output_cmd。
		.i_clk(i_clk),                          // 结果写回：与HP2及结果队列共用FCLK。
		.i_rstn(flag_core_rstn),                // 结果写回：低有效异步复位，上游同域同步释放。
		.i_ce(i_ce),                            // 结果写回：暂停准备和新出队，已发布AXIS事务仍正常握手。
		.i_soft_reset(1'b0),                    // 结果写回：先静止DataMover，再与生产者及FIFO共同同步复位。
		.i_start(flag_layer_start),             // 结果写回：空闲时锁存当前层完整指令。
		.i_base_instruction(base_instruction),  // 结果写回：论文基础指令原固定切片。
		.i_extension(extension),                // 结果写回：工程扩展字原固定切片。
		.o_start_ready(flag_output_start_ready), // 结果写回：两个FIFO及packer排空后允许新层。
		.o_busy(flag_output_busy),              // 结果写回：当前层还有写回或完成屏障待处理。
		.i_group_index(group_index),            // 结果写回：CAL当前完整组标签，卷积切组握手。
		.o_group_index(output_group_index),     // 结果写回：CONV/FC当前完整组标签；后处理固定零，不跟随输入quad。
		.o_group_write_done(flag_output_group_done), // 结果写回：CONV/FC本组或后处理整流最后成功状态齐备，保持至切组或新层。
		.i_compute_done(flag_compute_done),     // 结果写回：CAL单FCLK完成脉冲，暂停也锁存。
		.i_packer_busy(flag_packer_busy),       // 结果写回：B5有尚未入队的结果，禁止完成层。
		.i_dependency_error(flag_any_error),    // 结果写回：CAL或结果通路错误，粘滞终止任务。
		.o_output_done(layer_done_o),           // 结果写回：最后成功状态及计算/packer/双FIFO屏障齐备的单FCLK通知。
		.o_error(flag_output_error),            // 结果写回：首配置或运行错误粘滞。
		.o_error_code(output_error_code),       // 结果写回：一配置二地址三状态四mask五早响应六依赖七组标签。
		.o_commands_accepted(cnt_output_commands), // 结果写回：实际命令握手累计，与数据及响应独立。
		.o_data_beats(cnt_output_beats),        // 结果写回：HP2实际数据握手累计。
		.o_responses_ok(cnt_output_status),     // 结果写回：精确80成功状态累计。
		.i_spatial_fifo_valid(flag_spatial_valid), // 结果写回：空间及后处理结果队首有效。
		.o_spatial_fifo_ready(flag_output_spatial_ready), // 结果写回：仅当前选择路径允许一个队首进入holding。
		.i_spatial_fifo_data(spatial_data),     // 结果写回：空间队首四个INT16低lane在低位。
		.i_spatial_fifo_mask(spatial_mask),     // 结果写回：当前quad有效lane前缀。
		.i_spatial_fifo_empty(flag_spatial_empty), // 结果写回：空间私有FIFO没有待写结果。
		.i_bypass_fifo_valid(flag_bypass_valid), // 结果写回：1x1或矩阵结果队首有效。
		.o_bypass_fifo_ready(flag_output_bypass_ready), // 结果写回：仅旁路层允许该队首出队。
		.i_bypass_fifo_data(bypass_data),       // 结果写回：旁路队首四个INT16。
		.i_bypass_fifo_mask(bypass_mask),       // 结果写回：旁路当前quad有效lane前缀。
		.i_bypass_fifo_empty(flag_bypass_empty), // 结果写回：旁路私有FIFO没有待写结果。
		.o_cmd_valid(output_cmd_valid_o),       // 结果写回：HP2 Full S2MM命令VALID保持到接受，不受ce撤销。
		.i_cmd_ready(i_output_cmd_ready),       // 结果写回：HP2接受当前稳定命令。
		.o_cmd_data(output_cmd_data_o),         // 结果写回：TAG0、32位SADDR、EOF1、INCR和23位BTT。
		.o_data_valid(output_data_valid_o),     // 结果写回：holding数据VALID保持到HP2接受。
		.i_data_ready(i_output_data_ready),     // 结果写回：HP2流数据接受许可。
		.o_data(output_data_o),                 // 结果写回：mask无效lane清零后的四个INT16。
		.o_data_keep(output_keep_o),            // 结果写回：补齐完整64位beat，始终ff。
		.o_data_last(output_last_o),            // 结果写回：当前命令最后一个实际数据beat。
		.i_status_valid(i_output_status_valid), // 结果写回：当前唯一在途S2MM状态有效。
		.o_status_ready(output_status_ready_o), // 结果写回：接收当前事务状态，即使用户暂停。
		.i_status(i_output_status)              // 结果写回：TAG0且OKAY精确80，其他状态报错。
	);

	//三行缓存使用既有独立模块合同。
	feature_buffer features(                    // 完整连接feature_buffer。
		.i_clk(i_clk),                          // 三行缓存：统一时钟
		.i_rstn(flag_core_rstn),                // 三行缓存：低有效异步清控制，上游同域同步释放；RAM及RAM读数据不复位
		.i_ce(flag_datapath_ce),                // 三行缓存：统一推进使能
		.i_wr_valid(flag_f_wr),                 // 三行缓存：写请求有效
		.i_wr_safe(flag_f_safe),                // 三行缓存：当前word覆盖授权
		.i_wr_bank(f_bank),                     // 三行缓存：物理bank编号0到2
		.i_wr_addr(f_addr),                     // 三行缓存：四INT16 word地址
		.i_wr_data(f_write_data),               // 三行缓存：小端四通道写数据
		.o_wr_ready(flag_f_wr_ready),           // 三行缓存：授权且无碰撞时接受写入
		.i_rd_valid(flag_feature_rd),           // 三行缓存：同步读请求
		.i_rd_addr(feature_addr),               // 三行缓存：双INT16 pair地址
		.o_rd_ready(flag_feature_rd_ready),     // 三行缓存：全局推进时接受读取
		.o_out_valid(flag_feature_response),    // 三行缓存：同步读完成标志
		.o_out_data(feature_data)               // 三行缓存：低到高三个物理bank双通道数据
	);

	//核缓存使用既有独立模块合同。
	kernel_buffer weights(                      // 完整连接kernel_buffer。
		.i_clk(i_clk),                          // 核缓存：统一计算时钟
		.i_rstn(flag_core_rstn),                // 核缓存：低有效异步清valid，上游同域同步释放；RAM与读数据不复位
		.i_ce(flag_datapath_ce),                // 核缓存：全局推进
		.i_load_enable(flag_w_load_enable),     // 核缓存：1装载0计算，互斥
		.i_wr_valid(flag_w_wr),                 // 核缓存：原生pair写请求
		.i_wr_cu(w_cu),                         // 核缓存：CU编号0到7
		.i_wr_bank(w_bank),                     // 核缓存：核bank编号0到8
		.i_wr_addr(w_addr),                     // 核缓存：写pair地址
		.i_wr_data(w_write_data),               // 核缓存：低到高两个INT16
		.o_wr_ready(flag_w_wr_ready),           // 核缓存：合法装载请求接受条件
		.i_rd_valid(flag_weight_rd),            // 核缓存：共同读pair请求
		.i_rd_addr(weight_addr),                // 核缓存：共同读pair地址
		.o_rd_ready(flag_weight_rd_ready),      // 核缓存：计算阶段接受条件
		.o_out_valid(flag_weight_response),     // 核缓存：同步读完成
		.o_out_data(weight_data)                // 核缓存：低到高CU-major/K-major共72个pair
	);

	//行选择使用既有独立模块合同。
	fout_selector select_features(              // 完整连接fout_selector。
		.i_in_valid(flag_pair_valid),           // 行选择：真实缓存响应或虚拟列事件
		.i_in_data(feature_data),               // 行选择：三个物理bank双INT16数据
		.i_mode(mode),                          // 行选择：四种计算模式编码
		.i_row_select(row_select),              // 行选择：第一逻辑行的物理bank，3非法
		.i_row_mask(row_mask),                  // 行选择：三逻辑行的空间有效位
		.i_column_valid(flag_column_valid),     // 行选择：水平列有效位
		.i_pair_mask(pair_mask),                // 行选择：两个逻辑通道有效位
		.o_out_valid(flag_selected_valid),      // 行选择：输入有效且角色合法
		.o_out_data(selected_data)              // 行选择：三路选定特征，CU位序
	);

	//并行计算使用既有独立模块合同。
	compute_array compute_core(                 // 完整连接compute_array。
		.i_clk(i_clk),                          // 并行计算：FCLK_CLK0域统一计算时钟。
		.i_rstn(flag_core_rstn),                // 并行计算：低有效异步复位，上游统一同步释放。
		.i_ce(flag_datapath_ce),                // 并行计算：同步冻结八份完整CU。
		.i_in_valid(flag_array_input_valid),    // 并行计算：寄存入口的pair有效标签。
		.i_first(flag_array_input_first),       // 并行计算：与入口载荷同沿锁存的首pair。
		.i_last(flag_array_input_last),         // 并行计算：延迟后的深度末pair授权。
		.i_row_last(flag_array_input_row_last), // 并行计算：延迟后的末列行结束资格。
		.i_mode(reg_array_mode),                // 并行计算：入口数据所对应的任务类别。
		.i_feature_data(reg_array_features),    // 并行计算：切断BRAM至DSP组合长路径的三行输入。
		.i_weight_data(reg_array_weights),      // 并行计算：同pair的八份私有核权重。
		.o_ready(flag_array_ready),             // 并行计算：锁步CU共享运行资格，首CU代表共同许可。
		.o_cu_valid(flag_cu_valid_vector),      // 并行计算：每个计算单元的完成标签。
		.o_zero(cu_zero),                       // 并行计算：八个空间48位点积。
		.o_one(cu_one),                         // 并行计算：所有CU第一核列的三lane结果。
		.o_two(cu_two),                         // 并行计算：每份中央核列的独立点积组。
		.o_three(cu_three),                     // 并行计算：末核列向量按CU编号聚合。
		.o_column_commit(column_commit),        // 并行计算：八个实际缓存列提交事件。
		.o_row_advance(row_advance)             // 并行计算：共同扫描行末的bank轮换通知。
	);

	//结果重排使用既有独立模块合同。
	concat concatenate(                         // 完整连接concat。
		.i_clk(i_clk),                          // 结果重排：配置预译码共享阵列时钟。
		.i_rstn(flag_core_rstn),                // 结果重排：异步清除全部lane选择，上游同步释放。
		.i_ce(i_ce),                            // 结果重排：暂停时任务配置保持原值。
		.i_mode(mode),                          // 结果重排：四模式在同一任务中固定。
		.i_valid_lanes(flag_valid_lanes),       // 结果重排：空间合法1至8，旁路合法1至72。
		.i_cu_valid(flag_cu_valid_vector),      // 结果重排：八份CU共同完成资格。
		.i_zero(cu_zero),                       // 结果重排：阵列所有空间48位点。
		.i_one(cu_one),                         // 结果重排：第一核列独立点积集合。
		.i_two(cu_two),                         // 结果重排：中央核列三lane输入。
		.i_three(cu_three),                     // 结果重排：末核列的补码打包结果。
		.o_bundle_valid(flag_concat_valid),     // 结果重排：全部CU有效且任务至少启用一个lane。
		.o_bundle_data(bundle_data),            // 结果重排：CU-major K0至K8固定72个48位结果。
		.o_lane_mask(concat_mask)               // 结果重排：lane资格按低位前缀输出。
	);

	//量化队列使用既有独立模块合同。
	result_output results(                      // 完整连接result_output。
		.i_clk(i_clk),                          // 量化队列：单时钟FCLK_CLK0上升沿。
		.i_rstn(flag_core_rstn),                // 量化队列：低有效异步清控制，上游同域同步释放，RAM不复位。
		.i_bundle_valid(flag_result_bundle_valid), // 量化队列：当前完整点积bundle有效。
		.o_bundle_ready(flag_bundle_ready),     // 量化队列：packer空闲且所选队列未满才接受。
		.i_bundle_data(result_bundle),          // 量化队列：CU-major低到高72个signed48点积。
		.i_bias_data(result_bias),              // 量化队列：当前bundle每lane对应的48位偏置。
		.i_lane_mask(result_mask),              // 量化队列：低位连续非空前缀，空间模式至多12lane。
		.i_mode(result_mode),                   // 量化队列：00/01为空间，10/11为旁路。
		.i_spatial_index(flag_packer_spatial_index), // 量化队列：跨tile空间槽编号，固定容量小于196。
		.i_first_tile(flag_result_first),       // 量化队列：首输入tile覆盖旧部分和。
		.i_last_tile(flag_result_last),         // 量化队列：末输入tile才量化并进入结果队列。
		.i_right_shift(result_quant_shift),     // 量化队列：量化加半舍入算术右移配置。
		.i_relu(flag_result_quant_relu),        // 量化队列：输出INT16可选负值抑制。
		.o_busy(flag_packer_busy),              // 量化队列：packer当前bundle或量化项未排空，不含FIFO占用。
		.o_fifo_full(flag_fifo_full),           // 量化队列：busy时按锁存路由，否则按输入模式选择满状态。
		.o_spatial_fifo_valid(flag_spatial_valid), // 量化队列：空间私有队列队首有效。
		.i_spatial_fifo_ready(flag_output_spatial_ready), // 量化队列：空间私有队列消费者允许队首出队。
		.o_spatial_fifo_data(spatial_data),     // 量化队列：空间私有队列64位四lane结果。
		.o_spatial_fifo_mask(spatial_mask),     // 量化队列：空间私有队列四位参与标签。
		.o_spatial_fifo_full(flag_unused_result_output_spatial_fifo_full), // 量化队列：空间私有队列占用512。
		.o_spatial_fifo_empty(flag_spatial_empty), // 量化队列：空间排空标志，只有没有待消费结果时置位。
		.o_spatial_fifo_count(cnt_spatial),     // 量化队列：空间私有队列零至512的占用。
		.o_bypass_fifo_valid(flag_bypass_valid), // 量化队列：旁路私有队列队首有效。
		.i_bypass_fifo_ready(flag_output_bypass_ready), // 量化队列：旁路私有队列消费者允许队首出队。
		.o_bypass_fifo_data(bypass_data),       // 量化队列：旁路私有队列64位四lane结果。
		.o_bypass_fifo_mask(bypass_mask),       // 量化队列：旁路私有队列四位参与标签。
		.o_bypass_fifo_full(flag_unused_result_output_bypass_fifo_full), // 量化队列：旁路私有队列占用512。
		.o_bypass_fifo_empty(flag_bypass_empty), // 量化队列：旁路排空标志，只有没有待消费结果时置位。
		.o_bypass_fifo_count(cnt_bypass)        // 量化队列：旁路私有队列零至512的占用。
	);

	// 按四角读流累计最大值，复用同一HP0和结果队列。
	pool_unit pool_core(                        // 完整连接池化读流与算术。
		.i_clk(i_clk),                          // 池化与生产核心共用FCLK。
		.i_rstn(flag_core_rstn),                // 共同复位隔离旧角点。
		.i_ce(i_ce),                            // 算法暂停，协议独立记账。
		.i_start(flag_layer_start && flag_pool), // 仅池化层锁存指令。
		.i_base_instruction(base_instruction),  // 复用原基础位布局。
		.i_extension(extension),                // 复用原扩展位布局。
		.o_start_ready(flag_pool_start_ready),  // 池化开始许可。
		.o_busy(flag_pool_busy),                // 池化在途状态。
		.o_error(flag_pool_error),              // 池化首错粘滞。
		.o_error_code(pool_error_code),         // 局部诊断复用Feature槽。
		.i_block_req(flag_pool_post_block_req), // CAL建立当前真实块。
		.o_block_ready(flag_pool_block_ready),  // 读流元数据接受。
		.i_block_row(pool_post_block_row),      // 本次读取窗口由CAL真实行坐标绑定。
		.i_block(pool_post_block),              // 全局512通道块。
		.i_block_channels(pool_post_block_channels), // 尾块有效通道数。
		.o_block_done(flag_pool_block_done),    // 读流上下文就绪。
		.i_post_valid(flag_pool_post_valid),    // 四角坐标有效。
		.o_post_ready(flag_pool_post_ready),    // 前一角点已经确认。
		.i_post_row(pool_post_row),             // 当前输入真实行。
		.i_post_col(pool_post_col),             // 当前输入真实列。
		.i_post_stage(pool_post_stage),         // 固定四角顺序。
		.i_post_quad(pool_post_quad),           // 块内quad索引。
		.i_post_mask(pool_post_mask),           // 尾lane有效位。
		.o_post_done(flag_pool_post_done),      // 结果实际交给B5。
		.o_result_valid(flag_pool_result_valid), // 完整窗口四lane结果。
		.i_result_ready(flag_bundle_ready),     // 复用既有B5反压。
		.o_result_data(pool_result_data),       // 原尺度signed INT16最大值。
		.o_result_mask(pool_result_mask),       // 无效lane已补零。
		.o_cmd_valid(flag_pool_cmd_valid),      // 独占HP0新命令。
		.i_cmd_ready(i_feature_cmd_ready && flag_pool), // 仅本层命令接受。
		.o_cmd_data(pool_cmd_data),             // 真实HWC角点地址。
		.i_data_valid(i_feature_data_valid && flag_pool), // 输入流归属池化。
		.o_data_ready(flag_pool_data_ready),    // 单角点完整beat许可。
		.i_data(i_feature_data),                // HP0四lane物理字。
		.i_data_keep(i_feature_keep),           // 必须完整八字节。
		.i_data_last(i_feature_last),           // 单beat命令末尾。
		.i_status_valid(i_feature_status_valid && flag_pool), // 当前池化读状态。
		.o_status_ready(flag_pool_status_ready), // 暂停期间仍保存状态。
		.i_status(i_feature_status)             // 只接受精确成功80。
	);

endmodule
