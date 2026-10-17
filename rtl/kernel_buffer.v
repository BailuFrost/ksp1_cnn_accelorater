`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     kernel_buffer
// Module Name:     kernel_buffer
// Description:     description/kernel_buffer_Design.pdf
// Simulations:     testbench/vivado/2021.1/kernel_buffer
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/kernel_buffer_spec.md; docs/设计文档.md 4.4
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/08 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Codex             Create fixed 12-CU nine-bank weight RAM.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Codex
//
// 创建日期:        2026年10月08日
// 设计名称:        kernel_buffer
// 模块名称:        kernel_buffer
// 模块说明:        Description/kernel_buffer_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/kernel_buffer
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/kernel_buffer_spec.md; docs/设计文档.md 4.4
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             创建固定八单元九核权重缓存

module kernel_buffer
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 权重装载、共同读及响应有效标签时钟。
	input i_rstn,                               // 低有效异步清有效资格，上游同步释放，RAM不复位。
	input i_ce,                                 // CAL统一冻结全部权重存储动作。

	//-----------------用户接口-----------------//
	input i_load_enable,                        // 一为装载阶段，零为计算阶段，读写分时。
	input i_wr_valid,                           // Weight_cmd原生双INT16写请求有效。
	input [3:0]i_wr_cu,                         // 写入目标计算单元，范围零至十一。
	input [3:0]i_wr_bank,                       // 目标CU内核bank，范围零至八。
	input [7:0]i_wr_addr,                       // 每bank双通道pair地址零至255。
	input [31:0]i_wr_data,                      // 低16位为先通道，高16位为后通道。
	output o_wr_ready,                          // 装载阶段且CU和bank合法时允许写入。
	input i_rd_valid,                           // CAL对全部bank共同发出pair读请求。
	input [7:0]i_rd_addr,                       // 全72个bank共用双通道读地址。
	output o_rd_ready,                          // 计算阶段且全局推进时接受读取。
	output o_out_valid,                         // 最近推进沿接受的共同读响应有效。
	output [2303:0]o_out_data                   // CU-major、bank-major的72个32位权重pair。
);

	//-----------------标志信号-----------------//
	wire flag_write;                            // 合法装载请求已经完成握手。
	wire flag_read;                             // 计算阶段已接受共同读请求。

	//-----------------其他信号-----------------//
	//静态存储展开索引
	genvar cu_index;                            // 固定八个计算单元的展开索引。
	genvar bank_index;                          // 每CU固定九个私有核bank的展开索引。

	//-----------------输出信号-----------------//
	//用户接口
	wire wr_ready_o;                            // 复位、暂停和地址编码共同限定装载许可。
	wire rd_ready_o;                            // 装载期间禁止共同读，避免读写碰撞。
	reg out_valid_o;                            // 暂停时保持，异步复位立即撤销。
	wire [2303:0]out_data_o;                    // 各bank同步读寄存器按物理顺序拼接。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_write = i_wr_valid && wr_ready_o; // 仅成功握手允许目标存储体更新。
	assign flag_read = i_rd_valid && rd_ready_o; // 全bank共同同步读，连续请求每拍一项。
	assign wr_ready_o = i_rstn && i_ce && i_load_enable && i_wr_cu < 4'd8 && i_wr_bank < 4'd9; // 非法CU或bank在接口边界拒绝。
	assign rd_ready_o = i_rstn && i_ce && !i_load_enable; // 分时读写不依赖RAM读写同址行为。

	// 以固定CU-major/K-major展开连接完整72路同步读，不对权重再次转置。
	assign out_data_o = {                       // 固定拼接72个独立同步RAM读pair。
		{gen_compute_unit[7].gen_kernel_bank[8].reg_pair_read, gen_compute_unit[7].gen_kernel_bank[7].reg_pair_read, gen_compute_unit[7].gen_kernel_bank[6].reg_pair_read, gen_compute_unit[7].gen_kernel_bank[5].reg_pair_read, gen_compute_unit[7].gen_kernel_bank[4].reg_pair_read, gen_compute_unit[7].gen_kernel_bank[3].reg_pair_read, gen_compute_unit[7].gen_kernel_bank[2].reg_pair_read, gen_compute_unit[7].gen_kernel_bank[1].reg_pair_read, gen_compute_unit[7].gen_kernel_bank[0].reg_pair_read},
		{gen_compute_unit[6].gen_kernel_bank[8].reg_pair_read, gen_compute_unit[6].gen_kernel_bank[7].reg_pair_read, gen_compute_unit[6].gen_kernel_bank[6].reg_pair_read, gen_compute_unit[6].gen_kernel_bank[5].reg_pair_read, gen_compute_unit[6].gen_kernel_bank[4].reg_pair_read, gen_compute_unit[6].gen_kernel_bank[3].reg_pair_read, gen_compute_unit[6].gen_kernel_bank[2].reg_pair_read, gen_compute_unit[6].gen_kernel_bank[1].reg_pair_read, gen_compute_unit[6].gen_kernel_bank[0].reg_pair_read},
		{gen_compute_unit[5].gen_kernel_bank[8].reg_pair_read, gen_compute_unit[5].gen_kernel_bank[7].reg_pair_read, gen_compute_unit[5].gen_kernel_bank[6].reg_pair_read, gen_compute_unit[5].gen_kernel_bank[5].reg_pair_read, gen_compute_unit[5].gen_kernel_bank[4].reg_pair_read, gen_compute_unit[5].gen_kernel_bank[3].reg_pair_read, gen_compute_unit[5].gen_kernel_bank[2].reg_pair_read, gen_compute_unit[5].gen_kernel_bank[1].reg_pair_read, gen_compute_unit[5].gen_kernel_bank[0].reg_pair_read},
		{gen_compute_unit[4].gen_kernel_bank[8].reg_pair_read, gen_compute_unit[4].gen_kernel_bank[7].reg_pair_read, gen_compute_unit[4].gen_kernel_bank[6].reg_pair_read, gen_compute_unit[4].gen_kernel_bank[5].reg_pair_read, gen_compute_unit[4].gen_kernel_bank[4].reg_pair_read, gen_compute_unit[4].gen_kernel_bank[3].reg_pair_read, gen_compute_unit[4].gen_kernel_bank[2].reg_pair_read, gen_compute_unit[4].gen_kernel_bank[1].reg_pair_read, gen_compute_unit[4].gen_kernel_bank[0].reg_pair_read},
		{gen_compute_unit[3].gen_kernel_bank[8].reg_pair_read, gen_compute_unit[3].gen_kernel_bank[7].reg_pair_read, gen_compute_unit[3].gen_kernel_bank[6].reg_pair_read, gen_compute_unit[3].gen_kernel_bank[5].reg_pair_read, gen_compute_unit[3].gen_kernel_bank[4].reg_pair_read, gen_compute_unit[3].gen_kernel_bank[3].reg_pair_read, gen_compute_unit[3].gen_kernel_bank[2].reg_pair_read, gen_compute_unit[3].gen_kernel_bank[1].reg_pair_read, gen_compute_unit[3].gen_kernel_bank[0].reg_pair_read},
		{gen_compute_unit[2].gen_kernel_bank[8].reg_pair_read, gen_compute_unit[2].gen_kernel_bank[7].reg_pair_read, gen_compute_unit[2].gen_kernel_bank[6].reg_pair_read, gen_compute_unit[2].gen_kernel_bank[5].reg_pair_read, gen_compute_unit[2].gen_kernel_bank[4].reg_pair_read, gen_compute_unit[2].gen_kernel_bank[3].reg_pair_read, gen_compute_unit[2].gen_kernel_bank[2].reg_pair_read, gen_compute_unit[2].gen_kernel_bank[1].reg_pair_read, gen_compute_unit[2].gen_kernel_bank[0].reg_pair_read},
		{gen_compute_unit[1].gen_kernel_bank[8].reg_pair_read, gen_compute_unit[1].gen_kernel_bank[7].reg_pair_read, gen_compute_unit[1].gen_kernel_bank[6].reg_pair_read, gen_compute_unit[1].gen_kernel_bank[5].reg_pair_read, gen_compute_unit[1].gen_kernel_bank[4].reg_pair_read, gen_compute_unit[1].gen_kernel_bank[3].reg_pair_read, gen_compute_unit[1].gen_kernel_bank[2].reg_pair_read, gen_compute_unit[1].gen_kernel_bank[1].reg_pair_read, gen_compute_unit[1].gen_kernel_bank[0].reg_pair_read},
		{gen_compute_unit[0].gen_kernel_bank[8].reg_pair_read, gen_compute_unit[0].gen_kernel_bank[7].reg_pair_read, gen_compute_unit[0].gen_kernel_bank[6].reg_pair_read, gen_compute_unit[0].gen_kernel_bank[5].reg_pair_read, gen_compute_unit[0].gen_kernel_bank[4].reg_pair_read, gen_compute_unit[0].gen_kernel_bank[3].reg_pair_read, gen_compute_unit[0].gen_kernel_bank[2].reg_pair_read, gen_compute_unit[0].gen_kernel_bank[1].reg_pair_read, gen_compute_unit[0].gen_kernel_bank[0].reg_pair_read}
	};                                          // 最低32位为CU0/K0，最高32位为CU7/K8。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_wr_ready = wr_ready_o;             // Weight_cmd保持请求直到目标bank接受。
	assign o_rd_ready = rd_ready_o;             // CAL在共同读取许可时推进深度地址。
	assign o_out_valid = out_valid_o;           // 下游以ce且有效消费当前同步响应。
	assign o_out_data = out_data_o;             // 最低288位为首CU，最高288位为末CU。


	//-------------输出信号处理区域-------------//
	//用户接口
	// 控制复位独立于RAM过程，不给存储体或读数据添加复位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(!i_rstn)begin
			out_valid_o <= 1'b0;                // 任意相位取消在途读响应资格。
		end else if(i_ce)begin
			out_valid_o <= flag_read;           // 接受沿后输出资格，装载或空读沿撤销。
		end
	end

	//---------------生成块区域-----------------//
	// 固定展开八个CU的私有存储与两级写使能，不暴露容量参数。
	generate
		// 展开固定八组CU，每组只接受对应编号的权重写入。
		for(cu_index = 0; cu_index < 8; cu_index = cu_index + 1)begin:gen_compute_unit
			localparam [3:0] CU_INDEX = cu_index; // 此静态CU编号参与第一层装载译码。
			wire flag_cu_write;                 // 共享写事务仅进入被选中的计算单元。
			assign flag_cu_write = flag_write && i_wr_cu == CU_INDEX; // 先选择CU，再选择内部核bank。
			// 每个CU的九个bank保持各自的同步读寄存器。
			for(bank_index = 0; bank_index < 9; bank_index = bank_index + 1)begin:gen_kernel_bank
				localparam [3:0] BANK_INDEX = bank_index; // 固定核位置或独立输出lane编号。
				(* ram_style = "block" *) reg [31:0]reg_pair_memory [0:255]; // 每bank512个INT16，不初始化、不清RAM。
				reg [31:0]reg_pair_read;        // 无复位同步读数据，保持BRAM读寄存器推断。
				wire flag_bank_write;           // 第二层译码只许可一个核bank写入。
				assign flag_bank_write = flag_cu_write && i_wr_bank == BANK_INDEX; // CU私有权重不受其他bank写入影响。
				// 分时同步读写保证无碰撞；复位和暂停由共享握手许可抑制。
				always@(posedge i_clk)begin
					if(flag_bank_write)begin
						reg_pair_memory[i_wr_addr] <= i_wr_data; // 接受当前pair并覆盖旧group或tile权重。
					end
					if(flag_read)begin
						reg_pair_read <= reg_pair_memory[i_rd_addr]; // 同沿读取全部bank的相邻两个通道。
					end
				end
			end
		end
	endgenerate

endmodule
