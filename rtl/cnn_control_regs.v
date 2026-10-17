`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/10 00:00:00
// Design Name:     cnn_control_regs
// Module Name:     cnn_control_regs
// Description:     description/cnn_control_regs_Design.pdf
// Simulations:     testbench/vivado/2021.1/cnn_control_regs
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/cnn_control_regs_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/10 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/10       V1.0        Codex             Create cnn_control_regs production integration.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月10日
// 设计名称:        cnn_control_regs
// 模块名称:        cnn_control_regs
// 模块说明:        Description/cnn_control_regs_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/cnn_control_regs
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/cnn_control_regs_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月10日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月10日   V1.0        Codex             创建微型网络生产集成接口

module cnn_control_regs
(
	//-----------------用户接口-----------------//
	input i_clk,                                // FCLK_CLK0统一时钟。
	input i_rstn,                               // 低有效异步断言，上游同域同步释放。

	input [7:0]i_axi_awaddr,                    // 寄存器字节偏移，独立接受AW。
	input i_axi_awvalid,                        // 写地址有效。
	output o_axi_awready,                       // 单个地址缓存可接受。
	input [31:0]i_axi_wdata,                    // 写寄存器载荷。
	input [3:0]i_axi_wstrb,                     // 逐字节写入资格。
	input i_axi_wvalid,                         // 写载荷有效，允许早于AW。
	output o_axi_wready,                        // 单个载荷缓存可接受。
	output [1:0]o_axi_bresp,                    // OKAY/SLVERR/DECERR响应。
	output o_axi_bvalid,                        // 写提交响应，直到BREADY保持。
	input i_axi_bready,                         // 主机接收写响应。
	input [7:0]i_axi_araddr,                    // 读字节偏移。
	input i_axi_arvalid,                        // 读地址有效。
	output o_axi_arready,                       // 单个读响应空闲。
	output [31:0]o_axi_rdata,                   // 接受AR时锁存的寄存器值。
	output [1:0]o_axi_rresp,                    // 读地址和对齐检查响应。
	output o_axi_rvalid,                        // 读值和响应保持至RREADY。
	input i_axi_rready,                         // 主机接收读响应。
	input i_start_ready,                        // 分发器及DMA/核心复位释放后整网接受资格。
	input i_clear_ready,                        // DMA复位完成且整网静止才允许清首错。
	input i_busy,                               // 整网执行或复位应答等待。
	input i_done,                               // 分发器粘滞成功。
	input i_error,                              // 分发器粘滞首错。
	input i_fifo_stall,                         // 结果FIFO满观测。
	input i_reset_busy,                         // DMA或计算核心正在共同复位。
	input i_runtime_error,                      // GP周期记录未成功提交。
	input [31:0]i_error_code,                   // 低8位首错、bit8运行记录错、15:12来源、31:16控制器码。
	input [7:0]i_current_layer,                 // 当前缓存层号。
	input [63:0]i_cycles,                       // 实际整网FCLK计数。
	output [31:0]o_model_base,                  // PS配置，忙时写拒绝。
	output [31:0]o_model_bytes,                 // PS实际装载文件长度，忙时写拒绝。
	output o_start,                             // 合法CONTROL写提交产生单FCLK启动。
	output o_soft_reset,                        // 单FCLK软复位，不复位AXI-Lite本身。
	output o_clear_done,                        // 静止且DMA已复位后清粘滞位。
	output o_irq                                // irq_enable且done/error为真时高电平。
);

	//----------------寄存器信号----------------//
	reg [7:0]reg_write_address = 0;             // AW缓存和载荷独立接收，提交前保持。
	reg [31:0]reg_write_data = 0;               // W缓存等待对应写地址。
	reg [3:0]reg_write_strobe = 0;              // 与缓存载荷绑定的四字节资格。
	reg [63:0]reg_cycle_snapshot = 0;           // 低周期读接受时同时抓取高半字。

	//-----------------标志信号-----------------//
	reg flag_address_pending = 0;               // 尚未配对提交的AW。
	reg flag_data_pending = 0;                  // 有效数据正在等待地址或响应槽。
	reg flag_irq_enable = 0;                    // CONTROL最低字节显式配置中断许可。
	reg flag_cycle_snapshot = 0;                // 曾接受低周期读，后续高位使用该快照。
	wire flag_write_commit;                     // 两个独立缓存及响应空闲共同授权写入。

	//-----------------其他信号-----------------//
	//写字节资格
	wire [31:0]write_mask;                      // 将WSTRB扩展为逐位更新掩码。
	wire [31:0]control_value;                   // CONTROL仅解释实际有效字节。

	//-----------------输出信号-----------------//
	//用户接口

	//用户接口
	wire axi_awready_o;                         // 写地址单在途缓存空闲许可。
	wire axi_wready_o;                          // 写载荷独立单在途许可。
	reg [1:0]axi_bresp_o = 0;                   // 本次配对写的诊断响应。
	reg axi_bvalid_o = 0;                       // 已提交写的应答保持资格。
	wire axi_arready_o;                         // 当前没有尚未被主机接受的读值。
	reg [31:0]axi_rdata_o = 0;                  // AR接受沿锁存值，R反压不改变。
	reg [1:0]axi_rresp_o = 0;                   // 当前读的地址检查结果。
	reg axi_rvalid_o = 0;                       // 读响应保持至真实接受。

	//用户接口
	reg [31:0]model_base_o = 0;                 // 软件完整装载后的模型头指针。
	reg [31:0]model_bytes_o = 0;                // 软件实际写入DDR的文件长度。
	reg start_o = 0;                            // 合法启动写提交后只保持一拍。
	reg soft_reset_o = 0;                       // 允许运行中请求共同取消，不清总线响应。
	reg clear_done_o = 0;                       // DMA已复位后清粘滞状态请求。
	wire irq_o;                                 // PS读取或被反压不能消除粘滞中断来源。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_write_commit = flag_address_pending && flag_data_pending && !axi_bvalid_o; // AW/W到齐后的独立提交资格。
	assign write_mask = {{8{reg_write_strobe[3]}}, {8{reg_write_strobe[2]}}, {8{reg_write_strobe[1]}}, {8{reg_write_strobe[0]}}}; // 部分写只改被选中字节。
	assign control_value = reg_write_data & write_mask; // 非有效字节不能产生脉冲或保留位错误。

	//用户接口
	assign axi_awready_o = i_rstn && !flag_address_pending && !axi_bvalid_o; // 有未提交地址或响应时禁止覆盖AW。
	assign axi_wready_o = i_rstn && !flag_data_pending && !axi_bvalid_o; // 先来的W可以独立等待AW。
	assign axi_arready_o = i_rstn && !axi_rvalid_o; // RREADY未到时不接受新AR。

	//用户接口
	assign irq_o = flag_irq_enable && (i_done || i_error); // IRQ许可与粘滞完成/首错直接组合。

	//---------------输出信号连线---------------//
	//用户接口

	//用户接口
	assign o_axi_awready = axi_awready_o;       // 地址ready直接转发独立缓存状态。
	assign o_axi_wready = axi_wready_o;         // 数据ready不依赖AWVALID。
	assign o_axi_bresp = axi_bresp_o;           // 错误不默默丢弃写请求。
	assign o_axi_bvalid = axi_bvalid_o;         // 总线必须接受该已提交响应。
	assign o_axi_arready = axi_arready_o;       // 单读响应容量向上游传播。
	assign o_axi_rdata = axi_rdata_o;           // 读取值从锁存寄存器输出。
	assign o_axi_rresp = axi_rresp_o;           // 读权限与范围诊断转发。
	assign o_axi_rvalid = axi_rvalid_o;         // 待接收读响应的稳定有效位。

	//用户接口
	assign o_model_base = model_base_o;         // 完整模型指针供分发器层首锁存。
	assign o_model_bytes = model_bytes_o;       // 文件长度来自PS而非未校验模型头。
	assign o_start = start_o;                   // 整网单拍启动请求输出。
	assign o_soft_reset = soft_reset_o;         // 同步共同复位事件交给顶层。
	assign o_clear_done = clear_done_o;         // 只清结束任务的粘滞位。
	assign o_irq = irq_o;                       // 电平IRQ等待PS清状态。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 两个写通道独立缓存，配对后只提交一次CONTROL或参数更新。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_write_address <= 0; reg_write_data <= 0; reg_write_strobe <= 0; // 硬复位取消尚未配对的总线载荷。
			flag_address_pending <= 0; flag_data_pending <= 0; flag_irq_enable <= 0; // 写缓存及中断许可初始化。
			axi_bvalid_o <= 0; axi_bresp_o <= 0; // 硬复位没有遗留写应答。
			model_base_o <= 0; model_bytes_o <= 0; // 必须由PS显式配置真实文件。
			start_o <= 0; soft_reset_o <= 0; clear_done_o <= 0; // 硬复位不产生控制事件。
		end else begin
			start_o <= 0; soft_reset_o <= 0; clear_done_o <= 0; // 所有控制事件默认撤销，只在本次写提交产生。
			if(axi_bvalid_o == 1'b1 && i_axi_bready == 1'b1)begin
				axi_bvalid_o <= 0;              // 主机真实接受后释放响应容量。
			end
			if(o_axi_awready == 1'b1 && i_axi_awvalid == 1'b1)begin
				reg_write_address <= i_axi_awaddr; flag_address_pending <= 1; // 地址可早于或晚于载荷。
			end
			if(o_axi_wready == 1'b1 && i_axi_wvalid == 1'b1)begin
				reg_write_data <= i_axi_wdata; reg_write_strobe <= i_axi_wstrb; flag_data_pending <= 1; // 同一W事务保留其字节mask。
			end
			if(flag_write_commit == 1'b1)begin
				flag_address_pending <= 0; flag_data_pending <= 0; axi_bvalid_o <= 1; axi_bresp_o <= 0; // 配对提交后不再重复执行。
				if(reg_write_address[1:0] != 0)begin
					axi_bresp_o <= 2'b10;       // 字地址未对齐不能更新寄存器。
				end else begin
					case(reg_write_address)
						8'h00:begin
							if(control_value[31:4] != 0 || (control_value[0] && (control_value[1] || control_value[3])) || (control_value[0] && i_start_ready == 1'b0) || (control_value[3] && i_clear_ready == 1'b0))begin
								axi_bresp_o <= 2'b10; // 保留位及非法控制组合/时机直接拒绝。
							end else if(reg_write_strobe[0])begin
								flag_irq_enable <= reg_write_data[2]; start_o <= reg_write_data[0]; soft_reset_o <= reg_write_data[1]; clear_done_o <= reg_write_data[3]; // 最低有效字节原子提交控制。
							end
						end
						8'h08:begin
							if(i_busy == 1'b1)begin
								axi_bresp_o <= 2'b10; // 当前模型执行时不修改PS指针。
							end else begin
								model_base_o <= (model_base_o & ~write_mask) | (reg_write_data & write_mask); // 部分写保持其它字节。
							end
						end
						8'h20:begin
							if(i_busy == 1'b1)begin
								axi_bresp_o <= 2'b10; // 当前模型执行时不改变实际文件长度。
							end else begin
								model_bytes_o <= (model_bytes_o & ~write_mask) | (reg_write_data & write_mask); // 长度也支持WSTRB。
							end
						end
						8'h04,8'h0c,8'h10,8'h14,8'h18,8'h1c:begin
							axi_bresp_o <= 2'b10; // 所有只读寄存器写请求明确报权限错误。
						end
						default:begin
							axi_bresp_o <= 2'b11; // 未定义偏移不提供隐含寄存器别名。
						end
					endcase
				end
			end
		end
	end

	// 接受读地址时捕获完整应答，周期低/高读取保持同一个64位快照。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			axi_rdata_o <= 0; axi_rresp_o <= 0; axi_rvalid_o <= 0; // 没有硬复位之前的读结果。
			reg_cycle_snapshot <= 0; flag_cycle_snapshot <= 0; // 周期快照资格从零开始。
		end else begin
			if(soft_reset_o == 1'b1)begin
				reg_cycle_snapshot <= 0; flag_cycle_snapshot <= 0; // 新任务不能复用旧周期高位。
			end
			if(axi_rvalid_o == 1'b1 && i_axi_rready == 1'b1)begin
				axi_rvalid_o <= 0;              // R握手后释放单响应槽。
			end
			if(o_axi_arready == 1'b1 && i_axi_arvalid == 1'b1)begin
				axi_rvalid_o <= 1; axi_rdata_o <= 0; axi_rresp_o <= 0; // 安全默认值随该AR接受绑定。
				if(i_axi_araddr[1:0] != 0)begin
					axi_rresp_o <= 2'b10;       // 未对齐读不返回相邻字。
				end else begin
					case(i_axi_araddr)
						8'h00:begin
							axi_rdata_o <= {29'd0, flag_irq_enable, 2'd0}; // 脉冲位读取为零，许可位可回读。
						end
						8'h04:begin
							axi_rdata_o <= {25'd0, i_start_ready, i_runtime_error, i_reset_busy, i_fifo_stall, i_error, i_done, i_busy}; // STATUS附带复位与启动资格。
						end
						8'h08:begin
							axi_rdata_o <= model_base_o; // 回读PS保存的模型基址。
						end
						8'h0c:begin
							axi_rdata_o <= i_cycles[31:0]; reg_cycle_snapshot <= i_cycles; flag_cycle_snapshot <= 1; // 周期低位读取建立高位一致性。
						end
						8'h10:begin
							axi_rdata_o <= flag_cycle_snapshot ? reg_cycle_snapshot[63:32] : i_cycles[63:32]; // 有快照时禁止混入更新后的高位。
						end
						8'h14:begin
							axi_rdata_o <= {24'd0, i_current_layer}; // 层号按原八位零扩展。
						end
						8'h18:begin
							axi_rdata_o <= i_error_code; // 首诊断及控制器来源完整回读。
						end
						8'h1c:begin
							axi_rdata_o <= 32'h20261015; // 固定构建标识与交付日期一致。
						end
						8'h20:begin
							axi_rdata_o <= model_bytes_o; // 核对装载字节数配置。
						end
						default:begin
							axi_rresp_o <= 2'b11; // 未知地址返回DECERR且数据零。
						end
					endcase
				end
			end
		end
	end

endmodule
