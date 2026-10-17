`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/08 10:30:02
// Design Name:     concat_group
// Module Name:     concat_group
// Description:     description/concat_group_Design.pdf
// Simulations:     testbench/vivado/2021.1/concat_group
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/08 10:30:02
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Erie              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月08日
// 设计名称:        concat_group
// 模块名称:        concat_group
// 模块说明:        Description/concat_group_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/concat_group
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月08日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月08日   V1.0        Erie              创建文件

module concat_group
(
	//-----------------用户接口-----------------//
	input [17:0]i_selection,                    // 九个二bit路由，10空间、11旁路、00屏蔽。
	input [431:0]i_spatial,                     // 本组九份空间点结果。
	input [143:0]i_one,                         // 第一列K0与K3和K6。
	input [143:0]i_two,                         // 中间列K1及K4和K7。
	input [143:0]i_three,                       // 右列K2与K5和K8。
	output [431:0]o_data,                       // 九lane按K0至K8固定排列。
	output [8:0]o_mask                          // 路由最高位表示启用资格。
);

	//----------------寄存器信号----------------//
	reg [47:0]reg_lane_first = 48'd0;           // 左上核的组合中间结果。
	reg [47:0]reg_lane_second = 48'd0;          // 顶边中点的组合中间结果。
	reg [47:0]reg_lane_third = 48'd0;           // 右上角的组合中间结果。
	reg [47:0]reg_lane_fourth = 48'd0;          // 左侧中行的组合中间结果。
	reg [47:0]reg_lane_fifth = 48'd0;           // 卷积中心的组合中间结果。
	reg [47:0]reg_lane_sixth = 48'd0;           // 中排末端的组合中间结果。
	reg [47:0]reg_lane_seventh = 48'd0;         // 底行起点的组合中间结果。
	reg [47:0]reg_lane_eighth = 48'd0;          // 下边中央的组合中间结果。
	reg [47:0]reg_lane_ninth = 48'd0;           // 右下收尾的组合中间结果。

	//-----------------其他信号-----------------//
	//组合选择控制
	wire [17:0]wire_selection;                  // 原样保留组内二bit类别字段。

	//-----------------输出信号-----------------//
	//用户接口
	wire [431:0]data_o;                         // 九份无额外时钟延迟的选择结果。
	wire [8:0]mask_o;                           // 每lane与点积共享有效路由。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign wire_selection = i_selection;        // 任务固定配置直接提供选择控制。
	assign data_o[47:0] = reg_lane_first;       // 左上核补码结果送往固定lane。
	assign mask_o[0] = wire_selection[1];       // 左上核许可取所属路由高位。
	assign data_o[95:48] = reg_lane_second;     // 顶边中点补码结果送往固定lane。
	assign mask_o[1] = wire_selection[3];       // 顶边中点许可取所属路由高位。
	assign data_o[143:96] = reg_lane_third;     // 右上角补码结果送往固定lane。
	assign mask_o[2] = wire_selection[5];       // 右上角许可取所属路由高位。
	assign data_o[191:144] = reg_lane_fourth;   // 左侧中行补码结果送往固定lane。
	assign mask_o[3] = wire_selection[7];       // 左侧中行许可取所属路由高位。
	assign data_o[239:192] = reg_lane_fifth;    // 卷积中心补码结果送往固定lane。
	assign mask_o[4] = wire_selection[9];       // 卷积中心许可取所属路由高位。
	assign data_o[287:240] = reg_lane_sixth;    // 中排末端补码结果送往固定lane。
	assign mask_o[5] = wire_selection[11];      // 中排末端许可取所属路由高位。
	assign data_o[335:288] = reg_lane_seventh;  // 底行起点补码结果送往固定lane。
	assign mask_o[6] = wire_selection[13];      // 底行起点许可取所属路由高位。
	assign data_o[383:336] = reg_lane_eighth;   // 下边中央补码结果送往固定lane。
	assign mask_o[7] = wire_selection[15];      // 下边中央许可取所属路由高位。
	assign data_o[431:384] = reg_lane_ninth;    // 右下收尾补码结果送往固定lane。
	assign mask_o[8] = wire_selection[17];      // 右下收尾许可取所属路由高位。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_data[47:0] = data_o[47:0];         // 左上核输出桥不跨越时钟。
	assign o_data[95:48] = data_o[95:48];       // 顶边中点输出桥不跨越时钟。
	assign o_data[143:96] = data_o[143:96];     // 右上角输出桥不跨越时钟。
	assign o_data[191:144] = data_o[191:144];   // 左侧中行输出桥不跨越时钟。
	assign o_data[239:192] = data_o[239:192];   // 卷积中心输出桥不跨越时钟。
	assign o_data[287:240] = data_o[287:240];   // 中排末端输出桥不跨越时钟。
	assign o_data[335:288] = data_o[335:288];   // 底行起点输出桥不跨越时钟。
	assign o_data[383:336] = data_o[383:336];   // 下边中央输出桥不跨越时钟。
	assign o_data[431:384] = data_o[431:384];   // 右下收尾输出桥不跨越时钟。
	assign o_mask[0] = mask_o[0];               // 左上核资格随数据一并可见。
	assign o_mask[1] = mask_o[1];               // 顶边中点资格随数据一并可见。
	assign o_mask[2] = mask_o[2];               // 右上角资格随数据一并可见。
	assign o_mask[3] = mask_o[3];               // 左侧中行资格随数据一并可见。
	assign o_mask[4] = mask_o[4];               // 卷积中心资格随数据一并可见。
	assign o_mask[5] = mask_o[5];               // 中排末端资格随数据一并可见。
	assign o_mask[6] = mask_o[6];               // 底行起点资格随数据一并可见。
	assign o_mask[7] = mask_o[7];               // 下边中央资格随数据一并可见。
	assign o_mask[8] = mask_o[8];               // 右下收尾资格随数据一并可见。

	//-------------主要任务处理区域-------------//
	// 左上核在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[1:0])
			2'b10:begin
				reg_lane_first = i_spatial[47:0]; // 左上核空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_first = i_one[47:0];   // 左上核独立核按原序恢复。
			end
			default:begin
				reg_lane_first = 48'd0;         // 左上核未启用时严格清零。
			end
		endcase
	end

	// 顶边中点在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[3:2])
			2'b10:begin
				reg_lane_second = i_spatial[95:48]; // 顶边中点空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_second = i_two[47:0];  // 顶边中点独立核按原序恢复。
			end
			default:begin
				reg_lane_second = 48'd0;        // 顶边中点未启用时严格清零。
			end
		endcase
	end

	// 右上角在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[5:4])
			2'b10:begin
				reg_lane_third = i_spatial[143:96]; // 右上角空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_third = i_three[47:0]; // 右上角独立核按原序恢复。
			end
			default:begin
				reg_lane_third = 48'd0;         // 右上角未启用时严格清零。
			end
		endcase
	end

	// 左侧中行在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[7:6])
			2'b10:begin
				reg_lane_fourth = i_spatial[191:144]; // 左侧中行空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_fourth = i_one[95:48]; // 左侧中行独立核按原序恢复。
			end
			default:begin
				reg_lane_fourth = 48'd0;        // 左侧中行未启用时严格清零。
			end
		endcase
	end

	// 卷积中心在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[9:8])
			2'b10:begin
				reg_lane_fifth = i_spatial[239:192]; // 卷积中心空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_fifth = i_two[95:48];  // 卷积中心独立核按原序恢复。
			end
			default:begin
				reg_lane_fifth = 48'd0;         // 卷积中心未启用时严格清零。
			end
		endcase
	end

	// 中排末端在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[11:10])
			2'b10:begin
				reg_lane_sixth = i_spatial[287:240]; // 中排末端空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_sixth = i_three[95:48]; // 中排末端独立核按原序恢复。
			end
			default:begin
				reg_lane_sixth = 48'd0;         // 中排末端未启用时严格清零。
			end
		endcase
	end

	// 底行起点在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[13:12])
			2'b10:begin
				reg_lane_seventh = i_spatial[335:288]; // 底行起点空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_seventh = i_one[143:96]; // 底行起点独立核按原序恢复。
			end
			default:begin
				reg_lane_seventh = 48'd0;       // 底行起点未启用时严格清零。
			end
		endcase
	end

	// 下边中央在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[15:14])
			2'b10:begin
				reg_lane_eighth = i_spatial[383:336]; // 下边中央空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_eighth = i_two[143:96]; // 下边中央独立核按原序恢复。
			end
			default:begin
				reg_lane_eighth = 48'd0;        // 下边中央未启用时严格清零。
			end
		endcase
	end

	// 右下收尾在空间值与对应核之间选择。
	always@(*)begin
		case(wire_selection[17:16])
			2'b10:begin
				reg_lane_ninth = i_spatial[431:384]; // 右下收尾空间点直接使用本组输入。
			end
			2'b11:begin
				reg_lane_ninth = i_three[143:96]; // 右下收尾独立核按原序恢复。
			end
			default:begin
				reg_lane_ninth = 48'd0;         // 右下收尾未启用时严格清零。
			end
		endcase
	end

endmodule
