`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     feature_cmd
// Module Name:     feature_cmd
// Description:     description/feature_cmd_Design.pdf
// Simulations:     testbench/vivado/2021.1/feature_cmd
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/feature_cmd_spec.md; docs/设计文档.md 4.3
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/14 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Codex             Create HWC feature transfer controller.
// 2026/10/09       V1.0        Codex             Use software-precomputed feature fields; move row capacity validation to software.
// 2026/10/14       V1.0        Codex             Register authorized update offsets before DDR address addition.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Codex
//
// 创建日期:        2026年10月08日
// 设计名称:        feature_cmd
// 模块名称:        feature_cmd
// 模块说明:        Description/feature_cmd_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/feature_cmd
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/feature_cmd_spec.md; docs/设计文档.md 4.3
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月14日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             创建三行初装及安全覆盖控制器
// 2026年10月09日   V1.0        Codex             直用软件特征字段，缓存行容量改由软件预检

module feature_cmd
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 所有控制与HP0接口共用FCLK_CLK0。
	input i_rstn,                               // 低有效异步复位，上游同步释放。
	input i_ce,                                 // 冻结请求、数据、状态和缓存写。
	input i_soft_reset,                         // 同步清控制；上游先使DataMover静止。

	//-----------------用户接口-----------------//
	input i_start,                              // 锁存当前层A3指令。
	input [255:0]i_base_instruction,            // A3论文基础指令。
	input [255:0]i_extension,                   // A3工程扩展字。
	output o_start_ready,                       // 空闲可接收层配置。
	input i_scan_req,                           // 新group/tile三行扫描请求。
	output o_scan_ready,                        // 扫描请求可接受。
	input [9:0]i_group_index,                   // 输出组标识。
	input [7:0]i_tile_index,                    // 输入tile标识。
	input [15:0]i_tile_channel_base,            // 512对齐tile起始通道。

	//UPDATE接口
	input i_update_req,                         // CAL已消费完整向量的覆盖授权。
	output o_update_ready,                      // 可接收覆盖请求。
	input [15:0]i_update_row,                   // 将装入的真实输入行。
	input [11:0]i_update_col,                   // 输入列及缓存向量位置。
	input [1:0]i_update_bank,                   // 被授权覆盖的物理bank。
	input i_scan_finish,                        // CAL已消费本次扫描所有结果。
	output o_feature_ready,                     // 当前扫描初装或更新已成功完成。
	output o_update_done,                       // 当前覆盖成功完成单拍通知。
	output o_scan_done,                         // 扫描消费完成单拍通知。
	output [9:0]o_group_index,                  // 当前响应输出组标签。
	output [7:0]o_tile_index,                   // 当前响应输入tile标签。
	output o_busy,                              // 存在未结束的扫描或DMA。
	output o_error,                             // 粘滞错误，阻断新事务。
	output [3:0]o_error_code,                   // 1配置/2扫描/3覆盖/4帧/5状态。

	//CMD接口
	output o_cmd_valid,                         // HP0 Full DataMover命令有效。
	input i_cmd_ready,                          // DataMover命令接受。
	output [71:0]o_cmd_data,                    // TAG0/32位SADDR/EOF1/INCR/BTT。
	input i_data_valid,                         // HP0 MM2S数据有效。
	output o_data_ready,                        // 合法状态下根据缓存与ce反压。
	input [63:0]i_data,                         // 四INT16小端DDR数据。
	input [7:0]i_data_keep,                     // 固定全字节有效。
	input i_data_last,                          // 每向量末beat为1。
	input i_status_valid,                       // DataMover8位状态有效。
	output o_status_ready,                      // 接受当前唯一未完成命令状态。
	input [7:0]i_status,                        // OKAY及错误位和TAG。

	//WR接口
	output o_wr_valid,                          // C0缓存完整word写请求。
	input i_wr_ready,                           // C0无读写冲突可接受。
	output o_wr_safe,                           // 锁存安全授权，仅用于本次地址。
	output [1:0]o_wr_bank,                      // C0物理bank。
	output [11:0]o_wr_addr,                     // C0四通道word地址。
	output [63:0]o_wr_data                      // 真实通道签名和显式零尾lane。
);

	//---------------状态参数区域---------------//
	localparam [2:0]ST_COMMAND = 3'd1;          // 已锁存向量命令等待DataMover。
	localparam [2:0]ST_ERROR = 3'd5;            // 粘滞错误阻断后续事务。
	localparam [2:0]ST_IDLE = 3'd0;             // 等待层配置或新扫描。
	localparam [2:0]ST_RECEIVE = 3'd2;          // 接受数据及可能提前到达的状态。
	localparam [2:0]ST_ADVANCE = 3'd3;          // 数据和状态齐备后推进初装。
	localparam [2:0]ST_READY = 3'd4;            // 当前向量可供CAL消费或覆盖。
	localparam [2:0]ST_ADDRESS = 3'd6;          // 将已授权坐标偏移合成为DDR命令地址。

	//-----------------计数信号-----------------//
	reg [11:0]cnt_column = 0;                   // 初装当前空间列。
	reg [1:0]cnt_bank = 0;                      // 初装真实行对应物理bank。
	reg [7:0]cnt_quad = 0;                      // 当前向量已接受的四通道word数量。

	//----------------状态机信号----------------//
	reg [2:0]state_current = 0;                 // 控制事务及CAL握手阶段。
	reg [2:0]state_next = 0;                    // 明确组合次态及所有保持路径。

	//----------------寄存器信号----------------//
	reg [31:0]reg_feature_base = 0;             // 当前层特征DDR首地址。
	reg [31:0]reg_vector_address = 0;           // 当前向量tile片段起始DDR地址。
	reg [31:0]reg_row_bytes = 0;                // 完整HWC行字节跨度。
	reg [31:0]reg_update_row_offset = 0;        // 授权沿保存行跨度乘积，切断跨模块长路径。
	reg [31:0]reg_update_column_offset = 0;     // 授权列的完整HWC字节偏移，暂停期间保持。
	reg [31:0]reg_logical_channels = 0;         // FC展平有效长度或空间逻辑通道。
	reg [15:0]reg_channels_padded = 0;          // 完整DDR向量补齐深度。
	reg [15:0]reg_height = 0;                   // 当前扫描真实输入高度。
	reg [11:0]reg_width = 0;                    // 当前扫描真实输入宽度。
	reg [1:0]reg_initial_rows = 0;              // 首次装入一至三个真实行。
	reg [15:0]reg_tile_base = 0;                // 当前tile通道起始偏移。
	reg [9:0]reg_tile_channels = 0;             // 当前tile补齐深度，最高512。
	reg [9:0]reg_active_channels = 0;           // 当前tile真实有效深度。
	reg [11:0]reg_write_base = 0;               // 当前向量在物理行内的首word。
	reg [11:0]reg_initial_word = 0;             // 首三行连续装载的行内word游标。

	//-----------------标志信号-----------------//
	reg flag_configured = 0;                    // 已成功锁存并验证层特征字段。
	reg flag_matrix = 0;                        // FC展平后只有一个空间位置。
	reg flag_update = 0;                        // 当前事务由CAL覆盖授权触发。
	reg flag_data_done = 0;                     // 命令末数据beat已经写入缓存。
	reg flag_status_done = 0;                   // 当前命令已收到成功状态。
	wire flag_matrix_config;                    // 当前待接受层按FC展平。
	wire flag_config_bad;                       // 特征地址、尺寸或A3切换字段不合法。
	wire flag_scan_bad;                         // tile标签或通道起点不合法。
	wire flag_update_bad;                       // 安全请求的空间坐标或bank越界。
	wire flag_frame_bad;                        // 当前输入beat的keep或TLAST不匹配。
	wire flag_status_bad;                       // DataMover非成功状态或错误TAG。
	wire flag_write;                            // 缓存与DDR流同步完成本次word握手。

	//-----------------其他信号-----------------//
	//完整输入特征尺寸
	wire [31:0]config_channels;                 // 待接受的完整逻辑输入深度。
	wire [31:0]config_padded;                   // A3完整DDR深度扩展到32位。
	wire [31:0]config_width;                    // 空间宽度或FC单向量宽度。
	wire [31:0]config_height;                   // 空间高度或FC单向量高度。
	wire [31:0]config_row_elements;             // 软件提供的空间行跨度或FC单向量跨度。

	//输入总容量
	wire [31:0]config_elements;                 // 指令预计算的输入总量，单位为INT16元素。

	//宽化DDR范围末址
	wire [32:0]input_limit_address;             // 宽化末地址避免32位回绕。
	wire [31:0]scan_remaining;                  // 当前tile起点之后的有效元素。
	wire [9:0]scan_active;                      // 尾tile真实通道数。
	wire [9:0]scan_padded;                      // 以四通道word补齐后的tile深度。

	//CAL安全请求行偏移
	(* use_dsp="no" *) wire [31:0]update_row_offset; // 请求输入行的完整HWC字节偏移。

	//CAL安全请求列偏移
	(* use_dsp="no" *) wire [31:0]update_column_offset; // 当前输入列的完整DDR字节偏移。

	//tile缓存写地址
	(* use_dsp="no" *) wire [21:0]update_word_offset; // 当前列在tile缓存内的word偏移。

	//当前word有效lane边界
	wire [9:0]write_channel;                    // 本beat低lane在tile内的相对通道。
	wire [7:0]vector_words;                     // 每命令固定一至128个完整word。

	//-----------------输出信号-----------------//
	//用户接口
	wire start_ready_o;                         // 空闲且可推进时接受层配置。
	wire scan_ready_o;                          // 配置完成后可接受新group/tile。

	//用户接口UPDATE接口
	wire update_ready_o;                        // 当前扫描可消费时允许单个授权请求。

	//用户接口
	wire feature_ready_o;                       // 初装或安全覆盖已成功完成。
	reg update_done_o = 0;                      // 覆盖数据和成功状态齐备通知。
	reg scan_done_o = 0;                        // CAL确认本扫描消费完成通知。
	reg [9:0]group_index_o = 0;                 // 当前扫描所属输出组。
	reg [7:0]tile_index_o = 0;                  // 当前扫描所属输入tile。
	wire busy_o;                                // 扫描尚未收到CAL消费结束通知。
	wire error_o;                               // 首个错误进入锁存态。
	reg [3:0]error_code_o = 0;                  // 首个错误原因在复位前保持。

	//用户接口CMD接口
	wire cmd_valid_o;                           // 命令呈现后不能因ce暂停而撤销。
	wire [71:0]cmd_data_o;                      // 标准Full DataMover命令载荷。

	//用户接口
	wire data_ready_o;                          // 数据与缓存write使用同一握手资格。
	wire status_ready_o;                        // 一个命令只接收一个状态。

	//用户接口WR接口
	wire wr_valid_o;                            // 授权合法数据向量的当前word。
	wire wr_safe_o;                             // 初装或锁存CAL请求后的单事务授权。
	reg [1:0]wr_bank_o = 0;                     // 单笔已授权向量的物理写bank。
	wire [11:0]wr_addr_o;                       // 向量首word加当前quad偏移。
	wire [63:0]wr_data_o;                       // 逻辑通道外强制补零，独立于DDR内容。

	//---------------其他信号连线---------------//
	//其他信号连线
	//A3字段与地址检查
	assign flag_matrix_config = i_extension[171:168] == 4'd1; // FC使用INPUT_ELEMENTS而非K_DEPTH。
	assign config_channels = flag_matrix_config ? i_extension[223:192] : (i_base_instruction[183:172] == 12'd0 ? 32'd4096 : {20'd0, i_base_instruction[183:172]}); // 保留4096的零编码。
	assign config_padded = {16'd0, i_extension[143:128]}; // Cin_padded来自扩展word四。
	assign config_width = flag_matrix_config ? 32'd1 : {20'd0, i_base_instruction[147:136]}; // FC只缓存当前输入tile。
	assign config_height = flag_matrix_config ? 32'd1 : {16'd0, i_extension[111:96]}; // FC空间形状不参与缓存寻址。
	assign config_row_elements = flag_matrix_config ? config_padded : {8'd0, i_base_instruction[135:112]}; // FC为单展平向量，空间行跨度直接采用F_CAL_SWITCH。
	assign config_elements = {8'd0, i_base_instruction[87:64]}; // 直接消费F_TRANS_NUM，不再重算整层几何乘积。
	assign input_limit_address = {1'b0, i_base_instruction[31:0]} + {config_elements, 1'b0}; // 字节末地址使用足够宽度。
	assign flag_config_bad = i_base_instruction[2:0] != 3'd0 || i_base_instruction[31:0] < 32'h05000000 || input_limit_address > 33'h011000000 || config_elements == 32'd0 || config_row_elements == 32'd0 || config_channels == 32'd0 || config_padded < config_channels || config_padded[1:0] != 2'd0 || config_width == 32'd0 || config_height == 32'd0 || i_extension[171:168] > 4'd4 || (flag_matrix_config && i_base_instruction[199:196] != 4'd3) || (!flag_matrix_config && i_base_instruction[199:196] > 4'd2); // 保留地址、尺寸与模式边界，不复算软件字段一致性。
	assign scan_remaining = reg_logical_channels - {16'd0, i_tile_channel_base}; // 扫描越界由独立比较保护。
	assign scan_active = scan_remaining > 32'd512 ? 10'd512 : scan_remaining[9:0]; // 逻辑尾tile限制有效lane。
	assign scan_padded = (scan_active + 10'd3) & 10'h3fc; // 最多512，四通道对齐。
	assign flag_scan_bad = {16'd0, i_tile_channel_base} >= reg_logical_channels || {16'd0, i_tile_channel_base} != {15'd0, i_tile_index, 9'd0}; // tile序号与起点必须一致。

	//UPDATE接口
	assign update_row_offset = {16'd0, i_update_row} * reg_row_bytes; // 真实DDR行跨度不使用tile缓存深度。
	assign update_column_offset = {20'd0, i_update_col} * {15'd0, reg_channels_padded, 1'b0}; // 当前列的完整HWC深度跨度。
	assign update_word_offset = i_update_col * reg_tile_channels[9:2]; // 当前tile每列占用完整word数。
	assign flag_update_bad = flag_matrix || i_update_bank == 2'd3 || i_update_col >= reg_width || i_update_row >= reg_height || i_update_row < 16'd3; // 虚拟Padding和初装行不发更新。

	//其他信号连线
	assign write_channel = {cnt_quad, 2'b00};   // 当前word低lane相对有效通道边界。
	assign vector_words = reg_tile_channels[9:2]; // 512通道对应128个64位beat。

	//CMD接口
	assign flag_frame_bad = i_data_keep != 8'hff || i_data_last != (cnt_quad == vector_words - 8'd1); // 拒绝提前或迟到末拍。
	assign flag_status_bad = i_status != 8'h80; // TAG零且仅OKAY为一才成功。
	assign wr_data_o = {((write_channel + 10'd3 < reg_active_channels) ? i_data[63:48] : 16'd0), ((write_channel + 10'd2 < reg_active_channels) ? i_data[47:32] : 16'd0), ((write_channel + 10'd1 < reg_active_channels) ? i_data[31:16] : 16'd0), ((write_channel < reg_active_channels) ? i_data[15:0] : 16'd0)}; // 尾lane不能泄漏DDR脏补齐。

	//WR接口
	assign flag_write = wr_valid_o && i_wr_ready; // 数据消费与C0写入必须同时发生。

	//其他信号连线

	//用户接口
	assign start_ready_o = i_rstn && i_ce && state_current == ST_IDLE; // 运行中不替换层参数。
	assign scan_ready_o = start_ready_o && flag_configured && !i_start; // 层start优先于新扫描。
	assign update_ready_o = i_rstn && i_ce && state_current == ST_READY && !i_scan_finish; // 扫描结束优先于覆盖请求。
	assign feature_ready_o = i_rstn && state_current == ST_READY; // 向量和状态全部成功才可用。
	assign busy_o = state_current != ST_IDLE && state_current != ST_ERROR; // 空闲与错误均不代表有效计算扫描。
	assign error_o = state_current == ST_ERROR; // 错误必须由复位清除。
	assign cmd_valid_o = i_rstn && state_current == ST_COMMAND; // AXIS valid在ce低时仍保持。
	assign cmd_data_o = {8'd0, reg_vector_address, 1'b0, 1'b1, 6'd0, 1'b1, 12'd0, reg_tile_channels, 1'b0}; // 72位RSVD/TAG/SADDR/DRR/EOF/DSA/TYPE/BTT。
	assign data_ready_o = i_rstn && i_ce && state_current == ST_RECEIVE && !flag_data_done && i_wr_ready; // 缓存冲突直接反压HP0。
	assign status_ready_o = i_rstn && i_ce && state_current == ST_RECEIVE && !flag_status_done; // 可以先于末数据接受成功状态。
	assign wr_valid_o = wr_safe_o && i_data_valid && !flag_frame_bad && !(status_ready_o && i_status_valid && flag_status_bad); // valid独立于C0 ready，错误当拍禁止污染缓存。
	assign wr_safe_o = i_rstn && i_ce && state_current == ST_RECEIVE && !flag_data_done; // 授权由锁存事务产生，避免与C0 ready形成组合环。
	assign wr_addr_o = reg_write_base + {4'd0, cnt_quad}; // 不跨越当前向量缓存边界。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_start_ready = start_ready_o;       // 层配置接收资格。
	assign o_scan_ready = scan_ready_o;         // group/tile请求接收资格。

	//用户接口UPDATE接口
	assign o_update_ready = update_ready_o;     // CAL授权请求接收资格。

	//用户接口
	assign o_feature_ready = feature_ready_o;   // 缓存数据可消费资格。
	assign o_update_done = update_done_o;       // 覆盖完成FCLK单拍。
	assign o_scan_done = scan_done_o;           // 扫描完成FCLK单拍。
	assign o_group_index = group_index_o;       // 响应保留输出组标签。
	assign o_tile_index = tile_index_o;         // 响应保留输入tile标签。
	assign o_busy = busy_o;                     // 扫描活动状态。
	assign o_error = error_o;                   // 分发器停止后续层的错误通知。
	assign o_error_code = error_code_o;         // 首个错误码。

	//用户接口CMD接口
	assign o_cmd_valid = cmd_valid_o;           // 保持到DataMover接受，不能因CAL暂停撤销。
	assign o_cmd_data = cmd_data_o;             // HP0命令完整载荷。

	//用户接口
	assign o_data_ready = data_ready_o;         // HP0数据消费允许。
	assign o_status_ready = status_ready_o;     // HP0状态消费允许。

	//用户接口WR接口
	assign o_wr_valid = wr_valid_o;             // C0当前word有效。
	assign o_wr_safe = wr_safe_o;               // C0当前word安全授权。
	assign o_wr_bank = wr_bank_o;               // 当前向量物理bank。
	assign o_wr_addr = wr_addr_o;               // C0行内word地址。
	assign o_wr_data = wr_data_o;               // 逻辑深度外补零的四lane。

	//-------------输出信号处理区域-------------//
	//用户接口
	// ponytail: 每向量单命令且只允许一个在途事务；HP0带宽实测不足时合并同tile连续全深度向量。
	// 所有CAL请求仅在ce沿接受；已呈现命令的AXIS握手始终由FCLK采样。
	// 层字段与传输游标只由已接受的请求、缓存写和DMA状态更新。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_configured <= 1'b0;            // 旧层参数不能继续使用。
			flag_matrix <= 1'b0;                // 默认不保留展平资格。
			flag_update <= 1'b0;                // 旧授权立即作废。
			flag_data_done <= 1'b0;             // 撤销旧数据完成资格。
			flag_status_done <= 1'b0;           // 撤销旧状态完成资格。
			update_done_o <= 1'b0;              // 复位期间不通知覆盖成功。
			scan_done_o <= 1'b0;                // 复位期间不通知扫描成功。
			cnt_column <= 12'd0;                // 初装列游标归零。
			cnt_bank <= 2'd0;                   // 初装物理行归零。
			cnt_quad <= 8'd0;                   // 接收word游标归零。
			reg_feature_base <= 32'd0;          // 旧DDR首址作废。
			reg_vector_address <= 32'd0;        // 旧命令载荷作废。
			reg_row_bytes <= 32'd0;             // 不保留行跨度。
			reg_update_row_offset <= 32'd0;     // 旧授权行地址不能用于新扫描。
			reg_update_column_offset <= 32'd0;  // 丢弃旧任务的空间列偏移。
			reg_logical_channels <= 32'd0;      // 旧逻辑深度无效。
			reg_channels_padded <= 16'd0;       // 旧DDR深度无效。
			reg_height <= 16'd0;                // 旧行数无效。
			reg_width <= 12'd0;                 // 旧列数无效。
			reg_initial_rows <= 2'd0;           // 不产生初装请求。
			reg_tile_base <= 16'd0;             // 旧tile偏移作废。
			reg_tile_channels <= 10'd0;         // 旧命令长度作废。
			reg_active_channels <= 10'd0;       // 所有旧lane无效。
			group_index_o <= 10'd0;             // 输出组响应标签归零。
			tile_index_o <= 8'd0;               // 输入tile响应标签归零。
			wr_bank_o <= 2'd0;                  // 写bank定位归零。
			reg_write_base <= 12'd0;            // 向量word首址归零。
			reg_initial_word <= 12'd0;          // 初装word游标归零。
			error_code_o <= 4'd0;               // 硬复位清首错误。
		end else if(i_soft_reset == 1'b1)begin
			flag_configured <= 1'b0;            // 软复位后重新锁存层配置。
			flag_data_done <= 1'b0;             // 清本地数据完成资格。
			flag_status_done <= 1'b0;           // 清本地状态完成资格。
			update_done_o <= 1'b0;              // 清覆盖通知。
			scan_done_o <= 1'b0;                // 清扫描通知。
			error_code_o <= 4'd0;               // 同步清粘滞错误。
		end else begin
			update_done_o <= 1'b0;              // 完成通知每FCLK单拍，不因ce延长。
			scan_done_o <= 1'b0;                // 扫描结束通知每FCLK单拍。
			if(cmd_valid_o == 1'b1 && i_cmd_ready == 1'b1)begin
				cnt_quad <= 8'd0;               // 新向量从首word接收。
				flag_data_done <= 1'b0;         // 每条命令重新等待全部数据。
				flag_status_done <= 1'b0;       // 每条命令重新等待成功状态。
			end else if(i_ce == 1'b1)begin
				case(state_current)

					// 新层配置优先，扫描只使用已验证的锁存字段。
					ST_IDLE:begin
						if(i_start == 1'b1)begin
							if(flag_config_bad == 1'b1)begin
								error_code_o <= 4'd1; // 配置不合法。
							end else begin
								flag_configured <= 1'b1; // 允许后续scan请求。
								flag_matrix <= flag_matrix_config; // 保存FC展平语义。
								reg_feature_base <= i_base_instruction[31:0]; // 保存完整输入首址。
								reg_row_bytes <= {config_row_elements[30:0], 1'b0}; // 将软件给出的行元素数左移一位形成字节步长。
								reg_logical_channels <= config_channels; // 保存有效输入深度。
								reg_channels_padded <= config_padded[15:0]; // 保存DDR通道步长。
								reg_width <= config_width[11:0]; // 保存当前扫描宽度。
								reg_height <= config_height[15:0]; // 保存真实扫描高度。
								reg_initial_rows <= config_height >= 32'd3 ? 2'd3 : config_height[1:0]; // 不读取虚拟Padding行。
							end
						end else if(i_scan_req == 1'b1 && scan_ready_o == 1'b1)begin
							if(flag_scan_bad == 1'b1)begin
								error_code_o <= 4'd2; // scan参数不合法。
							end else begin
								reg_vector_address <= reg_feature_base + {15'd0, i_tile_channel_base, 1'b0}; // 首向量当前tile片段地址。
								reg_tile_base <= i_tile_channel_base; // 后续覆盖保持同一tile。
								reg_tile_channels <= scan_padded; // 当前缓存向量深度。
								reg_active_channels <= scan_active; // 屏蔽末tile无效lane。
								group_index_o <= i_group_index; // 绑定新输出组响应。
								tile_index_o <= i_tile_index; // 绑定新输入tile响应。
								cnt_column <= 12'd0; // 新扫描从首列重装。
								cnt_bank <= 2'd0; // 新扫描从bank零重装。
								wr_bank_o <= 2'd0; // 当前初装行写bank零。
								reg_write_base <= 12'd0; // 首列缓存word归零。
								reg_initial_word <= 12'd0; // 三行初装游标重新建立。
								flag_update <= 1'b0; // 初装事务没有旧数据消费依赖。
							end
						end
					end

					// 状态可以先到，只有成功状态与末数据齐备才完成。
					ST_RECEIVE:begin
						if((status_ready_o == 1'b1 && i_status_valid == 1'b1 && flag_status_bad == 1'b1) || (data_ready_o == 1'b1 && i_data_valid == 1'b1 && flag_frame_bad == 1'b1))begin
							error_code_o <= (status_ready_o && i_status_valid && flag_status_bad) ? 4'd5 : 4'd4; // 状态错误优先于帧错误。
						end else begin
							if(status_ready_o == 1'b1 && i_status_valid == 1'b1)begin
								flag_status_done <= 1'b1; // 锁存当前TAG的成功状态。
							end
							if(flag_write == 1'b1)begin
								cnt_quad <= cnt_quad + 8'd1; // 只在实际写入后增加字计数。
								if(i_data_last == 1'b1)begin
									flag_data_done <= 1'b1; // 最后word已经写入C0。
								end
							end
						end
					end

					// 初装逐列逐行，覆盖只完成锁存的那个向量。
					ST_ADVANCE:begin
						if(flag_update == 1'b1)begin
							update_done_o <= 1'b1; // 通知CAL可以继续该列。
						end else if(cnt_column == reg_width - 12'd1 && cnt_bank == reg_initial_rows - 2'd1)begin
						end else begin
							reg_vector_address <= reg_vector_address + {15'd0, reg_channels_padded, 1'b0}; // DDR完整向量跨度保持HWC。
							if(cnt_column == reg_width - 12'd1)begin
								cnt_column <= 12'd0; // 下一真实行从首列开始。
								cnt_bank <= cnt_bank + 2'd1; // 初装推进物理行。
								wr_bank_o <= cnt_bank + 2'd1; // 新命令绑定下一bank。
								reg_write_base <= 12'd0; // 每物理行缓存从零寻址。
								reg_initial_word <= 12'd0; // 新行首word归零。
							end else begin
								cnt_column <= cnt_column + 12'd1; // 本行推进空间列。
								reg_initial_word <= reg_initial_word + {4'd0, vector_words}; // 按tileword深度推进缓存。
								reg_write_base <= reg_initial_word + {4'd0, vector_words}; // 下一向量首缓存word。
							end
						end
					end

					// 只接受CAL显式授权，不猜测读游标或行角色。
					ST_READY:begin
						if(i_scan_finish == 1'b1)begin
							scan_done_o <= 1'b1; // 标签保持到下一scan请求。
						end else if(i_update_req == 1'b1 && update_ready_o == 1'b1)begin
							if(flag_update_bad == 1'b1)begin
								error_code_o <= 4'd3; // 覆盖坐标或bank错误。
							end else begin
								reg_update_row_offset <= update_row_offset; // 接受授权时冻结真实行乘积。
								reg_update_column_offset <= update_column_offset; // 同时保存对应列的HWC跨度。
								wr_bank_o <= i_update_bank; // 锁存被授权物理行。
								reg_write_base <= update_word_offset[11:0]; // 锁存该列缓存首word。
								flag_update <= 1'b1; // 授权仅覆盖这次命令全部quad。
							end
						end
					end

					// 乘积与四项地址求和分拍，CAL无需保持已接受请求坐标。
					ST_ADDRESS:begin
						reg_vector_address <= reg_feature_base + reg_update_row_offset + reg_update_column_offset + {15'd0, reg_tile_base, 1'b0}; // 使用同一授权的锁存行列及tile偏移。
					end

					// 命令等待或粘滞错误时冻结缓存游标。
					default:begin
						cnt_quad <= cnt_quad;   // 无数据握手不推进word计数。
					end
				endcase
			end
		end
	end

	//----------------状态机区域----------------//
	// 次态保持默认，真实命令握手优先于CAL暂停。
	always@(*)begin
		state_next = state_current;             // 未发生事件保持事务状态。
		if(cmd_valid_o == 1'b1 && i_cmd_ready == 1'b1)begin
			state_next = ST_RECEIVE;            // AXIS命令必须在每个FCLK采样。
		end else if(i_ce == 1'b1)begin
			case(state_current)

				// 配置与扫描共享空闲接收入口。
				ST_IDLE:begin
					if(i_start == 1'b1 && flag_config_bad == 1'b1)begin
						state_next = ST_ERROR;  // 配置失败立即阻断DMA。
					end else if(i_start == 1'b0 && i_scan_req == 1'b1 && scan_ready_o == 1'b1)begin
						state_next = flag_scan_bad ? ST_ERROR : ST_COMMAND; // 已验证扫描开始初装。
					end else begin
						state_next = ST_IDLE;   // 空闲沿没有发起任何事务。
					end
				end

				// 错误优先于数据和状态齐备。
				ST_RECEIVE:begin
					if((status_ready_o == 1'b1 && i_status_valid == 1'b1 && flag_status_bad == 1'b1) || (data_ready_o == 1'b1 && i_data_valid == 1'b1 && flag_frame_bad == 1'b1))begin
						state_next = ST_ERROR;  // 首个协议或状态错误终止扫描。
					end else if(flag_data_done == 1'b1 && flag_status_done == 1'b1)begin
						state_next = ST_ADVANCE; // 完整数据和状态均已锁存。
					end else begin
						state_next = ST_RECEIVE; // 继续等待缺失完成条件。
					end
				end

				// 当前向量完成后选择下一初装或CAL消费。
				ST_ADVANCE:begin
					if(flag_update == 1'b1 || (cnt_column == reg_width - 12'd1 && cnt_bank == reg_initial_rows - 2'd1))begin
						state_next = ST_READY;  // 初装全部行或单次覆盖成功。
					end else begin
						state_next = ST_COMMAND; // 下一向量命令串行发出。
					end
				end

				// CAL决定安全覆盖及扫描结束。
				ST_READY:begin
					if(i_scan_finish == 1'b1)begin
						state_next = ST_IDLE;   // 保留层配置等待下一group/tile。
					end else if(i_update_req == 1'b1 && update_ready_o == 1'b1)begin
						state_next = flag_update_bad ? ST_ERROR : ST_ADDRESS; // 合法授权先锁存完整HWC偏移。
					end else begin
						state_next = ST_READY;  // 无授权不写旧向量。
					end
				end

				// 地址形成后再发布命令，CE暂停时保持捕获的坐标。
				ST_ADDRESS:begin
					state_next = ST_COMMAND;    // 已注册地址满足下一拍命令载荷稳定。
				end

				// 命令等待和错误态由握手或复位退出。
				default:begin
					state_next = state_current; // 不创建隐式事务。
				end
			endcase
		end else begin
			state_next = state_current;         // CAL暂停保持所有非命令事件。
		end
	end

	// 状态与数据过程共用低有效异步复位及同步清控制请求。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			state_current <= ST_IDLE;           // 与DataMover同源硬复位。
		end else if(i_soft_reset == 1'b1)begin
			state_current <= ST_IDLE;           // 顶层先排空DataMover后同步复位。
		end else begin
			state_current <= state_next;        // 每沿提交已确定的次态。
		end
	end

endmodule
