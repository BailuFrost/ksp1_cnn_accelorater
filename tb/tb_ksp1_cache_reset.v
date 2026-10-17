`timescale 1ns / 1ps
`include "width_step1_checks.vh"
// 独立入口检查连续完整列、宽补码、级间暂停、非沿复位和任务重启。
module tb_ksp1_cache_reset;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    reg ce = 1'b0;
    reg column_valid = 1'b0;
    reg row_last = 1'b0;
    reg [143:0] column_data = 144'd0;
    wire ready, commit, advance, valid;
    wire signed [47:0] data;
    wire [431:0] snapshot;
    reg [927:0] held;
    reg test_done = 1'b0;
    reg test_failed = 1'b0;
    integer async_reset_checks = 0;
    integer completed = 0;
    integer stalls = 0;
    integer n, row;
    reg signed [47:0] scale, expected;
    ksp1_cache dut (
        .i_clk(clk), .i_rstn(rstn), .i_ce(ce),
        .i_column_valid(column_valid), .i_column_data(column_data), .i_row_last(row_last),
        .o_ready(ready), .o_column_commit(commit), .o_row_advance(advance),
        .o_valid(valid), .o_data(data)
    );
    assign snapshot = {{{6{dut.reg_cache_third_right[41]}}, dut.reg_cache_third_right},
        {{6{dut.reg_cache_third_middle[41]}}, dut.reg_cache_third_middle},
        {{6{dut.reg_cache_third_left[41]}}, dut.reg_cache_third_left},
        {{6{dut.reg_cache_second_right[41]}}, dut.reg_cache_second_right},
        {{6{dut.reg_cache_second_middle[41]}}, dut.reg_cache_second_middle},
        {{6{dut.reg_cache_second_left[41]}}, dut.reg_cache_second_left},
        {{6{dut.reg_cache_first_right[41]}}, dut.reg_cache_first_right},
        {{6{dut.reg_cache_first_middle[41]}}, dut.reg_cache_first_middle},
        {{6{dut.reg_cache_first_left[41]}}, dut.reg_cache_first_left}};
    always #5 clk = ~clk;

    task fail;
        input [255:0] reason;
        begin
            test_failed = 1'b1;
            $display("FAIL B2 directed %s n=%0d row=%0d data=%0d", reason, n, row, data);
            $finish;
        end
    endtask

    initial begin
        // 同域释放后首沿建立ready，该沿脏valid不能被接受。
        @(posedge clk); #2; rstn = 1'b1;
        @(negedge clk); ce = 1'b1; column_valid = 1'b1; column_data = {3{48'd999}};
        @(posedge clk); #1;
        if (!ready || commit || snapshot !== 432'd0) fail("recovery acceptance");
        // 五个连续完整列；第五项仍在流水时已有第一个非零结果。
        for (n = 0; n < 6; n = n + 1) begin
            @(negedge clk);
            column_valid = n < 5;
            row_last = n == 4;
            column_data[47:0] = 10*(n+1);
            column_data[95:48] = 100*(n+1);
            column_data[143:96] = 1000*(n+1);
            @(posedge clk); #1;
        end
        if (!valid || data !== 48'sd3210 || snapshot === 432'd0) fail("pre-reset occupancy");
        @(negedge clk); ce = 1'b0;
        #2; rstn = 1'b0;
        #1;
        if (ready || valid || commit || advance || data !== 48'sd0 || snapshot !== 432'd0 ||
            dut.reg_ingress !== 128'd0 || dut.flag_complete !== 2'd0 ||
            dut.reg_history !== 84'd0 || dut.reg_pair !== 43'd0 ||
            dut.reg_third !== 42'd0 || dut.reg_third_aligned !== 42'd0 ||
            dut.reg_slot !== 2'd0 || dut.reg_filled !== 2'd0) fail("async clear before edge");
        async_reset_checks = async_reset_checks + 1;
        @(posedge clk); #2; rstn = 1'b1;
        column_valid = 1'b0;
        @(posedge clk); #1;
        if (ready || commit || valid) fail("recovery while stalled");
        // 两行分别用正负合法42位列值（原极值超出1536乘积范围），不依靠列间空拍掩盖丢失或覆盖。
        for (n = 0; n < 14; n = n + 1) begin
            // n0~4正行、n5~9负行，无行间气泡，前行结果与下一行提交重叠。
            row = n < 5 ? 0 : 1;
            scale = row == 0 ? 48'sd34359738368 : -48'sd34359738368;
            @(negedge clk);
            ce = 1'b1;
            column_valid = n < 10;
            row_last = n == 4 || n == 9;
            column_data[47:0] = scale * (n % 5 + 1);
            column_data[95:48] = scale * (n % 5 + 11);
            column_data[143:96] = scale * (n % 5 + 21);
            if (n == 4 || n == 9) begin
                ce = 1'b0;
                held = {snapshot, dut.reg_ingress, dut.reg_history, dut.reg_pair,
                    dut.reg_third_aligned, dut.reg_third, dut.reg_position,
                    dut.flag_active, dut.flag_complete, valid, data};
                repeat (2) begin
                    @(posedge clk); #1;
                    if (commit || advance || ready || held !== {snapshot, dut.reg_ingress,
                        dut.reg_history, dut.reg_pair, dut.reg_third_aligned,
                        dut.reg_third, dut.reg_position, dut.flag_active,
                        dut.flag_complete, valid, data}) fail("pipeline stall");
                    stalls = stalls + 1;
                    @(negedge clk);
                end
                ce = 1'b1;
            end
            @(posedge clk);
            if (commit !== (n >= 1 && n <= 10) || advance !== (n == 5 || n == 10)) fail("commit or row timing");
            #1;
            if (valid !== ((n >= 5 && n <= 7) || (n >= 10 && n <= 12))) fail("result latency");
            if (valid) begin
                expected = (n < 10 ? 48'sd34359738368 : -48'sd34359738368) * (36 + 3*(n % 5));
                if (data !== expected) fail("signed wide sum");
                completed = completed + 1;
            end
        end
        if (completed != 6 || stalls != 4 || async_reset_checks != 1) fail("counts");
        test_done = 1'b1;
        $display("PASS B2 directed results=6 stalls=4 async_reset_checks=1 contiguous_legal_column_rows=2");
        $finish;
    end
    initial begin
        #10000; fail("watchdog");
    end
    `WIDTH_CACHE(dut,width_check)
endmodule
