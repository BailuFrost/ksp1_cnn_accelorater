`timescale 1ns / 1ps
`include "result_count.vh"
module tb_result_packer;
    reg clk=1'b0,rst_n=1'b0,bundle_valid=1'b0,out_ready=1'b0;
    reg [12222:0] stimulus;
    reg [12222:0] vectors [0:`RESULT_BUNDLES-1];
    reg [3455:0] input_data,input_bias;
    wire bundle_ready,out_valid,out_bypass,busy;
    wire [63:0] out_data;
    wire [3:0] out_mask;
    reg test_done=1'b0,test_failed=1'b0;
    reg held=1'b0;
    reg [63:0] held_data;
    reg [3:0] held_mask;
    integer item,quad,beats,cycles,trace_file,expected_quads,lane,fill_cycles;
    reg [63:0] expected_data;
    reg [3:0] expected_mask;
    result_packer result_packer_Inst (
        .i_clk(clk),.i_rstn(rst_n),.i_bundle_valid(bundle_valid),.o_bundle_ready(bundle_ready),
        .i_bundle_data(input_data),.i_bias_data(input_bias),.i_lane_mask(stimulus[10475:10368]),
        .i_mode(stimulus[10477:10476]),.i_spatial_index(stimulus[10485:10478]),
        .i_first_tile(stimulus[10486]),.i_last_tile(stimulus[10487]),
        .i_right_shift(stimulus[10493:10488]),.i_relu(stimulus[10494]),
        .o_out_valid(out_valid),.i_out_ready(out_ready),.o_out_data(out_data),.o_out_mask(out_mask),
        .o_out_bypass(out_bypass),.o_busy(busy)
    );
    always #5 clk=~clk;
    initial begin
        cycles=0;beats=0;stimulus=0;input_data=0;input_bias=0;
        $readmemh("result_vectors.mem",vectors);
        trace_file=$fopen("result_trace.csv","w");
        if (!trace_file) begin test_failed=1'b1;$display("FAIL trace open");$finish;end
        $fdisplay(trace_file,"fclk,bundle,quad,mask,data");
        repeat(3) @(negedge clk);
        rst_n=1'b1;
        for (item=0;item<`RESULT_BUNDLES;item=item+1) begin
            stimulus=vectors[item];input_data=stimulus[5183:0];input_bias=stimulus[10367:5184];
            bundle_valid=1'b1;quad=0;expected_quads=0;held=1'b0;fill_cycles=0;
            for (lane=0;lane<18;lane=lane+1)
                if (|stimulus[10368+lane*4 +:4]) expected_quads=expected_quads+1;
            @(posedge clk);
            if (!bundle_ready) begin test_failed=1'b1;$display("FAIL bundle ready %0d",item);$finish;end
            @(negedge clk);
            bundle_valid=1'b0;input_data=~input_data;input_bias=~input_bias;
            while (busy) begin
                out_ready=(stimulus[10486] && stimulus[10487]) || (cycles%5<2);
                @(posedge clk);
                if (bundle_ready) begin test_failed=1'b1;$display("FAIL busy ready");$finish;end
                if (stimulus[10486] && stimulus[10487]) begin
                    if (!out_valid) begin
                        if (quad>0 || fill_cycles!=0) begin
                            test_failed=1'b1;$display("FAIL single tile serialization bubble");$finish;
                        end
                        fill_cycles=fill_cycles+1;
                    end else if (quad==0 && fill_cycles!=1) begin
                        test_failed=1'b1;$display("FAIL quantization fill latency");$finish;
                    end
                end
                if (held && (!out_valid || out_data!==held_data || out_mask!==held_mask)) begin
                    test_failed=1'b1;$display("FAIL stalled output changed");$finish;
                end
                held=out_valid && !out_ready;held_data=out_data;held_mask=out_mask;
                if (out_valid) begin
                    expected_data=stimulus[10495+quad*64 +:64];
                    expected_mask=stimulus[10368+quad*4 +:4];
                    if (!stimulus[10487] || out_data!==expected_data || out_mask!==expected_mask ||
                        out_bypass!==stimulus[10477]) begin
                        test_failed=1'b1;$display("FAIL B5 item=%0d quad=%0d got=%h expected=%h",item,quad,out_data,expected_data);$finish;
                    end
                    if (out_ready) begin
                        $fdisplay(trace_file,"%0d,%0d,%0d,%h,%h",cycles,item,quad,out_mask,out_data);
                        quad=quad+1;beats=beats+1;
                    end
                end
                cycles=cycles+1;
                @(negedge clk);
            end
            if ((stimulus[10487] && quad!=expected_quads) || (!stimulus[10487] && quad!=0)) begin
                test_failed=1'b1;$display("FAIL beat count item=%0d count=%0d expected=%0d",item,quad,expected_quads);$finish;
            end
        end
        $fclose(trace_file);
        if (beats!=`RESULT_BEATS) begin test_failed=1'b1;$display("FAIL total beats");end
        else begin test_done=1'b1;$display("PASS B5 bundles=%0d beats=%0d cycles=%0d",`RESULT_BUNDLES,beats,cycles);end
        $finish;
    end
    initial begin #1000000;test_failed=1'b1;$display("FAIL B5 watchdog");$finish;end
endmodule
