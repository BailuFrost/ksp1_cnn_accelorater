`timescale 1ns / 1ps
// Python任意精度oracle覆盖全部shift/mask/ReLU及signed48边界。
module tb_result_stage;
  reg clk=0,rst_n=0,in_valid=0;
  reg [458:0] vectors [0:2047];
  reg [458:0] stimulus;
  wire [63:0] result_data;
  wire in_ready,out_valid;
  wire [3:0] out_mask;
  reg test_done=0,test_failed=0;
  integer item,cases=0;
  result_stage dut (
    .i_clk(clk),.i_rstn(rst_n),.i_in_valid(in_valid),.o_in_ready(in_ready),
    .i_sum_data(stimulus[191:0]),.i_bias_data(stimulus[383:192]),
    .i_lane_mask(stimulus[387:384]),.i_right_shift(stimulus[393:388]),
    .i_relu(stimulus[394]),.o_result_data(result_data),
    .o_out_valid(out_valid),.i_out_ready(1'b1),.o_out_mask(out_mask)
  );
  always #5 clk=~clk;
  initial begin
    $readmemh("result_stage_vectors.mem",vectors);
    repeat(2) @(posedge clk);rst_n<=1;
    for (item=0;item<2048;item=item+1) begin
      @(negedge clk);stimulus=vectors[item];in_valid=1;
      @(posedge clk);if (!in_ready) begin test_failed=1;$finish;end
      #1;
      if (!out_valid || out_mask!==stimulus[387:384] || result_data!==stimulus[458:395]) begin
        test_failed=1;
        $display("FAIL quantize case=%0d shift=%0d got=%h expected=%h",item,stimulus[393:388],result_data,stimulus[458:395]);
        $finish;
      end
      cases=cases+1;
    end
    test_done=1;$display("PASS B5 quantization cases=%0d",cases);$finish;
  end
endmodule
