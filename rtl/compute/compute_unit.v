`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/07 21:56:20
// Design Name:     compute_unit
// Module Name:     compute_unit
// Description:     description/compute_unit_Design.pdf
// Simulations:     testbench/vivado/2021.1/compute_unit
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
// 设计名称:        compute_unit
// 模块名称:        compute_unit
// 模块说明:        Description/compute_unit_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/compute_unit
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

module compute_unit
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 同域计算时钟。
	input i_rstn,                               // 低有效异步复位，由上游统一同步释放。

	//-----------------用户接口-----------------//
	input i_ce,                                 // MAC、控制标签及累加共同推进。
	input i_in_valid,                           // 当前完整通道对有效。
	input i_first,                              // tile向量首对。
	input i_last,                               // tile向量末对。
	input i_row_last,                           // 末向量属于扫描行尾。
	input [1:0]i_mode,                          // 任务固定00/01/10/11，切换需复位。
	input [95:0]i_feature_data,                 // 三行各打包两个INT16，行选择由上游完成。
	input [287:0]i_weight_data,                 // 低到高K0至K8的私有INT16对。
	output o_ready,                             // 首个恢复时钟后且ce允许时接受输入。
	output o_valid,                             // 与O0或九lane结果同步的有效标志。
	output signed [47:0]o_zero,                 // 空间模式的signed48完整点。
	output [143:0]o_one,                        // K0/K3/K6三个独立深度点积。
	output [143:0]o_two,                        // 第二核列按中上、中行、中下排列的48位值。
	output [143:0]o_three,                      // 末核列保留右上、右中与右下三路结果。
	output o_column_commit,                     // 缓存实际列写入事件，按沿前值消费。
	output o_row_advance                        // 物理bank轮换事件，只对应真实行末提交。
);

	//----------------寄存器信号----------------//
	//MAC核连接--用户接口
	wire [296:0]reg_mac_data;                   // 九个33位双乘积和，保持核位置顺序。
	reg [2:0]reg_tags_first = 3'd0;             // 与MAC乘积同拍锁存的first/last/row_last。
	reg [2:0]reg_tags_second = 3'd0;            // 与MAC双乘积和同拍到达列入口。
	wire signed [32:0]reg_mac_top_left_data;    // 左上双乘积进入首核列的上方贡献。
	wire signed [32:0]reg_mac_top_middle_data;  // 上排中央点积提供第二列第一项。
	wire signed [32:0]reg_mac_top_right_data;   // 右上角权重形成末核列顶部值。
	wire signed [32:0]reg_mac_middle_left_data; // 中行左核对应垂直预加的中间项。
	wire signed [32:0]reg_mac_middle_center_data; // 中心卷积位置送出本列当前通道和。
	wire signed [32:0]reg_mac_middle_right_data; // 中排右侧乘法连接第三组预累加。
	wire signed [32:0]reg_mac_bottom_left_data; // 左下计算值补齐零三六组最后输入。
	wire signed [32:0]reg_mac_bottom_middle_data; // 底部中央核提供一四七的第三项。
	wire signed [32:0]reg_mac_bottom_right_data; // 右下角双乘积结束二五八垂直组合。

	//-----------------标志信号-----------------//
	wire [8:0]flag_mac_valid;                   // 各MAC的两级有效标签。
	wire flag_accepted;                         // valid与ready共同满足的输入通道对。
	wire flag_mac_top_left_valid;               // 首核完成标签代表九路共同到达。
	wire flag_mac_top_middle_valid;             // 上方中核的资格随中央乘积对齐。
	wire flag_mac_top_right_valid;              // 右上数据标签记录末组顶部完成。
	wire flag_mac_middle_left_valid;            // 左侧中行产生与预加项一致的标记。
	wire flag_mac_middle_center_valid;          // 中心MAC完成位追踪独占权重运算。
	wire flag_mac_middle_right_valid;           // 中右核的结果资格纳入末列核对。
	wire flag_mac_bottom_left_valid;            // 下排左侧有效位对应底行乘法结束。
	wire flag_mac_bottom_middle_valid;          // 底部中核用标签标识第三项更新。
	wire flag_mac_bottom_right_valid;           // 右下完成通知保存九路标签最高位。
	wire flag_input_first;                      // tile起始标签与MAC第二级完成沿对齐。
	wire flag_input_last;                       // 末通道对资格通知列累加输出完整点。
	wire flag_input_row_last;                   // 扫描行结束标识跟随窗口最后输入。

	//-----------------其他信号-----------------//
	// 输入接受的原始握手字段
	wire [1:0]transfer_control;                 // 同拍valid和ready两个必要条件。

	//-----------------输出信号-----------------//
	//用户接口
	wire ready_o;                               // 三组累加的恢复资格，由共同复位建立。
	wire valid_o;                               // 累加器的已寄存结果资格。
	wire signed [47:0]zero_o;                   // 转发空间点积，不引入跨MAC算术。
	wire [143:0]one_o;                          // 第一核列独立三lane结果。
	wire [143:0]two_o;                          // 第二核列独立三lane结果。
	wire [143:0]three_o;                        // 第三核列独立三lane结果。
	wire column_commit_o;                       // 转发真实缓存提交事件。
	wire row_advance_o;                         // 转发实际行末提交事件。
	wire [31:0]feature_top_data_o;              // 逻辑上行的双通道特征送往首排三个MAC。
	wire [31:0]feature_middle_data_o;           // 中间像素行在同一时刻广播给中央核。
	wire [31:0]feature_bottom_data_o;           // 底部输入对供最后一排乘法使用。
	wire [31:0]weight_top_left_data_o;          // 左上位置独占输入权重的最低通道对。
	wire [31:0]weight_top_middle_data_o;        // 上方中央核读取紧随首对的系数。
	wire [31:0]weight_top_right_data_o;         // 右上乘法使用首行末尾的权重组。
	wire [31:0]weight_middle_left_data_o;       // 左侧中核取得第二行起始系数。
	wire [31:0]weight_middle_center_data_o;     // 中心位置的低高通道权重成对送入。
	wire [31:0]weight_middle_right_data_o;      // 中行右侧核读取本行最后两项系数。
	wire [31:0]weight_bottom_left_data_o;       // 下方左核使用底行首位置权重。
	wire [31:0]weight_bottom_middle_data_o;     // 底部中央取倒数第二份私有系数。
	wire [31:0]weight_bottom_right_data_o;      // 右下角消耗权重总线最高双通道。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign feature_top_data_o = i_feature_data[31:0]; // 提取首行像素对，支持三个顶部权重共享特征。
	assign feature_middle_data_o = i_feature_data[63:32]; // 总线中央32位对应中行两个输入通道。
	assign feature_bottom_data_o = i_feature_data[95:64]; // 高位像素对连接核窗口的底部逻辑行。
	assign weight_top_left_data_o = i_weight_data[31:0]; // 最低权重对连接窗口的第一个乘法入口。
	assign weight_top_middle_data_o = i_weight_data[63:32]; // 中央上核以私有系数区别相邻两列。
	assign weight_top_right_data_o = i_weight_data[95:64]; // 第一排右侧参数从打包权重前段分离。
	assign weight_middle_left_data_o = i_weight_data[127:96]; // 中排起点的系数按双通道顺序转发。
	assign weight_middle_center_data_o = i_weight_data[159:128]; // 总线中段提取中心卷积核输入。
	assign weight_middle_right_data_o = i_weight_data[191:160]; // 第二排末位置保留两份独占乘数。
	assign weight_bottom_left_data_o = i_weight_data[223:192]; // 第三排起始参数切到左下计算端。
	assign weight_bottom_middle_data_o = i_weight_data[255:224]; // 倒数第二组权重传递到下方中点。
	assign weight_bottom_right_data_o = i_weight_data[287:256]; // 最高打包段作为右下核系数来源。
	assign reg_mac_data[32:0] = reg_mac_top_left_data; // 最低33位保留零号核的二乘积结果。
	assign reg_mac_data[65:33] = reg_mac_top_middle_data; // 次低片段装入顶部第二路计算值。
	assign reg_mac_data[98:66] = reg_mac_top_right_data; // 首行末项落到第三个MAC数据槽。
	assign reg_mac_data[131:99] = reg_mac_middle_left_data; // 中左乘积写入打包总线第二行起点。
	assign reg_mac_data[164:132] = reg_mac_middle_center_data; // 中央点的通道和占据聚合向量中段。
	assign reg_mac_data[197:165] = reg_mac_middle_right_data; // 中右贡献接在中心值之后供末列取用。
	assign reg_mac_data[230:198] = reg_mac_bottom_left_data; // 底行第一路按核序填入靠高数据区。
	assign reg_mac_data[263:231] = reg_mac_bottom_middle_data; // 下方中点承接第八份有符号结果。
	assign reg_mac_data[296:264] = reg_mac_bottom_right_data; // 总线顶端保存窗口右下的最终项。
	assign flag_mac_valid[0] = flag_mac_top_left_valid; // 有效总线最低位来自第一个乘法单元。
	assign flag_mac_valid[1] = flag_mac_top_middle_valid; // 第二个核完成状态归入顶部标签组。
	assign flag_mac_valid[2] = flag_mac_top_right_valid; // 首排结束资格放在低三位的末端。
	assign flag_mac_valid[3] = flag_mac_middle_left_valid; // 中间排首位置更新第四份有效记录。
	assign flag_mac_valid[4] = flag_mac_middle_center_valid; // 中心计算的完成标记占据状态向量中央。
	assign flag_mac_valid[5] = flag_mac_middle_right_valid; // 中右标签紧随中央核的有效信息。
	assign flag_mac_valid[6] = flag_mac_bottom_left_valid; // 底部左核完成位加入最后一排状态。
	assign flag_mac_valid[7] = flag_mac_bottom_middle_valid; // 第八路乘法到达记录排列在高位组。
	assign flag_mac_valid[8] = flag_mac_bottom_right_valid; // 标签最高位对应最后一份双乘积。
	assign flag_input_first = reg_tags_second[0]; // 首通道对标记控制覆盖旧累加值。
	assign flag_input_last = reg_tags_second[1]; // 向量结束位触发深度求和的完成流水。
	assign flag_input_row_last = reg_tags_second[2]; // 传递行尾通知，缓存据此重新建立填充资格。
	assign transfer_control = {i_in_valid, o_ready}; // 输入标签与恢复后许可共同参与握手。
	assign flag_accepted = &transfer_control;   // 两个握手条件同时成立才产生有效MAC输入。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_ready = ready_o;                   // 同域释放后的运行资格与全局推进。
	assign o_valid = valid_o;                   // 输出有效桥接。
	assign o_zero = zero_o;                     // 空间结果保持48位补码。
	assign o_one = one_o;                       // 独立点积不重排核位置。
	assign o_two = two_o;                       // 第二核列结果直接连接。
	assign o_three = three_o;                   // 第三核列结果直接连接。
	assign o_column_commit = column_commit_o;   // 下游在实际写入沿消费事件。
	assign o_row_advance = row_advance_o;       // bank控制与该事件同步。

	//-------------主要任务处理区域-------------//
	// 首级控制标签仅随实际接受的通道对锁存。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_tags_first <= 3'd0;             // 清除尚未随乘积推进的首末标签。
		end else if(i_ce == 1'b1)begin
			reg_tags_first <= flag_accepted ? {i_row_last, i_last, i_first} : 3'd0; // 气泡和恢复沿不携带任务标签。
		end
	end

	// 第二级标签与MAC求和输出共同推进，硬复位立即取消。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_tags_second <= 3'd0;            // 立即清除到达列入口的旧标签。
		end else if(i_ce == 1'b1)begin
			reg_tags_second <= reg_tags_first;  // 标签共享MAC的第二级使能边界。
		end
	end

	//--------------模块实例化区域--------------//
	// 左上双乘积供首核列点积。
	packed_mac packed_mac_top_left_Inst(        // 左上双乘积供首核列点积。
		.i_clk(i_clk),                          // 首行左核：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 首行左核：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 首行左核：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 首行左核：握手成立后标记本通道对。
		.i_feature_data(feature_top_data_o),    // 首行左核：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_top_left_data_o), // 首行左核：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_top_left_valid),  // 首行左核：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_top_left_data)      // 首行左核：完整33位结果写入对应核位置。
	);

	// 上排中央权重产生中核列贡献。
	packed_mac packed_mac_top_middle_Inst(      // 上排中央权重产生中核列贡献。
		.i_clk(i_clk),                          // 上排中点：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 上排中点：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 上排中点：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 上排中点：握手成立后标记本通道对。
		.i_feature_data(feature_top_data_o),    // 上排中点：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_top_middle_data_o), // 上排中点：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_top_middle_valid), // 上排中点：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_top_middle_data)    // 上排中点：完整33位结果写入对应核位置。
	);

	// 右上核乘法送往第三组预加。
	packed_mac packed_mac_top_right_Inst(       // 右上核乘法送往第三组预加。
		.i_clk(i_clk),                          // 右上位置：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 右上位置：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 右上位置：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 右上位置：握手成立后标记本通道对。
		.i_feature_data(feature_top_data_o),    // 右上位置：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_top_right_data_o), // 右上位置：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_top_right_valid), // 右上位置：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_top_right_data)     // 右上位置：完整33位结果写入对应核位置。
	);

	// 中行左侧两乘积进入036列。
	packed_mac packed_mac_middle_left_Inst(     // 中行左侧两乘积进入036列。
		.i_clk(i_clk),                          // 中央行左侧：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 中央行左侧：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 中央行左侧：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 中央行左侧：握手成立后标记本通道对。
		.i_feature_data(feature_middle_data_o), // 中央行左侧：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_middle_left_data_o), // 中央行左侧：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_middle_left_valid), // 中央行左侧：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_middle_left_data)   // 中央行左侧：完整33位结果写入对应核位置。
	);

	// 中心核处理当前逻辑中间行。
	packed_mac packed_mac_middle_center_Inst(   // 中心核处理当前逻辑中间行。
		.i_clk(i_clk),                          // 中心卷积点：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 中心卷积点：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 中心卷积点：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 中心卷积点：握手成立后标记本通道对。
		.i_feature_data(feature_middle_data_o), // 中心卷积点：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_middle_center_data_o), // 中心卷积点：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_middle_center_valid), // 中心卷积点：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_middle_center_data) // 中心卷积点：完整33位结果写入对应核位置。
	);

	// 中排右核提供258中央贡献。
	packed_mac packed_mac_middle_right_Inst(    // 中排右核提供258中央贡献。
		.i_clk(i_clk),                          // 中排右核：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 中排右核：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 中排右核：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 中排右核：握手成立后标记本通道对。
		.i_feature_data(feature_middle_data_o), // 中排右核：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_middle_right_data_o), // 中排右核：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_middle_right_valid), // 中排右核：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_middle_right_data)  // 中排右核：完整33位结果写入对应核位置。
	);

	// 左下核计算首列最后垂直项。
	packed_mac packed_mac_bottom_left_Inst(     // 左下核计算首列最后垂直项。
		.i_clk(i_clk),                          // 末行左端：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 末行左端：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 末行左端：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 末行左端：握手成立后标记本通道对。
		.i_feature_data(feature_bottom_data_o), // 末行左端：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_bottom_left_data_o), // 末行左端：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_bottom_left_valid), // 末行左端：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_bottom_left_data)   // 末行左端：完整33位结果写入对应核位置。
	);

	// 底部中核形成147下行乘积。
	packed_mac packed_mac_bottom_middle_Inst(   // 底部中核形成147下行乘积。
		.i_clk(i_clk),                          // 底部中核：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 底部中核：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 底部中核：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 底部中核：握手成立后标记本通道对。
		.i_feature_data(feature_bottom_data_o), // 底部中核：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_bottom_middle_data_o), // 底部中核：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_bottom_middle_valid), // 底部中核：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_bottom_middle_data) // 底部中核：完整33位结果写入对应核位置。
	);

	// 右下角核送出最后一项乘积和。
	packed_mac packed_mac_bottom_right_Inst(    // 右下角核送出最后一项乘积和。
		.i_clk(i_clk),                          // 右下角核：当前核位置使用同域计算时钟。
		.i_rstn(i_rstn),                        // 右下角核：硬复位清除本路两级乘法状态。
		.i_ce(i_ce),                            // 右下角核：全局停顿同时冻结乘积和标签。
		.i_in_valid(flag_accepted),             // 右下角核：握手成立后标记本通道对。
		.i_feature_data(feature_bottom_data_o), // 右下角核：该核所在逻辑行的双通道特征。
		.i_weight_data(weight_bottom_right_data_o), // 右下角核：此核独占的低高两个INT16权重。
		.o_out_valid(flag_mac_bottom_right_valid), // 右下角核：两级输出标签对齐双乘积和。
		.o_out_data(reg_mac_bottom_right_data)  // 右下角核：完整33位结果写入对应核位置。
	);

	// 复用036/147/258列预加及KsP1缓存，不设置普通九路加法树。
	three_stage_acc three_stage_acc_Inst(       // 固定三个列组及空间缓存的完整累加封装。
		.i_clk(i_clk),                          // 三组累加沿用MAC计算时钟。
		.i_rstn(i_rstn),                        // 父子统一异步清空任务状态。
		.i_ce(i_ce),                            // 列累加与输入标签共享推进条件。
		.i_in_valid(flag_mac_top_left_valid),   // 九路同拍完成，取首核MAC有效标签。
		.i_first(flag_input_first),             // 首对标签与第二级MAC输出对齐。
		.i_last(flag_input_last),               // 向量末对触发B1点积完成。
		.i_row_last(flag_input_row_last),       // 行尾经过MAC两级后进入四级列流水。
		.i_mode(i_mode),                        // 任务期间固定的四模式选择。
		.i_mac_data(reg_mac_data),              // 按核位置拼接九个signed33乘积和。
		.o_ready(ready_o),                      // 三列恢复资格作为CU输入许可。
		.o_valid(valid_o),                      // 当前激活路径的结果标签。
		.o_zero(zero_o),                        // 空间卷积完整点直达CU低48位。
		.o_one(one_o),                          // 第一核列独立三lane连接O1。
		.o_two(two_o),                          // 中间核列深度点积连接O2。
		.o_three(three_o),                      // 最后核列旁路向量连接O3。
		.o_column_commit(column_commit_o),      // 转发实际写槽时刻给控制器。
		.o_row_advance(row_advance_o)           // 转发末列写入事件以轮换bank。
	);

endmodule
