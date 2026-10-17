`timescale 1ns / 1ps

// D2真实D0/D1/C0/C1/C2/12CU/CONCAT/B5/双FIFO；DMA和后处理为确定性事务模型。
module tb_cal_cmd;
    reg clk=0;
    always #5 clk=~clk;
    reg rstn=0,ce=1,soft_reset=0,start=0;
    reg [255:0]base_instruction=0,extension=0;
    wire cal_start_ready,cal_busy,compute_done,cal_error;
    wire [3:0]cal_error_code;
    reg dependency_error=0,force_full=0;
    wire scan_req,scan_ready,feature_ready,scan_finish,scan_done;
    wire load_req,load_ready,weight_ready,compute_idle;
    wire [9:0]group_index,feature_group;
    wire [8:0]weight_group,loaded_group;
    wire [7:0]tile_index,feature_tile,loaded_tile;
    wire [15:0]tile_base;
    wire update_req,update_ready,update_done;
    wire [15:0]update_row;
    wire [11:0]update_col;
    wire [1:0]update_bank;
    wire feature_rd,feature_rd_ready,feature_response,weight_rd,weight_rd_ready,weight_response;
    wire [12:0]feature_addr;
    wire [7:0]weight_addr;
    wire datapath_ce,pair_valid,pair_first,pair_last,pair_row_last,array_ready;
    wire [1:0]mode,row_select,pair_mask;
    wire [2:0]row_mask;
    wire column_valid,bundle_valid,bundle_ready,packer_busy,fifo_full,first_tile,last_tile;
    wire [71:0]lane_mask;
    wire [31:0]spatial_index;
    wire [7:0]cu_valid,column_commit,row_advance;
    wire [383:0]cu_zero;
    wire [1151:0]cu_one,cu_two,cu_three;
    wire [3455:0]bundle_data,bias_data;
    wire [71:0]concat_mask;
    wire concat_valid;
    wire [95:0]feature_data,selected_data;
    wire selected_valid;
    wire [2303:0]weight_data;
    wire feature_error,weight_error,feature_start_ready,weight_start_ready;
    wire f_cmd_valid,f_cmd_ready,f_data_valid,f_data_ready,f_last,f_status_valid,f_status_ready;
    wire w_cmd_valid,w_cmd_ready,w_data_valid,w_data_ready,w_last,w_status_valid,w_status_ready;
    wire [71:0]f_cmd,w_cmd;
    wire [63:0]f_data,w_data;
    wire f_wr,f_wr_ready,f_safe,w_wr,w_wr_ready,w_load_enable;
    wire [1:0]f_bank;
    wire [11:0]f_addr;
    wire [63:0]f_write_data;
    wire [3:0]w_cu,w_bank;
    wire [7:0]w_addr;
    wire [31:0]w_write_data;
    wire spatial_valid,bypass_valid,spatial_empty,bypass_empty;
    wire [63:0]spatial_data,bypass_data;
    wire [3:0]spatial_mask,bypass_mask;
    wire [9:0]spatial_count,bypass_count;
    reg consumer_enable=1;
    wire consumer_ready=consumer_enable && ce && cycles%7!=2;
    wire group_write_done=spatial_empty && bypass_empty && !packer_busy && cycles%11==0;
    wire stream_req,block_req,post_valid;
    wire [15:0]block_row,post_row;
    wire [7:0]post_block;
    wire [9:0]block_channels;
    wire [11:0]post_col;
    wire [1:0]post_stage;
    wire [6:0]post_quad;
    wire [3:0]post_mask;
    reg stream_done=0,block_done=0,post_done=0;
    wire stream_ready=cycles%5==0;
    wire block_ready=cycles%7==0;
    wire post_ready=cycles%4!=1;
    wire dependencies=dependency_error || feature_error || weight_error;
    wire cal_full=force_full || fifo_full;
    reg test_done=0,test_failed=0;
    integer cycles=0,case_index=0,pairs_seen=0,posts_seen=0,bundles_seen=0,beats_seen=0;
    integer scans_seen=0,loads_seen=0,updates_seen=0,commits_seen=0,rows_seen=0;
    integer full_cycles=0,pause_cycles=0,block_requests=0,stream_requests=0;
    integer freeze_checks=0;
    reg [127:0]control_before;
    reg [1023:0]core_before;
    reg control_stopped,core_stopped;
    wire [127:0]control_state={dut.state_current,group_index,tile_index,dut.cnt_pair,dut.cnt_row,dut.cnt_column,row_select,spatial_index,feature_addr,row_mask,column_valid};
    wire [1023:0]core_state={array.compute_unit_first_Inst.reg_tags_first,array.compute_unit_first_Inst.reg_tags_second,
        array.compute_unit_first_Inst.three_stage_acc_Inst.column_acc_first_Inst.reg_top_sum,
        array.compute_unit_first_Inst.three_stage_acc_Inst.column_acc_middle_Inst.reg_top_sum,
        array.compute_unit_first_Inst.three_stage_acc_Inst.column_acc_last_Inst.reg_top_sum,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_position,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_left,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_middle,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_right,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_left,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_middle,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_right,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_left,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_middle,
        array.compute_unit_first_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_right};
    integer errors_checked=0,resets_checked=0,boundaries_checked=0;
    integer frame=0,trace=0,delay_stream=0,delay_block=0,delay_post=0;
    integer f_beats=0,f_position=0,w_beats=0,w_position=0;
    reg f_active=0,w_active=0,f_status=0,w_status=0;
    reg [31:0]f_address=0,w_address=0;
    reg [511:0]configs[0:8];
    reg [127:0]metadata[0:8];
    reg [95:0]pair_expected[0:6787];
    reg [63:0]post_expected[0:2063];
    reg [5343:0]bundle_expected[0:85];
    reg [71:0]beat_expected[0:747];
    reg [95:0]pair_actual;
    reg [63:0]post_actual;
    reg [5343:0]bundle_actual;
    reg [511:0]held_state;

    cal_cmd dut(
        .i_clk(clk),.i_rstn(rstn),.i_ce(ce),.i_soft_reset(soft_reset),.i_start(start),
        .i_base_instruction(base_instruction),.i_extension(extension),.o_start_ready(cal_start_ready),
        .o_busy(cal_busy),.o_compute_done(compute_done),.o_error(cal_error),.o_error_code(cal_error_code),.i_dependency_error(dependencies),
        .o_scan_req(scan_req),.i_scan_ready(scan_ready),.i_feature_ready(feature_ready),.i_feature_group(feature_group),.i_feature_tile(feature_tile),
        .o_scan_finish(scan_finish),.i_scan_done(scan_done),.o_load_req(load_req),.i_load_ready(load_ready),.i_weight_ready(weight_ready),
        .i_weight_group(loaded_group),.i_weight_tile(loaded_tile),.o_compute_idle(compute_idle),.o_group_index(group_index),
        .o_weight_group(weight_group),.o_tile_index(tile_index),.o_tile_channel_base(tile_base),
        .o_update_req(update_req),.i_update_ready(update_ready),.o_update_row(update_row),.o_update_col(update_col),.o_update_bank(update_bank),.i_update_done(update_done),
        .o_feature_rd_valid(feature_rd),.i_feature_rd_ready(feature_rd_ready),.o_feature_rd_addr(feature_addr),.i_feature_out_valid(feature_response),
        .o_weight_rd_valid(weight_rd),.i_weight_rd_ready(weight_rd_ready),.o_weight_rd_addr(weight_addr),.i_weight_out_valid(weight_response),
        .o_datapath_ce(datapath_ce),.o_pair_valid(pair_valid),.i_array_ready(array_ready),.o_pair_first(pair_first),.o_pair_last(pair_last),
        .o_pair_row_last(pair_row_last),.o_mode(mode),.o_row_select(row_select),.o_row_mask(row_mask),.o_column_valid(column_valid),.o_pair_mask(pair_mask),
        .i_column_commit(column_commit[0]),.i_row_advance(row_advance[0]),.i_cu_valid(cu_valid[0]),
        .i_bundle_ready(bundle_ready),.i_packer_busy(packer_busy),.i_fifo_full(cal_full),.i_group_write_done(group_write_done),
        .o_bundle_valid(bundle_valid),.o_lane_mask(lane_mask),.o_spatial_index(spatial_index),.o_first_tile(first_tile),.o_last_tile(last_tile),
        .o_post_stream_req(stream_req),.i_post_stream_ready(stream_ready),.i_post_stream_done(stream_done),
        .o_post_block_req(block_req),.i_post_block_ready(block_ready),.i_post_block_done(block_done),
        .o_post_block_row(block_row),.o_post_block(post_block),.o_post_block_channels(block_channels),
        .o_post_valid(post_valid),.i_post_ready(post_ready),.o_post_row(post_row),.o_post_col(post_col),.o_post_stage(post_stage),
        .o_post_quad(post_quad),.o_post_mask(post_mask),.i_post_done(post_done));

    // 后处理层不启动现有CONV/FC权重控制器，缓存和流适配器以单在途BFM连接。
    feature_cmd feature_control(
        .i_clk(clk),.i_rstn(rstn),.i_ce(ce),.i_soft_reset(soft_reset),.i_start(start && case_index<6),
        .i_base_instruction(base_instruction),.i_extension(extension),.o_start_ready(feature_start_ready),
        .i_scan_req(scan_req),.o_scan_ready(scan_ready),.i_group_index(group_index),.i_tile_index(tile_index),.i_tile_channel_base(tile_base),
        .i_update_req(update_req),.o_update_ready(update_ready),.i_update_row(update_row),.i_update_col(update_col),.i_update_bank(update_bank),
        .i_scan_finish(scan_finish),.o_feature_ready(feature_ready),.o_update_done(update_done),.o_scan_done(scan_done),
        .o_group_index(feature_group),.o_tile_index(feature_tile),.o_busy(),.o_error(feature_error),.o_error_code(),
        .o_cmd_valid(f_cmd_valid),.i_cmd_ready(f_cmd_ready),.o_cmd_data(f_cmd),.i_data_valid(f_data_valid),.o_data_ready(f_data_ready),
        .i_data(f_data),.i_data_keep(8'hff),.i_data_last(f_last),.i_status_valid(f_status_valid),.o_status_ready(f_status_ready),.i_status(8'h80),
        .o_wr_valid(f_wr),.i_wr_ready(f_wr_ready),.o_wr_safe(f_safe),.o_wr_bank(f_bank),.o_wr_addr(f_addr),.o_wr_data(f_write_data));
    weight_cmd weight_control(
        .i_clk(clk),.i_rstn(rstn),.i_ce(ce),.i_soft_reset(soft_reset),.i_start(start && case_index<6),
        .i_base_instruction(base_instruction),.i_extension(extension),.i_compute_idle(compute_idle),.o_start_ready(weight_start_ready),
        .i_load_req(load_req),.o_load_ready(load_ready),.i_group_index(weight_group),.i_tile_index(tile_index),
        .o_weight_ready(weight_ready),.o_load_done(),.o_group_index(loaded_group),.o_tile_index(loaded_tile),.o_bias_data(bias_data),
        .o_load_enable(w_load_enable),.o_busy(),.o_error(weight_error),.o_error_code(),
        .o_cmd_valid(w_cmd_valid),.i_cmd_ready(w_cmd_ready),.o_cmd_data(w_cmd),.i_data_valid(w_data_valid),.o_data_ready(w_data_ready),
        .i_data(w_data),.i_data_keep(8'hff),.i_data_last(w_last),.i_status_valid(w_status_valid),.o_status_ready(w_status_ready),.i_status(8'h80),
        .o_wr_valid(w_wr),.i_wr_ready(w_wr_ready),.o_wr_cu(w_cu),.o_wr_bank(w_bank),.o_wr_addr(w_addr),.o_wr_data(w_write_data));
    feature_buffer features(
        .i_clk(clk),.i_rstn(rstn),.i_ce(datapath_ce),.i_wr_valid(f_wr),.i_wr_safe(f_safe),.i_wr_bank(f_bank),.i_wr_addr(f_addr),.i_wr_data(f_write_data),
        .o_wr_ready(f_wr_ready),.i_rd_valid(feature_rd),.i_rd_addr(feature_addr),.o_rd_ready(feature_rd_ready),.o_out_valid(feature_response),.o_out_data(feature_data));
    kernel_buffer weights(
        .i_clk(clk),.i_rstn(rstn),.i_ce(datapath_ce),.i_load_enable(w_load_enable),.i_wr_valid(w_wr),.i_wr_cu(w_cu),.i_wr_bank(w_bank),.i_wr_addr(w_addr),.i_wr_data(w_write_data),
        .o_wr_ready(w_wr_ready),.i_rd_valid(weight_rd),.i_rd_addr(weight_addr),.o_rd_ready(weight_rd_ready),.o_out_valid(weight_response),.o_out_data(weight_data));
    fout_selector select_features(
        .i_in_valid(pair_valid),.i_in_data(feature_data),.i_mode(mode),.i_row_select(row_select),.i_row_mask(row_mask),
        .i_column_valid(column_valid),.i_pair_mask(pair_mask),.o_out_valid(selected_valid),.o_out_data(selected_data));
    compute_array array(
        .i_clk(clk),.i_rstn(rstn),.i_ce(datapath_ce),.i_in_valid(selected_valid),.i_first(pair_first),.i_last(pair_last),.i_row_last(pair_row_last),
        .i_mode(mode),.i_feature_data(selected_data),.i_weight_data(weight_data),.o_ready(array_ready),.o_cu_valid(cu_valid),
        .o_zero(cu_zero),.o_one(cu_one),.o_two(cu_two),.o_three(cu_three),.o_column_commit(column_commit),.o_row_advance(row_advance));
    concat concatenate(
        .i_clk(clk),.i_rstn(rstn),.i_ce(ce),.i_mode(mode),.i_valid_lanes(dut.reg_lanes),.i_cu_valid(cu_valid),
        .i_zero(cu_zero),.i_one(cu_one),.i_two(cu_two),.i_three(cu_three),.o_bundle_valid(concat_valid),.o_bundle_data(bundle_data),.o_lane_mask(concat_mask));
    result_output results(
        .i_clk(clk),.i_rstn(rstn),.i_bundle_valid(bundle_valid),.o_bundle_ready(bundle_ready),.i_bundle_data(bundle_data),.i_bias_data(bias_data),
        .i_lane_mask(lane_mask),.i_mode(mode),.i_spatial_index(spatial_index[7:0]),.i_first_tile(first_tile),.i_last_tile(last_tile),.i_right_shift(6'd0),.i_relu(1'b0),
        .o_busy(packer_busy),.o_fifo_full(fifo_full),.o_spatial_fifo_valid(spatial_valid),.i_spatial_fifo_ready(consumer_ready),
        .o_spatial_fifo_data(spatial_data),.o_spatial_fifo_mask(spatial_mask),.o_spatial_fifo_full(),.o_spatial_fifo_empty(spatial_empty),.o_spatial_fifo_count(spatial_count),
        .o_bypass_fifo_valid(bypass_valid),.i_bypass_fifo_ready(consumer_ready),.o_bypass_fifo_data(bypass_data),.o_bypass_fifo_mask(bypass_mask),
        .o_bypass_fifo_full(),.o_bypass_fifo_empty(bypass_empty),.o_bypass_fifo_count(bypass_count));

    // HP0每地址由完整DDR HWC步长定义；填充lane故意为非零。
    function [63:0]feature_word;
        input [31:0]address;
        integer vector,value;
        begin
            vector=(address-base_instruction[31:0])/(extension[143:128]*2);
            value=vector%7-3;
            feature_word={4{value[15:0]}};
        end
    endfunction
    // HP1由A3固定CU/bank/channel物理布局枚举，不依赖CAL读地址。
    function [63:0]weight_word;
        input [31:0]address;
        integer element,block_number,group_number,cu,bank,output_channel,value;
        integer logical_depth,tiles,parallel;
        begin
            parallel=base_instruction[197] ? 72 : 8;
            if(address>=extension[63:32])begin
                output_channel=(address-extension[63:32])/8;
                value=output_channel%5-2;
                weight_word={{32{value[31]}},value[31:0]};
            end else begin
                logical_depth=extension[171:168]==1 ? extension[223:192] : base_instruction[183:172];
                tiles=(logical_depth+511)/512;
                element=(address-extension[31:0])/2;
                block_number=element/36864;
                group_number=block_number/tiles;
                cu=(element%36864)/4608;
                bank=(element%4608)/512;
                output_channel=group_number*parallel+(parallel==72 ? cu*9+bank : cu);
                value=1+output_channel%3;
                weight_word={4{value[15:0]}};
            end
        end
    endfunction
    assign f_cmd_ready=!f_active && !f_status && cycles%3!=1;
    assign w_cmd_ready=!w_active && !w_status && cycles%5!=2;
    assign f_data_valid=f_active && cycles%4!=1;
    assign w_data_valid=w_active && cycles%7!=3;
    assign f_data=feature_word(f_address+f_position*8);
    assign w_data=weight_word(w_address+w_position*8);
    assign f_last=f_position==f_beats-1;
    assign w_last=w_position==w_beats-1;
    assign f_status_valid=f_status && cycles%3==0;
    assign w_status_valid=w_status && cycles%5==0;

    // 命令在ce暂停中也按FCLK接受，数据/状态由实际ready决定推进。
    always@(posedge clk)begin
        cycles=cycles+1;
        if(!rstn || soft_reset)begin
            f_active<=0;w_active<=0;f_status<=0;w_status<=0;
            f_position<=0;w_position<=0;
            stream_done<=0;block_done<=0;post_done<=0;
            delay_stream<=0;delay_block<=0;delay_post<=0;
        end else begin
            if(f_cmd_valid && f_cmd_ready)begin
                f_address<=f_cmd[63:32];f_beats<=f_cmd[22:0]/8;f_position<=0;f_active<=1;
                if(f_cmd[71:64]!=0 || f_cmd[31:23]!=9'h081 || f_cmd[2:0]!=0) $fatal(1,"HP0 command contract");
            end
            if(w_cmd_valid && w_cmd_ready)begin
                w_address<=w_cmd[63:32];w_beats<=w_cmd[22:0]/8;w_position<=0;w_active<=1;
            end
            if(f_data_valid && f_data_ready)begin
                f_position<=f_position+1;
                if(f_last)begin f_active<=0;f_status<=1;end
            end
            if(w_data_valid && w_data_ready)begin
                w_position<=w_position+1;
                if(w_last)begin w_active<=0;w_status<=1;end
            end
            if(f_status_valid && f_status_ready) f_status<=0;
            if(w_status_valid && w_status_ready) w_status<=0;
            stream_done<=0;block_done<=0;post_done<=0;
            if(stream_req && stream_ready)begin stream_requests=stream_requests+1;end
            if(block_req && block_ready)begin
                block_requests=block_requests+1;delay_block<=3;
                if(block_channels !== (post_block==0 ? 10'd512 : 10'd1) || block_row!==post_row-(post_stage[1]))
                    $fatal(1,"Pool block coordinates/tail mismatch");
            end
            if(delay_block>0)begin
                delay_block<=delay_block-1;
                if(delay_block==1) block_done<=1;
            end
            if(post_valid && post_ready)begin
                if(post_stage==3 || extension[171:168]==3) delay_post<=3;
                if(group_index==dut.reg_groups-1 && post_row==dut.reg_height-1 && post_col==dut.reg_width-1 && extension[171:168]>=3) delay_stream<=5;
                if(group_index==dut.reg_groups-1 && post_row==dut.reg_height-1 && post_col==dut.reg_width-1 && extension[171:168]==4) delay_post<=25;
            end
            if(delay_stream>0)begin delay_stream<=delay_stream-1;if(delay_stream==1)stream_done<=1;end
            if(delay_post>0)begin delay_post<=delay_post-1;if(delay_post==1)post_done<=1;end
        end
    end

    // 只比较实际握手事件；不同FCLK停顿不得改变算法序列。
    always@(posedge clk)begin
        if(rstn && !soft_reset)begin
            if(cal_error || feature_error || weight_error) $fatal(1,"D2 error case=%0d CAL=%0d F=%b W=%b state=%0d",case_index,cal_error_code,feature_error,weight_error,dut.state_current);
            if(scan_req && scan_ready) scans_seen=scans_seen+1;
            if(load_req && load_ready)begin
                loads_seen=loads_seen+1;
                if(!compute_idle || feature_rd || weight_rd || pair_valid) $fatal(1,"Unsafe weight load");
            end
            if(update_req && update_ready)begin
                updates_seen=updates_seen+1;
                if(update_row<3 || update_bank!=update_row%3 || pair_valid || feature_rd || weight_rd) $fatal(1,"Unsafe feature update");
            end
            if(datapath_ce && column_commit[0])begin
                commits_seen=commits_seen+1;
                if(column_commit!==8'hff) $fatal(1,"CU commit lost lockstep");
            end
            if(datapath_ce && row_advance[0]) rows_seen=rows_seen+1;
            if(pair_valid && array_ready)begin
                pair_actual={10'd0,pair_mask,column_valid,row_mask,row_select,weight_addr,feature_addr,dut.cnt_pair,dut.cnt_column,dut.cnt_row,tile_index,group_index};
                if(pair_actual!==pair_expected[pairs_seen]) $fatal(1,"Pair event %0d mismatch got=%h expected=%h",pairs_seen,pair_actual,pair_expected[pairs_seen]);
                pairs_seen=pairs_seen+1;
            end
            if(bundle_valid && bundle_ready)begin
                bundle_actual={last_tile,first_tile,tile_index,group_index,spatial_index,36'd0,lane_mask,1728'd0,bundle_data};
                if(bundle_actual!==bundle_expected[bundles_seen]) $fatal(1,"Bundle %0d mismatch case=%0d group=%0d tile=%0d spatial=%0d low=%h expectedlow=%h",bundles_seen,case_index,group_index,tile_index,spatial_index,bundle_data[47:0],bundle_expected[bundles_seen][47:0]);
                if(cu_valid!==8'hff || lane_mask!==concat_mask) $fatal(1,"CONCAT lockstep/mask mismatch");
                bundles_seen=bundles_seen+1;
            end
            if(consumer_ready && (spatial_valid || bypass_valid))begin
                if({3'd0,bypass_valid,(bypass_valid ? bypass_mask : spatial_mask),(bypass_valid ? bypass_data : spatial_data)}!==beat_expected[beats_seen])
                    $fatal(1,"FIFO beat %0d mismatch",beats_seen);
                beats_seen=beats_seen+1;
            end
            if(post_valid && post_ready)begin
                post_actual={5'd0,post_mask,post_quad,post_block,post_stage,group_index,post_col,post_row};
                if(post_actual!==post_expected[posts_seen]) $fatal(1,"Post event %0d got=%h expected=%h",posts_seen,post_actual,post_expected[posts_seen]);
                posts_seen=posts_seen+1;
            end
            if(!ce && (pair_valid || feature_rd || weight_rd || update_req || bundle_valid || post_valid)) $fatal(1,"Pause emitted event");
            $fwrite(trace,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%b,%b,%b,%b,%b,%b\n",case_index,cycles,dut.state_current,group_index,tile_index,dut.cnt_row,dut.cnt_column,dut.cnt_pair,ce,pair_valid&&array_ready,datapath_ce&&column_commit[0],bundle_valid&&bundle_ready,fifo_full,post_valid&&post_ready);
        end
    end
    // 固定外部暂停；真实FIFO满保持40拍后放开消费者。
    always@(posedge clk)begin
        if(rstn && !soft_reset)begin
            control_before=control_state;core_before=core_state;
            control_stopped=!dut.flag_step;core_stopped=!datapath_ce;
            #1;
            if(control_stopped && control_state!==control_before) $fatal(1,"CAL coordinates changed during pause/full");
            if(core_stopped && core_state!==core_before) $fatal(1,"CU/KsP1 state changed without CE");
            if(control_stopped || core_stopped)freeze_checks=freeze_checks+1;
        end
    end
    always@(negedge clk)begin
        if(rstn)begin
            ce=cycles%97<92;
            if(!ce)pause_cycles=pause_cycles+1;
            if(case_index==5 && fifo_full)begin
                full_cycles=full_cycles+1;
                if(full_cycles>=40) consumer_enable=1;
            end
        end
    end
    task tick;
        begin @(posedge clk);#1;@(negedge clk);#1;end
    endtask
    task reset_all;
        begin
            rstn=0;start=0;ce=1;consumer_enable=1;
            f_active=0;w_active=0;f_status=0;w_status=0;
            repeat(3) tick;
            rstn=1;repeat(3)tick;
        end
    endtask
    initial begin
        $readmemh("d2_configs.mem",configs);$readmemh("d2_meta.mem",metadata);
        $readmemh("d2_pairs.mem",pair_expected);$readmemh("d2_posts.mem",post_expected);
        $readmemh("d2_bundles.mem",bundle_expected);$readmemh("d2_beats.mem",beat_expected);
        trace=$fopen("d2_trace.csv","w");
        $fwrite(trace,"case,fclk,state,group,tile,row,column,pair,ce,pair_fire,column_commit,output_fire,fifo_full,post_fire\n");
        for(case_index=0;case_index<9;case_index=case_index+1)begin
            reset_all;
            {extension,base_instruction}=configs[case_index];
            if(case_index==5)consumer_enable=0;
            while(!cal_start_ready || (case_index<6 && (!feature_start_ready || !weight_start_ready)))tick;
            start=1;tick;start=0;
            while(!compute_done)tick;
            if(pairs_seen!=metadata[case_index][31:0] || posts_seen!=metadata[case_index][63:32] || bundles_seen!=metadata[case_index][95:64] || beats_seen!=metadata[case_index][127:96])
                $fatal(1,"D2 case %0d final counts P=%0d POST=%0d B=%0d OUT=%0d",case_index,pairs_seen,posts_seen,bundles_seen,beats_seen);
            if(case_index==5 && full_cycles<40) $fatal(1,"Actual FIFO did not fill");
            $display("PASS D2 case=%0d pairs=%0d posts=%0d bundles=%0d beats=%0d",case_index,pairs_seen,posts_seen,bundles_seen,beats_seen);
            tick;if(compute_done)$fatal(1,"compute_done stretched");
        end
        $fclose(trace);test_done=1;$finish;
    end
    initial begin #30000000;test_failed=1;$fatal(1,"D2 watchdog case=%0d state=%0d pairs=%0d",case_index,dut.state_current,pairs_seen);end
endmodule
