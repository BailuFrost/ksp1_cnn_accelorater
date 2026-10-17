`timescale 1ns / 1ps
`include "fout_count.vh"
// 实际C0+C1联合测试：请求标签与同步BRAM输出同沿锁存。
module tb_fout_selector;
	reg clk = 1'b0;
	reg rst_n;
	reg ce;
	reg wr_valid;
	reg wr_safe;
	reg [1:0] wr_bank;
	reg [11:0] wr_addr;
	reg [63:0] wr_data;
	reg request_valid;
	reg [12:0] request_pair;
	reg [1:0] request_mode;
	reg [1:0] request_role;
	reg [2:0] request_rows;
	reg request_column;
	reg [1:0] request_channels;
	wire real_read;
	wire wr_ready;
	wire rd_ready;
	wire cache_valid;
	wire [95:0] cache_data;
	reg response_valid;
	reg [1:0] response_mode;
	reg [1:0] response_role;
	reg [2:0] response_rows;
	reg response_column;
	reg [1:0] response_channels;
	wire out_valid;
	wire [95:0] out_data;
	reg [207:0] vectors [0:`FOUT_VECTOR_COUNT-1];
	reg [207:0] current_vector;
	reg [207:0] previous_vector;
	reg test_done = 1'b0;
	reg test_failed = 1'b0;
	integer cycles = 0;
	integer writes = 0;
	integer reads = 0;
	integer consumed = 0;
	integer paused_valid = 0;
	integer async_reset_checks = 0;
	integer restart_responses = 0;
	reg [95:0] held_data;
	integer index;
	integer trace_file;

	assign real_read = request_valid && request_column && (|request_rows);
	feature_buffer u_feature_buffer (
		.i_clk(clk), .i_rstn(rst_n), .i_ce(ce),
		.i_wr_valid(wr_valid), .i_wr_safe(wr_safe), .i_wr_bank(wr_bank), .i_wr_addr(wr_addr),
		.i_wr_data(wr_data), .o_wr_ready(wr_ready),
		.i_rd_valid(real_read), .i_rd_addr(request_pair), .o_rd_ready(rd_ready),
		.o_out_valid(cache_valid), .o_out_data(cache_data)
	);
	fout_selector u_fout_selector (
		.i_in_valid(response_valid), .i_in_data(cache_data), .i_mode(response_mode),
		.i_row_select(response_role), .i_row_mask(response_rows), .i_column_valid(response_column),
		.i_pair_mask(response_channels), .o_out_valid(out_valid), .o_out_data(out_data)
	);

	always #5 clk = ~clk;

	// 模拟CAL_cmd的读响应标签；暂停时与RAM数据一起保持。
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			response_valid <= 1'b0;
			response_mode <= 2'd0;
			response_role <= 2'd0;
			response_rows <= 3'd0;
			response_column <= 1'b0;
			response_channels <= 2'd0;
		end else if (ce) begin
			response_valid <= request_valid;
			if (request_valid) begin
				response_mode <= request_mode;
				response_role <= request_role;
				response_rows <= request_rows;
				response_column <= request_column;
				response_channels <= request_channels;
			end
		end
	end

	initial begin
		$readmemh("fout_vectors.mem", vectors);
		trace_file = $fopen("fout_trace.csv", "w");
		if (!trace_file) begin
			test_failed = 1'b1;
			$fatal(1, "Cannot open C1 trace file");
		end
		$fwrite(trace_file, "cycle,ce,request_valid,request_role,request_mode,real_read,response_role,response_mode,out_valid,out_data\n");
		for (index = 0; index < `FOUT_VECTOR_COUNT; index = index + 1) begin
			@(negedge clk);
			current_vector = vectors[index];
			{request_channels, request_column, request_rows, request_role, request_mode,
			 request_pair, request_valid, wr_data, wr_addr, wr_bank, wr_safe, wr_valid, ce, rst_n}
				= current_vector[105:0];
			#1;
			// 下一请求已经改变，但当前响应必须仍对应上一次读请求。
			if (index > 0 && rst_n) begin
				previous_vector = vectors[index - 1];
				if (out_valid !== previous_vector[107] || response_role !== previous_vector[205:204]
					|| response_mode !== previous_vector[207:206]) begin
					test_failed = 1'b1;
					$fatal(1, "C1 cycle %0d response changed with next request", index);
				end
				if (out_valid && out_data !== previous_vector[203:108]) begin
					test_failed = 1'b1;
					$fatal(1, "C1 cycle %0d previous response corrupted before consume", index);
				end
			end
			if (!rst_n && (out_valid || cache_valid || response_valid)) begin
				test_failed = 1'b1;
				$fatal(1, "C1 async clear failed before accepting edge");
			end
			if (wr_ready !== current_vector[106] || rd_ready !== (rst_n && ce)) begin
				test_failed = 1'b1;
				$fatal(1, "C1 cycle %0d readiness mismatch", index);
			end
			@(posedge clk);
			if (wr_valid && wr_ready) begin
				writes = writes + 1;
			end
			if (real_read && rd_ready) begin
				reads = reads + 1;
			end
			if (rst_n && ce && out_valid) begin
				consumed = consumed + 1;
			end
			#1;
			cycles = cycles + 1;
			if (!ce && out_valid) begin
				paused_valid = paused_valid + 1;
			end
			if (out_valid !== current_vector[107] || response_role !== current_vector[205:204]
				|| response_mode !== current_vector[207:206]) begin
				test_failed = 1'b1;
				$fatal(1, "C1 cycle %0d valid/tag mismatch", index);
			end
			if ((out_valid || response_role == 2'd3) && out_data !== current_vector[203:108]) begin
				test_failed = 1'b1;
				$fatal(1, "C1 cycle %0d data actual=%h expected=%h", index, out_data, current_vector[203:108]);
			end
			if (cache_valid !== (response_valid && response_column && (|response_rows))) begin
				test_failed = 1'b1;
				$fatal(1, "C1 cycle %0d physical/virtual response mismatch", index);
			end
			$fwrite(trace_file, "%0d,%b,%b,%0d,%0d,%b,%0d,%0d,%b,%h\n", index,
				ce, request_valid, request_role, request_mode, real_read, response_role, response_mode, out_valid, out_data);
		end
		$fclose(trace_file);
		// 建立非零广播响应，再将下一请求标签改为不同模式与角色。
		@(negedge clk);
		ce = 1'b1;
		request_valid = 1'b0;
		wr_valid = 1'b1;
		wr_safe = 1'b1;
		wr_bank = 2'd1;
		wr_addr = 12'd0;
		wr_data = 64'h7fff8000ffff0001;
		@(posedge clk); #1;
		if (!wr_ready) begin
			test_failed = 1'b1;
			$fatal(1, "C1 directed initial load rejected");
		end
		@(negedge clk);
		wr_valid = 1'b0;
		request_valid = 1'b1;
		request_pair = 13'd0;
		request_mode = 2'd2;
		request_role = 2'd1;
		request_rows = 3'b001;
		request_column = 1'b1;
		request_channels = 2'b11;
		@(posedge clk); #1;
		if (!out_valid || out_data !== {3{32'hffff0001}}) begin
			test_failed = 1'b1;
			$fatal(1, "C1 directed broadcast response");
		end
		held_data = out_data;
		@(negedge clk);
		ce = 1'b0;
		request_mode = 2'd1;
		request_role = 2'd0;
		request_pair = 13'd1;
		wr_valid = 1'b1;
		wr_data = 64'd0;
		@(posedge clk); #1;
		if (!out_valid || out_data !== held_data || response_mode !== 2'd2 || response_role !== 2'd1) begin
			test_failed = 1'b1;
			$fatal(1, "C1 paused response changed with dirty next request");
		end
		// 在两个时钟沿之间拉低复位，组合选择器通过源标签立即失效。
		@(negedge clk); #2; rst_n = 1'b0; #1;
		if (out_valid || cache_valid || response_valid || out_data !== 96'd0 ||
			response_role !== 2'd0 || response_mode !== 2'd0 || wr_ready || rd_ready) begin
			test_failed = 1'b1;
			$fatal(1, "C1 async response and tag clear before rising edge");
		end
		async_reset_checks = async_reset_checks + 1;
		@(posedge clk);
		@(negedge clk);
		request_valid = 1'b0;
		wr_valid = 1'b0;
		@(posedge clk); rst_n <= 1'b1;
		@(posedge clk); #1;
		if (out_valid || cache_valid || response_valid || rd_ready) begin
			test_failed = 1'b1;
			$fatal(1, "C1 reset release while paused");
		end
		// 新任务先装载广播源，再验证矩阵模式连续两个pair的响应对齐。
		@(negedge clk);
		ce = 1'b1;
		wr_valid = 1'b1;
		wr_bank = 2'd2;
		wr_data = 64'h80007fff0000ffff;
		@(posedge clk); #1;
		for (index = 0; index < 2; index = index + 1) begin
			@(negedge clk);
			wr_valid = 1'b0;
			request_valid = 1'b1;
			request_mode = 2'd3;
			request_role = 2'd2;
			request_rows = 3'b001;
			request_column = 1'b1;
			request_channels = 2'b11;
			request_pair = index;
			@(posedge clk); #1;
			if (!out_valid || !cache_valid || response_mode !== 2'd3 || response_role !== 2'd2 ||
				out_data !== (index == 0 ? {3{32'h0000ffff}} : {3{32'h80007fff}})) begin
				test_failed = 1'b1;
				$fatal(1, "C1 restart matrix pair or tag mismatch");
			end
			restart_responses = restart_responses + 1;
		end
		test_done = 1'b1;
		$display("PASS C1 cycles=%0d writes=%0d reads=%0d consumed=%0d paused_valid=%0d async_reset_checks=%0d restart_responses=%0d",
			cycles, writes, reads, consumed, paused_valid, async_reset_checks, restart_responses);
		$finish;
	end

	initial begin
		#50000;
		test_failed = 1'b1;
		$fatal(1, "C1 watchdog timeout");
	end
endmodule
