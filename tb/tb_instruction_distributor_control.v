`timescale 1ns/1ps
module tb_instruction_distributor_control;
    reg i_clk=0;
    reg i_rstn=0;
    reg i_ce=0;
    reg i_soft_reset=0;
    reg i_start=0;
    reg i_clear_done=0;
    reg [31:0]i_model_base=0;
    reg [31:0]i_model_bytes=0;
    reg [3:0]i_controller_ready=0;
    reg [3:0]i_controller_busy=0;
    reg [3:0]i_controller_error=0;
    reg [15:0]i_controller_error_code=0;
    reg i_compute_done=0;
    reg i_output_done=0;
    reg i_packer_busy=0;
    reg i_spatial_fifo_empty=0;
    reg i_bypass_fifo_empty=0;
    wire o_start_ready;
    wire o_busy;
    wire o_done;
    wire o_error;
    wire [7:0]o_error_code;
    wire [3:0]o_error_source;
    wire [15:0]o_controller_error_code;
    wire o_runtime_error;
    wire o_abort;
    wire [63:0]o_cycles;
    wire [63:0]o_layer_cycles;
    wire [7:0]o_current_layer;
    wire [255:0]o_base_instruction;
    wire [255:0]o_extension;
    wire [3:0]o_layer_start;
    wire o_read_cmd_valid;
    reg i_read_cmd_ready=0;
    wire [71:0]o_read_cmd_data;
    reg i_read_data_valid=0;
    wire o_read_data_ready;
    reg [31:0]i_read_data=0;
    reg [3:0]i_read_keep=0;
    reg i_read_last=0;
    reg i_read_status_valid=0;
    wire o_read_status_ready;
    reg [7:0]i_read_status=0;
    wire o_write_cmd_valid;
    reg i_write_cmd_ready=0;
    wire [71:0]o_write_cmd_data;
    wire o_write_data_valid;
    reg i_write_data_ready=0;
    wire [31:0]o_write_data;
    wire [3:0]o_write_keep;
    wire o_write_last;
    reg i_write_status_valid=0;
    wire o_write_status_ready;
    reg [7:0]i_write_status=0;
    instruction_distributor dut(.i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_ce(i_ce),
        .i_soft_reset(i_soft_reset),
        .i_start(i_start),
        .i_clear_done(i_clear_done),
        .i_model_base(i_model_base),
        .i_model_bytes(i_model_bytes),
        .i_controller_ready(i_controller_ready),
        .i_controller_busy(i_controller_busy),
        .i_controller_error(i_controller_error),
        .i_controller_error_code(i_controller_error_code),
        .i_compute_done(i_compute_done),
        .i_output_done(i_output_done),
        .i_packer_busy(i_packer_busy),
        .i_spatial_fifo_empty(i_spatial_fifo_empty),
        .i_bypass_fifo_empty(i_bypass_fifo_empty),
        .o_start_ready(o_start_ready),
        .o_busy(o_busy),
        .o_done(o_done),
        .o_error(o_error),
        .o_error_code(o_error_code),
        .o_error_source(o_error_source),
        .o_controller_error_code(o_controller_error_code),
        .o_runtime_error(o_runtime_error),
        .o_abort(o_abort),
        .o_cycles(o_cycles),
        .o_layer_cycles(o_layer_cycles),
        .o_current_layer(o_current_layer),
        .o_base_instruction(o_base_instruction),
        .o_extension(o_extension),
        .o_layer_start(o_layer_start),
        .o_read_cmd_valid(o_read_cmd_valid),
        .i_read_cmd_ready(i_read_cmd_ready),
        .o_read_cmd_data(o_read_cmd_data),
        .i_read_data_valid(i_read_data_valid),
        .o_read_data_ready(o_read_data_ready),
        .i_read_data(i_read_data),
        .i_read_keep(i_read_keep),
        .i_read_last(i_read_last),
        .i_read_status_valid(i_read_status_valid),
        .o_read_status_ready(o_read_status_ready),
        .i_read_status(i_read_status),
        .o_write_cmd_valid(o_write_cmd_valid),
        .i_write_cmd_ready(i_write_cmd_ready),
        .o_write_cmd_data(o_write_cmd_data),
        .o_write_data_valid(o_write_data_valid),
        .i_write_data_ready(i_write_data_ready),
        .o_write_data(o_write_data),
        .o_write_keep(o_write_keep),
        .o_write_last(o_write_last),
        .i_write_status_valid(i_write_status_valid),
        .o_write_status_ready(o_write_status_ready),
        .i_write_status(i_write_status));

    always #5 i_clk=~i_clk;
    reg [31:0]memory[0:4111],original[0:79];
    reg [255:0]expected_base,expected_extension;
    reg [71:0]held_command;
    reg [127:0]runtime_record;
    integer test_done=0,test_failed=0,checks=0,starts=0,max_layers=0;
    integer j,k,n,reads,offset,words,guard,mode;
    reg [7:0]saved_code;
    task tick;begin @(posedge i_clk);#1;end endtask
    task reset_job;begin
        i_rstn=0;i_ce=1;i_start=0;i_soft_reset=0;i_clear_done=0;
        i_model_base=32'h04000000;i_model_bytes=320;
        i_controller_ready=0;i_controller_busy=0;i_controller_error=0;i_controller_error_code=0;
        i_compute_done=0;i_output_done=0;i_packer_busy=0;i_spatial_fifo_empty=1;i_bypass_fifo_empty=1;
        i_read_cmd_ready=0;i_read_data_valid=0;i_read_status_valid=0;
        i_read_keep=15;i_read_last=0;i_write_cmd_ready=0;i_write_data_ready=0;i_write_status_valid=0;
        i_read_status=8'h80;i_write_status=8'h80;
        for(j=0;j<80;j=j+1)memory[j]=original[j];
        starts=0;reads=0;repeat(2)tick;i_rstn=1;repeat(2)tick;
        if(!o_start_ready || o_done || o_error)$fatal(1,"reset qualification");
    end endtask
    task begin_job;begin i_start=1;tick;i_start=0;end endtask
    task read_packet;
        input integer fault;
        begin
            guard=0;while(!o_read_cmd_valid && !o_error)begin tick;guard=guard+1;if(guard>50)$fatal(1,"read command timeout");end
            if(o_error)$fatal(1,"unexpected read error %0d",o_error_code);
            held_command=o_read_cmd_data;
            offset=(held_command[63:32]-i_model_base)/4;words=held_command[22:0]/4;
            if(held_command[71:64]!=0 || held_command[31:23]!=9'h081 || held_command[1:0]!=0 || offset<0 || offset+words>4112)$fatal(1,"GP command ABI");
            i_ce=0;repeat(3)begin tick;if(!o_read_cmd_valid || o_read_cmd_data!==held_command)$fatal(1,"command pause hold");end
            i_read_cmd_ready=1;tick;i_read_cmd_ready=0;
            if(!o_read_data_ready)$fatal(1,"command accepted during ce=0");
            if(fault==4)begin i_read_status_valid=1;tick;i_read_status_valid=0;i_ce=1;end
            else begin
                for(k=0;k<words;k=k+1)begin
                    i_read_data=memory[offset+k];i_read_data_valid=1;i_read_keep=(fault==1 && k==0)?7:15;
                    i_read_last=(fault==2 && k==0)?1:((fault==3)?0:(k==words-1));
                    tick;
                    if(o_error)k=words;
                end
                i_read_data_valid=0;i_read_last=0;i_read_keep=15;
                if(!o_error)begin
                    if(!o_read_status_ready)$fatal(1,"read status qualification");
                    i_read_status=fault==5?8'h81:8'h80;i_read_status_valid=1;tick;i_read_status_valid=0;
                end
                i_ce=1;
            end
            reads=reads+1;
        end
    endtask
    task preload;begin read_packet(0);read_packet(0);read_packet(0);end endtask
    task layer_start;
        input integer index;
        begin
            i_controller_ready=15;
            #1;guard=0;while(!o_layer_start)begin tick;guard=guard+1;if(guard>40)$fatal(1,"layer start timeout index=%0d code=%0d state=%0d phase=%0d ce=%0d ready=%h",index,o_error_code,dut.state_current,dut.reg_phase,i_ce,i_controller_ready);end
            if(o_layer_start!==4'hf || reads!=3 || o_current_layer!=index)$fatal(1,"broadcast/prefetch/index");
            for(j=0;j<8;j=j+1)begin
                expected_base[j*32+:32]=memory[16+index*8+j];
                expected_extension[j*32+:32]=memory[memory[8]/4+index*8+j];
            end
            if(o_base_instruction!==expected_base || o_extension!==expected_extension)$fatal(1,"same-index dual cache %0d",index);
            i_controller_busy=15;tick;i_controller_ready=0;starts=starts+1;
        end
    endtask
    task hold_boundary;begin
        repeat(3)begin tick;if(o_layer_start || o_write_cmd_valid || o_base_instruction!==expected_base || o_extension!==expected_extension)$fatal(1,"premature boundary or config change");end
    end endtask
    task complete_layer;begin
        i_ce=0;i_compute_done=1;i_packer_busy=1;i_spatial_fifo_empty=0;i_bypass_fifo_empty=0;
        tick;i_compute_done=0;hold_boundary;
        i_output_done=1;tick;i_output_done=0;hold_boundary;
        i_ce=1;i_controller_busy=0;hold_boundary;
        i_packer_busy=0;hold_boundary;
        i_spatial_fifo_empty=1;hold_boundary;
        i_bypass_fifo_empty=1;
    end endtask
    task runtime_write;
        input integer response_fault;
        begin
            guard=0;while(!o_write_cmd_valid)begin tick;guard=guard+1;if(guard>50)$fatal(1,"runtime command timeout code=%0d",o_error_code);end
            if(o_write_cmd_data!==72'h00041fffc040800010 || o_done)$fatal(1,"runtime command/done");
            held_command=o_write_cmd_data;i_ce=0;repeat(3)begin tick;if(o_write_cmd_data!==held_command || !o_write_cmd_valid)$fatal(1,"write command hold");end
            i_write_cmd_ready=1;tick;i_write_cmd_ready=0;
            if(response_fault==2)begin i_write_status_valid=1;tick;i_write_status_valid=0;end
            else begin
                for(k=0;k<4;k=k+1)begin
                    runtime_record[k*32+:32]=o_write_data;
                    repeat(2)begin tick;if(o_write_data!==runtime_record[k*32+:32] || !o_write_data_valid || o_write_keep!=15 || o_write_last!=(k==3) || o_done)$fatal(1,"write payload hold");end
                    i_write_data_ready=1;tick;i_write_data_ready=0;
                end
                if(runtime_record[63:0]!==o_cycles || runtime_record[95:64]!=={24'd0,o_current_layer} || runtime_record[127:96]!=={o_controller_error_code,o_error_code,6'd0,o_error,!o_error})$fatal(1,"runtime ABI snapshot");
                repeat(8)begin tick;if(o_done || !o_busy)$fatal(1,"done before final GP status");end
                i_write_status=response_fault==1?8'h81:8'h80;i_write_status_valid=1;tick;i_write_status_valid=0;
            end
            i_ce=1;repeat(3)tick;
            if(o_busy || (response_fault==0 && !o_error && !o_done) || (response_fault!=0 && (!o_runtime_error || o_done)))$fatal(1,"runtime commit result");
        end
    endtask
    task local_error;
        input [7:0]code;
        begin
            guard=0;while(!o_error)begin tick;guard=guard+1;if(guard>30)$fatal(1,"missing local error %0d",code);end
            repeat(3)tick;
            if(o_error_code!=code || o_busy || o_done || o_write_cmd_valid || o_layer_start || starts!=0)$fatal(1,"local failure code=%0d expected=%0d",o_error_code,code);
            checks=checks+1;
        end
    endtask
    task reported_error;
        input [7:0]code;
        begin
            guard=0;while(!o_error)begin tick;guard=guard+1;if(guard>30)$fatal(1,"missing reported error %0d",code);end
            if(o_error_code!=code || o_done || o_layer_start)$fatal(1,"reported failure code=%0d expected=%0d",o_error_code,code);
            saved_code=o_error_code;runtime_write(0);
            if(o_error_code!=saved_code || o_done)$fatal(1,"first fault preservation");checks=checks+1;
        end
    endtask
    initial begin
        $readmemh("d4_gp_words.mem",original);
        // Four-mode table: ready ports stagger, two done pulses arrive while ce=0; every drain condition is required.
        reset_job;begin_job;preload;
        repeat(8)tick;
        for(n=0;n<4;n=n+1)begin
            i_controller_ready=1;repeat(3)tick;if(o_layer_start)$fatal(1,"ready bit0 alone");
            i_controller_ready=3;repeat(3)tick;if(o_layer_start)$fatal(1,"ready bits01 alone");
            i_controller_ready=7;repeat(3)tick;if(o_layer_start)$fatal(1,"ready bits012 alone");
            layer_start(n);complete_layer;
        end
        runtime_write(0);if(starts!=4 || !o_done)$fatal(1,"four layer chain");checks=checks+1;
        i_clear_done=1;tick;i_clear_done=0;if(!o_start_ready)$fatal(1,"clear done restart");checks=checks+1;
        // Model range and actual loaded byte count are independent of the header declaration.
        for(mode=0;mode<5;mode=mode+1)begin
            reset_job;
            case(mode)0:i_model_base=32'h04000004;1:i_model_base=32'h03ffffc0;2:i_model_base=32'h041fffc0;3:i_model_base=32'hffffffc0;4:i_model_bytes=63;endcase
            begin_job;local_error(1);
        end
        for(mode=0;mode<14;mode=mode+1)begin
            reset_job;
            case(mode)
                0:memory[0]=0;1:memory[2]=1;2:memory[3]=32;3:memory[4]=8;4:memory[5]=0;5:memory[5]=257;
                6:memory[6]=128;7:memory[7]=64;8:memory[9]=64;9:memory[11]=0;10:memory[12]=0;11:memory[15]=1;
                12:memory[8]=196;13:memory[13]=256;
            endcase
            begin_job;read_packet(0);local_error(mode<12?2:3);
        end
        reset_job;i_model_bytes=256;begin_job;read_packet(0);local_error(3);
        for(mode=0;mode<4;mode=mode+1)begin
            reset_job;case(mode)0:memory[10]=32'h04000000;1:memory[10]=32'h041ffff8;2:memory[10]=32'h03fffff8;3:memory[10]=32'h041fffc4;endcase
            begin_job;read_packet(0);local_error(4);
        end
        for(mode=1;mode<=5;mode=mode+1)begin reset_job;begin_job;read_packet(mode);local_error(mode>=4?6:5);end
        reset_job;begin_job;read_packet(0);read_packet(1);reported_error(5);
        // Basic layer validation is performed after both tables load, before any broadcast.
        for(mode=0;mode<6;mode=mode+1)begin
            reset_job;
            case(mode)
                0:memory[53]=(memory[53]&32'hfffff0ff)|32'h00000500;
                1:memory[23]=memory[23]|32'h10;
                2:memory[53]=memory[53]|32'h80;
                3:memory[53]=(memory[53]&32'hffffffc0)|48;
                4:memory[16]=memory[16]|1;
                5:memory[23]=memory[23]|32'h1000;
            endcase
            begin_job;preload;reported_error(7);if(starts!=0)$fatal(1,"bad layer broadcast");
        end
        reset_job;begin_job;preload;layer_start(0);i_controller_error=4'b0010;i_controller_error_code=16'h0050;tick;
        reported_error(8);if(o_error_source!=2 || o_controller_error_code!=16'h0050)$fatal(1,"controller diagnostic snapshot");
        reset_job;memory[55]=8;begin_job;preload;layer_start(0);i_ce=0;repeat(9)tick;i_ce=1;reported_error(9);
        for(mode=1;mode<=2;mode=mode+1)begin
            reset_job;begin_job;preload;layer_start(0);i_controller_error=1;tick;runtime_write(mode);
            if(o_error_code!=8 || !o_runtime_error)$fatal(1,"first controller error survives GP write failure");checks=checks+1;
        end
        for(mode=1;mode<=2;mode=mode+1)begin
            reset_job;begin_job;preload;
            for(n=0;n<4;n=n+1)begin layer_start(n);i_controller_busy=0;i_compute_done=1;i_output_done=1;tick;i_compute_done=0;i_output_done=0;end
            runtime_write(mode);if(o_error_code!=(mode==1?10:11) || !o_runtime_error || o_done)$fatal(1,"GP write error diagnosis");checks=checks+1;
        end
        // All 256 cache entries are loaded through real GP beats and dispatched with same-index comparison.
        reset_job;memory[5]=256;memory[8]=8256;memory[13]=16448;i_model_bytes=16448;
        for(n=0;n<256;n=n+1)begin
            for(j=0;j<8;j=j+1)begin memory[16+n*8+j]=original[16+j];memory[2064+n*8+j]=original[48+j];end
            memory[23+n*8]=(original[23]&32'hfffff00f)|(n<<4);
            memory[2069+n*8]=(original[53]&32'hffffff7f)|(n==255?128:0);
        end
        begin_job;preload;
        for(n=0;n<256;n=n+1)begin layer_start(n);i_controller_busy=0;i_compute_done=1;i_output_done=1;tick;i_compute_done=0;i_output_done=0;end
        runtime_write(0);max_layers=starts;if(max_layers!=256)$fatal(1,"cache capacity");checks=checks+1;
        reset_job;begin_job;read_packet(0);i_ce=0;i_soft_reset=1;tick;i_soft_reset=0;i_ce=1;tick;
        if(!o_start_ready || o_error || o_done)$fatal(1,"soft reset ce=0");checks=checks+1;
        reads=0;
        begin_job;preload;layer_start(0);#2;i_rstn=0;#1;
        if(o_layer_start || o_read_cmd_valid || o_write_cmd_valid || o_done || o_error)$fatal(1,"async reset publication");checks=checks+1;
        test_done=1;$display("PASS D4 control checks=%0d capacity=%0d",checks,max_layers);$finish;
    end
    initial begin #3000000;test_failed=1;$fatal(1,"D4 control watchdog checks=%0d",checks);end
endmodule
