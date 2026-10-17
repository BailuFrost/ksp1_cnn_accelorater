`timescale 1ns / 1ps
`include "width_step1_checks.vh"
// 四模式完整CU：非沿复位、恢复首沿、在途清空、冻结及数值重启。
module tb_compute_unit_reset;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    reg ce = 1'b0;
    reg input_valid = 1'b0;
    reg first = 1'b0, last = 1'b0, row_last = 1'b0;
    reg [1:0] mode = 2'd0;
    reg [95:0] features = 96'd0;
    reg [287:0] weights = 288'd0;
    wire ready, valid, commit, advance;
    wire signed [47:0] zero;
    wire [143:0] one, two, three;
    wire [431:0] cache;
    wire [1840:0] snapshot;
    reg [1840:0] held;
    reg test_done = 1'b0, test_failed = 1'b0;
    integer async_reset_checks = 0;
    integer completed = 0, stalls = 0;
    integer m,n,k,first_result,column_index;
    reg expected_valid;
    reg signed [47:0] expected;
    compute_unit dut (
        .i_clk(clk), .i_rstn(rstn), .i_ce(ce), .i_in_valid(input_valid),
        .i_first(first), .i_last(last), .i_row_last(row_last), .i_mode(mode),
        .i_feature_data(features), .i_weight_data(weights), .o_ready(ready),
        .o_valid(valid), .o_zero(zero), .o_one(one), .o_two(two), .o_three(three),
        .o_column_commit(commit), .o_row_advance(advance)
    );
    assign cache = {{{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_right[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_right},
        {{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_middle[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_middle},
        {{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_left[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_third_left},
        {{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_right[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_right},
        {{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_middle[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_middle},
        {{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_left[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_second_left},
        {{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_right[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_right},
        {{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_middle[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_middle},
        {{6{dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_left[41]}}, dut.three_stage_acc_Inst.ksp1_cache_Inst.reg_cache_first_left}};
    // Parent控制状态、全部MAC/列结果以及三列缓存作为同一暂停快照。
    assign snapshot = {dut.reg_tags_first,dut.reg_tags_second,
        dut.flag_mac_valid,dut.reg_mac_data,dut.three_stage_acc_Inst.reg_mode,
        dut.three_stage_acc_Inst.reg_row_tags,dut.three_stage_acc_Inst.reg_small_ingress,
        dut.three_stage_acc_Inst.reg_previous,dut.three_stage_acc_Inst.reg_small_result,
        dut.three_stage_acc_Inst.flag_small_filled,dut.three_stage_acc_Inst.flag_small_valid,
        dut.three_stage_acc_Inst.flag_bypass_valid,dut.three_stage_acc_Inst.flag_vector_valid,
        dut.three_stage_acc_Inst.reg_vector_data,cache,valid,zero,one,two,three};
    always #5 clk = ~clk;
    task fail;
        input [255:0] reason;
        begin
            test_failed = 1'b1;
            $display("FAIL B3 reset mode=%0d n=%0d %s",m,n,reason);
            $finish;
        end
    endtask
    task release_reset;
        begin
            @(posedge clk); #2; rstn = 1'b1;
            @(negedge clk);
            ce = 1'b1; input_valid = 1'b1; first = 1'b1; last = 1'b1;
            features = {3{32'd999}};
            if (ready) fail("ready before recovery");
            @(posedge clk); #1;
            if (!ready || dut.flag_mac_valid || dut.reg_tags_first || dut.reg_tags_second || valid || commit)
                fail("dirty recovery accepted");
        end
    endtask
    initial begin
        // Cin=1，高通道全零；非对称K0~K8正权重直接给出独立标量期望。
        for (k=0;k<9;k=k+1) weights[k*32 +: 32] = k+1;
        for (m=0;m<4;m=m+1) begin
            mode=m;
            release_reset();
            first_result=m==0 ? 11 : (m==1 ? 8 : 6);
            // 结果已有效且后续列仍在途时暂停并异步清空。
            for (n=0;n<=first_result;n=n+1) begin
                @(negedge clk);
                input_valid=1'b1; first=1'b1; last=1'b1;
                row_last=m<2 && n%5==4;
                features={3{32'd1}}*(n+1);
                @(posedge clk); #1;
            end
            if (!valid || {three,two,one,zero}==480'd0) fail("reset occupancy missing");
            @(negedge clk); ce=1'b0;
            #2; rstn=1'b0;
            #1;
            if (ready || valid || commit || advance || snapshot!==1841'd0) fail("async clear before edge");
            async_reset_checks=async_reset_checks+1;
            release_reset();
            // 一行五列，数值期望仅由固定核和输入决定，不复写流水算法。
            for (n=0;n<16;n=n+1) begin
                @(negedge clk);
                input_valid=n<5; first=input_valid; last=input_valid;
                row_last=m<2 && n==4;
                features={3{32'd1}}*(n+1);
                if (n==first_result+1) begin
                    ce=1'b0; held=snapshot;
                    repeat (2) begin
                        @(posedge clk); #1;
                        if (ready || commit || advance || snapshot!==held) fail("full CU pause");
                        stalls=stalls+1;
                        @(negedge clk);
                    end
                    ce=1'b1;
                end
                @(posedge clk);
                if (commit!==(m<2 && n>=7 && n<=11) || advance!==(m<2 && n==11)) fail("cache event timing");
                #1;
                expected_valid=m==0 ? (n>=11 && n<=13) : (m==1 ? (n>=8 && n<=11) : (n>=6 && n<=10));
                if (valid!==expected_valid) fail("restart valid latency");
                if (valid) begin
                    if (m<2) begin
                        column_index=n-(m==0 ? 9 : 7);
                        expected=m==0 ? 45*column_index+6 : 12*column_index+7;
                        if (zero!==expected || {three,two,one}!==432'd0) fail("spatial scalar result");
                    end else begin
                        if (zero!==48'd0) fail("bypass zero output");
                        for (k=0;k<3;k=k+1) begin
                            expected=(n-5)*(1+3*k);
                            if (one[k*48 +: 48]!==expected) fail("O1 lane order");
                            expected=(n-5)*(2+3*k);
                            if (two[k*48 +: 48]!==expected) fail("O2 lane order");
                            expected=(n-5)*(3+3*k);
                            if (three[k*48 +: 48]!==expected) fail("O3 lane order");
                        end
                    end
                    completed=completed+1;
                end
            end
            @(negedge clk); ce=1'b0; #2; rstn=1'b0; #1;
        end
        if (async_reset_checks!=4 || completed!=17 || stalls!=8) fail("final counts");
        test_done=1'b1;
        $display("PASS B3 directed modes=4 async_reset_checks=4 restart_outputs=17 stall_clocks=8");
        $finish;
    end
    initial begin
        #20000; fail("watchdog");
    end
    `WIDTH_CU(dut)
endmodule
