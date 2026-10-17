`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/07 20:38:06
// Design Name:     column_acc
// Module Name:     column_acc
// Description:     description/column_acc_Design.pdf
// Simulations:     testbench/vivado/2021.1/column_acc
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/07 20:38:06
// History:
// Time             Version     Revised by        Contents
// 2026/10/07       V1.0        Erie              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月07日
// 设计名称:        column_acc
// 模块名称:        column_acc
// 模块说明:        Description/column_acc_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/column_acc
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月07日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月07日   V1.0        Erie              创建文件

module column_acc
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 计算域时钟。
	input i_rstn,                               // 异步置位、上游同域同步释放。

	//-----------------用户接口-----------------//
	input i_ce,                                 // 全局推进，所有级同步暂停。
	input i_mac_valid,                          // 当前通道对有效。
	input [98:0]i_mac_data,                     // 低到高上中下三个signed33。
	input [2:0]i_row_mask,                      // 本列有效行选择。
	input i_bypass,                             // 九lane独立点积旁路模式。
	input i_first,                              // 当前tile首对。
	input i_last,                               // 当前tile末对。
	output o_ready,                             // 首个恢复沿建立就绪状态，且全局允许推进。
	output o_valid,                             // 末对已计入部分和。
	output [143:0]o_data                        // 三个signed48，空间模式高两lane为零。
);

	//----------------寄存器信号----------------//
	reg signed [33:0]reg_upper = 34'd0;         // 前两行34位预加。
	reg signed [32:0]reg_top_masked = 33'd0;    // top行第1级旁路数据。
	reg signed [32:0]reg_top_aligned = 33'd0;   // 第一独立MAC穿越上两行加法边界，和34位列部分和同拍。
	reg signed [34:0]reg_top_selected = 35'd0;  // 空间列signed35或符号扩展的独立MAC。
	reg signed [41:0]reg_top_sum = 42'd0;       // 最多1536个INT16乘积，signed42。
	reg signed [32:0]reg_middle_masked = 33'd0; // 中央核位置的mask输出，下一沿参加垂直预加。
	reg signed [32:0]reg_middle_aligned = 33'd0; // K3/K4/K5对应贡献保持原33位精度，供独立点积选择。
	reg signed [32:0]reg_middle_selected = 33'd0; // 中央独立MAC或空间零值，signed33。
	reg signed [40:0]reg_middle_sum = 41'd0;    // 中央MAC累积单tile独立点积，41位存储覆盖512通道。
	reg signed [32:0]reg_bottom_masked = 33'd0; // 核底行参与位已施加，2×2下方脏输入在此被清除。
	reg signed [32:0]reg_bottom_aligned = 33'd0; // 第三项等待上中预加结束，随后进入35位列加法。
	reg signed [32:0]reg_bottom_selected = 33'd0; // 底行独立MAC或空间零值，signed33。
	reg signed [40:0]reg_bottom_sum = 41'd0;    // 底行旁路的深度反馈，符号位40维持负数点积。

	//-----------------标志信号-----------------//
	reg [2:0]flag_valid = 3'd0;                 // 进入最终累加级前的三个有效标签。
	reg [2:0]flag_first = 3'd0;                 // 逐级首对标签。
	reg [2:0]flag_last = 3'd0;                  // 对齐最终列结果的末对标签。
	reg [2:0]flag_bypass = 3'd0;                // 每笔数据的模式标签。
	reg flag_active = 1'd0;                     // 异步复位清零，释放后首个时钟进入可接受状态。
	wire flag_accepted;                         // 启动状态就绪后才接受输入。

	//-----------------其他信号-----------------//
	// 合法域：每项为两个signed16乘积之和，每次first至last最多256个有效通道对。
	// 完整精度操作数与控制译码
	wire signed [32:0]term_top;                 // 上行输入补码解释。
	wire signed [32:0]term_middle;              // 中行输入补码解释。
	wire signed [32:0]term_bottom;              // 下行输入补码解释。
	wire [1:0]sign_top;                         // signed33旁路补齐35位选择寄存器。
	wire signed [42:0]sum_top;                  // signed43累加中间和，最高位供溢出检查。
	wire signed [41:0]sum_middle;               // signed42中间和，写回signed41。
	wire signed [41:0]sum_bottom;               // 末lane旧向量合并当前底部MAC，位41用于写回检查。
	wire signed [34:0]column_value;             // 34位上两行与33位下行形成35位列和。
	wire [1:0]select_control;                   // 推进与旁路译码固定两位。
	wire [2:0]accumulate_control;               // 推进/有效/首项的三位联合条件。

	//-----------------输出信号-----------------//
	//用户接口
	reg valid_o = 1'd0;                         // 累加后的有效事件。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign term_top = i_mac_data[32:0];         // 有符号低通道对。
	assign term_middle = i_mac_data[65:33];     // 有符号中通道对。
	assign term_bottom = i_mac_data[98:66];     // 有符号高通道对。
	assign sign_top = {2{reg_top_aligned[32]}}; // 旁路低lane显式扩展到signed35。
	assign sum_top = reg_top_sum + reg_top_selected; // signed42反馈与signed35本项相加，保留检查位。
	assign sum_middle = reg_middle_sum + reg_middle_selected; // 中lane旧部分和加上本通道项，宽位结果待写回。
	assign sum_bottom = reg_bottom_sum + reg_bottom_selected; // 底行独立向量的有效贡献与其历史点积合并。
	assign column_value = reg_upper + reg_bottom_aligned; // 最后一项列预加。
	assign select_control = {i_ce, flag_bypass[1]}; // 空间与旁路Acc选择。
	assign accumulate_control = {i_ce, flag_valid[2], flag_first[2]}; // 深度累加有限条件编码。
	assign flag_accepted = i_mac_valid && flag_active; // 首个复位恢复沿不接受数据。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_ready = flag_active && i_ce;       // 不额外产生本地ready链。
	assign o_valid = valid_o;                   // 下游同时判断全局推进。
	assign o_data = {{7{reg_bottom_sum[40]}}, reg_bottom_sum, {7{reg_middle_sum[40]}}, reg_middle_sum, {6{reg_top_sum[41]}}, reg_top_sum}; // 本列三lane点积保持原序。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 对齐第四级累加完成沿，向下游发布整个tile的完成资格。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			valid_o <= 1'd0;                    // 立即撤销尚未消费的列完成事件。
		end else if(i_ce == 1'b1)begin
			valid_o <= flag_valid[2] && flag_last[2]; // 最后通道对已到达第四级，置位完整向量结果标签。
		end
	end

	//-------------主要任务处理区域-------------//
	// 通道标签流水记录各级气泡，暂停不增加使能序号。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_valid <= 3'd0;                 // 丢弃所有预加流水气泡和旧事务资格。
		end else if(i_ce == 1'b1)begin
			flag_valid <= {flag_valid[1:0], flag_accepted}; // 已就绪的MAC数据每使能沿进入有效移位链。
		end
	end

	// 向量起点沿预加路径传递，决定覆盖旧部分和。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_first <= 3'd0;                 // 首通道标记清空，防止复位后覆盖新任务。
		end else if(i_ce == 1'b1)begin
			flag_first <= {flag_first[1:0], i_first}; // 新向量起点按相同使能时钟逐级传递。
		end
	end

	// tile结束标志等待第三行和旁路选择完成。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_last <= 3'd0;                  // 末项信息作废，停止旧tile产生完成脉冲。
		end else if(i_ce == 1'b1)begin
			flag_last <= {flag_last[1:0], i_last}; // 输入尾对延迟三个寄存边界再触发深度和输出。
		end
	end

	// 模式随数据移动，避免回压时选择另一条数值路径。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_bypass <= 3'd0;                // 恢复空间默认路由，等待新任务模式。
		end else if(i_ce == 1'b1)begin
			flag_bypass <= {flag_bypass[1:0], i_bypass}; // 旁路选择随当前通道数据前进，不依赖变化的外部模式。
		end
	end

	// 输入低33位应用上行参与位，仅屏蔽未使用核位置。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_top_masked <= 33'd0;            // 上行输入寄存置零，消除旧的低位MAC贡献。
		end else if(i_ce == 1'b1)begin
			reg_top_masked <= i_row_mask[0] ? term_top : 33'sd0; // 第一行按核位置参与位锁存33位补码数。
		end
	end

	// 第一行旁路多延迟一拍，与上中两行和同步。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_top_aligned <= 33'd0;           // 清除第一旁路延时拍，与上两行和一起重新填充。
		end else if(i_ce == 1'b1)begin
			reg_top_aligned <= reg_top_masked;  // 低行原始贡献穿过加法边界，供独立lane模式选用。
		end
	end

	// 中央MAC行补码结果独立锁存，确保负数符号保持。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_middle_masked <= 33'd0;         // 中央行清零，后续预加不再看到残留中间项。
		end else if(i_ce == 1'b1)begin
			reg_middle_masked <= i_row_mask[1] ? term_middle : 33'sd0; // 中行不参与时输入零值，参与时保留完整双乘积和。
		end
	end

	// 第二路独立点积穿过预加级，供矩阵九lane输出。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_middle_aligned <= 33'd0;        // 第二路点积对齐寄存没有有效旧样本。
		end else if(i_ce == 1'b1)begin
			reg_middle_aligned <= reg_middle_masked; // 中央MAC数值随上行预加时钟延迟一次。
		end
	end

	// 底部核行不参与时写零，阻止2×2脏数据污染。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_bottom_masked <= 33'd0;         // 最后一行贡献擦除，避免旧底部窗口延续。
		end else if(i_ce == 1'b1)begin
			reg_bottom_masked <= i_row_mask[2] ? term_bottom : 33'sd0; // 底行的参与mask真实屏蔽2×2核外非零数据。
		end
	end

	// 第三路对齐寄存器为35位最终列加法提供操作数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_bottom_aligned <= 33'd0;        // 第三加数对齐拍恢复零，后级列加法重新开始。
		end else if(i_ce == 1'b1)begin
			reg_bottom_aligned <= reg_bottom_masked; // 下行数据等待34位上中预加值，防止跨拍混加。
		end
	end

	// 34位寄存边界保存上中两项之和，切断串联加法链。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_upper <= 34'd0;                 // 34位部分列和归零，预加链从空流水起步。
		end else if(i_ce == 1'b1)begin
			reg_upper <= reg_top_masked + reg_middle_masked; // 上中两项相加保留进位，为最终列预加建立独立寄存边界。
		end
	end

	// 低lane依据模式锁存完整35位列和或单路MAC，存入signed35。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_top_selected <= 35'd0;          // 35位低lane的Acc输入清空，不引入旧向量末项。
		end else begin
			case(select_control)
				2'b11:begin
					reg_top_selected <= {sign_top, reg_top_aligned}; // 1×1/矩阵低lane选择符号扩展的第一MAC。
				end
				2'b10:begin
					reg_top_selected <= column_value; // 空间模式将35位完整列和扩展到35位。
				end
				default:begin
					reg_top_selected <= reg_top_selected; // 模式选择级在暂停拍保留低路Acc样本。
				end
			endcase
		end
	end

	// 有效首对覆盖低lane，后续对通过43位中间和累加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_top_sum <= 42'd0;               // 本列主要深度累加值立即归零。
		end else begin
			case(accumulate_control)
				3'b110:begin
					reg_top_sum <= sum_top[41:0]; // 低lane用43位加法中间值更新，合法tile范围内保留42位。
				end
				3'b111:begin
					reg_top_sum <= {{7{reg_top_selected[34]}}, reg_top_selected}; // 新的空间列或低lane向量首项取代旧深度结果。
				end
				default:begin
					reg_top_sum <= reg_top_sum; // 未满足联合消费条件，低路结果维持原值。
				end
			endcase
		end
	end

	// 空间卷积清零中lane，旁路模式保留K3/K4/K5贡献。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_middle_selected <= 33'd0;       // 中间Acc选择级复位到空点积。
		end else begin
			case(select_control)
				2'b11:begin
					reg_middle_selected <= reg_middle_aligned; // 中央旁路保留K3/K4/K5所属列的独立贡献。
				end
				2'b10:begin
					reg_middle_selected <= 33'sd0; // 3×3/2×2中lane不用，必须向深度和提供零。
				end
				default:begin
					reg_middle_selected <= reg_middle_selected; // 全局停顿不改变中央旁路寄存数据。
				end
			endcase
		end
	end

	// 中lane只在有效推进时更新深度部分和，气泡保持原值。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_middle_sum <= 41'd0;            // 九lane旁路的中央深度和重新初始化。
		end else begin
			case(accumulate_control)
				3'b110:begin
					reg_middle_sum <= sum_middle[40:0]; // 中路累计当前有效输入对，不遗漏最后高通道补零项。
				end
				3'b111:begin
					reg_middle_sum <= {{8{reg_middle_selected[32]}}, reg_middle_selected}; // 旁路中央向量以当前Acc建立新的部分和。
				end
				default:begin
					reg_middle_sum <= reg_middle_sum; // 停顿或气泡期间中央深度和保持，禁止重复累加。
				end
			endcase
		end
	end

	// 高lane选择K6/K7/K8独立贡献，末通道仍保持全精度。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_bottom_selected <= 33'd0;       // 高路预加输出无残留通道贡献。
		end else begin
			case(select_control)
				2'b11:begin
					reg_bottom_selected <= reg_bottom_aligned; // 最高旁路输出来自K6/K7/K8对应的底行。
				end
				2'b10:begin
					reg_bottom_selected <= 33'sd0; // 空间卷积高lane为空，防止形成额外输出通道。
				end
				default:begin
					reg_bottom_selected <= reg_bottom_selected; // 最上层调用未推进时保留末lane输入。
				end
			endcase
		end
	end

	// 底lane自累加与同行valid同步完成，不提前输出末项。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_bottom_sum <= 41'd0;            // 底部独立输出恢复空向量，所有历史累加作废。
		end else begin
			case(accumulate_control)
				3'b110:begin
					reg_bottom_sum <= sum_bottom[40:0]; // 高lane维持独立通道点积，末对更新与valid同拍。
				end
				3'b111:begin
					reg_bottom_sum <= {{8{reg_bottom_selected[32]}}, reg_bottom_selected}; // 底lane首通道直接装载，首尾同拍也适用。
				end
				default:begin
					reg_bottom_sum <= reg_bottom_sum; // 无有效推进时底lane状态不增加通道贡献。
				end
			endcase
		end
	end

	// 任务恢复状态在时钟沿建立，硬复位立即禁止ready。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_active <= 1'b0;                // 硬复位禁止接口接受任何通道对。
		end else begin
			flag_active <= 1'b1;                // 复位已由上游释放，首个本域时钟建立运行资格。
		end
	end

endmodule
