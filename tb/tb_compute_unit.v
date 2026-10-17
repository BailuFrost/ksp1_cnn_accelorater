`timescale 1ns / 1ps
`include "width_step1_checks.vh"
`include "compute_unit_count.vh"
// 完整CU：每模式一个案例；3×3逐拍额外核对全部缓存状态。
module tb_compute_unit;
    reg clk = 1'b0;
    reg [1310:0] stimulus = 1311'd0;
    reg [1310:0] vectors [0:`COMPUTE_UNIT_CYCLES-1];
    wire in_ready, out_valid, commit, advance;
    wire signed [47:0] o_zero;
    wire [143:0] o_one,o_two,o_three;
    wire [431:0] cache_snapshot;
    reg test_done = 1'b0;
    reg test_failed = 1'b0;
    integer cycle;
    integer counts [0:3];
    integer mode_index;
    integer trace_file;
    reg sampled_commit,sampled_advance;
    reg recovered = 1'b0;
    always @(posedge clk or negedge stimulus[386]) begin
        if (!stimulus[386]) recovered <= 1'b0;
        else recovered <= 1'b1;
    end

    compute_unit compute_unit_Inst (
        .i_clk(clk), .i_rstn(stimulus[386]), .i_ce(stimulus[387]), .i_mode(stimulus[385:384]),
        .i_in_valid(stimulus[388]), .i_first(stimulus[389]), .i_last(stimulus[390]),
        .i_row_last(stimulus[391]), .i_feature_data(stimulus[95:0]), .i_weight_data(stimulus[383:96]),
        .o_ready(in_ready), .o_valid(out_valid), .o_zero(o_zero),
        .o_one(o_one), .o_two(o_two), .o_three(o_three), .o_column_commit(commit), .o_row_advance(advance)
    );
assign cache_snapshot = {{{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_right[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_right},
        {{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_middle[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_middle},
        {{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_left[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_left},
        {{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_right[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_right},
        {{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_middle[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_middle},
        {{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_left[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_left},
        {{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_right[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_right},
        {{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_middle[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_middle},
        {{6{compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_left[41]}}, compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_left}};
    always #5 clk=~clk;
    initial begin
        for (mode_index=0;mode_index<4;mode_index=mode_index+1) counts[mode_index]=0;
        $readmemh("compute_unit_vectors.mem",vectors);
        trace_file=$fopen("compute_unit_trace.csv","w");
        if (trace_file==0) begin test_failed=1'b1; $display("FAIL trace open"); $finish; end
        $fdisplay(trace_file,"fclk,mode,ce,in_valid,column_commit,row_advance,out_valid,result_hex,cache_hex");
        for (cycle=0;cycle<`COMPUTE_UNIT_CYCLES;cycle=cycle+1) begin
            @(negedge clk); stimulus=vectors[cycle];
            @(posedge clk);
            sampled_commit=commit; sampled_advance=advance;
            if (commit !== stimulus[392] || advance !== stimulus[393] ||
                in_ready !== (recovered && stimulus[386] && stimulus[387])) begin
                test_failed=1'b1; $display("FAIL event cycle=%0d",cycle); $finish;
            end
            #1;
            if (out_valid !== stimulus[394] || {o_three,o_two,o_one,o_zero} !== stimulus[874:395]) begin
                test_failed=1'b1;
                $display("FAIL result cycle=%0d mode=%0d valid=%b/%b",cycle,stimulus[385:384],out_valid,stimulus[394]);
                $display("actual=%h expected=%h",{o_three,o_two,o_one,o_zero},stimulus[874:395]); $finish;
            end
            if (stimulus[385:384]==2'b00 && (cache_snapshot !== stimulus[1306:875] ||
                compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_slot !== stimulus[1308:1307] ||
                compute_unit_Inst.three_stage_acc_Inst.ksp1_cache_Inst.reg_filled !== stimulus[1310:1309])) begin
                test_failed=1'b1; $display("FAIL cache cycle=%0d",cycle); $finish;
            end
            if (stimulus[386] && stimulus[387] && out_valid) counts[stimulus[385:384]]=counts[stimulus[385:384]]+1;
            $fdisplay(trace_file,"%0d,%0d,%b,%b,%b,%b,%b,%h,%h",cycle,stimulus[385:384],stimulus[387],
                      stimulus[388],sampled_commit,sampled_advance,out_valid,{o_three,o_two,o_one,o_zero},cache_snapshot);
        end
        $fclose(trace_file);
        if (counts[0]!=6 || counts[1]!=12 || counts[2]!=3 || counts[3]!=3) begin
            test_failed=1'b1; $display("FAIL counts %0d,%0d,%0d,%0d",counts[0],counts[1],counts[2],counts[3]);
        end else begin
            test_done=1'b1; $display("PASS B3 cycles=%0d outputs=6,12,3,3 four_modes=PASS",cycle);
        end
        $finish;
    end
    initial begin
        #20000; test_failed=1'b1; $display("FAIL B3 watchdog"); $finish;
    end
    `WIDTH_CU(compute_unit_Inst)
endmodule
