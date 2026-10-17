`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/09 00:00:00
// Design Name:     output_cmd
// Module Name:     output_cmd
// Description:     description/output_cmd_Design.pdf
// Simulations:     testbench/vivado/2021.1/output_cmd
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/output_cmd_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/09 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/09       V1.0        Codex             Create HWC S2MM output controller.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月09日
// 设计名称:        output_cmd
// 模块名称:        output_cmd
// 模块说明:        Description/output_cmd_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/output_cmd
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/output_cmd_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月09日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月09日   V1.0        Codex             创建固定HWC输出写回控制器

module output_cmd
(
	//-----------------用户接口-----------------//
	input i_clk,                                // 与HP2及结果队列共用FCLK。
	input i_rstn,                               // 低有效异步复位，上游同域同步释放。
	input i_ce,                                 // 暂停准备和新出队，已发布事务仍握手。
	input i_soft_reset,                         // 先静止DMA，再与FIFO及生产者共同复位。
	input i_start,                              // 空闲锁存完整层指令。
	input [255:0]i_base_instruction,            // 论文基础指令原位序。
	input [255:0]i_extension,                   // 工程扩展字原位序。
	output o_start_ready,                       // 双FIFO及packer空才接受层。
	output o_busy,                              // 当前层还有写回或屏障待完成。
	input [9:0]i_group_index,                   // CAL当前完整输出组。
	output [9:0]o_group_index,                  // 完成资格绑定的当前组。
	output o_group_write_done,                  // 本组成功状态齐备，保持到CAL切组。
	input i_compute_done,                       // 计算完成单拍，暂停也锁存。
	input i_packer_busy,                        // 结果级未排空禁止完成。
	input i_dependency_error,                   // 上游错误粘滞阻断写回。
	output o_output_done,                       // 写响应和结果排空齐备的单FCLK完成。
	output o_error,                             // 首错误粘滞至共同复位。
	output [3:0]o_error_code,                   // 一配置二地址三状态四mask五早响应六依赖七组标签。
	output [31:0]o_commands_accepted,           // 实际命令握手累计。
	output [31:0]o_data_beats,                  // HP2实际数据握手累计。
	output [31:0]o_responses_ok,                // 精确80成功响应累计。

	//SPATIAL_FIFO接口
	input i_spatial_fifo_valid,                 // 空间及后处理队首有效。
	output o_spatial_fifo_ready,                // 仅选中路队首进入holding。
	input [63:0]i_spatial_fifo_data,            // 空间四lane低位在前。
	input [3:0]i_spatial_fifo_mask,             // 四lane参与前缀。
	input i_spatial_fifo_empty,                 // 空间私有队列排空。

	//BYPASS_FIFO接口
	input i_bypass_fifo_valid,                  // 旁路私有队首有效。
	output o_bypass_fifo_ready,                 // 仅旁路层允许出队。
	input [63:0]i_bypass_fifo_data,             // 旁路四lane结果。
	input [3:0]i_bypass_fifo_mask,              // 旁路参与标签。
	input i_bypass_fifo_empty,                  // 旁路私有队列排空。

	//CMD接口
	output o_cmd_valid,                         // 命令保持到ready，不因ce撤销。
	input i_cmd_ready,                          // HP2命令接受资格。
	output [71:0]o_cmd_data,                    // TAG0、地址、EOF1、INCR和BTT。
	output o_data_valid,                        // holding有效保持到HP2接受。
	input i_data_ready,                         // HP2当前数据接受许可。
	output [63:0]o_data,                        // mask无效INT16清零后的数据。
	output [7:0]o_data_keep,                    // 完整补齐beat固定ff。
	output o_data_last,                         // 当前命令末数据beat。
	input i_status_valid,                       // 当前唯一在途命令的状态。
	output o_status_ready,                      // 暂停期间也接收写响应。
	input [7:0]i_status                         // TAG0成功精确80。
);

	//---------------状态参数区域---------------//
	localparam ST_IDLE = 4'd0;                  // 旧任务和队列已排空。
	localparam ST_COUNTS = 4'd1;                // 常数除法形成组数。
	localparam ST_GEOMETRY = 4'd2;              // 寄存输出宽度。
	localparam ST_SPATIAL = 4'd3;               // 寄存输出空间总量。
	localparam ST_LIMIT = 4'd4;                 // 宽化DDR末址。
	localparam ST_CHECK = 4'd5;                 // 开放事务前校验。
	localparam ST_PREPARE = 4'd6;               // 当前组尾数和命令准备。
	localparam ST_COMMAND = 4'd7;               // 稳定呈现命令到接受。
	localparam ST_STREAM = 4'd8;                // 单beat弹性holding发送。
	localparam ST_STATUS = 4'd9;                // 最后数据之后等待写状态。
	localparam ST_ADVANCE = 4'd10;              // 成功事务后推进算法游标。
	localparam ST_GROUP = 4'd11;                // 旧组完成保持到CAL切组。
	localparam ST_FINISH = 4'd12;               // 计算和全部结果排空屏障。
	localparam ST_ERROR = 4'd15;                // 错误只由共同复位恢复。

	//-----------------计数信号-----------------//
	reg [31:0]cnt_spatial = 0;                  // 当前组已完成空间事务数。
	reg [4:0]cnt_word = 0;                      // 当前命令已暂存quad数量。
	reg [9:0]cnt_post_quad = 0;                 // 后处理当前HWC通道quad。

	//----------------状态机信号----------------//
	reg [3:0]state_current = ST_IDLE;           // 单命令在途阶段。
	reg [3:0]state_next = 0;                    // 完整握手形成次态。

	//----------------寄存器信号----------------//
	reg [3:0]reg_opcode = 0;                    // 配置锁存的算子。
	reg [1:0]reg_mode = 0;                      // CU输出并行类别。
	reg [1:0]reg_stride = 0;                    // 横向输出步长。
	reg [1:0]reg_padding = 0;                   // 横向虚拟列。
	reg [2:0]reg_kernel = 0;                    // 已译码的卷积核宽。
	reg [11:0]reg_width = 0;                    // 原输入宽度。
	reg [15:0]reg_height_out = 0;               // 软件预检后的输出高度。
	reg [12:0]reg_width_out = 0;                // 寄存横向输出数量。
	reg [12:0]reg_outputs = 0;                  // 恢复4096的逻辑Cout。
	reg [15:0]reg_padded_outputs = 0;           // 原扩展字Cout_padded。
	reg [13:0]reg_group_numerator = 0;          // 加法与组数除法分拍。
	reg [10:0]reg_groups = 0;                   // 输出组数，包括后处理1024。
	reg [10:0]reg_post_quads = 0;               // 每个后处理像素quad数。
	reg [12:0]reg_output_base = 0;              // 当前卷积组首逻辑通道。
	reg [6:0]reg_lanes = 0;                     // 本事务逻辑参与lane数。
	reg [4:0]reg_words = 0;                     // 当前命令应发送beat数。
	reg [22:0]reg_bytes = 0;                    // 当前稳定命令BTT。
	reg [31:0]reg_origin = 0;                   // 当前层输出首地址。
	reg [31:0]reg_cursor = 0;                   // 下一命令地址游标。
	reg [31:0]reg_address = 0;                  // 已准备命令地址保持。
	reg [15:0]reg_pixel_bytes = 0;              // 跨像素HWC字节步长。
	reg [23:0]reg_output_elements = 0;          // 原O_TRANS_NUM，不重算完整张量。
	reg [31:0]reg_total_beats = 0;              // 软件传输总量四lane换算。
	(* use_dsp="no" *) reg [31:0]reg_spatial_total = 0; // 准备阶段空间数量使用逻辑资源。
	reg [31:0]reg_input_start = 0;              // 原输入地址用于重叠保护。
	reg [23:0]reg_input_elements = 0;           // 原输入传输总量。
	reg [32:0]reg_input_limit = 0;              // 输入末址防32位绕回。
	reg [32:0]reg_output_limit = 0;             // 输出张量完整末址。
	reg [19:0]reg_reserved = 0;                 // 原保留字段必须为零。
	reg [3:0]reg_raw_mode = 0;                  // 模式字段高位也参与非法判断。

	//-----------------标志信号-----------------//
	reg flag_compute_done = 0;                  // CAL单拍已保存。
	wire flag_compute;                          // CONV/FC使用组空间地址。
	wire flag_bypass;                           // 仅CONV单点或FC选择旁路FIFO。
	wire flag_fifo_valid;                       // 所选FIFO当前队首存在。
	wire flag_pop;                              // 当前队首进入holding的真实事件。
	wire flag_command;                          // 当前命令与HP2共同接受。
	wire flag_data;                             // holding当前数据被HP2接受。
	wire flag_status;                           // 当前在途状态被接收。
	wire flag_status_bad;                       // 非精确成功状态或早成功。
	wire flag_mask_bad;                         // 所选队首资格与当前quad不符。
	wire flag_config_bad;                       // 请求前保护条件不符。
	wire flag_address_bad;                      // 当前命令越界或非对齐。
	wire flag_finish;                           // 最后成功响应和结果排空齐备。

	wire flag_range_valid;                      // 完整输出位于工程允许写区。

	//-----------------其他信号-----------------//
	//当前quad与DDR范围
	wire [12:0]remaining_outputs;               // 当前组之后剩余逻辑Cout。
	wire [6:0]remaining_lanes;                  // 当前quad实际逻辑参与数。
	wire [3:0]expected_mask;                    // 尾quad的明确有效前缀。
	wire [63:0]fifo_data;                       // 已选路径的未清尾数据。
	wire [3:0]fifo_mask;                        // 已选路径的参与标签。
	wire [12:0]horizontal_extent;               // 卷积完整核起点数量减一。
	wire [32:0]command_limit;                   // 当前事务宽化末址。

	//-----------------输出信号-----------------//
	//用户接口
	wire start_ready_o;                         // 空闲且旧结果排空。
	wire busy_o;                                // 配置和写回仍进行。
	reg [9:0]group_index_o = 0;                 // 完成响应完整组标签。
	reg group_write_done_o = 0;                 // 本组最后写成功资格保持。
	reg output_done_o = 0;                      // 独立单FCLK层完成通知。
	reg [3:0]error_code_o = 0;                  // 首错误锁存。
	reg [31:0]commands_accepted_o = 0;          // 真实命令接受累计。
	reg [31:0]data_beats_o = 0;                 // 实际流发送累计。
	reg [31:0]responses_ok_o = 0;               // 精确成功状态累计。

	//用户接口SPATIAL_FIFO接口
	wire spatial_fifo_ready_o;                  // 空间路独占出队资格。

	//用户接口BYPASS_FIFO接口
	wire bypass_fifo_ready_o;                   // 旁路独占出队资格。

	//用户接口CMD接口
	wire cmd_valid_o;                           // 当前命令不受ce撤销。
	wire [71:0]cmd_data_o;                      // 稳定地址和BTT完整组合。
	reg data_valid_o = 0;                       // holding拥有一笔数据。

	//用户接口CMD接口
	//用户接口
	reg [63:0]data_o = 0;                       // 零填充后的在途beat。
	reg data_last_o = 0;                        // holding所属命令末beat。
	wire status_ready_o;                        // 仅接收当前命令状态。

	//---------------其他信号连线---------------//
	//其他信号连线
	//类别、尾数与保护
	assign flag_compute = reg_opcode < 2;       // 后处理保持连续HWC。
	assign flag_bypass = flag_compute && reg_mode[1]; // 后处理固定模式不能选择旁路。
	assign flag_fifo_valid = flag_bypass ? i_bypass_fifo_valid : i_spatial_fifo_valid; // 未选FIFO绝不消费。
	assign fifo_data = flag_bypass ? i_bypass_fifo_data : i_spatial_fifo_data; // 两路完整beat选择。
	assign fifo_mask = flag_bypass ? i_bypass_fifo_mask : i_spatial_fifo_mask; // 数据与mask共用路由。
	assign remaining_outputs = reg_outputs - reg_output_base; // 热路径只用组通道游标减法。
	assign remaining_lanes = flag_compute ? reg_lanes - {cnt_word, 2'b00} : (reg_outputs - {1'b0, cnt_post_quad, 2'b00} >= 4 ? 7'd4 : reg_outputs - {1'b0, cnt_post_quad, 2'b00}); // 后处理尾quad按逻辑Cout。
	assign expected_mask = remaining_lanes >= 4 ? 4'hf : (4'h1 << remaining_lanes) - 4'h1; // 连续有效lane数转前缀。
	assign horizontal_extent = {1'b0, reg_width} + {10'd0, reg_padding, 1'b0} - {10'd0, reg_kernel}; // 仅准备阶段参与横向几何。
	assign command_limit = {1'b0, reg_address} + {10'd0, reg_bytes}; // 每笔命令防越过整层范围。
	assign flag_range_valid = (reg_origin >= 32'h05000000 && reg_output_limit <= 33'h011000000) || (reg_origin >= 32'h04200000 && reg_output_limit <= 33'h004400000); // feature和最终result区均允许。
	assign flag_config_bad = reg_opcode > 4 || reg_raw_mode > 3 || reg_reserved != 0 || reg_outputs == 0 || reg_padded_outputs != ((reg_outputs + 13'd3) & 13'h1ffc) || reg_output_elements == 0 || reg_output_elements[1:0] != 0 || reg_origin[2:0] != 0 || !flag_range_valid || !(reg_output_limit <= {1'b0, reg_input_start} || {1'b0, reg_origin} >= reg_input_limit) || (flag_compute && (reg_width == 0 || reg_height_out == 0 || reg_spatial_total == 0 || (reg_opcode == 0 && (reg_mode == 3 || reg_stride == 0 || reg_stride > 2 || reg_padding > 1 || {1'b0, reg_width} + {10'd0, reg_padding, 1'b0} < {10'd0, reg_kernel})) || (reg_opcode == 1 && reg_mode != 3))); // 静态总量一致性由软件和分发器保证。
	assign flag_address_bad = reg_address[2:0] != 0 || reg_bytes == 0 || reg_bytes[2:0] != 0 || command_limit > reg_output_limit; // 提交前阻止写越界。
	assign flag_mask_bad = state_current == ST_STREAM && i_ce && !data_valid_o && flag_fifo_valid && fifo_mask != expected_mask; // 消费前拒绝错序或非法lane标签。
	assign flag_pop = state_current == ST_STREAM && i_rstn && i_ce && !data_valid_o && flag_fifo_valid && !flag_mask_bad && !flag_status_bad && !i_dependency_error; // 一次holding只取一个队首。
	assign flag_command = cmd_valid_o && i_cmd_ready; // 命令实际接受与软件暂停无关。
	assign flag_data = i_rstn && data_valid_o && i_data_ready && !flag_status_bad && !i_dependency_error; // 已发布beat在暂停期间继续协议记账。
	assign flag_status = i_status_valid && status_ready_o; // 只有唯一在途命令可消费状态。
	assign flag_status_bad = flag_status && (i_status != 8'h80 || state_current != ST_STATUS); // 成功状态不能早于末数据接受。
	assign flag_finish = flag_compute_done && !i_packer_busy && i_spatial_fifo_empty && i_bypass_fifo_empty; // 结果级和两队列分别检查。

	//用户接口
	assign start_ready_o = i_rstn && i_ce && state_current == ST_IDLE && !i_packer_busy && i_spatial_fifo_empty && i_bypass_fifo_empty; // 不允许旧层数据混入新层。
	assign busy_o = state_current != ST_IDLE && state_current != ST_ERROR; // 错误独立报告。
	assign spatial_fifo_ready_o = flag_pop && !flag_bypass; // 只选中空间队首。
	assign bypass_fifo_ready_o = flag_pop && flag_bypass; // 只选中旁路队首。
	assign cmd_valid_o = i_rstn && state_current == ST_COMMAND && !flag_address_bad && !i_dependency_error; // VALID保持，越界配置在发布前阻断。
	assign cmd_data_o = {8'd0, reg_address, 9'h081, reg_bytes}; // EOF和INCR固定，DSA及TAG为零。
	assign status_ready_o = i_rstn && (state_current == ST_STREAM || state_current == ST_STATUS); // 用户暂停也能保存真实响应。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_start_ready = start_ready_o;       // 分发器以此锁存配置。
	assign o_busy = busy_o;                     // 当前层生命周期状态。
	assign o_group_index = group_index_o;       // CONV/FC完成绑定完整组标签，后处理保持零。
	assign o_group_write_done = group_write_done_o; // CAL切组或后处理整流完成均等待真实写响应。
	assign o_output_done = output_done_o;       // 不与compute_done合并。
	assign o_error = error_code_o != 0;         // 非零诊断表示粘滞错误。
	assign o_error_code = error_code_o;         // 保留首错误种类。
	assign o_commands_accepted = commands_accepted_o; // 命令数量单独可观测。
	assign o_data_beats = data_beats_o;         // 数据发送单独可观测。
	assign o_responses_ok = responses_ok_o;     // 最后成功状态单独可观测。

	//用户接口SPATIAL_FIFO接口
	assign o_spatial_fifo_ready = spatial_fifo_ready_o; // 未选路保持不消费。

	//用户接口BYPASS_FIFO接口
	assign o_bypass_fifo_ready = bypass_fifo_ready_o; // 与空间路互斥。

	//用户接口CMD接口
	assign o_cmd_valid = cmd_valid_o;           // 已发布命令直到接受保持。
	assign o_cmd_data = cmd_data_o;             // 反压时地址和长度均寄存稳定。

	//用户接口
	assign o_data_valid = i_rstn && data_valid_o && !flag_status_bad && !i_dependency_error; // holding不随ce丢资格。
	assign o_data = data_o;                     // 尾lane零填充保持到握手。
	assign o_data_keep = 8'hff;                 // DDR张量按四lane完整补齐。
	assign o_data_last = data_last_o;           // 与holding数据保持同一命令边界。
	assign o_status_ready = status_ready_o;     // 错误状态可及早终止在途流。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 算法准备受ce约束，已发布协议事务独立完成并记账。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_opcode <= 0; reg_mode <= 0; reg_stride <= 0; reg_padding <= 0; reg_kernel <= 0; // 清配置类别和几何资格。
			reg_width <= 0; reg_height_out <= 0; reg_width_out <= 0; reg_outputs <= 0; reg_padded_outputs <= 0; // 旧张量尺寸无效。
			reg_group_numerator <= 0; reg_groups <= 0; reg_post_quads <= 0; reg_output_base <= 0; // 旧组游标清零。
			reg_lanes <= 0; reg_words <= 0; reg_bytes <= 0; reg_origin <= 0; reg_cursor <= 0; reg_address <= 0; reg_pixel_bytes <= 0; // 旧命令不能重新发布。
			reg_output_elements <= 0; reg_total_beats <= 0; reg_spatial_total <= 0; // 清数量目标。
			reg_input_start <= 0; reg_input_elements <= 0; reg_input_limit <= 0; reg_output_limit <= 0; reg_reserved <= 0; reg_raw_mode <= 0; // 清区域保护上下文。
			cnt_spatial <= 0; cnt_word <= 0; cnt_post_quad <= 0; // 旧事务坐标失效。
			group_index_o <= 0; group_write_done_o <= 0; output_done_o <= 0; error_code_o <= 0; // 不产生旧完成通知。
			commands_accepted_o <= 0; data_beats_o <= 0; responses_ok_o <= 0; // 硬复位清诊断累计。
			data_valid_o <= 0; data_o <= 0; data_last_o <= 0; flag_compute_done <= 0; // 异步撤销在途holding资格。
		end else if(i_soft_reset == 1'b1)begin
			group_write_done_o <= 0; output_done_o <= 0; error_code_o <= 0; // DMA静止后同步取消完成。
			data_valid_o <= 0; data_last_o <= 0; flag_compute_done <= 0; // 共同清控制隔离旧FIFO载荷。
			commands_accepted_o <= 0; data_beats_o <= 0; responses_ok_o <= 0; // 新任务重新建立累计。
		end else begin
			output_done_o <= 0;                 // 完成严格只占一个FCLK，与ce无关。
			if(state_current != ST_IDLE && i_compute_done == 1'b1)begin
				flag_compute_done <= 1;         // 暂停期间CAL单拍不会丢失。
			end
			if(i_dependency_error == 1'b1 && state_current != ST_IDLE && state_current != ST_ERROR)begin
				error_code_o <= 4'd6; data_valid_o <= 0; // 上游故障禁止新写回。
			end else if(flag_status_bad == 1'b1)begin
				error_code_o<=i_status!=8'h80 ? 4'd3: 4'd5; data_valid_o <= 0; // 失败TAG/错误或早成功不能计数。
			end else if(flag_mask_bad == 1'b1)begin
				error_code_o <= 4'd4;           // 错误队首未出队，不发送脏数据。
			end else if(state_current == ST_COMMAND && flag_address_bad == 1'b1)begin
				error_code_o <= 4'd2;           // 当前事务越界即使暂停也不能发布。
			end else if(start_ready_o == 1'b1 && i_start == 1'b1)begin
				reg_opcode <= i_extension[171:168]; reg_mode <= i_base_instruction[197:196]; // 锁存算子并保持到层末。
				reg_raw_mode <= i_base_instruction[199:196]; reg_reserved <= i_base_instruction[255:236]; // 原高位不能被缩位掩盖。
				reg_stride <= i_base_instruction[201:200]; reg_padding <= i_base_instruction[203:202]; // 恢复横向卷积配置。
				reg_kernel <= i_base_instruction[197] ? 3'd1 : (i_base_instruction[196] ? 3'd2 : 3'd3); // 核大小固定译码。
				reg_width <= i_base_instruction[147:136]; reg_height_out <= i_extension[127:112]; // 输出高度采用软件字段。
				reg_outputs <= i_base_instruction[195:184] == 0 ? 13'd4096 : {1'b0, i_base_instruction[195:184]}; // 零编码还原4096。
				reg_padded_outputs <= i_extension[159:144]; reg_pixel_bytes <= {i_extension[158:144], 1'b0}; // HWC像素字节步长提前寄存。
				reg_group_numerator <= (i_base_instruction[195:184] == 0 ? 14'd4096 : {2'd0, i_base_instruction[195:184]}) + (i_extension[171:168] >= 2 ? 14'd3 : (i_base_instruction[197] ? 14'd71 : 14'd7)); // 加法先于常数除法。
				reg_origin <= i_base_instruction[63:32]; reg_cursor <= i_base_instruction[63:32]; // 当前组首空间从输出首地址开始。
				reg_input_start <= i_base_instruction[31:0]; reg_input_elements <= i_base_instruction[87:64]; // 原输入传输范围用于保护。
				reg_output_elements <= i_base_instruction[227:204]; reg_total_beats <= {10'd0, i_base_instruction[227:206]}; // 原INT16数量换成四lane，不新增字段。
				cnt_spatial <= 0; cnt_word <= 0; cnt_post_quad <= 0; reg_output_base <= 0; group_index_o <= 0; // 新层重建算法游标。
				group_write_done_o <= 0; flag_compute_done <= 0; error_code_o <= 0; // 旧完成资格不得影响新层。
				commands_accepted_o <= 0; data_beats_o <= 0; responses_ok_o <= 0; data_valid_o <= 0; // 新层独立事务记账。
			end else begin
				if(flag_command == 1'b1)begin
					commands_accepted_o <= commands_accepted_o + 32'd1; cnt_word <= 0; // 命令游标与流消费分开维护。
					reg_cursor <= reg_cursor + (flag_compute ? {16'd0, reg_pixel_bytes} : 32'd8); // 下一地址只在真实命令接受后推进。
				end
				if(flag_pop == 1'b1)begin
					data_o <= {fifo_mask[3] ? fifo_data[63:48] : 16'd0, fifo_mask[2] ? fifo_data[47:32] : 16'd0, fifo_mask[1] ? fifo_data[31:16] : 16'd0, fifo_mask[0] ? fifo_data[15:0] : 16'd0}; // 四个补齐INT16必须清除无效lane。
					data_last_o <= cnt_word == reg_words - 1'b1; data_valid_o <= 1; cnt_word <= cnt_word + 5'd1; // TLAST随数据锁存，不依赖外部ready。
				end else if(flag_data == 1'b1)begin
					data_valid_o <= 0; data_beats_o <= data_beats_o + 32'd1; // 只统计实际HP2数据握手。
				end
				if(flag_status == 1'b1)begin
					responses_ok_o <= responses_ok_o + 32'd1; // 已排除非80及早响应。
				end
				if(i_ce == 1'b1)begin
					case(state_current)

						// 形成完整组数和HWC通道quad数。
						ST_COUNTS:begin
							reg_groups <= reg_opcode >= 2 ? reg_group_numerator >> 2 : (reg_mode[1] ? reg_group_numerator / 14'd72 : reg_group_numerator / 14'd8); // 固定并行度的常数除法。
							reg_post_quads <= reg_padded_outputs[12:2]; // 通道补齐由软件和配置保护共同保证。
						end

						// 按算子准备横向输出数量。
						ST_GEOMETRY:begin
							reg_width_out <= reg_opcode == 1 || reg_opcode == 4 ? 13'd1 : (reg_opcode == 3 ? {1'b0, reg_width} : (reg_opcode == 2 ? {1'b0, reg_width} >> 1 : (reg_stride == 2 ? (horizontal_extent >> 1) + 13'd1 : horizontal_extent + 13'd1))); // 各算子输出宽度独立译码。
						end

						// 形成组内空间位置总数。
						ST_SPATIAL:begin
							reg_spatial_total <= reg_width_out * reg_height_out; // 空间总量只在准备阶段形成。
						end

						// 宽化输入输出张量末地址。
						ST_LIMIT:begin
							reg_output_limit <= {1'b0, reg_origin} + {8'd0, reg_output_elements, 1'b0}; // 宽化整层写区末址。
							reg_input_limit <= {1'b0, reg_input_start} + {8'd0, reg_input_elements, 1'b0}; // 输入末址不能32位绕回。
						end

						// 写入前检查字段和区域保护。
						ST_CHECK:begin
							if(flag_config_bad == 1'b1)begin
								error_code_o <= 4'd1; // 任何写命令之前拒绝非法配置。
							end
						end

						// 准备当前组尾数及稳定命令载荷。
						ST_PREPARE:begin
							reg_lanes <= flag_compute ? (remaining_outputs > (reg_mode[1] ? 13'd72 : 13'd8) ? (reg_mode[1] ? 7'd72 : 7'd8) : remaining_outputs[6:0]) : 7'd4; // 当前尾组保持逻辑长度。
							reg_words <= flag_compute ? (remaining_outputs > (reg_mode[1] ? 13'd72 : 13'd8) ? (reg_mode[1] ? 5'd18 : 5'd2) : (remaining_outputs[6:0] + 7'd3) >> 2) : 5'd1; // 末组补齐完整四lane。
							reg_bytes <= flag_compute ? (remaining_outputs > (reg_mode[1] ? 13'd72 : 13'd8) ? (reg_mode[1] ? 23'd144 : 23'd16) : {13'd0, ((remaining_outputs[6:0] + 7'd3) & 7'h7c), 1'b0}) : 23'd8; // 一空间一命令，后处理一beat一命令。
							reg_address <= reg_cursor; // 准备完成后VALID期间保持不变。
						end

						// 保持命令直到HP2接受。
						ST_COMMAND:begin
							if(flag_address_bad == 1'b1)begin
								error_code_o <= 4'd2; // 事务越界不允许提交。
							end
						end

						// 成功事务之后推进空间或HWC游标。
						ST_ADVANCE:begin
							if(flag_compute == 1'b1)begin
								cnt_spatial <= cnt_spatial + 32'd1; // 仅成功写响应之后完成空间事务。
								if(cnt_spatial == reg_spatial_total - 1'b1)begin
									group_write_done_o <= 1; // 当前组最后成功状态保存至切组。
								end
							end else begin
								cnt_post_quad <= cnt_post_quad == reg_post_quads - 1'b1 ? 10'd0 : cnt_post_quad + 10'd1; // 后处理空间外层通道内层。
								if(commands_accepted_o == reg_total_beats)begin
									group_write_done_o <= 1; // 后处理整流写回先释放CAL，随后等待compute_done。
								end
							end
						end

						// 当前组完成保持至CAL进入下一组。
						ST_GROUP:begin
							if(i_group_index == group_index_o + 10'd1)begin
								group_index_o <= group_index_o + 10'd1; reg_output_base <= reg_output_base + (reg_mode[1] ? 13'd72 : 13'd8); // 下一完整组重新建立尾数。
								reg_cursor <= reg_origin + {18'd0, reg_output_base, 1'b0} + (reg_mode[1] ? 32'd144 : 32'd16); // 新组从首像素的组内偏移开始。
								cnt_spatial <= 0; group_write_done_o <= 0; // 清旧完成后才能写新组。
							end else if(i_group_index != group_index_o)begin
								error_code_o <= 4'd7; // 跳组不能静默关联错误数据。
							end
						end

						// 最终响应及计算和结果排空共同屏障。
						ST_FINISH:begin
							if(flag_finish == 1'b1)begin
								if(data_beats_o == reg_total_beats && commands_accepted_o == responses_ok_o)begin
									output_done_o <= 1; // 最后真实成功响应及排空条件都已齐备。
								end else begin
									error_code_o <= 4'd2; // 软件总量与实际写回不符，禁止成功通知。
								end
							end
						end

						// 未知阶段保留游标并禁止新写入。
						default:begin
							cnt_spatial <= cnt_spatial; // 协议阶段和空闲不改变算法空间游标。
						end
					endcase
				end
			end
		end
	end

	//----------------状态机区域----------------//
	// shortcut: 仅一个S2MM命令在途，HP2实测吞吐不足时再增加有界事务队列。
	// 次态已包含算法ce和不受ce阻断的真实协议事件。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			state_current <= ST_IDLE;           // 硬复位立即停止旧任务。
		end else if(i_soft_reset == 1'b1)begin
			state_current <= ST_IDLE;           // 共同同步清控制后可重新配置。
		end else begin
			state_current <= state_next;        // 真实接受事件不能因用户暂停漏记。
		end
	end

	// 准备受ce保持，发布后的AXIS阶段按实际握手推进。
	always@(*)begin
		state_next = state_current;             // 未满足当前阶段的完整握手时保持上下文。
		if(i_dependency_error == 1'b1 && state_current != ST_IDLE && state_current != ST_ERROR)begin
			state_next = ST_ERROR;              // 依赖模块已失败，不允许新的写回任务。
		end else if(flag_status_bad == 1'b1 || flag_mask_bad == 1'b1)begin
			state_next = ST_ERROR;              // 当前队首或S2MM响应违反事务合同。
		end else begin
			case(state_current)

				// 等待新层且旧结果已经排空。
				ST_IDLE:begin
					if(start_ready_o == 1'b1 && i_start == 1'b1)begin
						state_next = ST_COUNTS; // 完成等待新层且旧结果已经排空后进入形成完整组数和HWC通道quad数。
					end else begin
						state_next = ST_IDLE;   // 等待新层且旧结果已经排空暂不提交。
					end
				end

				// 形成完整组数和HWC通道quad数。
				ST_COUNTS:begin
					if(i_ce == 1'b1)begin
						state_next = ST_GEOMETRY; // 完成形成完整组数和HWC通道quad数后进入按算子准备横向输出数量。
					end else begin
						state_next = ST_COUNTS; // 形成完整组数和HWC通道quad数暂不提交。
					end
				end

				// 按算子准备横向输出数量。
				ST_GEOMETRY:begin
					if(i_ce == 1'b1)begin
						state_next = ST_SPATIAL; // 完成按算子准备横向输出数量后进入形成组内空间位置总数。
					end else begin
						state_next = ST_GEOMETRY; // 按算子准备横向输出数量暂不提交。
					end
				end

				// 形成组内空间位置总数。
				ST_SPATIAL:begin
					if(i_ce == 1'b1)begin
						state_next = ST_LIMIT;  // 完成形成组内空间位置总数后进入宽化输入输出张量末地址。
					end else begin
						state_next = ST_SPATIAL; // 形成组内空间位置总数暂不提交。
					end
				end

				// 宽化输入输出张量末地址。
				ST_LIMIT:begin
					if(i_ce == 1'b1)begin
						state_next = ST_CHECK;  // 完成宽化输入输出张量末地址后进入写入前检查字段和区域保护。
					end else begin
						state_next = ST_LIMIT;  // 宽化输入输出张量末地址暂不提交。
					end
				end

				// 写入前检查字段和区域保护。
				ST_CHECK:begin
					if(i_ce == 1'b1)begin
						state_next = flag_config_bad ? ST_ERROR : ST_PREPARE; // 非法配置不开放写命令。
					end else begin
						state_next = ST_CHECK;  // 写入前检查字段和区域保护暂不提交。
					end
				end

				// 准备当前组尾数及稳定命令载荷。
				ST_PREPARE:begin
					if(i_ce == 1'b1)begin
						state_next = ST_COMMAND; // 完成准备当前组尾数及稳定命令载荷后进入保持命令直到HP2接受。
					end else begin
						state_next = ST_PREPARE; // 准备当前组尾数及稳定命令载荷暂不提交。
					end
				end

				// 保持命令直到HP2接受。
				ST_COMMAND:begin
					if(flag_address_bad == 1'b1)begin
						state_next = ST_ERROR;  // 完成保持命令直到HP2接受后进入错误粘滞禁止后续命令。
					end else if(flag_command == 1'b1)begin
						state_next = ST_STREAM; // 完成保持命令直到HP2接受后进入FIFO队首暂存后发送当前命令数据。
					end else begin
						state_next = ST_COMMAND; // 保持命令直到HP2接受暂不提交。
					end
				end

				// FIFO队首暂存后发送当前命令数据。
				ST_STREAM:begin
					if(flag_data == 1'b1 && data_last_o == 1'b1)begin
						state_next = ST_STATUS; // 完成FIFO队首暂存后发送当前命令数据后进入最后数据接受后等待成功写状态。
					end else begin
						state_next = ST_STREAM; // FIFO队首暂存后发送当前命令数据暂不提交。
					end
				end

				// 最后数据接受后等待成功写状态。
				ST_STATUS:begin
					if(flag_status == 1'b1)begin
						state_next = ST_ADVANCE; // 完成最后数据接受后等待成功写状态后进入成功事务之后推进空间或HWC游标。
					end else begin
						state_next = ST_STATUS; // 最后数据接受后等待成功写状态暂不提交。
					end
				end

				// 成功事务之后推进空间或HWC游标。
				ST_ADVANCE:begin
					if(i_ce == 1'b1)begin
						if(flag_compute == 1'b1)begin
							state_next = cnt_spatial == reg_spatial_total - 1'b1 ? (group_index_o == reg_groups - 1'b1 ? ST_FINISH : ST_GROUP) : ST_PREPARE; // 完成组或准备下一个空间位置。
						end else begin
							state_next = commands_accepted_o == reg_total_beats ? ST_FINISH : ST_PREPARE; // 后处理按原完整beat数连续写。
						end
					end else begin
						state_next = ST_ADVANCE; // 成功事务之后推进空间或HWC游标暂不提交。
					end
				end

				// 当前组完成保持至CAL进入下一组。
				ST_GROUP:begin
					if(i_ce == 1'b1 && i_group_index != group_index_o)begin
						state_next = i_group_index == group_index_o + 10'd1 ? ST_PREPARE : ST_ERROR; // 只允许CAL恰好进入下一组。
					end else begin
						state_next = ST_GROUP;  // 当前组完成保持至CAL进入下一组暂不提交。
					end
				end

				// 最终响应及计算和结果排空共同屏障。
				ST_FINISH:begin
					if(i_ce == 1'b1 && flag_finish == 1'b1)begin
						state_next = data_beats_o == reg_total_beats && commands_accepted_o == responses_ok_o ? ST_IDLE : ST_ERROR; // 结果数量与响应数量最终独立核对。
					end else begin
						state_next = ST_FINISH; // 最终响应及计算和结果排空共同屏障暂不提交。
					end
				end

				// 错误粘滞禁止后续命令。
				ST_ERROR:begin
					state_next = ST_ERROR;      // 错误粘滞禁止后续命令暂不提交。
				end

				// 未知阶段保留游标并禁止新写入。
				default:begin
					state_next = ST_ERROR;      // 状态编码损坏时封锁HP2请求。
				end
			endcase
		end
	end

endmodule
