`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     result_fifo_3x3
// Module Name:     result_fifo_3x3
// Description:     description/result_fifo_3x3_Design.pdf
// Simulations:     testbench/vivado/2021.1/result_fifo_3x3
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/result_fifo_3x3_spec.md; docs/设计文档.md 4.9
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/08 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Codex             Create fixed result queue and output integration.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Codex
//
// 创建日期:        2026年10月08日
// 设计名称:        result_fifo_3x3
// 模块名称:        result_fifo_3x3
// 模块说明:        Description/result_fifo_3x3_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/result_fifo_3x3
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/result_fifo_3x3_spec.md; docs/设计文档.md 4.9
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             创建结果队列及序列化连接

module result_fifo_3x3
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 单时钟FCLK_CLK0上升沿。
	input i_rstn,                               // 低有效异步清控制，上游同域同步释放，RAM不复位。

	//-----------------用户接口-----------------//
	input i_in_valid,                           // 四lane结果及mask写请求。
	output o_in_ready,                          // 非满且复位释放允许接受。
	input [63:0]i_in_data,                      // 低lane在低位的四项INT16。
	input [3:0]i_in_mask,                       // 随输入数据存储的四lane参与位。
	output o_out_valid,                         // 队列非空时队首有效。
	input i_out_ready,                          // 消费者允许当前队首出队。
	output [63:0]o_out_data,                    // 异步读当前队首的64位结果。
	output [3:0]o_out_mask,                     // 队首数据对应的四lane标签。
	output o_full,                              // 实际占用等于512，满时保守拒绝写。
	output o_empty,                             // 实际占用为零，不提供空旁路。
	output [9:0]o_count                         // 十位占用计数，范围零至512。
);

	//-----------------计数信号-----------------//
	//私有队列占用汇接
	wire [9:0]cnt_items;                        // 私有FIFO返回：十位占用计数，范围零至512。

	//-----------------输出信号-----------------//
	//用户接口
	wire in_ready_o;                            // 内部写入许可由私有存储容量决定。
	wire out_valid_o;                           // 内部出队资格只在有效占用时取得。
	wire [63:0]out_data_o;                      // 私有FIFO返回：异步读当前队首的64位结果。
	wire [3:0]out_mask_o;                       // 私有FIFO返回：队首数据对应的四lane标签。
	wire full_o;                                // 子实例反馈已耗尽512项容量。
	wire empty_o;                               // 子实例反馈当前没有未消费结果。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_in_ready = in_ready_o;             // 将私有容量许可返回当前写入端。
	assign o_out_valid = out_valid_o;           // 对外提供已写队首的可消费资格。
	assign o_out_data = out_data_o;             // 将内部存储读头载荷转交消费者。
	assign o_out_mask = out_mask_o;             // 把当前项的参与位随载荷交付。
	assign o_full = full_o;                     // 上游利用本路满标志停止继续提交。
	assign o_empty = empty_o;                   // 外部排空判断使用本路零占用标志。
	assign o_count = cnt_items;                 // 公开子实例的精确队列项数。

	//--------------模块实例化区域--------------//
	// 私有队列只保存本路结果，不与另一封装共享指针或容量。
	result_fifo result_fifo_Inst(               // 固定512项四lane数据及mask存储。
		.i_clk(i_clk),                          // 子队列读写指针与数据写口使用统一计算时钟。
		.i_rstn(i_rstn),                        // 立即取消私有队列旧占用，保留数据数组。
		.i_in_valid(i_in_valid),                // 只有本类量化项可提出私有队列写请求。
		.o_in_ready(in_ready_o),                // 本队列的剩余容量反馈给在途生产者。
		.i_in_data(i_in_data),                  // 本次四lane数值按原位序入私有存储。
		.i_in_mask(i_in_mask),                  // 当前四lane参与位与数据写入同一项。
		.o_out_valid(out_valid_o),              // 已写队首是否存在由队列控制返回。
		.i_out_ready(i_out_ready),              // 写回端独立决定本路队首消费时机。
		.o_out_data(out_data_o),                // 私有读头的64位数值送到所属写回流。
		.o_out_mask(out_mask_o),                // 读头附带参与标签同步送写回端。
		.o_full(full_o),                        // 容量告警来自本路实际512项占用。
		.o_empty(empty_o),                      // 没有历史待写回项时通知外部屏障。
		.o_count(cnt_items)                     // 反馈实际积压项数供验收和控制检查。
	);

endmodule
