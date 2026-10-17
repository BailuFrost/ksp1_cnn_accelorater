`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/07 21:56:20
// Design Name:     three_stage_acc
// Module Name:     three_stage_acc
// Description:     description/three_stage_acc_Design.pdf
// Simulations:     testbench/vivado/2021.1/three_stage_acc
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/07 21:56:20
// History:
// Time             Version     Revised by        Contents
// 2026/10/07       V1.0        Erie              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月07日
// 设计名称:        three_stage_acc
// 模块名称:        three_stage_acc
// 模块说明:        Description/three_stage_acc_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/three_stage_acc
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

module three_stage_acc
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 同一计算域的时钟。
	input i_rstn,                               // 异步置位，上游统一同步释放。

	//-----------------用户接口-----------------//
	input i_ce,                                 // 三列累加、缓存与输出共享冻结控制。
	input i_in_valid,                           // 九个MAC乘积和同时有效。
	input i_first,                              // 当前tile向量的首通道对。
	input i_last,                               // 当前tile向量的末通道对。
	input i_row_last,                           // 对齐MAC结果的扫描行末标签。
	input [1:0]i_mode,                          // 层内固定模式；流水排空且行尾提交后允许切换。
	input [296:0]i_mac_data,                    // 按K0至K8排列的九个signed33结果。
	output o_ready,                             // 三列累加共同接受资格。
	output o_valid,                             // 当前模式的已寄存结果有效。
	output signed [47:0]o_zero,                 // 空间卷积的完整signed48点。
	output [143:0]o_one,                        // 第一核列的三个独立点积。
	output [143:0]o_two,                        // 第二核列的三个独立点积。
	output [143:0]o_three,                      // 第三核列的三个独立点积。
	output o_column_commit,                     // 3×3或2×2实际缓存写入事件。
	output o_row_advance                        // 实际行末缓存提交事件。
);

	//--------------模块实例化信号--------------//
	//ksp1_cache--用户接口
	wire signed [47:0]cache_data;               // 三列完整空间点，非三列任务始终为零。

	//----------------寄存器信号----------------//
	//固定列连接--用户接口
	wire [431:0]reg_vector_data;                // 三份B1列累加结果，各144位。
	wire [143:0]reg_spatial_data;               // 已完成三组空间点积送入B2。
	wire [98:0]reg_column_first;                // K6/K3/K0按下中上拼接。
	wire [98:0]reg_column_middle;               // K7/K4/K1保持中央核列对应。
	wire [98:0]reg_column_last;                 // K8/K5/K2形成末核列输入。
	reg [2:0]reg_mode = 3'd0;                   // one-hot类别：001三列、010两列、100独立lane。
	reg [3:0]reg_row_tags = 4'd0;               // 行尾标签共享B1四级推进。
	reg [85:0]reg_small_ingress = 86'd0;        // 两列入口：有效、已限定行尾及两个42位列点积。
	reg signed [41:0]reg_previous = 42'd0;      // 两列KsP1的上一扫描列K0/K3贡献。
	reg signed [42:0]reg_small_result = 43'd0;  // 两列缓存完成点，气泡时保持数值。

	// 列累加器端口只连接完整宽度的中间信号。
	wire [143:0]reg_vector_first_data;          // 首列零三六的三个48位深度结果。
	wire [143:0]reg_vector_middle_data;         // 中央一四七组保存第二核列向量。
	wire [143:0]reg_vector_last_data;           // 末组二五八提供右侧垂直点积。

	//-----------------标志信号-----------------//
	wire [2:0]flag_mask_active;                 // 两列任务只启用垂直上中行。
	wire [2:0]flag_mask_last;                   // 无效第三核列在两列任务屏蔽。
	reg flag_small_filled = 1'b0;               // 两列缓存具有一个有效历史贡献。
	reg flag_small_valid = 1'b0;                // 两列结果同步有效标签。
	reg flag_bypass_valid = 1'b0;               // 独立lane结果同步有效标签。
	wire [2:0]flag_vector_valid;                // 三列同步完成向量的有效标签。
	wire [2:0]flag_vector_ready;                // 三列统一恢复与冻结资格。
	wire flag_cache_valid;                      // B2已寄存完整空间点资格。
	wire flag_cache_commit;                     // B2实际写槽事件。
	wire flag_cache_row;                        // B2实际行末写槽事件。
	wire flag_spatial;                          // 已寄存三列类别译码。
	wire flag_small;                            // 已寄存两列类别译码。
	wire flag_bypass;                           // 已寄存独立lane类别译码。
	wire flag_small_accept;                     // 完整列与两列模式同时满足。
	wire flag_cache_ready;                      // 三列缓存与B1同时恢复的许可。
	wire flag_vector_first_valid;               // 第一组完成位代表同步列结果到达。
	wire flag_vector_first_ready;               // 首列累加器恢复后允许输入。
	wire flag_vector_middle_valid;              // 中央列点积结束后建立向量资格。
	wire flag_vector_middle_ready;              // 中间核组共享全局推进许可。
	wire flag_vector_last_valid;                // 右侧第三列标记自己的末通道输出。
	wire flag_vector_last_ready;                // 最右组复位恢复状态用于三列核对。
	wire flag_spatial_accept;                   // 三列入口的完整有效信号。
	wire flag_spatial_row_last;                 // 三列入口的完整行尾标签。

	//-----------------其他信号-----------------//
	// 合法域：tile最多512通道，旁路lane为signed41符号扩展，两列点积为signed42符号扩展。
	// 两列算术和统一事件的有限控制字段
	wire signed [41:0]current_second;           // 两列入口中的K1/K4新贡献。
	wire signed [42:0]small_sum;                // 两个signed42相加的signed43完整和。
	wire [2:0]commit_control;                   // 同拍三列/两列写入资格与ce合并。
	wire [2:0]row_control;                      // 真正行末提交的有限译码字段。
	wire [2:0]bypass_control;                   // 全局推进、列完成和独立lane类别。
	wire [2:0]small_control;                    // 两列实际提交及历史填充资格。

	//-----------------输出信号-----------------//
	//用户接口
	wire ready_o;                               // 三列同步恢复资格的单bit桥接。
	reg [122:0]one_o = 123'd0;                  // K0/K3/K6独立点积末级寄存器。
	reg [122:0]two_o = 123'd0;                  // 第二核列三lane的补码结果。
	reg [122:0]three_o = 123'd0;                // 高核列上中下向量输出存储。
	reg column_commit_o = 1'b0;                 // 两种空间路径合并后的缓存事件。
	reg row_advance_o = 1'b0;                   // 两种空间路径合并后的行末事件。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign reg_vector_data = {reg_vector_last_data, reg_vector_middle_data, reg_vector_first_data}; // 聚合完整列输出，保持258/147/036位序。
	assign flag_vector_valid = {flag_vector_last_valid, flag_vector_middle_valid, flag_vector_first_valid}; // 聚合三列完整有效端口。
	assign flag_vector_ready = {flag_vector_last_ready, flag_vector_middle_ready, flag_vector_first_ready}; // 聚合三列完整恢复许可端口。
	assign flag_spatial_accept = flag_vector_first_valid && flag_spatial; // 三列入口有效条件显式连线，不在实例端口运算。
	assign flag_spatial_row_last = reg_row_tags[3]; // 行尾标签切片在连线区域完成。
	assign flag_spatial = reg_mode[0];          // 三列类别由时钟边界预译码。
	assign flag_small = reg_mode[1];            // 两列类别不穿过宽加法选择链。
	assign flag_bypass = reg_mode[2];           // 两种旁路共享独立lane路径。
	assign flag_small_accept = flag_vector_first_valid && flag_small; // 两列入口资格先寄存，再执行实际求和。
	assign current_second = reg_small_ingress[41:0]; // 显式有符号解释当前列贡献。
	assign small_sum = reg_previous + current_second; // 43位赋值上下文保留完整进位。
	assign ready_o = flag_cache_ready;          // 三列共享资格，取首列代表。
	assign commit_control = {i_ce, flag_cache_commit, reg_small_ingress[85]}; // 资格拼接不再串接模式比较。
	assign row_control = {i_ce, flag_cache_row, reg_small_ingress[84]}; // 缓存行尾和已限定两列行尾合并。
	assign bypass_control = {i_ce, flag_vector_first_valid, flag_bypass}; // 末级使能用单次有限case译码。
	assign small_control = {i_ce, reg_small_ingress[85], flag_small_filled}; // 两列首列填充不输出完整点。
	assign reg_spatial_data = {reg_vector_data[335:288], reg_vector_data[191:144], reg_vector_data[47:0]}; // 258/147/036三个低lane对齐缓存输入。
	assign reg_column_first = {i_mac_data[230:198], i_mac_data[131:99], i_mac_data[32:0]}; // 首核列遵循036分组。
	assign reg_column_middle = {i_mac_data[263:231], i_mac_data[164:132], i_mac_data[65:33]}; // 三行乘积和汇入147垂直通路。
	assign reg_column_last = {i_mac_data[296:264], i_mac_data[197:165], i_mac_data[98:66]}; // 末核列以258顺序输入列累加。
	assign flag_mask_active = flag_small ? 3'b011 : 3'b111; // 小核前两组只取上中两项。
	assign flag_mask_last = flag_small ? 3'b000 : 3'b111; // 两列任务不使用K2/K5/K8。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_ready = ready_o;                   // 同一时钟/复位/ce使三列资格一致。
	assign o_valid = (flag_spatial && flag_cache_valid) || (flag_small && flag_small_valid) || (flag_bypass && flag_bypass_valid); // 只发布当前模式完成资格，隔离旧层标签。
	assign o_zero = flag_spatial ? cache_data : (flag_small ? {{5{reg_small_result[42]}}, reg_small_result} : 48'd0); // 未激活路径可能保留前层值，按模式选择空间结果。
	assign o_one = flag_bypass ? {{7{one_o[122]}}, one_o[122:82], {7{one_o[81]}}, one_o[81:41], {7{one_o[40]}}, one_o[40:0]} : 144'd0; // 空间层屏蔽上一旁路层的低三lane。
	assign o_two = flag_bypass ? {{7{two_o[122]}}, two_o[122:82], {7{two_o[81]}}, two_o[81:41], {7{two_o[40]}}, two_o[40:0]} : 144'd0; // 空间层屏蔽上一旁路层的中央三lane。
	assign o_three = flag_bypass ? {{7{three_o[122]}}, three_o[122:82], {7{three_o[81]}}, three_o[81:41], {7{three_o[40]}}, three_o[40:0]} : 144'd0; // 仅旁路模式发布末核列向量。
	assign o_column_commit = column_commit_o;   // 事件以沿前值消费，不在停顿重复提交。
	assign o_row_advance = row_advance_o;       // 控制器仅在实际末列写入时轮换bank。

	//-------------输出信号处理区域-------------//
	// 首核列的独立lane输出级。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			one_o <= 123'd0;                    // 非沿复位撤销对应核列旧结果。
		end else begin
			case(bypass_control)
				3'b111:begin
					one_o <= {reg_vector_data[136:96], reg_vector_data[88:48], reg_vector_data[40:0]}; // 点积完成后只寄存，无核间算术。
				end
				default:begin
					one_o <= one_o;             // 当前点积在气泡和停顿保持。
				end
			endcase
		end
	end

	// 中央核列点积寄存级。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			two_o <= 123'd0;                    // 中间核列的补码向量立即抹除。
		end else begin
			case(bypass_control)
				3'b111:begin
					two_o <= {reg_vector_data[280:240], reg_vector_data[232:192], reg_vector_data[184:144]}; // 中间列深度累加后存入O2。
				end
				default:begin
					two_o <= two_o;             // 中央列没有新完成向量时保留。
				end
			endcase
		end
	end

	// 末核列结果在统一ce下推进。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			three_o <= 123'd0;                  // 旧任务末列三个lane在复位时失效。
		end else begin
			case(bypass_control)
				3'b111:begin
					three_o <= {reg_vector_data[424:384], reg_vector_data[376:336], reg_vector_data[328:288]}; // 末组完成的九lane高片段写入O3。
				end
				default:begin
					three_o <= three_o;         // 最后核列随全局冻结停止更新。
				end
			endcase
		end
	end

	//用户接口
	// 写槽许可由已寄存的三列/两列事务和全局推进联合译码。
	always@(*)begin
		case(commit_control)
			3'b101,3'b110,3'b111:begin
				column_commit_o = 1'b1;         // 任一空间路径实际写入且全局推进。
			end
			default:begin
				column_commit_o = 1'b0;         // 停顿或未填入有效列时无事件。
			end
		endcase
	end

	// 合并真实行末写入，不把延迟输出当行切换。
	always@(*)begin
		case(row_control)
			3'b101,3'b110,3'b111:begin
				row_advance_o = 1'b1;           // 入口行尾已与有效资格共同寄存。
			end
			default:begin
				row_advance_o = 1'b0;           // 不发出虚假的行轮换。
			end
		endcase
	end

	//-------------主要任务处理区域-------------//
	// 固定任务模式在恢复沿预译码，ce停顿不改变任务类别。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_mode <= 3'd0;                   // 复位时所有任务类别均关闭。
		end else begin
			case(i_mode)
				2'b00:begin
					reg_mode <= 3'b001;         // 三列KsP1。
				end
				2'b01:begin
					reg_mode <= 3'b010;         // 两列KsP1。
				end
				default:begin
					reg_mode <= 3'b100;         // 1×1与矩阵保留独立lane。
				end
			endcase
		end
	end

	// 行尾沿B1四级数据边界延迟。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_row_tags <= 4'd0;               // 立即取消B1在途行尾标签。
		end else if(i_ce == 1'b1)begin
			reg_row_tags <= {reg_row_tags[2:0], i_row_last}; // 与四级列完成标签共同推进。
		end
	end

	// 两列点积及已限定行尾在求和之前锁存。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_small_ingress <= 86'd0;         // 清未实际写入两列缓存的数据和事件。
		end else if(i_ce == 1'b1)begin
			reg_small_ingress <= {flag_small_accept, flag_small_accept && reg_row_tags[3], reg_vector_data[41:0], reg_vector_data[185:144]}; // 行尾资格在入口合并，后级不再串接模式译码。
		end
	end

	// 实际两列提交更新上一核列贡献。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_previous <= 42'sd0;             // 旧扫描列贡献立即作废。
		end else if(i_ce == 1'b1 && reg_small_ingress[85])begin
			reg_previous <= reg_small_ingress[83:42]; // 每次真实提交保存K0/K3新贡献。
		end
	end

	// 行末清下一行填充资格，末点仍使用沿前历史项。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_small_filled <= 1'b0;          // 新行必须先填入一个历史列。
		end else if(i_ce == 1'b1 && reg_small_ingress[85])begin
			flag_small_filled <= !reg_small_ingress[84]; // 行末输出后清除下一行填充资格。
		end
	end

	// 两列历史与当前点积相加后寄存。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_small_result <= 43'sd0;         // 在途两列结果在非时钟沿清零。
		end else begin
			case(small_control)
				3'b111:begin
					reg_small_result <= small_sum[42:0]; // 合法tile结果保留43位，读取的是提交前旧贡献。
				end
				default:begin
					reg_small_result <= reg_small_result; // 首列填充不改变两列完成点。
				end
			endcase
		end
	end

	// 完成资格与两列结果同拍产生。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_small_valid <= 1'b0;           // 非沿复位撤销两列输出。
		end else if(i_ce == 1'b1)begin
			flag_small_valid <= reg_small_ingress[85] && flag_small_filled; // 标签对应本沿更新的完整两列结果。
		end
	end

	// 独立lane数据和valid共享末级推进。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_bypass_valid <= 1'b0;          // 非沿复位撤销旁路结果资格。
		end else if(i_ce == 1'b1)begin
			flag_bypass_valid <= flag_vector_first_valid && flag_bypass; // 旁路结果和valid共享最后使能边界。
		end
	end

	//--------------模块实例化区域--------------//
	// 零三六列垂直预加与深度累加。
	column_acc column_acc_first_Inst(           // 零三六列垂直预加与深度累加。
		.i_clk(i_clk),                          // 零三六列：列流水在统一时钟上推进。
		.i_rstn(i_rstn),                        // 零三六列：清该列mask、预加及深度累加。
		.i_ce(i_ce),                            // 零三六列：冻结列数据与完成资格。
		.i_mac_valid(i_in_valid),               // 零三六列：三路MAC乘积和同时有效。
		.i_mac_data(reg_column_first),          // 零三六列：按下中上顺序拼接first列三项。
		.i_row_mask(flag_mask_active),          // 零三六列：两列任务只保留核内的上中行。
		.i_bypass(flag_bypass),                 // 零三六列：独立lane任务不做垂直预加。
		.i_first(i_first),                      // 零三六列：首通道对覆盖历史tile部分和。
		.i_last(i_last),                        // 零三六列：末通道对产生完整列点积。
		.o_ready(flag_vector_first_ready),      // 零三六列：恢复首沿建立该列接受资格。
		.o_valid(flag_vector_first_valid),      // 零三六列：末对四级后输出完成标签。
		.o_data(reg_vector_first_data)          // 零三六列：空间低lane或旁路三lane结果。
	);

	// 一四七组保留中央核列贡献。
	column_acc column_acc_middle_Inst(          // 一四七组保留中央核列贡献。
		.i_clk(i_clk),                          // 一四七组：列流水在统一时钟上推进。
		.i_rstn(i_rstn),                        // 一四七组：清该列mask、预加及深度累加。
		.i_ce(i_ce),                            // 一四七组：冻结列数据与完成资格。
		.i_mac_valid(i_in_valid),               // 一四七组：三路MAC乘积和同时有效。
		.i_mac_data(reg_column_middle),         // 一四七组：按下中上顺序拼接middle列三项。
		.i_row_mask(flag_mask_active),          // 一四七组：两列任务只保留核内的上中行。
		.i_bypass(flag_bypass),                 // 一四七组：独立lane任务不做垂直预加。
		.i_first(i_first),                      // 一四七组：首通道对覆盖历史tile部分和。
		.i_last(i_last),                        // 一四七组：末通道对产生完整列点积。
		.o_ready(flag_vector_middle_ready),     // 一四七组：恢复首沿建立该列接受资格。
		.o_valid(flag_vector_middle_valid),     // 一四七组：末对四级后输出完成标签。
		.o_data(reg_vector_middle_data)         // 一四七组：空间低lane或旁路三lane结果。
	);

	// 二五八路汇聚末核列三行值。
	column_acc column_acc_last_Inst(            // 二五八路汇聚末核列三行值。
		.i_clk(i_clk),                          // 二五八路：列流水在统一时钟上推进。
		.i_rstn(i_rstn),                        // 二五八路：清该列mask、预加及深度累加。
		.i_ce(i_ce),                            // 二五八路：冻结列数据与完成资格。
		.i_mac_valid(i_in_valid),               // 二五八路：三路MAC乘积和同时有效。
		.i_mac_data(reg_column_last),           // 二五八路：按下中上顺序拼接last列三项。
		.i_row_mask(flag_mask_last),            // 二五八路：两列任务只保留核内的上中行。
		.i_bypass(flag_bypass),                 // 二五八路：独立lane任务不做垂直预加。
		.i_first(i_first),                      // 二五八路：首通道对覆盖历史tile部分和。
		.i_last(i_last),                        // 二五八路：末通道对产生完整列点积。
		.o_ready(flag_vector_last_ready),       // 二五八路：恢复首沿建立该列接受资格。
		.o_valid(flag_vector_last_valid),       // 二五八路：末对四级后输出完成标签。
		.o_data(reg_vector_last_data)           // 二五八路：空间低lane或旁路三lane结果。
	);

	// 三列缓存自带输入、历史选择、预加及完整点四级流水。
	ksp1_cache ksp1_cache_Inst(                 // 三列滑动复用及四级完整点生成。
		.i_clk(i_clk),                          // KsP1缓存与列累加同域运行。
		.i_rstn(i_rstn),                        // 三列9槽与结果流水异步清空。
		.i_ce(i_ce),                            // 全局暂停冻结缓存全部寄存边界。
		.i_column_valid(flag_spatial_accept),   // 仅三列任务提交完整列点积。
		.i_column_data(reg_spatial_data),       // 三组空间低lane按258/147/036拼接。
		.i_row_last(flag_spatial_row_last),     // B1末级行尾进入B2同一输入寄存。
		.o_ready(flag_cache_ready),             // 本封装无独立缓存反压，共享ce。
		.o_column_commit(flag_cache_commit),    // 实际三列写槽事件进入统一事件合并。
		.o_row_advance(flag_cache_row),         // 扫描行末真实写入通知物理bank控制。
		.o_valid(flag_cache_valid),             // 四级B2完成点有效标签。
		.o_data(cache_data)                     // 完整三列结果供空间低lane输出。
	);

endmodule
