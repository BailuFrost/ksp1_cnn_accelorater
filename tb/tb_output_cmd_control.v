`timescale 1ns / 1ps
// 短保护和协议测试；大组游标预置不代替完整层数值验收。
module tb_output_cmd_control;
    reg i_clk=0;
    reg i_rstn=0;
    reg i_ce=1;
    reg i_soft_reset=0;
    reg i_start=0;
    reg [255:0]i_base_instruction=0;
    reg [255:0]i_extension=0;
    wire o_start_ready;
    wire o_busy;
    reg [9:0]i_group_index=0;
    wire [9:0]o_group_index;
    wire o_group_write_done;
    reg i_compute_done=0;
    reg i_packer_busy=0;
    reg i_dependency_error=0;
    wire o_output_done;
    wire o_error;
    wire [3:0]o_error_code;
    wire [31:0]o_commands_accepted;
    wire [31:0]o_data_beats;
    wire [31:0]o_responses_ok;
    reg i_spatial_fifo_valid=0;
    wire o_spatial_fifo_ready;
    reg [63:0]i_spatial_fifo_data=0;
    reg [3:0]i_spatial_fifo_mask=0;
    reg i_spatial_fifo_empty=1;
    reg i_bypass_fifo_valid=0;
    wire o_bypass_fifo_ready;
    reg [63:0]i_bypass_fifo_data=0;
    reg [3:0]i_bypass_fifo_mask=0;
    reg i_bypass_fifo_empty=1;
    wire o_cmd_valid;
    reg i_cmd_ready=0;
    wire [71:0]o_cmd_data;
    wire o_data_valid;
    reg i_data_ready=0;
    wire [63:0]o_data;
    wire [7:0]o_data_keep;
    wire o_data_last;
    reg i_status_valid=0;
    wire o_status_ready;
    reg [7:0]i_status=0;
    output_cmd dut(
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_ce(i_ce),
        .i_soft_reset(i_soft_reset),
        .i_start(i_start),
        .i_base_instruction(i_base_instruction),
        .i_extension(i_extension),
        .o_start_ready(o_start_ready),
        .o_busy(o_busy),
        .i_group_index(i_group_index),
        .o_group_index(o_group_index),
        .o_group_write_done(o_group_write_done),
        .i_compute_done(i_compute_done),
        .i_packer_busy(i_packer_busy),
        .i_dependency_error(i_dependency_error),
        .o_output_done(o_output_done),
        .o_error(o_error),
        .o_error_code(o_error_code),
        .o_commands_accepted(o_commands_accepted),
        .o_data_beats(o_data_beats),
        .o_responses_ok(o_responses_ok),
        .i_spatial_fifo_valid(i_spatial_fifo_valid),
        .o_spatial_fifo_ready(o_spatial_fifo_ready),
        .i_spatial_fifo_data(i_spatial_fifo_data),
        .i_spatial_fifo_mask(i_spatial_fifo_mask),
        .i_spatial_fifo_empty(i_spatial_fifo_empty),
        .i_bypass_fifo_valid(i_bypass_fifo_valid),
        .o_bypass_fifo_ready(o_bypass_fifo_ready),
        .i_bypass_fifo_data(i_bypass_fifo_data),
        .i_bypass_fifo_mask(i_bypass_fifo_mask),
        .i_bypass_fifo_empty(i_bypass_fifo_empty),
        .o_cmd_valid(o_cmd_valid),
        .i_cmd_ready(i_cmd_ready),
        .o_cmd_data(o_cmd_data),
        .o_data_valid(o_data_valid),
        .i_data_ready(i_data_ready),
        .o_data(o_data),
        .o_data_keep(o_data_keep),
        .o_data_last(o_data_last),
        .i_status_valid(i_status_valid),
        .o_status_ready(o_status_ready),
        .i_status(i_status)
    );

    always #5 i_clk=~i_clk;
    reg test_done=0,test_failed=0;
    integer n,j,guard,boundaries_checked=0,errors_checked=0,labels_checked=0,resets_checked=0,pause_checks=0,barrier_checks=0;
    reg [511:0]configs[0:23];
    reg [63:0]expected[0:23];
    reg [71:0]held_command;
    reg [72:0]held_data;
    task tick;
        begin @(posedge i_clk);#1;@(negedge i_clk);#1;end
    endtask
    task clear;
        begin
            i_ce=0;i_soft_reset=1;tick;i_soft_reset=0;
            if(dut.state_current!=dut.ST_IDLE || o_error || o_cmd_valid || o_data_valid || o_output_done)$fatal(1,"paused soft reset failed");
            i_ce=1;i_start=0;i_dependency_error=0;i_cmd_ready=0;i_data_ready=0;i_status_valid=0;i_compute_done=0;
            i_spatial_fifo_valid=0;i_spatial_fifo_empty=1;i_bypass_fifo_valid=0;i_bypass_fifo_empty=1;i_packer_busy=0;i_group_index=0;
            tick;
        end
    endtask
    task configure;
        input integer index;
        begin
            clear;{i_extension,i_base_instruction}=configs[index];
            while(!o_start_ready)tick;i_start=1;tick;i_start=0;
            i_base_instruction=0;i_extension=0;
            guard=0;
            while(!o_cmd_valid && !o_error)begin tick;guard=guard+1;if(guard>20)$fatal(1,"prepare stuck");end
        end
    endtask
    task accept_command;
        begin i_cmd_ready=1;tick;i_cmd_ready=0;if(dut.state_current!=dut.ST_STREAM)$fatal(1,"command accept lost");end
    endtask
    task supply_beat;
        input [3:0]mask;
        input last;
        begin
            i_ce=1;i_spatial_fifo_mask=mask;i_spatial_fifo_data=64'h1234123412341234;i_spatial_fifo_valid=1;i_spatial_fifo_empty=0;
            #1;
            while(!o_spatial_fifo_ready)tick;tick;i_spatial_fifo_valid=0;i_spatial_fifo_empty=1;
            if(!o_data_valid || o_data_last!==last)$fatal(1,"holding/last mismatch");
            i_data_ready=1;tick;i_data_ready=0;
        end
    endtask
    initial begin
        $readmemh("d3_control_configs.mem",configs);$readmemh("d3_control_expected.mem",expected);
        repeat(2)tick;i_rstn=1;tick;
        for(n=0;n<24;n=n+1)begin
            configure(n);
            if(o_error_code!==expected[n][59:56])$fatal(1,"config %0d error=%0d expected=%0d",n,o_error_code,expected[n][59:56]);
            if(n<11)begin
                if(dut.reg_groups!==expected[n][10:0] || dut.reg_words!==expected[n][20:16] || dut.reg_total_beats!==expected[n][55:24])$fatal(1,"derived range %0d",n);
            end else begin
                if(o_cmd_valid || o_data_valid)$fatal(1,"invalid config emitted write");
                i_start=1;repeat(2)tick;i_start=0;if(!o_error || o_start_ready)$fatal(1,"config error not sticky");errors_checked=errors_checked+1;
            end
            boundaries_checked=boundaries_checked+1;
        end
        // 原总量过小但合法对齐：当前BTT越界必须在命令发布前拒绝。
        clear;{i_extension,i_base_instruction}=configs[1];i_base_instruction[227:204]=4;
        i_start=1;tick;i_start=0;repeat(9)tick;
        if(o_error_code!=2 || o_cmd_valid || o_commands_accepted!=0)$fatal(1,"per-command range guard failed");errors_checked=errors_checked+1;
        // TAG错误、写错误、无OKAY状态均不计成功；早成功单独报协议错误。
        for(n=0;n<4;n=n+1)begin
            configure(1);accept_command;i_ce=0;
            i_status=n==0 ? 8'h81 : n==1 ? 8'h90 : n==2 ? 8'h00 : 8'h80;
            i_status_valid=1;tick;i_status_valid=0;
            if(o_error_code!=(n==3 ? 5 : 3) || o_responses_ok!=0 || o_output_done)$fatal(1,"failed/early status accepted");errors_checked=errors_checked+1;
        end
        configure(1);accept_command;i_spatial_fifo_valid=1;i_spatial_fifo_empty=0;i_spatial_fifo_mask=7;
        #1;if(o_spatial_fifo_ready || o_data_valid)$fatal(1,"bad mask consumed");tick;
        if(o_error_code!=4 || o_data_beats!=0)$fatal(1,"bad mask not latched");errors_checked=errors_checked+1;
        configure(1);i_ce=0;i_dependency_error=1;tick;
        if(o_error_code!=6 || o_cmd_valid)$fatal(1,"paused dependency error lost");errors_checked=errors_checked+1;
        configure(2);@(negedge i_clk);#1;dut.state_current=dut.ST_GROUP;dut.group_write_done_o=1;
        i_group_index=2;tick;if(o_error_code!=7)$fatal(1,"skipped group accepted");errors_checked=errors_checked+1;
        // 十位group256/511：只预置合法游标，执行正常准备及稳定命令。
        for(n=256;n<=511;n=n+255)begin
            configure(3);@(negedge i_clk);#1;
            dut.state_current=dut.ST_PREPARE;dut.group_index_o=n;dut.reg_output_base=n*8;dut.reg_cursor=dut.reg_origin+n*16;
            tick;
            if(!o_cmd_valid || o_group_index!=n || o_cmd_data[63:32]!=32'h0b000000+n*16 || o_cmd_data[22:0]!=16)$fatal(1,"wide group cursor truncated");
            labels_checked=labels_checked+1;
        end
        configure(9);accept_command;@(negedge i_clk);#1;dut.cnt_post_quad=1023;
        i_spatial_fifo_mask=15;i_spatial_fifo_valid=1;i_spatial_fifo_empty=0;#1;
        if(!o_spatial_fifo_ready || dut.expected_mask!=15)$fatal(1,"post quad1023 truncated");labels_checked=labels_checked+1;
        // 命令VALID在暂停和反压时保持；ce=0真实接受仍必须记账。
        configure(1);held_command=o_cmd_data;i_ce=0;repeat(3)tick;
        if(!o_cmd_valid || o_cmd_data!==held_command)$fatal(1,"paused command lost");
        accept_command;if(o_commands_accepted!=1)$fatal(1,"paused command not counted");
        i_spatial_fifo_mask=15;i_spatial_fifo_valid=1;i_spatial_fifo_empty=0;tick;
        if(o_spatial_fifo_ready || o_data_valid)$fatal(1,"pause consumed new FIFO item");
        i_ce=1;i_spatial_fifo_data=64'h123456789abcdef0;tick;i_spatial_fifo_valid=0;i_spatial_fifo_empty=1;
        held_data={o_data_last,o_data_keep,o_data};i_ce=0;repeat(3)tick;
        if(!o_data_valid || {o_data_last,o_data_keep,o_data}!==held_data)$fatal(1,"paused data lost");
        i_data_ready=1;tick;i_data_ready=0;if(o_data_beats!=1)$fatal(1,"paused data handshake lost");pause_checks=pause_checks+1;
        supply_beat(15,1);
        if(dut.state_current!=dut.ST_STATUS || o_group_write_done || o_output_done)$fatal(1,"done before final response");
        i_ce=0;i_compute_done=1;tick;i_compute_done=0;i_packer_busy=1;i_bypass_fifo_empty=0;
        i_status=8'h80;i_status_valid=1;tick;i_status_valid=0;
        if(o_responses_ok!=1 || !dut.flag_compute_done)$fatal(1,"paused completion pulses lost");pause_checks=pause_checks+1;
        i_ce=1;repeat(4)tick;if(o_output_done)$fatal(1,"packer/other FIFO barrier bypassed");
        i_packer_busy=0;repeat(3)tick;if(o_output_done)$fatal(1,"other FIFO barrier bypassed");
        i_bypass_fifo_empty=1;tick;if(!o_output_done)$fatal(1,"complete barrier did not finish");
        i_ce=0;tick;if(o_output_done)$fatal(1,"done stretched under pause");barrier_checks=barrier_checks+1;
        // 运行中同步软复位与非沿硬复位，复位后重新配置可正常发布命令。
        configure(1);accept_command;i_ce=0;#2;i_soft_reset=1;#1;
        if(dut.state_current==dut.ST_IDLE)$fatal(1,"soft reset acted asynchronously");
        tick;i_soft_reset=0;if(dut.state_current!=dut.ST_IDLE || o_error || o_cmd_valid || o_data_valid)$fatal(1,"soft reset failed");resets_checked=resets_checked+1;
        configure(1);accept_command;i_spatial_fifo_valid=1;i_spatial_fifo_empty=0;i_spatial_fifo_mask=15;tick;
        i_ce=0;#2;i_rstn=0;#1;
        if(dut.state_current!=dut.ST_IDLE || o_cmd_valid || o_data_valid || o_output_done || o_error)$fatal(1,"async reset failed");
        #1;i_rstn=1;i_spatial_fifo_valid=0;i_spatial_fifo_empty=1;tick;configure(1);
        if(!o_cmd_valid || o_error)$fatal(1,"restart after hard reset failed");resets_checked=resets_checked+1;
        $display("PASS D3 control boundaries=%0d errors=%0d labels=%0d resets=%0d pause=%0d barrier=%0d",boundaries_checked,errors_checked,labels_checked,resets_checked,pause_checks,barrier_checks);
        test_done=1;$finish;
    end
    initial begin #100000;test_failed=1;$fatal(1,"D3 control watchdog state=%0d boundaries=%0d errors=%0d labels=%0d words=%0d data=%0d holding=%b",dut.state_current,boundaries_checked,errors_checked,labels_checked,dut.cnt_word,o_data_beats,o_data_valid);end
endmodule
