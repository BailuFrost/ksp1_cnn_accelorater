`timescale 1ns / 1ps
// D3：真实B5/双FIFO与后处理FIFO，HP2为固定反压事务模型。
module tb_output_cmd;
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
    wire i_compute_done;
    wire i_packer_busy;
    reg i_dependency_error=0;
    wire o_output_done;
    wire o_error;
    wire [3:0]o_error_code;
    wire [31:0]o_commands_accepted;
    wire [31:0]o_data_beats;
    wire [31:0]o_responses_ok;
    wire i_spatial_fifo_valid;
    wire o_spatial_fifo_ready;
    wire [63:0]i_spatial_fifo_data;
    wire [3:0]i_spatial_fifo_mask;
    wire i_spatial_fifo_empty;
    wire i_bypass_fifo_valid;
    wire o_bypass_fifo_ready;
    wire [63:0]i_bypass_fifo_data;
    wire [3:0]i_bypass_fifo_mask;
    wire i_bypass_fifo_empty;
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

    wire post_cal_ready,post_compute_done,post_cal_error,post_token,post_stream_req,post_block_req;
    wire [9:0]post_group;
    wire [1:0]post_stage;
    wire [3:0]cal_post_mask;
    reg post_stream_done=0,post_block_done=0,post_result_done=0;
    integer post_delay=0,block_delay=0,case_posts=0,posts_seen=0,post_layers_done=0;
    wire cal_post_ready=post_ready && cycles%7!=1;
    wire token_fire=post_token && cal_post_ready;
    wire post_emit=case_index>=4 && i_ce && (case_index==6 ? case_posts==516 && post_position<meta[case_index][63:32] : token_fire && (case_index==5 || post_stage==3));
    always@(*)begin
        if(case_index>=4)begin
            post_in_valid=post_emit;
            post_in_data=expected_beats[post_position][127:64];
            post_in_mask=expected_beats[post_position][131:128];
        end
    end
    always@(posedge i_clk)begin
        if(!i_rstn)begin
            case_posts<=0;post_delay<=0;block_delay<=0;
            post_stream_done<=0;post_block_done<=0;post_result_done<=0;
        end else if(case_index>=4)begin
            post_stream_done<=0;post_block_done<=0;post_result_done<=0;
            if(post_cal_error)$fatal(1,"real post CAL error case=%0d state=%0d",case_index,post_cal.state_current);
            if(post_block_req)block_delay<=3;
            if(block_delay>0)begin
                block_delay<=block_delay-1;
                if(block_delay==1)post_block_done<=1;
            end
            if(token_fire)begin
                if(post_group!==((case_posts/(case_index==4 ? 4 : 1))%129) || cal_post_mask!==(post_group==128 ? 4'h1 : 4'hf) || (case_index==4 && post_stage!==(case_posts%4)))$fatal(1,"post CAL token order/mask");
                case_posts<=case_posts+1;posts_seen=posts_seen+1;
                if(case_posts+1==(case_index==4 ? 2064 : 516))post_stream_done<=1;
            end
            if(post_in_valid && post_ready)begin
                post_position<=post_position+1;
                if(case_index!=6 || post_position+1==meta[case_index][63:32])post_delay<=3;
            end
            if(post_delay>0)begin
                post_delay<=post_delay-1;
                if(post_delay==1)post_result_done<=1;
            end
            if(post_compute_done)begin
                if(!o_group_write_done || o_responses_ok!=o_commands_accepted)$fatal(1,"CAL released before real last successful write");
                post_layers_done=post_layers_done+1;
            end
        end
    end
    cal_cmd post_cal(
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_ce(i_ce),
        .i_soft_reset(i_soft_reset),
        .i_start(i_start && case_index>=4),
        .i_base_instruction(i_base_instruction),
        .i_extension(i_extension),
        .o_start_ready(post_cal_ready),
        .o_busy(),
        .o_compute_done(post_compute_done),
        .o_error(post_cal_error),
        .o_error_code(),
        .i_dependency_error(1'd0),
        .o_scan_req(),
        .i_scan_ready(1'd0),
        .i_feature_ready(1'd0),
        .i_feature_group(10'd0),
        .i_feature_tile(8'd0),
        .o_scan_finish(),
        .i_scan_done(1'd0),
        .o_load_req(),
        .i_load_ready(1'd0),
        .i_weight_ready(1'd0),
        .i_weight_group(9'd0),
        .i_weight_tile(8'd0),
        .o_compute_idle(),
        .o_group_index(post_group),
        .o_weight_group(),
        .o_tile_index(),
        .o_tile_channel_base(),
        .o_update_req(),
        .i_update_ready(1'd0),
        .o_update_row(),
        .o_update_col(),
        .o_update_bank(),
        .i_update_done(1'd0),
        .o_feature_rd_valid(),
        .i_feature_rd_ready(1'd0),
        .o_feature_rd_addr(),
        .i_feature_out_valid(1'd0),
        .o_weight_rd_valid(),
        .i_weight_rd_ready(1'd0),
        .o_weight_rd_addr(),
        .i_weight_out_valid(1'd0),
        .o_datapath_ce(),
        .o_pair_valid(),
        .i_array_ready(1'd0),
        .o_pair_first(),
        .o_pair_last(),
        .o_pair_row_last(),
        .o_mode(),
        .o_row_select(),
        .o_row_mask(),
        .o_column_valid(),
        .o_pair_mask(),
        .i_column_commit(1'd0),
        .i_row_advance(1'd0),
        .i_cu_valid(1'd0),
        .i_bundle_ready(1'd0),
        .i_packer_busy(i_packer_busy),
        .i_fifo_full(post_full),
        .i_group_write_done(o_group_write_done),
        .o_bundle_valid(),
        .o_lane_mask(),
        .o_spatial_index(),
        .o_first_tile(),
        .o_last_tile(),
        .o_post_stream_req(post_stream_req),
        .i_post_stream_ready(1'b1),
        .i_post_stream_done(post_stream_done),
        .o_post_block_req(post_block_req),
        .i_post_block_ready(1'b1),
        .i_post_block_done(post_block_done),
        .o_post_block_row(),
        .o_post_block(),
        .o_post_block_channels(),
        .o_post_valid(post_token),
        .i_post_ready(cal_post_ready),
        .o_post_row(),
        .o_post_col(),
        .o_post_stage(post_stage),
        .o_post_quad(),
        .o_post_mask(cal_post_mask),
        .i_post_done(post_result_done)
    );

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
    integer cycles=0,case_index=0,commands_seen=0,beats_seen=0,statuses_seen=0,bundles_sent=0;
    integer group_events=0,command_stalls=0,data_stalls=0,pause_handshakes=0,full_cycles=0;
    integer n,post_position,case_start,active_words=0,active_position=0,status_delay=0;
    integer trace;
    reg active=0,hold_packer=0,pause_override=0,mock_compute_done=0;
    reg producer_valid=0,post_in_valid=0;
    reg [3455:0]producer_data=0;
    reg [71:0]producer_mask=0;
    reg [7:0]producer_spatial=0;
    reg [63:0]post_in_data=0;
    reg [3:0]post_in_mask=0;
    wire bundle_ready,packer_busy,selected_full;
    wire spatial_valid,bypass_valid,spatial_empty,bypass_empty;
    wire [63:0]spatial_data,bypass_data;
    wire [3:0]spatial_mask,bypass_mask;
    wire post_valid,post_empty,post_full,post_ready;
    wire [63:0]post_data;
    wire [3:0]post_mask;
    reg [511:0]configs[0:6];
    reg [95:0]meta[0:6];
    reg [71:0]expected_commands[0:1194];
    reg [135:0]expected_beats[0:1323];
    reg [5323:0]bundles[0:33];
    reg previous_cmd_stall=0,previous_data_stall=0;
    reg [71:0]previous_cmd;
    reg [72:0]previous_data;
    wire [12:0]logical_outputs=i_base_instruction[195:184]==0 ? 13'd4096 : {1'b0,i_base_instruction[195:184]};
    wire [12:0]parallel=i_base_instruction[197] ? 13'd72 : 13'd8;
    wire [10:0]groups=(logical_outputs+parallel-1)/parallel;
    assign i_compute_done=case_index<4 ? mock_compute_done : post_compute_done;
    assign i_packer_busy=packer_busy || hold_packer;
    assign i_spatial_fifo_valid=case_index<4 ? spatial_valid : post_valid;
    assign i_spatial_fifo_data=case_index<4 ? spatial_data : post_data;
    assign i_spatial_fifo_mask=case_index<4 ? spatial_mask : post_mask;
    assign i_spatial_fifo_empty=case_index<4 ? spatial_empty : post_empty;
    assign i_bypass_fifo_valid=bypass_valid;
    assign i_bypass_fifo_data=bypass_data;
    assign i_bypass_fifo_mask=bypass_mask;
    assign i_bypass_fifo_empty=bypass_empty;
    result_output results(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_bundle_valid(producer_valid),.o_bundle_ready(bundle_ready),
        .i_bundle_data(producer_data),.i_bias_data(5184'd0),.i_lane_mask(producer_mask),
        .i_mode(i_base_instruction[197:196]),.i_spatial_index(producer_spatial),
        .i_first_tile(1'b1),.i_last_tile(1'b1),.i_right_shift(6'd0),.i_relu(1'b0),
        .o_busy(packer_busy),.o_fifo_full(selected_full),
        .o_spatial_fifo_valid(spatial_valid),.i_spatial_fifo_ready(case_index<4 && o_spatial_fifo_ready),
        .o_spatial_fifo_data(spatial_data),.o_spatial_fifo_mask(spatial_mask),.o_spatial_fifo_full(),
        .o_spatial_fifo_empty(spatial_empty),.o_spatial_fifo_count(),
        .o_bypass_fifo_valid(bypass_valid),.i_bypass_fifo_ready(o_bypass_fifo_ready),
        .o_bypass_fifo_data(bypass_data),.o_bypass_fifo_mask(bypass_mask),.o_bypass_fifo_full(),
        .o_bypass_fifo_empty(bypass_empty),.o_bypass_fifo_count());
    result_fifo_3x3 post_results(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_in_valid(post_in_valid),.o_in_ready(post_ready),
        .i_in_data(post_in_data),.i_in_mask(post_in_mask),.o_out_valid(post_valid),
        .i_out_ready(case_index>=4 && o_spatial_fifo_ready),.o_out_data(post_data),
        .o_out_mask(post_mask),.o_full(post_full),.o_empty(post_empty),.o_count());
    always@(posedge i_clk)begin
        cycles=cycles+1;
        if(!i_rstn)begin
            active<=0;status_delay<=0;i_status_valid<=0;
            previous_cmd_stall=0;previous_data_stall=0;
        end else begin
            if(o_error)$fatal(1,"D3 error case=%0d code=%0d state=%0d",case_index,o_error_code,dut.state_current);
            if(previous_cmd_stall && (!o_cmd_valid || o_cmd_data!==previous_cmd))$fatal(1,"command VALID/payload lost during stall/pause");
            if(previous_data_stall && (!o_data_valid || {o_data_last,o_data_keep,o_data}!==previous_data))$fatal(1,"data VALID/payload lost during stall/pause");
            previous_cmd_stall=o_cmd_valid && !i_cmd_ready;previous_cmd=o_cmd_data;
            previous_data_stall=o_data_valid && !i_data_ready;previous_data={o_data_last,o_data_keep,o_data};
            if(previous_cmd_stall)command_stalls=command_stalls+1;
            if(previous_data_stall)data_stalls=data_stalls+1;
            if(post_full)full_cycles=full_cycles+1;
            if(!i_ce && ((o_cmd_valid && i_cmd_ready) || (o_data_valid && i_data_ready) || (i_status_valid && o_status_ready)))pause_handshakes=pause_handshakes+1;
            if(o_cmd_valid && i_cmd_ready)begin
                if(active || o_cmd_data!==expected_commands[commands_seen])$fatal(1,"command %0d got=%h expected=%h active=%b",commands_seen,o_cmd_data,expected_commands[commands_seen],active);
                active<=1;active_words<=o_cmd_data[22:0]>>3;active_position<=0;
                commands_seen=commands_seen+1;
            end
            if(o_data_valid && i_data_ready)begin
                if(!active || o_data!==expected_beats[beats_seen][63:0] || o_data_keep!=8'hff || o_data_last!==expected_beats[beats_seen][132] || o_data_last!==(active_position==active_words-1))
                    $fatal(1,"beat %0d data=%h expected=%h last=%b pos=%0d/%0d",beats_seen,o_data,expected_beats[beats_seen][63:0],o_data_last,active_position,active_words);
                beats_seen=beats_seen+1;active_position<=active_position+1;
                if(o_data_last)status_delay<=commands_seen==meta[case_index][31:0] ? 17 : 3;
            end
            if(status_delay>0)begin
                status_delay<=status_delay-1;
                if(status_delay==1)begin i_status_valid<=1;i_status<=8'h80;end
            end
            if(i_status_valid && o_status_ready)begin
                if(active_position!=active_words)$fatal(1,"status before last data");
                i_status_valid<=0;active<=0;statuses_seen=statuses_seen+1;
            end
            if(o_output_done && (commands_seen!=meta[case_index][31:0] || beats_seen!=meta[case_index][63:32] || statuses_seen!=commands_seen || i_packer_busy || !i_spatial_fifo_empty || !i_bypass_fifo_empty))
                $fatal(1,"premature output_done");
            $fwrite(trace,"%0d,%0d,%0d,%0d,%b,%b,%b,%b,%b,%b,%b\n",case_index,cycles,dut.state_current,o_group_index,i_ce,o_cmd_valid&&i_cmd_ready,o_data_valid&&i_data_ready,i_status_valid&&o_status_ready,o_group_write_done,o_output_done,post_full);
        end
    end
    always@(negedge i_clk)begin
        if(i_rstn)begin
            i_ce=!pause_override && cycles%29<25;
            i_cmd_ready=cycles%7!=2 && !(case_index==4 && cycles-case_start<12000);
            i_data_ready=cycles%11<7;
            if(case_index<4 && o_group_write_done && o_group_index<groups-1 && i_group_index==o_group_index && cycles%7==0)begin
                i_group_index=o_group_index+1;group_events=group_events+1;
            end
        end
    end
    task tick;
        begin @(posedge i_clk);#1;@(negedge i_clk);#1;end
    endtask
    task reset_all;
        begin
            i_rstn=0;i_start=0;i_ce=1;pause_override=0;producer_valid=0;post_in_valid=0;
            hold_packer=0;mock_compute_done=0;i_group_index=0;
            repeat(3)tick;i_rstn=1;repeat(2)tick;
        end
    endtask
    initial begin
        $readmemh("d3_configs.mem",configs);$readmemh("d3_meta.mem",meta);
        $readmemh("d3_commands.mem",expected_commands);$readmemh("d3_beats.mem",expected_beats);$readmemh("d3_bundles.mem",bundles);
        trace=$fopen("d3_trace.csv","w");
        $fwrite(trace,"case,fclk,state,group,ce,command,data,status,group_done,output_done,fifo_full\n");
        for(case_index=0;case_index<7;case_index=case_index+1)begin
            reset_all;case_start=cycles;{i_extension,i_base_instruction}=configs[case_index];
            post_position=case_index<4 ? 0 : meta[case_index-1][63:32];
            while(!o_start_ready || (case_index>=4 && !post_cal_ready))tick;i_start=1;tick;i_start=0;
            if(case_index<4)begin
                while(bundles_sent<meta[case_index][95:64])begin
                    producer_spatial=bundles[bundles_sent][5299:5292];
                    producer_mask=bundles[bundles_sent][5255:5184];
                    producer_data=bundles[bundles_sent][3455:0];
                    while(!bundle_ready)tick;
                    producer_valid=1;tick;producer_valid=0;bundles_sent=bundles_sent+1;
                end
            end else begin
                while(post_position<meta[case_index][63:32])tick;
            end
            hold_packer=1;pause_override=1;i_ce=0;mock_compute_done=1;tick;mock_compute_done=0;
            repeat(4)tick;
            if((case_index<4 && !dut.flag_compute_done) || o_output_done)$fatal(1,"compute pulse lost or bypassed packer barrier");
            pause_override=0;repeat(6)tick;hold_packer=0;
            while(!o_output_done)tick;
            if(o_commands_accepted!=(meta[case_index][31:0]-(case_index==0 ? 0 : meta[case_index-1][31:0])) || o_data_beats!=(meta[case_index][63:32]-(case_index==0 ? 0 : meta[case_index-1][63:32])) || o_responses_ok!=o_commands_accepted)
                $fatal(1,"independent transaction counters mismatch");
            $display("PASS D3 case=%0d commands=%0d beats=%0d statuses=%0d",case_index,commands_seen,beats_seen,statuses_seen);
            pause_override=1;i_ce=0;tick;if(o_output_done)$fatal(1,"output_done stretched under pause");pause_override=0;
        end
        if(commands_seen!=1195 || beats_seen!=1324 || statuses_seen!=1195 || bundles_sent!=34 || group_events!=4 || full_cycles==0 || pause_handshakes==0 || posts_seen!=3096 || post_layers_done!=3)$fatal(1,"D3 coverage incomplete groups=%0d full=%0d pause=%0d posts=%0d",group_events,full_cycles,pause_handshakes,posts_seen);
        $fclose(trace);test_done=1;$finish;
    end
    initial begin #3000000;test_failed=1;$fatal(1,"D3 watchdog case=%0d state=%0d commands=%0d beats=%0d",case_index,dut.state_current,commands_seen,beats_seen);end
endmodule
