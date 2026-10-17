`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/15 00:00:00
// Design Name:     pool_unit
// Module Name:     pool_unit
// Description:     description/pool_unit_Design.pdf
// Simulations:     testbench/vivado/2021.1/pool_unit
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/pool_unit_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/15 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/15       V1.0        Codex             Create pool_unit signed pooling read stream.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月15日
// 设计名称:        pool_unit
// 模块名称:        pool_unit
// 模块说明:        Description/pool_unit_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/pool_unit
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/pool_unit_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月15日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月15日   V1.0        Codex             创建池化读流与四lane最大值单元

module pool_unit
(
	//-----------------全局信号-----------------//
	input i_clk,                                // FCLK统一上升沿。
	input i_rstn,                               // 低有效异步复位，上游同步释放。

	//-----------------用户接口-----------------//
	input i_ce,                                 // 暂停算法提交，已发布协议继续握手。
	input i_start,                              // 锁存池化层原始指令。
	input [255:0]i_base_instruction,            // 输入地址、深度和几何。
	input [255:0]i_extension,                   // 高度与补齐深度。
	output o_start_ready,                       // 无在途事务时接受新层。
	output o_busy,                              // 配置或读流或输出仍在途。
	output o_error,                             // 首错误粘滞至共同复位。
	output [3:0]o_error_code,                   // 一配置二坐标三帧四状态五地址。

	//BLOCK接口
	input i_block_req,                          // CAL请求真实首行和通道块。
	output o_block_ready,                       // 可以替换读流块上下文。
	input [15:0]i_block_row,                    // 当前窗口真实首行。
	input [7:0]i_block,                         // 每块512通道的全局索引。
	input [9:0]i_block_channels,                // 当前块有效通道一至512。
	output o_block_done,                        // 块元数据就绪通知，不表示预装整行。

	//POST接口
	input i_post_valid,                         // 四角坐标token有效。
	output o_post_ready,                        // 当前无在途角点读。
	input [15:0]i_post_row,                     // 输入真实行。
	input [11:0]i_post_col,                     // 输入真实列。
	input [1:0]i_post_stage,                    // 左上右上左下右下顺序。
	input [6:0]i_post_quad,                     // 块内四通道索引。
	input [3:0]i_post_mask,                     // 最后quad的有效lane前缀。
	output o_post_done,                         // 当前四lane结果已交给B5。

	//RESULT接口
	output o_result_valid,                      // 窗口结果保持至接受。
	input i_result_ready,                       // B5单tile入口许可。
	output [63:0]o_result_data,                 // signed INT16最大值，尾lane补零。
	output [3:0]o_result_mask,                  // 当前结果通道有效位。

	//CMD接口
	output o_cmd_valid,                         // HP0命令保持至接受。
	input i_cmd_ready,                          // DataMover命令接受许可。
	output [71:0]o_cmd_data,                    // 对齐地址和固定八字节BTT。
	input i_data_valid,                         // 当前角点四lane输入。
	output o_data_ready,                        // 只有当前读事务能接收数据。
	input [63:0]i_data,                         // 四个小端INT16。
	input [7:0]i_data_keep,                     // 必须完整八字节。
	input i_data_last,                          // 单beat命令必须带TLAST。
	input i_status_valid,                       // 当前读事务完成状态。
	output o_status_ready,                      // 提前状态也接受并报告错误。
	input [7:0]i_status                         // 仅精确80为成功。
);

	//---------------状态参数区域---------------//
	localparam ST_COMMAND = 4'd4;               // 等待HP0命令接受。
	localparam ST_STATUS = 4'd6;                // 等待真实DMA成功状态。
	localparam ST_OUTPUT = 4'd8;                // 保持最终四lane结果。
	localparam ST_ERROR = 4'd9;                 // 停止新DMA至共同复位。
	localparam ST_IDLE = 4'd0;                  // 无在途角点读。
	localparam ST_CONFIG = 4'd1;                // 几何和DDR区域检查。
	localparam ST_STRIDE = 4'd2;                // 逐位形成行跨度，不新增DSP。
	localparam ST_ADDRESS = 4'd3;               // 检查已寄存角点地址。
	localparam ST_DATA = 4'd5;                  // 接收唯一数据beat。
	localparam ST_COMMIT = 4'd7;                // CE有效时累计最大值。

	//-----------------计数信号-----------------//
	reg [3:0]cnt_setup = 0;                     // 宽度串行乘法的当前位。
	reg [15:0]cnt_row = 0;                      // 当前池化窗口真实首行。
	reg [11:0]cnt_col = 0;                      // 当前池化窗口真实首列。
	reg [9:0]cnt_quad = 0;                      // 全局通道quad，最多1024组。
	reg [1:0]cnt_stage = 0;                     // 当前预期四角阶段。

	//----------------状态机信号----------------//
	reg [3:0]state_next;                        // 组合形成下一个协议状态。
	reg [3:0]state_current = 0;                 // 单事务控制状态。

	//----------------寄存器信号----------------//
	reg [11:0]reg_width = 0;                    // 输入实际宽度。
	reg [15:0]reg_height = 0;                   // 输入实际高度。
	reg [12:0]reg_channels = 0;                 // 输入输出逻辑通道相同。
	reg [15:0]reg_padded = 0;                   // 每像素向四补齐通道。
	reg [31:0]reg_pixel_bytes = 0;              // 一个HWC像素的物理字节数。
	reg [31:0]reg_row_bytes = 0;                // 完整输入一行的物理字节数。
	reg [31:0]reg_stride_term = 0;              // 行跨度乘法当前移位项。
	reg [32:0]reg_window_address = 0;           // 当前左上角首通道的完整DDR地址。
	reg [32:0]reg_address = 0;                  // 当前角点四lane地址，发布后保持。
	reg [32:0]reg_input_limit = 0;              // 输入张量末地址，包含绕回位。
	reg [63:0]reg_corner = 0;                   // 已收到但尚未成功确认的输入beat。
	reg [63:0]reg_maximum = 0;                  // 当前窗口已成功确认角点的lane最大值。
	reg [7:0]reg_block = 0;                     // 已确认512通道块标签。
	reg [15:0]reg_block_row = 0;                // 块元数据绑定当前真实窗口行。
	reg [9:0]reg_block_channels = 0;            // 尾块有效逻辑通道。
	reg [3:0]reg_config_error = 0;              // 原始字段检查结果随层锁存。

	//-----------------标志信号-----------------//
	wire flag_command_active;                   // 已发布命令等待HP0接受。
	wire flag_status_active;                    // 当前唯一读事务已收到完整数据。
	wire flag_output_active;                    // 四角结果等待B5入口。
	reg flag_configured = 0;                    // 行跨度准备完成后允许token。
	reg flag_block_valid = 0;                   // 块元数据已接受。
	wire flag_token_bad;                        // 坐标、阶段或尾lane不匹配。
	wire flag_address_bad;                      // 越界或非八字节对齐禁止发布。

	//-----------------其他信号-----------------//
	//输入真实深度及四通道比较值
	wire [12:0]remaining_channels;              // 当前quad的真实剩余深度。
	wire [3:0]expected_mask;                    // 低位连续参与lane。
	wire [63:0]maximum_data;                    // 四lane独立有符号比较结果。

	//-----------------输出信号-----------------//
	//用户接口
	reg [3:0]error_code_o = 0;                  // 首错停止本层后续请求。

	//用户接口BLOCK接口
	//用户接口
	reg block_done_o = 0;                       // 块接受后一个FCLK通知。

	//用户接口POST接口
	reg post_done_o = 0;                        // B5实际接受后一个FCLK通知。

	//用户接口RESULT接口
	reg [3:0]result_mask_o = 0;                 // 当前四角共同使用的有效lane。

	//---------------其他信号连线---------------//
	//协议状态译码
	assign flag_command_active = state_current == ST_COMMAND; // CE暂停仍须准确记录命令。
	assign flag_status_active = state_current == ST_STATUS; // 只有末数据之后才允许成功状态。
	assign flag_output_active = state_current == ST_OUTPUT; // 结果保持状态独立于软件暂停。

	//其他信号连线
	//坐标与数据安全检查
	assign remaining_channels = reg_channels - {1'b0, cnt_quad, 2'b00}; // 保留4096通道的最高位。
	assign expected_mask = remaining_channels >= 4 ? 4'hf : (4'h1 << remaining_channels) - 4'h1; // 无效尾lane不能参加最大值。

	//POST接口
	assign flag_token_bad = i_post_row != cnt_row + {15'd0, cnt_stage[1]} || i_post_col != cnt_col + {11'd0, cnt_stage[0]} || i_post_stage != cnt_stage || i_post_quad != cnt_quad[6:0] || i_post_mask != expected_mask || reg_block != {5'd0, cnt_quad[9:7]} || reg_block_row != cnt_row || {1'b0, i_post_quad, 2'b00} >= reg_block_channels; // 禁止旧块或乱序角点进入新窗口。

	//其他信号连线
	assign flag_address_bad = reg_address[2:0] != 0 || reg_address < 33'h005000000 || reg_address + 33'd8 > reg_input_limit; // 宽化末址阻止地址绕回和越界。
	assign maximum_data = {($signed(reg_maximum[63:48]) > $signed(reg_corner[63:48]) ? reg_maximum[63:48] : reg_corner[63:48]), ($signed(reg_maximum[47:32]) > $signed(reg_corner[47:32]) ? reg_maximum[47:32] : reg_corner[47:32]), ($signed(reg_maximum[31:16]) > $signed(reg_corner[31:16]) ? reg_maximum[31:16] : reg_corner[31:16]), ($signed(reg_maximum[15:0]) > $signed(reg_corner[15:0]) ? reg_maximum[15:0] : reg_corner[15:0])}; // 四通道互不混合。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_start_ready = i_rstn && i_ce && state_current == ST_IDLE; // 已完成旧事务才允许替换层。
	assign o_busy = state_current != ST_IDLE && state_current != ST_ERROR; // 空闲元数据不阻止层完成。
	assign o_error = error_code_o != 0;         // 错误保持至外部共同复位。
	assign o_error_code = error_code_o;         // 顶层复用Feature错误来源槽。

	//用户接口BLOCK接口
	assign o_block_ready = i_rstn && i_ce && flag_configured && state_current == ST_IDLE && cnt_stage == 0; // 块只能在新窗口quad之前替换。

	//用户接口
	assign o_block_done = block_done_o;         // CAL按FCLK保存，不依赖CE。

	//用户接口POST接口
	assign o_post_ready = i_rstn && i_ce && flag_configured && flag_block_valid && state_current == ST_IDLE; // 一个角点在途时保持CAL坐标。
	assign o_post_done = post_done_o;           // 四角输出真实接受之后才通知。

	//用户接口RESULT接口
	assign o_result_valid = i_rstn && state_current == ST_OUTPUT; // 反压及CE暂停不能撤销VALID。
	assign o_result_data = {result_mask_o[3] ? reg_maximum[63:48] : 16'd0, result_mask_o[2] ? reg_maximum[47:32] : 16'd0, result_mask_o[1] ? reg_maximum[31:16] : 16'd0, result_mask_o[0] ? reg_maximum[15:0] : 16'd0}; // 补齐lane明确清零。
	assign o_result_mask = result_mask_o;       // 与保持的结果载荷绑定。

	//用户接口CMD接口
	assign o_cmd_valid = i_rstn && state_current == ST_COMMAND; // 已寄存命令等待DataMover接受。
	assign o_cmd_data = {8'd0, reg_address[31:0], 9'h081, 23'd8}; // 每角点一个完整64位读。

	//用户接口
	assign o_data_ready = i_rstn && i_ce && state_current == ST_DATA; // 数据holding仅在算法允许时接收。
	assign o_status_ready = i_rstn && (state_current == ST_DATA || state_current == ST_STATUS); // 错误状态不会因用户暂停丢失。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 地址、数据和状态单事务记账；窗口缓存不依赖未确认DDR内容。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			// 取消全部协议资格。
			cnt_setup <= 0; cnt_row <= 0; cnt_col <= 0; cnt_quad <= 0; cnt_stage <= 0; // 新任务从左上首通道开始。
			reg_width <= 0; reg_height <= 0; reg_channels <= 0; reg_padded <= 0; // 旧层几何失效。
			reg_pixel_bytes <= 0; reg_row_bytes <= 0; reg_stride_term <= 0; // 行跨度重新建立。
			reg_window_address <= 0; reg_address <= 0; reg_input_limit <= 0; // 不保留旧DDR地址资格。
			reg_corner <= 0; reg_maximum <= 0; result_mask_o <= 0; // 清窗口和尾lane标签。
			reg_block <= 0; reg_block_row <= 0; reg_block_channels <= 0; reg_config_error <= 0; // 清块绑定。
			flag_configured <= 0; flag_block_valid <= 0; // RAM及旧层不能赋予新读资格。
			block_done_o <= 0; post_done_o <= 0; error_code_o <= 0; // 不产生虚假完成。
		end else begin
			block_done_o <= 0; post_done_o <= 0; // 完成通知只持续一个FCLK。
			if(state_current == ST_COMMAND && i_cmd_ready == 1'b1)begin
				// 已发布命令在CE暂停仍准确接受。
			end else if(o_status_ready == 1'b1 && i_status_valid == 1'b1)begin
				if(state_current != ST_STATUS || i_status != 8'h80)begin
					error_code_o <= 4'd4;       // 提前状态或非精确成功均终止。
				end else begin
					// 状态成功保存到CE恢复后处理。
				end
			end else if(state_current == ST_OUTPUT && i_result_ready == 1'b1)begin
				post_done_o <= 1;               // B5接受后才允许CAL推进quad。
				if(remaining_channels <= 4)begin
					cnt_quad <= 0; flag_block_valid <= 0; // 下一空间位置重新建立首块。
					if(cnt_col == reg_width - 12'd2)begin
						cnt_col <= 0; cnt_row <= cnt_row + 16'd2; // 真实输入按两行推进。
						reg_window_address <= reg_window_address + {1'b0, reg_row_bytes} + {reg_pixel_bytes, 1'b0}; // 最后一窗到下一行首窗的位移。
					end else begin
						cnt_col <= cnt_col + 12'd2; reg_window_address <= reg_window_address + {reg_pixel_bytes, 1'b0}; // 下一窗口横向跳两个像素。
					end
				end else begin
					cnt_quad <= cnt_quad + 10'd1; // 一个像素内四通道递增。
				end
			end else if(i_ce == 1'b1)begin
				case(state_current)

					// 层配置和块元数据仅在空闲接受。
					ST_IDLE:begin
						if(i_start == 1'b1)begin
							reg_width <= i_base_instruction[147:136]; reg_height <= i_extension[111:96]; // 锁存真实几何。
							reg_channels <= i_base_instruction[183:172] == 0 ? 13'd4096 : {1'b0, i_base_instruction[183:172]}; // 恢复4096哨兵编码。
							reg_padded <= i_extension[143:128]; reg_pixel_bytes <= {15'd0, i_extension[143:128], 1'b0}; // 物理像素使用完整补齐深度。
							reg_window_address <= {1'b0, i_base_instruction[31:0]}; // 第一窗口左上首通道。
							reg_input_limit <= {1'b0, i_base_instruction[31:0]} + {8'd0, i_base_instruction[87:64], 1'b0}; // 宽化输入区域末址。
							reg_config_error <= i_extension[171:168] != 2 || i_base_instruction[199:196] != 1 || i_base_instruction[203:200] != 2 || i_extension[166:160] != 0 || i_base_instruction[31:0] < 32'h05000000 || i_base_instruction[2:0] != 0 || i_base_instruction[87:64] == 0 || i_base_instruction[65:64] != 0 || i_extension[127:112] != (i_extension[111:96] >> 1) ? 4'd1 : 4'd0; // 未支持几何和数值变换在读前拒绝。
							cnt_row <= 0; cnt_col <= 0; cnt_quad <= 0; cnt_stage <= 0; // 每层重建真实HWC起点。
							flag_configured <= 0; flag_block_valid <= 0; // 先检查再准备读流。
						end else if(i_block_req == 1'b1 && o_block_ready == 1'b1)begin
							if(i_block_row != cnt_row || i_block != {5'd0, cnt_quad[9:7]} || i_block_channels != (reg_channels - {1'b0, cnt_quad[9:7], 9'd0} > 512 ? 13'd512 : reg_channels - {1'b0, cnt_quad[9:7], 9'd0}))begin
								error_code_o <= 4'd2; // 旧行或错误尾块长度不得放行。
							end else begin
								reg_block <= i_block; reg_block_row <= i_block_row; reg_block_channels <= i_block_channels; // 元数据绑定本窗口真实块。
								flag_block_valid <= 1; block_done_o <= 1; // 按需读流就绪，不伪造DDR装载成功。
							end
						end else if(i_post_valid == 1'b1 && o_post_ready == 1'b1)begin
							if(flag_token_bad == 1'b1)begin
								error_code_o <= 4'd2; // 拒绝乱序或错误mask。
							end else begin
								reg_address <= reg_window_address + {20'd0, cnt_quad, 3'd0} + (cnt_stage[0] ? {1'b0, reg_pixel_bytes} : 33'd0) + (cnt_stage[1] ? {1'b0, reg_row_bytes} : 33'd0); // 四角地址由窗口和通道真实坐标形成。
								result_mask_o <= i_post_mask; // 锁存当前quad参与资格。
							end
						end else begin
						end
					end

					// 全部静态几何合法后才形成行跨度。
					ST_CONFIG:begin
						if(reg_config_error != 0 || reg_width < 2 || reg_width[0] || reg_height < 2 || reg_height[0] || reg_padded != ((reg_channels + 13'd3) & 13'h1ffc) || reg_input_limit > 33'h011000000)begin
							error_code_o <= 4'd1; // 禁止越界、奇数几何和非规范补齐。
						end else begin
							cnt_setup <= 0; reg_row_bytes <= 0; reg_stride_term <= reg_pixel_bytes; // 十二拍串行常数乘法。
						end
					end

					// shortcut: 行跨度准备固定十二拍，性能需要时复用已验证的地址准备流水。
					ST_STRIDE:begin
						if(reg_width[cnt_setup] == 1'b1)begin
							reg_row_bytes <= reg_row_bytes + reg_stride_term; // 只在当前宽度位为一时累加。
						end
						reg_stride_term <= reg_stride_term << 1; // 下一宽度位对应两倍像素跨度。
						if(cnt_setup == 11)begin
							flag_configured <= 1; // 已寄存完整行跨度。
						end else begin
							cnt_setup <= cnt_setup + 4'd1; // 扫描下一宽度位。
						end
					end

					// 寄存地址先检查，再发布稳定命令。
					ST_ADDRESS:begin
						if(flag_address_bad == 1'b1)begin
							error_code_o <= 4'd5; // 错误地址从未交给DataMover。
						end else begin
							// 地址和BTT在反压时保持。
						end
					end

					// 单beat帧必须完整且带TLAST。
					ST_DATA:begin
						if(i_data_valid == 1'b1)begin
							if(i_data_keep != 8'hff || i_data_last != 1'b1)begin
								error_code_o <= 4'd3; // 数据格式错误不提交最大值。
							end else begin
								reg_corner <= i_data; // 先保存数据再等待成功响应。
							end
						end
					end

					// 第一个角点直接初始化，避免零错误压过全负窗口。
					ST_COMMIT:begin
						reg_maximum <= cnt_stage == 0 ? reg_corner : maximum_data; // 每lane有符号累计四角最大值。
						if(cnt_stage == 3)begin
							cnt_stage <= 0;     // 四个成功角点产生唯一结果。
						end else begin
							cnt_stage <= cnt_stage + 2'd1; // 继续下一真实角点。
						end
					end

					// 其余状态只由协议分支或次态机推进。
					default:begin
					end
				endcase
			end
		end
	end

	//----------------状态机区域----------------//
	// 状态寄存与数据更新共用原始FCLK，复位立即取消协议资格。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			state_current <= ST_IDLE;           // 无在途读流。
		end else begin
			state_current <= state_next;        // 下一协议状态不受错误CE阻断。
		end
	end

	// 已发布协议先记账，只有配置、坐标和算术提交等待CE。
	always@(*)begin
		state_next = state_current;             // 默认等待当前握手。
		if(flag_command_active && i_cmd_ready == 1'b1)begin
			state_next = ST_DATA;               // 命令接受后才接收输入beat。
		end else if(o_status_ready == 1'b1 && i_status_valid == 1'b1)begin
			state_next = flag_status_active && i_status == 8'h80 ? ST_COMMIT : ST_ERROR; // 提前或错误状态终止。
		end else if(flag_output_active && i_result_ready == 1'b1)begin
			state_next = ST_IDLE;               // 最终结果只接受一次。
		end else if(i_ce == 1'b1)begin
			case(state_current)

				// 空闲只接受一个来源的配置或读token。
				ST_IDLE:begin
					if(i_start == 1'b1)begin
						state_next = ST_CONFIG; // 新层先检查。
					end else if(i_block_req == 1'b1 && o_block_ready == 1'b1)begin
						if(i_block_row != cnt_row || i_block != {5'd0, cnt_quad[9:7]} || i_block_channels != (reg_channels - {1'b0, cnt_quad[9:7], 9'd0} > 512 ? 13'd512 : reg_channels - {1'b0, cnt_quad[9:7], 9'd0}))begin
							state_next = ST_ERROR; // 旧块元数据不能继续读取。
						end else begin
							state_next = ST_IDLE; // 元数据就绪后等待token。
						end
					end else if(i_post_valid == 1'b1 && o_post_ready == 1'b1)begin
						state_next = flag_token_bad ? ST_ERROR : ST_ADDRESS; // 错误坐标不发布命令。
					end else begin
						state_next = ST_IDLE;   // 等待真实请求。
					end
				end

				// 地址范围和几何完整保护。
				ST_CONFIG:begin
					state_next = reg_config_error != 0 || reg_width < 2 || reg_width[0] || reg_height < 2 || reg_height[0] || reg_padded != ((reg_channels + 13'd3) & 13'h1ffc) || reg_input_limit > 33'h011000000 ? ST_ERROR : ST_STRIDE; // 非法字段在读前停止。
				end

				// 完整十二位宽度决定真实行跨度。
				ST_STRIDE:begin
					state_next = cnt_setup == 11 ? ST_IDLE : ST_STRIDE; // 准备结束才可读取。
				end

				// 禁止非对齐或越过声明输入区的地址。
				ST_ADDRESS:begin
					state_next = flag_address_bad ? ST_ERROR : ST_COMMAND; // 检查通过后稳定发布。
				end

				// 数据帧只接受一个完整beat。
				ST_DATA:begin
					if(i_data_valid == 1'b1)begin
						state_next = i_data_keep == 8'hff && i_data_last == 1'b1 ? ST_STATUS : ST_ERROR; // 错帧不参与最大值。
					end else begin
						state_next = ST_DATA;   // 数据反压时保持事务。
					end
				end

				// 四角累计完成才生成结果。
				ST_COMMIT:begin
					state_next = cnt_stage == 3 ? ST_OUTPUT : ST_IDLE; // 保持CAL四角次序。
				end

				// 命令、状态及结果握手由上方优先级处理。
				default:begin
					state_next = state_current; // 无外部握手不前进。
				end
			endcase
		end else begin
			state_next = state_current;         // 软件暂停保持算法状态。
		end
	end

endmodule
