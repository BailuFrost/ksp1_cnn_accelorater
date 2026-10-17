`timescale 1ns / 1ps
// 合法来源、有效通道对计数及每个有截位风险的累加写回；不综合到硬件。
module width_column_check(input clk, rstn, ce, valid, ready, first, last,
    input [98:0] macs, input [2:0] tags, first_tags,
    input signed [42:0] sum_top, input signed [41:0] sum_middle, sum_bottom);
    integer pairs = 0;
    integer lane;
    reg signed [32:0] term;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) pairs = 0;
        else if (ce) begin
            if (valid && ready) begin
                if (first) pairs = 0;
                if (pairs >= 256) $fatal(1,"WIDTH illegal tile: more than 256 pairs");
                pairs = pairs + 1;
                for (lane=0; lane<3; lane=lane+1) begin
                    term = macs[lane*33 +:33];
                    if (term < -33'sd2147418112 || term > 33'sd2147483648)
                        $fatal(1,"WIDTH illegal signed16 MAC source");
                end
                if (last) pairs = 0;
            end
            if (tags[2] && !first_tags[2]) begin
                if (sum_top[42] !== sum_top[41] || sum_middle[41] !== sum_middle[40] ||
                    sum_bottom[41] !== sum_bottom[40]) $fatal(1,"WIDTH accumulator sign extension");
            end
        end
    end
endmodule

module width_cache_check(input clk, rstn, ce, valid, ready, input [143:0] columns);
    integer lane;
    reg signed [47:0] value;
    always @(posedge clk) begin
        if (rstn && ce && valid && ready) begin
            for (lane=0; lane<3; lane=lane+1) begin
                value = columns[lane*48 +:48];
                if (value[47:42] !== {6{value[41]}} ||
                    value < -48'sd1649217110016 || value > 48'sd1649267441664)
                    $fatal(1,"WIDTH illegal column source before signed42 write");
            end
        end
    end
endmodule

module width_acc_check(input clk, rstn, ce, valid, bypass_mode, small_mode,
    input [431:0] columns);
    integer lane;
    reg signed [47:0] value;
    always @(posedge clk) begin
        if (rstn && ce && valid) begin
            if (bypass_mode) begin
                for (lane=0; lane<9; lane=lane+1) begin
                    value = columns[lane*48 +:48];
                    if (value[47:41] !== {7{value[40]}})
                        $fatal(1,"WIDTH bypass lane before signed41 write");
                end
            end
            if (small_mode) begin
                for (lane=0; lane<2; lane=lane+1) begin
                    value = columns[lane*144 +:48];
                    if (value[47:42] !== {6{value[41]}})
                        $fatal(1,"WIDTH small column before signed42 write");
                end
            end
        end
    end
endmodule
