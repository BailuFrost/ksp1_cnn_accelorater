`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     tile_psum_buffer
// Module Name:     tile_psum_buffer
// Description:     description/tile_psum_buffer_Design.pdf
// Simulations:     testbench/vivado/2021.1/tile_psum_buffer
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/tile_psum_buffer_spec.md; docs/设计文档.md 4.11
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
// 设计名称:        tile_psum_buffer
// 模块名称:        tile_psum_buffer
// 模块说明:        Description/tile_psum_buffer_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/tile_psum_buffer
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/tile_psum_buffer_spec.md; docs/设计文档.md 4.11
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             统一既有阶段B代码风格

module tile_psum_buffer
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 部分和读写及响应流水共用时钟。
	input i_rstn,                               // 低有效异步清除控制，上游同步释放；RAM与读数据不复位。

	//-----------------用户接口-----------------//
	input i_in_valid,                           // 四lane部分和请求有效。
	output o_in_ready,                          // 响应可推进且地址在固定容量内时允许接收。
	input [12:0]i_address,                      // 空间位置乘27加四lane字号，范围零至5291。
	input [191:0]i_in_data,                     // 低到高四项48位完整tile点积。
	input [3:0]i_in_mask,                       // 每位对应一个有效部分和lane。
	input i_first_tile,                         // 首tile整字覆盖旧缓存，无需读历史RAM。
	input i_last_tile,                          // 末tile返回完整和，禁止写回量化结果。
	output o_out_valid,                         // 已寄存响应有效，等待下游消费。
	input i_out_ready,                          // 下游允许消费当前完整部分和。
	output [191:0]o_out_data                    // 屏蔽无效lane后的四项48位完整和。
);

	//----------------寄存器信号----------------//
	reg [12:0]reg_saved_address;                // 请求地址跨同步读边界保持。
	reg [191:0]reg_saved_data;                  // 当前tile四项完整点积等待历史数据。
	reg [3:0]reg_saved_mask;                    // lane参与资格与请求数据一同保存。
	(* ram_style = "block", ram_decomp = "power" *) reg [191:0]reg_memory [0:5291]; // 固定196乘27个宽字，使用块RAM且不复位。
	reg [191:0]reg_read_data;                   // 同步RAM旧字，仅在非首tile有效读后使用。

	//-----------------标志信号-----------------//
	reg flag_pending;                           // 请求已锁存，下一推进沿形成响应。
	reg flag_saved_first;                       // 锁存首tile资格以选择覆盖路径。
	reg flag_saved_last;                        // 锁存末tile标志以抑制RAM写回。
	wire flag_advance;                          // 输出空闲或本拍被消费时两级共同推进。

	//-----------------其他信号-----------------//
	//四lane部分和计算
	wire [191:0]accumulated;                    // 每项按48位补码求和，无效lane写零。

	//-----------------输出信号-----------------//
	//用户接口
	wire in_ready_o;                            // 容量检查和输出推进共同决定入口许可。
	reg out_valid_o;                            // 响应资格随pending推进，反压时保持。
	reg [191:0]out_data_o;                      // 完整部分和响应寄存器，不做INT16量化。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_advance = !out_valid_o || i_out_ready; // 响应已占用且下游停顿时冻结读写。
	assign accumulated[47:0] = reg_saved_mask[0] ? (flag_saved_first ? reg_saved_data[47:0] : reg_read_data[47:0]+reg_saved_data[47:0]) : 48'd0; // 最低lane首tile覆盖、后续累加，未参与时归零。
	assign accumulated[95:48] = reg_saved_mask[1] ? (flag_saved_first ? reg_saved_data[95:48] : reg_read_data[95:48]+reg_saved_data[95:48]) : 48'd0; // 次低lane首tile覆盖、后续累加，未参与时归零。
	assign accumulated[143:96] = reg_saved_mask[2] ? (flag_saved_first ? reg_saved_data[143:96] : reg_read_data[143:96]+reg_saved_data[143:96]) : 48'd0; // 次高lane首tile覆盖、后续累加，未参与时归零。
	assign accumulated[191:144] = reg_saved_mask[3] ? (flag_saved_first ? reg_saved_data[191:144] : reg_read_data[191:144]+reg_saved_data[191:144]) : 48'd0; // 最高lane首tile覆盖、后续累加，未参与时归零。

	assign in_ready_o = i_rstn && flag_advance && i_address<13'd5292; // 复位或越界禁止新请求进入缓存。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_in_ready = in_ready_o;             // 请求许可经完整单bit信号连接端口。
	assign o_out_valid = out_valid_o;           // 下游以有效且就绪消费响应。
	assign o_out_data = out_data_o;             // 输出四项未量化完整部分和。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 请求与响应共享推进条件；保持原有E0接受、E1响应、E2消费边界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(!i_rstn)begin
			flag_pending <= 1'b0;               // 取消等待生成响应的旧请求。
			out_valid_o <= 1'b0;                // 立即撤销输出响应资格。
			reg_saved_address <= 13'd0;         // 复位请求的线性地址标签。
			reg_saved_data <= 192'd0;           // 清除请求携带的四项tile贡献。
			reg_saved_mask <= 4'd0;             // 旧请求不再允许任何lane参与。
			flag_saved_first <= 1'b0;           // 清除首tile覆盖控制。
			flag_saved_last <= 1'b0;            // 清除末tile写回抑制标志。
			out_data_o <= 192'd0;               // 旧响应的四项数据立即归零。
		end else if(flag_advance)begin
			out_valid_o <= flag_pending;        // 上一接受的请求进入响应级。
			if(flag_pending)begin
				out_data_o <= accumulated;      // 仅已接受请求更新完整和响应。
			end
			flag_pending <= i_in_valid && o_in_ready; // 同拍允许下一个合法请求接续。
			if(i_in_valid && o_in_ready)begin
				reg_saved_address <= i_address; // 保存RAM响应与写回所用地址。
				reg_saved_data <= i_in_data;    // 锁存当前tile的四lane原始贡献。
				reg_saved_mask <= i_in_mask;    // 请求参与位随数值跨越读边界。
				flag_saved_first <= i_first_tile; // 接受沿确定覆盖或读加写路径。
				flag_saved_last <= i_last_tile; // 本次请求的末tile属性不受后续输入影响。
			end
		end
	end

	//-------------主要任务处理区域-------------//
	// RAM过程仅同步读写，硬复位禁止写入且保留数组原值。
	always@(posedge i_clk)begin
		if(i_in_valid && o_in_ready && !i_first_tile)begin
			reg_read_data <= reg_memory[i_address]; // 后续tile在接受沿读取旧的四lane字。
		end
		if(i_rstn && flag_advance && flag_pending && !flag_saved_last)begin
			reg_memory[reg_saved_address] <= accumulated; // 非末tile在响应生成沿写回完整48位部分和。
		end
	end

endmodule
