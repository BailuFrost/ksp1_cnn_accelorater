`timescale 1ns / 1ps
// 预期失败测试：正常仿真不应静默接受非法MAC域、超长tile、窄写回溢出或非法列值。
module tb_width_reject_source;
    reg clk=0,rstn=0;
    always #5 clk=~clk;
    initial begin #2;rstn=1;#3000;$fatal(1,"MONITOR DID NOT REJECT");end
    width_column_check check(clk,rstn,1'b1,1'b1,1'b1,1'b0,1'b0,99'd4294967295,3'd0,3'd0,43'd0,42'd0,42'd0);
endmodule

module tb_width_reject_depth;
    reg clk=0,rstn=0;
    always #5 clk=~clk;
    initial begin #2;rstn=1;#3000;$fatal(1,"MONITOR DID NOT REJECT");end
    width_column_check check(clk,rstn,1'b1,1'b1,1'b1,1'b0,1'b0,99'd0,3'd0,3'd0,43'd0,42'd0,42'd0);
endmodule

module tb_width_reject_sum;
    reg clk=0,rstn=0;
    always #5 clk=~clk;
    initial begin #2;rstn=1;#3000;$fatal(1,"MONITOR DID NOT REJECT");end
    width_column_check check(clk,rstn,1'b1,1'b1,1'b1,1'b0,1'b0,99'd0,3'b100,3'd0,43'd2199023255552,42'd0,42'd0);
endmodule

module tb_width_reject_cache;
    reg clk=0,rstn=0;
    always #5 clk=~clk;
    initial begin #2;rstn=1;#3000;$fatal(1,"MONITOR DID NOT REJECT");end
    width_cache_check check(clk,rstn,1'b1,1'b1,1'b1,{48'sd0,48'sd0,48'sd2199023255552});
endmodule
