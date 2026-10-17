`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     result_fifo
// Module Name:     result_fifo
// Description:     description/result_fifo_Design.pdf
// Simulations:     testbench/vivado/2021.1/result_fifo
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/result_fifo_spec.md; docs/设计文档.md 4.9
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
// 设计名称:        result_fifo
// 模块名称:        result_fifo
// 模块说明:        Description/result_fifo_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/result_fifo
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/result_fifo_spec.md; docs/设计文档.md 4.9
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             创建结果队列及序列化连接

module result_fifo
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
	output [63:0]o_out_data,                    // 沿后立即呈现当前队首的64位结果。
	output [3:0]o_out_mask,                     // 队首数据对应的四lane标签。
	output o_full,                              // 实际占用等于512，满时保守拒绝写。
	output o_empty,                             // 实际占用为零，不提供空旁路。
	output [9:0]o_count                         // 十位占用计数，范围零至512。
);

	//-----------------计数信号-----------------//
	reg [9:0]cnt_occupancy;                     // 队列实际占用，十位表示满容量512。
	wire [9:0]cnt_items;                        // 占用状态供输出控制器判断排空。

	//----------------寄存器信号----------------//
	reg [8:0]reg_write_pointer;                 // 写游标九位自然从511回到零。
	reg [8:0]reg_read_pointer;                  // 出队游标仅在成功消费时推进。
	(* ram_style="block" *) reg [67:0]reg_memory [0:511]; // 数据与mask同址保存，数组不复位。
	reg [67:0]reg_read_data;                    // 出队沿同步读取下一队首，反压时保持。
	reg [67:0]reg_bypass_data;                  // 空队列首写或单项替换直接保存新载荷。

	//-----------------标志信号-----------------//
	wire flag_write;                            // 当前非满写请求完成握手。
	wire flag_read;                             // 当前非空队首完成出队。
	reg flag_bypass;                            // 当前队首来自首写旁路而非同步RAM读口。
	wire flag_replace;                          // 首写或单项同沿读写需要避开RAM同址碰撞。

	//-----------------其他信号-----------------//
	//队首同步读与首写旁路
	wire [67:0]head_word;                       // RAM读口和直接首写共享外部队首合同。
	wire [8:0]next_read_pointer;                // 九位加法保持511到零的自然回绕。

	//-----------------输出信号-----------------//
	//用户接口
	wire in_ready_o;                            // 复位释放且非满才允许写入。
	wire out_valid_o;                           // 复位期间禁止旧队首取得消费资格。
	wire [63:0]out_data_o;                      // 当前队首低64位载荷。
	wire [3:0]out_mask_o;                       // 当前队首高四位参与标签。
	wire full_o;                                // 满状态独立于消费者当前ready。
	wire empty_o;                               // 零占用禁止空队列读出。

	//---------------其他信号连线---------------//
	//握手与存储读口
	assign flag_write = i_in_valid && in_ready_o; // 只有被接受数据才能更新RAM。
	assign flag_read = out_valid_o && i_out_ready; // 出队事件不得受输入valid影响。
	assign flag_replace = flag_write && (empty_o || (flag_read && cnt_occupancy == 10'd1)); // 单项替换直接使用新写数据。
	assign next_read_pointer = reg_read_pointer + 9'd1; // 消费沿预取下一有效项。
	assign head_word = flag_bypass ? reg_bypass_data : reg_read_data; // 保持E0入队、E1最早消费的既有边界。
	assign in_ready_o = i_rstn && !full_o;      // 满时即使同沿读也保守拒绝新写。
	assign out_valid_o = i_rstn && !empty_o;    // 未初始化RAM只能在写入后输出有效。
	assign out_data_o = head_word[63:0];        // INT16低lane保持在低位。
	assign out_mask_o = head_word[67:64];       // mask与数据原子入队和出队。
	assign full_o = cnt_occupancy == 10'd512;   // 固定容量不可缩减。
	assign empty_o = cnt_occupancy == 10'd0;    // 空状态不做输入旁路。
	assign cnt_items = cnt_occupancy;           // 同时读写时占用保持。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_in_ready = in_ready_o;             // 生产者仅在写许可时提交。
	assign o_out_valid = out_valid_o;           // 消费者使用队首资格握手。
	assign o_out_data = out_data_o;             // 四项结果不再处理数值。
	assign o_out_mask = out_mask_o;             // 尾组标签转交OUTPUT_cmd。
	assign o_full = full_o;                     // 向上游传播容量耗尽状态。
	assign o_empty = empty_o;                   // 空队列状态参与层间屏障。
	assign o_count = cnt_items;                 // 完整计数用于验收与控制。

	//-------------主要任务处理区域-------------//
	// 异步清队列控制而不清RAM，释放由上游时钟域统一完成。
	always@(posedge i_clk or negedge i_rstn)begin
		if(!i_rstn)begin
			reg_write_pointer <= 9'd0;          // 新队列从首项覆盖历史载荷。
			reg_read_pointer <= 9'd0;           // 丢弃所有旧队首资格。
			cnt_occupancy <= 10'd0;             // 复位立即恢复空队列。
			flag_bypass <= 1'b0;                // 复位只清资格，RAM及读口载荷不清除。
		end else begin
			if(flag_replace)begin
				flag_bypass <= 1'b1;            // 首项或替换项在同一接受沿后可见。
			end else if(flag_read && cnt_occupancy > 10'd1)begin
				flag_bypass <= 1'b0;            // 其余出队由同步RAM读口提供后继项。
			end
			if(flag_write)begin
				reg_write_pointer <= reg_write_pointer + 9'd1; // 接受后移动下一写位置。
			end
			if(flag_read)begin
				reg_read_pointer <= reg_read_pointer + 9'd1; // 消费后切到下一队首。
			end
			if(flag_write && !flag_read)begin
				cnt_occupancy <= cnt_occupancy + 10'd1; // 只有写入时增加实际占用。
			end else if(flag_read && !flag_write)begin
				cnt_occupancy <= cnt_occupancy - 10'd1; // 只有出队时释放一项容量。
			end
		end
	end

	// 同步双端口RAM；单项替换另走旁路，避免依赖同址读写模式。
	always@(posedge i_clk)begin
		if(flag_write)begin
			reg_memory[reg_write_pointer] <= {i_in_mask,i_in_data}; // 数据标签同沿写同一槽。
		end
		if(flag_read && cnt_occupancy > 10'd1)begin
			reg_read_data <= reg_memory[next_read_pointer]; // 旧队首被消费后沿立即更新到后继项。
		end
		if(flag_replace)begin
			reg_bypass_data <= {i_in_mask,i_in_data}; // 首写及单项替换不读取未初始化或同址RAM。
		end
	end

endmodule
