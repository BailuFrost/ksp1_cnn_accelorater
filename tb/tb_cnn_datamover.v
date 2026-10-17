`timescale 1ns / 1ps
// E-J2测试只注入搬运事务；不把注入流作为CNN推理证据。
module tb_cnn_datamover;
reg clk=0; always #5 clk=~clk;
reg rstn=0; reg gp_request=1, hp_request=1;
wire gp_halt,hp_halt,gp_rstn,hp_rstn; wire [1:0]gp_halted; wire [2:0]hp_halted;
integer cycles=0, checks=0, cancel_checks=0, test_done=0, test_failed=0;
integer gp_low=0,hp_low=0;
always@(negedge clk)begin if(rstn)begin if(!gp_rstn)gp_low=gp_low+1;else if(gp_low!=0)begin if(gp_low!=4)begin $display("FAIL GP reset width %0d",gp_low);test_failed=1;$finish;end gp_low=0;end if(!hp_rstn)hp_low=hp_low+1;else if(hp_low!=0)begin if(hp_low!=4)begin $display("FAIL HP reset width %0d",hp_low);test_failed=1;$finish;end hp_low=0;end end end
integer i,j,k,lane; reg [31:0]value;
reg [4:0]cmd_valid=0,tx_valid=0,tx_last=0,hold_read=0,allow_response=31,allow_write=31;
wire [4:0]cmd_ready,rx_valid,rx_last,tx_ready,sts_valid,sts_last;
reg [71:0]cmd_data[0:4]; reg [63:0]tx_data[0:4]; integer frame_bytes[0:4];
wire [63:0]rx_data[0:4]; wire [7:0]rx_keep[0:4]; wire [7:0]sts_data[0:4];
integer read_count[0:4],status_count[0:4],ar_count[0:4],aw_count[0:4],write_count[0:4];
always@(posedge clk) cycles<=cycles+1;
initial begin #2000000; $display("FAIL timeout cycles=%0d GP=%b/%b/%b HP=%b/%b/%b cmds=%b states=%d/%d counts=%d/%d/%d/%d/%d",cycles,gp_request,gp_halted,gp_rstn,hp_request,hp_halted,hp_rstn,cmd_valid,dut.gp_reset_manager.state_current,dut.hp_reset_manager.state_current,status_count[0],status_count[1],status_count[2],status_count[3],status_count[4]); test_failed=1; $finish; end
wire cmd_valid_wire_0,sts_ready_0; wire [71:0]cmd_wire_0;
wire [31:0]data_wire_0; wire [3:0]keep_wire_0; wire last_wire_0,valid_wire_0,ready_wire_0;
wire [31:0]addr_0; wire [7:0]len_0; wire [2:0]size_0; wire [1:0]burst_0; wire addr_valid_0; reg addr_ready_0;
reg [31:0]mem_data_0=0; reg mem_valid_0=0,mem_last_0=0; wire mem_ready_0;
wire [31:0]write_data_0; wire [3:0]write_strobe_0; wire write_valid_0,write_last_0; reg write_ready_0;
reg bvalid_0=0; wire bready_0;
reg [7:0]memory_0[0:16383]; integer address_0=0,remaining_0=0,pending_0=0,bwait_0=0,delay_0=0,n_0;
wire raw_status_valid_0,raw_status_last_0; wire [7:0]raw_status_0; wire raw_status_keep_0;
assign rx_valid[0]=valid_wire_0 && ready_wire_0;
assign rx_data[0]=data_wire_0;
assign rx_keep[0]=keep_wire_0; assign rx_last[0]=last_wire_0; assign tx_ready[0]=0;
assign sts_valid[0]=raw_status_valid_0; assign sts_data[0]=raw_status_0; assign sts_last[0]=raw_status_last_0;
always@(posedge clk)begin
if(rstn && dut.flag_gp_enabled)begin
if(raw_status_valid_0 && sts_ready_0)begin
if(raw_status_0!==8'h80 || raw_status_keep_0!==1 || raw_status_last_0!==1)begin $display("FAIL status lane 0 %h",raw_status_0);test_failed=1;$finish;end
status_count[0]<=status_count[0]+1;end
if(rx_valid[0])begin
for(n_0=0;n_0<4;n_0=n_0+1)begin
if(rx_data[0][n_0*8+:8]!==((32'hff0+read_count[0]*4+n_0)*13+0*37+90)%256)begin $display("FAIL read lane 0 beat %0d",read_count[0]);test_failed=1;$finish;end
end
if(rx_keep[0]!==4'hf || rx_last[0]!==(read_count[0]==1023))begin $display("FAIL read frame lane 0");test_failed=1;$finish;end
read_count[0]<=read_count[0]+1;end
end
end
always@*begin addr_ready_0=!pending_0 && !mem_valid_0 && !bvalid_0 && !bwait_0 && cycles%3!=0;
write_ready_0=pending_0 && allow_write[0] && cycles%4!=0;end
always@(posedge clk)begin
if(!rstn)begin pending_0<=0;mem_valid_0<=0;bvalid_0<=0;bwait_0<=0;end else begin
if(addr_valid_0 && addr_ready_0)begin
if(burst_0!=1 || size_0!=2 || len_0>15 || addr_0[11:0]+(len_0+1)*4>4096 || addr_0+(len_0+1)*4>16384)begin $display("FAIL AXI burst lane 0");test_failed=1;$finish;end
address_0<=addr_0;remaining_0<=len_0+1;pending_0<=1;ar_count[0]<=ar_count[0]+1;end
if(mem_valid_0 && mem_ready_0)mem_valid_0<=0;
if(pending_0 && (!mem_valid_0 || mem_ready_0) && allow_response[0] && cycles%3!=1)begin
for(n_0=0;n_0<4;n_0=n_0+1)mem_data_0[n_0*8+:8]<=memory_0[address_0+n_0];
mem_valid_0<=1;mem_last_0<=remaining_0==1;address_0<=address_0+4;remaining_0<=remaining_0-1;
if(remaining_0==1)pending_0<=0;end
end end
wire cmd_valid_wire_1,sts_ready_1; wire [71:0]cmd_wire_1;
wire [31:0]data_wire_1; wire [3:0]keep_wire_1; wire last_wire_1,valid_wire_1,ready_wire_1;
wire [31:0]addr_1; wire [7:0]len_1; wire [2:0]size_1; wire [1:0]burst_1; wire addr_valid_1; reg addr_ready_1;
reg [31:0]mem_data_1=0; reg mem_valid_1=0,mem_last_1=0; wire mem_ready_1;
wire [31:0]write_data_1; wire [3:0]write_strobe_1; wire write_valid_1,write_last_1; reg write_ready_1;
reg bvalid_1=0; wire bready_1;
reg [7:0]memory_1[0:16383]; integer address_1=0,remaining_1=0,pending_1=0,bwait_1=0,delay_1=0,n_1;
wire raw_status_valid_1,raw_status_last_1; wire [7:0]raw_status_1; wire raw_status_keep_1;
assign rx_valid[1]=0; assign rx_data[1]=0; assign rx_keep[1]=0; assign rx_last[1]=0;
assign tx_ready[1]=ready_wire_1;
assign sts_valid[1]=raw_status_valid_1; assign sts_data[1]=raw_status_1; assign sts_last[1]=raw_status_last_1;
always@(posedge clk)begin
if(rstn && dut.flag_gp_enabled)begin
if(raw_status_valid_1 && sts_ready_1)begin
if(raw_status_1!==8'h80 || raw_status_keep_1!==1 || raw_status_last_1!==1)begin $display("FAIL status lane 1 %h",raw_status_1);test_failed=1;$finish;end
status_count[1]<=status_count[1]+1;end
if(rx_valid[1])begin
for(n_1=0;n_1<4;n_1=n_1+1)begin
if(rx_data[1][n_1*8+:8]!==((32'hff0+read_count[1]*4+n_1)*13+1*37+90)%256)begin $display("FAIL read lane 1 beat %0d",read_count[1]);test_failed=1;$finish;end
end
if(rx_keep[1]!==4'hf || rx_last[1]!==(read_count[1]==1023))begin $display("FAIL read frame lane 1");test_failed=1;$finish;end
read_count[1]<=read_count[1]+1;end
end
end
always@*begin addr_ready_1=!pending_1 && !mem_valid_1 && !bvalid_1 && !bwait_1 && cycles%3!=0;
write_ready_1=pending_1 && allow_write[1] && cycles%4!=0;end
always@(posedge clk)begin
if(!rstn)begin pending_1<=0;mem_valid_1<=0;bvalid_1<=0;bwait_1<=0;end else begin
if(addr_valid_1 && addr_ready_1)begin
if(burst_1!=1 || size_1!=2 || len_1>15 || addr_1[11:0]+(len_1+1)*4>4096 || addr_1+(len_1+1)*4>16384)begin $display("FAIL AXI burst lane 1");test_failed=1;$finish;end
address_1<=addr_1;remaining_1<=len_1+1;pending_1<=1;aw_count[1]<=aw_count[1]+1;end
if(write_valid_1 && write_ready_1)begin
if(write_last_1!==(remaining_1==1))begin $display("FAIL WLAST lane 1");test_failed=1;$finish;end
for(n_1=0;n_1<4;n_1=n_1+1)if(write_strobe_1[n_1])memory_1[address_1+n_1]<=write_data_1[n_1*8+:8];
address_1<=address_1+4;remaining_1<=remaining_1-1;write_count[1]<=write_count[1]+1;
if(remaining_1==1)begin pending_1<=0;bwait_1<=1;delay_1<=7;end end
if(bwait_1 && allow_response[1])begin if(delay_1==0)begin bvalid_1<=1;bwait_1<=0;end else delay_1<=delay_1-1;end
if(bvalid_1 && bready_1)bvalid_1<=0;
end end
wire cmd_valid_wire_2,sts_ready_2; wire [71:0]cmd_wire_2;
wire [63:0]data_wire_2; wire [7:0]keep_wire_2; wire last_wire_2,valid_wire_2,ready_wire_2;
wire [31:0]addr_2; wire [7:0]len_2; wire [2:0]size_2; wire [1:0]burst_2; wire addr_valid_2; reg addr_ready_2;
reg [63:0]mem_data_2=0; reg mem_valid_2=0,mem_last_2=0; wire mem_ready_2;
wire [63:0]write_data_2; wire [7:0]write_strobe_2; wire write_valid_2,write_last_2; reg write_ready_2;
reg bvalid_2=0; wire bready_2;
reg [7:0]memory_2[0:16383]; integer address_2=0,remaining_2=0,pending_2=0,bwait_2=0,delay_2=0,n_2;
wire raw_status_valid_2,raw_status_last_2; wire [7:0]raw_status_2; wire raw_status_keep_2;
assign rx_valid[2]=valid_wire_2 && ready_wire_2;
assign rx_data[2]=data_wire_2;
assign rx_keep[2]=keep_wire_2; assign rx_last[2]=last_wire_2; assign tx_ready[2]=0;
assign sts_valid[2]=raw_status_valid_2; assign sts_data[2]=raw_status_2; assign sts_last[2]=raw_status_last_2;
always@(posedge clk)begin
if(rstn && dut.flag_hp_enabled)begin
if(raw_status_valid_2 && sts_ready_2)begin
if(raw_status_2!==8'h80 || raw_status_keep_2!==1 || raw_status_last_2!==1)begin $display("FAIL status lane 2 %h",raw_status_2);test_failed=1;$finish;end
status_count[2]<=status_count[2]+1;end
if(rx_valid[2])begin
for(n_2=0;n_2<8;n_2=n_2+1)begin
if(rx_data[2][n_2*8+:8]!==((32'hff0+read_count[2]*8+n_2)*13+2*37+90)%256)begin $display("FAIL read lane 2 beat %0d",read_count[2]);test_failed=1;$finish;end
end
if(rx_keep[2]!==8'hff || rx_last[2]!==(read_count[2]==511))begin $display("FAIL read frame lane 2");test_failed=1;$finish;end
read_count[2]<=read_count[2]+1;end
end
end
always@*begin addr_ready_2=!pending_2 && !mem_valid_2 && !bvalid_2 && !bwait_2 && cycles%3!=0;
write_ready_2=pending_2 && allow_write[2] && cycles%4!=0;end
always@(posedge clk)begin
if(!rstn)begin pending_2<=0;mem_valid_2<=0;bvalid_2<=0;bwait_2<=0;end else begin
if(addr_valid_2 && addr_ready_2)begin
if(burst_2!=1 || size_2!=3 || len_2>15 || addr_2[11:0]+(len_2+1)*8>4096 || addr_2+(len_2+1)*8>16384)begin $display("FAIL AXI burst lane 2");test_failed=1;$finish;end
address_2<=addr_2;remaining_2<=len_2+1;pending_2<=1;ar_count[2]<=ar_count[2]+1;end
if(mem_valid_2 && mem_ready_2)mem_valid_2<=0;
if(pending_2 && (!mem_valid_2 || mem_ready_2) && allow_response[2] && cycles%3!=1)begin
for(n_2=0;n_2<8;n_2=n_2+1)mem_data_2[n_2*8+:8]<=memory_2[address_2+n_2];
mem_valid_2<=1;mem_last_2<=remaining_2==1;address_2<=address_2+8;remaining_2<=remaining_2-1;
if(remaining_2==1)pending_2<=0;end
end end
wire cmd_valid_wire_3,sts_ready_3; wire [71:0]cmd_wire_3;
wire [63:0]data_wire_3; wire [7:0]keep_wire_3; wire last_wire_3,valid_wire_3,ready_wire_3;
wire [31:0]addr_3; wire [7:0]len_3; wire [2:0]size_3; wire [1:0]burst_3; wire addr_valid_3; reg addr_ready_3;
reg [63:0]mem_data_3=0; reg mem_valid_3=0,mem_last_3=0; wire mem_ready_3;
wire [63:0]write_data_3; wire [7:0]write_strobe_3; wire write_valid_3,write_last_3; reg write_ready_3;
reg bvalid_3=0; wire bready_3;
reg [7:0]memory_3[0:16383]; integer address_3=0,remaining_3=0,pending_3=0,bwait_3=0,delay_3=0,n_3;
wire raw_status_valid_3,raw_status_last_3; wire [7:0]raw_status_3; wire raw_status_keep_3;
assign rx_valid[3]=valid_wire_3 && ready_wire_3;
assign rx_data[3]=data_wire_3;
assign rx_keep[3]=keep_wire_3; assign rx_last[3]=last_wire_3; assign tx_ready[3]=0;
assign sts_valid[3]=raw_status_valid_3; assign sts_data[3]=raw_status_3; assign sts_last[3]=raw_status_last_3;
always@(posedge clk)begin
if(rstn && dut.flag_hp_enabled)begin
if(raw_status_valid_3 && sts_ready_3)begin
if(raw_status_3!==8'h80 || raw_status_keep_3!==1 || raw_status_last_3!==1)begin $display("FAIL status lane 3 %h",raw_status_3);test_failed=1;$finish;end
status_count[3]<=status_count[3]+1;end
if(rx_valid[3])begin
for(n_3=0;n_3<8;n_3=n_3+1)begin
if(rx_data[3][n_3*8+:8]!==((32'hff0+read_count[3]*8+n_3)*13+3*37+90)%256)begin $display("FAIL read lane 3 beat %0d",read_count[3]);test_failed=1;$finish;end
end
if(rx_keep[3]!==8'hff || rx_last[3]!==(read_count[3]==511))begin $display("FAIL read frame lane 3");test_failed=1;$finish;end
read_count[3]<=read_count[3]+1;end
end
end
always@*begin addr_ready_3=!pending_3 && !mem_valid_3 && !bvalid_3 && !bwait_3 && cycles%3!=0;
write_ready_3=pending_3 && allow_write[3] && cycles%4!=0;end
always@(posedge clk)begin
if(!rstn)begin pending_3<=0;mem_valid_3<=0;bvalid_3<=0;bwait_3<=0;end else begin
if(addr_valid_3 && addr_ready_3)begin
if(burst_3!=1 || size_3!=3 || len_3>15 || addr_3[11:0]+(len_3+1)*8>4096 || addr_3+(len_3+1)*8>16384)begin $display("FAIL AXI burst lane 3");test_failed=1;$finish;end
address_3<=addr_3;remaining_3<=len_3+1;pending_3<=1;ar_count[3]<=ar_count[3]+1;end
if(mem_valid_3 && mem_ready_3)mem_valid_3<=0;
if(pending_3 && (!mem_valid_3 || mem_ready_3) && allow_response[3] && cycles%3!=1)begin
for(n_3=0;n_3<8;n_3=n_3+1)mem_data_3[n_3*8+:8]<=memory_3[address_3+n_3];
mem_valid_3<=1;mem_last_3<=remaining_3==1;address_3<=address_3+8;remaining_3<=remaining_3-1;
if(remaining_3==1)pending_3<=0;end
end end
wire cmd_valid_wire_4,sts_ready_4; wire [71:0]cmd_wire_4;
wire [63:0]data_wire_4; wire [7:0]keep_wire_4; wire last_wire_4,valid_wire_4,ready_wire_4;
wire [31:0]addr_4; wire [7:0]len_4; wire [2:0]size_4; wire [1:0]burst_4; wire addr_valid_4; reg addr_ready_4;
reg [63:0]mem_data_4=0; reg mem_valid_4=0,mem_last_4=0; wire mem_ready_4;
wire [63:0]write_data_4; wire [7:0]write_strobe_4; wire write_valid_4,write_last_4; reg write_ready_4;
reg bvalid_4=0; wire bready_4;
reg [7:0]memory_4[0:16383]; integer address_4=0,remaining_4=0,pending_4=0,bwait_4=0,delay_4=0,n_4;
wire raw_status_valid_4,raw_status_last_4; wire [7:0]raw_status_4; wire raw_status_keep_4;
assign rx_valid[4]=0; assign rx_data[4]=0; assign rx_keep[4]=0; assign rx_last[4]=0;
assign tx_ready[4]=ready_wire_4;
assign sts_valid[4]=raw_status_valid_4; assign sts_data[4]=raw_status_4; assign sts_last[4]=raw_status_last_4;
always@(posedge clk)begin
if(rstn && dut.flag_hp_enabled)begin
if(raw_status_valid_4 && sts_ready_4)begin
if(raw_status_4!==8'h80 || raw_status_keep_4!==1 || raw_status_last_4!==1)begin $display("FAIL status lane 4 %h",raw_status_4);test_failed=1;$finish;end
status_count[4]<=status_count[4]+1;end
if(rx_valid[4])begin
for(n_4=0;n_4<8;n_4=n_4+1)begin
if(rx_data[4][n_4*8+:8]!==((32'hff0+read_count[4]*8+n_4)*13+4*37+90)%256)begin $display("FAIL read lane 4 beat %0d",read_count[4]);test_failed=1;$finish;end
end
if(rx_keep[4]!==8'hff || rx_last[4]!==(read_count[4]==511))begin $display("FAIL read frame lane 4");test_failed=1;$finish;end
read_count[4]<=read_count[4]+1;end
end
end
always@*begin addr_ready_4=!pending_4 && !mem_valid_4 && !bvalid_4 && !bwait_4 && cycles%3!=0;
write_ready_4=pending_4 && allow_write[4] && cycles%4!=0;end
always@(posedge clk)begin
if(!rstn)begin pending_4<=0;mem_valid_4<=0;bvalid_4<=0;bwait_4<=0;end else begin
if(addr_valid_4 && addr_ready_4)begin
if(burst_4!=1 || size_4!=3 || len_4>15 || addr_4[11:0]+(len_4+1)*8>4096 || addr_4+(len_4+1)*8>16384)begin $display("FAIL AXI burst lane 4");test_failed=1;$finish;end
address_4<=addr_4;remaining_4<=len_4+1;pending_4<=1;aw_count[4]<=aw_count[4]+1;end
if(write_valid_4 && write_ready_4)begin
if(write_last_4!==(remaining_4==1))begin $display("FAIL WLAST lane 4");test_failed=1;$finish;end
for(n_4=0;n_4<8;n_4=n_4+1)if(write_strobe_4[n_4])memory_4[address_4+n_4]<=write_data_4[n_4*8+:8];
address_4<=address_4+8;remaining_4<=remaining_4-1;write_count[4]<=write_count[4]+1;
if(remaining_4==1)begin pending_4<=0;bwait_4<=1;delay_4<=7;end end
if(bwait_4 && allow_response[4])begin if(delay_4==0)begin bvalid_4<=1;bwait_4<=0;end else delay_4<=delay_4-1;end
if(bvalid_4 && bready_4)bvalid_4<=0;
end end
cnn_board_top dut(.i_clk(clk),
.i_rstn(rstn),
.i_ce(1'b1),
.i_axi_awaddr(0),
.i_axi_awvalid(0),
.o_axi_awready(),
.i_axi_wdata(0),
.i_axi_wstrb(0),
.i_axi_wvalid(0),
.o_axi_wready(),
.o_axi_bresp(),
.o_axi_bvalid(),
.i_axi_bready(0),
.i_axi_araddr(0),
.i_axi_arvalid(0),
.o_axi_arready(),
.o_axi_rdata(),
.o_axi_rresp(),
.o_axi_rvalid(),
.i_axi_rready(0),
.o_irq(),
.o_busy(),
.o_done(),
.o_error(),
.o_error_code(),
.o_current_layer(),
.o_cycles(),
.o_layer_done(),
.o_gp_read_cmd_valid(cmd_valid_wire_0),
.i_gp_read_cmd_ready(cmd_ready[0]),
.o_gp_read_cmd_data(cmd_wire_0),
.i_gp_read_data_valid(valid_wire_0),
.o_gp_read_data_ready(ready_wire_0),
.i_gp_read_data(data_wire_0),
.i_gp_read_keep(keep_wire_0),
.i_gp_read_last(last_wire_0),
.i_gp_read_status_valid(sts_valid[0]),
.o_gp_read_status_ready(sts_ready_0),
.i_gp_read_status(sts_data[0]),
.o_gp_write_cmd_valid(cmd_valid_wire_1),
.i_gp_write_cmd_ready(cmd_ready[1]),
.o_gp_write_cmd_data(cmd_wire_1),
.o_gp_write_data_valid(valid_wire_1),
.i_gp_write_data_ready(ready_wire_1),
.o_gp_write_data(data_wire_1),
.o_gp_write_keep(keep_wire_1),
.o_gp_write_last(last_wire_1),
.i_gp_write_status_valid(sts_valid[1]),
.o_gp_write_status_ready(sts_ready_1),
.i_gp_write_status(sts_data[1]),
.o_feature_cmd_valid(cmd_valid_wire_2),
.i_feature_cmd_ready(cmd_ready[2]),
.o_feature_cmd_data(cmd_wire_2),
.i_feature_data_valid(valid_wire_2),
.o_feature_data_ready(ready_wire_2),
.i_feature_data(data_wire_2),
.i_feature_keep(keep_wire_2),
.i_feature_last(last_wire_2),
.i_feature_status_valid(sts_valid[2]),
.o_feature_status_ready(sts_ready_2),
.i_feature_status(sts_data[2]),
.o_weight_cmd_valid(cmd_valid_wire_3),
.i_weight_cmd_ready(cmd_ready[3]),
.o_weight_cmd_data(cmd_wire_3),
.i_weight_data_valid(valid_wire_3),
.o_weight_data_ready(ready_wire_3),
.i_weight_data(data_wire_3),
.i_weight_keep(keep_wire_3),
.i_weight_last(last_wire_3),
.i_weight_status_valid(sts_valid[3]),
.o_weight_status_ready(sts_ready_3),
.i_weight_status(sts_data[3]),
.o_output_cmd_valid(cmd_valid_wire_4),
.i_output_cmd_ready(cmd_ready[4]),
.o_output_cmd_data(cmd_wire_4),
.o_output_data_valid(valid_wire_4),
.i_output_data_ready(ready_wire_4),
.o_output_data(data_wire_4),
.o_output_keep(keep_wire_4),
.o_output_last(last_wire_4),
.i_output_status_valid(sts_valid[4]),
.o_output_status_ready(sts_ready_4),
.i_output_status(sts_data[4]),
.i_gp_halted(gp_halted),
.i_hp_halted(hp_halted),
.o_gp_halt(gp_halt),
.o_gp_dma_rstn(gp_rstn),
.o_hp_halt(hp_halt),
.o_hp_dma_rstn(hp_rstn));
e_j2_system_dma_gp_0 dma_gp(.m_axi_mm2s_aclk(clk),
.m_axi_mm2s_aresetn(gp_rstn),
.mm2s_halt(gp_halt),
.mm2s_halt_cmplt(gp_halted[0]),
.m_axis_mm2s_cmdsts_aclk(clk),
.m_axis_mm2s_cmdsts_aresetn(gp_rstn),
.s_axis_mm2s_cmd_tvalid(cmd_valid_wire_0),
.s_axis_mm2s_cmd_tready(cmd_ready[0]),
.s_axis_mm2s_cmd_tdata(cmd_wire_0),
.m_axis_mm2s_sts_tvalid(raw_status_valid_0),
.m_axis_mm2s_sts_tready(sts_ready_0),
.m_axis_mm2s_sts_tdata(raw_status_0),
.m_axis_mm2s_sts_tkeep(raw_status_keep_0),
.m_axis_mm2s_sts_tlast(raw_status_last_0),
.mm2s_allow_addr_req(1'b1),
.mm2s_dbg_sel(4'b0),
.m_axi_mm2s_araddr(addr_0),
.m_axi_mm2s_arlen(len_0),
.m_axi_mm2s_arsize(size_0),
.m_axi_mm2s_arburst(burst_0),
.m_axi_mm2s_arvalid(addr_valid_0),
.m_axi_mm2s_arready(addr_ready_0),
.m_axi_mm2s_rdata(mem_data_0),
.m_axi_mm2s_rresp(2'b0),
.m_axi_mm2s_rlast(mem_last_0),
.m_axi_mm2s_rvalid(mem_valid_0),
.m_axi_mm2s_rready(mem_ready_0),
.m_axis_mm2s_tdata(data_wire_0),
.m_axis_mm2s_tkeep(keep_wire_0),
.m_axis_mm2s_tlast(last_wire_0),
.m_axis_mm2s_tvalid(valid_wire_0),
.m_axis_mm2s_tready(ready_wire_0),
.m_axi_s2mm_aclk(clk),
.m_axi_s2mm_aresetn(gp_rstn),
.s2mm_halt(gp_halt),
.s2mm_halt_cmplt(gp_halted[1]),
.m_axis_s2mm_cmdsts_awclk(clk),
.m_axis_s2mm_cmdsts_aresetn(gp_rstn),
.s_axis_s2mm_cmd_tvalid(cmd_valid_wire_1),
.s_axis_s2mm_cmd_tready(cmd_ready[1]),
.s_axis_s2mm_cmd_tdata(cmd_wire_1),
.m_axis_s2mm_sts_tvalid(raw_status_valid_1),
.m_axis_s2mm_sts_tready(sts_ready_1),
.m_axis_s2mm_sts_tdata(raw_status_1),
.m_axis_s2mm_sts_tkeep(raw_status_keep_1),
.m_axis_s2mm_sts_tlast(raw_status_last_1),
.s2mm_allow_addr_req(1'b1),
.s2mm_dbg_sel(4'b0),
.m_axi_s2mm_awaddr(addr_1),
.m_axi_s2mm_awlen(len_1),
.m_axi_s2mm_awsize(size_1),
.m_axi_s2mm_awburst(burst_1),
.m_axi_s2mm_awvalid(addr_valid_1),
.m_axi_s2mm_awready(addr_ready_1),
.m_axi_s2mm_wdata(write_data_1),
.m_axi_s2mm_wstrb(write_strobe_1),
.m_axi_s2mm_wlast(write_last_1),
.m_axi_s2mm_wvalid(write_valid_1),
.m_axi_s2mm_wready(write_ready_1),
.m_axi_s2mm_bresp(2'b0),
.m_axi_s2mm_bvalid(bvalid_1),
.m_axi_s2mm_bready(bready_1),
.s_axis_s2mm_tdata(data_wire_1),
.s_axis_s2mm_tkeep(keep_wire_1),
.s_axis_s2mm_tlast(last_wire_1),
.s_axis_s2mm_tvalid(valid_wire_1),
.s_axis_s2mm_tready(ready_wire_1));
e_j2_system_dma_feature_0 dma_feature(.m_axi_mm2s_aclk(clk),
.m_axi_mm2s_aresetn(hp_rstn),
.mm2s_halt(hp_halt),
.mm2s_halt_cmplt(hp_halted[0]),
.m_axis_mm2s_cmdsts_aclk(clk),
.m_axis_mm2s_cmdsts_aresetn(hp_rstn),
.s_axis_mm2s_cmd_tvalid(cmd_valid_wire_2),
.s_axis_mm2s_cmd_tready(cmd_ready[2]),
.s_axis_mm2s_cmd_tdata(cmd_wire_2),
.m_axis_mm2s_sts_tvalid(raw_status_valid_2),
.m_axis_mm2s_sts_tready(sts_ready_2),
.m_axis_mm2s_sts_tdata(raw_status_2),
.m_axis_mm2s_sts_tkeep(raw_status_keep_2),
.m_axis_mm2s_sts_tlast(raw_status_last_2),
.mm2s_allow_addr_req(1'b1),
.mm2s_dbg_sel(4'b0),
.m_axi_mm2s_araddr(addr_2),
.m_axi_mm2s_arlen(len_2),
.m_axi_mm2s_arsize(size_2),
.m_axi_mm2s_arburst(burst_2),
.m_axi_mm2s_arvalid(addr_valid_2),
.m_axi_mm2s_arready(addr_ready_2),
.m_axi_mm2s_rdata(mem_data_2),
.m_axi_mm2s_rresp(2'b0),
.m_axi_mm2s_rlast(mem_last_2),
.m_axi_mm2s_rvalid(mem_valid_2),
.m_axi_mm2s_rready(mem_ready_2),
.m_axis_mm2s_tdata(data_wire_2),
.m_axis_mm2s_tkeep(keep_wire_2),
.m_axis_mm2s_tlast(last_wire_2),
.m_axis_mm2s_tvalid(valid_wire_2),
.m_axis_mm2s_tready(ready_wire_2));
e_j2_system_dma_weight_0 dma_weight(.m_axi_mm2s_aclk(clk),
.m_axi_mm2s_aresetn(hp_rstn),
.mm2s_halt(hp_halt),
.mm2s_halt_cmplt(hp_halted[1]),
.m_axis_mm2s_cmdsts_aclk(clk),
.m_axis_mm2s_cmdsts_aresetn(hp_rstn),
.s_axis_mm2s_cmd_tvalid(cmd_valid_wire_3),
.s_axis_mm2s_cmd_tready(cmd_ready[3]),
.s_axis_mm2s_cmd_tdata(cmd_wire_3),
.m_axis_mm2s_sts_tvalid(raw_status_valid_3),
.m_axis_mm2s_sts_tready(sts_ready_3),
.m_axis_mm2s_sts_tdata(raw_status_3),
.m_axis_mm2s_sts_tkeep(raw_status_keep_3),
.m_axis_mm2s_sts_tlast(raw_status_last_3),
.mm2s_allow_addr_req(1'b1),
.mm2s_dbg_sel(4'b0),
.m_axi_mm2s_araddr(addr_3),
.m_axi_mm2s_arlen(len_3),
.m_axi_mm2s_arsize(size_3),
.m_axi_mm2s_arburst(burst_3),
.m_axi_mm2s_arvalid(addr_valid_3),
.m_axi_mm2s_arready(addr_ready_3),
.m_axi_mm2s_rdata(mem_data_3),
.m_axi_mm2s_rresp(2'b0),
.m_axi_mm2s_rlast(mem_last_3),
.m_axi_mm2s_rvalid(mem_valid_3),
.m_axi_mm2s_rready(mem_ready_3),
.m_axis_mm2s_tdata(data_wire_3),
.m_axis_mm2s_tkeep(keep_wire_3),
.m_axis_mm2s_tlast(last_wire_3),
.m_axis_mm2s_tvalid(valid_wire_3),
.m_axis_mm2s_tready(ready_wire_3));
e_j2_system_dma_output_0 dma_output(.m_axi_s2mm_aclk(clk),
.m_axi_s2mm_aresetn(hp_rstn),
.s2mm_halt(hp_halt),
.s2mm_halt_cmplt(hp_halted[2]),
.m_axis_s2mm_cmdsts_awclk(clk),
.m_axis_s2mm_cmdsts_aresetn(hp_rstn),
.s_axis_s2mm_cmd_tvalid(cmd_valid_wire_4),
.s_axis_s2mm_cmd_tready(cmd_ready[4]),
.s_axis_s2mm_cmd_tdata(cmd_wire_4),
.m_axis_s2mm_sts_tvalid(raw_status_valid_4),
.m_axis_s2mm_sts_tready(sts_ready_4),
.m_axis_s2mm_sts_tdata(raw_status_4),
.m_axis_s2mm_sts_tkeep(raw_status_keep_4),
.m_axis_s2mm_sts_tlast(raw_status_last_4),
.s2mm_allow_addr_req(1'b1),
.s2mm_dbg_sel(4'b0),
.m_axi_s2mm_awaddr(addr_4),
.m_axi_s2mm_awlen(len_4),
.m_axi_s2mm_awsize(size_4),
.m_axi_s2mm_awburst(burst_4),
.m_axi_s2mm_awvalid(addr_valid_4),
.m_axi_s2mm_awready(addr_ready_4),
.m_axi_s2mm_wdata(write_data_4),
.m_axi_s2mm_wstrb(write_strobe_4),
.m_axi_s2mm_wlast(write_last_4),
.m_axi_s2mm_wvalid(write_valid_4),
.m_axi_s2mm_wready(write_ready_4),
.m_axi_s2mm_bresp(2'b0),
.m_axi_s2mm_bvalid(bvalid_4),
.m_axi_s2mm_bready(bready_4),
.s_axis_s2mm_tdata(data_wire_4),
.s_axis_s2mm_tkeep(keep_wire_4),
.s_axis_s2mm_tlast(last_wire_4),
.s_axis_s2mm_tvalid(valid_wire_4),
.s_axis_s2mm_tready(ready_wire_4));
task automatic command; input integer idx; input [22:0]bytes; begin
@(negedge clk);frame_bytes[idx]=bytes;cmd_data[idx]={8'b0,32'hff0,9'h081,bytes};cmd_valid[idx]=1;
while(!cmd_ready[idx])@(negedge clk);@(negedge clk);cmd_valid[idx]=0;end endtask
task automatic write_stream; input integer idx; input integer beats; integer beat,b,bytes; begin
bytes=idx==1 ? 4 : 8;
for(beat=0;beat<beats;beat=beat+1)begin
@(negedge clk); for(b=0;b<bytes;b=b+1)tx_data[idx][b*8+:8]=(beat*bytes+b)*7+idx*19+165;
tx_last[idx]=beat==frame_bytes[idx]/bytes-1;tx_valid[idx]=1;while(!tx_ready[idx])@(negedge clk);@(negedge clk);tx_valid[idx]=0;end end endtask
task check_writes; integer a; begin
for(a=0;a<4096;a=a+1)begin
if(memory_1[4080+a]!==((a*7+19+165)%256) || memory_4[4080+a]!==((a*7+76+165)%256))begin $display("FAIL stored byte %0d",a);test_failed=1;$finish;end
end checks=checks+2;end endtask
task prepare; begin
for(i=0;i<5;i=i+1)begin read_count[i]=0;status_count[i]=0;ar_count[i]=0;aw_count[i]=0;write_count[i]=0;end
for(i=0;i<16384;i=i+1)begin
memory_0[i]=(i*13+0*37+90)%256;
memory_1[i]=(i*13+1*37+90)%256;
memory_2[i]=(i*13+2*37+90)%256;
memory_3[i]=(i*13+3*37+90)%256;
memory_4[i]=(i*13+4*37+90)%256;
end end endtask
initial begin
for(i=0;i<5;i=i+1)begin cmd_data[i]=0;tx_data[i]=0;frame_bytes[i]=4096;end
prepare;
force dut.flag_core_gp_read_cmd_valid=cmd_valid[0];
force dut.gp_read_cmd_data_o=cmd_data[0];
force dut.flag_core_gp_read_status_ready=(cycles%7!=0);
force dut.flag_core_gp_read_data_ready=!hold_read[0] && cycles%5!=0;
force dut.flag_core_gp_write_cmd_valid=cmd_valid[1];
force dut.gp_write_cmd_data_o=cmd_data[1];
force dut.flag_core_gp_write_status_ready=(cycles%7!=0);
force dut.flag_core_gp_write_data_valid=tx_valid[1];
force dut.gp_write_data_o=tx_data[1];
force dut.gp_write_keep_o=4'hf;
force dut.gp_write_last_o=tx_last[1];
force dut.flag_core_feature_cmd_valid=cmd_valid[2];
force dut.feature_cmd_data_o=cmd_data[2];
force dut.flag_core_feature_status_ready=(cycles%7!=0);
force dut.flag_core_feature_data_ready=!hold_read[2] && cycles%5!=0;
force dut.flag_core_weight_cmd_valid=cmd_valid[3];
force dut.weight_cmd_data_o=cmd_data[3];
force dut.flag_core_weight_status_ready=(cycles%7!=0);
force dut.flag_core_weight_data_ready=!hold_read[3] && cycles%5!=0;
force dut.flag_core_output_cmd_valid=cmd_valid[4];
force dut.output_cmd_data_o=cmd_data[4];
force dut.flag_core_output_status_ready=(cycles%7!=0);
force dut.flag_core_output_data_valid=tx_valid[4];
force dut.output_data_o=tx_data[4];
force dut.output_keep_o=8'hff;
force dut.output_last_o=tx_last[4];
force dut.flag_gp_reset_req=gp_request; force dut.flag_hp_reset_req=hp_request;
repeat(12)@(negedge clk);rstn=1;
wait(dut.flag_gp_reset_done && dut.flag_hp_reset_done);@(negedge clk);gp_request=0;hp_request=0;repeat(4)@(negedge clk);$display("READY cycles=%0d",cycles);
// 五个方向短并发，4KiB从0xFF0起跨页，BFM逐burst检查页边界。
fork command(0,4096);command(1,4096);command(2,4096);command(3,4096);command(4,4096);write_stream(1,1024);write_stream(4,512);join $display("SENT cycles=%0d",cycles);
wait(status_count[0]==1 && status_count[1]==1 && status_count[2]==1 && status_count[3]==1 && status_count[4]==1);
if(read_count[0]!=1024 || read_count[2]!=512 || read_count[3]!=512 || ar_count[0]<2 || aw_count[1]<2 || aw_count[4]<2)begin $display("FAIL counts");test_failed=1;$finish;end
checks=checks+5;check_writes;
// 在途HP读且S2MM只有第一个beat，停止后不能向核心交付旧状态。
prepare;hold_read=12;allow_response[3]=0;
fork command(2,4096);command(3,4096);command(4,4096);write_stream(4,1);join
wait(pending_3);repeat(8)@(negedge clk);hp_request=1;
repeat(12)@(negedge clk);if(dut.flag_hp_reset_done || !hp_rstn || gp_halt || !dut.flag_gp_enabled)begin $display("FAIL premature HP cancel");test_failed=1;$finish;end
checks=checks+1;allow_response[3]=1;wait(dut.flag_hp_reset_done);cancel_checks=cancel_checks+1;$display("HP CANCEL cycles=%0d",cycles);
repeat(8)@(negedge clk);if(!dut.flag_hp_reset_done || !hp_rstn || hp_halt)begin $display("FAIL held ACK");test_failed=1;$finish;end
hp_request=0;hold_read=0;repeat(4)@(negedge clk);
// GP读等待响应、GP写等待B，取消必须等共享AXI响应完成。
prepare;allow_response[0]=0;allow_response[1]=0;
fork command(0,4096);command(1,16);write_stream(1,4);join
wait(bwait_1);@(negedge clk);gp_request=1;repeat(12)@(negedge clk);
if(dut.flag_gp_reset_done || !gp_rstn || hp_halt || !dut.flag_hp_enabled)begin $display("FAIL premature GP cancel");test_failed=1;$finish;end
checks=checks+1;allow_response=31;wait(dut.flag_gp_reset_done);cancel_checks=cancel_checks+1;@(negedge clk);gp_request=0;repeat(4)@(negedge clk);$display("GP CANCEL cycles=%0d",cycles);
// 重复取消要求每次撤销旧应答，局部复位保持完整四周期。
for(j=0;j<3;j=j+1)begin @(negedge clk);gp_request=1;hp_request=1;#1;
if(dut.flag_gp_reset_done || dut.flag_hp_reset_done)begin $display("FAIL stale ACK");test_failed=1;$finish;end
wait(dut.flag_gp_reset_done && dut.flag_hp_reset_done);@(negedge clk);gp_request=0;hp_request=0;repeat(4)@(negedge clk);cancel_checks=cancel_checks+1;end
// 全部取消完成后重装已知数据并重复并发传输。
prepare;fork command(0,4096);command(1,4096);command(2,4096);command(3,4096);command(4,4096);write_stream(1,1024);write_stream(4,512);join
wait(status_count[0]==1 && status_count[1]==1 && status_count[2]==1 && status_count[3]==1 && status_count[4]==1);check_writes;
checks=checks+5;test_done=1;$display("PASS E-J2 real DataMover checks=%0d cancels=%0d cycles=%0d",checks,cancel_checks,cycles);$finish;
end
endmodule
