`timescale 1ns/1ps
module tb_result_fifo_bram;
reg clk=0,rstn=1,valid=0,ready=0;
reg [63:0]data=0;
reg [3:0]mask=0;
reg [31:0]random_state=32'h20261015;
wire in_ready,out_valid,full,empty,old_in_ready,old_out_valid,old_full,old_empty;
wire [63:0]out_data,old_out_data;
wire [3:0]out_mask,old_out_mask;
wire [9:0]count,old_count;
integer cycles=0,checks=0,full_checks=0,replacements=0,simultaneous=0,reset_checks=0,index;
reg test_done=0,test_failed=0;
always #5 clk=~clk;
result_fifo dut(.i_clk(clk),.i_rstn(rstn),.i_in_valid(valid),.o_in_ready(in_ready),
 .i_in_data(data),.i_in_mask(mask),.o_out_valid(out_valid),.i_out_ready(ready),
 .o_out_data(out_data),.o_out_mask(out_mask),.o_full(full),.o_empty(empty),.o_count(count));
result_fifo_baseline original(.i_clk(clk),.i_rstn(rstn),.i_in_valid(valid),.o_in_ready(old_in_ready),
 .i_in_data(data),.i_in_mask(mask),.o_out_valid(old_out_valid),.i_out_ready(ready),
 .o_out_data(old_out_data),.o_out_mask(old_out_mask),.o_full(old_full),.o_empty(old_empty),.o_count(old_count));
task compare;
begin
 if({in_ready,out_valid,full,empty,count} !== {old_in_ready,old_out_valid,old_full,old_empty,old_count})
  $fatal(1,"FIFO handshake/count mismatch cycle=%0d",cycles);
 if(out_valid && {out_mask,out_data} !== {old_out_mask,old_out_data})
  $fatal(1,"FIFO head mismatch cycle=%0d count=%0d",cycles,count);
 checks=checks+1;
end
endtask
task tick;
input write_valid,read_ready;
begin
 @(negedge clk);valid=write_valid;ready=read_ready;
 data={32'hface1234,cycles[31:0]};mask=cycles[3:0];
 #1;compare;
 if(full && valid && ready)full_checks=full_checks+1;
 if(in_ready && valid && out_valid && ready)begin
  simultaneous=simultaneous+1;
  if(count==1)replacements=replacements+1;
 end
 @(posedge clk);cycles=cycles+1;#1;compare;
end
endtask
task reset_queue;
begin
 @(negedge clk);#2;rstn=0;#1;compare;
 if(count!==0 || in_ready!==0 || out_valid!==0)$fatal(1,"FIFO async reset mismatch");
 reset_checks=reset_checks+1;
 @(posedge clk);#1;compare;
 @(negedge clk);rstn=1;valid=0;ready=0;#1;compare;
end
endtask
initial begin
 reset_queue;
 repeat(515)tick(1,0);
 repeat(1030)tick(1,1);
 repeat(515)tick(0,1);
 tick(1,0);
 repeat(64)tick(1,1);
 tick(0,1);
 for(index=0;index<16000;index=index+1)begin
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  tick(random_state[0],random_state[1]);
  if(index==1000 || index==8000 || index==12000)reset_queue;
 end
 repeat(513)tick(0,1);
 if(full_checks<1 || replacements<64 || simultaneous<1000 || reset_checks!=4 || !empty)
  $fatal(1,"FIFO boundary coverage incomplete");
 test_done=1;
 $display("PASS E-J2 BRAM FIFO cycle equivalence: cycles=%0d checks=%0d replacements=%0d full=%0d",cycles,checks,replacements,full_checks);
 $finish;
end
endmodule
