`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     fout_selector
// Module Name:     fout_selector
// Description:     description/fout_selector_Design.pdf
// Simulations:     testbench/vivado/2021.1/fout_selector
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/fout_selector_spec.md; docs/架构文档.md 6
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/08 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Codex             Create four-mode feature selector.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Codex
//
// 创建日期:        2026年10月08日
// 设计名称:        fout_selector
// 模块名称:        fout_selector
// 模块说明:        Description/fout_selector_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/fout_selector
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/fout_selector_spec.md; docs/架构文档.md 6
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             创建四模式特征选择器

module fout_selector
(
	//-----------------用户接口-----------------//
	input i_in_valid,                           // 已对齐的真实读响应或虚拟Padding事件。
	input [95:0]i_in_data,                      // 低到高为三个物理bank的双INT16通道对。
	input [1:0]i_mode,                          // 零三行、一两行、二单行广播、三矩阵广播。
	input [1:0]i_row_select,                    // 第一逻辑行对应的物理bank，编码三非法。
	input [2:0]i_row_mask,                      // 换位后三个逻辑行的空间有效位。
	input i_column_valid,                       // 水平列在图像内，否则输出整数零。
	input [1:0]i_pair_mask,                     // 低到高双通道有效位，奇数尾通道为零一。
	output o_out_valid,                         // 输入事件有效且行角色合法，Padding仍有效。
	output [95:0]o_out_data                     // 按CU上中下三路排列的选定通道对。
);

	//----------------寄存器信号----------------//
	reg [95:0]reg_logical_rows;                 // 组合换位后的三逻辑行，不产生时钟寄存器。

	//-----------------其他信号-----------------//
	//空间与通道屏蔽
	wire [31:0]pair_first;                      // 第一逻辑行屏蔽后的双通道，用于广播源。
	wire [31:0]pair_second;                     // 第二逻辑行屏蔽后的双通道。
	wire [31:0]pair_third;                      // 第三逻辑行屏蔽后的双通道。

	//-----------------输出信号-----------------//
	//用户接口
	wire out_valid_o;                           // 非法角色不能产生消费事件。
	wire [95:0]out_data_o;                      // 模式选择不增加使能拍延迟。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign pair_first[15:0] = i_column_valid && i_row_mask[0] && i_pair_mask[0] ? reg_logical_rows[15:0] : 16'd0; // 首行低通道越界或无效时隔离RAM未知值。
	assign pair_first[31:16] = i_column_valid && i_row_mask[0] && i_pair_mask[1] ? reg_logical_rows[31:16] : 16'd0; // 首行高通道按独立通道有效位补零。
	assign pair_second[15:0] = i_column_valid && i_row_mask[1] && i_pair_mask[0] ? reg_logical_rows[47:32] : 16'd0; // 第二逻辑行使用换位后的空间mask。
	assign pair_second[31:16] = i_column_valid && i_row_mask[1] && i_pair_mask[1] ? reg_logical_rows[63:48] : 16'd0; // 中行第二通道保留原INT16补码。
	assign pair_third[15:0] = i_column_valid && i_row_mask[2] && i_pair_mask[0] ? reg_logical_rows[79:64] : 16'd0; // 末行低通道越界时输出整数零。
	assign pair_third[31:16] = i_column_valid && i_row_mask[2] && i_pair_mask[1] ? reg_logical_rows[95:80] : 16'd0; // 末行高通道与其他行同规则屏蔽。
	assign out_valid_o = i_in_valid && i_row_select != 2'd3; // Padding保留事件，非法bank编码撤销有效资格。
	assign out_data_o = i_mode[1] ? {3{pair_first}} : {i_mode[0] ? 32'd0 : pair_third, pair_second, pair_first}; // 单行及矩阵复制首行，两行模式关闭第三路。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_out_valid = out_valid_o;           // CAL与CU以统一ce限定实际消费。
	assign o_out_data = out_data_o;             // 低32位对应CU首行，上位依次中行和末行。

	//-------------主要任务处理区域-------------//
	// 三物理行循环换位仅解释已对齐标签，地址和行末推进由CAL负责。
	always@(*)begin
		case(i_row_select)
			// 物理bank零作为第一逻辑行。
			2'd0:begin
				reg_logical_rows = i_in_data;   // 逻辑行顺序为物理零、一、二。
			end

			// 物理bank一作为第一逻辑行。
			2'd1:begin
				reg_logical_rows = {i_in_data[31:0], i_in_data[95:32]}; // 逻辑行顺序为物理一、二、零。
			end

			// 物理bank二作为第一逻辑行。
			2'd2:begin
				reg_logical_rows = {i_in_data[63:0], i_in_data[95:64]}; // 逻辑行顺序为物理二、零、一。
			end

			// 非法角色全零，不让未知RAM内容进入计算。
			default:begin
				reg_logical_rows = 96'd0;       // 同时由有效资格阻止非法结果被消费。
			end
		endcase
	end

endmodule
