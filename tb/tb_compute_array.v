`timescale 1ns / 1ps
`include "compute_array_count.vh"
// 12份实际CU串接CONCAT，原始结果与重排bundle同时自检。
module tb_compute_array;
    reg clk=1'b0;
    reg [9341:0] stimulus=9342'd0;
    reg [9341:0] vectors [0:`COMPUTE_ARRAY_CYCLES-1];
    wire in_ready;
    wire [7:0] cu_valid,commit,advance;
    wire [383:0] o_zero;
    wire [1151:0] o_one,o_two,o_three;
    wire bundle_valid;
    wire [3455:0] bundle_data;
    wire [71:0] lane_mask;
    reg recovered=1'b0;
    reg test_done=1'b0;
    reg test_failed=1'b0;
    reg signed [47:0] base_value;
    reg signed [47:0] expected_value;
    reg [479:0] cu_result;
    integer cycle,cu,lane;
    integer counts [0:3];
    integer trace_file;
    compute_array compute_array_Inst (
        .i_clk(clk),.i_rstn(stimulus[3554]),.i_ce(stimulus[3555]),.i_mode(stimulus[3553:3552]),
        .i_in_valid(stimulus[3556]),.i_first(stimulus[3557]),.i_last(stimulus[3558]),.i_row_last(stimulus[3559]),
        .i_feature_data(stimulus[95:0]),.i_weight_data(stimulus[3551:96]),
        .o_ready(in_ready),.o_cu_valid(cu_valid),.o_zero(o_zero),.o_one(o_one),
        .o_two(o_two),.o_three(o_three),.o_column_commit(commit),.o_row_advance(advance)
    );
    concat concat_Inst (
        .i_clk(clk),.i_rstn(stimulus[3554]),.i_ce(stimulus[3555]),
        .i_mode(stimulus[3553:3552]),.i_valid_lanes(stimulus[3566:3560]),.i_cu_valid(cu_valid),
        .i_zero(o_zero),.i_one(o_one),.i_two(o_two),.i_three(o_three),
        .o_bundle_valid(bundle_valid),.o_bundle_data(bundle_data),.o_lane_mask(lane_mask)
    );
    always #5 clk=~clk;
    initial begin
        for (lane=0;lane<4;lane=lane+1) counts[lane]=0;
        $readmemh("compute_array_vectors.mem",vectors);
        trace_file=$fopen("compute_array_trace.csv","w");
        if (trace_file==0) begin test_failed=1'b1;$display("FAIL trace open");$finish;end
        $fdisplay(trace_file,"fclk,mode,valid_lanes,bundle_valid,lane_mask,bundle_data");
        for (cycle=0;cycle<`COMPUTE_ARRAY_CYCLES;cycle=cycle+1) begin
            @(negedge clk);stimulus=vectors[cycle];
            @(posedge clk);
            if (commit !== {8{stimulus[3567]}} || advance !== {8{stimulus[3568]}} ||
                in_ready !== (stimulus[3554]&&stimulus[3555]&&recovered)) begin
                test_failed=1'b1;$display("FAIL B4 handshake cycle=%0d",cycle);$finish;
            end
            if (!stimulus[3554]) recovered=1'b0;
            else if (stimulus[3555]) recovered=1'b1;
            if (compute_array_Inst.compute_unit_first_Inst.o_ready !== in_ready) begin test_failed=1; $display("FAIL ready lockstep first");$finish;end
if (compute_array_Inst.compute_unit_second_Inst.o_ready !== in_ready) begin test_failed=1; $display("FAIL ready lockstep second");$finish;end
if (compute_array_Inst.compute_unit_third_Inst.o_ready !== in_ready) begin test_failed=1; $display("FAIL ready lockstep third");$finish;end
if (compute_array_Inst.compute_unit_fourth_Inst.o_ready !== in_ready) begin test_failed=1; $display("FAIL ready lockstep fourth");$finish;end
if (compute_array_Inst.compute_unit_fifth_Inst.o_ready !== in_ready) begin test_failed=1; $display("FAIL ready lockstep fifth");$finish;end
if (compute_array_Inst.compute_unit_sixth_Inst.o_ready !== in_ready) begin test_failed=1; $display("FAIL ready lockstep sixth");$finish;end
if (compute_array_Inst.compute_unit_seventh_Inst.o_ready !== in_ready) begin test_failed=1; $display("FAIL ready lockstep seventh");$finish;end
if (compute_array_Inst.compute_unit_eighth_Inst.o_ready !== in_ready) begin test_failed=1; $display("FAIL ready lockstep eighth");$finish;end
            #1;
            if (cu_valid !== {8{stimulus[3569]}} || bundle_valid !== stimulus[3569] ||
                lane_mask !== stimulus[9341:9234] || bundle_data !== stimulus[9233:4050]) begin
                test_failed=1'b1;$display("FAIL B4 bundle cycle=%0d mode=%0d",cycle,stimulus[3553:3552]);$finish;
            end
            for (cu=0;cu<8;cu=cu+1) begin
                cu_result={o_three[cu*144 +:144],o_two[cu*144 +:144],o_one[cu*144 +:144],o_zero[cu*48 +:48]};
                for (lane=0;lane<10;lane=lane+1) begin
                    base_value=stimulus[3570+lane*48 +:48];
                    expected_value=base_value*(cu+1);
                    if (cu_result[lane*48 +:48] !== expected_value) begin
                        test_failed=1'b1;$display("FAIL B4 raw CU=%0d lane=%0d cycle=%0d",cu,lane,cycle);$finish;
                    end
                end
            end
            if (stimulus[3554]&&stimulus[3555]&&bundle_valid)
                counts[stimulus[3553:3552]]=counts[stimulus[3553:3552]]+1;
            $fdisplay(trace_file,"%0d,%0d,%0d,%b,%h,%h",cycle,stimulus[3553:3552],stimulus[3566:3560],bundle_valid,lane_mask,bundle_data);
        end
        $fclose(trace_file);
        if (counts[0]!=6||counts[1]!=12||counts[2]!=3||counts[3]!=3) begin
            test_failed=1'b1;$display("FAIL B4 counts");
        end else begin
            test_done=1'b1;$display("PASS B4 cycles=262 lanes=12,108,5,101 raw_CUs_and_bundle=PASS");
        end
        $finish;
    end
    initial begin
        #20000;test_failed=1'b1;$display("FAIL B4 watchdog");$finish;
    end
endmodule
