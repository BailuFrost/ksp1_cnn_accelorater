`timescale 1ns / 1ps
// B0 自检：固定黄金向量、气泡、暂停、非沿异步复位及同步释放。
module tb_packed_mac;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ce = 1'b0;
    reg in_valid = 1'b0;
    reg [31:0] feature_data = 32'd0;
    reg [31:0] weight_data = 32'd0;
    wire out_valid;
    wire signed [32:0] out_data;
    reg [96:0] vectors [0:263];
    reg signed [32:0] expected_input = 33'sd0;
    reg signed [32:0] expected_pending = 33'sd0;
    reg signed [32:0] expected_output = 33'sd0;
    reg pending_valid = 1'b0;
    reg expected_valid = 1'b0;
    reg test_done = 1'b0;
    reg test_failed = 1'b0;
    reg count_results = 1'b0;
    integer sent = 0;
    integer received = 0;
    integer cycles = 0;
    integer stalls = 0;
    integer bubbles = 0;
    integer async_reset_checks = 0;

    packed_mac packed_mac_Inst (
        .i_clk(clk), .i_rstn(rst_n), .i_ce(ce), .i_in_valid(in_valid),
        .i_feature_data(feature_data), .i_weight_data(weight_data),
        .o_out_valid(out_valid), .o_out_data(out_data)
    );

    always #5 clk = ~clk;

    // 从 Python 黄金值建立两级队列，同时检查无效拍和暂停拍的数据保持。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_pending = 33'sd0;
            expected_output = 33'sd0;
            pending_valid = 1'b0;
            expected_valid = 1'b0;
        end else if (ce) begin
            expected_output = expected_pending;
            expected_valid = pending_valid;
            expected_pending = expected_input;
            pending_valid = in_valid;
        end
        #1;
        if ((out_valid !== expected_valid) || (out_data !== expected_output)) begin
            test_failed = 1'b1;
            $display("FAIL cycle=%0d valid=%b/%b data=%h/%h", cycles,
                     out_valid, expected_valid, out_data, expected_output);
            $finish;
        end
        if (rst_n && ce && out_valid && count_results)
            received = received + 1;
    end

    initial begin
        $readmemh("packed_mac_vectors.mem", vectors);
        repeat (2) @(negedge clk);
        // 同时填满两个流水寄存器，然后 ce=0 时复位，验证复位优先。
        @(posedge clk); #2;
        // 抽象proc_sys_reset输出：上升沿触发后释放，留出模拟传播时间。
        rst_n = 1'b1;
        @(negedge clk);
        ce = 1'b1;
        in_valid = 1'b1;
        feature_data = vectors[2][96:65];
        weight_data = vectors[2][64:33];
        expected_input = vectors[2][32:0];
        repeat (2) @(negedge clk);
        ce = 1'b0;
        #2;
        rst_n = 1'b0;
        #1;
        if (clk!==1'b0 || out_valid!==1'b0 || out_data!==33'sd0 ||
            packed_mac_Inst.reg_product_low!==32'sd0 || packed_mac_Inst.reg_product_high!==32'sd0) begin
            test_failed=1'b1;$display("FAIL asynchronous reset before clock edge");$finish;
        end
        async_reset_checks=async_reset_checks+1;
        @(posedge clk); #2;
        rst_n = 1'b1;
        in_valid = 1'b0;
        repeat (2) @(negedge clk);
        count_results = 1'b1;
        while (received < 264) begin
            // 前八组连续输入，后续固定通两拍停三拍并插入 valid 气泡。
            ce = (cycles < 8) || ((cycles % 5) < 2);
            in_valid = (sent < 264) && ((cycles < 8) || ((cycles % 7) != 0));
            feature_data = vectors[sent % 264][96:65];
            weight_data = vectors[sent % 264][64:33];
            expected_input = vectors[sent % 264][32:0];
            if (ce && in_valid) sent = sent + 1;
            if (!ce) stalls = stalls + 1;
            if (ce && !in_valid) bubbles = bubbles + 1;
            cycles = cycles + 1;
            @(negedge clk);
        end
        // 排空之后继续推进，捕获重复输出或未排掉的有效标志。
        in_valid = 1'b0;
        ce = 1'b1;
        repeat (4) @(negedge clk);
        if ((sent != 264) || (received != 264) || (stalls == 0) || (bubbles == 0) || (async_reset_checks!=1)) begin
            test_failed = 1'b1;
            $display("FAIL sent=%0d received=%0d", sent, received);
        end else begin
            test_done = 1'b1;
            $display("PASS B0: directed=8 random=256 seed=0xB0 sent=%0d received=%0d stalls=%0d bubbles=%0d async_assert_sync_release=PASS reset_flush=PASS",
                     sent, received, stalls, bubbles);
        end
        $finish;
    end

    initial begin
        #20000;
        test_failed = 1'b1;
        $display("FAIL B0 watchdog timeout");
        $finish;
    end
endmodule
