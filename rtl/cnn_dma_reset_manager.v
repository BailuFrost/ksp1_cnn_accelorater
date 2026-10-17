`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/14 00:00:00
// Design Name:     cnn_dma_reset_manager
// Module Name:     cnn_dma_reset_manager
// Description:     description/cnn_dma_reset_manager_Design.pdf
// Simulations:     testbench/vivado/2021.1/cnn_dma_reset_manager
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/cnn_dma_reset_manager_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/14 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/14       V1.0        Codex             Create cnn_dma_reset_manager production integration.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月14日
// 设计名称:        cnn_dma_reset_manager
// 模块名称:        cnn_dma_reset_manager
// 模块说明:        Description/cnn_dma_reset_manager_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/cnn_dma_reset_manager
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/cnn_dma_reset_manager_spec.md; docs/设计文档.md 4.2、4.9、4.10
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月14日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月14日   V1.0        Codex             创建真实搬运器取消边界

module cnn_dma_reset_manager
(
	//-----------------用户接口-----------------//
	input i_clk,                                // FCLK统一采样时钟。
	input i_rstn,                               // 全局低有效复位，上游同步释放。
	input i_request,                            // 本组取消请求，允许保持至收到应答。
	input [2:0]i_halted,                        // 本组全部方向的真实halt向量，GP未用高位置一。
	output o_halt,                              // 要求本组停止新地址并完成已提交事务。
	output o_dma_rstn,                          // 仅halt全部完成后断言四拍局部复位。
	output o_enabled,                           // 正常任务流资格，取消立即撤销。
	output o_done                               // 当前取消已完成，保持至请求撤销。
);

	//---------------状态参数区域---------------//
	localparam [2:0]ST_HALT = 3'd0;             // 等待本组全部AXI主设备停止。
	localparam [2:0]ST_RESET = 3'd1;            // 已静止引擎保持局部低有效复位。
	localparam [2:0]ST_GUARD = 3'd2;            // 释放后等待IP接口恢复。
	localparam [2:0]ST_ACK = 3'd3;              // 保留本轮应答等待请求撤销。
	localparam [2:0]ST_READY = 3'd4;            // 接受下一次独立取消请求。

	//-----------------计数信号-----------------//
	reg [3:0]cnt_wait = 0;                      // 四拍复位或十六拍恢复计数。

	//----------------状态机信号----------------//
	reg [2:0]state_current = 0;                 // 当前真实引擎取消阶段。
	reg [2:0]state_next = 0;                    // 下一拍取消阶段。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_halt = i_rstn && state_current == ST_HALT; // 全局复位期间不发软停机。
	assign o_dma_rstn = i_rstn && state_current != ST_RESET; // 共享互连始终不受此复位影响。
	assign o_enabled = i_rstn && !i_request && (state_current == ST_READY || state_current == ST_ACK); // 取消请求立即隔离流。
	assign o_done = i_rstn && (state_current == ST_ACK || (state_current == ST_READY && !i_request)); // 新请求不能沿用空闲旧应答。

	//----------------状态机区域----------------//
	// 每个组独立等待所有真实halt完成，允许取消中途撤销请求。
	always@(*)begin
		state_next = state_current;             // 无事件时保持当前取消阶段。
		case(state_current)

			// 已提交AXI事务必须由IP完成。
			ST_HALT:begin
				if(&i_halted)begin
					state_next = ST_RESET;      // 全部方向静止后才允许复位。
				end else begin
					state_next = ST_HALT;       // 保持互连工作，继续等待在途事务。
				end
			end

			// PG022要求至少三个周期，实际保留四个。
			ST_RESET:begin
				if(cnt_wait == 4'd3)begin
					state_next = ST_GUARD;      // 同域时钟边沿释放局部复位。
				end else begin
					state_next = ST_RESET;      // 延长本组引擎复位断言。
				end
			end

			// 保护时间固定但取消完成依赖真实halt响应。
			ST_GUARD:begin
				if(cnt_wait == 4'd15)begin
					state_next = ST_ACK;        // 对当前轮次给出持久完成应答。
				end else begin
					state_next = ST_GUARD;      // 等待内部IP复位释放资格稳定。
				end
			end

			// 长请求只执行一次halt/reset，避免应答振荡。
			ST_ACK:begin
				if(i_request == 1'b0)begin
					state_next = ST_READY;      // 观察低电平后才能开始下一轮。
				end else begin
					state_next = ST_ACK;        // 持续请求不重新触发局部复位。
				end
			end

			// 新请求立即撤销旧应答并在采样沿启动halt。
			ST_READY:begin
				if(i_request == 1'b1)begin
					state_next = ST_HALT;       // 将下一轮请求交给真实IP。
				end else begin
					state_next = ST_READY;      // 静止资格保持至下一轮取消。
				end
			end

			// 非法编码恢复至停止状态，禁止直接宣称完成。
			default:begin
				state_next = ST_HALT;           // 重新确认所有AXI通道静止。
			end
		endcase
	end

	// 在同域采样沿提交阶段，硬复位后从真实halt确认开始。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			state_current <= ST_HALT;           // 启动也必须完成真实取消握手。
		end else begin
			state_current <= state_next;        // 提交当前组取消阶段。
		end
	end

	//-------------状态任务处理区域-------------//
	// 只在固定复位和恢复阶段计时，halt等待不采用虚假超时。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			cnt_wait <= 4'd0;                   // 清除上次等待周期。
		end else if(state_current != state_next)begin
			cnt_wait <= 4'd0;                   // 阶段切换重新计时。
		end else if(state_current == ST_RESET || state_current == ST_GUARD)begin
			cnt_wait <= cnt_wait + 4'd1;        // 累计完整复位或恢复周期。
		end else begin
			cnt_wait <= 4'd0;                   // 空闲或halt期间无固定倒计时。
		end
	end

endmodule
