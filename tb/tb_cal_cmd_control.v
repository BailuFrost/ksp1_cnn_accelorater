`timescale 1ns / 1ps
// 短控制序列：大层不执行全部DMA，游标预置只用于验证完整标签和完成屏障。
module tb_cal_cmd_control;
    reg i_clk=0;
    reg i_rstn=0;
    reg i_ce=1;
    reg i_soft_reset=0;
    reg i_start=0;
    reg [255:0]i_base_instruction=0;
    reg [255:0]i_extension=0;
    wire o_start_ready;
    wire o_busy;
    wire o_compute_done;
    wire o_error;
    wire [3:0]o_error_code;
    reg i_dependency_error=0;
    wire o_scan_req;
    reg i_scan_ready=0;
    reg i_feature_ready=0;
    reg [9:0]i_feature_group=0;
    reg [7:0]i_feature_tile=0;
    wire o_scan_finish;
    reg i_scan_done=0;
    wire o_load_req;
    reg i_load_ready=0;
    reg i_weight_ready=0;
    reg [8:0]i_weight_group=0;
    reg [7:0]i_weight_tile=0;
    wire o_compute_idle;
    wire [9:0]o_group_index;
    wire [8:0]o_weight_group;
    wire [7:0]o_tile_index;
    wire [15:0]o_tile_channel_base;
    wire o_update_req;
    reg i_update_ready=0;
    wire [15:0]o_update_row;
    wire [11:0]o_update_col;
    wire [1:0]o_update_bank;
    reg i_update_done=0;
    wire o_feature_rd_valid;
    reg i_feature_rd_ready=1;
    wire [12:0]o_feature_rd_addr;
    reg i_feature_out_valid=0;
    wire o_weight_rd_valid;
    reg i_weight_rd_ready=1;
    wire [7:0]o_weight_rd_addr;
    reg i_weight_out_valid=0;
    wire o_datapath_ce;
    wire o_pair_valid;
    reg i_array_ready=1;
    wire o_pair_first;
    wire o_pair_last;
    wire o_pair_row_last;
    wire [1:0]o_mode;
    wire [1:0]o_row_select;
    wire [2:0]o_row_mask;
    wire o_column_valid;
    wire [1:0]o_pair_mask;
    reg i_column_commit=0;
    reg i_row_advance=0;
    reg i_cu_valid=0;
    reg i_bundle_ready=1;
    reg i_packer_busy=0;
    reg i_fifo_full=0;
    reg i_group_write_done=0;
    wire o_bundle_valid;
    wire [71:0]o_lane_mask;
    wire [31:0]o_spatial_index;
    wire o_first_tile;
    wire o_last_tile;
    wire o_post_stream_req;
    reg i_post_stream_ready=0;
    reg i_post_stream_done=0;
    wire o_post_block_req;
    reg i_post_block_ready=0;
    reg i_post_block_done=0;
    wire [15:0]o_post_block_row;
    wire [7:0]o_post_block;
    wire [9:0]o_post_block_channels;
    wire o_post_valid;
    reg i_post_ready=0;
    wire [15:0]o_post_row;
    wire [11:0]o_post_col;
    wire [1:0]o_post_stage;
    wire [6:0]o_post_quad;
    wire [3:0]o_post_mask;
    reg i_post_done=0;
    cal_cmd dut(
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_ce(i_ce),
        .i_soft_reset(i_soft_reset),
        .i_start(i_start),
        .i_base_instruction(i_base_instruction),
        .i_extension(i_extension),
        .o_start_ready(o_start_ready),
        .o_busy(o_busy),
        .o_compute_done(o_compute_done),
        .o_error(o_error),
        .o_error_code(o_error_code),
        .i_dependency_error(i_dependency_error),
        .o_scan_req(o_scan_req),
        .i_scan_ready(i_scan_ready),
        .i_feature_ready(i_feature_ready),
        .i_feature_group(i_feature_group),
        .i_feature_tile(i_feature_tile),
        .o_scan_finish(o_scan_finish),
        .i_scan_done(i_scan_done),
        .o_load_req(o_load_req),
        .i_load_ready(i_load_ready),
        .i_weight_ready(i_weight_ready),
        .i_weight_group(i_weight_group),
        .i_weight_tile(i_weight_tile),
        .o_compute_idle(o_compute_idle),
        .o_group_index(o_group_index),
        .o_weight_group(o_weight_group),
        .o_tile_index(o_tile_index),
        .o_tile_channel_base(o_tile_channel_base),
        .o_update_req(o_update_req),
        .i_update_ready(i_update_ready),
        .o_update_row(o_update_row),
        .o_update_col(o_update_col),
        .o_update_bank(o_update_bank),
        .i_update_done(i_update_done),
        .o_feature_rd_valid(o_feature_rd_valid),
        .i_feature_rd_ready(i_feature_rd_ready),
        .o_feature_rd_addr(o_feature_rd_addr),
        .i_feature_out_valid(i_feature_out_valid),
        .o_weight_rd_valid(o_weight_rd_valid),
        .i_weight_rd_ready(i_weight_rd_ready),
        .o_weight_rd_addr(o_weight_rd_addr),
        .i_weight_out_valid(i_weight_out_valid),
        .o_datapath_ce(o_datapath_ce),
        .o_pair_valid(o_pair_valid),
        .i_array_ready(i_array_ready),
        .o_pair_first(o_pair_first),
        .o_pair_last(o_pair_last),
        .o_pair_row_last(o_pair_row_last),
        .o_mode(o_mode),
        .o_row_select(o_row_select),
        .o_row_mask(o_row_mask),
        .o_column_valid(o_column_valid),
        .o_pair_mask(o_pair_mask),
        .i_column_commit(i_column_commit),
        .i_row_advance(i_row_advance),
        .i_cu_valid(i_cu_valid),
        .i_bundle_ready(i_bundle_ready),
        .i_packer_busy(i_packer_busy),
        .i_fifo_full(i_fifo_full),
        .i_group_write_done(i_group_write_done),
        .o_bundle_valid(o_bundle_valid),
        .o_lane_mask(o_lane_mask),
        .o_spatial_index(o_spatial_index),
        .o_first_tile(o_first_tile),
        .o_last_tile(o_last_tile),
        .o_post_stream_req(o_post_stream_req),
        .i_post_stream_ready(i_post_stream_ready),
        .i_post_stream_done(i_post_stream_done),
        .o_post_block_req(o_post_block_req),
        .i_post_block_ready(i_post_block_ready),
        .i_post_block_done(i_post_block_done),
        .o_post_block_row(o_post_block_row),
        .o_post_block(o_post_block),
        .o_post_block_channels(o_post_block_channels),
        .o_post_valid(o_post_valid),
        .i_post_ready(i_post_ready),
        .o_post_row(o_post_row),
        .o_post_col(o_post_col),
        .o_post_stage(o_post_stage),
        .o_post_quad(o_post_quad),
        .o_post_mask(o_post_mask),
        .i_post_done(i_post_done)
    );

    always #5 i_clk=~i_clk;
    reg test_done=0,test_failed=0;
    integer boundaries_checked=0,labels_checked=0,errors_checked=0,resets_checked=0,pulse_checks=0;
    integer n,guard;
    reg [511:0]configs[0:25];
    reg [127:0]expected[0:25];
    task tick;
        begin @(posedge i_clk);#1;@(negedge i_clk);#1;end
    endtask
    task clear;
        begin
            i_ce=0;i_soft_reset=1;tick;i_soft_reset=0;
            if(dut.state_current!=dut.ST_IDLE || o_error || o_compute_done) $fatal(1,"soft reset during pause");
            i_scan_ready=0;i_load_ready=0;i_feature_ready=0;i_weight_ready=0;
            i_dependency_error=0;i_scan_done=0;i_post_done=0;i_group_write_done=0;
            i_ce=1;tick;
        end
    endtask
    task configure;
        input integer index;
        begin
            clear;{i_extension,i_base_instruction}=configs[index];
            i_start=1;tick;i_start=0;
            // 锁存后外部配置改变不能影响本层。
            i_base_instruction=0;i_extension=0;
            guard=0;
            while(dut.state_current!=dut.ST_REQUEST && dut.state_current!=dut.ST_POST_START && dut.state_current!=dut.ST_POST_BLOCK && !o_error)begin
                tick;guard=guard+1;if(guard>15)$fatal(1,"prepare stuck at %0d",dut.state_current);
            end
        end
    endtask
    task accept_load;
        begin
            i_scan_ready=1;i_load_ready=1;tick;i_scan_ready=0;i_load_ready=0;tick;
            if(dut.state_current!=dut.ST_READY) $fatal(1,"independent load handshake");
        end
    endtask
    initial begin
        $readmemh("d2_control_configs.mem",configs);$readmemh("d2_control_expected.mem",expected);
        repeat(2)tick;i_rstn=1;tick;
        for(n=0;n<26;n=n+1)begin
            configure(n);
            if(o_error_code!==expected[n][91:88]) $fatal(1,"boundary %0d error got=%0d expected=%0d",n,o_error_code,expected[n][91:88]);
            if(expected[n][91:88]==0)begin
                if(dut.reg_depth!==expected[n][31:0] || dut.reg_groups!==expected[n][42:32] || dut.reg_tiles!==expected[n][55:48] || dut.cnt_spatial_total!==expected[n][87:56])
                    $fatal(1,"derived quantity %0d depth=%0d groups=%0d tiles=%0d spatial=%0d",n,dut.reg_depth,dut.reg_groups,dut.reg_tiles,dut.cnt_spatial_total);
            end else begin
                if(o_scan_req || o_load_req || o_post_stream_req || o_post_block_req) $fatal(1,"invalid config issued request");
                i_start=1;repeat(3)tick;i_start=0;
                if(!o_error || o_start_ready) $fatal(1,"error was not sticky");
                errors_checked=errors_checked+1;
            end
            boundaries_checked=boundaries_checked+1;
        end
        // 4096卷积512组：直接预置合法组边界，正常执行TILE和请求/响应。
        for(n=256;n<=511;n=n+255)begin
            configure(7);@(negedge i_clk);#1;
            dut.state_current=dut.ST_TILE;dut.group_index_o=n;dut.reg_output_base=n*8;
            tick;
            if(o_group_index!=n || o_weight_group!=n || dut.reg_lanes!=8) $fatal(1,"wide group/tail truncated");
            accept_load;
            i_feature_group=n;i_weight_group=n;i_feature_tile=0;i_weight_tile=0;i_feature_ready=1;i_weight_ready=1;tick;
            if(o_error || dut.state_current!=dut.ST_ADDRESS) $fatal(1,"legal wide response rejected");
            labels_checked=labels_checked+1;
        end
        // 后处理标签1023、block7、quad127在真实token路径完整呈现。
        configure(17);i_post_stream_ready=1;tick;i_post_stream_ready=0;
        @(negedge i_clk);#1;dut.group_index_o=1023;#1;
        if(!o_post_valid || o_group_index!=1023 || o_post_quad!=127 || o_post_block!=7 || o_post_mask!=15) $fatal(1,"post label truncated");
        labels_checked=labels_checked+1;
        // 错标签和依赖错误从活动任务进入粘滞错误态。
        configure(0);accept_load;i_feature_ready=1;i_weight_ready=1;i_feature_group=1;i_weight_group=0;tick;
        if(o_error_code!=2) $fatal(1,"stale label accepted");errors_checked=errors_checked+1;
        configure(0);i_ce=0;i_dependency_error=1;tick;
        if(o_error_code!=3) $fatal(1,"paused dependency error lost");errors_checked=errors_checked+1;
        // 完成单拍在ce=0时锁存，恢复后才推进tile；不会丢通知。
        configure(3);@(negedge i_clk);#1;dut.state_current=dut.ST_FINISH_WAIT;
        i_ce=0;i_scan_done=1;tick;i_scan_done=0;repeat(3)tick;
        if(!dut.flag_scan_done || o_tile_index!=0 || dut.state_current!=dut.ST_FINISH_WAIT) $fatal(1,"paused done lost or advanced");
        i_ce=1;tick;
        if(o_tile_index!=1 || dut.state_current!=dut.ST_TILE) $fatal(1,"latched done did not resume");pulse_checks=pulse_checks+1;
        // 组完成须等实际写响应；done只占一个FCLK，即使下一拍暂停。
        configure(0);@(negedge i_clk);#1;dut.state_current=dut.ST_GROUP;dut.group_index_o=1;
        repeat(3)tick;if(o_compute_done)$fatal(1,"group completed before HP2 response");
        i_group_write_done=1;tick;if(!o_compute_done)$fatal(1,"group final completion missing");
        i_ce=0;tick;if(o_compute_done)$fatal(1,"done stretched under pause");pulse_checks=pulse_checks+1;
        // 运行中软复位只在时钟沿生效；异步硬复位在非沿立即撤销valid。
        configure(0);i_ce=0;#2;i_soft_reset=1;#1;
        if(dut.state_current==dut.ST_IDLE) $fatal(1,"soft reset acted asynchronously");
        tick;i_soft_reset=0;if(dut.state_current!=dut.ST_IDLE || o_error)$fatal(1,"soft reset failed");resets_checked=resets_checked+1;
        configure(0);i_ce=0;#2;i_rstn=0;#1;
        if(dut.state_current!=dut.ST_IDLE || o_busy || o_scan_req || o_load_req || o_pair_valid || o_compute_done || o_error) $fatal(1,"async reset failed");
        #1;i_rstn=1;tick;i_ce=1;tick;configure(0);
        if(!o_scan_req || !o_load_req || o_error)$fatal(1,"restart after reset failed");resets_checked=resets_checked+1;
        $display("PASS D2 control: boundaries=%0d labels=%0d errors=%0d resets=%0d pulses=%0d",boundaries_checked,labels_checked,errors_checked,resets_checked,pulse_checks);
        test_done=1;$finish;
    end
    initial begin #100000;test_failed=1;$fatal(1,"control watchdog");end
endmodule
