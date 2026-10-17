`timescale 1ns/1ps
// D1系统自检：A3真实文件 -> HP1 Full DataMover BFM -> Weight_cmd -> C2 -> 真实CU。
module tb_weight_cmd;
reg clk=0;
always #5 clk=~clk;
reg rstn=0, ce=1, soft_reset=0, start=0, compute_idle=1, load_req=0;
reg [255:0]base_instruction=0, extension=0;
reg [8:0]group_index=0;
reg [7:0]tile_index=0;
wire start_ready,load_ready,weight_ready,load_done,load_enable,busy,error;
wire [3:0]error_code;
wire [8:0]loaded_group;
wire [7:0]loaded_tile;
wire [3455:0]bias_data;
wire cmd_valid,data_ready,status_ready,wr_valid;
wire [71:0]cmd_data;
reg cmd_ready=0,data_valid=0,data_last=0,status_valid=0;
reg [63:0]data=0;
reg [7:0]data_keep=8'hff,status=8'h80;
wire wr_ready,cache_wr_ready;
wire [3:0]wr_cu,wr_bank;
wire [7:0]wr_addr;
wire [31:0]wr_data;
reg allow_write=1,rd_valid=0;
reg [7:0]rd_addr=0;
wire rd_ready,cache_valid;
wire [2303:0]cache_data;
reg cu_rstn=0;
reg [1:0]mode=0;
wire cu_ready,cu_valid,cu_commit,cu_row;
wire [47:0]cu_zero;
wire [143:0]cu_one,cu_two,cu_three;
wire cu_input=cache_valid && weight_ready;
assign wr_ready=cache_wr_ready && allow_write;
weight_cmd dut(.i_clk(clk),.i_rstn(rstn),.i_ce(ce),.i_soft_reset(soft_reset),
 .i_start(start),.o_start_ready(start_ready),.i_base_instruction(base_instruction),.i_extension(extension),
 .i_compute_idle(compute_idle),.i_load_req(load_req),.o_load_ready(load_ready),.i_group_index(group_index),.i_tile_index(tile_index),
 .o_weight_ready(weight_ready),.o_load_done(load_done),.o_group_index(loaded_group),.o_tile_index(loaded_tile),.o_bias_data(bias_data),
 .o_load_enable(load_enable),.o_busy(busy),.o_error(error),.o_error_code(error_code),
 .o_cmd_valid(cmd_valid),.i_cmd_ready(cmd_ready),.o_cmd_data(cmd_data),.i_data_valid(data_valid),.o_data_ready(data_ready),
 .i_data(data),.i_data_keep(data_keep),.i_data_last(data_last),.i_status_valid(status_valid),.o_status_ready(status_ready),.i_status(status),
 .o_wr_valid(wr_valid),.i_wr_ready(wr_ready),.o_wr_cu(wr_cu),.o_wr_bank(wr_bank),.o_wr_addr(wr_addr),.o_wr_data(wr_data));
kernel_buffer cache(.i_clk(clk),.i_rstn(rstn),.i_ce(ce),.i_load_enable(load_enable),
 .i_wr_valid(wr_valid && allow_write),.i_wr_cu(wr_cu),.i_wr_bank(wr_bank),.i_wr_addr(wr_addr),.i_wr_data(wr_data),.o_wr_ready(cache_wr_ready),
 .i_rd_valid(rd_valid),.i_rd_addr(rd_addr),.o_rd_ready(rd_ready),.o_out_valid(cache_valid),.o_out_data(cache_data));
compute_unit cu(.i_clk(clk),.i_rstn(cu_rstn),.i_ce(ce),.i_in_valid(cu_input),.i_first(1'b1),.i_last(1'b1),.i_row_last(1'b1),
 .i_mode(mode),.i_feature_data(96'h000100010001000100010001),.i_weight_data(cache_data[287:0]),
 .o_ready(cu_ready),.o_valid(cu_valid),.o_zero(cu_zero),.o_one(cu_one),.o_two(cu_two),.o_three(cu_three),
 .o_column_commit(cu_commit),.o_row_advance(cu_row));
reg [511:0]configs[0:5];
reg [31:0]requests[0:10];
reg [71:0]commands[0:17];
reg [63:0]beats[0:101687];
reg [47:0]words[0:202751];
reg [2303:0]reads[0:65];
reg [3455:0]biases[0:10];
integer cycles=0,commands_seen=0,writes=0,readbacks=0,loads=0,cu_accepts=0,cu_results=0;
integer pauses=0,write_stalls=0,error_checks=0,reset_checks=0,guard_checks=0;
integer total_commands=0,total_writes=0,boundary_checks=0,trace;
integer config_pause_checks=0,config_reset_checks=0;
reg [200:0]held_config;
reg test_done=0,test_failed=0,auto_dma=0,checking=0,inject_bias=0;
reg pending=0,sent_status=0,sent_data=0;
integer remaining=0,beat_index=0,status_delay=0;
reg early_status=0,bias_transfer=0,command_pause_checked=0;
reg [71:0]held_command;
reg [47:0]held_write;
reg hold_write=0;

task fail;
 input [511:0]message;
 begin
  $display("FAIL D1 cycle=%0d: %0s",cycles,message);
  test_failed=1;
  $finish;
 end
endtask

always @(posedge clk) begin
 cycles=cycles+1;
 if(cycles>1500000) fail("simulation timeout");
 if(rstn) begin
  if(!ce) pauses=pauses+1;
  if(wr_valid && !wr_ready) write_stalls=write_stalls+1;
  if(!weight_ready && cu_input) fail("CU accepted unavailable weight");
  if(load_enable && rd_ready) fail("cache allows compute read while loading");
  if(!weight_ready && (cu_valid || cu_commit)) fail("compute pipeline active before weight ready");
  if(cu_input && cu_ready && ce && cu_rstn) cu_accepts=cu_accepts+1;
  if(cu_valid && ce && cu_rstn) cu_results=cu_results+1;
  if(hold_write && {wr_cu,wr_bank,wr_addr,wr_data} !== held_write) fail("pair payload changed under pause/backpressure");
  hold_write=wr_valid && !wr_ready;
  held_write={wr_cu,wr_bank,wr_addr,wr_data};
  if(wr_valid && wr_ready) begin
   total_writes=total_writes+1;
   if(checking) begin
    if({wr_cu,wr_bank,wr_addr,wr_data} !== words[writes]) begin
     $display("write %0d got=%h expected=%h",writes,{wr_cu,wr_bank,wr_addr,wr_data},words[writes]);
     fail("all-bank write oracle mismatch");
    end
    writes=writes+1;
   end
  end
  if(auto_dma) begin
   if(cmd_valid && cmd_ready) begin
    if(pending) fail("multiple outstanding commands");
    total_commands=total_commands+1;
    if(checking) begin
     if(cmd_data !== commands[commands_seen]) begin
      $display("command %0d got=%h expected=%h",commands_seen,cmd_data,commands[commands_seen]);
      fail("HP1 command oracle mismatch");
     end
     commands_seen=commands_seen+1;
    end
    pending=1; remaining=cmd_data[22:0]/8;
    early_status=(total_commands%2)==0;
    bias_transfer=cmd_data[22:0]!=73728;
    sent_status=0; sent_data=0; status_delay=0;
    $fdisplay(trace,"%0d,command,%h,%0d",cycles,cmd_data,total_writes);
   end
   if(data_valid && data_ready) begin
    beat_index=beat_index+1; remaining=remaining-1;
    if(remaining==0) sent_data=1;
   end
   if(status_valid && status_ready) sent_status=1;
   if(sent_data) status_delay=status_delay+1;
   if(pending && sent_data && sent_status) pending=0;
  end
 end else begin
  hold_write=0;
 end
end

always @(negedge clk) begin
 if(auto_dma) begin
  ce=(cycles%4096)<4093;
  // 第一个已呈现命令在ce零时握手，验证VALID不可撤销。
  if(cmd_valid && !command_pause_checked) begin
   ce=0; cmd_ready=1; held_command=cmd_data;
   command_pause_checked=1;
  end else begin
   cmd_ready=(cycles%13)>=3;
  end
  allow_write=(cycles%17)!=0;
  data_valid=pending && !sent_data && (cycles%7)!=0;
  data=beats[beat_index]; data_keep=8'hff; data_last=remaining==1;
  if(inject_bias && bias_transfer) data=64'h0000800000000000;
  status_valid=pending && !sent_status && (early_status || (sent_data && status_delay>5));
  status=8'h80;
 end
end

task reset_local;
 begin
  auto_dma=0; checking=0; pending=0; ce=1; cmd_ready=0; data_valid=0; status_valid=0;
  load_req=0; start=0; rd_valid=0; cu_rstn=0; allow_write=1; hold_write=0;
  @(negedge clk); soft_reset=1;
  @(negedge clk); soft_reset=0;
  if(error || weight_ready || busy) fail("soft reset did not revoke qualifications");
 end
endtask
task wait_configuration;
 integer step;
 begin
  for(step=0;step<7;step=step+1) begin
   if(load_ready || start_ready || weight_ready || cmd_valid || wr_valid || !busy)
    fail("configuration published qualification before seven stages completed");
   @(negedge clk);
  end
 end
endtask
task configure;
 input integer layer;
 begin
  @(negedge clk); base_instruction=configs[layer][255:0]; extension=configs[layer][511:256]; start=1;
  if(!start_ready) fail("layer start unexpectedly blocked");
  @(negedge clk); start=0;
  wait_configuration;
  if(error || !load_ready) fail("valid A3 configuration rejected");
 end
endtask
task request_load;
 input [8:0]g;
 input [7:0]t;
 begin
  @(negedge clk); group_index=g; tile_index=t; load_req=1;
  if(!load_ready) fail("load request unexpectedly blocked");
  @(negedge clk); load_req=0;
 end
endtask
task expect_error;
 input [3:0]code;
 begin
  repeat(8) @(negedge clk);
  if(!error || error_code!=code || weight_ready || cmd_valid || wr_valid) fail("error qualification mismatch");
  error_checks=error_checks+1;
 end
endtask
task take_command;
 begin
  wait(cmd_valid); @(negedge clk); cmd_ready=1;
  @(negedge clk); cmd_ready=0;
 end
endtask
task send_fault;
 input integer kind;
 begin
  reset_local; configure(0); request_load(0,0); take_command;
  @(negedge clk); data_valid=1; data=64'h0001000200030004; data_keep=kind==0 ? 8'h7f : 8'hff;
  data_last=kind==1;
  if(kind==2) begin status_valid=1; status=8'h90; end
  @(negedge clk); data_valid=0; status_valid=0; data_keep=8'hff; data_last=0;
  expect_error(kind==2 ? 4'd4 : 4'd3);
 end
endtask
integer n,j,current_layer=-1;
reg [3455:0]previous_bias;
initial begin
 $readmemh("d1_configs.mem",configs); $readmemh("d1_requests.mem",requests);
 $readmemh("d1_commands.mem",commands); $readmemh("d1_beats.mem",beats);
 $readmemh("d1_writes.mem",words); $readmemh("d1_reads.mem",reads); $readmemh("d1_biases.mem",biases);
 trace=$fopen("d1_trace.csv","w"); $fdisplay(trace,"cycle,event,command,writes");
 repeat(3) @(negedge clk); rstn=1;
 // 每个配置阶段均暂停，改变外部指令验证只使用接受沿锁存的数据。
 for(n=0;n<7;n=n+1) begin
  reset_local;
  @(negedge clk); base_instruction=configs[5][255:0]; extension=configs[5][511:256]; start=1;
  @(negedge clk); start=0;
  repeat(n) @(negedge clk);
  ce=0; base_instruction=256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  extension=base_instruction;
  held_config={dut.state_current,dut.reg_group_numerator,dut.reg_config_groups,dut.reg_config_tiles,
   dut.reg_bias_base,dut.reg_bias_bytes,dut.reg_weight_limit,dut.reg_bias_limit,
   dut.flag_fields_bad,dut.flag_limits_bad,dut.flag_configured};
  repeat(3) begin
   @(negedge clk);
   if({dut.state_current,dut.reg_group_numerator,dut.reg_config_groups,dut.reg_config_tiles,
    dut.reg_bias_base,dut.reg_bias_bytes,dut.reg_weight_limit,dut.reg_bias_limit,
    dut.flag_fields_bad,dut.flag_limits_bad,dut.flag_configured}!==held_config)
    fail("configuration pipeline advanced during ce pause");
   if(load_ready || cmd_valid || wr_valid || error) fail("paused configuration leaked qualification");
  end
  ce=1;
  while(busy) @(negedge clk);
  if(error || !load_ready || dut.reg_tiles!=49 || dut.reg_groups!=57 || dut.reg_bias_bytes!=32832)
   fail("configuration did not resume with accepted FC6 instruction");
  config_pause_checks=config_pause_checks+1;
 end
 // 逐阶段在ce暂停时软/硬复位，观察旧流水不再自动提交，再接受新配置。
 for(n=0;n<7;n=n+1) begin
  for(j=0;j<2;j=j+1) begin
   reset_local;
   @(negedge clk); base_instruction=configs[5][255:0]; extension=configs[5][511:256]; start=1;
   @(negedge clk); start=0;
   repeat(n) @(negedge clk);
   ce=0;
   if(j==0) begin
    soft_reset=1; @(negedge clk); soft_reset=0;
   end else begin
    #2 rstn=0; #1;
    if(load_ready || weight_ready || cmd_valid || wr_valid || load_done)
     fail("configuration async reset did not revoke qualification");
    @(negedge clk); rstn=1;
   end
   ce=1; repeat(9) @(negedge clk);
   if(busy || load_ready || weight_ready || error || dut.flag_configured)
    fail("reset configuration pipeline committed stale result");
   configure(0);
   config_reset_checks=config_reset_checks+1;
  end
 end
 // 错误配置：权重高位造成区域重叠、地址未对齐、直接重叠及非法算子。
 for(n=0;n<4;n=n+1) begin
  reset_local;
  @(negedge clk); base_instruction=configs[0][255:0]; extension=configs[0][511:256];
  case(n)
   0: extension[191:184]=8'd1;
   1: extension[2:0]=3'd1;
   2: extension[63:32]=extension[31:0];
   3: extension[171:168]=4'd3;
  endcase
  start=1; @(negedge clk); start=0; expect_error(1);
 end
 // 故意绕过软件生成入口，数量与几何不一致但DDR范围合法；不发load请求。
 for(n=0;n<2;n=n+1) begin
  reset_local;
  @(negedge clk); base_instruction=configs[0][255:0]; extension=configs[0][511:256];
  if(n==0) base_instruction[171:148]=base_instruction[171:148]-24'd4;
  else begin extension[191:184]=8'd1; extension[63:32]=32'h15000000; end
  start=1; @(negedge clk); start=0;
  wait_configuration;
  if(error || !load_ready || cmd_valid || dut.reg_tiles!=1 || dut.reg_groups!=1)
   fail("removed weight count consistency check still rejects configuration");
  if(dut.cnt_weight!={extension[191:184],base_instruction[171:148]} ||
     dut.weight_limit!={2'd0,extension[31:0]}+{1'b0,extension[191:184],base_instruction[171:148],1'b0})
   fail("software weight count not used for DDR end address");
  boundary_checks=boundary_checks+1;
 end
 reset_local; configure(0); request_load(0,1); expect_error(2);
 send_fault(0); send_fault(1); send_fault(2);
 // 真实C2接收低半后暂停高半，再异步复位。RAM不清，后续完整覆盖。
 reset_local; configure(0); request_load(0,0); take_command;
 @(negedge clk); data_valid=1; data=64'h0001000200030004;
 @(negedge clk); data_valid=0;
 @(negedge clk); ce=0; held_write={wr_cu,wr_bank,wr_addr,wr_data};
 repeat(3) begin @(negedge clk); if({wr_cu,wr_bank,wr_addr,wr_data}!==held_write) fail("high half advanced during ce pause"); end
 #2 rstn=0; #1;
 if(weight_ready || cmd_valid || wr_valid || load_done) fail("async reset left valid qualification");
 reset_checks=reset_checks+1;
 @(negedge clk); rstn=1; reset_local;
 reset_checks=reset_checks+1;
 // 完整主验收：四模式、尾group及尾tile全部加载。
 // 高8位非零的合法大层：4096零编码、342组九位索引、FC6的25088输入。
 configure(4);
 if(dut.reg_tiles!=8 || dut.reg_groups!=512 || dut.reg_inputs!=4096 || dut.reg_outputs!=4096) fail("4096 convolution configuration truncated");
 boundary_checks=boundary_checks+1;
 reset_local; configure(5);
 if(dut.reg_tiles!=49 || dut.reg_groups!=57 || dut.reg_inputs!=25088 || dut.reg_outputs!=4096) fail("FC6 input elements/high weight count truncated");
 boundary_checks=boundary_checks+1;
 reset_local;
 checking=1; auto_dma=1; beat_index=0; command_pause_checked=0;
 for(n=0;n<11;n=n+1) begin
  if(current_layer!=requests[n][31:24]) begin
   current_layer=requests[n][31:24]; cu_rstn=0; configure(current_layer); mode=requests[n][18:17];
   @(negedge clk); cu_rstn=1;
  end
  previous_bias=bias_data;
  // CAL报告仍在计算时，即使请求持续呈现也不得接受。
  @(negedge clk); compute_idle=0; load_req=1; group_index=requests[n][16:8]; tile_index=requests[n][7:0];
  repeat(3) begin @(negedge clk); if(load_ready || busy) fail("compute idle guard accepted unsafe load"); end
  guard_checks=guard_checks+1;
  load_req=0; compute_idle=1;
  request_load(requests[n][16:8],requests[n][7:0]);
  rd_valid=1; rd_addr=0; // 持续尝试共同读，C2在装载期间必须拒绝。
  wait(load_done); @(negedge clk); rd_valid=0;
  if(!weight_ready || loaded_group!=requests[n][16:8] || loaded_tile!=requests[n][7:0]) fail("load completion tag mismatch");
  if(bias_data!==biases[n]) fail("bias lane/sign/order mismatch");
  if(requests[n][7:0]!=0 && bias_data!==previous_bias) fail("later tile did not retain group bias");
  loads=loads+1;
  // 等一拍排空完成时的试探读，然后采样所有108个bank的六个首/中/末地址。
  repeat(2) @(negedge clk);
  for(j=0;j<6;j=j+1) begin
   @(negedge clk); case(j) 0:rd_addr=0;1:rd_addr=1;2:rd_addr=126;3:rd_addr=127;4:rd_addr=254;5:rd_addr=255;endcase
   rd_valid=1;
   while(!rd_ready) @(negedge clk);
   @(posedge clk); #1;
   if(!cache_valid || cache_data!==reads[readbacks]) begin
    $display("readback %0d pair=%0d",readbacks,rd_addr); fail("real C2 all-bank readback mismatch");
   end
   readbacks=readbacks+1;
   @(negedge clk); rd_valid=0;
  end
  repeat(24) @(negedge clk); // 排空实际CU流水后才允许下一次load。
 end
 if(commands_seen!=18 || writes!=202752 || readbacks!=66 || loads!=11 || beat_index!=101688) fail("main acceptance counts mismatch");
 if(cu_accepts==0 || cu_results==0 || pauses==0 || write_stalls==0 || !command_pause_checked) fail("required compute/stall coverage missing");
 // 整块正常写完后注入不可表示的INT48偏置。
 reset_local; configure(0); cu_rstn=0; auto_dma=1; inject_bias=1; beat_index=0;
 request_load(0,0); wait(error); @(negedge clk); auto_dma=0; data_valid=0; status_valid=0; cmd_ready=0; expect_error(5);
 if(error_checks!=9 || reset_checks!=2 || guard_checks!=11 || boundary_checks!=4 || config_pause_checks!=7 || config_reset_checks!=14) fail("negative/reset coverage mismatch");
 $display("PASS D1 loads=%0d commands=%0d writes=%0d readbacks=%0d CUaccepted=%0d CUresults=%0d errors=%0d cycles=%0d",loads,commands_seen,writes,readbacks,cu_accepts,cu_results,error_checks,cycles);
 $fclose(trace); test_done=1; $finish;
end
endmodule
