`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Codex
//
// Create Date:     2026/10/08 00:00:00
// Design Name:     result_packer
// Module Name:     result_packer
// Description:     description/result_packer_Design.pdf
// Simulations:     testbench/vivado/2021.1/result_packer
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/result_packer_spec.md; docs/设计文档.md 4.11
//
// Dependencies:
// Module Name      Version
// tile_psum_buffer -
// result_stage     -
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
// 设计名称:        result_packer
// 模块名称:        result_packer
// 模块说明:        Description/result_packer_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/result_packer
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/result_packer_spec.md; docs/设计文档.md 4.11
//
// 依赖文件:
// 模块名称         版本
// tile_psum_buffer -
// result_stage     -
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Codex             统一既有阶段B代码风格

module result_packer
(
	//-----------------全局信号-----------------//
	input i_clk,                                // bundle、部分和缓存与量化共用时钟。
	input i_rstn,                               // 低有效异步复位，上游统一同步释放。

	//-----------------用户接口-----------------//
	input i_bundle_valid,                       // 一个完整72-lane点积bundle有效。
	output o_bundle_ready,                      // 空闲且配置合法时接受整个bundle。
	input [3455:0]i_bundle_data,                // CU-major低到高72项signed48完整点积。
	input [3455:0]i_bias_data,                  // 与bundle lane相同顺序的48位偏置。
	input [71:0]i_lane_mask,                    // 非空低位连续前缀，空间模式仅允许低8位。
	input [1:0]i_mode,                          // 高位区分空间卷积与独立lane结果路由。
	input [7:0]i_spatial_index,                 // 多tile空间位置须小于196。
	input i_first_tile,                         // 当前输出组的首输入tile，覆盖旧部分和。
	input i_last_tile,                          // 末输入tile才允许量化完整点积。
	input [5:0]i_right_shift,                   // 本bundle的加半舍入右移位数。
	input i_relu,                               // 本bundle量化后的ReLU开关。
	output o_out_valid,                         // 四lane INT16结果已就绪。
	input i_out_ready,                          // 下游允许消费当前四lane结果。
	output [63:0]o_out_data,                    // 低lane在低位的四项INT16结果。
	output [3:0]o_out_mask,                     // 输出四lane参与位，尾项可不足四路。
	output o_out_bypass,                        // 已锁存任务路由供双FIFO选择。
	output o_busy                               // 已锁存bundle或量化在途项尚未排空。
);

	//--------------模块实例化信号--------------//
	//部分和缓存与量化级连接
	wire [191:0]response_data;                  // 部分和缓存返回的四项signed48。
	wire [191:0]stage_data;                     // 直通bundle或RAM完整和送量化准备级。
	wire [12:0]ingress_address;                 // 当前空间基址加四lane字号。
	wire [191:0]ingress_data;                   // 待提交RAM的最低四项原始tile贡献。
	wire [191:0]stage_bias;                     // 与当前quad对齐的四项48位偏置。

	//-----------------计数信号-----------------//
	reg [4:0]cnt_quad;                          // 当前四lane字号，满72组遍历18字。

	//----------------寄存器信号----------------//
	reg [3455:0]reg_data;                       // 已接受bundle按四lane逐字右移。
	reg [3455:0]reg_bias;                       // 私有偏置与数据同步移位，避免lane错配。
	reg [71:0]reg_mask;                         // 剩余有效lane前缀用于确定末quad。
	reg [12:0]reg_base_address;                 // 固定空间位置乘27的部分和字基址。
	reg [5:0]reg_shift;                         // 锁存本bundle的右移配置。

	//-----------------标志信号-----------------//
	reg flag_active;                            // bundle已接受，尚有quad等待处理。
	reg flag_waiting;                           // 已发出一个RAM请求，等待响应消费。
	reg flag_first;                             // 首tile配置在整个bundle内保持。
	reg flag_last;                              // 末tile资格决定是否进入量化级。
	reg flag_relu;                              // 激活开关在bundle接受沿锁存。
	wire flag_direct;                           // 首tile且末tile直接量化，不访问部分和RAM。
	wire flag_request_valid;                    // 非直通且没有在途请求时发出当前quad。
	wire flag_request_ready;                    // 部分和缓存接受请求的许可。
	wire flag_response_valid;                   // 缓存的四lane完整和响应资格。
	wire flag_response_ready;                   // 非末tile直接消费，末tile等待量化空槽。
	wire flag_step;                             // 当前quad已交付量化或完成非末tile写回。
	wire [3:0]flag_quad_mask;                   // 当前最低四lane对应的参与位。
	wire flag_quantize_valid;                   // 仅末tile的直通或RAM响应允许量化。
	wire flag_quantize_ready;                   // 弹性准备寄存允许接收新四lane项。

	//-----------------其他信号-----------------//
	//固定空间字地址扩展
	wire [12:0]spatial_address;                 // 空间位置补零扩到固定地址宽度。

	//-----------------输出信号-----------------//
	//用户接口
	wire bundle_ready_o;                        // bundle入口许可由空闲和合法配置决定。
	wire out_valid_o;                           // 量化末级有效标签，排空前继续占用本bundle。
	wire [63:0]out_data_o;                      // 完整量化结果从子模块整端口接入。
	wire [3:0]out_mask_o;                       // 量化输出mask与四项结果一同转发。
	reg out_bypass_o;                           // 本bundle路由在busy期间固定。
	wire busy_o;                                // bundle和量化在途资格合并的忙状态。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign spatial_address = {5'd0,i_spatial_index}; // 空间编号补零供13位地址加法使用。
	assign ingress_address = reg_base_address+{8'd0,cnt_quad}; // 每个quad按线性字址访问独占空间槽。
	assign ingress_data = reg_data[191:0];      // RAM请求只取尚未移出的最低四lane。
	assign stage_bias = reg_bias[191:0];        // 偏置与最低四项点积保持同序。
	assign flag_quad_mask = reg_mask[3:0];      // 参与位随数据移位后取最低四位。
	assign flag_direct = flag_first && flag_last; // 单tile路径绕过缓存读改写等待。
	assign flag_request_valid = flag_active && !flag_direct && !flag_waiting; // 每次仅允许一个未完成RAM quad。
	assign flag_response_ready = flag_active && flag_waiting && (!flag_last || flag_quantize_ready); // 末tile响应需量化许可，其他tile只完成部分和。
	assign flag_quantize_valid = flag_active && flag_last && (flag_direct || (flag_waiting && flag_response_valid)); // 首末同tile直接量化，否则等待有效RAM响应。
	assign stage_data = flag_direct ? reg_data[191:0] : response_data; // 两条互斥路径共享同一个四lane量化级。
	assign flag_step = (flag_quantize_valid && flag_quantize_ready) || (!flag_last && flag_waiting && flag_response_valid); // 仅真正消费当前quad时移动bundle游标。

	assign bundle_ready_o = i_rstn && !flag_active && !out_valid_o && (|i_lane_mask) && (i_mode[1] || i_lane_mask[71:8]==64'd0) && ((i_first_tile && i_last_tile) || i_spatial_index<8'd196); // 非空lane、空间范围与空闲条件均满足才允许锁存。
	assign busy_o = flag_active || out_valid_o; // 最后quad已提交时仍等待量化输出排空。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_bundle_ready = bundle_ready_o;     // 全bundle只在入口握手时锁存一次。
	assign o_out_valid = out_valid_o;           // 输出资格直接转发弹性量化项。
	assign o_out_data = out_data_o;             // 四项INT16保持量化子模块输出次序。
	assign o_out_mask = out_mask_o;             // 尾组lane资格与数据共同输出。
	assign o_out_bypass = out_bypass_o;         // 在途模式仅使用接受沿锁存的路由。
	assign o_busy = busy_o;                     // 下游排空前保持忙状态。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 一个bundle占用全部quad处理期间；保持原有多个if的执行与赋值优先级。
	always@(posedge i_clk or negedge i_rstn)begin
		if(!i_rstn)begin
			flag_active <= 1'b0;                // 取消尚未排空的bundle处理状态。
			flag_waiting <= 1'b0;               // 取消未消费的RAM请求资格。
			reg_data <= 3456'd0;                // 旧bundle全部点积立即作废。
			reg_bias <= 3456'd0;                // 旧组偏置不再参与恢复任务。
			reg_mask <= 72'd0;                  // 清除剩余lane参与前缀。
			reg_base_address <= 13'd0;          // 清除旧空间部分和基址。
			cnt_quad <= 5'd0;                   // 四lane游标回到组内首字。
			flag_first <= 1'b0;                 // 撤销旧首tile覆盖属性。
			flag_last <= 1'b0;                  // 撤销旧末tile量化资格。
			out_bypass_o <= 1'b0;               // 路由恢复空间默认值。
			flag_relu <= 1'b0;                  // 清除组内激活配置。
			reg_shift <= 6'd0;                  // 量化右移配置复位。
		end else begin
			if(i_bundle_valid && o_bundle_ready)begin
				flag_active <= 1'b1;            // 接受整个bundle并独占当前处理上下文。
				flag_waiting <= 1'b0;           // 新bundle起始没有在途RAM请求。
				reg_data <= i_bundle_data;      // 输入点积一次锁存，后续输入变化无效。
				reg_bias <= i_bias_data;        // 当前输出组的完整私有偏置一同锁存。
				reg_mask <= i_lane_mask;        // 有效前缀决定组内输出字数量。
				reg_base_address <= (spatial_address<<4)+(spatial_address<<3)+(spatial_address<<1)+spatial_address; // 固定移位加法计算空间位置乘27。
				cnt_quad <= 5'd0;               // 首quad从最低四lane开始。
				flag_first <= i_first_tile;     // 首tile属性在组内所有quad共享。
				flag_last <= i_last_tile;       // 末tile属性决定完整和后处理。
				out_bypass_o <= i_mode[1];      // 输入模式高位锁存为空间或旁路路由。
				flag_relu <= i_relu;            // 本组激活配置保持到全部结果排空。
				reg_shift <= i_right_shift;     // 接受沿保存本组量化位数。
			end
			if(flag_request_valid && flag_request_ready)begin
				flag_waiting <= 1'b1;           // RAM请求接受后禁止重复发送同一quad。
			end
			if(flag_step)begin
				flag_waiting <= 1'b0;           // 当前quad响应消费后释放请求槽。
				cnt_quad <= cnt_quad+1'b1;      // 四lane字号仅在真实消费后递增。
				reg_data <= reg_data>>192;      // 移出已处理的四项48位点积。
				reg_bias <= reg_bias>>192;      // 偏置移位与点积游标同步。
				reg_mask <= reg_mask>>4;        // 已消费四lane参与位移出前缀。
				if(reg_mask[71:4]==68'd0)begin
					flag_active <= 1'b0;        // 当前quad为末项，量化在途仍由busy保护。
				end
			end
		end
	end

	//--------------模块实例化区域--------------//
	// 固定部分和缓存保持48位完整和，首tile覆盖且末tile不写回。
	tile_psum_buffer tile_psum_buffer_Inst(     // 跨tile完整部分和的同步缓存实例。
		.i_clk(i_clk),                          // 部分和RAM在请求接受沿采样。
		.i_rstn(i_rstn),                        // 清除缓存响应资格，保留RAM历史值。
		.i_in_valid(flag_request_valid),        // 请求标志约束缓存每次只接收一个quad。
		.o_in_ready(flag_request_ready),        // 同步读写槽可用时反馈请求许可。
		.i_address(ingress_address),            // 提供空间基址加当前quad字号。
		.i_in_data(ingress_data),               // 提交最低四项原始tile贡献。
		.i_in_mask(flag_quad_mask),             // 四lane参与位与当前请求同序。
		.i_first_tile(flag_first),              // 首tile覆盖历史缓存字。
		.i_last_tile(flag_last),                // 末tile只返回完整和，不写回量化值。
		.o_out_valid(flag_response_valid),      // 部分和完成事件通知packer推进。
		.i_out_ready(flag_response_ready),      // 响应端根据是否末tile选择消费许可。
		.o_out_data(response_data)              // 完整四项48位响应送后处理。
	);

	// 四lane共享弹性量化寄存，偏置仅在末tile完整和之后加入。
	result_stage result_stage_Inst(             // 末tile四lane舍入饱和与激活实例。
		.i_clk(i_clk),                          // 量化准备寄存由同一时钟捕获。
		.i_rstn(i_rstn),                        // 取消在途控制，上游负责同步释放。
		.i_in_valid(flag_quantize_valid),       // 当前四lane请求具备完整有效资格。
		.o_in_ready(flag_quantize_ready),       // 返回当前子模块接受许可。
		.i_sum_data(stage_data),                // 直通或缓存返回的完整跨tile和。
		.i_bias_data(stage_bias),               // 点积对应的四项系数在量化准备沿加入。
		.i_lane_mask(flag_quad_mask),           // 尾quad的参与位随准备数据锁存。
		.i_right_shift(reg_shift),              // 使用bundle接受沿锁存的右移配置。
		.i_relu(flag_relu),                     // 使用组内保持不变的激活开关。
		.o_result_data(out_data_o),             // 四个INT16结果完整端口连接。
		.o_out_valid(out_valid_o),              // 返回与子模块响应对应的资格。
		.i_out_ready(i_out_ready),              // 下游许可控制子模块弹性推进。
		.o_out_mask(out_mask_o)                 // 量化结果对应的四lane参与标签。
	);

endmodule
