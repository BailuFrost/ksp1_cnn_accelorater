`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     result_output
// Module Name:     result_output
// Description:     description/result_output_Design.pdf
// Simulations:     testbench/vivado/2021.1/result_output
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/result_output_spec.md; docs/设计文档.md 4.9
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
// 设计名称:        result_output
// 模块名称:        result_output
// 模块说明:        Description/result_output_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/result_output
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/result_output_spec.md; docs/设计文档.md 4.9
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             创建结果队列及序列化连接

module result_output
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 单时钟FCLK_CLK0上升沿。
	input i_rstn,                               // 低有效异步清控制，上游同域同步释放，RAM不复位。

	//-----------------用户接口-----------------//
	input i_bundle_valid,                       // 当前完整点积bundle有效。
	output o_bundle_ready,                      // packer空闲且所选队列未满才接受。
	input [3455:0]i_bundle_data,                // CU-major低到高72个signed48点积。
	input [3455:0]i_bias_data,                  // 当前bundle每lane对应的48位偏置。
	input [71:0]i_lane_mask,                    // 低位连续非空前缀，空间模式至多12lane。
	input [1:0]i_mode,                          // 00/01为空间，10/11为旁路。
	input [7:0]i_spatial_index,                 // 跨tile空间槽编号，固定容量小于196。
	input i_first_tile,                         // 首输入tile覆盖旧部分和。
	input i_last_tile,                          // 末输入tile才量化并进入结果队列。
	input [5:0]i_right_shift,                   // 量化加半舍入算术右移配置。
	input i_relu,                               // 输出INT16可选负值抑制。
	output o_busy,                              // packer当前bundle或量化项未排空，不含FIFO占用。
	output o_fifo_full,                         // busy时按锁存路由，否则按输入模式选择满状态。
	output o_spatial_fifo_valid,                // 空间私有队列队首有效。
	input i_spatial_fifo_ready,                 // 空间私有队列消费者允许队首出队。
	output [63:0]o_spatial_fifo_data,           // 空间私有队列64位四lane结果。
	output [3:0]o_spatial_fifo_mask,            // 空间私有队列四位参与标签。
	output o_spatial_fifo_full,                 // 空间私有队列占用512。
	output o_spatial_fifo_empty,                // 空间排空标志，只有没有待消费结果时置位。
	output [9:0]o_spatial_fifo_count,           // 空间私有队列零至512的占用。
	output o_bypass_fifo_valid,                 // 旁路私有队列队首有效。
	input i_bypass_fifo_ready,                  // 旁路私有队列消费者允许队首出队。
	output [63:0]o_bypass_fifo_data,            // 旁路私有队列64位四lane结果。
	output [3:0]o_bypass_fifo_mask,             // 旁路私有队列四位参与标签。
	output o_bypass_fifo_full,                  // 旁路私有队列占用512。
	output o_bypass_fifo_empty,                 // 旁路排空标志，只有没有待消费结果时置位。
	output [9:0]o_bypass_fifo_count             // 旁路私有队列零至512的占用。
);

	//--------------模块实例化信号--------------//
	//实际B5序列化器连接
	wire [63:0]quantized_data;                  // B5完成量化的四lane结果。

	//-----------------计数信号-----------------//
	//私有队列占用汇接
	wire [9:0]cnt_spatial_occupancy;            // 子模块汇接：空间私有队列零至512的占用。
	wire [9:0]cnt_bypass_occupancy;             // 子模块汇接：旁路私有队列零至512的占用。

	//-----------------标志信号-----------------//
	wire flag_selected_bypass;                  // 当前容量查询使用的简单一位类别索引。
	wire [3:0]flag_quantized_mask;              // B5保持在途项对应的参与标签。
	wire flag_packer_valid;                     // 实际量化项已准备好入队。
	wire flag_packer_ready;                     // 已锁存路由的队列有可写空间。
	wire flag_packer_bypass;                    // 接受bundle时锁存的目标类别。
	wire flag_bundle_ready;                     // B5当前无bundle或量化项在途。
	wire flag_bundle_valid;                     // 所选队列未满时将入口请求送B5。
	wire flag_spatial_ready;                    // 空间私有队列写入许可。
	wire flag_bypass_ready;                     // 旁路私有队列写入许可。
	wire flag_spatial_valid;                    // 空间类别的在途项有效。
	wire flag_bypass_valid;                     // 旁路类别的在途项有效。

	//-----------------其他信号-----------------//
	//两路容量状态
	wire [1:0]queue_capacity;                   // 低位为空间满，高位为旁路满，供当前路由索引。

	//-----------------输出信号-----------------//
	//用户接口
	wire bundle_ready_o;                        // 入口握手还需B5空闲以及输入类别队列留有空槽。
	wire busy_o;                                // 直接汇接B5的bundle和量化在途状态。
	wire fifo_full_o;                           // 以当前任务或pending模式选择容量告警。
	wire spatial_fifo_valid_o;                  // 空间队首存在可消费数据的汇接资格。
	wire [63:0]spatial_fifo_data_o;             // 子模块汇接：空间私有队列64位四lane结果。
	wire [3:0]spatial_fifo_mask_o;              // 子模块汇接：空间私有队列四位参与标签。
	wire spatial_fifo_full_o;                   // 空间容量不足时选路反压所需标志。
	wire spatial_fifo_empty_o;                  // 空间层间屏障所需的排空状态。
	wire bypass_fifo_valid_o;                   // 旁路队首存在可消费数据的汇接资格。
	wire [63:0]bypass_fifo_data_o;              // 子模块汇接：旁路私有队列64位四lane结果。
	wire [3:0]bypass_fifo_mask_o;               // 子模块汇接：旁路私有队列四位参与标签。
	wire bypass_fifo_full_o;                    // 旁路容量不足时选路反压所需标志。
	wire bypass_fifo_empty_o;                   // 旁路层间屏障所需的排空状态。

	//---------------其他信号连线---------------//
	//入口许可与在途分流
	assign queue_capacity = {bypass_fifo_full_o,spatial_fifo_full_o}; // 两个独立存储体的容量标志组成路由查表。
	assign flag_selected_bypass = busy_o ? flag_packer_bypass : i_mode[1]; // 在途只选接受沿路由，空闲才读取输入类别。
	assign bundle_ready_o = flag_bundle_ready && !fifo_full_o; // 空闲及当前输入路队列未满才接受。
	assign flag_bundle_valid = i_bundle_valid && !fifo_full_o; // 满时不能让B5误接受未握手的bundle。
	assign fifo_full_o = queue_capacity[flag_selected_bypass]; // 只对当前类别报告满状态，不合并另一队列占用。
	assign flag_packer_ready = flag_packer_bypass ? flag_bypass_ready : flag_spatial_ready; // 两私有容量分别向当前量化项反压。
	assign flag_spatial_valid = flag_packer_valid && !flag_packer_bypass; // 空间项只向空间队列写一次。
	assign flag_bypass_valid = flag_packer_valid && flag_packer_bypass; // 旁路项保持独占的输入握手。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_bundle_ready = bundle_ready_o;     // 当前入口只有通过完整握手才提交到B5。
	assign o_busy = busy_o;                     // 外部用此状态避免在途量化时切换任务。
	assign o_fifo_full = fifo_full_o;           // 向CAL提供当前所选结果路的容量状态。
	assign o_spatial_fifo_valid = spatial_fifo_valid_o; // 空间把本路已有队首资格交给写回端。
	assign o_spatial_fifo_data = spatial_fifo_data_o; // 空间从所属存储体交付当前四项INT16。
	assign o_spatial_fifo_mask = spatial_fifo_mask_o; // 空间把尾字参与信息交给本路消费者。
	assign o_spatial_fifo_full = spatial_fifo_full_o; // 空间为CAL公开本路容量耗尽情况。
	assign o_spatial_fifo_empty = spatial_fifo_empty_o; // 空间为层结束判断公开本路排空情况。
	assign o_spatial_fifo_count = cnt_spatial_occupancy; // 空间公开等待本路HP2消费的精确项数。
	assign o_bypass_fifo_valid = bypass_fifo_valid_o; // 旁路把本路已有队首资格交给写回端。
	assign o_bypass_fifo_data = bypass_fifo_data_o; // 旁路从所属存储体交付当前四项INT16。
	assign o_bypass_fifo_mask = bypass_fifo_mask_o; // 旁路把尾字参与信息交给本路消费者。
	assign o_bypass_fifo_full = bypass_fifo_full_o; // 旁路为CAL公开本路容量耗尽情况。
	assign o_bypass_fifo_empty = bypass_fifo_empty_o; // 旁路为层结束判断公开本路排空情况。
	assign o_bypass_fifo_count = cnt_bypass_occupancy; // 旁路公开等待本路HP2消费的精确项数。

	//--------------模块实例化区域--------------//
	// 复用当前B5弹性量化边界及跨tile完整部分和。
	result_packer result_packer_Inst(           // 无第二份bundle数据寄存，直接使用B5。
		.i_clk(i_clk),                          // 序列化和两个FIFO在同一FCLK域推进。
		.i_rstn(i_rstn),                        // 在途bundle与弹性量化项同时被取消。
		.i_bundle_valid(flag_bundle_valid),     // 只有所选队列未满的请求进入B5锁存端。
		.o_bundle_ready(flag_bundle_ready),     // B5上下文已释放才开放外部入口。
		.i_bundle_data(i_bundle_data),          // 直接提供完整点积，C3没有第二份超宽寄存。
		.i_bias_data(i_bias_data),              // 本组偏置只由B5末tile路径使用。
		.i_lane_mask(i_lane_mask),              // 有效前缀决定当前bundle排出几个quad。
		.i_mode(i_mode),                        // B5在接受沿保存该组的结果类别。
		.i_spatial_index(i_spatial_index),      // 跨tile访问沿用B5空间部分和槽位。
		.i_first_tile(i_first_tile),            // 首tile任务从此重新覆盖部分和历史。
		.i_last_tile(i_last_tile),              // 只有完整和才交付量化和结果队列。
		.i_right_shift(i_right_shift),          // 每个接受的bundle保持其量化缩放配置。
		.i_relu(i_relu),                        // 激活属性在B5接受沿保存到该组排空。
		.o_out_valid(flag_packer_valid),        // 已准备的四lane量化项发出入队请求。
		.i_out_ready(flag_packer_ready),        // 锁存类别对应的写容量控制弹性项推进。
		.o_out_data(quantized_data),            // 量化后的四项INT16共用分流数据总线。
		.o_out_mask(flag_quantized_mask),       // 结果资格随四项数值一起分流。
		.o_out_bypass(flag_packer_bypass),      // pending输入模式不能修改已接受组的路由。
		.o_busy(busy_o)                         // 最后量化项未写入前继续保护当前上下文。
	);

	// spatial路队列独立吸收当前B5已接受的结果。
	result_fifo_3x3 result_spatial_fifo_Inst(   // 私有512项结果存储封装。
		.i_clk(i_clk),                          // 空间专用：子队列读写指针与数据写口使用统一计算时钟。
		.i_rstn(i_rstn),                        // 空间专用：立即取消私有队列旧占用，保留数据数组。
		.i_in_valid(flag_spatial_valid),        // 空间专用：只有本类量化项可提出私有队列写请求。
		.o_in_ready(flag_spatial_ready),        // 空间专用：本队列的剩余容量反馈给在途生产者。
		.i_in_data(quantized_data),             // 空间专用：本次四lane数值按原位序入私有存储。
		.i_in_mask(flag_quantized_mask),        // 空间专用：当前四lane参与位与数据写入同一项。
		.o_out_valid(spatial_fifo_valid_o),     // 空间专用：已写队首是否存在由队列控制返回。
		.i_out_ready(i_spatial_fifo_ready),     // 空间专用：写回端独立决定本路队首消费时机。
		.o_out_data(spatial_fifo_data_o),       // 空间专用：私有读头的64位数值送到所属写回流。
		.o_out_mask(spatial_fifo_mask_o),       // 空间专用：读头附带参与标签同步送写回端。
		.o_full(spatial_fifo_full_o),           // 空间专用：容量告警来自本路实际512项占用。
		.o_empty(spatial_fifo_empty_o),         // 空间专用：没有历史待写回项时通知外部屏障。
		.o_count(cnt_spatial_occupancy)         // 空间专用：反馈实际积压项数供验收和控制检查。
	);

	// 72路独立输出和矩阵列共用旁路私有队列。
	result_fifo_1x1 result_bypass_fifo_Inst(    // 旁路类别独占的队首及写入控制。
		.i_clk(i_clk),                          // 独立旁路：子队列读写指针与数据写口使用统一计算时钟。
		.i_rstn(i_rstn),                        // 独立旁路：立即取消私有队列旧占用，保留数据数组。
		.i_in_valid(flag_bypass_valid),         // 独立旁路：只有本类量化项可提出私有队列写请求。
		.o_in_ready(flag_bypass_ready),         // 独立旁路：本队列的剩余容量反馈给在途生产者。
		.i_in_data(quantized_data),             // 独立旁路：本次四lane数值按原位序入私有存储。
		.i_in_mask(flag_quantized_mask),        // 独立旁路：当前四lane参与位与数据写入同一项。
		.o_out_valid(bypass_fifo_valid_o),      // 独立旁路：已写队首是否存在由队列控制返回。
		.i_out_ready(i_bypass_fifo_ready),      // 独立旁路：写回端独立决定本路队首消费时机。
		.o_out_data(bypass_fifo_data_o),        // 独立旁路：私有读头的64位数值送到所属写回流。
		.o_out_mask(bypass_fifo_mask_o),        // 独立旁路：读头附带参与标签同步送写回端。
		.o_full(bypass_fifo_full_o),            // 独立旁路：容量告警来自本路实际512项占用。
		.o_empty(bypass_fifo_empty_o),          // 独立旁路：没有历史待写回项时通知外部屏障。
		.o_count(cnt_bypass_occupancy)          // 独立旁路：反馈实际积压项数供验收和控制检查。
	);

endmodule
