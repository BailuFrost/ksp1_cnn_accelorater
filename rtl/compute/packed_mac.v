`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/07 09:06:00
// Design Name:     packed_mac
// Module Name:     packed_mac
// Description:     description/packed_mac_Design.pdf
// Simulations:     testbench/vivado/2021.1/packed_mac
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/packed_mac_spec.md; docs/设计文档.md 4.11
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/07 09:06:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/07       V1.0        Codex             Migrate async reset and normalize.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月07日
// 设计名称:        packed_mac
// 模块名称:        packed_mac
// 模块说明:        Description/packed_mac_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/packed_mac
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/packed_mac_spec.md; docs/设计文档.md 4.11
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月07日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月07日   V1.0        Codex             迁移异步复位并规范化

module packed_mac
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 统一计算时钟。
	input i_rstn,                               // 低有效异步复位，上游统一同步释放，优先于暂停。

	//-----------------用户接口-----------------//
	input i_ce,                                 // 全局流水推进；为零时所有寄存器保持。
	input i_in_valid,                           // 当前打包通道对有效。
	input [31:0]i_feature_data,                 // {高通道, 低通道}，各为有符号 INT16。
	input [31:0]i_weight_data,                  // 与特征同序的两个权重。
	output o_out_valid,                         // 与双乘积和对齐的有效标志。
	output signed [32:0]o_out_data              // 不截位的有符号双乘积和。
);

	//----------------寄存器信号----------------//
	(* use_dsp = "yes" *) reg signed [31:0]reg_product_low = 32'd0; // 低通道完整乘积。
	(* use_dsp = "yes" *) reg signed [31:0]reg_product_high = 32'd0; // 高通道完整乘积。

	//-----------------标志信号-----------------//
	reg flag_product_valid = 1'd0;              // 首级有效标志，暂停时保持。

	//-----------------其他信号-----------------//
	// 独立声明符号，避免打包总线切片被作为无符号数乘法。
	wire signed [15:0]feature_low;              // 较低输入通道的有符号特征。
	wire signed [15:0]feature_high;             // 较高输入通道的有符号特征。
	wire signed [15:0]weight_low;               // 较低输入通道的有符号权重。
	wire signed [15:0]weight_high;              // 较高输入通道的有符号权重。

	//-----------------输出信号-----------------//
	//用户接口
	reg out_valid_o = 1'd0;                     // 末级有效标志，与和同步推进。
	(* use_dsp = "no" *) reg signed [32:0]out_data_o = 33'd0; // 使用逻辑加法，避免第三个DSP。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign feature_low = i_feature_data[15:0];  // 取低通道并保留补码符号。
	assign feature_high = i_feature_data[31:16]; // 解释高通道INT16输入。
	assign weight_low = i_weight_data[15:0];    // 选择低位配对权重。
	assign weight_high = i_weight_data[31:16];  // 高位权重与高通道特征对齐。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_out_valid = out_valid_o;           // 输出寄存有效标志直接连接端口。
	assign o_out_data = out_data_o;             // 转发完整33位乘积和。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 输出标签：有效标志只在全局推进时更新。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			out_valid_o <= 1'b0;                // 立即撤销在途有效结果。
		end else if(i_ce == 1'b1)begin
			out_valid_o <= flag_product_valid;  // 第二级有效标志跟随已锁存乘积。
		end
	end

	// 求和级：二级数据保持完整精度，暂停时保留结果。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			out_data_o <= 33'sd0;               // 异步清零旧的输出和。
		end else if(i_ce == 1'b1)begin
			out_data_o <= reg_product_low + reg_product_high; // 33位赋值上下文扩展两项signed32后相加。
		end
	end

	//-------------主要任务处理区域-------------//
	// 高通道乘法：异步清除高位乘积寄存器。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product_high <= 32'sd0;         // 清除高通道旧乘积。
		end else if(i_ce == 1'b1)begin
			reg_product_high <= feature_high * weight_high; // 同拍锁存高通道完整32位乘积。
		end
	end

	// 低通道乘法：独立DSP路径与高通道同拍推进。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product_low <= 32'sd0;          // 复位低通道乘积寄存器。
		end else if(i_ce == 1'b1)begin
			reg_product_low <= feature_low * weight_low; // 使能沿计算低通道有符号乘法。
		end
	end

	// 首级标签：记录接受通道对的有效性。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_product_valid <= 1'b0;         // 丢弃首级在途标签。
		end else if(i_ce == 1'b1)begin
			flag_product_valid <= i_in_valid;   // 保存本拍输入气泡或有效状态。
		end
	end

endmodule
