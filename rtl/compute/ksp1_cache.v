`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/07 21:25:49
// Design Name:     ksp1_cache
// Module Name:     ksp1_cache
// Description:     description/ksp1_cache_Design.pdf
// Simulations:     testbench/vivado/2021.1/ksp1_cache
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/07 21:25:49
// History:
// Time             Version     Revised by        Contents
// 2026/10/07       V1.0        Erie              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月07日
// 设计名称:        ksp1_cache
// 模块名称:        ksp1_cache
// 模块说明:        Description/ksp1_cache_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/ksp1_cache
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

module ksp1_cache
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 同域计算时钟，驱动缓存与列和流水。
	input i_rstn,                               // 异步硬复位，上游proc_sys_reset负责同步释放。

	//-----------------用户接口-----------------//
	input i_ce,                                 // 所有缓存、标签和输出由全局推进同步冻结。
	input i_column_valid,                       // 三组列部分和同时有效。
	input [143:0]i_column_data,                 // 低到高036/147/258的三个signed48点积。
	input i_row_last,                           // 当前完整列属于扫描行末。
	output o_ready,                             // 首个恢复时钟后且ce允许时可提交新列。
	output o_column_commit,                     // 沿前缓存实际写入事件，比输入接受晚一使能沿。
	output o_row_advance,                       // 行末提交通知控制器轮换物理bank。
	output o_valid,                             // 三组和已寄存，停顿保持有效。
	output signed [47:0]o_data                  // 最终空间点的完整tile部分和。
);

	//----------------寄存器信号----------------//
	reg [4:0]reg_position = 5'b00001;           // 空行/首列/右槽/左槽/中槽五相one-hot，转移只需移位和一位或。
	wire [1:0]reg_slot;                         // 五相one-hot位置译码为行内模三写槽。
	wire [1:0]reg_filled;                       // 空行/首列/稳态位置译码为零/一/二列填充资格。
	reg [127:0]reg_ingress = 128'd0;            // 完整列输入、行尾与接受资格共同寄存，截断握手扇入。
	reg [83:0]reg_history = 84'd0;              // 当前完成槽内036和147的两个42位补码历史值。
	reg signed [41:0]reg_third_aligned = 42'd0; // 高核列新值等待历史预加边界后参与最后求和。
	reg signed [42:0]reg_pair = 43'd0;          // 历史两项在选择寄存之后求43位预加，阻断多槽算术链。
	reg signed [41:0]reg_third = 42'd0;         // 当前258新值与历史预加同沿锁存。
	reg signed [41:0]reg_cache_first_left = 42'd0; // 036左槽保存当前模三起点的核列值。
	reg signed [41:0]reg_cache_first_middle = 42'd0; // 首核列中间历史点积供下一输出完成槽读取。
	reg signed [41:0]reg_cache_first_right = 42'd0; // 上组右侧历史值等待循环核横移完成。
	reg signed [41:0]reg_cache_second_left = 42'd0; // 147左位置在余数一写入对应中央列贡献。
	reg signed [41:0]reg_cache_second_middle = 42'd0; // 第二核列中槽维持两次提交之间的完整补码点积。
	reg signed [41:0]reg_cache_second_right = 42'd0; // 中组右槽在第一提交接收新的核列部分和。
	reg signed [41:0]reg_cache_third_left = 42'd0; // 258左位置由余数二覆盖，保留末核列历史状态。
	reg signed [41:0]reg_cache_third_middle = 42'd0; // 第三组中位置收取行内余数零的高42位输入。
	reg signed [41:0]reg_cache_third_right = 42'd0; // 末核列右槽在余数一保存当前扫描点贡献。

	//-----------------标志信号-----------------//
	reg flag_active = 1'b0;                     // 硬复位撤销运行资格，首个恢复沿重新建立。
	reg [1:0]flag_complete = 2'd0;              // 提交时满足两个历史列的输出资格。

	//-----------------其他信号-----------------//
	// 合法域：各输入signed48必须是signed42符号扩展，来自至多1536个INT16乘积。
	// 原始位置字段和完整精度加法操作数
	wire signed [41:0]history_first;            // 历史输入低半字的有符号解释。
	wire signed [41:0]history_second;           // 中核列历史项位于寄存对的高半字。
	wire [6:0]write_control;                    // 缓存写入的握手、填充及槽位字段。
	wire [2:0]row_control;                      // 指针推进及行末重启的联合译码。
	wire [4:0]complete_control;                 // 有效接受字段与填充数判断完整点。
	wire [5:0]pair_control;                     // 允许推进与循环槽位置。
	wire [1:0]result_control;                   // 第二求和级消费资格。
	wire signed [43:0]final_sum;                // 43位历史和加42位当前贡献的完整精度。

	//-----------------输出信号-----------------//
	//用户接口
	reg valid_o = 1'b0;                         // 最终结果与有效事件同时到达下游。
	reg signed [43:0]data_o = 44'd0;            // 气泡保持最近一次完成点的44位结果。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign write_control = {i_ce, reg_ingress[127], reg_position}; // 原始字段拼接避免算术串接写控制。
	assign row_control = {i_ce, reg_ingress[127:126]}; // 行切换与模三轮换采用有限case。
	assign complete_control = {i_ce, reg_ingress[127], reg_position[4:2]}; // 当前提交可输出的资格与第一预加同拍。
	assign pair_control = {i_ce, reg_position}; // 选择完成槽的历史036和147贡献。
	assign result_control = {i_ce, flag_complete[1]}; // 停顿阻止重复写回完整点。
	assign reg_slot = (reg_position[1] || reg_position[4]) ? 2'b01 : (reg_position[2] ? 2'b10 : 2'b00); // one-hot首列和中槽映射余数一，右槽映射二，其余为零。
	assign reg_filled = reg_position[0] ? 2'b00 : (reg_position[1] ? 2'b01 : 2'b10); // 空行与首列分别为零和一，三槽稳态资格饱和二。
	assign history_first = reg_history[41:0];   // 首核列补码数值不作无符号扩展。
	assign history_second = reg_history[83:42]; // 中核列历史值保持signed42含义。
	assign final_sum = reg_pair + reg_third_aligned; // 第二宽加法独立于槽选择与历史预加。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_ready = flag_active && i_ce;       // 恢复后允许接受，暂停时撤销ready。
	assign o_column_commit = i_ce && reg_ingress[127]; // 每笔三组点积只提交一次。
	assign o_row_advance = o_column_commit && reg_ingress[126]; // 行轮换只发生在末列真实提交。
	assign o_valid = valid_o;                   // 下游以ce判断有效输出消费。
	assign o_data = {{4{data_o[43]}}, data_o};  // 保留44位补码点积定义。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 有效输出随第二加法写回，停顿不能重复消费。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			valid_o <= 1'b0;                    // 立即撤销旧空间点的结果事件。
		end else begin
			if(i_ce == 1'b1)begin
				valid_o <= flag_complete[1];    // 完成标签已穿过槽读取与预加边界，同拍标记最终结果。
			end
		end
	end

	// 第二次宽加法在第四级写回完整空间点，缓存提交后再经历两次使能沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			data_o <= 44'sd0;                   // 尚未消费的空间点立即清零。
		end else begin
			case(result_control)
				2'b11:begin
					data_o <= final_sum[43:0];  // 合法tile范围内保留44位，完整计入最后核列。
				end
				default:begin
					data_o <= data_o;           // 气泡和停顿均保留上一完成点的数值。
				end
			endcase
		end
	end

	//-------------主要任务处理区域-------------//
	// 恢复沿建立接受资格，不增加本地复位同步链。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_active <= 1'b0;                // 复位立即禁止新列写入。
		end else begin
			flag_active <= 1'b1;                // 上游已同域释放，进入正常运行状态。
		end
	end

	// 完成资格随槽读取和历史预加经过两个寄存边界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_complete <= 2'd0;              // 异步取消所有在途空间点资格。
		end else begin
			case(complete_control)
				5'b11001,5'b11010,5'b11100:begin
					flag_complete <= {flag_complete[0], 1'b1}; // 接受第三列之后把完整点标志送入预加流水。
				end
				5'b10000,5'b10001,5'b10010,5'b10011,5'b10100,5'b10101,5'b10110,5'b10111,5'b11000,5'b11011,5'b11101,5'b11110,5'b11111:begin
					flag_complete <= {flag_complete[0], 1'b0}; // 推进气泡或填充期间仅移动已有标签。
				end
				default:begin
					flag_complete <= flag_complete; // 全局停顿保持两级完成状态。
				end
			endcase
		end
	end

	// 完成槽内两组历史值先寄存，选择和宽加法分离。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_history <= 84'd0;               // 选择级没有旧行补码数据残留。
		end else begin
			case(pair_control)
				6'b100001,6'b101000:begin
					reg_history <= {reg_cache_second_middle, reg_cache_first_middle}; // 余数零的完整点读取中槽两组历史项。
				end
				6'b100010,6'b110000:begin
					reg_history <= {reg_cache_second_right, reg_cache_first_right}; // 循环中间写入对应右边完成位置。
				end
				6'b100100:begin
					reg_history <= {reg_cache_second_left, reg_cache_first_left}; // 回绕时左槽保存所需前两列贡献。
				end
				default:begin
					reg_history <= reg_history; // 未推进或非法槽编码保持选择寄存。
				end
			endcase
		end
	end

	// 43位预加使用已选择的两项，避免将三个槽加法同时放进译码锥。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_pair <= 43'sd0;                 // 历史部分和立即失效，禁止旧项参与新扫描。
		end else if(i_ce == 1'b1)begin
			reg_pair <= history_first + history_second; // 两个signed42相加保留完整进位。
		end
	end

	// 当前258贡献锁存到下一求和级，避免同拍写读旧值。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_third <= 42'sd0;                // 第三核列在硬复位无残留。
		end else begin
			if(i_ce == 1'b1)begin
				reg_third <= reg_ingress[125:84]; // 输入级锁存的258点积与本次读取的历史两项并行延迟。
			end
		end
	end

	// 输入握手及行尾先寄存；下拍缓存事件从寄存资格产生。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_ingress <= 128'd0;              // 非沿复位清除尚未写缓存的完整列。
		end else if(i_ce == 1'b1)begin
			reg_ingress <= {i_column_valid && flag_active, i_row_last, i_column_data[137:96], i_column_data[89:48], i_column_data[41:0]}; // valid与ready成立的输入跨过同一寄存边界。
		end
	end

	// 新高核列多延迟一拍，与历史43位和到达最终加法。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_third_aligned <= 42'sd0;        // 最后求和操作数在硬复位时清零。
		end else if(i_ce == 1'b1)begin
			reg_third_aligned <= reg_third;     // 258值等待独立历史预加沿，不能错配下一列。
		end
	end

	// 五相循环只移动one-hot位，首两项填充之后按三个物理写槽重复。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_position <= 5'b00001;           // 复位进入空行阶段，禁止前两列产生完整输出。
		end else begin
			case(row_control)
				3'b110:begin
					reg_position <= {reg_position[3:2], reg_position[4] | reg_position[1], reg_position[0], 1'b0}; // 首项转首列，第二项进入右槽，稳态三槽持续轮换。
				end
				3'b111:begin
					reg_position <= 5'b00001;   // 实际行尾提交结束旧行，下行首项重新建立历史。
				end
				default:begin
					reg_position <= reg_position; // 非接受沿保持one-hot位置和填充资格。
				end
			endcase
		end
	end

	// 低核列左缓存仅在循环命中时覆盖，行首其它位置同时失效。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_first_left <= 42'sd0;     // 旧036起点立即清除。
		end else begin
			case(write_control)
				7'b1100001,7'b1101000:begin
					reg_cache_first_left <= reg_ingress[41:0]; // 左上物理位置取低输入，为三列横向复用建立起点。
				end
				default:begin
					reg_cache_first_left <= reg_cache_first_left; // 左上没有写授权，保持核列值。
				end
			endcase
		end
	end

	// 首组中央位置保留下一完成点所需历史036部分和。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_first_middle <= 42'sd0;   // 中间首核列恢复零点积。
		end else begin
			case(write_control)
				7'b1100010,7'b1110000:begin
					reg_cache_first_middle <= reg_ingress[41:0]; // 将036当前补码点积写入中间槽，等待下一完成位置选择。
				end
				7'b1100001:begin
					reg_cache_first_middle <= 42'sd0; // 第一列清除中间036旧贡献。
				end
				default:begin
					reg_cache_first_middle <= reg_cache_first_middle; // 第一组中间状态在非命中沿维持。
				end
			endcase
		end
	end

	// 最后首组写口轮换使用右槽，跨行不延续旧任务点积。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_first_right <= 42'sd0;    // 上组最右历史失效。
		end else begin
			case(write_control)
				7'b1100100:begin
					reg_cache_first_right <= reg_ingress[41:0]; // 余数二提交用低42位替换首组最右边核贡献。
				end
				7'b1100001:begin
					reg_cache_first_right <= 42'sd0; // 新扫描行尚无右侧首组历史。
				end
				default:begin
					reg_cache_first_right <= reg_cache_first_right; // 首组右位置无握手覆盖，保留历史。
				end
			endcase
		end
	end

	// 中核列左槽承担与第一组偏移一列的写入次序。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_second_left <= 42'sd0;    // 第二组左核列状态归空。
		end else begin
			case(write_control)
				7'b1100010,7'b1110000:begin
					reg_cache_second_left <= reg_ingress[83:42]; // 第二列核的输入中42位在左槽命中时保存。
				end
				7'b1100001:begin
					reg_cache_second_left <= 42'sd0; // 147左位置在新行重新填充。
				end
				default:begin
					reg_cache_second_left <= reg_cache_second_left; // 中央核组左缓存等待下一轮写入。
				end
			endcase
		end
	end

	// 147中央存储响应第三槽提交，独立保持42位精度。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_second_middle <= 42'sd0;  // 中央147贡献被异步抹除。
		end else begin
			case(write_control)
				7'b1100100:begin
					reg_cache_second_middle <= reg_ingress[83:42]; // 中央核组对应提交取完整147部分和作为新的中槽历史。
				end
				7'b1100001:begin
					reg_cache_second_middle <= 42'sd0; // 本行首项没有中央核列历史值。
				end
				default:begin
					reg_cache_second_middle <= reg_cache_second_middle; // 147中间物理位置暂停时不变。
				end
			endcase
		end
	end

	// 行内起点把第二核组值先放入右侧位置，形成斜向KsP1排列。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_second_right <= 42'sd0;   // 末端中组无残留旧行部分和。
		end else begin
			case(write_control)
				7'b1100001,7'b1101000:begin
					reg_cache_second_right <= reg_ingress[83:42]; // 147新贡献先写到右物理位置，保持相对写槽偏移。
				end
				default:begin
					reg_cache_second_right <= reg_cache_second_right; // 第二组右点积在气泡中仍有效保留。
				end
			endcase
		end
	end

	// 第三核组左写口在余数二替换，禁止无效输入覆盖。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_third_left <= 42'sd0;     // 高核列左位置复位为零。
		end else begin
			case(write_control)
				7'b1100100:begin
					reg_cache_third_left <= reg_ingress[125:84]; // 当前高42位输入覆盖底组左端位置。
				end
				7'b1100001:begin
					reg_cache_third_left <= 42'sd0; // 第三组左位置从空历史开始。
				end
				default:begin
					reg_cache_third_left <= reg_cache_third_left; // 底组左存储不随无效数据变化。
				end
			endcase
		end
	end

	// 高位新核列在首个循环位置保存，当前输出另经寄存旁路。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_third_middle <= 42'sd0;   // 底组中缓存立即响应硬复位。
		end else begin
			case(write_control)
				7'b1100001,7'b1101000:begin
					reg_cache_third_middle <= reg_ingress[125:84]; // 258首列新值保存在中央槽，同时经输入寄存旁路求最终和。
				end
				default:begin
					reg_cache_third_middle <= reg_cache_third_middle; // 末组中位置直到有效命中才更新。
				end
			endcase
		end
	end

	// 258最后一个物理槽随实际提交更新，不从新行复用旧历史。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cache_third_right <= 42'sd0;    // 258末槽的前任务贡献全部作废。
		end else begin
			case(write_control)
				7'b1100010,7'b1110000:begin
					reg_cache_third_right <= reg_ingress[125:84]; // 末组右端保存第二循环提交的高核列补码结果。
				end
				7'b1100001:begin
					reg_cache_third_right <= 42'sd0; // 末组右侧旧行贡献不能参与新的输出。
				end
				default:begin
					reg_cache_third_right <= reg_cache_third_right; // 最右末核列对停顿与输入气泡保持。
				end
			endcase
		end
	end

endmodule
