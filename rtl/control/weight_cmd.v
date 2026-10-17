`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     weight_cmd
// Module Name:     weight_cmd
// Description:     description/weight_cmd_Design.pdf
// Simulations:     testbench/vivado/2021.1/weight_cmd
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/weight_cmd_spec.md; docs/设计文档.md 4.4
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/09 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Codex             Create HP1 weight and bias load controller.
// 2026/10/09       V1.0        Codex             Use software weight count without geometry consistency check.
// 2026/10/09       V1.0        Codex             Register seven configuration stages without changing instructions.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月08日
// 设计名称:        weight_cmd
// 模块名称:        weight_cmd
// 模块说明:        Description/weight_cmd_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/weight_cmd
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/weight_cmd_spec.md; docs/设计文档.md 4.4
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月09日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             创建HP1权重与偏置装载控制器
// 2026年10月09日   V1.0        Codex             权重数量由软件保证，移除几何一致性重算
// 2026年10月09日   V1.0        Codex             配置计算分七拍寄存，保持指令格式

module weight_cmd
(
	//-----------------用户接口-----------------//
	input i_clk,                                // 权重控制与HP1接口共用FCLK_CLK0。
	input i_rstn,                               // 低有效异步清控制，上游同域同步释放。
	input i_ce,                                 // 统一暂停CAL请求、数据、状态和缓存写。
	input i_soft_reset,                         // DataMover静止后同步清本地控制。
	input i_start,                              // 锁存当前层完整A3指令。
	output o_start_ready,                       // 旧计算排空后可锁存新层。
	input [255:0]i_base_instruction,            // A3论文256位基础指令。
	input [255:0]i_extension,                   // A3工程256位扩展字。
	input i_compute_idle,                       // CAL保证旧缓存读响应及计算流水已排空。
	input i_load_req,                           // 当前group/tile完整装载请求。
	output o_load_ready,                        // 可接受新的权重装载请求。
	input [8:0]i_group_index,                   // 输出组编号，覆盖4096核的空间模式。
	input [7:0]i_tile_index,                    // 512输入元素tile编号。
	output o_weight_ready,                      // 全部权重pair和组偏置以及成功状态齐备。
	output o_load_done,                         // 本group/tile成功装载的FCLK单拍通知。
	output [8:0]o_group_index,                  // 完成响应当前输出组标签。
	output [7:0]o_tile_index,                   // 完成响应当前输入tile标签。
	output [3455:0]o_bias_data,                 // 低到高72个signed48偏置，空间模式仅低8lane有效。
	output o_load_enable,                       // C2装载阶段禁止读，ready后允许计算读。
	output o_busy,                              // 配置检查或DMA及pair写仍在进行。
	output o_error,                             // 首个错误粘滞并阻断后续层。
	output [3:0]o_error_code,                   // 1配置2请求3数据帧4状态5偏置格式。

	//CMD接口
	output o_cmd_valid,                         // HP1 Full DataMover命令有效。
	input i_cmd_ready,                          // HP1命令接受许可。
	output [71:0]o_cmd_data,                    // TAG0、32位SADDR、EOF1、INCR及BTT。
	input i_data_valid,                         // HP1 MM2S当前64位word有效。
	output o_data_ready,                        // 本地接收缓冲空闲且ce推进。
	input [63:0]i_data,                         // 小端四INT16权重或一项INT64偏置。
	input [7:0]i_data_keep,                     // 全word有效字节固定ff。
	input i_data_last,                          // 当前权重块或偏置组的最后beat。
	input i_status_valid,                       // HP1 DataMover当前命令状态有效。
	output o_status_ready,                      // 接收当前唯一命令的状态。
	input [7:0]i_status,                        // TAG0成功须为80，其余锁存错误。

	//WR接口
	output o_wr_valid,                          // C2原生32位pair写请求。
	input i_wr_ready,                           // C2接受当前pair写入。
	output [3:0]o_wr_cu,                        // 目标CU零至十一。
	output [3:0]o_wr_bank,                      // 目标bank零至八。
	output [7:0]o_wr_addr,                      // bank内双通道pair地址零至255。
	output [31:0]o_wr_data                      // 当前低高半word及逻辑边界补零。
);

	//---------------状态参数区域---------------//
	localparam ST_IDLE = 4'd0;                  // 层配置或安全装载请求等待态。
	localparam ST_CONFIG = 4'd1;                // 锁存组数分子、tile数量及字段边界。
	localparam ST_PREPARE = 4'd2;               // 已锁存块序号的命令地址准备态。
	localparam ST_COMMAND = 4'd3;               // HP1命令持续呈现并等待接收态。
	localparam ST_RECEIVE = 4'd4;               // 接收一笔权重beat或偏置word。
	localparam ST_WRITE = 4'd5;                 // 暂存beat分低高两个pair写入。
	localparam ST_WAIT = 4'd6;                  // 等待DMA成功状态与数据完成同时齐备。
	localparam ST_FINISH = 4'd7;                // 首tile追加偏置或发布装载完成。
	localparam ST_READY = 4'd8;                 // 当前group及tile权重可安全消费。
	localparam ST_ERROR = 4'd9;                 // 锁存错误并等待静止DMA后的复位。
	localparam ST_GROUPS = 4'd10;               // 独立寄存输出组数除法结果。
	localparam ST_BIAS_BASE = 4'd11;            // 寄存八lane对应的偏置长度。
	localparam ST_BIAS_BYTES = 4'd12;           // 寄存模式选择后的整层偏置长度。
	localparam ST_LIMIT = 4'd13;                // 寄存宽化权重和偏置DDR末址。
	localparam ST_CHECK = 4'd14;                // 寄存数量与DDR范围比较结果。
	localparam ST_COMMIT = 4'd15;               // 仅已寄存检查结果允许配置提交。

	//-----------------计数信号-----------------//
	reg [31:0]cnt_weight = 0;                   // 基础低24位加扩展高8位的完整权重元素数。
	reg [13:0]cnt_beat = 0;                     // 权重固定9216个64位beat。
	reg [6:0]cnt_bias = 0;                      // 最多72个64位偏置。
	reg [7:0]cnt_pair = 0;                      // 每bank256个双INT16地址。
	reg [3:0]cnt_cu = 0;                        // CU-major、bank-major遍历。
	reg [3:0]cnt_bank = 0;                      // 当前CU内零至八的核bank游标。

	//----------------状态机信号----------------//
	reg [3:0]state_current = 0;                 // 事务当前状态。
	reg [3:0]state_next = 0;                    // 独立组合逻辑决定下一状态。

	//----------------寄存器信号----------------//
	reg [31:0]reg_inputs = 0;                   // 锁存A3完整输入深度和地址。
	reg [31:0]reg_weight_addr = 0;              // A3文件当前层权重区起始DDR地址。
	reg [31:0]reg_bias_addr = 0;                // A3文件当前层所有输出组偏置起址。
	reg [12:0]reg_outputs = 0;                  // K_NUM零编码还原为4096。
	reg [15:0]reg_padded = 0;                   // A3补齐输入深度。
	reg [3:0]reg_mode = 0;                      // 只接受空间卷积和矩阵加权算子。
	reg [3:0]reg_opcode = 0;                    // 扩展算子码零卷积或一码矩阵运算。
	reg [9:0]reg_groups = 0;                    // 八输出并行时覆盖342个输出组。
	reg [7:0]reg_tiles = 0;                     // 输入tile数量不从K_DEPTH截断FC。
	reg [13:0]reg_group_numerator = 0;          // 十三位核数加71不超过8298，十四位足够。
	reg [31:0]reg_config_groups = 0;            // 未通过范围检查前保留完整组数。
	reg [31:0]reg_config_tiles = 0;             // 输入深度换算结果在128上限判断前不截位。
	reg [15:0]reg_bias_base = 0;                // 十位组数乘64的中间结果。
	reg [31:0]reg_bias_bytes = 0;               // 整层偏置长度不串联到末址计算。
	reg [33:0]reg_weight_limit = 0;             // 宽化末址与区间比较分拍。
	reg [33:0]reg_bias_limit = 0;               // 宽化偏置末址保留进位。
	reg [16:0]reg_load_block = 0;               // 九位group乘八位tile数加索引最多130560。
	reg [9:0]reg_active_inputs = 0;             // 尾输入tile有效深度。
	reg [7:0]reg_active_outputs = 0;            // 当前组实际输出lane数量。
	(* use_dsp="no" *) reg [31:0]reg_command_addr = 0; // 命令地址在VALID等待期间保持。
	reg [22:0]reg_command_bytes = 0;            // 权重固定块或整组偏置字节数。
	reg [63:0]reg_beat = 0;                     // 单beat暂存供低高两个32位写。

	//-----------------标志信号-----------------//
	reg flag_configured = 0;                    // 层和偏置资格独立于旧RAM内容。
	reg flag_bias_valid = 0;                    // 当前组首tile偏置已经完整成功装载。
	reg flag_bias_phase = 0;                    // 当前DMA事务为偏置而非权重块。
	reg flag_high = 0;                          // 两半写及状态独立完成。
	reg flag_data_done = 0;                     // 最后数据及其所有缓存写均已完成。
	reg flag_status_done = 0;                   // 当前命令状态已接收，禁止重复消费。
	reg flag_fields_bad = 0;                    // 原始字段边界先寄存，不参与长算术链。
	reg flag_limits_bad = 0;                    // 数量与DDR比较结果先寄存后提交。
	wire flag_config_bad;                       // 各边界错误阻止ready。
	wire flag_request_bad;                      // 越界group或不连续后续tile拒绝标志。
	wire flag_status_bad;                       // 当前状态帧不是TAG零且OKAY的成功值。
	wire flag_frame_bad;                        // 当前beat的KEEP或TLAST不匹配BTT。
	wire flag_bias_bad;                         // 偏置高16位不是低48位的符号扩展。
	wire flag_data_accept;                      // 所有数据动作使用统一握手。
	wire flag_status_accept;                    // 状态VALID与本地READY已经共同成立。
	wire flag_write_accept;                     // C2原生pair写口已成功接收当前半字。
	wire flag_lane_valid;                       // 空bank及尾输出写零。

	//-----------------其他信号-----------------//
	//常数除法得到完整块计数
	wire [31:0]config_tiles;                    // 常数除法得到完整块计数。

	//根据八或72并行输出计算组数量
	wire [13:0]config_groups;                   // 除法保持十四位运算，结果再零扩展校验。

	//空间八或旁路72输出
	wire [7:0]parallel_outputs;                 // 空间八或旁路72输出。

	//宽化末址防止回绕
	wire [33:0]weight_limit;                    // 宽化末址防止回绕。

	//八输出模式的全组偏置字节数
	(* use_dsp="no" *) wire [15:0]config_bias_base; // 十位组数量乘64字节，无512组截断。

	//整层所有组偏置的字节总量
	(* use_dsp="no" *) wire [31:0]config_bias_bytes; // 常数八或72输出对应64或576字节。

	//偏置整层区域的宽化末地址
	(* use_dsp="no" *) wire [33:0]bias_limit;   // 偏置整层区域的宽化末地址。

	//当前group/tile块序号
	(* use_dsp="no" *) wire [31:0]load_block;   // 当前group/tile块序号。

	//LUT常数地址换算
	(* use_dsp="no" *) wire [31:0]load_weight_offset; // LUT常数地址换算。

	//真实逻辑尾部剩余量
	wire [31:0]tile_remaining;                  // 真实逻辑尾部剩余量。

	//本请求输出组起点后的逻辑输出余量
	(* use_dsp="no" *) wire [31:0]group_remaining; // 本请求输出组起点后的逻辑输出余量。

	//低半或高半对应两个相邻通道
	wire [31:0]write_pair;                      // 低半或高半对应两个相邻通道。

	//pair内低通道编号
	wire [9:0]write_channel;                    // pair内低通道编号。

	//当前bank实际映射的组内输出lane
	(* use_dsp="no" *) wire [7:0]write_output;  // 当前bank实际映射的组内输出lane。

	//尾输出偏置清零
	wire [47:0]write_bias;                      // 尾输出偏置清零。

	//-----------------输出信号-----------------//
	//用户接口
	wire start_ready_o;                         // 配置、装载和计算分时资格。
	wire load_ready_o;                          // 已配置且旧计算排空的group及tile接收资格。
	wire weight_ready_o;                        // 本块权重及所需偏置已经可靠完成的消费资格。
	reg load_done_o = 0;                        // 完成事件单拍脉冲。
	reg [8:0]group_index_o = 0;                 // 本次事务输出组标签。
	reg [7:0]tile_index_o = 0;                  // 本次事务输入tile标签。
	reg [3455:0]bias_data_o = 0;                // 每CU九路48位偏置，空间模式仅低八路有效。
	wire load_enable_o;                         // C2共同读禁止并允许物理写入的分时阶段。
	wire busy_o;                                // 控制器正进行配置或HP1装载事务。
	wire error_o;                               // 错误状态机编码对应的锁存错误通知。
	reg [3:0]error_code_o = 0;                  // 锁存首个错误直到复位。

	//用户接口CMD接口
	wire cmd_valid_o;                           // 独立HP1和缓存握手。
	wire [71:0]cmd_data_o;                      // Full DataMover标准72位命令。

	//用户接口
	wire data_ready_o;                          // 单beat暂存可接收且本周期未发生DMA失败。
	wire status_ready_o;                        // 当前命令仍未收到状态并允许消费。

	//用户接口WR接口
	wire wr_valid_o;                            // 当前半字正在向C2呈现有效写入。
	wire [3:0]wr_cu_o;                          // 当前物理bank索引。
	wire [3:0]wr_bank_o;                        // 目标CU内部的九个核bank之一。
	wire [7:0]wr_addr_o;                        // 当前双通道pair地址。
	wire [31:0]wr_data_o;                       // 尾通道逐INT16屏蔽后的数据。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign parallel_outputs = reg_mode[1] ? 8'd72 : 8'd8; // 1x1和FC使用九路旁路输出。
	assign config_tiles = (reg_inputs + 32'd511) >> 9; // 输入每512通道形成一个tile。
	assign config_groups = reg_mode[1] ? reg_group_numerator / 14'd72 : reg_group_numerator / 14'd8; // 十四位分子覆盖核数加法的所有值。
	assign config_bias_base = {reg_config_groups[9:0],6'd0}; // 512组乘64字节仍保留完整32768。
	assign config_bias_bytes = reg_mode[1] ? {reg_bias_base,3'd0}+reg_bias_base : {16'd0,reg_bias_base}; // 模式换算只消费寄存的基础长度。
	assign weight_limit = reg_weight_limit;     // 比较与TB观察均使用已寄存宽化末址。
	assign bias_limit = reg_bias_limit;         // 偏置长度、末址及比较不再同拍串联。
	assign flag_config_bad = flag_fields_bad || flag_limits_bad; // 提交使能只汇总已寄存检查结果。
	assign load_block = i_group_index * reg_tiles + i_tile_index; // group外层tile内层与A3一致。
	assign load_weight_offset = reg_load_block * 32'd73728; // 固定块偏移只消费已寄存的块序号。
	assign tile_remaining = reg_inputs - {15'd0, i_tile_index, 9'd0}; // tile起点以后真实输入数量。
	assign group_remaining = reg_outputs - i_group_index * parallel_outputs; // 组起点以后真实输出数量。
	assign flag_request_bad = i_group_index >= reg_groups || i_tile_index >= reg_tiles || (i_tile_index != 8'd0 && (!flag_bias_valid || i_group_index != group_index_o || {1'b0, i_tile_index} != {1'b0, tile_index_o} + 9'd1)); // 后续tile严格继承同组偏置。
	assign flag_data_accept = i_data_valid && data_ready_o; // 数据暂停时不采样。
	assign flag_status_accept = i_status_valid && status_ready_o; // 每命令至多一个状态。
	assign flag_status_bad = flag_status_accept && i_status != 8'h80; // TAG零且OKAY的Full状态必须精确匹配。
	assign flag_frame_bad = flag_data_accept && (i_data_keep != 8'hff || i_data_last != (flag_bias_phase ? cnt_bias == parallel_outputs - 8'd1 : cnt_beat == 14'd9215)); // KEEP和TLAST与BTT严格对应。
	assign flag_bias_bad = flag_data_accept && flag_bias_phase && i_data[63:48] != {16{i_data[47]}}; // INT64偏置必须是INT48符号扩展。
	assign flag_write_accept = wr_valid_o && i_wr_ready; // 只有缓存实际接收才推进物理地址。
	assign write_pair = flag_high ? reg_beat[63:32] : reg_beat[31:0]; // DDR低半先写高半后写。
	assign write_channel = {1'b0, cnt_pair, 1'b0}; // bank内pair的低INT16通道。
	assign write_output = reg_mode[1] ? cnt_cu * 8'd9 + cnt_bank : {4'd0, cnt_cu}; // 空间CU或旁路CU乘九加bank。
	assign flag_lane_valid = write_output < reg_active_outputs && (reg_mode != 4'd1 || cnt_bank == 4'd0 || cnt_bank == 4'd1 || cnt_bank == 4'd3 || cnt_bank == 4'd4); // 2x2不用的五bank覆盖为零。
	assign write_bias = cnt_bias < reg_active_outputs ? i_data[47:0] : 48'd0; // 偏置尾lane不依赖DDR填充值。
	assign start_ready_o = i_rstn && i_ce && i_compute_idle && (state_current == ST_IDLE || state_current == ST_READY); // 旧计算及读响应排空后才能切层。
	assign load_ready_o = start_ready_o && flag_configured && !i_start; // 层配置优先于装载请求。
	assign weight_ready_o = i_rstn && state_current == ST_READY; // 数据与成功状态齐备后允许计算。
	assign load_enable_o = !weight_ready_o;     // 装载期间C2禁止计算读。
	assign busy_o = state_current != ST_IDLE && state_current != ST_READY && state_current != ST_ERROR; // 一笔装载覆盖权重及可选偏置。
	assign error_o = state_current == ST_ERROR; // 错误锁存且禁止计算。
	assign cmd_valid_o = i_rstn && state_current == ST_COMMAND; // VALID不能因ce暂停而撤销。
	assign cmd_data_o = {8'd0, reg_command_addr, 1'b0, 1'b1, 6'd0, 1'b1, reg_command_bytes}; // TAG零、EOF一、INCR一、BTT二十三位。
	assign data_ready_o = i_rstn && i_ce && state_current == ST_RECEIVE && !flag_data_done && !flag_status_bad; // 单beat暂存防止覆盖未写高半。
	assign status_ready_o = i_rstn && i_ce && !flag_status_done && (state_current == ST_RECEIVE || state_current == ST_WRITE || state_current == ST_WAIT); // 状态可先于或晚于数据完成。
	assign wr_valid_o = i_rstn && i_ce && state_current == ST_WRITE && !flag_status_bad; // 同拍失败状态立即抑制写。
	assign wr_cu_o = cnt_cu;                    // 当前CU-major索引。
	assign wr_bank_o = cnt_bank;                // 当前CU内部核序号在pair255后更新。
	assign wr_addr_o = cnt_pair;                // 每成功pair写后递增。
	assign wr_data_o = {(flag_lane_valid && write_channel + 10'd1 < reg_active_inputs ? write_pair[31:16] : 16'd0), (flag_lane_valid && write_channel < reg_active_inputs ? write_pair[15:0] : 16'd0)}; // 两个尾通道各自补零。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_start_ready = start_ready_o;       // 传出计算排空后的层切换资格。
	assign o_load_ready = load_ready_o;         // 传出配置完成后的单块请求许可。
	assign o_weight_ready = weight_ready_o;     // 把成功事务的消费资格交给CAL。
	assign o_load_done = load_done_o;           // 传出完成沿的一次性事件寄存器。
	assign o_group_index = group_index_o;       // 向CAL回送已锁存的输出组标签。
	assign o_tile_index = tile_index_o;         // 向CAL回送已锁存的输入块编号。
	assign o_bias_data = bias_data_o;           // 公开按lane排列且跨tile保持的偏置寄存器。
	assign o_load_enable = load_enable_o;       // 把装载互斥阶段直接接到C2。
	assign o_busy = busy_o;                     // 向上层汇报正在处理命令的状态。
	assign o_error = error_o;                   // 公开复位前保持的故障状态。
	assign o_error_code = error_code_o;         // 输出首个失败边界的诊断编码。

	//用户接口CMD接口
	assign o_cmd_valid = cmd_valid_o;           // 向HP1呈现不依赖全局暂停的命令资格。
	assign o_cmd_data = cmd_data_o;             // HP1从稳定地址和BTT寄存器获取载荷。

	//用户接口
	assign o_data_ready = data_ready_o;         // 把单beat缓冲接收资格返回HP1。
	assign o_status_ready = status_ready_o;     // 通知DataMover可以提交唯一状态帧。

	//用户接口WR接口
	assign o_wr_valid = wr_valid_o;             // 转出当前低半或高半pair的写请求。
	assign o_wr_cu = wr_cu_o;                   // 接到C2八单元的目标选择端。
	assign o_wr_bank = wr_bank_o;               // 接到选中CU内部的核bank选择端。
	assign o_wr_addr = wr_addr_o;               // 接到目标bank的八位pair地址端。
	assign o_wr_data = wr_data_o;               // 接到C2原生32位权重写端且已屏蔽无效lane。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 载荷无控制复位；完整8或72项覆盖后才允许计算消费。
	always@(posedge i_clk)begin
		if(flag_data_accept && flag_bias_phase && !i_soft_reset && !flag_frame_bad && !flag_bias_bad)begin
			bias_data_o <= reg_mode[1] ? {write_bias, bias_data_o[3455:48]} : {3072'd0, write_bias, bias_data_o[383:48]}; // 保持原lane顺序、尾部补零及空间高位归零。
		end
	end

	// 配置载荷与数据游标只在合法握手后推进，偏置跨后续tile保持。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_configured <= 1'b0; flag_bias_valid <= 1'b0; flag_bias_phase <= 1'b0; // 旧缓存与偏置不能再消费。
			flag_high <= 1'b0; flag_data_done <= 1'b0; flag_status_done <= 1'b0; // 清除事务进度。
			load_done_o <= 1'b0; error_code_o <= 4'd0; // 清除事件和错误。
			group_index_o <= 9'd0; tile_index_o <= 8'd0; // 清除事务标签。
			reg_inputs <= 32'd0; reg_outputs <= 13'd0; reg_padded <= 16'd0; // 未配置尺寸。
			cnt_weight <= 32'd0; reg_weight_addr <= 32'd0; reg_bias_addr <= 32'd0; // 未配置DDR范围。
			reg_mode <= 4'd0; reg_opcode <= 4'd0; reg_groups <= 10'd0; reg_tiles <= 8'd0; // 未配置模式和计数。
			reg_group_numerator <= 14'd0; reg_config_groups <= 32'd0; reg_config_tiles <= 32'd0; // 清除中间数量。
			reg_bias_base <= 16'd0; reg_bias_bytes <= 32'd0; // 清除中间偏置长度。
			reg_weight_limit <= 34'd0; reg_bias_limit <= 34'd0; // 旧区间末址无效。
			reg_load_block <= 17'd0;            // 未接受请求时块序号无效。
			flag_fields_bad <= 1'b0; flag_limits_bad <= 1'b0; // 清除配置流水检查结果。
			reg_active_inputs <= 10'd0; reg_active_outputs <= 8'd0; // 禁止有效lane。
			reg_command_addr <= 32'd0; reg_command_bytes <= 23'd0; reg_beat <= 64'd0; // 命令及beat无有效资格。
			cnt_beat <= 14'd0; cnt_bias <= 7'd0; cnt_pair <= 8'd0; cnt_cu <= 4'd0; cnt_bank <= 4'd0; // 遍历从物理首地址开始。
		end else if(i_soft_reset == 1'b1)begin
			flag_configured <= 1'b0; flag_bias_valid <= 1'b0; flag_bias_phase <= 1'b0; // 保留存储内容但撤销有效标签。
			flag_high <= 1'b0; flag_data_done <= 1'b0; flag_status_done <= 1'b0; // 清事务进度。
			load_done_o <= 1'b0; error_code_o <= 4'd0; // 单拍清除不受ce影响。
			flag_fields_bad <= 1'b0; flag_limits_bad <= 1'b0; // 状态回空闲，撤销旧检查结果。
		end else begin
			load_done_o <= 1'b0;                // 事件不因暂停被拉长。
			if(state_current == ST_COMMAND && i_cmd_ready == 1'b1)begin
				flag_data_done <= 1'b0; flag_status_done <= 1'b0; // 每个命令独立等待数据和状态。
				cnt_beat <= 14'd0; cnt_bias <= 7'd0; // 新事务从零计数。
			end else if(i_ce == 1'b1)begin
				if(flag_status_accept == 1'b1)begin
					flag_status_done <= 1'b1;   // 允许状态早到且只接受一次。
				end
				if(flag_status_bad == 1'b1 || flag_frame_bad == 1'b1 || flag_bias_bad == 1'b1)begin
					error_code_o <= flag_status_bad ? 4'd4 : (flag_frame_bad ? 4'd3 : 4'd5); // 同拍状态错误优先。
				end else begin
					case(state_current)
						ST_IDLE, ST_READY:begin
							if(i_start == 1'b1 && start_ready_o == 1'b1)begin
								reg_inputs <= i_extension[171:168] == 4'd1 ? i_extension[223:192] : (i_base_instruction[183:172] == 12'd0 ? 32'd4096 : {20'd0, i_base_instruction[183:172]}); // FC以INPUT_ELEMENTS决定tile数。
								reg_outputs <= i_base_instruction[195:184] == 12'd0 ? 13'd4096 : {1'b0, i_base_instruction[195:184]}; // 支持4096输出零编码。
								reg_padded <= i_extension[143:128]; reg_mode <= i_base_instruction[199:196]; reg_opcode <= i_extension[171:168]; // 锁存原始配置字段。
								cnt_weight <= {i_extension[191:184], i_base_instruction[171:148]}; // 完整三八位权重数量。
								reg_weight_addr <= i_extension[31:0]; reg_bias_addr <= i_extension[63:32]; // HP1地址来自扩展字。
								flag_configured <= 1'b0; flag_bias_valid <= 1'b0; // 切层撤销旧偏置。
								flag_fields_bad <= 1'b0; flag_limits_bad <= 1'b0; // 新层不继承上一层检查结论。
							end else if(i_load_req == 1'b1 && load_ready_o == 1'b1)begin
								if(flag_request_bad == 1'b1)begin
									error_code_o <= 4'd2; // tile或组标签不合法。
								end else begin
									reg_load_block <= load_block[16:0]; reg_command_bytes <= 23'd73728; // 完整物理索引先寄存，不串联DDR偏移。
									group_index_o <= i_group_index; tile_index_o <= i_tile_index; // 完成标签与请求一致。
									reg_active_inputs <= tile_remaining > 32'd512 ? 10'd512 : tile_remaining[9:0]; // 尾输入限制。
									reg_active_outputs <= group_remaining > parallel_outputs ? parallel_outputs : group_remaining[7:0]; // 尾输出限制。
									flag_bias_phase <= 1'b0; flag_high <= 1'b0; cnt_pair <= 8'd0; cnt_bank <= 4'd0; cnt_cu <= 4'd0; // 新权重块写游标复位。
									if(i_tile_index == 8'd0)begin
										flag_bias_valid <= 1'b0; // 首tile完整重装后才重新发布偏置资格。
									end
								end
							end
						end

						// 块序号与固定偏移分拍，已有准备态不增加外部命令延迟。
						ST_PREPARE:begin
							reg_command_addr <= reg_weight_addr + load_weight_offset; // 请求索引在上一阶段锁存。
						end

						// 原配置逻辑分拍，最终提交前禁止装载请求。
						ST_CONFIG:begin
							reg_group_numerator <= {1'b0,reg_outputs} + (reg_mode[1] ? 14'd71 : 14'd7); // 十四位加法保留全部进位。
							reg_config_tiles <= config_tiles; // 全宽数量在检查后才缩位。
							flag_fields_bad <= reg_inputs == 32'd0 || reg_inputs > 32'd65532 || reg_padded < reg_inputs || reg_padded[1:0] != 2'd0 || reg_outputs == 13'd0 || reg_mode > 4'd3 || !((reg_opcode == 4'd0 && reg_mode < 4'd3) || (reg_opcode == 4'd1 && reg_mode == 4'd3)) || reg_weight_addr[2:0] != 3'd0 || reg_bias_addr[2:0] != 3'd0 || reg_weight_addr < 32'h12000000 || reg_bias_addr < 32'h12000000; // 原字段检查保持不变。
						end
						ST_GROUPS:begin
							reg_config_groups <= config_groups; // 除法结果不再串联偏置及范围逻辑。
						end
						ST_BIAS_BASE:begin
							reg_bias_base <= config_bias_base; // 组数乘64结果独立寄存。
						end
						ST_BIAS_BYTES:begin
							reg_bias_bytes <= config_bias_bytes; // 空间或旁路长度独立寄存。
						end
						ST_LIMIT:begin
							reg_weight_limit <= {1'b0, reg_weight_addr} + {1'b0, cnt_weight, 1'b0}; // 保留原宽化权重范围加法。
							reg_bias_limit <= {1'b0, reg_bias_addr} + {2'd0,reg_bias_bytes}; // 保留偏置末址进位。
						end
						ST_CHECK:begin
							flag_limits_bad <= reg_config_tiles > 32'd128 || reg_config_groups > 32'd512 || weight_limit > 33'h026000000 || bias_limit > 33'h026000000 || !(weight_limit <= {1'b0, reg_bias_addr} || bias_limit <= {1'b0, reg_weight_addr}); // 原数量和区间检查结果寄存。
						end
						ST_COMMIT:begin
							if(flag_config_bad == 1'b1)begin
								error_code_o <= 4'd1; // 完整配置边界检查失败。
							end else begin
								reg_groups <= reg_config_groups[9:0]; reg_tiles <= reg_config_tiles[7:0]; flag_configured <= 1'b1; // 通过全宽检查后发布层资格。
							end
						end

						//接收一笔权重beat或偏置word。
						ST_RECEIVE:begin
							if(flag_data_accept == 1'b1)begin
								if(flag_bias_phase == 1'b1)begin
									cnt_bias <= cnt_bias + 7'd1; flag_data_done <= i_data_last; // 偏置整组完成资格。
								end else begin
									reg_beat <= i_data; flag_high <= 1'b0; // 暂存完整beat再分两次写。
								end
							end
						end

						//暂存beat分低高两个pair写入。
						ST_WRITE:begin
							if(flag_write_accept == 1'b1)begin
								flag_high <= !flag_high; // 两半写交替。
								if(flag_high == 1'b1)begin
									cnt_beat <= cnt_beat + 14'd1; flag_data_done <= cnt_beat == 14'd9215; // 高半成功后推进beat。
								end
								if(cnt_pair == 8'd255)begin
									cnt_pair <= 8'd0; // 下一bank从pair零开始。
									if(cnt_bank == 4'd8)begin
										cnt_bank <= 4'd0; cnt_cu <= cnt_cu + 4'd1; // 下一CU。
									end else begin
										cnt_bank <= cnt_bank + 4'd1; // 同CU下一bank。
									end
								end else begin
									cnt_pair <= cnt_pair + 8'd1; // 同bank下一pair。
								end
							end
						end

						//首tile追加偏置或发布装载完成。
						ST_FINISH:begin
							if(flag_bias_phase == 1'b0 && tile_index_o == 8'd0)begin
								reg_command_addr <= reg_bias_addr + group_index_o * parallel_outputs * 32'd8; reg_command_bytes <= parallel_outputs * 23'd8; flag_bias_phase <= 1'b1; // 首tile追加偏置DMA。
							end else begin
								flag_bias_valid <= 1'b1; load_done_o <= 1'b1; // 数据和状态完成后一次发布ready。
							end
						end
						default:begin
							flag_configured <= flag_configured; // 准备、命令、等待及错误状态保持载荷。
						end
					endcase
				end
			end
		end
	end

	//----------------状态机区域----------------//
	// 根据CAL授权、两半写游标和DMA完成资格决定下一状态。
	always@(*)begin
		state_next = state_current;             // 默认保持，所有分支覆盖无锁存。
		case(state_current)
			ST_IDLE, ST_READY:begin
				if(i_start == 1'b1 && start_ready_o == 1'b1)begin
					state_next = ST_CONFIG;     // 新层配置撤销旧ready。
				end else if(i_load_req == 1'b1 && load_ready_o == 1'b1)begin
					state_next = flag_request_bad ? ST_ERROR : ST_PREPARE; // 请求边界先校验。
				end else begin
					state_next = state_current; // 等待CAL安全请求。
				end

			end

			// 配置阶段与中间寄存器共同受ce冻结。
			ST_CONFIG:begin
				state_next = ST_GROUPS;         // 加法结果进入独立除法阶段。
			end

			// 组数除法结果独立锁存。
			ST_GROUPS:begin
				state_next = ST_BIAS_BASE;      // 组数结果进入长度换算。
			end

			// 八lane偏置基础长度寄存。
			ST_BIAS_BASE:begin
				state_next = ST_BIAS_BYTES;     // 乘64后再选择旁路长度。
			end

			// 根据模式换算整层偏置长度。
			ST_BIAS_BYTES:begin
				state_next = ST_LIMIT;          // 完整长度进入末址加法。
			end

			// 权重和偏置区间末址并行寄存。
			ST_LIMIT:begin
				state_next = ST_CHECK;          // 已寄存末址进入区间比较。
			end

			// 宽化数量和区间范围判断。
			ST_CHECK:begin
				state_next = ST_COMMIT;         // 检查结论在下一阶段使用。
			end

			// 检查均通过后发布装载资格。
			ST_COMMIT:begin
				state_next = flag_config_bad ? ST_ERROR : ST_IDLE; // 层参数及DDR范围合法才接受。

			end

			//已锁存块序号的命令地址准备态。
			ST_PREPARE:begin
				state_next = ST_COMMAND;        // 同沿寄存地址，随后呈现有效命令。

			end

			//HP1命令持续呈现并等待接收态。
			ST_COMMAND:begin
				if(i_cmd_ready == 1'b1)begin
					state_next = ST_RECEIVE;    // 不依赖ce完成已呈现命令握手。
				end else begin
					state_next = ST_COMMAND;    // 持有相同命令直到接受。
				end

			end

			//接收一笔权重beat或偏置word。
			ST_RECEIVE:begin
				if(flag_data_accept == 1'b1)begin
					state_next = flag_bias_phase ? (i_data_last ? ST_WAIT : ST_RECEIVE) : ST_WRITE; // 偏置直接装寄存器，权重拆两半。
				end else begin
					state_next = ST_RECEIVE;    // 等待下一beat。
				end

			end

			//暂存beat分低高两个pair写入。
			ST_WRITE:begin
				if(flag_write_accept == 1'b1 && flag_high == 1'b1)begin
					state_next = cnt_beat == 14'd9215 ? ST_WAIT : ST_RECEIVE; // 最后高半写完才算数据完成。
				end else begin
					state_next = ST_WRITE;      // 低半或缓存反压期间保持。
				end

			end

			//等待DMA成功状态与数据完成同时齐备。
			ST_WAIT:begin
				if(flag_status_done == 1'b1 && flag_data_done == 1'b1)begin
					state_next = ST_FINISH;     // 数据和状态均已收到。
				end else begin
					state_next = ST_WAIT;       // 晚状态不提前发布ready。
				end

			end

			//首tile追加偏置或发布装载完成。
			ST_FINISH:begin
				state_next = !flag_bias_phase && tile_index_o == 8'd0 ? ST_COMMAND : ST_READY; // 首tile追加整组偏置命令。

			end

			//锁存错误并等待静止DMA后的复位。
			ST_ERROR:begin
				state_next = ST_ERROR;          // 需要静止DMA后复位恢复。
			end

			// 非法状态编码立即进入锁存故障态。
			default:begin
				state_next = ST_ERROR;          // 非法编码安全停机。
			end
		endcase
		if(flag_status_bad == 1'b1 || flag_frame_bad == 1'b1 || flag_bias_bad == 1'b1)begin
			state_next = ST_ERROR;              // 任何事务错误均阻止ready。
		end else begin
			state_next = state_next;            // 正常状态转移保持上方结果。
		end
	end

	// 状态寄存器异步撤销资格，命令等待期间允许独立HP1握手。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			state_current <= ST_IDLE;           // 异步立即撤销所有有效资格。
		end else if(i_soft_reset == 1'b1)begin
			state_current <= ST_IDLE;           // 上游已静止DMA才允许软清。
		end else if(i_ce == 1'b1 || state_current == ST_COMMAND)begin
			state_current <= state_next;        // 命令握手在ce暂停时仍完成。
		end else begin
			state_current <= state_current;     // 暂停其他全部状态动作。
		end
	end

endmodule
