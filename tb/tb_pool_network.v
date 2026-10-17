`timescale 1ns/1ps
module tb_pool_network;
reg i_clk=0;
reg i_rstn=0;
reg i_ce=0;
reg [7:0]i_axi_awaddr=0;
reg i_axi_awvalid=0;
wire o_axi_awready;
reg [31:0]i_axi_wdata=0;
reg [3:0]i_axi_wstrb=0;
reg i_axi_wvalid=0;
wire o_axi_wready;
wire [1:0]o_axi_bresp;
wire o_axi_bvalid;
reg i_axi_bready=0;
reg [7:0]i_axi_araddr=0;
reg i_axi_arvalid=0;
wire o_axi_arready;
wire [31:0]o_axi_rdata;
wire [1:0]o_axi_rresp;
wire o_axi_rvalid;
reg i_axi_rready=0;
reg i_gp_reset_done=0;
reg i_hp_reset_done=0;
wire o_gp_reset_req;
wire o_hp_reset_req;
wire o_irq;
wire o_busy;
wire o_done;
wire o_error;
wire [31:0]o_error_code;
wire [7:0]o_current_layer;
wire [63:0]o_cycles;
wire o_layer_done;
wire o_gp_read_cmd_valid;
reg i_gp_read_cmd_ready=0;
wire [71:0]o_gp_read_cmd_data;
reg i_gp_read_data_valid=0;
wire o_gp_read_data_ready;
reg [31:0]i_gp_read_data=0;
reg [3:0]i_gp_read_keep=0;
reg i_gp_read_last=0;
reg i_gp_read_status_valid=0;
wire o_gp_read_status_ready;
reg [7:0]i_gp_read_status=0;
wire o_gp_write_cmd_valid;
reg i_gp_write_cmd_ready=0;
wire [71:0]o_gp_write_cmd_data;
wire o_gp_write_data_valid;
reg i_gp_write_data_ready=0;
wire [31:0]o_gp_write_data;
wire [3:0]o_gp_write_keep;
wire o_gp_write_last;
reg i_gp_write_status_valid=0;
wire o_gp_write_status_ready;
reg [7:0]i_gp_write_status=0;
wire o_feature_cmd_valid;
reg i_feature_cmd_ready=0;
wire [71:0]o_feature_cmd_data;
reg i_feature_data_valid=0;
wire o_feature_data_ready;
reg [63:0]i_feature_data=0;
reg [7:0]i_feature_keep=0;
reg i_feature_last=0;
reg i_feature_status_valid=0;
wire o_feature_status_ready;
reg [7:0]i_feature_status=0;
wire o_weight_cmd_valid;
reg i_weight_cmd_ready=0;
wire [71:0]o_weight_cmd_data;
reg i_weight_data_valid=0;
wire o_weight_data_ready;
reg [63:0]i_weight_data=0;
reg [7:0]i_weight_keep=0;
reg i_weight_last=0;
reg i_weight_status_valid=0;
wire o_weight_status_ready;
reg [7:0]i_weight_status=0;
wire o_output_cmd_valid;
reg i_output_cmd_ready=0;
wire [71:0]o_output_cmd_data;
wire o_output_data_valid;
reg i_output_data_ready=0;
wire [63:0]o_output_data;
wire [7:0]o_output_keep;
wire o_output_last;
reg i_output_status_valid=0;
wire o_output_status_ready;
reg [7:0]i_output_status=0;
cnn_accelerator_top top(
.i_clk(i_clk),
.i_rstn(i_rstn),
.i_ce(i_ce),
.i_axi_awaddr(i_axi_awaddr),
.i_axi_awvalid(i_axi_awvalid),
.o_axi_awready(o_axi_awready),
.i_axi_wdata(i_axi_wdata),
.i_axi_wstrb(i_axi_wstrb),
.i_axi_wvalid(i_axi_wvalid),
.o_axi_wready(o_axi_wready),
.o_axi_bresp(o_axi_bresp),
.o_axi_bvalid(o_axi_bvalid),
.i_axi_bready(i_axi_bready),
.i_axi_araddr(i_axi_araddr),
.i_axi_arvalid(i_axi_arvalid),
.o_axi_arready(o_axi_arready),
.o_axi_rdata(o_axi_rdata),
.o_axi_rresp(o_axi_rresp),
.o_axi_rvalid(o_axi_rvalid),
.i_axi_rready(i_axi_rready),
.i_gp_reset_done(i_gp_reset_done),
.i_hp_reset_done(i_hp_reset_done),
.o_gp_reset_req(o_gp_reset_req),
.o_hp_reset_req(o_hp_reset_req),
.o_irq(o_irq),
.o_busy(o_busy),
.o_done(o_done),
.o_error(o_error),
.o_error_code(o_error_code),
.o_current_layer(o_current_layer),
.o_cycles(o_cycles),
.o_layer_done(o_layer_done),
.o_gp_read_cmd_valid(o_gp_read_cmd_valid),
.i_gp_read_cmd_ready(i_gp_read_cmd_ready),
.o_gp_read_cmd_data(o_gp_read_cmd_data),
.i_gp_read_data_valid(i_gp_read_data_valid),
.o_gp_read_data_ready(o_gp_read_data_ready),
.i_gp_read_data(i_gp_read_data),
.i_gp_read_keep(i_gp_read_keep),
.i_gp_read_last(i_gp_read_last),
.i_gp_read_status_valid(i_gp_read_status_valid),
.o_gp_read_status_ready(o_gp_read_status_ready),
.i_gp_read_status(i_gp_read_status),
.o_gp_write_cmd_valid(o_gp_write_cmd_valid),
.i_gp_write_cmd_ready(i_gp_write_cmd_ready),
.o_gp_write_cmd_data(o_gp_write_cmd_data),
.o_gp_write_data_valid(o_gp_write_data_valid),
.i_gp_write_data_ready(i_gp_write_data_ready),
.o_gp_write_data(o_gp_write_data),
.o_gp_write_keep(o_gp_write_keep),
.o_gp_write_last(o_gp_write_last),
.i_gp_write_status_valid(i_gp_write_status_valid),
.o_gp_write_status_ready(o_gp_write_status_ready),
.i_gp_write_status(i_gp_write_status),
.o_feature_cmd_valid(o_feature_cmd_valid),
.i_feature_cmd_ready(i_feature_cmd_ready),
.o_feature_cmd_data(o_feature_cmd_data),
.i_feature_data_valid(i_feature_data_valid),
.o_feature_data_ready(o_feature_data_ready),
.i_feature_data(i_feature_data),
.i_feature_keep(i_feature_keep),
.i_feature_last(i_feature_last),
.i_feature_status_valid(i_feature_status_valid),
.o_feature_status_ready(o_feature_status_ready),
.i_feature_status(i_feature_status),
.o_weight_cmd_valid(o_weight_cmd_valid),
.i_weight_cmd_ready(i_weight_cmd_ready),
.o_weight_cmd_data(o_weight_cmd_data),
.i_weight_data_valid(i_weight_data_valid),
.o_weight_data_ready(o_weight_data_ready),
.i_weight_data(i_weight_data),
.i_weight_keep(i_weight_keep),
.i_weight_last(i_weight_last),
.i_weight_status_valid(i_weight_status_valid),
.o_weight_status_ready(o_weight_status_ready),
.i_weight_status(i_weight_status),
.o_output_cmd_valid(o_output_cmd_valid),
.i_output_cmd_ready(i_output_cmd_ready),
.o_output_cmd_data(o_output_cmd_data),
.o_output_data_valid(o_output_data_valid),
.i_output_data_ready(i_output_data_ready),
.o_output_data(o_output_data),
.o_output_keep(o_output_keep),
.o_output_last(o_output_last),
.i_output_status_valid(i_output_status_valid),
.o_output_status_ready(o_output_status_ready),
.i_output_status(i_output_status)
);

always #5 i_clk=~i_clk;

integer case_id=0,fault=0,pool_read_index=0,full_checks=0,completed_cases=0;
integer metadata[0:7];
reg [31:0]expected_reads[0:8191];
reg stall_output=0;

reg test_done=0,test_failed=0,verify_network=1,inject_weight_error=0;
integer cycles=0,checks=0,jobs=0,reset_checks=0,error_checks=0;
integer launch_pause=0,start_pause_checks=0;
reg arm_launch_pause=0;
integer layers_started=0,layers_checked=0,modes_seen=0,commands_seen=0,beats_seen=0,statuses_seen=0;
integer pairs_seen=0,bundles_seen=0,gp_reads=0,gp_read_words=0,gp_writes=0,gp_write_words=0,gp_write_statuses=0;
integer feature_commands=0,weight_commands=0;
integer lc=0,lb=0,le=0,lr=0,position=0,n=0,k=0,stage=0;
reg [31:0]first_address=0,last_command=0,last_address=0,checksum=0,read_value;
reg [31:0]gp_memory[0:79],runtime_memory[0:3];
reg [63:0]weight_memory[0:55591],feature_a[0:65535],feature_b[0:65535],final_results[0:1];
reg [511:0]configs[0:3];
reg [71:0]expected_commands[0:4095],expected_beats[0:4095];
reg [223:0]layer_checks[0:3];
reg gp_active=0,gp_write_active=0,f_active=0,w_active=0,out_active=0;
reg gp_accepted=0,f_accepted=0,w_accepted=0;
integer gp_position=0,gp_words=0,gp_delay=0,gp_write_position=0,gp_write_delay=0;
integer f_position=0,f_beats=0,f_delay=0,w_position=0,w_beats=0,w_delay=0;
integer out_position=0,out_beats=0,out_delay=0,gp_reset_count=0,hp_reset_count=0;
reg [31:0]gp_address=0,f_address=0,w_address=0,out_address=0;
reg [31:0]beat_address;
reg [63:0]held_output;
reg held_valid=0;
integer trace;
integer progress;

function [63:0]feature_word;
 input [31:0]address;
 begin
  if(address>=32'h05000000 && address<32'h05080000)feature_word=feature_a[(address-32'h05000000)/8];
  else if(address>=32'h0b000000 && address<32'h0b080000)feature_word=feature_b[(address-32'h0b000000)/8];
  else begin feature_word=0;$fatal(1,"F-J0 feature DDR range %h",address);end
 end
endfunction

// Independent AW and W acceptance; alternate order and hold both B and R responses under backpressure.
task write_reg;
 input [7:0]address;input [31:0]value;input [3:0]strobe;input [1:0]response;input integer order;
 begin
  if(address==0 && value[0] && response==0)wait(top.flag_ps_ready && cycles%97<80);
  @(negedge i_clk);i_axi_awaddr=address;i_axi_wdata=value;i_axi_wstrb=strobe;i_axi_bready=0;
  if(order==0)begin
   i_axi_awvalid=1;do @(posedge i_clk);while(!o_axi_awready);@(negedge i_clk);i_axi_awvalid=0;
   repeat(3)@(negedge i_clk);i_axi_wvalid=1;do @(posedge i_clk);while(!o_axi_wready);@(negedge i_clk);i_axi_wvalid=0;
  end else begin
   i_axi_wvalid=1;do @(posedge i_clk);while(!o_axi_wready);@(negedge i_clk);i_axi_wvalid=0;
   repeat(2)@(negedge i_clk);i_axi_awvalid=1;do @(posedge i_clk);while(!o_axi_awready);@(negedge i_clk);i_axi_awvalid=0;
  end
  wait(o_axi_bvalid);repeat(4)begin @(negedge i_clk);if(!o_axi_bvalid || o_axi_bresp!==response)$fatal(1,"F-J0 B response address=%h got=%b expected=%b",address,o_axi_bresp,response);end
  i_axi_bready=1;@(posedge i_clk);@(negedge i_clk);i_axi_bready=0;checks=checks+1;
 end
endtask
task read_reg;
 input [7:0]address;input [1:0]response;output [31:0]value;
 reg [31:0]held;
 begin
  @(negedge i_clk);i_axi_araddr=address;i_axi_arvalid=1;i_axi_rready=0;
  do @(posedge i_clk);while(!o_axi_arready);@(negedge i_clk);i_axi_arvalid=0;
  wait(o_axi_rvalid);held=o_axi_rdata;
  repeat(5)begin @(negedge i_clk);if(!o_axi_rvalid || o_axi_rresp!==response || o_axi_rdata!==held)$fatal(1,"F-J0 R hold/response");end
  value=held;i_axi_rready=1;@(posedge i_clk);@(negedge i_clk);i_axi_rready=0;checks=checks+1;
 end
endtask
task init_job;
 begin
  @(negedge i_clk);
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/inputs.mem",case_id),feature_a,0,metadata[3]-1);
  pool_read_index=0;
  layers_started=0;layers_checked=0;modes_seen=0;commands_seen=0;beats_seen=0;statuses_seen=0;pairs_seen=0;bundles_seen=0;
  gp_reads=0;gp_read_words=0;gp_writes=0;gp_write_words=0;gp_write_statuses=0;
  feature_commands=0;weight_commands=0;
  lc=0;lb=0;le=0;lr=0;position=0;checksum=0;first_address=0;last_command=0;last_address=0;
 end
endtask
task reset_job;
 begin
  write_reg(0,6,1,0,1);
  if(o_gp_reset_req || o_hp_reset_req)begin
   if(!o_busy)$fatal(1,"F-J0 reset must be visible while DMA cancelling");
   wait(!o_gp_reset_req && !o_hp_reset_req);
  end
  // B channel stays live even though the datapath is reset. Both external acknowledgements are delayed.
  // After a fault, both DMA engines may already be cancelled before software consumes BVALID.
  repeat(5)@(negedge i_clk);
  if(!top.flag_core_rstn || !top.flag_spatial_empty || !top.flag_bypass_empty || o_error || o_done)$fatal(1,"F-J0 shared reset isolation");
  reset_checks=reset_checks+1;
 end
endtask
// Read-side BFMs obey ready/valid stability. Fixed gaps exercise independent GP/HP transactions and CE pauses.
always@(negedge i_clk)begin
 i_ce=cycles%97<92;
 if(arm_launch_pause && top.flag_ps_start)begin launch_pause=4;arm_launch_pause=0;start_pause_checks=start_pause_checks+1;end
 if(launch_pause>0)begin i_ce=0;launch_pause=launch_pause-1;end
 i_gp_read_cmd_ready=!o_gp_reset_req && !gp_active && !i_gp_read_status_valid && gp_delay==0 && cycles%5!=1;
 if(!i_gp_read_data_valid || gp_accepted)begin
  i_gp_read_data_valid=!o_gp_reset_req && gp_active && cycles%7!=2;
  i_gp_read_data=gp_memory[(gp_address-32'h04000000)/4+gp_position];
  i_gp_read_keep=15;i_gp_read_last=gp_position==gp_words-1;
 end
 i_gp_write_cmd_ready=!o_gp_reset_req && !gp_write_active && cycles%7!=2;
 i_gp_write_data_ready=!o_gp_reset_req && cycles%9<5;
 i_feature_cmd_ready=!o_hp_reset_req && !f_active && f_delay==0 && !i_feature_status_valid && cycles%3!=1;
 i_weight_cmd_ready=!o_hp_reset_req && !w_active && w_delay==0 && !i_weight_status_valid && cycles%5!=2;
 if(!i_feature_data_valid || f_accepted)begin
  i_feature_data_valid=!o_hp_reset_req && f_active && cycles%4!=1;
  if(f_active)i_feature_data=feature_word(f_address+f_position*8);
  i_feature_keep=fault==2 ? 8'h7f : 255;i_feature_last=fault==3 ? 0 : f_position==f_beats-1;
 end
 if(!i_weight_data_valid || w_accepted)begin
  i_weight_data_valid=!o_hp_reset_req && w_active && cycles%7!=3;
  if(w_active)i_weight_data=weight_memory[(w_address-32'h12000000)/8+w_position];
  i_weight_keep=255;i_weight_last=w_position==w_beats-1;
 end
 i_output_cmd_ready=!stall_output && !o_hp_reset_req && !out_active && out_delay==0 && !i_output_status_valid && cycles%7!=2;
 i_output_data_ready=!o_hp_reset_req && cycles%11<7;
 if(o_gp_reset_req)i_gp_read_data_valid=0;
 if(o_hp_reset_req)begin i_feature_data_valid=0;i_weight_data_valid=0;end
end

always@(posedge i_clk)begin
 gp_accepted=i_gp_read_data_valid && o_gp_read_data_ready;
 f_accepted=i_feature_data_valid && o_feature_data_ready;
 w_accepted=i_weight_data_valid && o_weight_data_ready;
 cycles=cycles+1;
 if(stall_output && top.cnt_spatial==512)begin
  full_checks=full_checks+1;
  if(full_checks==30)stall_output=0;
 end
 if(stall_output && o_layer_done)$fatal(1,"completion while HP2 stalled");
 if(out_delay>0 && o_layer_done)$fatal(1,"completion before final write status");
 if(cycles%10000==0)begin $fwrite(progress,"cycle=%0d stage=%0d jobs=%0d layer=%0d busy=%b error=%h reset=%b%b ack=%b%b\n",cycles,stage,jobs,o_current_layer,o_busy,o_error_code,o_gp_reset_req,o_hp_reset_req,i_gp_reset_done,i_hp_reset_done);$fflush(progress);end
 if(cycles>2500000)$fatal(1,"F-J0 timeout stage=%0d busy=%b error=%h",stage,o_busy,o_error_code);
 // Acknowledgements model completed external cancellation, independently delayed by 8 and 13 FCLKs.
 if(!i_rstn)begin i_gp_reset_done<=0;i_hp_reset_done<=0;gp_reset_count<=0;hp_reset_count<=0;end
 else begin
  if(o_gp_reset_req)begin
   if(gp_reset_count<8)begin gp_reset_count<=gp_reset_count+1;i_gp_reset_done<=0;end
   else i_gp_reset_done<=1;
  end else gp_reset_count<=0;
  if(o_hp_reset_req)begin
   if(hp_reset_count<13)begin hp_reset_count<=hp_reset_count+1;i_hp_reset_done<=0;end
   else i_hp_reset_done<=1;
  end else hp_reset_count<=0;
 end
 if(!i_rstn || o_gp_reset_req)begin
  gp_active<=0;gp_write_active<=0;gp_delay<=0;gp_write_delay<=0;
  i_gp_read_status_valid<=0;i_gp_write_status_valid<=0;gp_write_position<=0;
 end else begin
  if(o_gp_read_cmd_valid && i_gp_read_cmd_ready)begin
   if(o_gp_read_cmd_data[71:64]!=0 || o_gp_read_cmd_data[31:23]!=9'h081 || o_gp_read_cmd_data[63:32]<32'h04000000 || o_gp_read_cmd_data[63:32]+o_gp_read_cmd_data[22:0]>32'h04000140)$fatal(1,"F-J0 GP command range");
   gp_active<=1;gp_address<=o_gp_read_cmd_data[63:32];gp_words<=o_gp_read_cmd_data[22:0]/4;gp_position<=0;gp_reads=gp_reads+1;
  end
  if(i_gp_read_data_valid && o_gp_read_data_ready)begin
   gp_position<=gp_position+1;gp_read_words=gp_read_words+1;
   if(i_gp_read_last)begin gp_active<=0;gp_delay<=4;end
  end
  if(gp_delay>0)begin gp_delay<=gp_delay-1;if(gp_delay==1)begin i_gp_read_status<=8'h80;i_gp_read_status_valid<=1;end end
  if(i_gp_read_status_valid && o_gp_read_status_ready)i_gp_read_status_valid<=0;
  if(o_gp_write_cmd_valid && i_gp_write_cmd_ready)begin
   if(o_gp_write_cmd_data!==72'h00041fffc040800010)$fatal(1,"F-J0 runtime command");
   gp_write_active<=1;gp_write_position<=0;gp_writes=gp_writes+1;
  end
  if(o_gp_write_data_valid && i_gp_write_data_ready)begin
   if(!gp_write_active || o_gp_write_keep!=15 || o_gp_write_last!==(gp_write_position==3))$fatal(1,"F-J0 runtime framing");
   runtime_memory[gp_write_position]=o_gp_write_data;gp_write_position<=gp_write_position+1;gp_write_words=gp_write_words+1;
   if(o_gp_write_last)gp_write_delay<=19;
  end
  if(gp_write_delay>0)begin gp_write_delay<=gp_write_delay-1;if(gp_write_delay==1)begin i_gp_write_status<=8'h80;i_gp_write_status_valid<=1;end end
  if(i_gp_write_status_valid && o_gp_write_status_ready)begin i_gp_write_status_valid<=0;gp_write_active<=0;gp_write_statuses=gp_write_statuses+1;end
  if(o_done && (gp_write_statuses!=1 || runtime_memory[3]!=1 || runtime_memory[2]!=metadata[0]-1 || {runtime_memory[1],runtime_memory[0]}!==o_cycles))$fatal(1,"F-J0 completion before successful runtime commit");
 end
 if(!i_rstn || o_hp_reset_req)begin
  f_active<=0;w_active<=0;out_active<=0;f_delay<=0;w_delay<=0;out_delay<=0;
  i_feature_status_valid<=0;i_weight_status_valid<=0;i_output_status_valid<=0;held_valid<=0;
 end else begin
  if(o_feature_cmd_valid && i_feature_cmd_ready)begin
   if(top.flag_pool)begin
    if(o_feature_cmd_data[22:0]!=8 || o_feature_cmd_data[63:32]!==expected_reads[pool_read_index])$fatal(1,"pool read address index=%0d got=%h expected=%h",pool_read_index,o_feature_cmd_data[63:32],expected_reads[pool_read_index]);
    pool_read_index=pool_read_index+1;
   end
   feature_commands=feature_commands+1;
   if(o_feature_cmd_data[71:64]!=0 || o_feature_cmd_data[31:23]!=9'h081 || o_feature_cmd_data[2:0]!=0)$fatal(1,"F-J0 feature framing");
   f_address<=o_feature_cmd_data[63:32];f_beats<=o_feature_cmd_data[22:0]/8;f_position<=0;f_active<=1;
   if(fault==4)begin i_feature_status<=8'h80;i_feature_status_valid<=1;end
  end
  if(o_weight_cmd_valid && i_weight_cmd_ready)begin
   weight_commands=weight_commands+1;
   if(o_weight_cmd_data[63:32]<32'h12000000 || o_weight_cmd_data[63:32]+o_weight_cmd_data[22:0]>32'h12048640 || o_weight_cmd_data[2:0]!=0)$fatal(1,"F-J0 static weight file range %h",o_weight_cmd_data);
   w_address<=o_weight_cmd_data[63:32];w_beats<=o_weight_cmd_data[22:0]/8;w_position<=0;w_active<=1;
  end
  if(i_feature_data_valid && o_feature_data_ready)begin f_position<=f_position+1;if(i_feature_last)begin f_active<=0;f_delay<=4;end end
  if(i_weight_data_valid && o_weight_data_ready)begin w_position<=w_position+1;if(i_weight_last)begin w_active<=0;w_delay<=6;end end
  if(f_delay>0)begin f_delay<=f_delay-1;if(f_delay==1)begin i_feature_status<=fault==1 ? 8'h10 : 8'h80;i_feature_status_valid<=1;end end
  if(w_delay>0)begin w_delay<=w_delay-1;if(w_delay==1)begin i_weight_status<=inject_weight_error ? 8'h10 : 8'h80;i_weight_status_valid<=1;end end
  if(i_feature_status_valid && o_feature_status_ready)i_feature_status_valid<=0;
  if(i_weight_status_valid && o_weight_status_ready)i_weight_status_valid<=0;
  if(o_output_cmd_valid && i_output_cmd_ready)begin
   if(verify_network && o_output_cmd_data!==expected_commands[commands_seen])$fatal(1,"F-J0 command %0d got=%h expected=%h",commands_seen,o_output_cmd_data,expected_commands[commands_seen]);
   if(lc==0)first_address=o_output_cmd_data[63:32];last_command=o_output_cmd_data[63:32];lc=lc+1;commands_seen=commands_seen+1;
   out_active<=1;out_address<=o_output_cmd_data[63:32];out_beats<=o_output_cmd_data[22:0]/8;out_position<=0;
  end
  if(held_valid && (!o_output_data_valid || o_output_data!==held_output))$fatal(1,"F-J0 output data changed under backpressure");
  held_valid<=o_output_data_valid && !i_output_data_ready;held_output<=o_output_data;
  if(o_output_data_valid && i_output_data_ready)begin
   if(!out_active || o_output_keep!=255 || o_output_last!==(out_position==out_beats-1))$fatal(1,"F-J0 output framing");
   if(verify_network && o_output_data!==expected_beats[beats_seen][63:0])$fatal(1,"F-J0 output beat=%0d got=%h expected=%h",beats_seen,o_output_data,expected_beats[beats_seen][63:0]);
   beat_address=out_address+out_position*8;last_address=beat_address;
   if(beat_address>=32'h0b000000 && beat_address<32'h0b080000)feature_b[(beat_address-32'h0b000000)/8]=o_output_data;
   else if(beat_address>=32'h05000000 && beat_address<32'h05080000)feature_a[(beat_address-32'h05000000)/8]=o_output_data;
   else if(beat_address>=32'h04200000 && beat_address<32'h04200010)final_results[(beat_address-32'h04200000)/8]=o_output_data;
   else $fatal(1,"F-J0 output DDR range");
   for(k=0;k<4;k=k+1)begin checksum=checksum+(position+1)*o_output_data[k*16+:16];position=position+1;end
   lb=lb+1;beats_seen=beats_seen+1;out_position<=out_position+1;
   if(o_output_last)out_delay<=41;
  end
  if(out_delay>0)begin out_delay<=out_delay-1;if(out_delay==1)begin i_output_status<=8'h80;i_output_status_valid<=1;end end
  if(i_output_status_valid && o_output_status_ready)begin i_output_status_valid<=0;out_active<=0;statuses_seen=statuses_seen+1;lr=lr+1;end
 end
 if(i_rstn && !o_hp_reset_req)begin
  if(top.dist_layer_start!=0)begin
   if(verify_network && (top.dist_layer_start!=15 || {top.extension,top.base_instruction}!==configs[layers_started]))$fatal(1,"F-J0 layer config/start %0d",layers_started);
   layers_started=layers_started+1;modes_seen=modes_seen|(1<<top.base_instruction[197:196]);
  end
  if(top.flag_pair_valid && top.flag_array_ready)pairs_seen=pairs_seen+1;
  if(top.flag_bundle_valid && top.flag_bundle_ready)bundles_seen=bundles_seen+1;
  if(top.flag_spatial_valid && top.flag_output_spatial_ready)for(k=0;k<4;k=k+1)le=le+top.spatial_mask[k];
  if(top.flag_bypass_valid && top.flag_output_bypass_ready)for(k=0;k<4;k=k+1)le=le+top.bypass_mask[k];
  if(o_layer_done && verify_network)begin
   if({checksum,last_address,last_command,first_address,lb[31:0],lc[31:0],le[31:0]}!==layer_checks[layers_checked] || lr!=lc)$fatal(1,"F-J0 layer check %0d checksum=%0d addresses=%h/%h/%h counts=%0d/%0d/%0d response=%0d expected=%h",layers_checked,checksum,first_address,last_command,last_address,le,lc,lb,lr,layer_checks[layers_checked]);
   $fwrite(trace,"%0d,%0d,%0d,%0d,%0d,%h,%h,%h,%0d\n",jobs,layers_checked,le,lc,lb,first_address,last_command,last_address,checksum);
   $fflush(trace);
   layers_checked=layers_checked+1;lc=0;lb=0;le=0;lr=0;checksum=0;position=0;
  end
 end
end

task load_case;
 input integer selected;
 begin
  case_id=selected;
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/meta.mem",case_id),metadata);
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/gp.mem",case_id),gp_memory,0,metadata[7]-1);
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/weights.mem",case_id),weight_memory,0,metadata[4]-1);
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/configs.mem",case_id),configs,0,metadata[0]-1);
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/commands.mem",case_id),expected_commands,0,metadata[1]-1);
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/beats.mem",case_id),expected_beats,0,metadata[2]-1);
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/checks.mem",case_id),layer_checks,0,metadata[0]-1);
  $readmemh($sformatf("E:/Loongson_SoC/CNN/xc7z020_cnn_accelerator/reports/f_j0/fixtures/%0d/reads.mem",case_id),expected_reads,0,metadata[6]-1);
  write_reg(32,metadata[5],15,0,0);
 end
endtask
task run_success;
 begin
  verify_network=1;init_job();write_reg(0,5,1,0,0);wait(o_done);@(negedge i_clk);
  if(o_error || layers_checked!=metadata[0] || layers_started!=metadata[0] || commands_seen!=metadata[1] || beats_seen!=metadata[2] || statuses_seen!=metadata[1] || pool_read_index!=metadata[6] || gp_write_statuses!=1)$fatal(1,"pool job totals case=%0d layers=%0d cmd/beat/status=%0d/%0d/%0d reads=%0d",case_id,layers_checked,commands_seen,beats_seen,statuses_seen,pool_read_index);
  if(case_id!=6 && weight_commands!=0)$fatal(1,"pool requested weights");
  jobs=jobs+1;completed_cases=completed_cases+1;
  $display("PASS F-J0 case=%0d layers=%0d HP0_pool=%0d HP2=%0d beats=%0d",case_id,layers_checked,pool_read_index,commands_seen,beats_seen);
 end
endtask
initial begin
 progress=$fopen("f_j0_progress.log","w");trace=$fopen("f_j0_layers.csv","w");
 repeat(4)@(negedge i_clk);i_rstn=1;repeat(8)@(negedge i_clk);i_gp_reset_done=1;i_hp_reset_done=1;
 wait(!o_busy);repeat(4)@(negedge i_clk);
 write_reg(8,32'h04000000,15,0,0);
 for(stage=0;stage<7;stage=stage+1)begin
  if(stage!=0)reset_job();load_case(stage);
  if(stage==3)begin stall_output=1;full_checks=0;end
  run_success();
  if(stage==3 && full_checks!=30)$fatal(1,"FIFO full boundary not exercised");
 end
 // Read-state cancellation and retained status must not poison a restarted task.
 reset_job();load_case(2);verify_network=0;init_job();write_reg(0,5,1,0,0);
 wait(f_active);reset_job();run_success();
 // Each real HP0 failure reports Feature as source and commits a safe GP error record.
 for(fault=1;fault<=6;fault=fault+1)begin
  reset_job();load_case(2);verify_network=0;init_job();
  if(fault==5)gp_memory[18][23:0]=4; // Only one quad belongs to declared input region.
  if(fault==6)gp_memory[22][9:8]=1; // Unsupported stride must issue no HP work.
  write_reg(0,5,1,0,0);wait(o_error);wait(!o_busy);
  if(o_done || (fault<=5 && o_error_code[15:12]!=1) || gp_write_statuses!=1 || statuses_seen!=0)$fatal(1,"pool fault source/barrier fault=%0d code=%h",fault,o_error_code);
  if(fault<=5 && o_error_code[19:16]!=(fault==1 || fault==4 ? 4 : fault==5 ? 5 : 3))$fatal(1,"pool wrong fault detail %h",o_error_code);
  if(fault==6 && (feature_commands!=0 || weight_commands!=0))$fatal(1,"invalid geometry issued DMA");
  error_checks=error_checks+1;
 end
 fault=0;reset_job();load_case(2);run_success();
 if(completed_cases!=9 || error_checks!=6)$fatal(1,"pool coverage incomplete");
 $fclose(trace);$fclose(progress);test_done=1;
 $display("PASS F-J0 production pool suite: jobs=%0d errors=%0d resets=%0d FIFO_full_hold=30 cycles=%0d",jobs,error_checks,reset_checks,cycles);$finish;
end
endmodule
