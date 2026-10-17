`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/09 00:00:00
// Design Name:     instruction_distributor
// Module Name:     instruction_distributor
// Description:     description/instruction_distributor_Design.pdf
// Simulations:     testbench/vivado/2021.1/instruction_distributor
//
// Referrences:
// File Format      File Name
// 1.Book           docs/spec/instruction_distributor_spec.md; docs/设计文档.md 4.2、5.3、5.4
//
// Dependencies:
// Module Name      Version
//
// Version:         V1.0
// Revision Date:   2026/10/09 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/09       V1.0        Codex             Create V1 cached instruction distributor.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月09日
// 设计名称:        instruction_distributor
// 模块名称:        instruction_distributor
// 模块说明:        Description/instruction_distributor_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/instruction_distributor
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           docs/spec/instruction_distributor_spec.md; docs/设计文档.md 4.2、5.3、5.4
//
// 依赖文件:
// 模块名称         版本
//
// 当前版本:        V1.0
// 修订日期:        2026年10月09日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月09日   V1.0        Codex             创建V1双表缓存指令分发器

module instruction_distributor
(
	//-----------------用户接口-----------------//
	input i_clk,                                // 与GP及四控制器共用FCLK。
	input i_rstn,                               // 低有效异步复位，上游同域同步释放。
	input i_ce,                                 // 冻结算法准备和分发；已发布GP事务继续握手。
	input i_soft_reset,                         // GP及HP静止后与控制器/结果队列共同同步清控制。
	input i_start,                              // PS仅一次启动整个模型。
	input i_clear_done,                         // 空闲时清粘滞done/error；故障控制器还须共同复位。
	input [31:0]i_model_base,                   // 64字节对齐的Instructions模型头地址。
	input [31:0]i_model_bytes,                  // PS实际装载的现有命令文件长度，不能取自未经校验的模型头。

	//CONTROLLER接口
	input [3:0]i_controller_ready,              // bit0/1/2/3分别Feature/Weight/CAL/OUTPUT的配置资格。
	input [3:0]i_controller_busy,               // 四控制器尚有在途工作，完成层时分别检查。
	input [3:0]i_controller_error,              // 四控制器粘滞错误源。
	input [15:0]i_controller_error_code,        // 四个四位诊断按Feature至OUTPUT从低到高排列。
	input i_compute_done,                       // CAL单FCLK完成，跨暂停锁存。
	input i_output_done,                        // OUTPUT最终写成功通知，和compute_done分开锁存。
	input i_packer_busy,                        // 结果级仍有未入队数据。
	input i_spatial_fifo_empty,                 // 空间FIFO独立排空资格。
	input i_bypass_fifo_empty,                  // 旁路FIFO独立排空资格。
	output o_start_ready,                       // 空闲且上次结果/工作及粘滞状态已清才允许启动。
	output o_busy,                              // 从取头到最终GP写响应均为忙。
	output o_done,                              // 全部层及GP周期记录成功后粘滞完成。
	output o_error,                             // 首错误粘滞，失败时不宣称done。
	output [7:0]o_error_code,                   // 模型范围/头/文件/写区/读流/读状态/层配置/依赖/超时/写状态/早写状态。
	output [3:0]o_error_source,                 // 出错四控制器源；GP/模型错误为零。
	output [15:0]o_controller_error_code,       // 首控制器错误发生时锁存完整诊断。
	output o_runtime_error,                     // GP周期记录没有成功提交，PS须读本地状态。
	output o_abort,                             // 首错误后停止新层，并由D5接入正在运行的控制器依赖终止。
	output [63:0]o_cycles,                      // 从start接受至进入周期写回的实际FCLK数，包含取指及暂停。
	output [63:0]o_layer_cycles,                // 当前层start接受后的实际FCLK，包含暂停。
	output [7:0]o_current_layer,                // 当前同层配对的基础/扩展缓存索引，含255。
	output [255:0]o_base_instruction,           // BRAM同步读并锁存的现有基础配置，执行期间稳定。
	output [255:0]o_extension,                  // 同层工程扩展配置，保持原位序。
	output [3:0]o_layer_start,                  // 四模块同沿配置/start广播，只持续一个实际接受周期。

	//READ_CMD接口
	output o_read_cmd_valid,                    // GP MM2S命令发布后保持至READY。
	input i_read_cmd_ready,                     // GP MM2S接受命令。
	output [71:0]o_read_cmd_data,               // TAG0 Full命令，头64字节，双表各N×32字节。
	input i_read_data_valid,                    // GP 32位读数据有效。
	output o_read_data_ready,                   // 真实读事务接收资格，不受ce暂停阻断。

	//READ接口
	input [31:0]i_read_data,                    // 小端32位word；每条记录分别接收8个有效beat。
	input [3:0]i_read_keep,                     // 必须为f。
	input i_read_last,                          // 仅在当前读命令末beat拉高。
	input i_read_status_valid,                  // 唯一在途GP MM2S状态。
	output o_read_status_ready,                 // 数据发送及状态阶段接收，不受ce限制。
	input [7:0]i_read_status,                   // 精确80且晚于末读数据才成功。

	//WRITE_CMD接口
	output o_write_cmd_valid,                   // GP S2MM周期记录命令有效，直到READY。
	input i_write_cmd_ready,                    // GP S2MM接受周期记录命令。
	output [71:0]o_write_cmd_data,              // TAG0/EOF/INCR，写回固定16字节。
	output o_write_data_valid,                  // 4个32位周期记录word，载荷保持至READY。
	input i_write_data_ready,                   // GP S2MM接受周期记录word。

	//WRITE接口
	output [31:0]o_write_data,                  // word0/1周期低/高，word2层号，word3诊断16位/错误8位/状态8位。
	output [3:0]o_write_keep,                   // 固定f。
	output o_write_last,                        // 第四个word对应当前命令TLAST。
	input i_write_status_valid,                 // GP周期记录S2MM状态。
	output o_write_status_ready,                // 接收实际周期写回状态，暂停也接收。
	input [7:0]i_write_status                   // 精确80且晚于末写数据才提交done。
);

	//---------------状态参数区域---------------//
	localparam ST_IDLE = 3'd0;                  // 等待PS整网启动。
	localparam ST_READ_HEADER = 3'd1;           // 读取并验证64字节现有头。
	localparam ST_READ_MODEL_INFO = 3'd2;       // 分别预取两张完整表。
	localparam ST_DISPATCH = 3'd3;              // 同层同步读并准备四路启动。
	localparam ST_WAIT_LAYER_DONE = 3'd4;       // 等待分离完成与全部结果排空。
	localparam ST_WRITE_RUNTIME_INFO = 3'd5;    // 写回总周期、层号和状态。

	//-----------------计数信号-----------------//
	reg [11:0]cnt_read_word = 0;                // 单表最多2048个32位beat。
	reg [1:0]cnt_write_word = 0;                // 固定四word周期记录游标。
	reg [8:0]cnt_layer = 0;                     // 层数256必须保留第九位。

	//----------------状态机信号----------------//
	reg [2:0]state_current = ST_IDLE;           // 六主状态按算法边界组织。
	reg [2:0]state_next = ST_IDLE;              // 协议阶段可在暂停中推进。
	wire state_read_state;                      // 当前属于模型读取主状态。

	//----------------寄存器信号----------------//
	reg [3:0]reg_phase = 0;                     // 主状态内的准备、命令、数据和状态阶段。
	reg [511:0]reg_header = 0;                  // 小端16word模型头，先校验再使用。
	reg [31:0]reg_model_base = 0;               // 整网锁存的PS模型首址。
	reg [31:0]reg_model_bytes = 0;              // 来自PS实际文件长度。
	reg [32:0]reg_model_limit = 0;              // 模型末址宽化防回绕。
	reg [31:0]reg_table_bytes = 0;              // 单表长度N乘32。
	reg [32:0]reg_expected_extension = 0;       // canonical扩展表相对偏移。
	reg [32:0]reg_expected_file = 0;            // canonical文件补齐后长度。
	reg [31:0]reg_runtime_address = 0;          // 已通过范围检查的周期写区。
	reg [32:0]reg_runtime_limit = 0;            // 16字节写回末址。
	reg reg_extension_table = 0;                // 基础表成功后再取扩展表。
	reg [31:0]reg_command_address = 0;          // 已发布GP命令地址保持。
	reg [22:0]reg_command_bytes = 0;            // 已发布GP命令BTT保持。
	reg [11:0]reg_read_words = 0;               // 当前读命令真实word数。
	reg [127:0]reg_runtime_payload = 0;         // 周期记录四word在反压期间固定。
	reg [255:0]reg_base_read = 0;               // 同步BRAM读数据，无RAM清零依赖。
	reg [255:0]reg_extension_read = 0;          // 与基础表同索引同步读数据。
	(* ram_style = "block" *) reg [31:0]reg_base_first[0:255]; // 输入特征地址独立缓存。
	(* ram_style = "block" *) reg [31:0]reg_extension_first[0:255]; // 权重DDR首址所在扩展bank。
	(* ram_style = "block" *) reg [31:0]reg_base_second[0:255]; // 结果张量指针对应第二个基础word。
	(* ram_style = "block" *) reg [31:0]reg_extension_second[0:255]; // INT64偏置区域指针。
	(* ram_style = "block" *) reg [31:0]reg_base_third[0:255]; // 输入总量与写切换低位共用存储。
	(* ram_style = "block" *) reg [31:0]reg_extension_third[0:255]; // 残差辅助输入地址。
	(* ram_style = "block" *) reg [31:0]reg_base_fourth[0:255]; // 空间切换高段及行步长低段。
	(* ram_style = "block" *) reg [31:0]reg_extension_fourth[0:255]; // 输入及输出的纵向几何。
	(* ram_style = "block" *) reg [31:0]reg_base_fifth[0:255]; // 行跨度高位、宽度和权重数量低段。
	(* ram_style = "block" *) reg [31:0]reg_extension_fifth[0:255]; // DDR补齐输入和输出通道数。
	(* ram_style = "block" *) reg [31:0]reg_base_sixth[0:255]; // 权重高段、深度及输出核数低位。
	(* ram_style = "block" *) reg [31:0]reg_extension_sixth[0:255]; // 量化右移、算子和末层标志。
	(* ram_style = "block" *) reg [31:0]reg_base_seventh[0:255]; // 输出核数高段、模式、步长与结果长度低段。
	(* ram_style = "block" *) reg [31:0]reg_extension_seventh[0:255]; // 矩阵逻辑输入长度。
	(* ram_style = "block" *) reg [31:0]reg_base_eighth[0:255]; // 层序号、保留区及输出总量高段。
	(* ram_style = "block" *) reg [31:0]reg_extension_eighth[0:255]; // 单层FCLK超时阈值。

	// 逻辑维度与算子译码
	reg [7:0]reg_fault_code = 0;                // 当前失败类型选择。

	//-----------------标志信号-----------------//
	reg flag_header_valid = 0;                  // 只有完整合法头才能授权周期写回。
	reg flag_compute_done = 0;                  // 当前层CAL完成脉冲锁存。
	reg flag_output_done = 0;                   // 当前层OUTPUT成功完成独立锁存。
	wire flag_start;                            // PS整网启动实际接受。
	wire flag_launch;                           // 四接收端同沿接受当前配置。
	wire flag_read_command;                     // 已发布MM2S命令的真实握手。
	wire flag_read_data;                        // 32位数据实际进入头或指令缓存。
	wire flag_read_status;                      // MM2S状态实际接受。
	wire flag_write_command;                    // GP周期命令真实接受。
	wire flag_write_data;                       // 周期记录word真实接受。
	wire flag_write_status;                     // 最终写应答的真实消费资格。
	wire flag_cache_read;                       // 同层两表同步读请求。
	wire flag_layer_finished;                   // 两个完成及四模块/结果/FIFO独立屏障。
	wire flag_model_bad;                        // PS提供的模型范围错误。
	wire flag_header_bad;                       // 头固定字段或层数错误。
	wire flag_file_bad;                         // 双表偏移或真实文件长度错误。
	wire flag_runtime_bad;                      // 计时写区越界、未对齐或覆盖模型。
	wire flag_layer_bad;                        // 层配置基础字段或索引last错误。
	wire flag_controller_fault;                 // 已运行控制器出现错误。
	wire flag_timeout;                          // 当前层真实FCLK超时。
	reg flag_fault = 0;                         // 首故障在当前周期终止算法。

	//-----------------其他信号-----------------//
	//逻辑维度与算子字段
	wire [12:0]logical_depth;                   // 零编码恢复4096个输入通道。
	wire [12:0]logical_outputs;                 // 零编码恢复4096个输出核。
	wire [7:0]cache_write_index;                // 当前有效word所属的完整层记录索引。
	wire [3:0]opcode;                           // 扩展字现有算子编码。

	//-----------------输出信号-----------------//
	//用户接口
	wire start_ready_o;                         // 新整网的真实接受资格。
	wire busy_o;                                // 含GP末写状态的全任务忙。
	reg done_o = 0;                             // 仅成功周期写回后粘滞。
	wire error_o;                               // 首诊断的粘滞错误资格。
	reg [7:0]error_code_o = 0;                  // 第一项整网错误原因。
	reg [3:0]error_source_o = 0;                // 四控制器错误来源。
	reg [15:0]controller_error_code_o = 0;      // 完整控制器错误快照。
	reg runtime_error_o = 0;                    // GP周期记录没有成功提交。
	wire abort_o;                               // 交由顶层终止正在工作的控制器。
	reg [63:0]cycles_o = 0;                     // 实际整网FCLK计数，写回阶段冻结。
	reg [63:0]layer_cycles_o = 0;               // 当前层实际FCLK计数。
	reg [7:0]current_layer_o = 0;               // 同层表索引0至255。
	reg [255:0]base_instruction_o = 0;          // 当前稳定基础指令。
	reg [255:0]extension_o = 0;                 // 当前稳定工程扩展字。
	wire [3:0]layer_start_o;                    // 共用资格的同沿四路start。

	//用户接口
	wire read_cmd_valid_o;                      // MM2S已发布的稳定命令。
	wire [71:0]read_cmd_data_o;                 // Full DataMover读命令。

	//用户接口
	wire read_data_ready_o;                     // 暂停期间仍接收真实GP读流。

	//用户接口
	wire read_status_ready_o;                   // 单在途读状态接收。

	//用户接口
	wire write_cmd_valid_o;                     // S2MM周期记录稳定命令。
	wire [71:0]write_cmd_data_o;                // 固定16字节Full写命令。

	//用户接口
	wire write_data_valid_o;                    // 当前周期记录word有效。

	//用户接口
	wire [31:0]write_data_o;                    // 计时载荷按小端顺序发送。
	wire [3:0]write_keep_o;                     // 每个GP word全字节有效。
	wire write_last_o;                          // 记录末word事务界限。

	//用户接口
	wire write_status_ready_o;                  // 最后真实写响应独立接收。

	//---------------其他信号连线---------------//
	//其他信号连线
	// 基本配置与实际协议事件
	assign logical_depth = base_instruction_o[183:172] == 0 ? 13'd4096 : {1'b0, base_instruction_o[183:172]}; // 逻辑通道不截断4096。
	assign logical_outputs = base_instruction_o[195:184] == 0 ? 13'd4096 : {1'b0, base_instruction_o[195:184]}; // 逻辑Cout保持完整范围。
	assign cache_write_index = cnt_read_word[10:3]; // 单表32位word游标转换成256层地址。
	assign opcode = extension_o[171:168];       // 使用原扩展word5字段。
	assign state_read_state = state_current == ST_READ_HEADER || state_current == ST_READ_MODEL_INFO; // GP取指两主状态共享协议。
	assign flag_start = start_ready_o && i_start; // PS无需逐层干预。
	assign flag_launch = state_current == ST_DISPATCH && reg_phase == 4 && i_ce && &i_controller_ready && !flag_fault; // 四配置端同时接受才启动。
	assign flag_read_command = read_cmd_valid_o && i_read_cmd_ready; // ce暂停不能漏记命令接受。
	assign flag_read_data = read_data_ready_o && i_read_data_valid; // 指令流以实际有效拍计数。
	assign flag_read_status = read_status_ready_o && i_read_status_valid; // 成功状态和数据数量分开。
	assign flag_write_command = write_cmd_valid_o && i_write_cmd_ready; // 发布后的计时命令仍真实握手。
	assign flag_write_data = write_data_valid_o && i_write_data_ready; // 写回word仅真实接受后换载荷。
	assign flag_write_status = write_status_ready_o && i_write_status_valid; // done必须等待GP末状态。
	assign flag_cache_read = state_current == ST_DISPATCH && reg_phase == 0 && i_ce && !flag_fault; // 两BRAM使用同一个层索引。

	//CONTROLLER接口
	assign flag_layer_finished = (flag_compute_done || i_compute_done) && (flag_output_done || i_output_done) && i_controller_busy == 0 && !i_packer_busy && i_spatial_fifo_empty && i_bypass_fifo_empty; // 不用单一模糊done。

	//其他信号连线
	assign flag_model_bad = reg_model_base[5:0] != 0 || reg_model_bytes < 64 || reg_model_base < 32'h04000000 || reg_model_limit > 33'h004200000; // 宽化模型末址先挡住越区和回绕。
	assign flag_header_bad = reg_header[63:0] != 64'h0000444d434e4e43 || reg_header[95:64] != 2 || reg_header[127:96] != 64 || reg_header[159:128] != 16 || reg_header[191:160] == 0 || reg_header[191:160] > 256 || reg_header[223:192] != 64 || reg_header[255:224] != 32 || reg_header[319:288] != 32 || reg_header[383:352] != 1 || reg_header[415:384] != 1 || reg_header[511:480] != 0; // 固定8CU包标识才允许取指，旧12CU载荷在层广播前拒绝。
	assign flag_file_bad = {1'b0, reg_header[287:256]} != reg_expected_extension || {1'b0, reg_header[447:416]} != reg_expected_file || reg_header[447:416] != reg_model_bytes; // 两表及padding须完全落在实际文件内。
	assign flag_runtime_bad = reg_runtime_address[2:0] != 0 || reg_runtime_address < 32'h04000000 || reg_runtime_limit > 33'h004200000 || !(reg_runtime_limit <= {1'b0, reg_model_base} || {1'b0, reg_runtime_address} >= reg_model_limit); // 16字节写区不覆盖头、双表或padding。
	assign flag_layer_bad = base_instruction_o[255:236] != 0 || base_instruction_o[235:228] != current_layer_o || extension_o[167] != ({1'b0, current_layer_o} == cnt_layer - 1'b1) || opcode > 4 || base_instruction_o[199:196] > 3 || extension_o[165:160] > 47 || extension_o[177:172] > 47 || extension_o[183:178] > 47 || base_instruction_o[147:136] == 0 || extension_o[111:96] == 0 || extension_o[127:112] == 0 || base_instruction_o[87:64] == 0 || base_instruction_o[65:64] != 0 || base_instruction_o[227:204] == 0 || base_instruction_o[205:204] != 0 || base_instruction_o[2:0] != 0 || base_instruction_o[34:32] != 0 || extension_o[159:144] != ((logical_outputs + 13'd3) & 13'h1ffc) || (opcode == 0 && (base_instruction_o[199:196] == 3 || base_instruction_o[201:200] == 0 || base_instruction_o[201:200] > 2 || base_instruction_o[203:202] > 1)) || (opcode == 1 && (base_instruction_o[199:196] != 3 || base_instruction_o[183:172] != 0 || extension_o[223:192] == 0 || extension_o[223:192] > 65532)) || (opcode >= 2 && logical_depth != logical_outputs) || (opcode == 4 && logical_outputs > 2048); // 完整几何和静态总量仍由软件及所属控制器检查。
	assign flag_controller_fault = (state_current == ST_DISPATCH || state_current == ST_WAIT_LAYER_DONE) && i_controller_error != 0; // 任何控制器错误都禁止下一层。
	assign flag_timeout = state_current == ST_WAIT_LAYER_DONE && !flag_layer_finished && extension_o[255:224] != 0 && (layer_cycles_o[63:32] != 0 || layer_cycles_o[31:0] >= extension_o[255:224]); // 实际FCLK包含用户暂停。

	//用户接口
	assign start_ready_o = i_rstn && i_ce && state_current == ST_IDLE && !done_o && error_code_o == 0 && i_controller_busy == 0 && !i_packer_busy && i_spatial_fifo_empty && i_bypass_fifo_empty; // 上次任务资格清除后再接受模型。
	assign busy_o = state_current != ST_IDLE;   // GP周期最后响应也属于本任务。
	assign error_o = error_code_o != 0;         // 保留首错至clear或共同复位。
	assign abort_o = error_o;                   // 顶层据此终止活跃控制器。
	assign layer_start_o = {4{flag_launch}};    // 四个配置总线在同沿共同锁存。
	assign read_cmd_valid_o = i_rstn && state_read_state && reg_phase == 1; // 命令发布后不受ce撤销。
	assign read_cmd_data_o = {8'd0, reg_command_address, 9'h081, reg_command_bytes}; // 固定TAG0/EOF/INCR/DSA0。
	assign read_data_ready_o = i_rstn && state_read_state && reg_phase == 2; // 实际32位流接收阶段。
	assign read_status_ready_o = i_rstn && state_read_state && (reg_phase == 2 || reg_phase == 3); // 提前状态也需检测为故障。
	assign write_cmd_valid_o = i_rstn && state_current == ST_WRITE_RUNTIME_INFO && reg_phase == 1; // 计时命令到READY前稳定。
	assign write_cmd_data_o = {8'd0, reg_command_address, 9'h081, 23'd16}; // 固定四word计时及状态记录。
	assign write_data_valid_o = i_rstn && state_current == ST_WRITE_RUNTIME_INFO && reg_phase == 2; // ce暂停也允许已发布载荷握手。
	assign write_data_o = reg_runtime_payload[cnt_write_word * 32 +: 32]; // 仅接受后推进word选择。
	assign write_keep_o = 4'hf;                 // GP有效word完整写入。
	assign write_last_o = cnt_write_word == 3;  // 仅末word结束16字节事务。
	assign write_status_ready_o = i_rstn && state_current == ST_WRITE_RUNTIME_INFO && (reg_phase == 2 || reg_phase == 3); // 早状态不能被误认正常提交。

	//---------------输出信号连线---------------//
	//用户接口
	assign o_start_ready = start_ready_o;       // 传给PS启动仲裁的真实资格。
	assign o_busy = busy_o;                     // 包含计时响应等待的活动状态。
	assign o_done = done_o;                     // 保存给STATUS寄存器的成功标志。
	assign o_error = error_o;                   // PS读取首故障资格。
	assign o_error_code = error_code_o;         // 失败类型按八位完整传出。
	assign o_error_source = error_source_o;     // 来源位图供上层定位控制器。
	assign o_controller_error_code = controller_error_code_o; // 四个局部诊断的原始快照。
	assign o_runtime_error = runtime_error_o;   // 提醒软件改读寄存器诊断。
	assign o_abort = abort_o;                   // 上层使用粘滞失败封锁活跃数据面。
	assign o_cycles = cycles_o;                 // 传出已冻结的总计时。
	assign o_layer_cycles = layer_cycles_o;     // 传出单层超时观测计数。
	assign o_current_layer = current_layer_o;   // 暴露当前缓存索引供调试。
	assign o_base_instruction = base_instruction_o; // 向四控制器布线当前基础记录。
	assign o_extension = extension_o;           // 向四配置端共享当前扩展记录。
	assign o_layer_start = layer_start_o;       // 层首共同接受事件扇出到四端。

	//用户接口
	assign o_read_cmd_valid = read_cmd_valid_o; // GP读命令有效资格桥接。
	assign o_read_cmd_data = read_cmd_data_o;   // 稳定取指命令完整传到MM2S。

	//用户接口
	assign o_read_data_ready = read_data_ready_o; // GP读字接收使能出口。

	//用户接口
	assign o_read_status_ready = read_status_ready_o; // 读状态归属当前取指事务。

	//用户接口
	assign o_write_cmd_valid = write_cmd_valid_o; // 向S2MM呈现计时命令。
	assign o_write_cmd_data = write_cmd_data_o; // 记录的Full命令载荷出口。

	//用户接口
	assign o_write_data_valid = write_data_valid_o; // 当前计时word的发布资格。

	//用户接口
	assign o_write_data = write_data_o;         // 当前被保持的计时word传到GP。
	assign o_write_keep = write_keep_o;         // 完整32位word字节资格。
	assign o_write_last = write_last_o;         // 传出唯一周期事务结束标签。

	//用户接口
	assign o_write_status_ready = write_status_ready_o; // 软件暂停也保留GP写应答入口。

	//-------------输出信号处理区域-------------//
	//用户接口
	// 控制寄存器复位不清RAM；协议真实接受与ce算法推进分开。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_phase <= 0; reg_header <= 0;    // 旧头和协议资格立即撤销。
			reg_model_base <= 0; reg_model_bytes <= 0; reg_model_limit <= 0; // 旧模型范围失效。
			cnt_layer <= 0; reg_table_bytes <= 0; // 尚未验证层数量。
			reg_expected_extension <= 0; reg_expected_file <= 0; // 规范偏移重建。
			reg_runtime_address <= 0; reg_runtime_limit <= 0; // 不允许旧写区复用。
			reg_extension_table <= 0; reg_command_address <= 0; reg_command_bytes <= 0; // 旧GP命令失效。
			reg_read_words <= 0; cnt_read_word <= 0; cnt_write_word <= 0; reg_runtime_payload <= 0; // 旧读写游标无有效事务。
			flag_header_valid <= 0; flag_compute_done <= 0; flag_output_done <= 0; // 所有旧完成资格清除。
			done_o <= 0; error_code_o <= 0; error_source_o <= 0; controller_error_code_o <= 0; runtime_error_o <= 0; // 不报告旧任务状态。
			cycles_o <= 0; layer_cycles_o <= 0; current_layer_o <= 0; // 从新模型重新计时。
			base_instruction_o <= 0; extension_o <= 0; // 输出配置无旧指令资格。
		end else if(i_soft_reset == 1'b1)begin
			reg_phase <= 0; flag_header_valid <= 0; flag_compute_done <= 0; flag_output_done <= 0; // 共同同步清控制隔离旧缓存。
			done_o <= 0; error_code_o <= 0; error_source_o <= 0; controller_error_code_o <= 0; runtime_error_o <= 0; // 首错及完成重新建立。
			cycles_o <= 0; layer_cycles_o <= 0; current_layer_o <= 0; // 旧任务计数清除。
			base_instruction_o <= 0; extension_o <= 0; // 新模型装载前不输出旧配置。
		end else begin
			if(state_current != ST_IDLE && state_current != ST_WRITE_RUNTIME_INFO)begin
				cycles_o <= cycles_o + 64'd1;   // 暂停及取指均计实际FCLK。
			end
			if(state_current == ST_WAIT_LAYER_DONE)begin
				layer_cycles_o <= layer_cycles_o + 64'd1; // 单层超时按真实FCLK运行。
				if(i_compute_done == 1'b1)begin
					flag_compute_done <= 1;     // 完成脉冲与ce无关保存。
				end
				if(i_output_done == 1'b1)begin
					flag_output_done <= 1;      // 写回完成和计算完成独立保存。
				end
			end
			if(flag_fault == 1'b1)begin
				reg_phase <= 0; done_o <= 0;    // 错误不进入下一层。
				if(error_code_o == 0)begin
					error_code_o <= reg_fault_code; // 只锁存第一项失败。
					error_source_o <= flag_controller_fault ? i_controller_error : 4'd0; // 非控制器故障没有虚假源。
					controller_error_code_o <= flag_controller_fault ? i_controller_error_code : 16'd0; // 保留真实控制器诊断。
				end
				if(state_current == ST_WRITE_RUNTIME_INFO)begin
					runtime_error_o <= 1;       // 本地状态提示计时记录未提交。
				end
			end else if(flag_start == 1'b1)begin
				reg_model_base <= i_model_base; reg_model_bytes <= i_model_bytes; // 整网地址及真实文件长度一次锁存。
				reg_model_limit <= {1'b0, i_model_base} + {1'b0, i_model_bytes}; // 加法宽化防地址回绕。
				reg_header <= 0; reg_phase <= 0; reg_extension_table <= 0; flag_header_valid <= 0; // 开始重新取头与完整双表。
				flag_compute_done <= 0; flag_output_done <= 0; done_o <= 0; runtime_error_o <= 0; // 不复用旧完成资格。
				cycles_o <= 0; layer_cycles_o <= 0; current_layer_o <= 0; // 新模型从层零开始。
			end else begin
				case(state_current)

					// 空闲可清PS可见粘滞位，RAM依然必须重新装载。
					ST_IDLE:begin
						if(i_clear_done == 1'b1)begin
							done_o <= 0; error_code_o <= 0; error_source_o <= 0; controller_error_code_o <= 0; runtime_error_o <= 0; // 控制器故障本身由共同复位清除。
						end
					end

					// 头与双表采用同一单在途MM2S协议阶段。
					ST_READ_HEADER,ST_READ_MODEL_INFO:begin
						if(i_ce == 1'b1 && reg_phase == 0)begin
							reg_command_address <= state_current == ST_READ_HEADER ? reg_model_base : reg_model_base + (reg_extension_table ? reg_header[287:256] : 32'd64); // 读命令地址只在准备时形成。
							reg_command_bytes <= state_current == ST_READ_HEADER ? 23'd64 : reg_table_bytes[22:0]; // 不读取表间padding作为记录。
							reg_read_words <= state_current == ST_READ_HEADER ? 12'd16 : reg_table_bytes[13:2]; // 单表最多2048个word。
							cnt_read_word <= 0; reg_phase <= 1; // 下一FCLK发布稳定命令。
						end else if(flag_read_command == 1'b1)begin
							reg_phase <= 2;     // 真实命令接受后开放数据。
						end else if(flag_read_data == 1'b1)begin
							if(state_current == ST_READ_HEADER)begin
								reg_header <= {i_read_data, reg_header[511:32]}; // 16个有效32位beat按小端装头。
							end
							cnt_read_word <= cnt_read_word + 12'd1; // 不把停顿周期当有效word。
							if(cnt_read_word == reg_read_words - 1'b1)begin
								reg_phase <= 3; // 数据数目齐备还须等待成功状态。
							end
						end else if(flag_read_status == 1'b1)begin
							reg_phase <= 4;     // 已排除错误及早响应，保留成功资格。
						end else if(i_ce == 1'b1 && reg_phase == 4)begin
							if(state_current == ST_READ_HEADER)begin
								cnt_layer <= reg_header[168:160]; reg_table_bytes <= {18'd0, reg_header[168:160], 5'd0}; // 完整九位层数分拍派生表长度。
								reg_expected_extension <= ({19'd0, reg_header[168:160], 5'd0} + 33'd127) & 33'h1ffffffc0; // 基础表末址按64字节补齐。
								reg_runtime_address <= reg_header[351:320]; reg_phase <= 5; // 先锁存候选写区，尚未授权写。
							end else if(reg_extension_table == 1'b0)begin
								reg_extension_table <= 1; reg_phase <= 0; // 基础表成功才准备完整扩展表。
							end else begin
								reg_phase <= 7; // 两表均有真实成功状态。
							end
						end else if(i_ce == 1'b1 && reg_phase == 5 && state_current == ST_READ_HEADER)begin
							reg_expected_file <= (reg_expected_extension + {1'b0, reg_table_bytes} + 33'd63) & 33'h1ffffffc0; // 文件末padding独立阶段形成。
							reg_runtime_limit <= {1'b0, reg_runtime_address} + 33'd16; reg_phase <= 6; // 宽化计时记录写区末地址。
						end else if(i_ce == 1'b1 && reg_phase == 6 && state_current == ST_READ_HEADER)begin
							flag_header_valid <= 1; reg_phase <= 7; // 所有头及范围检查已排除失败。
						end else if(i_ce == 1'b1 && reg_phase == 7)begin
							reg_phase <= 0;     // 切换主状态时新阶段重新准备。
						end
					end

					// BRAM同步读取后再锁存当前完整512位配置。
					ST_DISPATCH:begin
						if(i_ce == 1'b1 && reg_phase < 2)begin
							reg_phase <= reg_phase + 4'd1; // 同步读及等待拍不启动控制器。
						end else if(i_ce == 1'b1 && reg_phase == 2)begin
							base_instruction_o <= reg_base_read; extension_o <= reg_extension_read; reg_phase <= 3; // 同层两条记录同时锁存。
						end else if(i_ce == 1'b1 && reg_phase == 3)begin
							reg_phase <= 4;     // 当前层基本检查通过后等待四ready。
						end else if(flag_launch == 1'b1)begin
							flag_compute_done <= 0; flag_output_done <= 0; layer_cycles_o <= 0; reg_phase <= 0; // 新层不得继承前层完成。
						end
					end

					// 独立完成锁存和四模块/结果/双FIFO屏障齐备才切层。
					ST_WAIT_LAYER_DONE:begin
						if(i_ce == 1'b1 && flag_layer_finished == 1'b1)begin
							reg_phase <= 0;     // 切层或周期写回都从准备阶段开始。
							if({1'b0, current_layer_o} != cnt_layer - 1'b1)begin
								current_layer_o <= current_layer_o + 8'd1; // 最大索引255后不再递增。
							end
						end
					end

					// shortcut: 单GP事务在途；取指实测成为瓶颈时再评估预取队列。
					ST_WRITE_RUNTIME_INFO:begin
						if(i_ce == 1'b1 && reg_phase == 0)begin
							reg_command_address <= reg_runtime_address; cnt_write_word <= 0; reg_phase <= 1; // 安全计时地址一旦发布保持不变。
							reg_runtime_payload <= {controller_error_code_o, error_code_o, 6'd0, error_o, !error_o, 24'd0, current_layer_o, cycles_o}; // 低word优先的固定16字节记录。
						end else if(flag_write_command == 1'b1)begin
							reg_phase <= 2;     // 命令接受才开放四word数据。
						end else if(flag_write_data == 1'b1)begin
							cnt_write_word <= cnt_write_word + 2'd1; // 只在真实数据接受后换载荷。
							if(cnt_write_word == 3)begin
								reg_phase <= 3; // 末word接受还不代表DDR写成功。
							end
						end else if(flag_write_status == 1'b1)begin
							done_o <= !error_o; reg_phase <= 4; // 精确80状态提交成功记录或错误记录。
						end else if(reg_phase == 4)begin
							reg_phase <= 0;     // 完成通知保持，主状态回空闲。
						end
					end

					// 状态损坏不推进任何缓存游标。
					default:begin
						reg_phase <= 0;         // 停止新协议发布。
					end
				endcase
			end
		end
	end

	//----------------状态机区域----------------//
	// 同域硬复位及GP静止后的同步软复位清主状态。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			state_current <= ST_IDLE;           // 异步撤销在途控制资格。
		end else if(i_soft_reset == 1'b1)begin
			state_current <= ST_IDLE;           // 同步清控制不清指令RAM内容。
		end else begin
			state_current <= state_next;        // 协议故障及写提交不受ce阻断。
		end
	end

	// 六主状态只在完整阶段资格齐备后切换。
	always@(*)begin
		state_next = state_current;             // 默认保持主状态。
		if(flag_fault == 1'b1)begin
			state_next = state_current != ST_WRITE_RUNTIME_INFO && flag_header_valid ? ST_WRITE_RUNTIME_INFO : ST_IDLE; // 只向已验证安全写区报告失败。
		end else begin
			case(state_current)

				// 清状态后等待PS一次整网启动。
				ST_IDLE:begin
					if(flag_start == 1'b1)begin
						state_next = ST_READ_HEADER; // 首先取完整模型头。
					end else begin
						state_next = ST_IDLE;   // 未接受整网start继续空闲。
					end
				end

				// 模型头及双表均以真实读状态结束。
				ST_READ_HEADER:begin
					if(i_ce == 1'b1 && reg_phase == 7)begin
						state_next = ST_READ_MODEL_INFO; // 合法头授权完整双表预取。
					end else begin
						state_next = ST_READ_HEADER; // 头数据、状态或校验尚未齐备。
					end
				end

				// 两张表全部成功后才开放层执行。
				ST_READ_MODEL_INFO:begin
					if(i_ce == 1'b1 && reg_phase == 7)begin
						state_next = ST_DISPATCH; // 同层缓存读取从索引零开始。
					end else begin
						state_next = ST_READ_MODEL_INFO; // 基础或扩展表事务尚未结束。
					end
				end

				// 同一FCLK四路配置共同被接受。
				ST_DISPATCH:begin
					if(flag_launch == 1'b1)begin
						state_next = ST_WAIT_LAYER_DONE; // 配置保持至本层全部结果排空。
					end else begin
						state_next = ST_DISPATCH; // BRAM、基本检查或四ready尚未齐备。
					end
				end

				// 最后层结束才写整网运行记录。
				ST_WAIT_LAYER_DONE:begin
					if(i_ce == 1'b1 && flag_layer_finished == 1'b1)begin
						state_next = {1'b0, current_layer_o} == cnt_layer - 1'b1 ? ST_WRITE_RUNTIME_INFO : ST_DISPATCH; // 按完整九位层数选择后继。
					end else begin
						state_next = ST_WAIT_LAYER_DONE; // 任一独立完成或排空条件缺失均等待。
					end
				end

				// 成功或失败记录提交后回空闲，状态保持给PS。
				ST_WRITE_RUNTIME_INFO:begin
					if(reg_phase == 4)begin
						state_next = ST_IDLE;   // 已接收最后真实GP写状态。
					end else begin
						state_next = ST_WRITE_RUNTIME_INFO; // 计时写命令、数据或状态仍在途。
					end
				end

				// 未知主状态关闭任务。
				default:begin
					state_next = ST_IDLE;       // 禁止从损坏状态继续发层start。
				end
			endcase
		end
	end

	//-------------状态任务处理区域-------------//
	// 首错误组合优先级；协议故障不等待算法ce。
	always@(*)begin
		flag_fault = 0;                         // 默认当前周期无故障。
		reg_fault_code = 0;                     // 默认无错误种类。
		if(flag_write_status == 1'b1 && (i_write_status != 8'h80 || reg_phase != 3))begin
			flag_fault = 1; reg_fault_code = i_write_status != 8'h80 ? 8'd10 : 8'd11; // 无效或早写状态不能宣称计时提交。
		end else if(flag_read_status == 1'b1 && (i_read_status != 8'h80 || reg_phase != 3))begin
			flag_fault = 1; reg_fault_code = 8'd6; // 读状态必须精确80且数据完整。
		end else if(flag_read_data == 1'b1 && (i_read_keep != 4'hf || i_read_last != (cnt_read_word == reg_read_words - 1'b1)))begin
			flag_fault = 1; reg_fault_code = 8'd5; // 错误keep或TLAST终止指令流。
		end else if(flag_controller_fault == 1'b1)begin
			flag_fault = 1; reg_fault_code = 8'd8; // 首控制器错误带诊断快照。
		end else if(flag_timeout == 1'b1)begin
			flag_fault = 1; reg_fault_code = 8'd9; // 超时独立于准备暂停。
		end else if(state_current == ST_READ_HEADER && i_ce == 1'b1 && reg_phase == 0 && flag_model_bad == 1'b1)begin
			flag_fault = 1; reg_fault_code = 8'd1; // 未发布头命令即拒绝非法模型地址。
		end else if(state_current == ST_READ_HEADER && i_ce == 1'b1 && reg_phase == 4 && flag_header_bad == 1'b1)begin
			flag_fault = 1; reg_fault_code = 8'd2; // 未开放缓存装载即拒绝非法头。
		end else if(state_current == ST_READ_HEADER && i_ce == 1'b1 && reg_phase == 6 && flag_file_bad == 1'b1)begin
			flag_fault = 1; reg_fault_code = 8'd3; // 截短或错位文件不能进入逐层调度。
		end else if(state_current == ST_READ_HEADER && i_ce == 1'b1 && reg_phase == 6 && flag_runtime_bad == 1'b1)begin
			flag_fault = 1; reg_fault_code = 8'd4; // 不可信写回地址不允许GP写。
		end else if(state_current == ST_DISPATCH && i_ce == 1'b1 && reg_phase == 3 && flag_layer_bad == 1'b1)begin
			flag_fault = 1; reg_fault_code = 8'd7; // 本层非法，不向任何模块发start。
		end else begin
			flag_fault = 0; reg_fault_code = 0; // 无故障保持正常算法及协议路径。
		end
	end

	// 固定八lane写使能；RAM内容不复位，装载成功资格隔离旧记录。
	always@(posedge i_clk)begin
		if(flag_read_data == 1'b1 && flag_fault == 1'b0 && state_current == ST_READ_MODEL_INFO)begin
			if(cnt_read_word[2:0] == 3'd0)begin
				if(reg_extension_table == 1'b1)begin
					reg_extension_first[cache_write_index] <= i_read_data; // 权重指针由本层首个扩展beat更新。
				end else begin
					reg_base_first[cache_write_index] <= i_read_data; // 接收GP流中的F_ADDR。
				end
			end
			if(cnt_read_word[2:0] == 3'd1)begin
				if(reg_extension_table == 1'b1)begin
					reg_extension_second[cache_write_index] <= i_read_data; // 偏置入口等待第二个流word到达。
				end else begin
					reg_base_second[cache_write_index] <= i_read_data; // O_ADDR保存在另一物理bank而不覆盖输入指针。
				end
			end
			if(cnt_read_word[2:0] == 3'd2)begin
				if(reg_extension_table == 1'b1)begin
					reg_extension_third[cache_write_index] <= i_read_data; // ADD残差分支载荷放入对应槽位。
				end else begin
					reg_base_third[cache_write_index] <= i_read_data; // 当前beat携带整层物理输入元素数。
				end
			end
			if(cnt_read_word[2:0] == 3'd3)begin
				if(reg_extension_table == 1'b1)begin
					reg_extension_fourth[cache_write_index] <= i_read_data; // H/Hout按原小端位序保存。
				end else begin
					reg_base_fourth[cache_write_index] <= i_read_data; // 写切换剩余部分与行跨度起始段同时落盘。
				end
			end
			if(cnt_read_word[2:0] == 3'd4)begin
				if(reg_extension_table == 1'b1)begin
					reg_extension_fifth[cache_write_index] <= i_read_data; // Cin_padded与Cout_padded不在PL重新编码。
				end else begin
					reg_base_fifth[cache_write_index] <= i_read_data; // 宽度及权重声明低位通过第五word装载。
				end
			end
			if(cnt_read_word[2:0] == 3'd5)begin
				if(reg_extension_table == 1'b1)begin
					reg_extension_sixth[cache_write_index] <= i_read_data; // 末层last和量化控制随word5接收。
				end else begin
					reg_base_sixth[cache_write_index] <= i_read_data; // K_DEPTH位段随本拍权重剩余字段缓存。
				end
			end
			if(cnt_read_word[2:0] == 3'd6)begin
				if(reg_extension_table == 1'b1)begin
					reg_extension_seventh[cache_write_index] <= i_read_data; // FC展平长度完整32位入缓存。
				end else begin
					reg_base_seventh[cache_write_index] <= i_read_data; // 模式和水平步长与输出数量低段一起更新。
				end
			end
			if(cnt_read_word[2:0] == 3'd7)begin
				if(reg_extension_table == 1'b1)begin
					reg_extension_eighth[cache_write_index] <= i_read_data; // 超时参数随扩展记录末beat写入。
				end else begin
					reg_base_eighth[cache_write_index] <= i_read_data; // 层索引及保留位随末个基础word存储。
				end
			end
		end
	end

	//-------------主要任务处理区域-------------//
	// 同层双BRAM同步读，后续两拍再锁存配置并检查资格。
	always@(posedge i_clk)begin
		if(flag_cache_read == 1'b1)begin
			reg_base_read <= {reg_base_eighth[current_layer_o], reg_base_seventh[current_layer_o], reg_base_sixth[current_layer_o], reg_base_fifth[current_layer_o], reg_base_fourth[current_layer_o], reg_base_third[current_layer_o], reg_base_second[current_layer_o], reg_base_first[current_layer_o]}; // 基础记录保持同一八位索引。
			reg_extension_read <= {reg_extension_eighth[current_layer_o], reg_extension_seventh[current_layer_o], reg_extension_sixth[current_layer_o], reg_extension_fifth[current_layer_o], reg_extension_fourth[current_layer_o], reg_extension_third[current_layer_o], reg_extension_second[current_layer_o], reg_extension_first[current_layer_o]}; // 扩展记录与基础读沿一致。
		end
	end

endmodule
