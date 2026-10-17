`timescale 1ns/1ps
module tb_cnn_control_regs;
reg i_clk=0;
reg i_rstn=0;
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
reg i_start_ready=0;
reg i_clear_ready=0;
reg i_busy=0;
reg i_done=0;
reg i_error=0;
reg i_fifo_stall=0;
reg i_reset_busy=0;
reg i_runtime_error=0;
reg [31:0]i_error_code=0;
reg [7:0]i_current_layer=0;
reg [63:0]i_cycles=0;
wire [31:0]o_model_base;
wire [31:0]o_model_bytes;
wire o_start;
wire o_soft_reset;
wire o_clear_done;
wire o_irq;
cnn_control_regs dut(
.i_clk(i_clk),
.i_rstn(i_rstn),
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
.i_start_ready(i_start_ready),
.i_clear_ready(i_clear_ready),
.i_busy(i_busy),
.i_done(i_done),
.i_error(i_error),
.i_fifo_stall(i_fifo_stall),
.i_reset_busy(i_reset_busy),
.i_runtime_error(i_runtime_error),
.i_error_code(i_error_code),
.i_current_layer(i_current_layer),
.i_cycles(i_cycles),
.o_model_base(o_model_base),
.o_model_bytes(o_model_bytes),
.o_start(o_start),
.o_soft_reset(o_soft_reset),
.o_clear_done(o_clear_done),
.o_irq(o_irq)
);
task write_reg;
 input [7:0]address;input [31:0]value;input [3:0]strobe;input [1:0]response;input integer order;
 begin
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


always #5 i_clk=~i_clk;
reg test_done=0,test_failed=0;
integer checks=0,start_pulses=0,reset_pulses=0,clear_pulses=0,cycles=0;
reg [31:0]value;
always@(posedge i_clk)begin
 cycles=cycles+1;if(cycles>10000)$fatal(1,"D5 CSR timeout");
 if(o_start)start_pulses=start_pulses+1;
 if(o_soft_reset)reset_pulses=reset_pulses+1;
 if(o_clear_done)clear_pulses=clear_pulses+1;
end
initial begin
 repeat(3)@(negedge i_clk);i_rstn=1;i_start_ready=1;i_clear_ready=1;
 i_cycles=64'h00000002fffffffe;read_reg(16,0,value);if(value!=2)$fatal(1,"CSR live high before snapshot");
 read_reg(12,0,value);if(value!=32'hfffffffe)$fatal(1,"CSR low snapshot");
 i_cycles=64'h0000000700000044;read_reg(16,0,value);if(value!=2)$fatal(1,"CSR rollover snapshot high");
 write_reg(8,32'h04000000,15,0,1);write_reg(8,32'h00001234,3,0,0);read_reg(8,0,value);if(value!=32'h04001234)$fatal(1,"CSR byte strobes");
 write_reg(32,320,15,0,0);write_reg(32,999,0,0,1);read_reg(32,0,value);if(value!=320)$fatal(1,"CSR zero strobe");
 i_busy=1;write_reg(8,0,15,2,0);write_reg(32,0,15,2,1);i_busy=0;
 i_start_ready=0;write_reg(0,5,1,2,1);i_start_ready=1;write_reg(0,5,1,0,0);
 i_clear_ready=0;write_reg(0,12,1,2,0);i_clear_ready=1;write_reg(0,12,1,0,1);
 write_reg(0,4,1,0,1);i_done=1;#1;if(!o_irq)$fatal(1,"CSR completion IRQ");
 i_done=0;i_error=1;#1;if(!o_irq)$fatal(1,"CSR error IRQ");
 i_fifo_stall=1;i_runtime_error=1;i_reset_busy=1;i_current_layer=255;i_error_code=32'h00402008;
 read_reg(4,0,value);if(value!=32'h0000007c)$fatal(1,"CSR diagnostic status %h",value);
 read_reg(20,0,value);if(value!=255)$fatal(1,"CSR layer255");read_reg(24,0,value);if(value!=32'h00402008)$fatal(1,"CSR full error code");
 write_reg(0,0,1,0,0);#1;if(o_irq)$fatal(1,"CSR IRQ disable");
 write_reg(0,6,1,0,1);read_reg(16,0,value);if(value!=7)$fatal(1,"CSR soft reset removes old snapshot");
 read_reg(8,0,value);if(value!=32'h04001234)$fatal(1,"CSR base persists across soft reset");
 read_reg(32,0,value);if(value!=320)$fatal(1,"CSR bytes persist across soft reset");
 write_reg(0,32'hff000005,1,0,0);write_reg(0,16,15,2,1);write_reg(0,9,1,2,0);
 if(start_pulses!=2 || reset_pulses!=1 || clear_pulses!=1)$fatal(1,"CSR single pulses %0d/%0d/%0d",start_pulses,reset_pulses,clear_pulses);
 test_done=1;$display("PASS D5 CSR rollover/response/strobe/errors checks=%0d",checks);$finish;
end

endmodule
