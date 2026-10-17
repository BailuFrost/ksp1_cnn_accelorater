`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/09 00:00:00
// Design Name:     cal_cmd
// Module Name:     cal_cmd
// Description:     description/cal_cmd_Design.pdf
// Simulations:     testbench/vivado/2021.1/cal_cmd
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/cal_cmd_spec.md; docs/设计文档.md 4.2、4.6、4.8、4.10
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/09 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/09       V1.0        Codex             Create layer computation scheduler.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月09日
// 设计名称:        cal_cmd
// 模块名称:        cal_cmd
// 模块说明:        Description/cal_cmd_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/cal_cmd
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/cal_cmd_spec.md; docs/设计文档.md 4.2、4.6、4.8、4.10
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月09日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月09日   V1.0        Codex             创建固定层计算调度控制器

module cal_cmd
(
	//-----------------用户接口-----------------//
	input i_clk,                                // CAL与数据通路共用FCLK。
	input i_rstn,                               // 低有效异步复位，上游同步释放。
	input i_ce,                                 // 用户暂停保持在途坐标。
	input i_soft_reset,                         // 静止DMA后与CU共同同步复位。
	input i_start,                              // 与start_ready共同锁存完整层指令。
	input [255:0]i_base_instruction,            // 基础指令原位序。
	input [255:0]i_extension,                   // 工程扩展字段按既有位序输入。
	output o_start_ready,                       // 空闲接受新层，不覆盖旧任务。
	output o_busy,                              // 当前层计算或组排空尚未结束。
	output o_compute_done,                      // 不再产生结果的FCLK单拍通知。
	output o_error,                             // 配置或依赖错误粘滞。
	output [3:0]o_error_code,                   // 一配置二标签三依赖四事件。
	input i_dependency_error,                   // D0、D1及后处理适配器错误汇总。
	output o_scan_req,                          // D0当前group和tile初装请求。
	input i_scan_ready,                         // D0接受新扫描。

	//FEATURE接口
	input i_feature_ready,                      // 当前D0数据和状态已齐备。
	input [9:0]i_feature_group,                 // D0十位响应组标签。
	input [7:0]i_feature_tile,                  // D0响应tile标签。
	output o_scan_finish,                       // 当前tile读与计算均已消费。
	input i_scan_done,                          // D0结束单拍，暂停期间也锁存。
	output o_load_req,                          // D1当前group和tile装载请求。
	input i_load_ready,                         // D1接受装载请求。

	//WEIGHT接口
	input i_weight_ready,                       // 当前权重和组偏置已齐备。
	input [8:0]i_weight_group,                  // D1仅卷积组标签，最大341。
	input [7:0]i_weight_tile,                   // 权重装载成功所属的输入分块编号。
	output o_compute_idle,                      // 没有读响应或计算流水时的装载授权。
	output [9:0]o_group_index,                  // 卷积512组、后处理1024组完整标签。
	output [8:0]o_weight_group,                 // 仅CONV及FC接D1，合法最大341。
	output [7:0]o_tile_index,                   // 当前输入tile，FC最多128块。
	output [15:0]o_tile_channel_base,           // 512对齐的tile起始通道。

	//UPDATE接口
	output o_update_req,                        // 整行排空后逐向量安全覆盖授权。
	input i_update_ready,                       // D0接受当前覆盖授权。
	output [15:0]o_update_row,                  // 将装载的真实新输入行。
	output [11:0]o_update_col,                  // 被覆盖物理行的真实列。
	output [1:0]o_update_bank,                  // 完整消费后释放的物理bank。
	input i_update_done,                        // 覆盖成功单拍，暂停期间也锁存。

	//FEATURE_RD接口
	output o_feature_rd_valid,                  // C0共同读请求，虚拟列不读。
	input i_feature_rd_ready,                   // C0同步读接受许可。
	output [12:0]o_feature_rd_addr,             // 当前tile紧密布局pair地址。
	input i_feature_out_valid,                  // C0与C2对齐的同步读响应。

	//WEIGHT_RD接口
	output o_weight_rd_valid,                   // C2所有bank共同读请求。
	input i_weight_rd_ready,                    // C2共同读接受许可。
	output [7:0]o_weight_rd_addr,               // 深度通道对零至255。
	input i_weight_out_valid,                   // C2同步读响应有效资格。
	output o_datapath_ce,                       // 寄存推进及CU结果holding冻结资格。
	output o_pair_valid,                        // 同步读响应送C1和CU的输入资格。
	input i_array_ready,                        // CU共同输入接受资格。
	output o_pair_first,                        // 当前向量首通道对。
	output o_pair_last,                         // 当前tile末通道对。
	output o_pair_row_last,                     // 末扫描列的末通道对行尾标签。
	output [1:0]o_mode,                         // 三列、两列、单点或矩阵模式。
	output [1:0]o_row_select,                   // 首逻辑行的物理bank，行内保持。
	output [2:0]o_row_mask,                     // 当前纵向窗口真实行有效位。
	output o_column_valid,                      // 虚拟Padding置零但保留MAC事件。
	output [1:0]o_pair_mask,                    // 奇数末pair高INT16清零。
	input i_column_commit,                      // 实际CU列缓存提交事件。
	input i_row_advance,                        // 实际CU行末提交事件。
	input i_cu_valid,                           // 完整CU结果，holding可保持。
	input i_bundle_ready,                       // B5接受当前完整结果的许可。
	input i_packer_busy,                        // B5尚未排空，不得切换组。
	input i_fifo_full,                          // 当前FIFO满，下一拍寄存停顿。
	input i_group_write_done,                   // D3当前组全部HP2成功响应齐备。
	output o_bundle_valid,                      // 命中stride的CU结果送B5。
	output [71:0]o_lane_mask,                   // 当前组低位连续有效lane。
	output [6:0]o_valid_lanes,                  // 公开当前组已寄存有效数量，供CONCAT使用。
	output [31:0]o_spatial_index,               // 空间位置计数，多tile接B5低八位。
	output o_first_tile,                        // 首tile覆盖旧部分和。
	output o_last_tile,                         // 末tile才允许量化输出。

	//POST_STREAM接口
	output o_post_stream_req,                   // ADD或GAP一次完整HWC流启动。
	input i_post_stream_ready,                  // 流适配器接受整层开始。
	input i_post_stream_done,                   // 全部输入与DMA成功状态齐备。

	//POST_BLOCK接口
	output o_post_block_req,                    // Pool当前真实行与512通道块请求。
	input i_post_block_ready,                   // Pool缓存适配器接受当前块。
	input i_post_block_done,                    // 绑定当前块坐标的装载成功单拍。
	output [15:0]o_post_block_row,              // 池化窗口真实首行。
	output [7:0]o_post_block,                   // 全局quad高位形成的通道块标签。
	output [9:0]o_post_block_channels,          // 当前尾块有效通道数。

	//POST接口
	output o_post_valid,                        // 后处理坐标token有效。
	input i_post_ready,                         // Pool读接受或ADD双方流共同接受。
	output [15:0]o_post_row,                    // Pool真实读行或流模式输入行。
	output [11:0]o_post_col,                    // 当前真实输入列。
	output [1:0]o_post_stage,                   // Pool四读阶段，流模式固定零。
	output [6:0]o_post_quad,                    // 当前块内四通道索引。
	output [3:0]o_post_mask,                    // 当前尾quad有效lane位。
	input i_post_done                           // Pool或ADD结果接受，GAP归约输出全部结束。
);

	//---------------状态参数区域---------------//
	localparam ST_IDLE = 5'd0;                  // 等待新层。
	localparam ST_ERROR = 5'd27;                // 错误仅由复位退出。
	localparam ST_COUNTS = 5'd1;                // 派生组数与tile数。
	localparam ST_GEOMETRY = 5'd2;              // 派生横向输出数量。
	localparam ST_SPATIAL = 5'd3;               // 寄存空间位置总数。
	localparam ST_CHECK = 5'd4;                 // 校验寄存范围。
	localparam ST_TILE = 5'd5;                  // 准备tile及组尾部。
	localparam ST_REQUEST = 5'd6;               // 独立握手两装载请求。
	localparam ST_READY = 5'd7;                 // 等待当前标签数据资格。
	localparam ST_ADDRESS = 5'd8;               // 地址及行列标签准备。
	localparam ST_READ = 5'd9;                  // 两缓存共同同步读。
	localparam ST_RESPONSE = 5'd10;             // 等待共同响应。
	localparam ST_PAIR = 5'd11;                 // 输入通道对进入MAC。
	localparam ST_COLUMN = 5'd12;               // 等待真实提交与结果。
	localparam ST_RETIRE = 5'd13;               // 清已消费CU有效标签。
	localparam ST_ROW = 5'd14;                  // 检查新物理行。
	localparam ST_UPDATE = 5'd15;               // 新行逐列安全覆盖。
	localparam ST_UPDATE_WAIT = 5'd16;          // 等待覆盖成功。
	localparam ST_ROTATE = 5'd17;               // 整行完成后轮换bank。
	localparam ST_FINISH = 5'd18;               // 通知D0本tile结束。
	localparam ST_FINISH_WAIT = 5'd19;          // 等待D0结束单拍。
	localparam ST_GROUP = 5'd20;                // 等待组结果及HP2排空。
	localparam ST_POST_START = 5'd21;           // HWC输入流开始。
	localparam ST_POST_BLOCK = 5'd22;           // Pool缓存块请求。
	localparam ST_POST_BLOCK_WAIT = 5'd23;      // 等待真实块装载。
	localparam ST_POST_TOKEN = 5'd24;           // 空间外层四通道调度。
	localparam ST_POST_WAIT = 5'd25;            // 等待结果实际接受。
	localparam ST_POST_END = 5'd26;             // 等待流状态及归约输出。

	//-----------------计数信号-----------------//
	(* use_dsp="no" *) reg [31:0]cnt_spatial_total = 0; // 当前tile完整空间数量，不挤占CU的216个DSP。
	reg [15:0]cnt_row = 0;                      // 输出行或流模式输入行。
	reg [13:0]cnt_column = 0;                   // KsP1扫描列或后处理空间列。
	reg [12:0]cnt_result_column = 0;            // 所有完整点的stride相位。

	//用户接口WEIGHT_RD接口
	reg [8:0]cnt_pair = 0;                      // 当前tile通道对索引。

	//----------------状态机信号----------------//
	reg [4:0]state_next = 0;                    // 组合次态默认保持，等待完整握手。
	reg [4:0]state_current = 0;                 // 单状态时序FSM按寄存坐标调度。

	//----------------寄存器信号----------------//
	reg [255:0]reg_base = 0;                    // 当前不可变基础字。
	reg [255:0]reg_extension = 0;               // 层字段副本在运行期间不受外部改变。
	reg [3:0]reg_opcode = 0;                    // 已有算子分类。
	reg [1:0]reg_stride = 0;                    // 步长一或二。
	reg [1:0]reg_padding = 0;                   // Padding零或一。
	reg [2:0]reg_kernel = 0;                    // 核尺寸一至三。
	reg [31:0]reg_depth = 0;                    // FC展平长度或逻辑Cin。
	reg [12:0]reg_outputs = 0;                  // K_NUM零编码恢复4096。
	reg [10:0]reg_groups = 0;                   // 组数量包含1024。
	reg [13:0]reg_group_numerator = 0;          // 开始沿保存组数除法分子，分开加法和除法。
	reg [7:0]reg_tiles = 0;                     // 输入tile数量最多128。
	reg [15:0]reg_height = 0;                   // 输入真实高度。
	reg [11:0]reg_width = 0;                    // 输入真实宽度。
	reg [15:0]reg_output_height = 0;            // 软件预检后的纵向输出数量。
	reg [12:0]reg_output_width = 0;             // 派生输出宽度。
	reg [13:0]reg_padded_width = 0;             // 包含虚拟列的扫描长度。
	reg [9:0]reg_active = 0;                    // 当前tile有效输入深度。
	reg [9:0]reg_tile_padded = 0;               // C0四通道补齐向量长度。
	reg [8:0]reg_pairs = 0;                     // 每tile最多256个pair。
	reg [6:0]reg_lanes = 0;                     // 当前输出组最多72个有效lane。
	reg [12:0]reg_output_base = 0;              // 当前组首输出通道游标。
	reg signed [16:0]reg_top = 0;               // 首输入行允许负Padding。
	reg signed [16:0]reg_target_top = 0;        // 下一输出行目标首输入行。
	reg [4:0]reg_drain = 0;                     // 单向量流水排空使能沿计数。
	reg [1:0]reg_role = 0;                      // 第一逻辑行的物理bank。

	//-----------------标志信号-----------------//
	reg flag_run = 0;                           // FIFO及B5资格寄存后统一广播。
	reg flag_scan_sent = 0;                     // 当前D0请求仅接受一次。
	reg flag_load_sent = 0;                     // 权重请求握手记录用于禁止重复块装载。
	reg flag_commit_seen = 0;                   // 当前列实际提交记录。
	reg flag_row_seen = 0;                      // 当前末列实际行末记录。
	reg flag_scan_done = 0;                     // 暂停时仍锁存扫描单拍。
	reg flag_update_done = 0;                   // 暂停时仍锁存覆盖单拍。
	reg flag_post_done = 0;                     // 后处理结果完成资格。
	reg flag_stream_done = 0;                   // 整层输入DMA完成资格。
	reg flag_block_done = 0;                    // Pool当前块完成资格。
	wire flag_step;                             // 当前控制推进资格。
	wire flag_compute;                          // CONV及FC任务类别。
	wire flag_hold;                             // 已寄存CU结果holding资格。
	wire flag_emit;                             // 完整点命中stride。
	wire flag_read;                             // 两缓存共同接受资格。
	wire flag_bad;                              // 基本字段及派生范围非法。
	wire flag_tags_bad;                         // 当前ready响应标签不匹配。

	//-----------------其他信号-----------------//
	//调度范围与真实坐标
	wire [31:0]remaining_depth;                 // 当前tile剩余输入元素。
	wire [12:0]remaining_outputs;               // 当前组剩余输出通道。
	wire [12:0]horizontal_extent;               // 核覆盖后的横向有效范围。
	wire signed [16:0]row_second;               // 窗口第二行候选。
	wire signed [16:0]row_third;                // 窗口第三行候选。
	wire [11:0]real_column;                     // 去Padding的输入真实列。
	(* use_dsp="no" *) wire [20:0]feature_column_offset; // 紧密列偏移的乘法明确使用逻辑资源。

	//后处理通道块
	wire [12:0]post_remaining;                  // 当前quad剩余有效通道。
	wire [12:0]block_remaining;                 // 当前512通道块剩余通道。

	//用户接口UPDATE接口
	wire signed [16:0]row_new;                  // 已释放bank对应的新真实行。

	//-----------------输出信号-----------------//
	//用户接口
	reg compute_done_o = 0;                     // 不受ce延长的单FCLK脉冲。
	reg [3:0]error_code_o = 0;                  // 首错误粘滞记录。

	//用户接口WEIGHT接口
	reg [9:0]group_index_o = 0;                 // 十位卷积组或后处理quad。
	reg [7:0]tile_index_o = 0;                  // 当前输入tile索引。

	//用户接口UPDATE接口
	wire [15:0]update_row_o;                    // 覆盖请求的真实新行号，符号边界已由调度保证。
	reg [11:0]update_col_o = 0;                 // 已释放物理行的覆盖列。
	wire [1:0]update_bank_o;                    // 覆盖写bank取已释放首行的物理位置。

	//用户接口FEATURE_RD接口
	(* use_dsp="no" *) reg [12:0]feature_rd_addr_o = 0; // C0共同pair地址准备寄存，地址乘法使用逻辑。

	//用户接口WEIGHT_RD接口
	wire [7:0]weight_rd_addr_o;                 // 全部权重bank共同使用当前八位深度地址。

	//用户接口
	reg [1:0]mode_o = 0;                        // 固定CU核模式。
	wire [1:0]row_select_o;                     // C1首逻辑行的物理bank选择，不随水平列移动。
	reg [2:0]row_mask_o = 0;                    // 纵向真实行有效位。
	reg column_valid_o = 0;                     // 虚拟列不读RAM。
	reg [31:0]spatial_index_o = 0;              // 当前tile已接受空间结果数量。

	//用户接口POST_BLOCK接口
	wire [7:0]post_block_o;                     // 全局quad高位形成缓存块。
	reg [9:0]post_block_channels_o = 0;         // Pool当前缓存块有效通道。

	//用户接口POST接口
	reg [1:0]post_stage_o = 0;                  // 池化四读阶段。

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_compute = reg_opcode < 4'd2;    // 后处理不进入权重循环。
	assign flag_step = i_rstn && i_ce && flag_run; // 状态按寄存推进资格更新。
	assign flag_hold = state_current == ST_COLUMN && i_cu_valid; // 单在途结果稳定等待B5。
	assign flag_emit = reg_opcode == 1 || (cnt_column >= reg_kernel - 1'b1 && (reg_stride != 2 || !cnt_result_column[0])); // stride二接收偶数完整列。
	assign flag_read = i_weight_rd_ready && (!column_valid_o || i_feature_rd_ready); // Padding仅读权重。
	assign remaining_depth = reg_depth - {15'd0, tile_index_o, 9'd0}; // 当前512对齐tile剩余深度。
	assign remaining_outputs = reg_outputs - reg_output_base; // 使用递增组游标裁剪尾组。
	assign horizontal_extent = {1'b0, reg_width} + {10'd0, reg_padding, 1'b0} - {10'd0, reg_kernel}; // 配置检查保护核不适配的负范围。
	assign row_second = reg_top + 17'sd1;       // 第二真实行独立检查。
	assign row_third = reg_top + 17'sd2;        // 第三行仅三核模式启用。
	assign row_new = reg_top + 17'sd3;          // 旧行所有水平向量排空后进入新行逐列授权阶段。
	assign real_column = cnt_column[11:0] - {10'd0, reg_padding}; // 仅真实列使用。
	assign feature_column_offset = real_column * reg_tile_padded[9:1]; // 独立线网阻止乘法在条件地址选择前推断DSP。
	assign post_block_o = {5'd0, group_index_o[9:7]}; // 一个块包含128个quad。
	assign post_remaining = reg_outputs - {1'b0, group_index_o, 2'b00}; // 全十位组标签形成尾quad长度。
	assign block_remaining = reg_outputs - {post_block_o[3:0], 9'd0}; // 最多八个512通道块。
	assign flag_bad = reg_opcode > 4'd4 || reg_width == 0 || reg_height == 0 || reg_output_height == 0 || reg_depth == 0 || reg_depth > 32'd65532 || reg_groups == 0 || reg_tiles == 0 || reg_base[199:196] > 4'd3 || reg_extension[165:160] > 6'd47 || reg_base[255:236] != 20'd0 || (flag_compute && cnt_spatial_total == 0) || (flag_compute && reg_tiles > 1 && cnt_spatial_total > 32'd196) || (reg_opcode == 0 && (mode_o == 3 || reg_stride == 0 || reg_stride > 2 || reg_padding > 1 || reg_depth > 32'd4096 || {1'b0, reg_width} + {10'd0, reg_padding, 1'b0} < {10'd0, reg_kernel})) || (reg_opcode == 1 && mode_o != 3) || (reg_opcode == 2 && (reg_width[0] || reg_height[0] || reg_stride != 2 || reg_padding != 0)) || (reg_opcode == 4 && reg_outputs > 13'd2048); // 静态数量一致性仍由软件及D4保证。
	assign flag_tags_bad = (i_feature_ready && (i_feature_group != group_index_o || i_feature_tile != tile_index_o)) || (i_weight_ready && (i_weight_group != group_index_o[8:0] || i_weight_tile != tile_index_o)); // 旧ready标签不允许参与新任务。
	assign update_row_o = row_new[15:0];        // 仅真实且至少第三行才发请求。
	assign update_bank_o = reg_role;            // 新行与释放首行bank同余。
	assign weight_rd_addr_o = cnt_pair[7:0];    // 权重深度独立于空间列。
	assign row_select_o = reg_role;             // 水平扫描保持物理行角色。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_start_ready = i_rstn && i_ce && state_current == ST_IDLE; // 空闲配置不受旧FIFO状态限制。
	assign o_busy = state_current != ST_IDLE && state_current != ST_ERROR; // 错误单独上报。
	assign o_compute_done = compute_done_o;     // 不替代层级output_done。
	assign o_error = error_code_o != 0;         // 诊断非零表示首错误粘滞，只有控制复位才允许新任务。
	assign o_error_code = error_code_o;         // 诊断首错误原因。
	assign o_scan_req = flag_step && state_current == ST_REQUEST && !flag_scan_sent; // 独立等待D0接受。

	//用户接口FEATURE接口
	assign o_scan_finish = flag_step && state_current == ST_FINISH; // 此时缓存读和算术均已排空。
	assign o_load_req = flag_step && state_current == ST_REQUEST && !flag_load_sent; // 持续呈现尚未接受的权重装载资格。

	//用户接口WEIGHT接口
	assign o_compute_idle = state_current == ST_IDLE || state_current == ST_TILE || state_current == ST_REQUEST || state_current == ST_READY || state_current == ST_FINISH || state_current == ST_FINISH_WAIT || state_current == ST_GROUP; // 装载授权期间无读请求或在途计算。
	assign o_group_index = group_index_o;       // D0十位完整组标签。
	assign o_weight_group = flag_compute ? group_index_o[8:0] : 9'd0; // D1从不收到后处理高组标签。
	assign o_tile_index = tile_index_o;         // 请求与结果保持同一tile。
	assign o_tile_channel_base = {tile_index_o[6:0], 9'd0}; // 最大FC合法起点65024。

	//用户接口UPDATE接口
	assign o_update_req = flag_step && state_current == ST_UPDATE; // 整行排空后才授权覆盖。
	assign o_update_row = update_row_o;         // 安全授权的新真实行号送入D0地址准备。
	assign o_update_col = update_col_o;         // ready及done等待期间保持坐标。
	assign o_update_bank = update_bank_o;       // 将释放的物理行位置提供给D0写bank选择。

	//用户接口FEATURE_RD接口
	assign o_feature_rd_valid = flag_step && state_current == ST_READ && column_valid_o && i_weight_rd_ready; // 两端口同沿共同接受。
	assign o_feature_rd_addr = feature_rd_addr_o; // 已寄存共同pair地址。

	//用户接口WEIGHT_RD接口
	assign o_weight_rd_valid = flag_step && state_current == ST_READ && (!column_valid_o || i_feature_rd_ready); // 不允许单边读响应误配。
	assign o_weight_rd_addr = weight_rd_addr_o; // C2共同pair读地址只取当前深度索引。

	//用户接口
	assign o_datapath_ce = flag_step && !flag_hold; // CU有效结果holding冻结，消费后恢复。
	assign o_pair_valid = flag_step && state_current == ST_PAIR; // 已取得同步响应的MAC输入。
	assign o_pair_first = cnt_pair == 0;        // 向量首pair重建深度累加。
	assign o_pair_last = cnt_pair == reg_pairs - 1'b1; // 有效深度决定末pair。
	assign o_pair_row_last = o_pair_last && cnt_column == reg_padded_width - 1'b1; // 末深度与末扫描列共同形成行尾。
	assign o_mode = mode_o;                     // 层间共同复位CU再切换模式。
	assign o_row_select = row_select_o;         // 行角色映射送C1三行换位逻辑。
	assign o_row_mask = row_mask_o;             // 与读地址同时准备的纵向有效位。
	assign o_column_valid = column_valid_o;     // C1为虚拟列送零。
	assign o_pair_mask = reg_active[0] && o_pair_last ? 2'b01 : 2'b11; // 奇数深度高lane清零。
	assign o_bundle_valid = flag_step && state_current == ST_COLUMN && reg_drain == 0 && i_cu_valid && flag_emit && !i_fifo_full; // 仅排空后且B5许可时接受一次结果。
	assign o_lane_mask = ~({72{1'b1}} << reg_lanes); // 等价低位前缀掩码，避免72位借位链串入结果许可。
	assign o_valid_lanes = reg_lanes;           // 尾组路由数量不在顶层重复推导。
	assign o_spatial_index = spatial_index_o;   // 仅结果接受后递增。
	assign o_first_tile = tile_index_o == 0;    // 首tile覆盖旧组部分和。
	assign o_last_tile = tile_index_o == reg_tiles - 1'b1; // 末tile才量化结果。

	//用户接口POST_STREAM接口
	assign o_post_stream_req = flag_step && state_current == ST_POST_START; // ADD和GAP一次整层流启动。

	//用户接口POST_BLOCK接口
	assign o_post_block_req = flag_step && state_current == ST_POST_BLOCK; // Pool块请求含真实窗口首行。
	assign o_post_block_row = {cnt_row[14:0], 1'b0}; // 固定stride二池化窗口首行。

	//用户接口
	assign o_post_block = post_block_o;         // 请求和token携带同一通道块。
	assign o_post_block_channels = post_block_channels_o; // 尾块逻辑通道数不截为零。

	//用户接口POST接口
	assign o_post_valid = flag_step && state_current == ST_POST_TOKEN && !i_fifo_full; // 四阶段Pool或完整HWC流顺序。
	assign o_post_row = reg_opcode == 2 ? {cnt_row[14:0], 1'b0} + {15'd0, post_stage_o[1]} : cnt_row; // Pool阶段高位选择下行。
	assign o_post_col = reg_opcode == 2 ? {cnt_column[10:0], 1'b0} + {11'd0, post_stage_o[0]} : cnt_column[11:0]; // Pool阶段低位选择右列。
	assign o_post_stage = post_stage_o;         // 左上右上左下右下固定次序。
	assign o_post_quad = group_index_o[6:0];    // 当前512通道块内quad。
	assign o_post_mask = post_remaining >= 4 ? 4'hf : (4'h1 << post_remaining) - 4'h1; // 尾quad无效lane补零。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 配置、读请求、安全覆盖和结果消费统一从寄存状态推进。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			compute_done_o <= 1'b0;             // 复位不产生伪完成。
			error_code_o <= 4'd0;               // 硬复位丢弃上一运行的诊断记录。
			reg_base <= 256'd0;                 // 旧基础指令失效。
			reg_extension <= 256'd0;            // 旧扩展指令失效。
			reg_opcode <= 4'd0;                 // 默认卷积。
			mode_o <= 2'd0;                     // 默认三核。
			reg_stride <= 2'd1;                 // 默认合法步长。
			reg_padding <= 2'd0;                // 默认无虚拟行。
			reg_kernel <= 3'd3;                 // 默认三列。
			reg_depth <= 32'd0;                 // 未配置有效深度。
			reg_outputs <= 13'd0;               // 未配置输出通道。
			reg_groups <= 11'd0;                // 未派生组数。
			reg_group_numerator <= 14'd0;       // 旧组数分子无效。
			reg_tiles <= 8'd0;                  // 未派生tile数。
			reg_height <= 16'd0;                // 未配置输入行。
			reg_width <= 12'd0;                 // 未配置输入列。
			reg_output_height <= 16'd0;         // 未配置输出行。
			reg_output_width <= 13'd0;          // 未派生输出列。
			cnt_spatial_total <= 32'd0;         // 尚无空间总数。
			reg_padded_width <= 14'd0;          // 尚无扫描长度。
			reg_active <= 10'd0;                // 尾tile无效。
			reg_tile_padded <= 10'd0;           // 旧缓存跨度失效。
			reg_pairs <= 9'd0;                  // 旧pair上限失效。
			reg_lanes <= 7'd0;                  // 旧lane资格失效。
			reg_output_base <= 13'd0;           // 新组通道游标归零。
			reg_top <= 17'sd0;                  // 清当前真实行起点。
			reg_target_top <= 17'sd0;           // 清stride目标行。
			reg_role <= 2'd0;                   // 默认物理bank零。
			feature_rd_addr_o <= 13'd0;         // 不发旧读地址。
			row_mask_o <= 3'd0;                 // 旧RAM内容无有效资格。
			column_valid_o <= 1'b0;             // 清真实列资格。
			reg_drain <= 5'd0;                  // 旧流水等待失效。
			post_stage_o <= 2'd0;               // Pool从左上开始。
			post_block_channels_o <= 10'd0;     // 当前块未建立。
			group_index_o <= 10'd0;             // 清当前组。
			tile_index_o <= 8'd0;               // 清当前tile。
			cnt_row <= 16'd0;                   // 清当前行。
			cnt_column <= 14'd0;                // 清当前列。
			cnt_pair <= 9'd0;                   // 清当前深度对。
			update_col_o <= 12'd0;              // 清覆盖列。
			spatial_index_o <= 32'd0;           // 清输出数量。
			cnt_result_column <= 13'd0;         // 清stride相位。
			flag_scan_sent <= 1'b0;             // 无初装在途。
			flag_load_sent <= 1'b0;             // 无装载在途。
			flag_commit_seen <= 1'b0;           // 无旧列事件。
			flag_row_seen <= 1'b0;              // 无旧行末事件。
		end else if(i_soft_reset == 1'b1)begin
			compute_done_o <= 1'b0;             // 中断任务不报成功。
			error_code_o <= 4'd0;               // DMA静止后软复位允许新任务重新检查。
		end else begin
			compute_done_o <= 1'b0;             // done严格为一个FCLK。
			if(i_dependency_error == 1'b1 && state_current != ST_IDLE && state_current != ST_ERROR)begin
				error_code_o <= 4'd3;           // 保留依赖错误原因。
			end else if(o_start_ready == 1'b1 && i_start == 1'b1)begin
				reg_base <= i_base_instruction; // 原位序锁存完整基础字。
				reg_extension <= i_extension;   // 运行期间忽略外部配置变化。
				reg_opcode <= i_extension[171:168]; // 已有opcode选择调度路径。
				mode_o <= i_base_instruction[197:196]; // CU模式保持到层末。
				reg_stride <= i_base_instruction[201:200]; // 原位序stride。
				reg_padding <= i_base_instruction[203:202]; // 原位序Padding。
				reg_kernel <= i_base_instruction[197] ? 3'd1 : (i_base_instruction[196] ? 3'd2 : 3'd3); // mode直接译码核尺寸。
				reg_depth <= i_extension[171:168] == 1 ? i_extension[223:192] : (i_base_instruction[183:172] == 0 ? 32'd4096 : {20'd0, i_base_instruction[183:172]}); // FC采用INPUT_ELEMENTS，卷积恢复4096零编码。
				reg_outputs <= i_base_instruction[195:184] == 0 ? 13'd4096 : {1'b0, i_base_instruction[195:184]}; // 4096输出不截为零。
				reg_group_numerator <= (i_base_instruction[195:184] == 0 ? 14'd4096 : {2'd0, i_base_instruction[195:184]}) + (i_extension[171:168] >= 2 ? 14'd3 : (i_base_instruction[197] ? 14'd71 : 14'd7)); // 配置沿加上并行数减一，下一阶段只做常数除法。
				reg_height <= i_extension[111:96]; // 保存真实高度。
				reg_width <= i_base_instruction[147:136]; // 保存真实宽度。
				reg_output_height <= i_extension[127:112]; // 输出高度直接采用软件预检后的字段。
				group_index_o <= 10'd0;         // 新层从首组开始。
				tile_index_o <= 8'd0;           // 新层从首tile开始。
				cnt_row <= 16'd0;               // 首空间行。
				cnt_column <= 14'd0;            // 首扫描列。
				spatial_index_o <= 32'd0;       // 尚无结果。
				reg_output_base <= 13'd0;       // 首输出通道。
				post_stage_o <= 2'd0;           // 软复位重启也从Pool左上开始。
				error_code_o <= 4'd0;           // 空闲接受后重新检查。
			end else if(flag_step == 1'b1)begin
				case(state_current)

					// 数量与几何分拍，后处理不使用零权重块计数。
					ST_COUNTS:begin
						reg_groups <= reg_opcode >= 2 ? reg_group_numerator >> 2 : (mode_o[1] ? reg_group_numerator / 14'd72 : reg_group_numerator / 14'd8); // 最大1024组，准备阶段不串联加法和常数除法。
						reg_tiles <= flag_compute ? (reg_depth + 32'd511) >> 9 : 8'd1; // 无权重算子采用一个输入流任务，无卷积块计数。
						reg_padded_width <= reg_opcode == 1 ? 14'd1 : {2'd0, reg_width} + {11'd0, reg_padding, 1'b0}; // FC单向量，卷积保留虚拟列。
					end

					// 不用变量除法，合法stride固定一或二。
					ST_GEOMETRY:begin
						reg_output_width <= reg_opcode == 1 || reg_opcode == 4 ? 13'd1 : (reg_opcode == 3 ? {1'b0, reg_width} : (reg_opcode == 2 ? {1'b0, reg_width} >> 1 : (reg_stride == 2 ? (horizontal_extent >> 1) + 13'd1 : horizontal_extent + 13'd1))); // ADD保留输入宽度，非法卷积stride稍后拒绝。
					end

					// 多tile固定27槽，不能按12lane放宽空间容量。
					ST_SPATIAL:begin
						cnt_spatial_total <= reg_output_width * reg_output_height; // 只在准备阶段形成空间数量。
					end

					// 非法配置在任何传输请求之前拒绝。
					ST_CHECK:begin
						if(flag_bad == 1'b1)begin
							error_code_o <= 4'd1; // 基本字段或容量错误。
						end else if(flag_compute == 1'b1)begin
						end else if(reg_opcode == 2)begin
							post_block_channels_o <= reg_outputs > 512 ? 10'd512 : reg_outputs[9:0]; // 首Pool块有效长度。
						end else begin
						end
					end

					// 当前tile与组尾数在请求前寄存。
					ST_TILE:begin
						reg_active <= remaining_depth > 512 ? 10'd512 : remaining_depth[9:0]; // 尾tile不消费脏高lane。
						reg_tile_padded <= remaining_depth > 512 ? 10'd512 : (remaining_depth[9:0] + 10'd3) & 10'h3fc; // C0四通道word布局。
						reg_pairs <= remaining_depth > 512 ? 9'd256 : (remaining_depth[9:0] + 10'd1) >> 1; // 奇数末pair只有低lane。
						reg_lanes <= remaining_outputs > (mode_o[1] ? 13'd72 : 13'd8) ? (mode_o[1] ? 7'd72 : 7'd8) : remaining_outputs[6:0]; // 输出尾组连续前缀。
						reg_top <= reg_opcode == 1 ? 17'sd0 : -$signed({15'd0, reg_padding}); // 每tile重建顶部Padding。
						reg_role <= reg_opcode == 1 || reg_padding == 0 ? 2'd0 : (reg_padding == 1 ? 2'd2 : 2'd1); // 首真实行号模三。
						cnt_row <= 16'd0;       // 每tile完整重扫。
						cnt_column <= 14'd0;    // 行首重新填充KsP1。
						cnt_pair <= 9'd0;       // 首向量首pair。
						spatial_index_o <= 32'd0; // 各tile复用相同空间地址。
						cnt_result_column <= 13'd0; // 重建stride相位。
						flag_scan_sent <= 1'b0; // 新D0请求重新握手。
						flag_load_sent <= 1'b0; // 清权重发送记录以绑定下个输入分块。
					end

					// 两个ready独立，不要求同沿接受。
					ST_REQUEST:begin
						if(o_scan_req == 1'b1 && i_scan_ready == 1'b1)begin
							flag_scan_sent <= 1'b1; // 已接受初装不重复。
						end
						if(o_load_req == 1'b1 && i_load_ready == 1'b1)begin
							flag_load_sent <= 1'b1; // 已接受装载不重复。
						end
						if((flag_scan_sent == 1'b1 || i_scan_ready == 1'b1) && (flag_load_sent == 1'b1 || i_load_ready == 1'b1))begin
						end
					end

					// 当前ready必须匹配完整标签。
					ST_READY:begin
						if(flag_tags_bad == 1'b1)begin
							error_code_o <= 4'd2; // 拒绝旧响应或错误块。
						end else if(i_feature_ready == 1'b1 && i_weight_ready == 1'b1)begin
						end
					end

					// 地址和资格同拍寄存，避免跨BRAM响应改变标签。
					ST_ADDRESS:begin
						column_valid_o <= reg_opcode == 1 || (cnt_column >= {12'd0, reg_padding} && cnt_column < {2'd0, reg_width} + {12'd0, reg_padding}); // 左右虚拟列不读取C0。
						feature_rd_addr_o <= reg_opcode == 1 || cnt_column < {12'd0, reg_padding} || cnt_column >= {2'd0, reg_width} + {12'd0, reg_padding} ? {4'd0, cnt_pair} : feature_column_offset[12:0] + {4'd0, cnt_pair}; // 软件行容量保护截位，地址算术不串ready。
						row_mask_o <= {mode_o == 0 && row_third >= 0 && row_third < $signed({1'b0, reg_height}), !mode_o[1] && row_second >= 0 && row_second < $signed({1'b0, reg_height}), reg_top >= 0 && reg_top < $signed({1'b0, reg_height})}; // 单点与矩阵仅广播首行。
					end

					// 输入实际握手才推进深度地址。
					ST_PAIR:begin
						if(i_array_ready == 1'b1)begin
							if(o_pair_last == 1'b1)begin
								reg_drain <= 5'd16; // 保守等待已知CU寄存级排空。
								flag_commit_seen <= 1'b0; // 重新等待当前列实际事件。
								flag_row_seen <= 1'b0; // 重新等待当前末列事件。
							end else begin
								cnt_pair <= cnt_pair + 9'd1; // 下一相邻通道对。
							end
						end
					end

					// 真实commit与结果holding分别记账。
					ST_COLUMN:begin
						if(i_column_commit == 1'b1 && o_datapath_ce == 1'b1)begin
							flag_commit_seen <= 1'b1; // 当前缓存已实际提交。
						end
						if(i_row_advance == 1'b1 && o_datapath_ce == 1'b1)begin
							flag_row_seen <= 1'b1; // 已实际提交行尾。
						end
						if(reg_drain != 0)begin
							reg_drain <= reg_drain - 5'd1; // 停顿不缩短等待。
						end else if(i_cu_valid == 1'b1)begin
							if(flag_emit == 1'b0 || (i_bundle_ready == 1'b1 && i_fifo_full == 1'b0))begin
								if(flag_emit == 1'b1)begin
									spatial_index_o <= spatial_index_o + 32'd1; // 仅结果握手增加空间地址。
								end
								cnt_result_column <= cnt_result_column + 13'd1; // 所有完整点参与stride相位。
							end
						end else if(!mode_o[1] && cnt_column < reg_kernel - 1'b1 && flag_commit_seen == 1'b1)begin
						end
					end

					// 清CU气泡后再改变空间坐标或授权覆盖。
					ST_RETIRE:begin
						cnt_pair <= 9'd0;       // 下一向量重启深度。
						if(cnt_column == reg_padded_width - 1'b1)begin
							if(!mode_o[1] && flag_row_seen == 1'b0)begin
								error_code_o <= 4'd4; // 缺真实行末事件禁止覆盖。
							end else if(cnt_row == reg_output_height - 1'b1)begin
								if(spatial_index_o != cnt_spatial_total)begin
									error_code_o <= 4'd4; // 完整空间结果数量不符。
								end else begin
								end
							end else begin
								reg_target_top <= reg_top + $signed({15'd0, reg_stride}); // 下一输出行真实起点。
								cnt_row <= cnt_row + 16'd1; // 输出行推进一次。
							end
						end else begin
							cnt_column <= cnt_column + 14'd1; // 水平推进保持bank角色。
						end
					end

					// stride二逐输入行推进，虚拟行不读DDR。
					ST_ROW:begin
						update_col_o <= 12'd0;  // 新真实行从首列覆盖。
						if(row_new >= 17'sd3 && row_new < $signed({1'b0, reg_height}))begin
						end else begin
						end
					end

					// 每个向量数据及成功状态齐备再继续。
					ST_UPDATE_WAIT:begin
						if(flag_update_done == 1'b1)begin
							if(update_col_o == reg_width - 1'b1)begin
							end else begin
								update_col_o <= update_col_o + 12'd1; // 下一真实列。
							end
						end
					end

					// 每次输入行变化仅轮换一次物理角色。
					ST_ROTATE:begin
						reg_top <= reg_top + 17'sd1; // 包含stride跳点中的中间行。
						reg_role <= reg_role == 2 ? 2'd0 : reg_role + 2'd1; // 三bank循环同余映射。
						if(reg_top + 17'sd1 == reg_target_top)begin
							cnt_column <= 14'd0; // 新行从虚拟首列重填KsP1。
							cnt_result_column <= 13'd0; // 新行stride相位归零。
						end else begin
						end
					end

					// 保留标签到scan_done且B5排空。
					ST_FINISH_WAIT:begin
						if(flag_scan_done == 1'b1 && i_packer_busy == 1'b0)begin
							if(tile_index_o == reg_tiles - 1'b1)begin
							end else begin
								tile_index_o <= tile_index_o + 8'd1; // 下一tile重装和重扫。
							end
						end
					end

					// 当前组最后成功写响应与B5排空分别检查。
					ST_GROUP:begin
						if(i_packer_busy == 1'b0 && i_group_write_done == 1'b1)begin
							if(group_index_o == reg_groups - 1'b1)begin
								compute_done_o <= 1'b1; // 本层不再产生结果。
							end else begin
								group_index_o <= group_index_o + 10'd1; // 完整十位下组标签。
								tile_index_o <= 8'd0; // 每组首tile装载偏置。
								reg_output_base <= reg_output_base + (mode_o[1] ? 13'd72 : 13'd8); // 组通道游标递增避免重复乘法。
							end
						end
					end

					// 空间外层quad内层，Pool角点最后一层。
					ST_POST_TOKEN:begin
						if(i_post_ready == 1'b1 && i_fifo_full == 1'b0)begin
							if(reg_opcode == 2 && post_stage_o != 3)begin
								post_stage_o <= post_stage_o + 2'd1; // 下一个真实窗口角点。
							end else begin
								post_stage_o <= 2'd0; // 新quad从左上或流阶段零开始。
							end
						end
					end

					// 下游停顿保持当前HWC坐标及lane有效数。
					ST_POST_WAIT:begin
						if(reg_opcode == 4 || flag_post_done == 1'b1)begin
							if(group_index_o != reg_groups - 1'b1)begin
								group_index_o <= group_index_o + 10'd1; // 当前空间点推进全局quad。
								if(reg_opcode == 2 && group_index_o[6:0] == 127)begin
									post_block_channels_o <= block_remaining > 1024 ? 10'd512 : block_remaining - 13'd512; // 下一块尾部逻辑深度。
								end else begin
								end
							end else begin
								group_index_o <= 10'd0; // 下空间点从通道零开始。
								if(cnt_column == (reg_opcode == 2 ? reg_output_width - 1'b1 : {1'b0, reg_width} - 1'b1))begin
									cnt_column <= 14'd0; // 行末横坐标归零。
									cnt_row <= cnt_row + 16'd1; // 空间行外层推进。
								end else begin
									cnt_column <= cnt_column + 14'd1; // 下一空间列。
								end
								if(cnt_row == (reg_opcode == 2 ? reg_output_height - 1'b1 : reg_height - 1'b1) && cnt_column == (reg_opcode == 2 ? reg_output_width - 1'b1 : {1'b0, reg_width} - 1'b1))begin
								end else if(reg_opcode == 2)begin
									post_block_channels_o <= reg_outputs > 512 ? 10'd512 : reg_outputs[9:0]; // 下窗口重新准备首缓存块。
								end else begin
								end
							end
						end
					end

					// GAP最后输入与归约输出完成必须分开。
					ST_POST_END:begin
						if((reg_opcode == 2 || flag_stream_done == 1'b1) && (reg_opcode != 4 || flag_post_done == 1'b1) && i_packer_busy == 1'b0 && i_group_write_done == 1'b1)begin
							compute_done_o <= 1'b1; // 全部计算结果被下游接受。
						end
					end

					// 空闲或未列出的数据任务不推进深度游标。
					default:begin
						cnt_pair <= cnt_pair;   // 没有通道对握手时保留当前权重地址。
					end
				endcase
			end
		end
	end

	//----------------状态机区域----------------//
	// 当前状态与数据过程使用同一硬复位和同步清控制请求。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			state_current <= ST_IDLE;           // 硬复位立即撤销旧任务阶段。
		end else if(i_soft_reset == 1'b1)begin
			state_current <= ST_IDLE;           // 通路共同同步清控制后返回空闲。
		end else begin
			state_current <= state_next;        // 提交当前完整握手得到的次态。
		end
	end

	// 下一状态组合逻辑只选择控制阶段，数据更新保留在原时序过程。
	always@(*)begin
		state_next = state_current;             // 停顿或未完成握手时维持当前阶段。
		if(i_dependency_error == 1'b1 && state_current != ST_IDLE && state_current != ST_ERROR)begin
			state_next = ST_ERROR;              // 依赖错误优先于任何调度。
		end else if(o_start_ready == 1'b1 && i_start == 1'b1)begin
			state_next = ST_COUNTS;             // 接受配置后开始数量准备。
		end else if(flag_step == 1'b1)begin
			case(state_current)

				// 配置数量形成后准备输出宽度。
				ST_COUNTS:begin
					state_next = ST_GEOMETRY;   // 准备层数量之后准备横向几何。
				end

				// 横向数量形成后准备空间数量。
				ST_GEOMETRY:begin
					state_next = ST_SPATIAL;    // 准备横向几何之后寄存空间数量。
				end

				// 空间数量寄存后独立检查范围。
				ST_SPATIAL:begin
					state_next = ST_CHECK;      // 寄存空间数量之后检查派生范围。
				end

				// 基本字段合法才选择算子路径。
				ST_CHECK:begin
					if(flag_bad == 1'b1)begin
						state_next = ST_ERROR;  // 检查派生范围之后停止新调度并等待复位。
					end else if(flag_compute == 1'b1)begin
						state_next = ST_TILE;   // 检查派生范围之后锁存分块尾部。
					end else if(reg_opcode == 2)begin
						state_next = ST_POST_BLOCK; // 检查派生范围之后请求Pool真实缓存块。
					end else begin
						state_next = ST_POST_START; // 检查派生范围之后启动整层HWC输入流。
					end
				end

				// 当前tile边界寄存后发布双请求。
				ST_TILE:begin
					state_next = ST_REQUEST;    // 锁存分块尾部之后接收双装载请求。
				end

				// 两个请求必须分别接受一次。
				ST_REQUEST:begin
					if((flag_scan_sent == 1'b1 || i_scan_ready == 1'b1) && (flag_load_sent == 1'b1 || i_load_ready == 1'b1))begin
						state_next = ST_READY;  // 接收双装载请求之后确认当前响应标签。
					end else begin
						state_next = ST_REQUEST; // 接收双装载请求之后接收双装载请求。
					end
				end

				// 不匹配的ready终止，不以旧层资格开始计算。
				ST_READY:begin
					if(flag_tags_bad == 1'b1)begin
						state_next = ST_ERROR;  // 确认当前响应标签之后停止新调度并等待复位。
					end else if(i_feature_ready == 1'b1 && i_weight_ready == 1'b1)begin
						state_next = ST_ADDRESS; // 确认当前响应标签之后寄存共同读地址。
					end else begin
						state_next = ST_READY;  // 确认当前响应标签之后确认当前响应标签。
					end
				end

				// 同步地址边界之后才发读。
				ST_ADDRESS:begin
					state_next = ST_READ;       // 寄存共同读地址之后共同读取特征及权重。
				end

				// 等待两个缓存共同接受。
				ST_READ:begin
					if(flag_read == 1'b1)begin
						state_next = ST_RESPONSE; // 共同读取特征及权重之后等待同步数据资格。
					end else begin
						state_next = ST_READ;   // 共同读取特征及权重之后共同读取特征及权重。
					end
				end

				// 同步数据资格对齐才进入MAC。
				ST_RESPONSE:begin
					if(i_weight_out_valid == 1'b1 && (column_valid_o == 1'b0 || i_feature_out_valid == 1'b1))begin
						state_next = ST_PAIR;   // 等待同步数据资格之后接受输入通道对。
					end else begin
						state_next = ST_RESPONSE; // 等待同步数据资格之后等待同步数据资格。
					end
				end

				// 深度向量末pair进入结果等待。
				ST_PAIR:begin
					if(i_array_ready == 1'b1)begin
						if(o_pair_last == 1'b1)begin
							state_next = ST_COLUMN; // 接受输入通道对之后等待实际CU结果及提交。
						end else begin
							state_next = ST_ADDRESS; // 接受输入通道对之后寄存共同读地址。
						end
					end else begin
						state_next = ST_PAIR;   // 接受输入通道对之后接受输入通道对。
					end
				end

				// 实际完整结果消费或者填充列提交后才能清当前向量。
				ST_COLUMN:begin
					if(reg_drain != 0)begin
						state_next = ST_COLUMN; // 已接受向量的流水等待计数尚未结束。
					end else if(i_cu_valid == 1'b1)begin
						if(flag_emit == 1'b0 || (i_bundle_ready == 1'b1 && i_fifo_full == 1'b0))begin
							state_next = ST_RETIRE; // 完整点已接受或stride丢弃后释放CU输出holding。
						end else begin
							state_next = ST_COLUMN; // B5或FIFO尚未许可，保留已寄存的完整CU结果。
						end
					end else if(!mode_o[1] && cnt_column < reg_kernel - 1'b1 && flag_commit_seen == 1'b1)begin
						state_next = ST_RETIRE; // 行首填充列确认实际commit后清除当前向量资格。
					end else begin
						state_next = ST_COLUMN; // 既没有完整点也没有填充列提交，继续等待实际事件。
					end
				end

				// 行末检查实际事件及结果数量，行内只推进水平坐标。
				ST_RETIRE:begin
					if(cnt_column == reg_padded_width - 1'b1)begin
						if(!mode_o[1] && flag_row_seen == 1'b0)begin
							state_next = ST_ERROR; // 末扫描列缺失实际row_advance，禁止授权新行覆盖。
						end else if(cnt_row == reg_output_height - 1'b1)begin
							if(spatial_index_o != cnt_spatial_total)begin
								state_next = ST_ERROR; // 空间结果总数不符，禁止进入下一输入分块。
							end else begin
								state_next = ST_FINISH; // 清除已消费CU标签之后通知D0扫描结束。
							end
						end else begin
							state_next = ST_ROW; // 清除已消费CU标签之后检查下一真实行。
						end
					end else begin
						state_next = ST_ADDRESS; // 清除已消费CU标签之后寄存共同读地址。
					end
				end

				// 只对未初装的真实新行请求覆盖。
				ST_ROW:begin
					if(row_new >= 17'sd3 && row_new < $signed({1'b0, reg_height}))begin
						state_next = ST_UPDATE; // 检查下一真实行之后授权新行向量覆盖。
					end else begin
						state_next = ST_ROTATE; // 检查下一真实行之后轮换物理行角色。
					end
				end

				// 覆盖授权接受之后等待独立完成。
				ST_UPDATE:begin
					if(i_update_ready == 1'b1)begin
						state_next = ST_UPDATE_WAIT; // 授权新行向量覆盖之后确认覆盖向量成功。
					end else begin
						state_next = ST_UPDATE; // 授权新行向量覆盖之后授权新行向量覆盖。
					end
				end

				// 整行全部列覆盖成功才轮换bank。
				ST_UPDATE_WAIT:begin
					if(flag_update_done == 1'b1)begin
						if(update_col_o == reg_width - 1'b1)begin
							state_next = ST_ROTATE; // 确认覆盖向量成功之后轮换物理行角色。
						end else begin
							state_next = ST_UPDATE; // 确认覆盖向量成功之后授权新行向量覆盖。
						end
					end else begin
						state_next = ST_UPDATE_WAIT; // 确认覆盖向量成功之后确认覆盖向量成功。
					end
				end

				// stride跳行中的每个输入行都单独轮换。
				ST_ROTATE:begin
					if(reg_top + 17'sd1 == reg_target_top)begin
						state_next = ST_ADDRESS; // 轮换物理行角色之后寄存共同读地址。
					end else begin
						state_next = ST_ROW;    // 轮换物理行角色之后检查下一真实行。
					end
				end

				// 结束脉冲仅发布一个推进沿。
				ST_FINISH:begin
					state_next = ST_FINISH_WAIT; // 通知D0扫描结束之后确认本tile排空。
				end

				// 本tile完成后等待通知和B5空闲。
				ST_FINISH_WAIT:begin
					if(flag_scan_done == 1'b1 && i_packer_busy == 1'b0)begin
						if(tile_index_o == reg_tiles - 1'b1)begin
							state_next = ST_GROUP; // 确认本tile排空之后确认当前组HP2响应。
						end else begin
							state_next = ST_TILE; // 确认本tile排空之后锁存分块尾部。
						end
					end else begin
						state_next = ST_FINISH_WAIT; // 确认本tile排空之后确认本tile排空。
					end
				end

				// 当前组HP2响应屏障完成后才换组。
				ST_GROUP:begin
					if(i_packer_busy == 1'b0 && i_group_write_done == 1'b1)begin
						if(group_index_o == reg_groups - 1'b1)begin
							state_next = ST_IDLE; // 确认当前组HP2响应之后空闲等待新层。
						end else begin
							state_next = ST_TILE; // 确认当前组HP2响应之后锁存分块尾部。
						end
					end else begin
						state_next = ST_GROUP;  // 确认当前组HP2响应之后确认当前组HP2响应。
					end
				end

				// 整层输入流开始后不重复请求。
				ST_POST_START:begin
					if(i_post_stream_ready == 1'b1)begin
						state_next = ST_POST_TOKEN; // 启动整层HWC输入流之后接受四通道读坐标。
					end else begin
						state_next = ST_POST_START; // 启动整层HWC输入流之后启动整层HWC输入流。
					end
				end

				// 缓存块请求接受后等待绑定该块的完成。
				ST_POST_BLOCK:begin
					if(i_post_block_ready == 1'b1)begin
						state_next = ST_POST_BLOCK_WAIT; // 请求Pool真实缓存块之后等待当前Pool块装载。
					end else begin
						state_next = ST_POST_BLOCK; // 请求Pool真实缓存块之后请求Pool真实缓存块。
					end
				end

				// 数据与成功状态齐备才开始Pool真实读。
				ST_POST_BLOCK_WAIT:begin
					if(flag_block_done == 1'b1)begin
						state_next = ST_POST_TOKEN; // 等待当前Pool块装载之后接受四通道读坐标。
					end else begin
						state_next = ST_POST_BLOCK_WAIT; // 等待当前Pool块装载之后等待当前Pool块装载。
					end
				end

				// Pool前三个角点仍停留token阶段。
				ST_POST_TOKEN:begin
					if(i_post_ready == 1'b1 && i_fifo_full == 1'b0 && (reg_opcode != 2 || post_stage_o == 3))begin
						state_next = ST_POST_WAIT; // 接受四通道读坐标之后确认后处理结果消费。
					end else begin
						state_next = ST_POST_TOKEN; // 接受四通道读坐标之后接受四通道读坐标。
					end
				end

				// 保持HWC顺序，并在新Pool块或窗口重新发加载请求。
				ST_POST_WAIT:begin
					if(reg_opcode == 4 || flag_post_done == 1'b1)begin
						if(group_index_o != reg_groups - 1'b1)begin
							if(reg_opcode == 2 && group_index_o[6:0] == 127)begin
								state_next = ST_POST_BLOCK; // 当前quad127结束，跨512通道边界装载下一块。
							end else begin
								state_next = ST_POST_TOKEN; // 空间点内下一quad继续当前缓存块或连续输入流。
							end
						end else if(cnt_row == (reg_opcode == 2 ? reg_output_height - 1'b1 : reg_height - 1'b1) && cnt_column == (reg_opcode == 2 ? reg_output_width - 1'b1 : {1'b0, reg_width} - 1'b1))begin
							state_next = ST_POST_END; // 确认后处理结果消费之后确认输入DMA与归约输出。
						end else if(reg_opcode == 2)begin
							state_next = ST_POST_BLOCK; // 下一池化窗口重新建立首真实行与第零通道块。
						end else begin
							state_next = ST_POST_TOKEN; // 全通道遍历结束后读取下一HWC空间位置的首quad。
						end
					end else begin
						state_next = ST_POST_WAIT; // 确认后处理结果消费之后确认后处理结果消费。
					end
				end

				// GAP独立等待归约输出，DMA及HP2状态单独确认。
				ST_POST_END:begin
					if((reg_opcode == 2 || flag_stream_done == 1'b1) && (reg_opcode != 4 || flag_post_done == 1'b1) && i_packer_busy == 1'b0 && i_group_write_done == 1'b1)begin
						state_next = ST_IDLE;   // 确认输入DMA与归约输出之后空闲等待新层。
					end else begin
						state_next = ST_POST_END; // 确认输入DMA与归约输出之后确认输入DMA与归约输出。
					end
				end

				// 空闲及错误只等待明确开始或复位。
				// 空闲无层请求，错误态由复位恢复。
				ST_IDLE:begin
					state_next = state_current; // 无合法开始时保留空闲，错误记录保持到复位。
				end

				// 错误阶段禁止创建任何新请求。
				ST_ERROR:begin
					state_next = ST_ERROR;      // 首错误保持，必须由控制复位恢复。
				end

				// 未识别的阶段保留状态并不产生任务。
				default:begin
					state_next = state_current; // 确认输入DMA与归约输出之后当前阶段保持。
				end
			endcase
		end else begin
			state_next = state_current;         // 用户暂停或寄存反压保持阶段。
		end
	end

	//-------------状态任务处理区域-------------//
	// 完成脉冲按FCLK锁存，入口清旧资格，不因ce暂停丢失。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_scan_done <= 1'b0;             // 旧扫描完成无效。
			flag_update_done <= 1'b0;           // 旧覆盖完成无效。
			flag_post_done <= 1'b0;             // 旧后处理结果无效。
			flag_stream_done <= 1'b0;           // 旧输入流完成无效。
			flag_block_done <= 1'b0;            // 旧池化块完成无效。
		end else if(i_soft_reset == 1'b1 || state_current == ST_IDLE)begin
			flag_scan_done <= 1'b0;             // 新层重新建立扫描资格。
			flag_update_done <= 1'b0;           // 新层重新等待覆盖通知。
			flag_post_done <= 1'b0;             // 新层重新等待结果通知。
			flag_stream_done <= 1'b0;           // 新层重新等待流状态。
			flag_block_done <= 1'b0;            // 新层重新等待块装载。
		end else begin
			if(o_scan_finish == 1'b1)begin
				flag_scan_done <= 1'b0;         // 每tile独立等待扫描完成。
			end else if(i_scan_done == 1'b1)begin
				flag_scan_done <= 1'b1;         // 暂停时保存单拍响应。
			end
			if(o_update_req == 1'b1 && i_update_ready == 1'b1)begin
				flag_update_done <= 1'b0;       // 新覆盖清旧完成资格。
			end else if(i_update_done == 1'b1)begin
				flag_update_done <= 1'b1;       // 成功完成保持到消费。
			end
			if(o_post_valid == 1'b1 && i_post_ready == 1'b1)begin
				flag_post_done <= 1'b0;         // 当前token后重新等待输出。
			end else if(i_post_done == 1'b1)begin
				flag_post_done <= 1'b1;         // 下游完成可跨暂停保持。
			end
			if(o_post_stream_req == 1'b1 && i_post_stream_ready == 1'b1)begin
				flag_stream_done <= 1'b0;       // 新流清除旧DMA完成。
			end else if(i_post_stream_done == 1'b1)begin
				flag_stream_done <= 1'b1;       // 整层输入成功状态保持。
			end
			if(o_post_block_req == 1'b1 && i_post_block_ready == 1'b1)begin
				flag_block_done <= 1'b0;        // 当前块重新等待新通知。
			end else if(i_post_block_done == 1'b1)begin
				flag_block_done <= 1'b1;        // 当前真实块完成保持。
			end
		end
	end

	// shortcut: 一个空间列在途，不设标签队列；实测吞吐不足后再增加有界流水。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_run <= 1'b0;                   // 异步撤销数据通路推进资格。
		end else if(i_soft_reset == 1'b1)begin
			flag_run <= 1'b0;                   // 同步撤销旧层推进资格。
		end else if(i_ce == 1'b1)begin
			flag_run <= !i_fifo_full && (!flag_compute || state_current <= ST_TILE || i_bundle_ready || flag_hold); // 配置不依赖尚未建立的lane资格，结果holding独立等待B5。
		end
	end

endmodule
