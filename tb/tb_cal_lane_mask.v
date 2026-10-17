`timescale 1ns / 1ps

// 与原108位表达式逐项比较，覆盖全部7位lane编码，包括0和超108编码。
module tb_cal_lane_mask;
    reg clk=0;
    always #5 clk=~clk;
    integer index=0, checks=0, cycles=0;
    reg test_done=0, test_failed=0;
    reg [71:0]expected;
    wire [71:0]mask;
    cal_cmd dut(.i_clk(clk), .i_rstn(1'b0), .i_ce(1'b0), .o_lane_mask(mask));
    initial begin
        force dut.reg_lanes=index;
        for(index=0;index<128;index=index+1)begin
            expected=(108'd1 << index)-108'd1;
            #1;
            if(mask!==expected)begin
                test_failed=1;
                $fatal(1,"lane mask mismatch encoding=%0d got=%h expected=%h",index,mask,expected);
            end
            checks=checks+1;
            cycles=cycles+1;
        end
        test_done=1;
        $display("PASS E-J2 lane mask RTL equivalence: 128 encodings");
        $finish;
    end
endmodule
