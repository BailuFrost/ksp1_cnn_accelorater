`timescale 1ns / 1ps
`include "width_step1_checks.vh"
`include "column_acc_count.vh"
// 三列独立实例；黄金数据按每FCLK完整比较，避免只看最终结果。
module tb_column_acc;
	reg clk = 1'b0;
	reg [745:0] stimulus = 746'd0;
	reg [745:0] vectors [0:`COLUMN_ACC_CYCLES-1];
	wire [431:0] result_data;
	wire [2:0] result_valid;
	wire [2:0] ready;
	reg test_done = 1'b0;
	reg test_failed = 1'b0;
	integer cycle;
	integer completed = 0;
	integer trace_file;
	integer async_reset_checks = 0;
	reg previous_reset = 1'b0;
	genvar col;

	generate
		for (col = 0; col < 3; col = col + 1) begin : gen_column
			column_acc column_acc_Inst (
				.i_clk(clk), .i_rstn(stimulus[306]), .i_ce(stimulus[307]),
				.i_mac_valid(stimulus[308]),
				.i_mac_data({stimulus[(col + 6) * 33 +: 33],
				          stimulus[(col + 3) * 33 +: 33], stimulus[col * 33 +: 33]}),
				.i_row_mask(stimulus[297 + col * 3 +: 3]),
				.i_bypass(stimulus[311]),
				.i_first(stimulus[309]), .i_last(stimulus[310]),
				.o_ready(ready[col]), .o_valid(result_valid[col]),
				.o_data(result_data[col * 144 +: 144])
			);
            `WIDTH_COLUMN(column_acc_Inst,width_check)
		end
	endgenerate

	always #5 clk = ~clk;

	initial begin
		$readmemh("column_acc_vectors.mem", vectors);
		trace_file = $fopen("column_acc_trace.csv", "w");
		if (trace_file == 0) begin
			test_failed = 1'b1;
			$display("FAIL cannot open trace");
			$finish;
		end
		$fdisplay(trace_file, "fclk,rst_n,ce,in_valid,first,last,bypass,out_valid,data_hex");
		for (cycle = 0; cycle < `COLUMN_ACC_CYCLES; cycle = cycle + 1) begin
			@(negedge clk);
			// 硬复位在下降沿后2ns拉低，下一上升沿前检查清零。
			if (previous_reset && !vectors[cycle][306]) begin
				#2;
				stimulus = vectors[cycle];
				#1;
				if (result_data !== 432'd0 || result_valid !== 3'd0 || ready !== 3'd0) begin
					test_failed = 1'b1;
					$display("FAIL B1 asynchronous reset before clock cycle=%0d", cycle);
					$finish;
				end
				async_reset_checks = async_reset_checks + 1;
			end else if (!previous_reset && vectors[cycle][306]) begin
				// 模拟上游同域寄存复位释放；本模块没有本地复位同步链。
				@(posedge clk);
				#2;
				stimulus = vectors[cycle];
				if (ready !== 3'd0) begin
					test_failed = 1'b1;
					$display("FAIL B1 ready before recovery clock");
					$finish;
				end
			end else stimulus = vectors[cycle];
			previous_reset = vectors[cycle][306];
			@(posedge clk);
			#1;
			if (result_valid !== {3{stimulus[312]}} ||
			    ready !== {3{stimulus[745]}} || result_data !== stimulus[744:313]) begin
				test_failed = 1'b1;
				$display("FAIL B1 cycle=%0d valid=%b expected=%b ready=%b", cycle, result_valid, stimulus[312], ready);
				$display("actual=%h expected=%h", result_data, stimulus[744:313]);
				$finish;
			end
			if (stimulus[306] && stimulus[307] && result_valid[0]) completed = completed + 1;
			$fdisplay(trace_file, "%0d,%b,%b,%b,%b,%b,%b,%b,%h", cycle,
			          stimulus[306], stimulus[307], stimulus[308], stimulus[309],
			          stimulus[310], stimulus[311], result_valid[0], result_data);
		end
		$fclose(trace_file);
		if (completed != 26 || async_reset_checks != 2) begin
			test_failed = 1'b1;
			$display("FAIL completion count %0d expected 26", completed);
		end else begin
			test_done = 1'b1;
			$display("PASS B1 cycles=%0d groups=3 depths=1,3,511,512,513 modes=4 tile_results=24 back_to_back=2 async_reset_checks=%0d", cycle, async_reset_checks);
		end
		$finish;
	end

	initial begin
		#100000;
		test_failed = 1'b1;
		$display("FAIL B1 watchdog");
		$finish;
	end
endmodule
