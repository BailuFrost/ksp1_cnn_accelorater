`timescale 1ns / 1ps
`include "kernel_count.vh"
// A3文件拆拍后实际读写108个RAM bank，逐拍比较全部3456位。
module tb_kernel_buffer;
	reg clk = 1'b0;
	reg rst_n;
	reg ce;
	reg load_enable;
	reg wr_valid;
	reg [3:0] wr_cu;
	reg [3:0] wr_bank;
	reg [7:0] wr_addr;
	reg [31:0] wr_data;
	reg rd_valid;
	reg [7:0] rd_addr;
	wire wr_ready;
	wire rd_ready;
	wire out_valid;
	wire [2303:0] out_data;
	reg [3519:0] vectors [0:`KERNEL_VECTOR_COUNT-1];
	reg [3519:0] current_vector;
	reg [3519:0] previous_vector;
	reg test_done = 1'b0;
	reg test_failed = 1'b0;
	reg [31:0] expected_first_pair;
	integer cycles = 0;
	integer writes = 0;
	integer reads = 0;
	integer consumed = 0;
	integer blocked_writes = 0;
	integer blocked_reads = 0;
	integer paused_valid = 0;
	integer async_reset_checks = 0;
	integer restart_reads = 0;
	reg [2303:0] expected_bundle;
	reg [3455:0] held_bundle;
	integer index;
	integer trace_file;

	kernel_buffer u_kernel_buffer (
		.i_clk(clk), .i_rstn(rst_n), .i_ce(ce), .i_load_enable(load_enable),
		.i_wr_valid(wr_valid), .i_wr_cu(wr_cu), .i_wr_bank(wr_bank), .i_wr_addr(wr_addr),
		.i_wr_data(wr_data), .o_wr_ready(wr_ready), .i_rd_valid(rd_valid), .i_rd_addr(rd_addr),
		.o_rd_ready(rd_ready), .o_out_valid(out_valid), .o_out_data(out_data)
	);

	always #5 clk = ~clk;

	initial begin
		$readmemh("kernel_vectors.mem", vectors);
		trace_file = $fopen("kernel_trace.csv", "w");
		if (!trace_file) begin
			test_failed = 1'b1;
			$fatal(1, "Cannot open C2 trace file");
		end
		$fwrite(trace_file, "cycle,ce,load,wr_valid,wr_ready,wr_cu,wr_bank,wr_addr,rd_valid,rd_ready,rd_addr,out_valid,out_data\n");
		for (index = 0; index < `KERNEL_VECTOR_COUNT; index = index + 1) begin
			@(negedge clk);
			current_vector = vectors[index];
			{rd_addr, rd_valid, wr_data, wr_addr, wr_bank, wr_cu, wr_valid, load_enable, ce, rst_n}
				= current_vector[60:0];
			#1;
			if (wr_ready !== current_vector[61] || rd_ready !== current_vector[62]) begin
				test_failed = 1'b1;
				$fatal(1, "C2 cycle %0d readiness mismatch", index);
			end
			if (index > 0 && rst_n) begin
				previous_vector = vectors[index - 1];
				if (out_valid !== previous_vector[63] || (out_valid && out_data !== previous_vector[3519:64])) begin
					test_failed = 1'b1;
					$fatal(1, "C2 cycle %0d previous response changed before consume", index);
				end
			end
			if (!rst_n && out_valid) begin
				test_failed = 1'b1;
				$fatal(1, "C2 async clear failed before rising edge");
			end
			@(posedge clk);
			if (wr_valid && wr_ready) begin
				writes = writes + 1;
				if (wr_cu == 4'd0 && wr_bank == 4'd0 && wr_addr == 8'd0) begin
					expected_first_pair = wr_data;
				end
			end
			if (rd_valid && rd_ready) begin
				reads = reads + 1;
			end
			if (rst_n && ce && out_valid) begin
				consumed = consumed + 1;
			end
			if (wr_valid && !wr_ready) begin
				blocked_writes = blocked_writes + 1;
			end
			if (rd_valid && !rd_ready) begin
				blocked_reads = blocked_reads + 1;
			end
			#1;
			cycles = cycles + 1;
			// 暂停期间存储体也不得被未握手的新值覆盖，不能只检查输出valid。
			if (!ce && load_enable && wr_valid && wr_cu == 4'd0 && wr_bank == 4'd0 && wr_addr == 8'd0) begin
				if (u_kernel_buffer.gen_compute_unit[0].gen_kernel_bank[0].reg_pair_memory[0] !== expected_first_pair) begin
					test_failed = 1'b1;
					$fatal(1, "C2 cycle %0d RAM changed without write handshake", index);
				end
			end
			if (!ce && out_valid) begin
				paused_valid = paused_valid + 1;
			end
			if (out_valid !== current_vector[63] || (out_valid && out_data !== current_vector[3519:64])) begin
				test_failed = 1'b1;
				$fatal(1, "C2 cycle %0d response mismatch actual=%h expected=%h", index, out_data, current_vector[3519:64]);
			end
			// 无效响应不转储3456位未知值；每个有效拍包含108个bank的完整数据。
			if (out_valid) begin
				$fwrite(trace_file, "%0d,%b,%b,%b,%b,%0d,%0d,%0d,%b,%b,%0d,%b,%h\n", index,
					ce, load_enable, wr_valid, wr_ready, wr_cu, wr_bank, wr_addr, rd_valid, rd_ready, rd_addr, out_valid, out_data);
			end
		end
		$fclose(trace_file);
		// 在108个bank的末地址装入不同签名，确认整个输出在复位前非零。
		for (index = 0; index < 72; index = index + 1) begin
			@(negedge clk);
			ce = 1'b1;
			load_enable = 1'b1;
			wr_valid = 1'b1;
			wr_cu = index / 9;
			wr_bank = index % 9;
			wr_addr = 8'd255;
			wr_data = 32'h80007fff ^ (index * 32'h00010001);
			rd_valid = 1'b0;
			expected_bundle[index * 32 +: 32] = wr_data;
			#1;
			if (!wr_ready || rd_ready) begin
				test_failed = 1'b1;
				$fatal(1, "C2 directed initial load readiness");
			end
			@(posedge clk); #1;
		end
		@(negedge clk);
		load_enable = 1'b0;
		wr_valid = 1'b0;
		rd_valid = 1'b1;
		rd_addr = 8'd255;
		@(posedge clk); #1;
		if (!out_valid || out_data !== expected_bundle) begin
			test_failed = 1'b1;
			$fatal(1, "C2 directed full-bank signature mismatch");
		end
		held_bundle = out_data;
		@(negedge clk);
		ce = 1'b0;
		load_enable = 1'b1;
		wr_valid = 1'b1;
		wr_cu = 4'd0;
		wr_bank = 4'd0;
		wr_data = 32'd0;
		@(posedge clk); #1;
		if (!out_valid || out_data !== held_bundle || wr_ready || rd_ready) begin
			test_failed = 1'b1;
			$fatal(1, "C2 response changed during pause");
		end
		// 非沿拉低立即取消响应资格；复位期间脏装载请求不得污染RAM。
		@(negedge clk); #2; rst_n = 1'b0; #1;
		if (out_valid || wr_ready || rd_ready || out_data !== held_bundle) begin
			test_failed = 1'b1;
			$fatal(1, "C2 async clear or RAM read-data retention");
		end
		async_reset_checks = async_reset_checks + 1;
		// 即使复位期间ce恢复，也不能发生读写事务。
		ce = 1'b1;
		@(posedge clk); #1;
		if (u_kernel_buffer.gen_compute_unit[0].gen_kernel_bank[0].reg_pair_memory[255] !== held_bundle[31:0]) begin
			test_failed = 1'b1;
			$fatal(1, "C2 dirty write accepted during reset");
		end
		@(negedge clk);
		ce = 1'b0;
		wr_valid = 1'b0;
		rd_valid = 1'b0;
		@(posedge clk); rst_n <= 1'b1;
		@(posedge clk); #1;
		if (out_valid || wr_ready || rd_ready) begin
			test_failed = 1'b1;
			$fatal(1, "C2 reset release while paused");
		end
		// 诊断重读全部bank证明RAM保留，随后新任务重新初装。
		@(negedge clk);
		ce = 1'b1;
		load_enable = 1'b0;
		rd_valid = 1'b1;
		@(posedge clk); #1;
		if (!out_valid || out_data !== held_bundle) begin
			test_failed = 1'b1;
			$fatal(1, "C2 full-bank RAM preservation across reset");
		end
		for (index = 0; index < 72; index = index + 1) begin
			@(negedge clk);
			load_enable = 1'b1;
			rd_valid = 1'b0;
			wr_valid = 1'b1;
			wr_cu = index / 9;
			wr_bank = index % 9;
			wr_addr = 8'd0;
			wr_data = 32'h7fff8000 ^ (index * 32'h00010001);
			expected_bundle[index * 32 +: 32] = wr_data;
			@(posedge clk); #1;
		end
		for (index = 0; index < 2; index = index + 1) begin
			@(negedge clk);
			load_enable = 1'b0;
			wr_valid = 1'b0;
			rd_valid = 1'b1;
			rd_addr = index == 0 ? 8'd0 : 8'd255;
			@(posedge clk); #1;
			if (!out_valid || out_data !== (index == 0 ? expected_bundle : held_bundle)) begin
				test_failed = 1'b1;
				$fatal(1, "C2 restart full-bank first/last address");
			end
			restart_reads = restart_reads + 1;
		end
		test_done = 1'b1;
		$display("PASS C2 cycles=%0d writes=%0d reads=%0d consumed=%0d blocked=%0d/%0d paused=%0d async_reset_checks=%0d restart_reads=%0d",
			cycles, writes, reads, consumed, blocked_writes, blocked_reads, paused_valid, async_reset_checks, restart_reads);
		$finish;
	end

	initial begin
		#100000;
		test_failed = 1'b1;
		$fatal(1, "C2 watchdog timeout");
	end
endmodule
