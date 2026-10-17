`timescale 1ns / 1ps

// D0子系统：实际Feature_cmd及C0，HP0为带固定反压的Full DataMover事务模型。
module tb_feature_cmd;
    reg clk=0;
    always #5 clk=~clk;
    reg rstn=0, ce=1, soft_reset=0, start=0;
    reg [255:0]base_instruction=0, extension=0;
    reg scan_req=0, update_req=0, scan_finish=0;
    reg [9:0]group_index=0;
    reg [7:0]tile_index=0;
    reg [15:0]tile_base=0, update_row=3;
    reg [11:0]update_col=0;
    reg [1:0]update_bank=0;
    wire start_ready, scan_ready, update_ready, feature_ready, update_done, scan_done, busy, error;
    wire [9:0]response_group;
    wire [7:0]response_tile;
    wire [3:0]error_code;
    wire cmd_valid;
    reg cmd_ready=0;
    wire [71:0]cmd_data;
    reg data_valid=0, data_last=0, status_valid=0;
    reg [63:0]data=0;
    reg [7:0]keep=8'hff, status=8'h80;
    wire data_ready, status_ready, wr_valid, wr_safe, wr_ready;
    wire [1:0]wr_bank;
    wire [11:0]wr_addr;
    wire [63:0]wr_data;
    reg rd_valid=0;
    reg [12:0]rd_addr=0;
    wire rd_ready, out_valid;
    wire [95:0]out_data;
    reg [71:0]commands[0:18];
    reg [141:0]words[0:32];
    reg [511:0]configs[0:4];
    reg [63:0]memory[0:2][0:4095];
    integer commands_seen=0, writes=0, updates=0, scans=0, cycles=0;
    integer pauses=0, collisions=0, reset_checks=0, error_checks=0, cache_reads=0;
    integer trace, k, j, beat_count, expected_commands, expected_writes;
    reg test_done=0, test_failed=0;
    reg compare_vectors=1;
    integer total_commands=0, total_writes=0, ps_field_checks=0;
    reg [71:0]held_command;
    reg [63:0]held_word;

    feature_cmd dut(
        .i_clk(clk), .i_rstn(rstn), .i_ce(ce), .i_soft_reset(soft_reset),
        .i_start(start), .i_base_instruction(base_instruction), .i_extension(extension),
        .o_start_ready(start_ready), .i_scan_req(scan_req), .o_scan_ready(scan_ready),
        .i_group_index(group_index), .i_tile_index(tile_index), .i_tile_channel_base(tile_base),
        .i_update_req(update_req), .o_update_ready(update_ready), .i_update_row(update_row),
        .i_update_col(update_col), .i_update_bank(update_bank), .i_scan_finish(scan_finish),
        .o_feature_ready(feature_ready), .o_update_done(update_done), .o_scan_done(scan_done),
        .o_group_index(response_group), .o_tile_index(response_tile), .o_busy(busy),
        .o_error(error), .o_error_code(error_code), .o_cmd_valid(cmd_valid),
        .i_cmd_ready(cmd_ready), .o_cmd_data(cmd_data), .i_data_valid(data_valid),
        .o_data_ready(data_ready), .i_data(data), .i_data_keep(keep), .i_data_last(data_last),
        .i_status_valid(status_valid), .o_status_ready(status_ready), .i_status(status),
        .o_wr_valid(wr_valid), .i_wr_ready(wr_ready), .o_wr_safe(wr_safe),
        .o_wr_bank(wr_bank), .o_wr_addr(wr_addr), .o_wr_data(wr_data)
    );
    feature_buffer cache(
        .i_clk(clk), .i_rstn(rstn), .i_ce(ce), .i_wr_valid(wr_valid), .i_wr_safe(wr_safe),
        .i_wr_bank(wr_bank), .i_wr_addr(wr_addr), .i_wr_data(wr_data), .o_wr_ready(wr_ready),
        .i_rd_valid(rd_valid), .i_rd_addr(rd_addr), .o_rd_ready(rd_ready),
        .o_out_valid(out_valid), .o_out_data(out_data)
    );

    // Python向量比较及实际事件CSV；异常立即终止，防止误报PASS。
    always @(posedge clk) begin
        cycles=cycles+1;
        if(cycles>4000) $fatal(1,"D0 timeout state=%d cmd=%d write=%d",dut.state_current,commands_seen,writes);
        if(rstn && wr_valid && wr_ready) begin
            if(compare_vectors && (writes>=33 || {wr_bank,wr_addr,wr_data} !== {words[writes][141:128],words[writes][63:0]}))
                $fatal(1,"write %d got bank=%d addr=%d data=%h expected=%h",writes,wr_bank,wr_addr,wr_data,words[writes]);
            memory[wr_bank][wr_addr]=wr_data;
            if(compare_vectors) writes=writes+1;
            total_writes=total_writes+1;
        end
        if(rstn && cmd_valid && cmd_ready) begin
            if(compare_vectors && (commands_seen>=19 || cmd_data !== commands[commands_seen]))
                $fatal(1,"command %d got=%h expected=%h",commands_seen,cmd_data,commands[commands_seen]);
            if(compare_vectors) commands_seen=commands_seen+1;
            total_commands=total_commands+1;
        end
        if(update_done) updates=updates+1;
        if(scan_done) scans=scans+1;
        if(!ce && (wr_valid || data_ready || status_ready || scan_ready || update_ready))
            $fatal(1,"ce pause consumed cache/data/status/request");
        $fwrite(trace,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
            cycles,ce,cmd_valid&&cmd_ready,wr_valid&&wr_ready,status_valid&&status_ready,
            feature_ready,update_done,scan_done,wr_bank,wr_addr,response_group,response_tile,error_code);
    end

    // 不参与RTL门禁的验证task允许时序控制；每一项检查真实接口结果。
    task tick;
        begin @(posedge clk); #1; @(negedge clk); end
    endtask
    task configure;
        input integer config_index;
        begin
            #1;
            if(!start_ready) $fatal(1,"configuration not ready");
            {extension,base_instruction}=configs[config_index];
            start=1; tick; start=0; #1; #1;
            if(error) $fatal(1,"legal A3 instruction rejected code=%d",error_code);
        end
    endtask
    task request_scan;
        input [9:0]g;
        input [7:0]t;
        begin
            group_index=g; tile_index=t; tile_base={t,9'd0};
            if(!scan_ready) $fatal(1,"scan request not ready");
            scan_req=1; tick; scan_req=0;
            if(feature_ready) $fatal(1,"old ready leaked into new scan");
        end
    endtask
    task service;
        input integer count;
        begin
            for(k=0;k<count;k=k+1) begin
                while(!cmd_valid) tick;
                held_command=cmd_data;
                // 命令ready反压以及ce暂停时valid/data稳定。
                tick; ce=0; tick;
                if(!cmd_valid || cmd_data!==held_command) $fatal(1,"command not held during pause");
                cmd_ready=1; tick; cmd_ready=0;
                if(cmd_valid) $fatal(1,"command handshake lost while ce=0");
                ce=1; pauses=pauses+1;
                beat_count=held_command[22:0]/8;
                // 偶数命令状态先到，奇数命令状态后到。
                if(k%2==0) begin
                    status_valid=1; tick; status_valid=0;
                    if(feature_ready) $fatal(1,"status alone produced ready");
                end
                for(j=0;j<beat_count;j=j+1) begin
                    data=words[writes][127:64]; data_last=(j==beat_count-1); data_valid=1;
                    // 真实C0同word读冲突反压，再统一暂停，最后恢复写。
                    rd_addr={wr_addr,1'b0}; rd_valid=1; #1;
                    if(data_ready || wr_ready) $fatal(1,"C0 read collision not backpressured");
                    held_word=wr_data; tick; collisions=collisions+1;
                    rd_valid=0; ce=0; tick;
                    if(wr_data!==held_word) $fatal(1,"paused payload changed");
                    ce=1; pauses=pauses+1;
                    #1; if(!data_ready) $fatal(1,"C0 write did not resume");
                    tick; data_valid=0;
                end
                if(k%2==1) begin
                    tick; tick;
                    if(feature_ready) $fatal(1,"last data alone produced ready");
                    status_valid=1; tick; status_valid=0;
                end
                tick; tick;
            end
        end
    endtask
    task read_cache;
        input integer word_count;
        input integer valid_banks;
        reg [95:0]expected;
        integer q, h, b;
        begin
            for(q=0;q<word_count;q=q+1) begin
                for(h=0;h<2;h=h+1) begin
                    rd_addr=q*2+h; rd_valid=1;
                    tick; rd_valid=0;
                    for(b=0;b<valid_banks;b=b+1) begin
                        expected[b*32+:32]=memory[b][q] >> (h*32);
                        if(!out_valid || out_data[b*32+:32]!==expected[b*32+:32])
                            $fatal(1,"C0 readback bank=%d word=%d half=%d",b,q,h);
                    end
                    cache_reads=cache_reads+1;
                end
            end
        end
    endtask
    task finish_scan;
        begin
            while(!feature_ready) tick;
            if(response_group!==group_index || response_tile!==tile_index) $fatal(1,"response tags mismatched");
            scan_finish=1; tick; scan_finish=0;
            if(!scan_done || feature_ready || busy) $fatal(1,"scan completion contract");
            tick;
        end
    endtask
    task sync_clear;
        reg previous_error;
        begin
            // 模型已无在途事务；soft_reset不连接C0异步复位。
            previous_error=error; soft_reset=1; #1;
            if(error!==previous_error || !rstn) $fatal(1,"soft reset changed state before clock edge");
            tick; soft_reset=0; tick;
            if(error || feature_ready || !start_ready || scan_ready) $fatal(1,"soft reset contract");
        end
    endtask

    initial begin
        trace=$fopen("d0_trace.csv","w");
        $fwrite(trace,"cycle,ce,command,write,status,ready,update_done,scan_done,bank,word,group,tile,error\n");
        $readmemh("d0_commands.mem",commands); $readmemh("d0_words.mem",words);
        $readmemh("d0_configs.mem",configs);
        #2; rstn=1; #1; rstn=0; #2;
        if(cmd_valid || wr_valid || feature_ready) $fatal(1,"idle async reset");
        reset_checks=reset_checks+1;
        @(posedge clk); #1; rstn=1; @(negedge clk);
        configure(0); request_scan(0,0); service(6);
        while(!feature_ready) tick;
        if(commands_seen!=6 || writes!=12) $fatal(1,"initial three rows counts");
        read_cache(4,3);
        // 请求线上的坐标不是授权；不拉update_req绝不覆盖。
        expected_commands=commands_seen; expected_writes=writes;
        tick; tick; tick;
        if(commands_seen!=expected_commands || writes!=expected_writes) $fatal(1,"unauthorized update");
        update_col=0; update_req=1; tick; update_req=0; service(1);
        while(!feature_ready) tick;
        read_cache(4,3);
        update_col=1; update_req=1; tick; update_req=0; service(1);
        while(!feature_ready) tick;
        read_cache(4,3); finish_scan;
        // 相同层新group无需PS参与，旧覆盖行被首三行重装替换。
        request_scan(341,0); service(6); while(!feature_ready) tick;
        if(response_group!=341) $fatal(1,"D2 ten-bit group response truncated");
        read_cache(4,3); finish_scan;
        configure(2); request_scan(256,1); service(3); while(!feature_ready) tick;
        read_cache(1,3); finish_scan;
        configure(3); request_scan(1023,1); service(1); while(!feature_ready) tick;
        read_cache(1,1); finish_scan;
        // 配置地址不对齐在发DMA之前拒绝。
        {extension,base_instruction}=configs[4]; base_instruction[0]=1; start=1; tick; start=0; #1;
        if(!error || error_code!=1 || cmd_valid) $fatal(1,"invalid instruction accepted");
        error_checks=error_checks+1; sync_clear;
        // 输入tile标签和base不一致不得发DMA。
        configure(2); tile_index=1; tile_base=0; scan_req=1; tick; scan_req=0;
        if(!error || error_code!=2 || cmd_valid) $fatal(1,"invalid tile accepted");
        error_checks=error_checks+1; sync_clear;
        // 运行中暂停，两个时钟沿之间拉低硬复位，必须立即撤销有效资格。
        configure(4); request_scan(4,0); ce=0; #2; rstn=0; #1;
        if(cmd_valid || data_ready || status_ready || wr_valid || feature_ready || busy) $fatal(1,"busy async reset");
        reset_checks=reset_checks+1;
        @(posedge clk); #1; rstn=1; @(negedge clk); ce=1;
        configure(4); request_scan(4,0); service(1); while(!feature_ready) tick;
        read_cache(1,1); finish_scan;
        if(commands_seen!=19 || writes!=33 || updates!=2 || scans!=5) $fatal(1,"D0 final successful counts");
        compare_vectors=0;
        // 静态字段与几何故意不一致：采用软件结果，不触发旧交叉校验。
        {extension,base_instruction}=configs[0];
        base_instruction[87:64]=24'd16;
        base_instruction[111:88]=24'd7;
        base_instruction[135:112]=24'd20;
        start=1; tick; start=0; #1;
        if(error || !scan_ready || dut.reg_row_bytes!=32'd40 || dut.input_limit_address!=33'h005000020)
            $fatal(1,"software transfer count/row stride not used directly");
        ps_field_checks=ps_field_checks+1; sync_clear;
        // FC行跨度仍是单展平向量，空间F_CAL_SWITCH不得改变矩阵寻址。
        {extension,base_instruction}=configs[3]; base_instruction[135:112]=24'd1024;
        start=1; tick; start=0; #1;
        if(error || dut.reg_row_bytes!=32'd1032) $fatal(1,"FC flattened row stride changed");
        ps_field_checks=ps_field_checks+1; sync_clear;
        // 使用F_TRANS_NUM检查DDR末址：恰好到分区末端可接受，多八字节拒绝。
        {extension,base_instruction}=configs[0];
        base_instruction[31:0]=32'h10fffff8; base_instruction[87:64]=24'd4;
        start=1; tick; start=0; #1;
        if(error || !scan_ready || dut.input_limit_address!=33'h011000000) $fatal(1,"DDR exact limit rejected");
        ps_field_checks=ps_field_checks+1; sync_clear;
        base_instruction[87:64]=24'd8; start=1; tick; start=0; #1;
        if(!error || error_code!=1 || cmd_valid) $fatal(1,"software DDR range overflow accepted");
        error_checks=error_checks+1; sync_clear;
        // 故意绕过软件预检注入过宽指令：RTL不再重复容量判断，不握手DMA。
        {extension,base_instruction}=configs[0]; base_instruction[147:136]=12'd4095;
        start=1; tick; start=0; #1; request_scan(0,0);
        if(error || !cmd_valid) $fatal(1,"removed hardware capacity check still blocks scan");
        ps_field_checks=ps_field_checks+1; sync_clear;
        // 数据状态错误路径不计入成功向量；再次发一条命令但拒绝写入。
        configure(4); request_scan(4,0); cmd_ready=1; tick; cmd_ready=0;
        status_valid=1; status=8'h90; data_valid=1; data_last=1; data=64'hbad; #1;
        if(wr_valid) $fatal(1,"error status allowed write");
        tick; status_valid=0; data_valid=0;
        if(!error || error_code!=5 || feature_ready || cmd_valid || writes!=33) $fatal(1,"status error not latched");
        error_checks=error_checks+1; sync_clear;
        configure(4); request_scan(4,0); cmd_ready=1; tick; cmd_ready=0;
        data_valid=1; data_last=0; #1;
        if(wr_valid) $fatal(1,"bad TLAST allowed write");
        tick; data_valid=0;
        if(!error || error_code!=4 || writes!=33) $fatal(1,"frame error not latched");
        error_checks=error_checks+1; sync_clear;
        // 覆盖请求的非法物理bank在DMA前拒绝。
        configure(4); request_scan(4,0); cmd_ready=1; tick; cmd_ready=0;
        data_valid=1; data_last=1; data=64'd0; tick; data_valid=0;
        status=8'h80; status_valid=1; tick; status_valid=0; tick; tick;
        while(!feature_ready) tick;
        update_bank=3; update_req=1; tick; update_req=0;
        if(!error || error_code!=3 || cmd_valid) $fatal(1,"invalid update accepted");
        error_checks=error_checks+1;
        if(ps_field_checks!=4 || error_checks!=6) $fatal(1,"software field/boundary coverage mismatch");
        $display("PASS D0: 19 oracle commands / 33 oracle writes, 2 updates, 5 scans, %d reads",cache_reads);
        test_done=1; $fclose(trace); $finish;
    end
endmodule
