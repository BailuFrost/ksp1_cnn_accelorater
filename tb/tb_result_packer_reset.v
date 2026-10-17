`timescale 1ns / 1ps
// 非沿/停钟复位、在途事务取消及首tile覆盖旧RAM的定向验证。
module tb_result_packer_reset;
  reg clk=0,clock_enable=1,rst_n=0,bundle_valid=0,out_ready=0;
  reg [3455:0] bundle_data=0,bias_data=0;
  reg [71:0] lane_mask=108'h1f;
  reg [1:0] mode=0;
  reg [7:0] spatial_index=0;
  reg first_tile=0,last_tile=0;
  reg [5:0] right_shift=0;
  reg relu=0;
  wire bundle_ready,out_valid,out_bypass,busy;
  wire [63:0] out_data;
  wire [3:0] out_mask;
  reg test_done=0,test_failed=0;
  integer scenario,lane,beats=0,reset_checks=0,restart_beats=0;
  reg [191:0] retained;
  result_packer dut (
    .i_clk(clk),.i_rstn(rst_n),.i_bundle_valid(bundle_valid),.o_bundle_ready(bundle_ready),
    .i_bundle_data(bundle_data),.i_bias_data(bias_data),.i_lane_mask(lane_mask),
    .i_mode(mode),.i_spatial_index(spatial_index),.i_first_tile(first_tile),.i_last_tile(last_tile),
    .i_right_shift(right_shift),.i_relu(relu),.o_out_valid(out_valid),.i_out_ready(out_ready),
    .o_out_data(out_data),.o_out_mask(out_mask),.o_out_bypass(out_bypass),.o_busy(busy)
  );
  always #5 if (clock_enable) clk=~clk;

  task fail;
    input [255:0] reason;
    begin test_failed=1;$display("FAIL B5 reset scenario=%0d: %0s",scenario,reason);$finish;end
  endtask
  task send;
    input first,last;
    input [47:0] value;
    begin
      @(negedge clk);
      for (lane=0;lane<72;lane=lane+1) begin
        bundle_data[lane*48 +:48]=value;
        bias_data[lane*48 +:48]=48'd3;
      end
      first_tile=first;last_tile=last;bundle_valid=1;
      @(posedge clk);if (!bundle_ready) fail("bundle was not accepted");
      @(negedge clk);bundle_valid=0;
    end
  endtask
  task drain_partial;
    begin
      while (busy) begin
        @(negedge clk);if (out_valid) fail("premature quantized output");
      end
    end
  endtask
  task assert_reset;
    begin
      retained=dut.tile_psum_buffer_Inst.reg_memory[0];
      // 距下一上升沿至少2ns；复位不能依赖时钟或ready。
      #2;rst_n=0;#1;
      if (busy!==0 || out_valid!==0 || bundle_ready!==0 || out_data!==0 || out_mask!==0)
        fail("async public outputs");
      if ((|{dut.flag_active,dut.flag_waiting,dut.reg_data,dut.reg_bias,dut.reg_mask,
             dut.reg_base_address,dut.cnt_quad,dut.flag_first,dut.flag_last,dut.out_bypass_o,
             dut.flag_relu,dut.reg_shift,dut.tile_psum_buffer_Inst.flag_pending,
             dut.tile_psum_buffer_Inst.out_valid_o,dut.tile_psum_buffer_Inst.reg_saved_address,
             dut.tile_psum_buffer_Inst.reg_saved_data,dut.tile_psum_buffer_Inst.reg_saved_mask,
             dut.tile_psum_buffer_Inst.flag_saved_first,dut.tile_psum_buffer_Inst.flag_saved_last,
             dut.tile_psum_buffer_Inst.out_data_o,dut.result_stage_Inst.out_valid_o,
             dut.result_stage_Inst.reg_rounded_first,dut.result_stage_Inst.reg_rounded_second,
             dut.result_stage_Inst.reg_rounded_third,dut.result_stage_Inst.reg_rounded_fourth,
             dut.result_stage_Inst.reg_shift,dut.result_stage_Inst.out_mask_o,
             dut.result_stage_Inst.flag_relu})!==1'b0) fail("async control snapshot");
      if (dut.tile_psum_buffer_Inst.reg_memory[0]!==retained) fail("RAM was reset");
      reset_checks=reset_checks+1;
      clock_enable=1;bundle_valid=0;out_ready=0;
      // 模拟上游已同步的复位释放，不增加本地同步器。
      @(posedge clk);rst_n<=1;
      @(negedge clk);
      if (busy || out_valid) fail("ghost response after reset");
    end
  endtask
  task restart;
    begin
      send(1,0,48'd30);drain_partial;
      send(0,1,48'd7);beats=0;out_ready=1;
      while (busy) begin
        @(posedge clk);
        if (out_valid) begin
          if (beats==0 && (out_mask!==4'hf || out_data!==64'h0028002800280028))
            fail("restart full beat");
          if (beats==1 && (out_mask!==4'h1 || out_data!==64'h0000000000000028))
            fail("restart masked beat");
          if (beats>1) fail("extra restart beat");
          beats=beats+1;
        end
        @(negedge clk);
      end
      if (beats!=2) fail("restart beat count");
      restart_beats=restart_beats+beats;out_ready=0;
    end
  endtask
  initial begin
    repeat(3) @(posedge clk);rst_n<=1;
    @(negedge clk);
    for (scenario=0;scenario<5;scenario=scenario+1) begin
      if (scenario==0 || scenario==4) begin
        send(1,1,48'd1000);
        while (!out_valid) @(negedge clk);
        if (scenario==4) clock_enable=0;
      end else begin
        send(1,0,48'd1000);
        if (scenario!=1) begin
          drain_partial;
          send(0,scenario==3,48'd2000);
        end
        if (scenario==3) begin
          while (!out_valid) @(negedge clk);
        end else begin
          while (!dut.tile_psum_buffer_Inst.flag_pending) @(negedge clk);
        end
      end
      assert_reset;restart;
    end
    // 非法多tile位置和空间模式高lane不得握手。
    spatial_index=196;first_tile=1;last_tile=0;#1;
    if (bundle_ready) fail("illegal spatial address");
    spatial_index=0;lane_mask=108'h1000;#1;
    if (bundle_ready) fail("illegal spatial lane");
    lane_mask=0;#1;if (bundle_ready) fail("empty bundle");
    test_done=1;
    $display("PASS B5 async reset checks=%0d restart_beats=%0d",reset_checks,restart_beats);
    $finish;
  end
  initial begin #100000;fail("watchdog");end
endmodule
