`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     feature_buffer
// Module Name:     feature_buffer
// Description:     description/feature_buffer_Design.pdf
// Simulations:     testbench/vivado/2021.1/feature_buffer
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/feature_buffer_spec.md; docs/设计文档.md 4.3
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/08 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Codex             Create fixed three-bank feature RAM.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Codex
//
// 创建日期:        2026年10月08日
// 设计名称:        feature_buffer
// 模块名称:        feature_buffer
// 模块说明:        Description/feature_buffer_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/feature_buffer
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/feature_buffer_spec.md; docs/设计文档.md 4.3
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             创建固定三物理行特征缓存

module feature_buffer
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 特征存储及响应标签共用时钟。
	input i_rstn,                               // 低有效异步清控制，上游同步释放，存储体不复位。
	input i_ce,                                 // CAL统一暂停读写和有效响应推进。

	//-----------------用户接口-----------------//
	input i_wr_valid,                           // Feature_cmd当前四通道写请求有效。
	input i_wr_safe,                            // 当前地址全部旧通道对已消费的覆盖授权。
	input [1:0]i_wr_bank,                       // 物理bank零至二，编码三拒绝写入。
	input [11:0]i_wr_addr,                      // 每行四通道word地址零至4095。
	input [63:0]i_wr_data,                      // 小端四个INT16，最低通道位于低16位。
	output o_wr_ready,                          // 获得授权且与读请求无碰撞时可写。
	input i_rd_valid,                           // CAL当前双通道读请求有效。
	input [12:0]i_rd_addr,                      // 双通道pair地址，最低位选择半word。
	output o_rd_ready,                          // 复位释放且统一推进时可读。
	output o_out_valid,                         // 上一推进沿接受读请求的响应资格。
	output [95:0]o_out_data                     // 低到高依次为三个物理bank的32位pair。
);

	//----------------寄存器信号----------------//
	(* ram_style = "block", ram_decomp = "power" *) reg [63:0]reg_bank_first [0:4095]; // 物理bank零保存16384个INT16，不清RAM。
	(* ram_style = "block", ram_decomp = "power" *) reg [63:0]reg_bank_second [0:4095]; // 物理bank一独立读写，不搬动行内容。
	(* ram_style = "block", ram_decomp = "power" *) reg [63:0]reg_bank_third [0:4095]; // 物理bank二容量与另两行相同。
	reg [63:0]reg_read_first;                   // bank零同步读出的完整四通道word。
	reg [63:0]reg_read_second;                  // bank一同步读出的完整四通道word。
	reg [63:0]reg_read_third;                   // bank二同步读出的完整四通道word。
	reg reg_read_half;                          // 与同步读word对齐的半word标签。

	//-----------------标志信号-----------------//
	wire flag_collision;                        // 三行同时读取时同word写入必须等待。
	wire flag_write;                            // 已授权且已握手的四通道写事务。
	wire flag_read;                             // 已握手的三物理bank共同读事务。

	//-----------------其他信号-----------------//
	//同步读地址
	wire [11:0]read_word;                       // pair地址去除最低半word选择位。

	//-----------------输出信号-----------------//
	//用户接口
	wire wr_ready_o;                            // 覆盖授权、合法bank和无碰撞共同许可。
	wire rd_ready_o;                            // 与CAL推进同步的读侧许可。
	reg out_valid_o;                            // 暂停保持，异步复位立即撤销资格。
	wire [95:0]out_data_o;                      // 由同步读word和寄存半word标签选取。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign read_word = i_rd_addr[12:1];         // 每个64位word对应两个相邻pair。
	assign flag_collision = i_rd_valid && read_word == i_wr_addr; // 读访问所有bank，同word时读优先。
	assign flag_write = i_wr_valid && wr_ready_o; // 仅握手成功才允许RAM更新。
	assign flag_read = i_rd_valid && rd_ready_o; // 仅握手成功才更新读word与标签。
	assign wr_ready_o = i_rstn && i_ce && i_wr_safe && i_wr_bank < 2'd3 && !flag_collision; // 未授权或非法请求保持反压。
	assign rd_ready_o = i_rstn && i_ce;         // 停顿和硬复位均禁止读事务。
	assign out_data_o = reg_read_half ? {reg_read_third[63:32], reg_read_second[63:32], reg_read_first[63:32]} : {reg_read_third[31:0], reg_read_second[31:0], reg_read_first[31:0]}; // 固定物理bank顺序，不在缓存内轮换角色。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_wr_ready = wr_ready_o;             // 写生产者保持请求直到此许可握手。
	assign o_rd_ready = rd_ready_o;             // CAL仅在许可时推进读地址。
	assign o_out_valid = out_valid_o;           // 消费者仅在ce与有效标志同时为一时消费。
	assign o_out_data = out_data_o;             // 有效响应之外的数据不作定义。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 有效资格与半word标签异步清除，RAM数据始终保持独立同步读。
	always@(posedge i_clk or negedge i_rstn)begin
		if(!i_rstn)begin
			out_valid_o <= 1'b0;                // 任意相位撤销在途响应，优先于暂停。
			reg_read_half <= 1'b0;              // 清除旧读请求的半word标签。
		end else if(i_ce)begin
			out_valid_o <= flag_read;           // 接受沿后输出响应，连续读取每拍一项。
			if(flag_read)begin
				reg_read_half <= i_rd_addr[0];  // 标签与三个同步读word同沿更新。
			end
		end
	end

	//-------------主要任务处理区域-------------//
	// bank零为同步简单双口RAM，同word写已在共享许可处阻止。
	always@(posedge i_clk)begin
		if(flag_write && i_wr_bank == 2'd0)begin
			reg_bank_first[i_wr_addr] <= i_wr_data; // 仅覆盖已经消费完的物理行word。
		end
		if(flag_read)begin
			reg_read_first <= reg_bank_first[read_word]; // 无复位读寄存器保持BRAM推断。
		end
	end

	// bank一与其他物理行同拍读取，不受角色轮换影响。
	always@(posedge i_clk)begin
		if(flag_write && i_wr_bank == 2'd1)begin
			reg_bank_second[i_wr_addr] <= i_wr_data; // 写侧每拍只能选择一个物理bank。
		end
		if(flag_read)begin
			reg_read_second <= reg_bank_second[read_word]; // 以共同地址取得对应的中间物理行word。
		end
	end

	// bank二保持相同容量，读写使能统一随CAL暂停。
	always@(posedge i_clk)begin
		if(flag_write && i_wr_bank == 2'd2)begin
			reg_bank_third[i_wr_addr] <= i_wr_data; // 合法末bank接受完整四通道word。
		end
		if(flag_read)begin
			reg_read_third <= reg_bank_third[read_word]; // 同步取第三个物理行word供并行输出。
		end
	end

endmodule
