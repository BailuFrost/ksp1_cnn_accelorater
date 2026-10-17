`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/08 10:21:03
// Design Name:     compute_array
// Module Name:     compute_array
// Description:     description/compute_array_Design.pdf
// Simulations:     testbench/vivado/2021.1/compute_array
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/08 10:21:03
// History:
// Time             Version     Revised by        Contents
// 2026/10/08       V1.0        Erie              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月08日
// 设计名称:        compute_array
// 模块名称:        compute_array
// 模块说明:        Description/compute_array_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/compute_array
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

module compute_array
(
	//-----------------全局信号-----------------//
	input i_clk,                                // FCLK_CLK0域统一计算时钟。
	input i_rstn,                               // 低有效异步复位，上游统一同步释放。

	//-----------------用户接口-----------------//
	input i_ce,                                 // 同步冻结八份完整CU。
	input i_in_valid,                           // 本拍完整输入通道对有效。
	input i_first,                              // tile的首通道对标签。
	input i_last,                               // 深度向量末通道对标志。
	input i_row_last,                           // 扫描末列的真实行结束标签。
	input [1:0]i_mode,                          // 固定任务类别，切换必须重新复位。
	input [95:0]i_feature_data,                 // 三行共享的双INT16特征。
	input [2303:0]i_weight_data,                // 八份私有288位核参数，低位为CU0。
	output o_ready,                             // 锁步CU共享运行资格，首CU代表共同许可。
	output [7:0]o_cu_valid,                     // 每个计算单元的完成标签。
	output [383:0]o_zero,                       // 八个空间48位点积。
	output [1151:0]o_one,                       // 所有CU第一核列的三lane结果。
	output [1151:0]o_two,                       // 每份中央核列的独立点积组。
	output [1151:0]o_three,                     // 末核列向量按CU编号聚合。
	output [7:0]o_column_commit,                // 八个实际缓存列提交事件。
	output [7:0]o_row_advance                   // 共同扫描行末的bank轮换通知。
);

	//-----------------标志信号-----------------//
	wire flag_second_ready;                     // 次序靠前的恢复输入资格。
	wire flag_third_ready;                      // 前三末端的恢复输入资格。
	wire flag_fourth_ready;                     // 第二组三核入口的恢复输入资格。
	wire flag_fifth_ready;                      // 低半中央的恢复输入资格。
	wire flag_sixth_ready;                      // 左半末尾的恢复输入资格。
	wire flag_seventh_ready;                    // 右半起始位置的恢复输入资格。
	wire flag_eighth_ready;                     // 高段中部的恢复输入资格。
	wire flag_first_valid;                      // 阵列起点的完整结果标志。
	wire flag_second_valid;                     // 次序靠前的完整结果标志。
	wire flag_third_valid;                      // 前三末端的完整结果标志。
	wire flag_fourth_valid;                     // 第二组三核入口的完整结果标志。
	wire flag_fifth_valid;                      // 低半中央的完整结果标志。
	wire flag_sixth_valid;                      // 左半末尾的完整结果标志。
	wire flag_seventh_valid;                    // 右半起始位置的完整结果标志。
	wire flag_eighth_valid;                     // 高段中部的完整结果标志。
	wire flag_first_commit;                     // 阵列起点的真实缓存写入。
	wire flag_second_commit;                    // 次序靠前的真实缓存写入。
	wire flag_third_commit;                     // 前三末端的真实缓存写入。
	wire flag_fourth_commit;                    // 第二组三核入口的真实缓存写入。
	wire flag_fifth_commit;                     // 低半中央的真实缓存写入。
	wire flag_sixth_commit;                     // 左半末尾的真实缓存写入。
	wire flag_seventh_commit;                   // 右半起始位置的真实缓存写入。
	wire flag_eighth_commit;                    // 高段中部的真实缓存写入。
	wire flag_first_advance;                    // 阵列起点的末列轮换通知。
	wire flag_second_advance;                   // 次序靠前的末列轮换通知。
	wire flag_third_advance;                    // 前三末端的末列轮换通知。
	wire flag_fourth_advance;                   // 第二组三核入口的末列轮换通知。
	wire flag_fifth_advance;                    // 低半中央的末列轮换通知。
	wire flag_sixth_advance;                    // 左半末尾的末列轮换通知。
	wire flag_seventh_advance;                  // 右半起始位置的末列轮换通知。
	wire flag_eighth_advance;                   // 高段中部的末列轮换通知。

	//-----------------其他信号-----------------//
	//权重聚合入口
	wire [2303:0]wire_weight_bus;               // 未拆分的整阵列私有参数总线。

	//-----------------输出信号-----------------//
	//用户接口
	wire ready_o;                               // 首核恢复完成后的共同输入资格。
	wire [7:0]cu_valid_o;                       // 所有CU完成状态聚合。
	wire [383:0]zero_o;                         // 八份空间点积桥接。
	wire [1151:0]one_o;                         // 第一核列独立向量总线。
	wire [1151:0]two_o;                         // 中间核列完整结果集合。
	wire [1151:0]three_o;                       // 末列点积分组输出。
	wire [7:0]column_commit_o;                  // 缓存实际提交状态。
	wire [7:0]row_advance_o;                    // 扫描末列通知打包。
	wire [287:0]weight_first_o;                 // 阵列起点私有双通道权重。
	wire [287:0]weight_second_o;                // 次序靠前私有双通道权重。
	wire [287:0]weight_third_o;                 // 前三末端私有双通道权重。
	wire [287:0]weight_fourth_o;                // 第二组三核入口私有双通道权重。
	wire [287:0]weight_fifth_o;                 // 低半中央私有双通道权重。
	wire [287:0]weight_sixth_o;                 // 左半末尾私有双通道权重。
	wire [287:0]weight_seventh_o;               // 右半起始位置私有双通道权重。
	wire [287:0]weight_eighth_o;                // 高段中部私有双通道权重。
	wire [47:0]cu_first_zero_o;                 // 阵列起点的空间点积端。
	wire [47:0]cu_second_zero_o;                // 次序靠前的空间点积端。
	wire [47:0]cu_third_zero_o;                 // 前三末端的空间点积端。
	wire [47:0]cu_fourth_zero_o;                // 第二组三核入口的空间点积端。
	wire [47:0]cu_fifth_zero_o;                 // 低半中央的空间点积端。
	wire [47:0]cu_sixth_zero_o;                 // 左半末尾的空间点积端。
	wire [47:0]cu_seventh_zero_o;               // 右半起始位置的空间点积端。
	wire [47:0]cu_eighth_zero_o;                // 高段中部的空间点积端。
	wire [143:0]cu_first_one_o;                 // 阵列起点的首核列向量。
	wire [143:0]cu_second_one_o;                // 次序靠前的首核列向量。
	wire [143:0]cu_third_one_o;                 // 前三末端的首核列向量。
	wire [143:0]cu_fourth_one_o;                // 第二组三核入口的首核列向量。
	wire [143:0]cu_fifth_one_o;                 // 低半中央的首核列向量。
	wire [143:0]cu_sixth_one_o;                 // 左半末尾的首核列向量。
	wire [143:0]cu_seventh_one_o;               // 右半起始位置的首核列向量。
	wire [143:0]cu_eighth_one_o;                // 高段中部的首核列向量。
	wire [143:0]cu_first_two_o;                 // 阵列起点的中央核列结果。
	wire [143:0]cu_second_two_o;                // 次序靠前的中央核列结果。
	wire [143:0]cu_third_two_o;                 // 前三末端的中央核列结果。
	wire [143:0]cu_fourth_two_o;                // 第二组三核入口的中央核列结果。
	wire [143:0]cu_fifth_two_o;                 // 低半中央的中央核列结果。
	wire [143:0]cu_sixth_two_o;                 // 左半末尾的中央核列结果。
	wire [143:0]cu_seventh_two_o;               // 右半起始位置的中央核列结果。
	wire [143:0]cu_eighth_two_o;                // 高段中部的中央核列结果。
	wire [143:0]cu_first_three_o;               // 阵列起点的末核列补码组。
	wire [143:0]cu_second_three_o;              // 次序靠前的末核列补码组。
	wire [143:0]cu_third_three_o;               // 前三末端的末核列补码组。
	wire [143:0]cu_fourth_three_o;              // 第二组三核入口的末核列补码组。
	wire [143:0]cu_fifth_three_o;               // 低半中央的末核列补码组。
	wire [143:0]cu_sixth_three_o;               // 左半末尾的末核列补码组。
	wire [143:0]cu_seventh_three_o;             // 右半起始位置的末核列补码组。
	wire [143:0]cu_eighth_three_o;              // 高段中部的末核列补码组。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign wire_weight_bus = i_weight_data;     // 宿主打包参数保持CU索引顺序。
	assign row_advance_o[0] = flag_first_advance; // 阵列起点行结束通知接往本核。
	assign row_advance_o[1] = flag_second_advance; // 次序靠前行结束通知接往本核。
	assign row_advance_o[2] = flag_third_advance; // 前三末端行结束通知接往本核。
	assign row_advance_o[3] = flag_fourth_advance; // 第二组三核入口行结束通知接往本核。
	assign row_advance_o[4] = flag_fifth_advance; // 低半中央行结束通知接往本核。
	assign row_advance_o[5] = flag_sixth_advance; // 左半末尾行结束通知接往本核。
	assign row_advance_o[6] = flag_seventh_advance; // 右半起始位置行结束通知接往本核。
	assign row_advance_o[7] = flag_eighth_advance; // 高段中部行结束通知接往本核。
	assign column_commit_o[0] = flag_first_commit; // 阵列起点写入事件归入固定索引。
	assign column_commit_o[1] = flag_second_commit; // 次序靠前写入事件归入固定索引。
	assign column_commit_o[2] = flag_third_commit; // 前三末端写入事件归入固定索引。
	assign column_commit_o[3] = flag_fourth_commit; // 第二组三核入口写入事件归入固定索引。
	assign column_commit_o[4] = flag_fifth_commit; // 低半中央写入事件归入固定索引。
	assign column_commit_o[5] = flag_sixth_commit; // 左半末尾写入事件归入固定索引。
	assign column_commit_o[6] = flag_seventh_commit; // 右半起始位置写入事件归入固定索引。
	assign column_commit_o[7] = flag_eighth_commit; // 高段中部写入事件归入固定索引。
	assign cu_valid_o[0] = flag_first_valid;    // 阵列起点结果标签映射到对应bit。
	assign cu_valid_o[1] = flag_second_valid;   // 次序靠前结果标签映射到对应bit。
	assign cu_valid_o[2] = flag_third_valid;    // 前三末端结果标签映射到对应bit。
	assign cu_valid_o[3] = flag_fourth_valid;   // 第二组三核入口结果标签映射到对应bit。
	assign cu_valid_o[4] = flag_fifth_valid;    // 低半中央结果标签映射到对应bit。
	assign cu_valid_o[5] = flag_sixth_valid;    // 左半末尾结果标签映射到对应bit。
	assign cu_valid_o[6] = flag_seventh_valid;  // 右半起始位置结果标签映射到对应bit。
	assign cu_valid_o[7] = flag_eighth_valid;   // 高段中部结果标签映射到对应bit。
	assign weight_first_o = wire_weight_bus[287:0]; // 阵列起点对应参数区切到完整端口。
	assign weight_second_o = wire_weight_bus[575:288]; // 次序靠前对应参数区切到完整端口。
	assign weight_third_o = wire_weight_bus[863:576]; // 前三末端对应参数区切到完整端口。
	assign weight_fourth_o = wire_weight_bus[1151:864]; // 第二组三核入口对应参数区切到完整端口。
	assign weight_fifth_o = wire_weight_bus[1439:1152]; // 低半中央对应参数区切到完整端口。
	assign weight_sixth_o = wire_weight_bus[1727:1440]; // 左半末尾对应参数区切到完整端口。
	assign weight_seventh_o = wire_weight_bus[2015:1728]; // 右半起始位置对应参数区切到完整端口。
	assign weight_eighth_o = wire_weight_bus[2303:2016]; // 高段中部对应参数区切到完整端口。
	assign zero_o[47:0] = cu_first_zero_o;      // 阵列起点空间点积端归入用户总线。
	assign zero_o[95:48] = cu_second_zero_o;    // 次序靠前空间点积端归入用户总线。
	assign zero_o[143:96] = cu_third_zero_o;    // 前三末端空间点积端归入用户总线。
	assign zero_o[191:144] = cu_fourth_zero_o;  // 第二组三核入口空间点积端归入用户总线。
	assign zero_o[239:192] = cu_fifth_zero_o;   // 低半中央空间点积端归入用户总线。
	assign zero_o[287:240] = cu_sixth_zero_o;   // 左半末尾空间点积端归入用户总线。
	assign zero_o[335:288] = cu_seventh_zero_o; // 右半起始位置空间点积端归入用户总线。
	assign zero_o[383:336] = cu_eighth_zero_o;  // 高段中部空间点积端归入用户总线。
	assign one_o[143:0] = cu_first_one_o;       // 阵列起点首核列向量归入用户总线。
	assign one_o[287:144] = cu_second_one_o;    // 次序靠前首核列向量归入用户总线。
	assign one_o[431:288] = cu_third_one_o;     // 前三末端首核列向量归入用户总线。
	assign one_o[575:432] = cu_fourth_one_o;    // 第二组三核入口首核列向量归入用户总线。
	assign one_o[719:576] = cu_fifth_one_o;     // 低半中央首核列向量归入用户总线。
	assign one_o[863:720] = cu_sixth_one_o;     // 左半末尾首核列向量归入用户总线。
	assign one_o[1007:864] = cu_seventh_one_o;  // 右半起始位置首核列向量归入用户总线。
	assign one_o[1151:1008] = cu_eighth_one_o;  // 高段中部首核列向量归入用户总线。
	assign two_o[143:0] = cu_first_two_o;       // 阵列起点中央核列结果归入用户总线。
	assign two_o[287:144] = cu_second_two_o;    // 次序靠前中央核列结果归入用户总线。
	assign two_o[431:288] = cu_third_two_o;     // 前三末端中央核列结果归入用户总线。
	assign two_o[575:432] = cu_fourth_two_o;    // 第二组三核入口中央核列结果归入用户总线。
	assign two_o[719:576] = cu_fifth_two_o;     // 低半中央中央核列结果归入用户总线。
	assign two_o[863:720] = cu_sixth_two_o;     // 左半末尾中央核列结果归入用户总线。
	assign two_o[1007:864] = cu_seventh_two_o;  // 右半起始位置中央核列结果归入用户总线。
	assign two_o[1151:1008] = cu_eighth_two_o;  // 高段中部中央核列结果归入用户总线。
	assign three_o[143:0] = cu_first_three_o;   // 阵列起点末核列补码组归入用户总线。
	assign three_o[287:144] = cu_second_three_o; // 次序靠前末核列补码组归入用户总线。
	assign three_o[431:288] = cu_third_three_o; // 前三末端末核列补码组归入用户总线。
	assign three_o[575:432] = cu_fourth_three_o; // 第二组三核入口末核列补码组归入用户总线。
	assign three_o[719:576] = cu_fifth_three_o; // 低半中央末核列补码组归入用户总线。
	assign three_o[863:720] = cu_sixth_three_o; // 左半末尾末核列补码组归入用户总线。
	assign three_o[1007:864] = cu_seventh_three_o; // 右半起始位置末核列补码组归入用户总线。
	assign three_o[1151:1008] = cu_eighth_three_o; // 高段中部末核列补码组归入用户总线。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_ready = ready_o;                   // 共同clk/rst/ce保证八CU许可相同，TB逐路检查。
	assign o_cu_valid[0] = cu_valid_o[0];       // 阵列起点完成资格单独引出。
	assign o_cu_valid[1] = cu_valid_o[1];       // 次序靠前完成资格单独引出。
	assign o_cu_valid[2] = cu_valid_o[2];       // 前三末端完成资格单独引出。
	assign o_cu_valid[3] = cu_valid_o[3];       // 第二组三核入口完成资格单独引出。
	assign o_cu_valid[4] = cu_valid_o[4];       // 低半中央完成资格单独引出。
	assign o_cu_valid[5] = cu_valid_o[5];       // 左半末尾完成资格单独引出。
	assign o_cu_valid[6] = cu_valid_o[6];       // 右半起始位置完成资格单独引出。
	assign o_cu_valid[7] = cu_valid_o[7];       // 高段中部完成资格单独引出。
	assign o_zero = zero_o;                     // 输出八份空间点积桥接。
	assign o_one = one_o;                       // 输出第一核列独立向量总线。
	assign o_two = two_o;                       // 输出中间核列完整结果集合。
	assign o_three = three_o;                   // 输出末列点积分组输出。
	assign o_column_commit[0] = column_commit_o[0]; // 阵列起点列缓存提交直接可见。
	assign o_column_commit[1] = column_commit_o[1]; // 次序靠前列缓存提交直接可见。
	assign o_column_commit[2] = column_commit_o[2]; // 前三末端列缓存提交直接可见。
	assign o_column_commit[3] = column_commit_o[3]; // 第二组三核入口列缓存提交直接可见。
	assign o_column_commit[4] = column_commit_o[4]; // 低半中央列缓存提交直接可见。
	assign o_column_commit[5] = column_commit_o[5]; // 左半末尾列缓存提交直接可见。
	assign o_column_commit[6] = column_commit_o[6]; // 右半起始位置列缓存提交直接可见。
	assign o_column_commit[7] = column_commit_o[7]; // 高段中部列缓存提交直接可见。
	assign o_row_advance[0] = row_advance_o[0]; // 阵列起点末列轮换事件保持私有。
	assign o_row_advance[1] = row_advance_o[1]; // 次序靠前末列轮换事件保持私有。
	assign o_row_advance[2] = row_advance_o[2]; // 前三末端末列轮换事件保持私有。
	assign o_row_advance[3] = row_advance_o[3]; // 第二组三核入口末列轮换事件保持私有。
	assign o_row_advance[4] = row_advance_o[4]; // 低半中央末列轮换事件保持私有。
	assign o_row_advance[5] = row_advance_o[5]; // 左半末尾末列轮换事件保持私有。
	assign o_row_advance[6] = row_advance_o[6]; // 右半起始位置末列轮换事件保持私有。
	assign o_row_advance[7] = row_advance_o[7]; // 高段中部末列轮换事件保持私有。

	//--------------模块实例化区域--------------//
	//首组承担最低空间点。
	// 阵列起点接入共享输入并保留私有乘法。
	compute_unit compute_unit_first_Inst(       // 阵列起点完整四模式计算。
		.i_clk(i_clk),                          // 阵列起点统一计算沿。
		.i_rstn(i_rstn),                        // 阵列起点撤销在途任务。
		.i_ce(i_ce),                            // 阵列起点冻结全数据通路。
		.i_in_valid(i_in_valid),                // 阵列起点接受共同通道对。
		.i_first(i_first),                      // 阵列起点覆盖tile旧累加。
		.i_last(i_last),                        // 阵列起点结束当前深度点。
		.i_row_last(i_row_last),                // 阵列起点标记扫描最后列。
		.i_mode(i_mode),                        // 阵列起点固定类别选择。
		.i_feature_data(i_feature_data),        // 阵列起点共享三行像素。
		.i_weight_data(weight_first_o),         // 阵列起点读取独占核参数。
		.o_ready(ready_o),                      // 阵列起点返回运行许可。
		.o_valid(flag_first_valid),             // 阵列起点产生输出资格。
		.o_zero(cu_first_zero_o),               // 阵列起点交付空间48位和。
		.o_one(cu_first_one_o),                 // 阵列起点保留零三六点积。
		.o_two(cu_first_two_o),                 // 阵列起点提供一四七贡献。
		.o_three(cu_first_three_o),             // 阵列起点输出二五八向量。
		.o_column_commit(flag_first_commit),    // 阵列起点报告实际列更新。
		.o_row_advance(flag_first_advance)      // 阵列起点通知行缓存切换。
	);

	//次组计算相邻输出通道。
	// 次序靠前接入共享输入并保留私有乘法。
	compute_unit compute_unit_second_Inst(      // 次序靠前完整四模式计算。
		.i_clk(i_clk),                          // 次序靠前统一计算沿。
		.i_rstn(i_rstn),                        // 次序靠前撤销在途任务。
		.i_ce(i_ce),                            // 次序靠前冻结全数据通路。
		.i_in_valid(i_in_valid),                // 次序靠前接受共同通道对。
		.i_first(i_first),                      // 次序靠前覆盖tile旧累加。
		.i_last(i_last),                        // 次序靠前结束当前深度点。
		.i_row_last(i_row_last),                // 次序靠前标记扫描最后列。
		.i_mode(i_mode),                        // 次序靠前固定类别选择。
		.i_feature_data(i_feature_data),        // 次序靠前共享三行像素。
		.i_weight_data(weight_second_o),        // 次序靠前读取独占核参数。
		.o_ready(flag_second_ready),            // 次序靠前返回运行许可。
		.o_valid(flag_second_valid),            // 次序靠前产生输出资格。
		.o_zero(cu_second_zero_o),              // 次序靠前交付空间48位和。
		.o_one(cu_second_one_o),                // 次序靠前保留零三六点积。
		.o_two(cu_second_two_o),                // 次序靠前提供一四七贡献。
		.o_three(cu_second_three_o),            // 次序靠前输出二五八向量。
		.o_column_commit(flag_second_commit),   // 次序靠前报告实际列更新。
		.o_row_advance(flag_second_advance)     // 次序靠前通知行缓存切换。
	);

	//第三组覆盖同一窗口的另一份核。
	// 前三末端接入共享输入并保留私有乘法。
	compute_unit compute_unit_third_Inst(       // 前三末端完整四模式计算。
		.i_clk(i_clk),                          // 前三末端统一计算沿。
		.i_rstn(i_rstn),                        // 前三末端撤销在途任务。
		.i_ce(i_ce),                            // 前三末端冻结全数据通路。
		.i_in_valid(i_in_valid),                // 前三末端接受共同通道对。
		.i_first(i_first),                      // 前三末端覆盖tile旧累加。
		.i_last(i_last),                        // 前三末端结束当前深度点。
		.i_row_last(i_row_last),                // 前三末端标记扫描最后列。
		.i_mode(i_mode),                        // 前三末端固定类别选择。
		.i_feature_data(i_feature_data),        // 前三末端共享三行像素。
		.i_weight_data(weight_third_o),         // 前三末端读取独占核参数。
		.o_ready(flag_third_ready),             // 前三末端返回运行许可。
		.o_valid(flag_third_valid),             // 前三末端产生输出资格。
		.o_zero(cu_third_zero_o),               // 前三末端交付空间48位和。
		.o_one(cu_third_one_o),                 // 前三末端保留零三六点积。
		.o_two(cu_third_two_o),                 // 前三末端提供一四七贡献。
		.o_three(cu_third_three_o),             // 前三末端输出二五八向量。
		.o_column_commit(flag_third_commit),    // 前三末端报告实际列更新。
		.o_row_advance(flag_third_advance)      // 前三末端通知行缓存切换。
	);

	//第四组独立处理本位置参数。
	// 第二组三核入口接入共享输入并保留私有乘法。
	compute_unit compute_unit_fourth_Inst(      // 第二组三核入口完整四模式计算。
		.i_clk(i_clk),                          // 第二组三核入口统一计算沿。
		.i_rstn(i_rstn),                        // 第二组三核入口撤销在途任务。
		.i_ce(i_ce),                            // 第二组三核入口冻结全数据通路。
		.i_in_valid(i_in_valid),                // 第二组三核入口接受共同通道对。
		.i_first(i_first),                      // 第二组三核入口覆盖tile旧累加。
		.i_last(i_last),                        // 第二组三核入口结束当前深度点。
		.i_row_last(i_row_last),                // 第二组三核入口标记扫描最后列。
		.i_mode(i_mode),                        // 第二组三核入口固定类别选择。
		.i_feature_data(i_feature_data),        // 第二组三核入口共享三行像素。
		.i_weight_data(weight_fourth_o),        // 第二组三核入口读取独占核参数。
		.o_ready(flag_fourth_ready),            // 第二组三核入口返回运行许可。
		.o_valid(flag_fourth_valid),            // 第二组三核入口产生输出资格。
		.o_zero(cu_fourth_zero_o),              // 第二组三核入口交付空间48位和。
		.o_one(cu_fourth_one_o),                // 第二组三核入口保留零三六点积。
		.o_two(cu_fourth_two_o),                // 第二组三核入口提供一四七贡献。
		.o_three(cu_fourth_three_o),            // 第二组三核入口输出二五八向量。
		.o_column_commit(flag_fourth_commit),   // 第二组三核入口报告实际列更新。
		.o_row_advance(flag_fourth_advance)     // 第二组三核入口通知行缓存切换。
	);

	//第五组追加空间输出深度。
	// 低半中央接入共享输入并保留私有乘法。
	compute_unit compute_unit_fifth_Inst(       // 低半中央完整四模式计算。
		.i_clk(i_clk),                          // 低半中央统一计算沿。
		.i_rstn(i_rstn),                        // 低半中央撤销在途任务。
		.i_ce(i_ce),                            // 低半中央冻结全数据通路。
		.i_in_valid(i_in_valid),                // 低半中央接受共同通道对。
		.i_first(i_first),                      // 低半中央覆盖tile旧累加。
		.i_last(i_last),                        // 低半中央结束当前深度点。
		.i_row_last(i_row_last),                // 低半中央标记扫描最后列。
		.i_mode(i_mode),                        // 低半中央固定类别选择。
		.i_feature_data(i_feature_data),        // 低半中央共享三行像素。
		.i_weight_data(weight_fifth_o),         // 低半中央读取独占核参数。
		.o_ready(flag_fifth_ready),             // 低半中央返回运行许可。
		.o_valid(flag_fifth_valid),             // 低半中央产生输出资格。
		.o_zero(cu_fifth_zero_o),               // 低半中央交付空间48位和。
		.o_one(cu_fifth_one_o),                 // 低半中央保留零三六点积。
		.o_two(cu_fifth_two_o),                 // 低半中央提供一四七贡献。
		.o_three(cu_fifth_three_o),             // 低半中央输出二五八向量。
		.o_column_commit(flag_fifth_commit),    // 低半中央报告实际列更新。
		.o_row_advance(flag_fifth_advance)      // 低半中央通知行缓存切换。
	);

	//第六组结束阵列前半通道。
	// 左半末尾接入共享输入并保留私有乘法。
	compute_unit compute_unit_sixth_Inst(       // 左半末尾完整四模式计算。
		.i_clk(i_clk),                          // 左半末尾统一计算沿。
		.i_rstn(i_rstn),                        // 左半末尾撤销在途任务。
		.i_ce(i_ce),                            // 左半末尾冻结全数据通路。
		.i_in_valid(i_in_valid),                // 左半末尾接受共同通道对。
		.i_first(i_first),                      // 左半末尾覆盖tile旧累加。
		.i_last(i_last),                        // 左半末尾结束当前深度点。
		.i_row_last(i_row_last),                // 左半末尾标记扫描最后列。
		.i_mode(i_mode),                        // 左半末尾固定类别选择。
		.i_feature_data(i_feature_data),        // 左半末尾共享三行像素。
		.i_weight_data(weight_sixth_o),         // 左半末尾读取独占核参数。
		.o_ready(flag_sixth_ready),             // 左半末尾返回运行许可。
		.o_valid(flag_sixth_valid),             // 左半末尾产生输出资格。
		.o_zero(cu_sixth_zero_o),               // 左半末尾交付空间48位和。
		.o_one(cu_sixth_one_o),                 // 左半末尾保留零三六点积。
		.o_two(cu_sixth_two_o),                 // 左半末尾提供一四七贡献。
		.o_three(cu_sixth_three_o),             // 左半末尾输出二五八向量。
		.o_column_commit(flag_sixth_commit),    // 左半末尾报告实际列更新。
		.o_row_advance(flag_sixth_advance)      // 左半末尾通知行缓存切换。
	);

	//第七组开启高位输出集合。
	// 右半起始位置接入共享输入并保留私有乘法。
	compute_unit compute_unit_seventh_Inst(     // 右半起始位置完整四模式计算。
		.i_clk(i_clk),                          // 右半起始位置统一计算沿。
		.i_rstn(i_rstn),                        // 右半起始位置撤销在途任务。
		.i_ce(i_ce),                            // 右半起始位置冻结全数据通路。
		.i_in_valid(i_in_valid),                // 右半起始位置接受共同通道对。
		.i_first(i_first),                      // 右半起始位置覆盖tile旧累加。
		.i_last(i_last),                        // 右半起始位置结束当前深度点。
		.i_row_last(i_row_last),                // 右半起始位置标记扫描最后列。
		.i_mode(i_mode),                        // 右半起始位置固定类别选择。
		.i_feature_data(i_feature_data),        // 右半起始位置共享三行像素。
		.i_weight_data(weight_seventh_o),       // 右半起始位置读取独占核参数。
		.o_ready(flag_seventh_ready),           // 右半起始位置返回运行许可。
		.o_valid(flag_seventh_valid),           // 右半起始位置产生输出资格。
		.o_zero(cu_seventh_zero_o),             // 右半起始位置交付空间48位和。
		.o_one(cu_seventh_one_o),               // 右半起始位置保留零三六点积。
		.o_two(cu_seventh_two_o),               // 右半起始位置提供一四七贡献。
		.o_three(cu_seventh_three_o),           // 右半起始位置输出二五八向量。
		.o_column_commit(flag_seventh_commit),  // 右半起始位置报告实际列更新。
		.o_row_advance(flag_seventh_advance)    // 右半起始位置通知行缓存切换。
	);

	//第八组占据后半核参数槽。
	// 高段中部接入共享输入并保留私有乘法。
	compute_unit compute_unit_eighth_Inst(      // 高段中部完整四模式计算。
		.i_clk(i_clk),                          // 高段中部统一计算沿。
		.i_rstn(i_rstn),                        // 高段中部撤销在途任务。
		.i_ce(i_ce),                            // 高段中部冻结全数据通路。
		.i_in_valid(i_in_valid),                // 高段中部接受共同通道对。
		.i_first(i_first),                      // 高段中部覆盖tile旧累加。
		.i_last(i_last),                        // 高段中部结束当前深度点。
		.i_row_last(i_row_last),                // 高段中部标记扫描最后列。
		.i_mode(i_mode),                        // 高段中部固定类别选择。
		.i_feature_data(i_feature_data),        // 高段中部共享三行像素。
		.i_weight_data(weight_eighth_o),        // 高段中部读取独占核参数。
		.o_ready(flag_eighth_ready),            // 高段中部返回运行许可。
		.o_valid(flag_eighth_valid),            // 高段中部产生输出资格。
		.o_zero(cu_eighth_zero_o),              // 高段中部交付空间48位和。
		.o_one(cu_eighth_one_o),                // 高段中部保留零三六点积。
		.o_two(cu_eighth_two_o),                // 高段中部提供一四七贡献。
		.o_three(cu_eighth_three_o),            // 高段中部输出二五八向量。
		.o_column_commit(flag_eighth_commit),   // 高段中部报告实际列更新。
		.o_row_advance(flag_eighth_advance)     // 高段中部通知行缓存切换。
	);





endmodule
