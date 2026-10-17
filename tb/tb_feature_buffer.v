`timescale 1ns / 1ps
`include "feature_count.vh"
// 对Python逐拍oracle执行实际RTL比较，包括暂停时的保持数据。
module tb_feature_buffer;
	reg clk = 1'b0;
	reg rst_n;
	reg ce;
	reg wr_valid;
	reg wr_safe;
	reg [1:0] wr_bank;
	reg [11:0] wr_addr;
	reg [63:0] wr_data;
	reg rd_valid;
	reg [12:0] rd_addr;
	wire wr_ready;
	wire rd_ready;
	wire out_valid;
	wire [95:0] out_data;
	reg [194:0] vectors [0:`FEATURE_VECTOR_COUNT-1];
	reg [194:0] current_vector;
	reg test_done = 1'b0;
	reg test_failed = 1'b0;
	integer cycles = 0;
	integer writes = 0;
	integer reads = 0;
	integer blocked_writes = 0;
	integer async_reset_checks = 0;
	integer restart_reads = 0;
	reg [95:0] held_data;
	integer index;
	integer trace_file;

	feature_buffer u_feature_buffer (
		.i_clk(clk), .i_rstn(rst_n), .i_ce(ce),
		.i_wr_valid(wr_valid), .i_wr_safe(wr_safe), .i_wr_bank(wr_bank),
		.i_wr_addr(wr_addr), .i_wr_data(wr_data), .o_wr_ready(wr_ready),
		.i_rd_valid(rd_valid), .i_rd_addr(rd_addr), .o_rd_ready(rd_ready),
		.o_out_valid(out_valid), .o_out_data(out_data)
	);

	always #5 clk = ~clk;

	initial begin
		$readmemh("feature_vectors.mem", vectors);
		trace_file = $fopen("feature_trace.csv", "w");
		if (!trace_file) begin
			test_failed = 1'b1;
			$fatal(1, "Cannot open C0 trace file");
		end
		$fwrite(trace_file, "cycle,ce,wr_valid,wr_safe,wr_bank,wr_addr,wr_ready,rd_valid,rd_addr,out_valid,out_data\n");
		for (index = 0; index < `FEATURE_VECTOR_COUNT; index = index + 1) begin
			@(negedge clk);
			current_vector = vectors[index];
			{rd_addr, rd_valid, wr_data, wr_addr, wr_bank, wr_safe, wr_valid, ce, rst_n}
				= current_vector[95:0];
			#1;
			if (wr_ready !== current_vector[96] || rd_ready !== current_vector[97]) begin
				test_failed = 1'b1;
				$fatal(1, "C0 cycle %0d readiness actual=%b/%b expected=%b/%b",
					index, wr_ready, rd_ready, current_vector[96], current_vector[97]);
			end
			if (wr_valid && wr_ready) begin
				writes = writes + 1;
			end
			if (rd_valid && rd_ready) begin
				reads = reads + 1;
			end
			if (wr_valid && !wr_ready) begin
				blocked_writes = blocked_writes + 1;
			end
			@(posedge clk);
			#1;
			cycles = cycles + 1;
			if (out_valid !== current_vector[98]) begin
				test_failed = 1'b1;
				$fatal(1, "C0 cycle %0d response valid mismatch", index);
			end
			if (out_valid && out_data !== current_vector[194:99]) begin
				test_failed = 1'b1;
				$fatal(1, "C0 cycle %0d data actual=%h expected=%h", index, out_data, current_vector[194:99]);
			end
			$fwrite(trace_file, "%0d,%b,%b,%b,%0d,%0d,%b,%b,%0d,%b,%h\n",
				index, ce, wr_valid, wr_safe, wr_bank, wr_addr, wr_ready, rd_valid, rd_addr, out_valid, out_data);
		end
		$fclose(trace_file);
		// 末地址高半word响应在暂停期间遇到非沿复位，必须立即撤销。
		@(negedge clk);
		ce = 1'b1;
		rd_valid = 1'b1;
		rd_addr = 13'd8191;
		wr_valid = 1'b0;
		@(posedge clk); #1;
		if (!out_valid || out_data !== 96'h0000ffffdeadbeef80007fff) begin
			test_failed = 1'b1;
			$fatal(1, "C0 pre-reset response");
		end
		held_data = out_data;
		@(negedge clk);
		ce = 1'b0;
		wr_valid = 1'b1;
		wr_safe = 1'b1;
		wr_bank = 2'd0;
		wr_addr = 12'd4095;
		wr_data = 64'hffffffffffffffff;
		@(posedge clk); #1;
		if (!out_valid || out_data !== held_data || rd_ready || wr_ready) begin
			test_failed = 1'b1;
			$fatal(1, "C0 held response while paused");
		end
		@(negedge clk); #2; rst_n = 1'b0; #1;
		if (out_valid || wr_ready || rd_ready) begin
			test_failed = 1'b1;
			$fatal(1, "C0 async reset did not clear before rising edge");
		end
		async_reset_checks = async_reset_checks + 1;
		// 脏请求在复位覆盖的时钟沿不得读写RAM；释放在上升沿NBA完成。
		@(posedge clk);
		@(negedge clk);
		wr_valid = 1'b0;
		rd_valid = 1'b0;
		@(posedge clk); rst_n <= 1'b1;
		@(posedge clk); #1;
		if (out_valid || rd_ready || wr_ready) begin
			test_failed = 1'b1;
			$fatal(1, "C0 reset release while paused");
		end
		// 诊断性重读验证RAM未清零且未被复位期间脏请求污染。
		@(negedge clk); ce = 1'b1; rd_valid = 1'b1;
		@(posedge clk); #1;
		if (!out_valid || out_data !== held_data) begin
			test_failed = 1'b1;
			$fatal(1, "C0 RAM preservation across reset");
		end
		// 新任务重新初装三个bank并检查两个半word，不消费未装载数据。
		for (index = 0; index < 3; index = index + 1) begin
			@(negedge clk);
			rd_valid = 1'b0;
			wr_valid = 1'b1;
			wr_bank = index;
			wr_addr = 12'd0;
			wr_data = 64'h8000ffff7fff0000 + index;
			#1;
			if (!wr_ready) begin
				test_failed = 1'b1;
				$fatal(1, "C0 restart initial load rejected");
			end
			@(posedge clk); #1;
		end
		for (index = 0; index < 2; index = index + 1) begin
			@(negedge clk);
			wr_valid = 1'b0;
			rd_valid = 1'b1;
			rd_addr = index;
			@(posedge clk); #1;
			if (!out_valid || out_data !== (index == 0 ?
				96'h7fff00027fff00017fff0000 : 96'h8000ffff8000ffff8000ffff)) begin
				test_failed = 1'b1;
				$fatal(1, "C0 restart pair mismatch");
			end
			restart_reads = restart_reads + 1;
		end
		test_done = 1'b1;
		$display("PASS C0 cycles=%0d writes=%0d reads=%0d blocked_writes=%0d async_reset_checks=%0d restart_reads=%0d", cycles, writes, reads, blocked_writes, async_reset_checks, restart_reads);
		$finish;
	end

	// 未完成或死循环也必须失败，不能由Tcl运行超时误判通过。
	initial begin
		#20000;
		test_failed = 1'b1;
		$fatal(1, "C0 watchdog timeout");
	end
endmodule
