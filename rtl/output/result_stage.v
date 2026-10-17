`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     result_stage
// Module Name:     result_stage
// Description:     description/result_stage_Design.pdf
// Simulations:     testbench/vivado/2021.1/result_stage
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/result_stage_spec.md; docs/设计文档.md 4.11
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/08 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Codex             Standardize existing Stage B RTL style.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Codex
//
// 创建日期:        2026年10月08日
// 设计名称:        result_stage
// 模块名称:        result_stage
// 模块说明:        Description/result_stage_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/result_stage
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/result_stage_spec.md; docs/设计文档.md 4.11
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             统一既有阶段B代码风格

module result_stage
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 四lane量化准备级时钟。
	input i_rstn,                               // 异步清除量化在途项，上游统一同步释放。

	//-----------------用户接口-----------------//
	input i_in_valid,                           // 输入完整和及偏置有效。
	output o_in_ready,                          // 准备寄存为空或当前输出被消费时允许接收。
	input [191:0]i_sum_data,                    // 低到高四项signed48跨tile完整点积。
	input [191:0]i_bias_data,                   // 与点积lane同序的四项signed48偏置。
	input [3:0]i_lane_mask,                     // 四lane参与位，无效项最终输出零。
	input [5:0]i_right_shift,                   // 零至63位加半舍入右移。
	input i_relu,                               // 置位时将量化后负数截为零。
	output [63:0]o_result_data,                 // 低到高四个饱和INT16结果。
	output o_out_valid,                         // 与结果、mask同拍的弹性流水资格。
	input i_out_ready,                          // 下游结果消费许可，未许可时保持全部寄存。
	output [3:0]o_out_mask                      // 与输出四项INT16严格对齐的lane mask。
);

	//----------------寄存器信号----------------//
	reg [5:0]reg_shift;                         // 与舍入和共同保存本项右移位数。
	reg signed [49:0]reg_rounded_first;         // 最低lane偏置和舍入后的50位准备寄存。
	reg signed [49:0]reg_rounded_second;        // 次低lane偏置和舍入后的50位准备寄存。
	reg signed [49:0]reg_rounded_third;         // 次高lane偏置和舍入后的50位准备寄存。
	reg signed [49:0]reg_rounded_fourth;        // 最高lane偏置和舍入后的50位准备寄存。

	//-----------------标志信号-----------------//
	reg flag_relu;                              // 当前在途四lane共同使用的ReLU配置。

	//-----------------其他信号-----------------//
	//四lane独立量化操作数
	wire signed [47:0]sum_value_first;          // 最低lane完整点积的有符号解释。
	wire signed [47:0]bias_value_first;         // 最低lane参与时取偏置，否则取零。
	wire signed [49:0]half_first;               // 最低lane量化位数对应的半单位舍入项。
	wire signed [49:0]rounded_first;            // 最低lane三项carry-save加法的完整50位和。
	wire signed [49:0]shifted_first;            // 最低lane准备寄存算术右移后的数值。
	wire [49:0]sum_wide_first;                  // 最低lane点积符号扩展的50位操作数。
	wire [49:0]bias_wide_first;                 // 最低lane偏置符号扩展供逐位压缩使用。
	wire [49:0]carry_save_sum_first;            // 最低lane三操作数逐位异或产生无进位和。
	wire [49:0]carry_save_carry_first;          // 最低lane多数位左移产生进位向量。
	wire signed [15:0]saturated_first;          // 最低lane限制到INT16上下界的补码值。
	wire signed [47:0]sum_value_second;         // 次低lane完整点积的有符号解释。
	wire signed [47:0]bias_value_second;        // 次低lane参与时取偏置，否则取零。
	wire signed [49:0]half_second;              // 次低lane量化位数对应的半单位舍入项。
	wire signed [49:0]rounded_second;           // 次低lane三项carry-save加法的完整50位和。
	wire signed [49:0]shifted_second;           // 次低lane准备寄存算术右移后的数值。
	wire [49:0]sum_wide_second;                 // 次低lane点积符号扩展的50位操作数。
	wire [49:0]bias_wide_second;                // 次低lane偏置符号扩展供逐位压缩使用。
	wire [49:0]carry_save_sum_second;           // 次低lane三操作数逐位异或产生无进位和。
	wire [49:0]carry_save_carry_second;         // 次低lane多数位左移产生进位向量。
	wire signed [15:0]saturated_second;         // 次低lane限制到INT16上下界的补码值。
	wire signed [47:0]sum_value_third;          // 次高lane完整点积的有符号解释。
	wire signed [47:0]bias_value_third;         // 次高lane参与时取偏置，否则取零。
	wire signed [49:0]half_third;               // 次高lane量化位数对应的半单位舍入项。
	wire signed [49:0]rounded_third;            // 次高lane三项carry-save加法的完整50位和。
	wire signed [49:0]shifted_third;            // 次高lane准备寄存算术右移后的数值。
	wire [49:0]sum_wide_third;                  // 次高lane点积符号扩展的50位操作数。
	wire [49:0]bias_wide_third;                 // 次高lane偏置符号扩展供逐位压缩使用。
	wire [49:0]carry_save_sum_third;            // 次高lane三操作数逐位异或产生无进位和。
	wire [49:0]carry_save_carry_third;          // 次高lane多数位左移产生进位向量。
	wire signed [15:0]saturated_third;          // 次高lane限制到INT16上下界的补码值。
	wire signed [47:0]sum_value_fourth;         // 最高lane完整点积的有符号解释。
	wire signed [47:0]bias_value_fourth;        // 最高lane参与时取偏置，否则取零。
	wire signed [49:0]half_fourth;              // 最高lane量化位数对应的半单位舍入项。
	wire signed [49:0]rounded_fourth;           // 最高lane三项carry-save加法的完整50位和。
	wire signed [49:0]shifted_fourth;           // 最高lane准备寄存算术右移后的数值。
	wire [49:0]sum_wide_fourth;                 // 最高lane点积符号扩展的50位操作数。
	wire [49:0]bias_wide_fourth;                // 最高lane偏置符号扩展供逐位压缩使用。
	wire [49:0]carry_save_sum_fourth;           // 最高lane三操作数逐位异或产生无进位和。
	wire [49:0]carry_save_carry_fourth;         // 最高lane多数位左移产生进位向量。
	wire signed [15:0]saturated_fourth;         // 最高lane限制到INT16上下界的补码值。

	//-----------------输出信号-----------------//
	//用户接口
	wire in_ready_o;                            // 输出阻塞时禁止覆盖准备寄存。
	wire [63:0]result_data_o;                   // 四项移位、饱和及ReLU后的结果打包。
	reg out_valid_o;                            // 量化准备寄存内的有效项资格。
	reg [3:0]out_mask_o;                        // lane参与位与准备和一同锁存。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign sum_value_first = i_sum_data[47:0];  // 最低lane从输入低到高提取signed48点积。
	assign bias_value_first = i_lane_mask[0] ? i_bias_data[47:0] : 48'd0; // 最低lane未参与时禁止偏置进入和。
	assign sum_wide_first = {{2{sum_value_first[47]}},sum_value_first}; // 最低lane以符号位补齐两个高位。
	assign bias_wide_first = {{2{bias_value_first[47]}},bias_value_first}; // 最低lane偏置保留负数补码符号。
	assign half_first = (i_right_shift<50) ? $signed((50'd1 << i_right_shift) >> 1) : 50'sd0; // 第一项采用当前右移配置产生半单位，加半定义与A2一致。
	assign carry_save_sum_first = sum_wide_first ^ bias_wide_first ^ half_first; // 最低点积、偏置和舍入量按位压缩成无进位和。
	assign carry_save_carry_first = ((sum_wide_first & bias_wide_first) | (sum_wide_first & half_first) | (bias_wide_first & half_first)) << 1; // 最低lane多数位的进位向量对齐下一位。
	assign rounded_first = $signed(carry_save_sum_first)+$signed(carry_save_carry_first); // 最低lane只做一次完整50位进位传播。
	assign shifted_first = (reg_shift>=50) ? 50'sd0 : (reg_rounded_first >>> reg_shift); // 最低准备和按锁存位数做符号移位，大移位特判为零。
	assign saturated_first = (shifted_first>50'sd32767) ? 16'sd32767 : (shifted_first< -50'sd32768) ? -16'sd32768 : shifted_first[15:0]; // 最低lane在移位后饱和，避免提前截断。
	assign sum_value_second = i_sum_data[95:48]; // 次低lane从输入低到高提取signed48点积。
	assign bias_value_second = i_lane_mask[1] ? i_bias_data[95:48] : 48'd0; // 次低lane未参与时禁止偏置进入和。
	assign sum_wide_second = {{2{sum_value_second[47]}},sum_value_second}; // 次低lane以符号位补齐两个高位。
	assign bias_wide_second = {{2{bias_value_second[47]}},bias_value_second}; // 次低lane偏置保留负数补码符号。
	assign half_second = (i_right_shift<50) ? $signed((50'd1 << i_right_shift) >> 1) : 50'sd0; // 第二项位数为零时舍入量为零，其余合法位数取二的幂次半值。
	assign carry_save_sum_second = sum_wide_second ^ bias_wide_second ^ half_second; // 第二路先异或三个50位操作数，保留与进位向量分离的部分。
	assign carry_save_carry_second = ((sum_wide_second & bias_wide_second) | (sum_wide_second & half_second) | (bias_wide_second & half_second)) << 1; // 次低lane多数位的进位向量对齐下一位。
	assign rounded_second = $signed(carry_save_sum_second)+$signed(carry_save_carry_second); // 次低lane只做一次完整50位进位传播。
	assign shifted_second = (reg_shift>=50) ? 50'sd0 : (reg_rounded_second >>> reg_shift); // 次低lane使用本项准备寄存，负数按算术右移而非逻辑移位处理。
	assign saturated_second = (shifted_second>50'sd32767) ? 16'sd32767 : (shifted_second< -50'sd32768) ? -16'sd32768 : shifted_second[15:0]; // 次低lane在移位后饱和，避免提前截断。
	assign sum_value_third = i_sum_data[143:96]; // 次高lane从输入低到高提取signed48点积。
	assign bias_value_third = i_lane_mask[2] ? i_bias_data[143:96] : 48'd0; // 次高lane未参与时禁止偏置进入和。
	assign sum_wide_third = {{2{sum_value_third[47]}},sum_value_third}; // 次高lane以符号位补齐两个高位。
	assign bias_wide_third = {{2{bias_value_third[47]}},bias_value_third}; // 次高lane偏置保留负数补码符号。
	assign half_third = (i_right_shift<50) ? $signed((50'd1 << i_right_shift) >> 1) : 50'sd0; // 第三项大位移不再加半，输入幅度保证shift至少50时结果为零。
	assign carry_save_sum_third = sum_wide_third ^ bias_wide_third ^ half_third; // 第三项使用逐位三输入压缩，准备级前只保留一次进位传播。
	assign carry_save_carry_third = ((sum_wide_third & bias_wide_third) | (sum_wide_third & half_third) | (bias_wide_third & half_third)) << 1; // 次高lane多数位的进位向量对齐下一位。
	assign rounded_third = $signed(carry_save_sum_third)+$signed(carry_save_carry_third); // 次高lane只做一次完整50位进位传播。
	assign shifted_third = (reg_shift>=50) ? 50'sd0 : (reg_rounded_third >>> reg_shift); // 第三lane与配置一起等待消费，位数大于等于50时输出零值。
	assign saturated_third = (shifted_third>50'sd32767) ? 16'sd32767 : (shifted_third< -50'sd32768) ? -16'sd32768 : shifted_third[15:0]; // 次高lane在移位后饱和，避免提前截断。
	assign sum_value_fourth = i_sum_data[191:144]; // 最高lane从输入低到高提取signed48点积。
	assign bias_value_fourth = i_lane_mask[3] ? i_bias_data[191:144] : 48'd0; // 最高lane未参与时禁止偏置进入和。
	assign sum_wide_fourth = {{2{sum_value_fourth[47]}},sum_value_fourth}; // 最高lane以符号位补齐两个高位。
	assign bias_wide_fourth = {{2{bias_value_fourth[47]}},bias_value_fourth}; // 最高lane偏置保留负数补码符号。
	assign half_fourth = (i_right_shift<50) ? $signed((50'd1 << i_right_shift) >> 1) : 50'sd0; // 第四项舍入增量先计算为50位，确保符号和后续完整加法一致。
	assign carry_save_sum_fourth = sum_wide_fourth ^ bias_wide_fourth ^ half_fourth; // 高位lane对符号扩展后的三项求异或，不在48位处截断。
	assign carry_save_carry_fourth = ((sum_wide_fourth & bias_wide_fourth) | (sum_wide_fourth & half_fourth) | (bias_wide_fourth & half_fourth)) << 1; // 最高lane多数位的进位向量对齐下一位。
	assign rounded_fourth = $signed(carry_save_sum_fourth)+$signed(carry_save_carry_fourth); // 最高lane只做一次完整50位进位传播。
	assign shifted_fourth = (reg_shift>=50) ? 50'sd0 : (reg_rounded_fourth >>> reg_shift); // 最高项取已捕获的50位补码和，右移配置与结果反压同步冻结。
	assign saturated_fourth = (shifted_fourth>50'sd32767) ? 16'sd32767 : (shifted_fourth< -50'sd32768) ? -16'sd32768 : shifted_fourth[15:0]; // 最高lane在移位后饱和，避免提前截断。

	assign in_ready_o = i_rstn && (!out_valid_o || i_out_ready); // 复位禁止握手；空槽或消费沿允许替换。
	assign result_data_o[15:0] = (!out_mask_o[0] || (flag_relu && saturated_first[15])) ? 16'd0 : saturated_first; // 最低lane在mask失效或激活抑制负值时清零，保留其他饱和值。
	assign result_data_o[31:16] = (!out_mask_o[1] || (flag_relu && saturated_second[15])) ? 16'd0 : saturated_second; // 次低16位只转发有效正值或关闭ReLU的补码，尾lane则屏蔽。
	assign result_data_o[47:32] = (!out_mask_o[2] || (flag_relu && saturated_third[15])) ? 16'd0 : saturated_third; // 第三INT16的符号由饱和值确定；参与位为零时无条件输出零。
	assign result_data_o[63:48] = (!out_mask_o[3] || (flag_relu && saturated_fourth[15])) ? 16'd0 : saturated_fourth; // 最高lane按本项mask与锁存激活配置选择零或INT16饱和结果。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_in_ready = in_ready_o;             // 入口以有效且就绪接受一项四lane数据。
	assign o_result_data = result_data_o;       // 输出保持低lane在低位的INT16顺序。
	assign o_out_valid = out_valid_o;           // 准备项资格直接对应组合后处理结果。
	assign o_out_mask = out_mask_o;             // 下游用此mask屏蔽尾组无效字节。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 准备级仅在可推进时接收；反压期间数值和所有配置共同保持。
	always@(posedge i_clk or negedge i_rstn)begin
		if(!i_rstn)begin
			out_valid_o <= 0;                   // 异步撤销尚未消费的量化项。
			reg_shift <= 0;                     // 复位量化右移配置。
			out_mask_o <= 0;                    // 复位后不存在有效输出lane。
			flag_relu <= 0;                     // 清除在途项的激活控制。
			reg_rounded_first <= 0;             // 最低lane准备和在非沿复位时立即归零。
			reg_rounded_second <= 0;            // 次低lane准备和在非沿复位时立即归零。
			reg_rounded_third <= 0;             // 次高lane准备和在非沿复位时立即归零。
			reg_rounded_fourth <= 0;            // 最高lane准备和在非沿复位时立即归零。
		end else if(o_in_ready)begin
			out_valid_o <= i_in_valid;          // 空闲气泡撤销资格，有效输入建立新项。
			if(i_in_valid)begin
				reg_shift <= i_right_shift;     // 接受沿锁存右移位数，隔离后续配置变化。
				out_mask_o <= i_lane_mask;      // 参与位跨过与四项准备和相同的寄存边界。
				flag_relu <= i_relu;            // 激活开关随已接受项冻结。
				reg_rounded_first <= rounded_first; // 最低lane完整50位舍入和进入准备寄存。
				reg_rounded_second <= rounded_second; // 次低lane完整50位舍入和进入准备寄存。
				reg_rounded_third <= rounded_third; // 次高lane完整50位舍入和进入准备寄存。
				reg_rounded_fourth <= rounded_fourth; // 最高lane完整50位舍入和进入准备寄存。
			end
		end
	end

endmodule
