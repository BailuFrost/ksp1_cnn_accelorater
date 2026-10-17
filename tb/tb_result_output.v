`timescale 1ns / 1ps
`include "output_count.vh"
// 实际B5+双FIFO自检，期望值由独立标量模型生成。
module tb_result_output;
    reg clk=1'b0, rst_n=1'b0, bundle_valid=1'b0;
    reg spatial_ready=1'b0, bypass_ready=1'b0;
    reg [10496:0] stimulus=10497'd0;
    reg [10496:0] vectors [0:`OUTPUT_BUNDLES-1];
    reg [67:0] expected_spatial [0:`OUTPUT_SPATIAL_BEATS-1];
    reg [67:0] expected_bypass [0:`OUTPUT_BYPASS_BEATS-1];
    wire bundle_ready,busy,fifo_full;
    wire spatial_valid,bypass_valid,spatial_full,bypass_full,spatial_empty,bypass_empty;
    wire [63:0] spatial_data,bypass_data;
    wire [3:0] spatial_mask,bypass_mask;
    wire [9:0] spatial_count,bypass_count;
    reg test_done=1'b0,test_failed=1'b0;
    reg held_spatial=1'b0,held_bypass=1'b0,held_packer=1'b0,held_bundle=1'b0;
    reg [67:0] saved_spatial,saved_bypass;
    reg [68:0] saved_packer;
    reg [10496:0] saved_bundle;
    reg [3:0] seen_modes=4'd0;
    integer item=0,phase=0,cycles=0,bundles=0;
    integer spatial_writes=0,bypass_writes=0,spatial_reads=0,bypass_reads=0;
    integer blocked_spatial=0,blocked_bypass=0,bundle_stalls=0;
    integer simultaneous_spatial=0,simultaneous_bypass=0;
    integer expected_spatial_count=0,expected_bypass_count=0;
    integer max_spatial=0,max_bypass=0,trace_file;
    reg release_spatial=1'b0,release_bypass=1'b0;
    reg clock_enable=1'b1;
    integer async_reset_checks=0;

    result_output dut (
        .i_clk(clk),.i_rstn(rst_n),.i_bundle_valid(bundle_valid),.o_bundle_ready(bundle_ready),
        .i_bundle_data(stimulus[5183:0]),.i_bias_data(stimulus[10367:5184]),
        .i_lane_mask(stimulus[10475:10368]),.i_mode(stimulus[10477:10476]),
        .i_spatial_index(stimulus[10485:10478]),.i_first_tile(stimulus[10486]),.i_last_tile(stimulus[10487]),
        .i_right_shift(stimulus[10493:10488]),.i_relu(stimulus[10494]),.o_busy(busy),.o_fifo_full(fifo_full),
        .o_spatial_fifo_valid(spatial_valid),.i_spatial_fifo_ready(spatial_ready),.o_spatial_fifo_data(spatial_data),
        .o_spatial_fifo_mask(spatial_mask),.o_spatial_fifo_full(spatial_full),.o_spatial_fifo_empty(spatial_empty),
        .o_spatial_fifo_count(spatial_count),.o_bypass_fifo_valid(bypass_valid),.i_bypass_fifo_ready(bypass_ready),
        .o_bypass_fifo_data(bypass_data),.o_bypass_fifo_mask(bypass_mask),.o_bypass_fifo_full(bypass_full),
        .o_bypass_fifo_empty(bypass_empty),.o_bypass_fifo_count(bypass_count)
    );
    always #5 begin
        if (clock_enable) clk=~clk;
    end

    initial begin
        $readmemh("output_bundles.mem",vectors);
        $readmemh("output_spatial.mem",expected_spatial);
        $readmemh("output_bypass.mem",expected_bypass);
        trace_file=$fopen("output_trace.csv","w");
        if (!trace_file) begin test_failed=1'b1;$fatal(1,"C3 trace open failed");end
        $fdisplay(trace_file,"fclk,phase,bundle,bundle_ready,busy,spatial_count,bypass_count,spatial_ready,bypass_ready,spatial_written,bypass_written,spatial_consumed,bypass_consumed");

        // 两队列均非空且packer在途时复位，随后主流不能泄漏旧结果。
        repeat(2) @(negedge clk);
        @(posedge clk);rst_n<=1'b1;
        @(negedge clk);stimulus=vectors[0];bundle_valid=1'b1;
        @(posedge clk);
        if (!bundle_ready) begin test_failed=1'b1;$fatal(1,"C3 reset fixture spatial refused");end
        @(negedge clk);bundle_valid=1'b0;
        while (busy) @(negedge clk);
        stimulus=vectors[258];bundle_valid=1'b1;
        @(posedge clk);
        if (!bundle_ready) begin test_failed=1'b1;$fatal(1,"C3 reset fixture bypass refused");end
        @(negedge clk);bundle_valid=1'b0;
        // 当前B5在E1准备、E2起入队，等至两项实际写入再构造在途复位。
        repeat(3) begin @(posedge clk);#1;end
        if (spatial_count!=2 || bypass_count!=2 || !busy) begin
            test_failed=1'b1;$fatal(1,"C3 reset fixture missing queued/inflight data");
        end
        @(negedge clk);clock_enable=1'b0;#2;rst_n=1'b0;#1;
        if (!spatial_empty || !bypass_empty || spatial_count!=0 || bypass_count!=0 ||
            spatial_valid || bypass_valid || busy || bundle_ready || dut.flag_packer_valid || dut.flag_packer_ready) begin
            test_failed=1'b1;$fatal(1,"C3 stopped-clock async reset did not abort both FIFOs and packer");
        end
        async_reset_checks=async_reset_checks+1;
        bundle_valid=1'b0;
        #10;
        if (clk || spatial_valid || bypass_valid || busy) begin
            test_failed=1'b1;$fatal(1,"C3 reset requires a clock edge");
        end
        clock_enable=1'b1;
        @(posedge clk);rst_n<=1'b1;
        @(negedge clk);

        while (item<`OUTPUT_BUNDLES || busy || !spatial_empty || !bypass_empty) begin
            if (item<`OUTPUT_BUNDLES) begin stimulus=vectors[item];bundle_valid=1'b1;end
            else bundle_valid=1'b0;
            // 保留前一phase读口直到packer排空，同时提前改变pending bundle模式。
            if (!busy && stimulus[10496:10495]>phase) phase=stimulus[10496:10495];
            if (blocked_spatial>=3) release_spatial=1'b1;
            if (blocked_bypass>=3) release_bypass=1'b1;
            spatial_ready=(phase==0 && release_spatial) || (phase==2 && cycles%5<2);
            bypass_ready=(phase==1 && release_bypass && cycles%5<2) || (phase==2 && cycles%5<2);
            @(posedge clk);
            if (busy && bundle_ready) begin test_failed=1'b1;$fatal(1,"C3 accepted while bundle busy");end
            if (fifo_full !== (busy ? (dut.flag_packer_bypass ? bypass_full : spatial_full) :
                                     (stimulus[10477] ? bypass_full : spatial_full))) begin
                test_failed=1'b1;$fatal(1,"C3 selected FIFO full does not follow latched route");
            end
            if (held_bundle && (!bundle_valid || stimulus!==saved_bundle)) begin
                test_failed=1'b1;$fatal(1,"C3 pending upstream bundle changed");
            end
            held_bundle=bundle_valid && !bundle_ready;saved_bundle=stimulus;
            if (bundle_valid && !bundle_ready) bundle_stalls=bundle_stalls+1;
            if (bundle_valid && bundle_ready) begin
                seen_modes[stimulus[10477:10476]]=1'b1;bundles=bundles+1;item=item+1;
            end
            if (held_spatial && (!spatial_valid || {spatial_mask,spatial_data}!==saved_spatial)) begin
                test_failed=1'b1;$fatal(1,"C3 stalled spatial head changed");
            end
            if (held_bypass && (!bypass_valid || {bypass_mask,bypass_data}!==saved_bypass)) begin
                test_failed=1'b1;$fatal(1,"C3 stalled bypass head changed");
            end
            if (held_packer && (!dut.flag_packer_valid || {dut.flag_packer_bypass,dut.flag_quantized_mask,dut.quantized_data}!==saved_packer)) begin
                test_failed=1'b1;$fatal(1,"C3 stalled serializer changed");
            end
            held_spatial=spatial_valid && !spatial_ready;saved_spatial={spatial_mask,spatial_data};
            held_bypass=bypass_valid && !bypass_ready;saved_bypass={bypass_mask,bypass_data};
            held_packer=dut.flag_packer_valid && !dut.flag_packer_ready;
            saved_packer={dut.flag_packer_bypass,dut.flag_quantized_mask,dut.quantized_data};
            if (held_packer) begin
                if (dut.flag_packer_bypass) blocked_bypass=blocked_bypass+1;
                else blocked_spatial=blocked_spatial+1;
            end
            // 八lane恰好填满FIFO时，反压发生在bundle入口。
            if(bundle_valid && !bundle_ready && !busy)begin
                if(stimulus[10477] && bypass_full) blocked_bypass=blocked_bypass+1;
                if(!stimulus[10477] && spatial_full) blocked_spatial=blocked_spatial+1;
            end
            if (dut.flag_packer_valid && dut.flag_packer_ready) begin
                if (dut.flag_packer_bypass) begin
                    if (bypass_writes>=`OUTPUT_BYPASS_BEATS || {dut.flag_quantized_mask,dut.quantized_data}!==expected_bypass[bypass_writes]) begin
                        test_failed=1'b1;$fatal(1,"C3 bypass FIFO write mismatch %0d",bypass_writes);
                    end
                    bypass_writes=bypass_writes+1;expected_bypass_count=expected_bypass_count+1;
                    if (bypass_valid && bypass_ready) simultaneous_bypass=simultaneous_bypass+1;
                end else begin
                    if (spatial_writes>=`OUTPUT_SPATIAL_BEATS || {dut.flag_quantized_mask,dut.quantized_data}!==expected_spatial[spatial_writes]) begin
                        test_failed=1'b1;$fatal(1,"C3 spatial FIFO write mismatch %0d",spatial_writes);
                    end
                    spatial_writes=spatial_writes+1;expected_spatial_count=expected_spatial_count+1;
                    if (spatial_valid && spatial_ready) simultaneous_spatial=simultaneous_spatial+1;
                end
            end
            if (spatial_valid && spatial_ready) begin
                if (spatial_reads>=`OUTPUT_SPATIAL_BEATS || {spatial_mask,spatial_data}!==expected_spatial[spatial_reads]) begin
                    test_failed=1'b1;$fatal(1,"C3 spatial output mismatch %0d",spatial_reads);
                end
                spatial_reads=spatial_reads+1;expected_spatial_count=expected_spatial_count-1;
            end
            if (bypass_valid && bypass_ready) begin
                if (bypass_reads>=`OUTPUT_BYPASS_BEATS || {bypass_mask,bypass_data}!==expected_bypass[bypass_reads]) begin
                    test_failed=1'b1;$fatal(1,"C3 bypass output mismatch %0d",bypass_reads);
                end
                bypass_reads=bypass_reads+1;expected_bypass_count=expected_bypass_count-1;
            end
            #1;cycles=cycles+1;
            if (spatial_count!==expected_spatial_count || bypass_count!==expected_bypass_count ||
                spatial_full!==(spatial_count==512) || bypass_full!==(bypass_count==512) ||
                spatial_empty!==(spatial_count==0) || bypass_empty!==(bypass_count==0)) begin
                test_failed=1'b1;$fatal(1,"C3 occupancy mismatch cycle %0d",cycles);
            end
            if (spatial_count>max_spatial) max_spatial=spatial_count;
            if (bypass_count>max_bypass) max_bypass=bypass_count;
            $fdisplay(trace_file,"%0d,%0d,%0d,%b,%b,%0d,%0d,%b,%b,%0d,%0d,%0d,%0d",cycles,phase,item,
                bundle_ready,busy,spatial_count,bypass_count,spatial_ready,bypass_ready,
                spatial_writes,bypass_writes,spatial_reads,bypass_reads);
            @(negedge clk);
        end
        if (bundles!=`OUTPUT_BUNDLES || spatial_reads!=`OUTPUT_SPATIAL_BEATS || bypass_reads!=`OUTPUT_BYPASS_BEATS ||
            spatial_writes!=spatial_reads || bypass_writes!=bypass_reads || seen_modes!=4'b1111 ||
            max_spatial!=512 || max_bypass!=512 || blocked_spatial<3 || blocked_bypass<3 ||
            simultaneous_spatial==0 || simultaneous_bypass==0 || bundle_stalls==0) begin
            test_failed=1'b1;$fatal(1,"C3 coverage/count check incomplete");
        end
        $fclose(trace_file);test_done=1'b1;
        $display("PASS C3 cycles=%0d bundles=%0d writes/reads=%0d/%0d full=%0d/%0d blocked=%0d/%0d simultaneous=%0d/%0d upstream_stalls=%0d reset_aborted_fifo_beats=5",
            cycles,bundles,spatial_reads,bypass_reads,max_spatial,max_bypass,blocked_spatial,blocked_bypass,
            simultaneous_spatial,simultaneous_bypass,bundle_stalls);
        $finish;
    end
    initial begin #1000000;test_failed=1'b1;$fatal(1,"C3 watchdog timeout");end
endmodule
