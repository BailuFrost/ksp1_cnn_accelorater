`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/08 10:30:01
// Design Name:     concat
// Module Name:     concat
// Description:     description/concat_Design.pdf
// Simulations:     testbench/vivado/2021.1/concat
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/08 10:30:01
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Erie              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月08日
// 设计名称:        concat
// 模块名称:        concat
// 模块说明:        Description/concat_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/concat
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

module concat
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 配置预译码共享阵列时钟。
	input i_rstn,                               // 异步清除全部lane选择，上游同步释放。

	//-----------------用户接口-----------------//
	input i_ce,                                 // 暂停时任务配置保持原值。
	input [1:0]i_mode,                          // 四模式在同一任务中固定。
	input [6:0]i_valid_lanes,                   // 空间合法1至8，旁路合法1至72。
	input [7:0]i_cu_valid,                      // 八份CU共同完成资格。
	input [383:0]i_zero,                        // 阵列所有空间48位点。
	input [1151:0]i_one,                        // 第一核列独立点积集合。
	input [1151:0]i_two,                        // 中央核列三lane输入。
	input [1151:0]i_three,                      // 末核列的补码打包结果。
	output o_bundle_valid,                      // 全部CU有效且任务至少启用一个lane。
	output [3455:0]o_bundle_data,               // CU-major K0至K8固定72个48位结果。
	output [71:0]o_lane_mask                    // lane资格按低位前缀输出。
);

	//----------------寄存器信号----------------//
	(* rom_style = "distributed" *) reg [143:0]reg_route = 144'd0; // 每lane00屏蔽、10空间、11旁路；首次恢复ce沿预译码。

	//-----------------其他信号-----------------//
	//配置索引
	wire [7:0]config_control;                   // 模式高位和lane数量的有限配置键。

	//-----------------输出信号-----------------//
	//用户接口
	wire bundle_valid_o;                        // 合法任务与共同结果资格的输出桥。
	wire [3455:0]bundle_data_o;                 // 八个九lane重排组聚合。
	wire [71:0]lane_mask_o;                     // 与结果来自同一任务选择寄存器。
	wire [431:0]group_first_spatial_o;          // 阵列起点空间点输入。
	wire [17:0]group_first_route_o;             // 阵列起点预译码选择。
	wire [431:0]group_first_data_o;             // 阵列起点九lane结果。
	wire [8:0]group_first_mask_o;               // 阵列起点尾组许可。
	wire [431:0]group_second_spatial_o;         // 次序靠前空间点输入。
	wire [17:0]group_second_route_o;            // 次序靠前预译码选择。
	wire [431:0]group_second_data_o;            // 次序靠前九lane结果。
	wire [8:0]group_second_mask_o;              // 次序靠前尾组许可。
	wire [431:0]group_third_spatial_o;          // 前三末端空间点输入。
	wire [17:0]group_third_route_o;             // 前三末端预译码选择。
	wire [431:0]group_third_data_o;             // 前三末端九lane结果。
	wire [8:0]group_third_mask_o;               // 前三末端尾组许可。
	wire [431:0]group_fourth_spatial_o;         // 第二组起点空间点输入。
	wire [17:0]group_fourth_route_o;            // 第二组起点预译码选择。
	wire [431:0]group_fourth_data_o;            // 第二组起点九lane结果。
	wire [8:0]group_fourth_mask_o;              // 第二组起点尾组许可。
	wire [431:0]group_fifth_spatial_o;          // 低半中央空间点输入。
	wire [17:0]group_fifth_route_o;             // 低半中央预译码选择。
	wire [431:0]group_fifth_data_o;             // 低半中央九lane结果。
	wire [8:0]group_fifth_mask_o;               // 低半中央尾组许可。
	wire [431:0]group_sixth_spatial_o;          // 左半末尾空间点输入。
	wire [17:0]group_sixth_route_o;             // 左半末尾预译码选择。
	wire [431:0]group_sixth_data_o;             // 左半末尾九lane结果。
	wire [8:0]group_sixth_mask_o;               // 左半末尾尾组许可。
	wire [431:0]group_seventh_spatial_o;        // 右半起始位置空间点输入。
	wire [17:0]group_seventh_route_o;           // 右半起始位置预译码选择。
	wire [431:0]group_seventh_data_o;           // 右半起始位置九lane结果。
	wire [8:0]group_seventh_mask_o;             // 右半起始位置尾组许可。
	wire [431:0]group_eighth_spatial_o;         // 高段中部空间点输入。
	wire [17:0]group_eighth_route_o;            // 高段中部预译码选择。
	wire [431:0]group_eighth_data_o;            // 高段中部九lane结果。
	wire [8:0]group_eighth_mask_o;              // 高段中部尾组许可。
	wire [143:0]group_first_one_o;              // 阵列起点首列独立核数据。
	wire [143:0]group_first_two_o;              // 阵列起点中心核列点积。
	wire [143:0]group_first_three_o;            // 阵列起点右列补码结果。
	wire [143:0]group_second_one_o;             // 次序靠前首列独立核数据。
	wire [143:0]group_second_two_o;             // 次序靠前中心核列点积。
	wire [143:0]group_second_three_o;           // 次序靠前右列补码结果。
	wire [143:0]group_third_one_o;              // 前三末端首列独立核数据。
	wire [143:0]group_third_two_o;              // 前三末端中心核列点积。
	wire [143:0]group_third_three_o;            // 前三末端右列补码结果。
	wire [143:0]group_fourth_one_o;             // 第二组三核入口首列独立核数据。
	wire [143:0]group_fourth_two_o;             // 第二组三核入口中心核列点积。
	wire [143:0]group_fourth_three_o;           // 第二组三核入口右列补码结果。
	wire [143:0]group_fifth_one_o;              // 低半中央首列独立核数据。
	wire [143:0]group_fifth_two_o;              // 低半中央中心核列点积。
	wire [143:0]group_fifth_three_o;            // 低半中央右列补码结果。
	wire [143:0]group_sixth_one_o;              // 左半末尾首列独立核数据。
	wire [143:0]group_sixth_two_o;              // 左半末尾中心核列点积。
	wire [143:0]group_sixth_three_o;            // 左半末尾右列补码结果。
	wire [143:0]group_seventh_one_o;            // 右半起始位置首列独立核数据。
	wire [143:0]group_seventh_two_o;            // 右半起始位置中心核列点积。
	wire [143:0]group_seventh_three_o;          // 右半起始位置右列补码结果。
	wire [143:0]group_eighth_one_o;             // 高段中部首列独立核数据。
	wire [143:0]group_eighth_two_o;             // 高段中部中心核列点积。
	wire [143:0]group_eighth_three_o;           // 高段中部右列补码结果。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign config_control = {i_mode[1], i_valid_lanes}; // 固定字段直接查表，不串接范围比较。
	assign bundle_valid_o = (&i_cu_valid) && (|reg_route); // 数量非法时所有选择零，禁止消费。
	assign group_first_spatial_o = {48'd0, i_zero}; // 阵列起点准备物理空间槽。
	assign group_first_route_o = reg_route[17:0]; // 阵列起点切出九份完整配置字段。
	assign bundle_data_o[431:0] = group_first_data_o; // 阵列起点连续写入九个结果位置。
	assign lane_mask_o[8:0] = group_first_mask_o; // 阵列起点资格放到相邻许可位。
	assign group_second_spatial_o = 432'd0;     // 次序靠前准备物理空间槽。
	assign group_second_route_o = reg_route[35:18]; // 次序靠前切出九份完整配置字段。
	assign bundle_data_o[863:432] = group_second_data_o; // 次序靠前连续写入九个结果位置。
	assign lane_mask_o[17:9] = group_second_mask_o; // 次序靠前资格放到相邻许可位。
	assign group_third_spatial_o = 432'd0;      // 前三末端准备物理空间槽。
	assign group_third_route_o = reg_route[53:36]; // 前三末端切出九份完整配置字段。
	assign bundle_data_o[1295:864] = group_third_data_o; // 前三末端连续写入九个结果位置。
	assign lane_mask_o[26:18] = group_third_mask_o; // 前三末端资格放到相邻许可位。
	assign group_fourth_spatial_o = 432'd0;     // 第二组起点准备物理空间槽。
	assign group_fourth_route_o = reg_route[71:54]; // 第二组起点切出九份完整配置字段。
	assign bundle_data_o[1727:1296] = group_fourth_data_o; // 第二组起点连续写入九个结果位置。
	assign lane_mask_o[35:27] = group_fourth_mask_o; // 第二组起点资格放到相邻许可位。
	assign group_fifth_spatial_o = 432'd0;      // 低半中央准备物理空间槽。
	assign group_fifth_route_o = reg_route[89:72]; // 低半中央切出九份完整配置字段。
	assign bundle_data_o[2159:1728] = group_fifth_data_o; // 低半中央连续写入九个结果位置。
	assign lane_mask_o[44:36] = group_fifth_mask_o; // 低半中央资格放到相邻许可位。
	assign group_sixth_spatial_o = 432'd0;      // 左半末尾准备物理空间槽。
	assign group_sixth_route_o = reg_route[107:90]; // 左半末尾切出九份完整配置字段。
	assign bundle_data_o[2591:2160] = group_sixth_data_o; // 左半末尾连续写入九个结果位置。
	assign lane_mask_o[53:45] = group_sixth_mask_o; // 左半末尾资格放到相邻许可位。
	assign group_seventh_spatial_o = 432'd0;    // 右半起始位置准备物理空间槽。
	assign group_seventh_route_o = reg_route[125:108]; // 右半起始位置切出九份完整配置字段。
	assign bundle_data_o[3023:2592] = group_seventh_data_o; // 右半起始位置连续写入九个结果位置。
	assign lane_mask_o[62:54] = group_seventh_mask_o; // 右半起始位置资格放到相邻许可位。
	assign group_eighth_spatial_o = 432'd0;     // 高段中部准备物理空间槽。
	assign group_eighth_route_o = reg_route[143:126]; // 高段中部切出九份完整配置字段。
	assign bundle_data_o[3455:3024] = group_eighth_data_o; // 高段中部连续写入九个结果位置。
	assign lane_mask_o[71:63] = group_eighth_mask_o; // 高段中部资格放到相邻许可位。
	assign group_first_one_o = i_one[143:0];    // 阵列起点提取K0与K3和K6。
	assign group_first_two_o = i_two[143:0];    // 阵列起点连接K1及K4和K7。
	assign group_first_three_o = i_three[143:0]; // 阵列起点接入K2与K5和K8。
	assign group_second_one_o = i_one[287:144]; // 次序靠前提取K0与K3和K6。
	assign group_second_two_o = i_two[287:144]; // 次序靠前连接K1及K4和K7。
	assign group_second_three_o = i_three[287:144]; // 次序靠前接入K2与K5和K8。
	assign group_third_one_o = i_one[431:288];  // 前三末端提取K0与K3和K6。
	assign group_third_two_o = i_two[431:288];  // 前三末端连接K1及K4和K7。
	assign group_third_three_o = i_three[431:288]; // 前三末端接入K2与K5和K8。
	assign group_fourth_one_o = i_one[575:432]; // 第二组三核入口提取K0与K3和K6。
	assign group_fourth_two_o = i_two[575:432]; // 第二组三核入口连接K1及K4和K7。
	assign group_fourth_three_o = i_three[575:432]; // 第二组三核入口接入K2与K5和K8。
	assign group_fifth_one_o = i_one[719:576];  // 低半中央提取K0与K3和K6。
	assign group_fifth_two_o = i_two[719:576];  // 低半中央连接K1及K4和K7。
	assign group_fifth_three_o = i_three[719:576]; // 低半中央接入K2与K5和K8。
	assign group_sixth_one_o = i_one[863:720];  // 左半末尾提取K0与K3和K6。
	assign group_sixth_two_o = i_two[863:720];  // 左半末尾连接K1及K4和K7。
	assign group_sixth_three_o = i_three[863:720]; // 左半末尾接入K2与K5和K8。
	assign group_seventh_one_o = i_one[1007:864]; // 右半起始位置提取K0与K3和K6。
	assign group_seventh_two_o = i_two[1007:864]; // 右半起始位置连接K1及K4和K7。
	assign group_seventh_three_o = i_three[1007:864]; // 右半起始位置接入K2与K5和K8。
	assign group_eighth_one_o = i_one[1151:1008]; // 高段中部提取K0与K3和K6。
	assign group_eighth_two_o = i_two[1151:1008]; // 高段中部连接K1及K4和K7。
	assign group_eighth_three_o = i_three[1151:1008]; // 高段中部接入K2与K5和K8。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_bundle_valid = bundle_valid_o;     // 配置建立早于最早的CU有效结果。
	assign o_bundle_data = bundle_data_o;       // 结果保持与CU同拍，无数据寄存级。
	assign o_lane_mask = lane_mask_o;           // 尾组许可与数据选择一致。

	//-------------主要任务处理区域-------------//
	// 首个恢复使能沿译码任务，复位立即撤销旧任务全部lane。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_route <= 144'd0;                // 非沿清除模式及尾组资格。
		end else if(i_ce == 1'b1)begin
			case(config_control)
				8'd1:begin
					reg_route <= 144'h000000000000000000000000000000000002; // 前一核空间。
				end
				8'd2:begin
					reg_route <= 144'h00000000000000000000000000000000000a; // 前二核空间。
				end
				8'd3:begin
					reg_route <= 144'h00000000000000000000000000000000002a; // 前三核空间。
				end
				8'd4:begin
					reg_route <= 144'h0000000000000000000000000000000000aa; // 前四核空间。
				end
				8'd5:begin
					reg_route <= 144'h0000000000000000000000000000000002aa; // 前五核空间。
				end
				8'd6:begin
					reg_route <= 144'h000000000000000000000000000000000aaa; // 前六核空间。
				end
				8'd7:begin
					reg_route <= 144'h000000000000000000000000000000002aaa; // 前七核空间。
				end
				8'd8:begin
					reg_route <= 144'h00000000000000000000000000000000aaaa; // 前八核空间。
				end




				8'd129:begin
					reg_route <= 144'h000000000000000000000000000000000003; // 前一项旁路。
				end
				8'd130:begin
					reg_route <= 144'h00000000000000000000000000000000000f; // 前二项旁路。
				end
				8'd131:begin
					reg_route <= 144'h00000000000000000000000000000000003f; // 前三项旁路。
				end
				8'd132:begin
					reg_route <= 144'h0000000000000000000000000000000000ff; // 前四项旁路。
				end
				8'd133:begin
					reg_route <= 144'h0000000000000000000000000000000003ff; // 前五项旁路。
				end
				8'd134:begin
					reg_route <= 144'h000000000000000000000000000000000fff; // 前六项旁路。
				end
				8'd135:begin
					reg_route <= 144'h000000000000000000000000000000003fff; // 前七项旁路。
				end
				8'd136:begin
					reg_route <= 144'h00000000000000000000000000000000ffff; // 前八项旁路。
				end
				8'd137:begin
					reg_route <= 144'h00000000000000000000000000000003ffff; // 前九项旁路。
				end
				8'd138:begin
					reg_route <= 144'h0000000000000000000000000000000fffff; // 前十项旁路。
				end
				8'd139:begin
					reg_route <= 144'h0000000000000000000000000000003fffff; // 前十一项旁路。
				end
				8'd140:begin
					reg_route <= 144'h000000000000000000000000000000ffffff; // 前十二项旁路。
				end
				8'd141:begin
					reg_route <= 144'h000000000000000000000000000003ffffff; // 前十三项旁路。
				end
				8'd142:begin
					reg_route <= 144'h00000000000000000000000000000fffffff; // 前十四项旁路。
				end
				8'd143:begin
					reg_route <= 144'h00000000000000000000000000003fffffff; // 前十五项旁路。
				end
				8'd144:begin
					reg_route <= 144'h0000000000000000000000000000ffffffff; // 前十六项旁路。
				end
				8'd145:begin
					reg_route <= 144'h0000000000000000000000000003ffffffff; // 前十七项旁路。
				end
				8'd146:begin
					reg_route <= 144'h000000000000000000000000000fffffffff; // 前十八项旁路。
				end
				8'd147:begin
					reg_route <= 144'h000000000000000000000000003fffffffff; // 前十九项旁路。
				end
				8'd148:begin
					reg_route <= 144'h00000000000000000000000000ffffffffff; // 前二十项旁路。
				end
				8'd149:begin
					reg_route <= 144'h00000000000000000000000003ffffffffff; // 前二十一项旁路。
				end
				8'd150:begin
					reg_route <= 144'h0000000000000000000000000fffffffffff; // 前二十二项旁路。
				end
				8'd151:begin
					reg_route <= 144'h0000000000000000000000003fffffffffff; // 前二十三项旁路。
				end
				8'd152:begin
					reg_route <= 144'h000000000000000000000000ffffffffffff; // 前二十四项旁路。
				end
				8'd153:begin
					reg_route <= 144'h000000000000000000000003ffffffffffff; // 前二十五项旁路。
				end
				8'd154:begin
					reg_route <= 144'h00000000000000000000000fffffffffffff; // 前二十六项旁路。
				end
				8'd155:begin
					reg_route <= 144'h00000000000000000000003fffffffffffff; // 前二十七项旁路。
				end
				8'd156:begin
					reg_route <= 144'h0000000000000000000000ffffffffffffff; // 前二十八项旁路。
				end
				8'd157:begin
					reg_route <= 144'h0000000000000000000003ffffffffffffff; // 前二十九项旁路。
				end
				8'd158:begin
					reg_route <= 144'h000000000000000000000fffffffffffffff; // 前三十项旁路。
				end
				8'd159:begin
					reg_route <= 144'h000000000000000000003fffffffffffffff; // 前三十一项旁路。
				end
				8'd160:begin
					reg_route <= 144'h00000000000000000000ffffffffffffffff; // 前三十二项旁路。
				end
				8'd161:begin
					reg_route <= 144'h00000000000000000003ffffffffffffffff; // 前三十三项旁路。
				end
				8'd162:begin
					reg_route <= 144'h0000000000000000000fffffffffffffffff; // 前三十四项旁路。
				end
				8'd163:begin
					reg_route <= 144'h0000000000000000003fffffffffffffffff; // 前三十五项旁路。
				end
				8'd164:begin
					reg_route <= 144'h000000000000000000ffffffffffffffffff; // 前三十六项旁路。
				end
				8'd165:begin
					reg_route <= 144'h000000000000000003ffffffffffffffffff; // 前三十七项旁路。
				end
				8'd166:begin
					reg_route <= 144'h00000000000000000fffffffffffffffffff; // 前三十八项旁路。
				end
				8'd167:begin
					reg_route <= 144'h00000000000000003fffffffffffffffffff; // 前三十九项旁路。
				end
				8'd168:begin
					reg_route <= 144'h0000000000000000ffffffffffffffffffff; // 前四十项旁路。
				end
				8'd169:begin
					reg_route <= 144'h0000000000000003ffffffffffffffffffff; // 前四十一项旁路。
				end
				8'd170:begin
					reg_route <= 144'h000000000000000fffffffffffffffffffff; // 前四十二项旁路。
				end
				8'd171:begin
					reg_route <= 144'h000000000000003fffffffffffffffffffff; // 前四十三项旁路。
				end
				8'd172:begin
					reg_route <= 144'h00000000000000ffffffffffffffffffffff; // 前四十四项旁路。
				end
				8'd173:begin
					reg_route <= 144'h00000000000003ffffffffffffffffffffff; // 前四十五项旁路。
				end
				8'd174:begin
					reg_route <= 144'h0000000000000fffffffffffffffffffffff; // 前四十六项旁路。
				end
				8'd175:begin
					reg_route <= 144'h0000000000003fffffffffffffffffffffff; // 前四十七项旁路。
				end
				8'd176:begin
					reg_route <= 144'h000000000000ffffffffffffffffffffffff; // 前四十八项旁路。
				end
				8'd177:begin
					reg_route <= 144'h000000000003ffffffffffffffffffffffff; // 前四十九项旁路。
				end
				8'd178:begin
					reg_route <= 144'h00000000000fffffffffffffffffffffffff; // 前五十项旁路。
				end
				8'd179:begin
					reg_route <= 144'h00000000003fffffffffffffffffffffffff; // 前五十一项旁路。
				end
				8'd180:begin
					reg_route <= 144'h0000000000ffffffffffffffffffffffffff; // 前五十二项旁路。
				end
				8'd181:begin
					reg_route <= 144'h0000000003ffffffffffffffffffffffffff; // 前五十三项旁路。
				end
				8'd182:begin
					reg_route <= 144'h000000000fffffffffffffffffffffffffff; // 前五十四项旁路。
				end
				8'd183:begin
					reg_route <= 144'h000000003fffffffffffffffffffffffffff; // 前五十五项旁路。
				end
				8'd184:begin
					reg_route <= 144'h00000000ffffffffffffffffffffffffffff; // 前五十六项旁路。
				end
				8'd185:begin
					reg_route <= 144'h00000003ffffffffffffffffffffffffffff; // 前五十七项旁路。
				end
				8'd186:begin
					reg_route <= 144'h0000000fffffffffffffffffffffffffffff; // 前五十八项旁路。
				end
				8'd187:begin
					reg_route <= 144'h0000003fffffffffffffffffffffffffffff; // 前五十九项旁路。
				end
				8'd188:begin
					reg_route <= 144'h000000ffffffffffffffffffffffffffffff; // 前六十项旁路。
				end
				8'd189:begin
					reg_route <= 144'h000003ffffffffffffffffffffffffffffff; // 前六十一项旁路。
				end
				8'd190:begin
					reg_route <= 144'h00000fffffffffffffffffffffffffffffff; // 前六十二项旁路。
				end
				8'd191:begin
					reg_route <= 144'h00003fffffffffffffffffffffffffffffff; // 前六十三项旁路。
				end
				8'd192:begin
					reg_route <= 144'h0000ffffffffffffffffffffffffffffffff; // 前六十四项旁路。
				end
				8'd193:begin
					reg_route <= 144'h0003ffffffffffffffffffffffffffffffff; // 前六十五项旁路。
				end
				8'd194:begin
					reg_route <= 144'h000fffffffffffffffffffffffffffffffff; // 前六十六项旁路。
				end
				8'd195:begin
					reg_route <= 144'h003fffffffffffffffffffffffffffffffff; // 前六十七项旁路。
				end
				8'd196:begin
					reg_route <= 144'h00ffffffffffffffffffffffffffffffffff; // 前六十八项旁路。
				end
				8'd197:begin
					reg_route <= 144'h03ffffffffffffffffffffffffffffffffff; // 前六十九项旁路。
				end
				8'd198:begin
					reg_route <= 144'h0fffffffffffffffffffffffffffffffffff; // 前七十项旁路。
				end
				8'd199:begin
					reg_route <= 144'h3fffffffffffffffffffffffffffffffffff; // 前七十一项旁路。
				end
				8'd200:begin
					reg_route <= 144'hffffffffffffffffffffffffffffffffffff; // 前七十二项旁路。
				end




































				default:begin
					reg_route <= 144'd0;        // 零数量、越界数量和未声明配置全部屏蔽。
				end
			endcase
		end
	end

	//--------------模块实例化区域--------------//
	// 阵列起点完成固定组重排。
	concat_group concat_group_first_Inst(       // 阵列起点组合组不增加数据延迟。
		.i_selection(group_first_route_o),      // 阵列起点按寄存选择取数。
		.i_spatial(group_first_spatial_o),      // 阵列起点提供低位空间值。
		.i_one(group_first_one_o),              // 阵列起点第一核列接到组内选择。
		.i_two(group_first_two_o),              // 阵列起点中央三项提供独立点积。
		.i_three(group_first_three_o),          // 阵列起点右侧核列参与原顺序恢复。
		.o_data(group_first_data_o),            // 阵列起点交付重排点积。
		.o_mask(group_first_mask_o)             // 阵列起点返回对应资格。
	);

	// 次序靠前完成固定组重排。
	concat_group concat_group_second_Inst(      // 次序靠前组合组不增加数据延迟。
		.i_selection(group_second_route_o),     // 次序靠前按寄存选择取数。
		.i_spatial(group_second_spatial_o),     // 次序靠前提供低位空间值。
		.i_one(group_second_one_o),             // 次序靠前第一核列接到组内选择。
		.i_two(group_second_two_o),             // 次序靠前中央三项提供独立点积。
		.i_three(group_second_three_o),         // 次序靠前右侧核列参与原顺序恢复。
		.o_data(group_second_data_o),           // 次序靠前交付重排点积。
		.o_mask(group_second_mask_o)            // 次序靠前返回对应资格。
	);

	// 前三末端完成固定组重排。
	concat_group concat_group_third_Inst(       // 前三末端组合组不增加数据延迟。
		.i_selection(group_third_route_o),      // 前三末端按寄存选择取数。
		.i_spatial(group_third_spatial_o),      // 前三末端提供低位空间值。
		.i_one(group_third_one_o),              // 前三末端第一核列接到组内选择。
		.i_two(group_third_two_o),              // 前三末端中央三项提供独立点积。
		.i_three(group_third_three_o),          // 前三末端右侧核列参与原顺序恢复。
		.o_data(group_third_data_o),            // 前三末端交付重排点积。
		.o_mask(group_third_mask_o)             // 前三末端返回对应资格。
	);

	// 第二组起点完成固定组重排。
	concat_group concat_group_fourth_Inst(      // 第二组起点组合组不增加数据延迟。
		.i_selection(group_fourth_route_o),     // 第二组起点按寄存选择取数。
		.i_spatial(group_fourth_spatial_o),     // 第二组起点提供低位空间值。
		.i_one(group_fourth_one_o),             // 第二组三核入口第一核列接到组内选择。
		.i_two(group_fourth_two_o),             // 第二组三核入口中央三项提供独立点积。
		.i_three(group_fourth_three_o),         // 第二组三核入口右侧核列参与原顺序恢复。
		.o_data(group_fourth_data_o),           // 第二组起点交付重排点积。
		.o_mask(group_fourth_mask_o)            // 第二组起点返回对应资格。
	);

	// 低半中央完成固定组重排。
	concat_group concat_group_fifth_Inst(       // 低半中央组合组不增加数据延迟。
		.i_selection(group_fifth_route_o),      // 低半中央按寄存选择取数。
		.i_spatial(group_fifth_spatial_o),      // 低半中央提供低位空间值。
		.i_one(group_fifth_one_o),              // 低半中央第一核列接到组内选择。
		.i_two(group_fifth_two_o),              // 低半中央中央三项提供独立点积。
		.i_three(group_fifth_three_o),          // 低半中央右侧核列参与原顺序恢复。
		.o_data(group_fifth_data_o),            // 低半中央交付重排点积。
		.o_mask(group_fifth_mask_o)             // 低半中央返回对应资格。
	);

	// 左半末尾完成固定组重排。
	concat_group concat_group_sixth_Inst(       // 左半末尾组合组不增加数据延迟。
		.i_selection(group_sixth_route_o),      // 左半末尾按寄存选择取数。
		.i_spatial(group_sixth_spatial_o),      // 左半末尾提供低位空间值。
		.i_one(group_sixth_one_o),              // 左半末尾第一核列接到组内选择。
		.i_two(group_sixth_two_o),              // 左半末尾中央三项提供独立点积。
		.i_three(group_sixth_three_o),          // 左半末尾右侧核列参与原顺序恢复。
		.o_data(group_sixth_data_o),            // 左半末尾交付重排点积。
		.o_mask(group_sixth_mask_o)             // 左半末尾返回对应资格。
	);

	// 右半起始位置完成固定组重排。
	concat_group concat_group_seventh_Inst(     // 右半起始位置组合组不增加数据延迟。
		.i_selection(group_seventh_route_o),    // 右半起始位置按寄存选择取数。
		.i_spatial(group_seventh_spatial_o),    // 右半起始位置提供低位空间值。
		.i_one(group_seventh_one_o),            // 右半起始位置第一核列接到组内选择。
		.i_two(group_seventh_two_o),            // 右半起始位置中央三项提供独立点积。
		.i_three(group_seventh_three_o),        // 右半起始位置右侧核列参与原顺序恢复。
		.o_data(group_seventh_data_o),          // 右半起始位置交付重排点积。
		.o_mask(group_seventh_mask_o)           // 右半起始位置返回对应资格。
	);

	// 高段中部完成固定组重排。
	concat_group concat_group_eighth_Inst(      // 高段中部组合组不增加数据延迟。
		.i_selection(group_eighth_route_o),     // 高段中部按寄存选择取数。
		.i_spatial(group_eighth_spatial_o),     // 高段中部提供低位空间值。
		.i_one(group_eighth_one_o),             // 高段中部第一核列接到组内选择。
		.i_two(group_eighth_two_o),             // 高段中部中央三项提供独立点积。
		.i_three(group_eighth_three_o),         // 高段中部右侧核列参与原顺序恢复。
		.o_data(group_eighth_data_o),           // 高段中部交付重排点积。
		.o_mask(group_eighth_mask_o)            // 高段中部返回对应资格。
	);





endmodule
