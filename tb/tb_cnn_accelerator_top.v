`timescale 1ns/1ps
module tb_cnn_accelerator_top;
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
reg [63:0]weight_memory[0:55591],feature_a[0:255],feature_b[0:255],final_results[0:1];
reg [511:0]configs[0:3];
reg [71:0]expected_commands[0:34],expected_beats[0:35];
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
  if(address>=32'h05000000 && address<32'h05000800)feature_word=feature_a[(address-32'h05000000)/8];
  else if(address>=32'h0b000000 && address<32'h0b000800)feature_word=feature_b[(address-32'h0b000000)/8];
  else begin feature_word=0;$fatal(1,"D5 feature DDR range %h",address);end
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
  wait(o_axi_bvalid);repeat(4)begin @(negedge i_clk);if(!o_axi_bvalid || o_axi_bresp!==response)$fatal(1,"D5 B response address=%h got=%b expected=%b",address,o_axi_bresp,response);end
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
  repeat(5)begin @(negedge i_clk);if(!o_axi_rvalid || o_axi_rresp!==response || o_axi_rdata!==held)$fatal(1,"D5 R hold/response");end
  value=held;i_axi_rready=1;@(posedge i_clk);@(negedge i_clk);i_axi_rready=0;checks=checks+1;
 end
endtask
task init_job;
 begin
  @(negedge i_clk);
  $readmemh("d5_inputs.mem",feature_a,0,35);
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
   if(!o_busy)$fatal(1,"D5 reset must be visible while DMA cancelling");
   wait(!o_gp_reset_req && !o_hp_reset_req);
  end
  // B channel stays live even though the datapath is reset. Both external acknowledgements are delayed.
  // After a fault, both DMA engines may already be cancelled before software consumes BVALID.
  repeat(5)@(negedge i_clk);
  if(!top.flag_core_rstn || !top.flag_spatial_empty || !top.flag_bypass_empty || o_error || o_done)$fatal(1,"D5 shared reset isolation");
  reset_checks=reset_checks+1;
 end
endtask
task successful_job;
 begin
  verify_network=1;init_job();write_reg(0,5,1,0,0);wait(o_done);@(negedge i_clk);
  if(o_error || !o_irq || layers_checked!=4 || layers_started!=4 || modes_seen!=15 || commands_seen!=35 || beats_seen!=36 || statuses_seen!=35 || pairs_seen!=72 || bundles_seen!=35 || gp_reads!=3 || gp_read_words!=80 || gp_writes!=1 || gp_write_words!=4 || gp_write_statuses!=1)$fatal(1,"D5 network totals layers=%0d/%0d modes=%0d cmd/beat/status=%0d/%0d/%0d pair/bundle=%0d/%0d GP=%0d/%0d/%0d/%0d/%0d irq=%b",layers_started,layers_checked,modes_seen,commands_seen,beats_seen,statuses_seen,pairs_seen,bundles_seen,gp_reads,gp_read_words,gp_writes,gp_write_words,gp_write_statuses,o_irq);
  if(final_results[0]!==expected_beats[34][63:0] || final_results[1]!==expected_beats[35][63:0])$fatal(1,"D5 final logits %h %h",final_results[0],final_results[1]);
  read_reg(4,0,read_value);if(read_value[2:0]!=2)$fatal(1,"D5 successful STATUS");
  read_reg(12,0,read_value);if(read_value!==o_cycles[31:0])$fatal(1,"D5 cycle low");
  read_reg(16,0,read_value);if(read_value!==o_cycles[63:32])$fatal(1,"D5 cycle high");
  write_reg(0,12,1,0,1);repeat(3)@(negedge i_clk);if(o_done || o_irq)$fatal(1,"D5 clear_done/IRQ");
  jobs=jobs+1;
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
  i_feature_keep=255;i_feature_last=f_position==f_beats-1;
 end
 if(!i_weight_data_valid || w_accepted)begin
  i_weight_data_valid=!o_hp_reset_req && w_active && cycles%7!=3;
  if(w_active)i_weight_data=weight_memory[(w_address-32'h12000000)/8+w_position];
  i_weight_keep=255;i_weight_last=w_position==w_beats-1;
 end
 i_output_cmd_ready=!o_hp_reset_req && !out_active && out_delay==0 && !i_output_status_valid && cycles%7!=2;
 i_output_data_ready=!o_hp_reset_req && cycles%11<7;
 if(o_gp_reset_req)i_gp_read_data_valid=0;
 if(o_hp_reset_req)begin i_feature_data_valid=0;i_weight_data_valid=0;end
end

always@(posedge i_clk)begin
 gp_accepted=i_gp_read_data_valid && o_gp_read_data_ready;
 f_accepted=i_feature_data_valid && o_feature_data_ready;
 w_accepted=i_weight_data_valid && o_weight_data_ready;
 cycles=cycles+1;
 if(cycles%10000==0)begin $fwrite(progress,"cycle=%0d stage=%0d jobs=%0d layer=%0d busy=%b error=%h reset=%b%b ack=%b%b\n",cycles,stage,jobs,o_current_layer,o_busy,o_error_code,o_gp_reset_req,o_hp_reset_req,i_gp_reset_done,i_hp_reset_done);$fflush(progress);end
 if(cycles>1500000)$fatal(1,"D5 timeout stage=%0d busy=%b error=%h",stage,o_busy,o_error_code);
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
   if(o_gp_read_cmd_data[71:64]!=0 || o_gp_read_cmd_data[31:23]!=9'h081 || o_gp_read_cmd_data[63:32]<32'h04000000 || o_gp_read_cmd_data[63:32]+o_gp_read_cmd_data[22:0]>32'h04000140)$fatal(1,"D5 GP command range");
   gp_active<=1;gp_address<=o_gp_read_cmd_data[63:32];gp_words<=o_gp_read_cmd_data[22:0]/4;gp_position<=0;gp_reads=gp_reads+1;
  end
  if(i_gp_read_data_valid && o_gp_read_data_ready)begin
   gp_position<=gp_position+1;gp_read_words=gp_read_words+1;
   if(i_gp_read_last)begin gp_active<=0;gp_delay<=4;end
  end
  if(gp_delay>0)begin gp_delay<=gp_delay-1;if(gp_delay==1)begin i_gp_read_status<=8'h80;i_gp_read_status_valid<=1;end end
  if(i_gp_read_status_valid && o_gp_read_status_ready)i_gp_read_status_valid<=0;
  if(o_gp_write_cmd_valid && i_gp_write_cmd_ready)begin
   if(o_gp_write_cmd_data!==72'h00041fffc040800010)$fatal(1,"D5 runtime command");
   gp_write_active<=1;gp_write_position<=0;gp_writes=gp_writes+1;
  end
  if(o_gp_write_data_valid && i_gp_write_data_ready)begin
   if(!gp_write_active || o_gp_write_keep!=15 || o_gp_write_last!==(gp_write_position==3))$fatal(1,"D5 runtime framing");
   runtime_memory[gp_write_position]=o_gp_write_data;gp_write_position<=gp_write_position+1;gp_write_words=gp_write_words+1;
   if(o_gp_write_last)gp_write_delay<=19;
  end
  if(gp_write_delay>0)begin gp_write_delay<=gp_write_delay-1;if(gp_write_delay==1)begin i_gp_write_status<=8'h80;i_gp_write_status_valid<=1;end end
  if(i_gp_write_status_valid && o_gp_write_status_ready)begin i_gp_write_status_valid<=0;gp_write_active<=0;gp_write_statuses=gp_write_statuses+1;end
  if(o_done && (gp_write_statuses!=1 || runtime_memory[3]!=1 || runtime_memory[2]!=3 || {runtime_memory[1],runtime_memory[0]}!==o_cycles))$fatal(1,"D5 completion before successful runtime commit");
 end
 if(!i_rstn || o_hp_reset_req)begin
  f_active<=0;w_active<=0;out_active<=0;f_delay<=0;w_delay<=0;out_delay<=0;
  i_feature_status_valid<=0;i_weight_status_valid<=0;i_output_status_valid<=0;held_valid<=0;
 end else begin
  if(o_feature_cmd_valid && i_feature_cmd_ready)begin
   feature_commands=feature_commands+1;
   if(o_feature_cmd_data[71:64]!=0 || o_feature_cmd_data[31:23]!=9'h081 || o_feature_cmd_data[2:0]!=0)$fatal(1,"D5 feature framing");
   f_address<=o_feature_cmd_data[63:32];f_beats<=o_feature_cmd_data[22:0]/8;f_position<=0;f_active<=1;
  end
  if(o_weight_cmd_valid && i_weight_cmd_ready)begin
   weight_commands=weight_commands+1;
   if(o_weight_cmd_data[63:32]<32'h12000000 || o_weight_cmd_data[63:32]+o_weight_cmd_data[22:0]>32'h12048640 || o_weight_cmd_data[2:0]!=0)$fatal(1,"D5 static weight file range %h",o_weight_cmd_data);
   w_address<=o_weight_cmd_data[63:32];w_beats<=o_weight_cmd_data[22:0]/8;w_position<=0;w_active<=1;
  end
  if(i_feature_data_valid && o_feature_data_ready)begin f_position<=f_position+1;if(i_feature_last)begin f_active<=0;f_delay<=4;end end
  if(i_weight_data_valid && o_weight_data_ready)begin w_position<=w_position+1;if(i_weight_last)begin w_active<=0;w_delay<=6;end end
  if(f_delay>0)begin f_delay<=f_delay-1;if(f_delay==1)begin i_feature_status<=8'h80;i_feature_status_valid<=1;end end
  if(w_delay>0)begin w_delay<=w_delay-1;if(w_delay==1)begin i_weight_status<=inject_weight_error ? 8'h10 : 8'h80;i_weight_status_valid<=1;end end
  if(i_feature_status_valid && o_feature_status_ready)i_feature_status_valid<=0;
  if(i_weight_status_valid && o_weight_status_ready)i_weight_status_valid<=0;
  if(o_output_cmd_valid && i_output_cmd_ready)begin
   if(verify_network && o_output_cmd_data!==expected_commands[commands_seen])$fatal(1,"D5 command %0d got=%h expected=%h",commands_seen,o_output_cmd_data,expected_commands[commands_seen]);
   if(lc==0)first_address=o_output_cmd_data[63:32];last_command=o_output_cmd_data[63:32];lc=lc+1;commands_seen=commands_seen+1;
   out_active<=1;out_address<=o_output_cmd_data[63:32];out_beats<=o_output_cmd_data[22:0]/8;out_position<=0;
  end
  if(held_valid && (!o_output_data_valid || o_output_data!==held_output))$fatal(1,"D5 output data changed under backpressure");
  held_valid<=o_output_data_valid && !i_output_data_ready;held_output<=o_output_data;
  if(o_output_data_valid && i_output_data_ready)begin
   if(!out_active || o_output_keep!=255 || o_output_last!==(out_position==out_beats-1))$fatal(1,"D5 output framing");
   if(verify_network && o_output_data!==expected_beats[beats_seen][63:0])$fatal(1,"D5 output beat=%0d got=%h expected=%h",beats_seen,o_output_data,expected_beats[beats_seen][63:0]);
   beat_address=out_address+out_position*8;last_address=beat_address;
   if(beat_address>=32'h0b000000 && beat_address<32'h0b000800)feature_b[(beat_address-32'h0b000000)/8]=o_output_data;
   else if(beat_address>=32'h05000000 && beat_address<32'h05000800)feature_a[(beat_address-32'h05000000)/8]=o_output_data;
   else if(beat_address>=32'h04200000 && beat_address<32'h04200010)final_results[(beat_address-32'h04200000)/8]=o_output_data;
   else $fatal(1,"D5 output DDR range");
   for(k=0;k<4;k=k+1)begin checksum=checksum+(position+1)*o_output_data[k*16+:16];position=position+1;end
   lb=lb+1;beats_seen=beats_seen+1;out_position<=out_position+1;
   if(o_output_last)out_delay<=7;
  end
  if(out_delay>0)begin out_delay<=out_delay-1;if(out_delay==1)begin i_output_status<=8'h80;i_output_status_valid<=1;end end
  if(i_output_status_valid && o_output_status_ready)begin i_output_status_valid<=0;out_active<=0;statuses_seen=statuses_seen+1;lr=lr+1;end
 end
 if(i_rstn && !o_hp_reset_req)begin
  if(top.dist_layer_start!=0)begin
   if(verify_network && (top.dist_layer_start!=15 || {top.extension,top.base_instruction}!==configs[layers_started]))$fatal(1,"D5 layer config/start %0d",layers_started);
   layers_started=layers_started+1;modes_seen=modes_seen|(1<<top.base_instruction[197:196]);
  end
  if(top.flag_pair_valid && top.flag_array_ready)pairs_seen=pairs_seen+1;
  if(top.flag_bundle_valid && top.flag_bundle_ready)bundles_seen=bundles_seen+1;
  if(top.flag_spatial_valid && top.flag_output_spatial_ready)for(k=0;k<4;k=k+1)le=le+top.spatial_mask[k];
  if(top.flag_bypass_valid && top.flag_output_bypass_ready)for(k=0;k<4;k=k+1)le=le+top.bypass_mask[k];
  if(o_layer_done && verify_network)begin
   if({checksum,last_address,last_command,first_address,lb[31:0],lc[31:0],le[31:0]}!==layer_checks[layers_checked] || lr!=lc)$fatal(1,"D5 layer check %0d checksum=%0d addresses=%h/%h/%h counts=%0d/%0d/%0d response=%0d expected=%h",layers_checked,checksum,first_address,last_command,last_address,le,lc,lb,lr,layer_checks[layers_checked]);
   $fwrite(trace,"%0d,%0d,%0d,%0d,%0d,%h,%h,%h,%0d\n",jobs,layers_checked,le,lc,lb,first_address,last_command,last_address,checksum);
   $fflush(trace);
   layers_checked=layers_checked+1;lc=0;lb=0;le=0;lr=0;checksum=0;position=0;
  end
 end
end

initial begin
 progress=$fopen("d5_progress.log","w");
 trace=$fopen("d5_layers.csv","w");$fwrite(trace,"job,layer,elements,commands,beats,first,last_command,last_beat,checksum\n");
 $readmemh("d5_gp_words.mem",gp_memory);$readmemh("d5_weights.mem",weight_memory);$readmemh("d5_configs.mem",configs);
 $readmemh("d5_commands.mem",expected_commands);$readmemh("d5_beats.mem",expected_beats);$readmemh("d5_layer_checks.mem",layer_checks);
 for(n=0;n<256;n=n+1)begin feature_a[n]=0;feature_b[n]=0;end
 repeat(5)@(negedge i_clk);i_rstn=1;wait(!o_busy);repeat(4)@(negedge i_clk);
 write_reg(8,32'h04000000,15,0,0);write_reg(32,320,15,0,1);
 read_reg(28,0,read_value);if(read_value!=32'h20261015)$fatal(1,"D5 BUILD_ID");
 write_reg(8,32'hffffff00,1,0,1);read_reg(8,0,read_value);if(read_value!=32'h04000000)$fatal(1,"D5 partial base write");
 write_reg(4,1,15,2,0);write_reg(9,1,15,2,1);write_reg(36,0,15,3,0);write_reg(0,3,1,2,1);
 read_reg(1,2,read_value);read_reg(36,3,read_value);
 successful_job();stage=1;
 verify_network=0;init_job();write_reg(0,5,1,0,1);wait(w_active && w_position>20);
 write_reg(8,0,15,2,0);write_reg(0,5,1,2,1);reset_job();stage=2;
 successful_job();stage=3;
 // Inject a real HP1 failure; HP resets immediately while GP completes a safe error record.
 verify_network=0;inject_weight_error=1;arm_launch_pause=1;init_job();write_reg(0,5,1,0,0);wait(o_error);wait(!o_busy);
 if(o_done || !o_irq || o_error_code[7:0]!=8 || o_error_code[15:12]!=2 || o_error_code[23:20]!=4 || gp_write_statuses!=1 || runtime_memory[3][1:0]!=2 || !o_hp_reset_req || !o_gp_reset_req)$fatal(1,"D5 HP fault source/runtime/reset code=%h runtime=%h",o_error_code,runtime_memory[3]);
 read_reg(24,0,read_value);if(read_value!==o_error_code)$fatal(1,"D5 first error retained across core reset");error_checks=error_checks+1;
 inject_weight_error=0;reset_job();stage=4;
 // Unknown/post opcode must fail without hanging the production top or issuing feature/weight DMA.
 gp_memory[53][11:8]=4'd3;
 init_job();write_reg(0,5,1,0,1);wait(o_error);wait(!o_busy);
 if(o_done || feature_commands!=0 || weight_commands!=0 || gp_write_statuses!=1)$fatal(1,"D5 unsupported opcode termination");error_checks=error_checks+1;
 reset_job();$readmemh("d5_gp_words.mem",gp_memory);stage=5;
 write_reg(32,256,15,0,0);init_job();write_reg(0,5,1,0,1);wait(o_error);wait(!o_busy);
 if(o_error_code[7:0]!=3 || layers_started!=0 || gp_write_statuses!=0 || gp_writes!=0)$fatal(1,"D5 truncated MODEL_BYTES code=%h layers=%0d writes=%0d statuses=%0d",o_error_code,layers_started,gp_writes,gp_write_statuses);error_checks=error_checks+1;
 reset_job();write_reg(32,320,15,0,1);stage=6;successful_job();
 if(start_pause_checks!=1)$fatal(1,"D5 accepted start was not paused");
 $fclose(trace);$fclose(progress);test_done=1;$display("PASS D5 production top: jobs=%0d CSR checks=%0d resets=%0d errors=%0d cycles=%0d",jobs,checks,reset_checks,error_checks,cycles);$finish;
end

endmodule
