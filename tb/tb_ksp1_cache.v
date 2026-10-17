`timescale 1ns / 1ps
`include "width_step1_checks.vh"
`include "ksp1_cache_count.vh"
// B1三列实例实际串接B2；每拍核对所有缓存槽、计数器及结果。
module tb_ksp1_cache;
	reg clk = 1'b0;
	reg [791:0] stimulus = 792'd0;
	reg [791:0] vectors [0:`KSP1_CACHE_CYCLES-1];
	wire [431:0] vector_data;
	wire [2:0] vector_valid;
	wire [2:0] vector_ready;
	wire cache_ready;
	wire commit;
	wire advance;
	wire out_valid;
	wire signed [47:0] out_data;
	wire [431:0] cache_snapshot;
	reg [3:0] row_tags = 4'd0;
	reg [1:0] bank_rotation = 2'd0;
	reg test_done = 1'b0;
	reg test_failed = 1'b0;
	integer cycle;
	integer commits = 0;
	integer outputs = 0;
	integer rows = 0;
	integer trace_file;
	reg sampled_commit;
	reg sampled_advance;
	reg sampled_output;
	genvar group_index;


assign cache_snapshot = {{{6{ksp1_cache_Inst.reg_cache_third_right[41]}}, ksp1_cache_Inst.reg_cache_third_right},
        {{6{ksp1_cache_Inst.reg_cache_third_middle[41]}}, ksp1_cache_Inst.reg_cache_third_middle},
        {{6{ksp1_cache_Inst.reg_cache_third_left[41]}}, ksp1_cache_Inst.reg_cache_third_left},
        {{6{ksp1_cache_Inst.reg_cache_second_right[41]}}, ksp1_cache_Inst.reg_cache_second_right},
        {{6{ksp1_cache_Inst.reg_cache_second_middle[41]}}, ksp1_cache_Inst.reg_cache_second_middle},
        {{6{ksp1_cache_Inst.reg_cache_second_left[41]}}, ksp1_cache_Inst.reg_cache_second_left},
        {{6{ksp1_cache_Inst.reg_cache_first_right[41]}}, ksp1_cache_Inst.reg_cache_first_right},
        {{6{ksp1_cache_Inst.reg_cache_first_middle[41]}}, ksp1_cache_Inst.reg_cache_first_middle},
        {{6{ksp1_cache_Inst.reg_cache_first_left[41]}}, ksp1_cache_Inst.reg_cache_first_left}};
	generate
		for (group_index = 0; group_index < 3; group_index = group_index + 1) begin : gen_group
			column_acc column_acc_Inst (
				.i_clk(clk), .i_rstn(stimulus[297]), .i_ce(stimulus[298]),
				.i_mac_valid(stimulus[299]), .i_first(stimulus[300]), .i_last(stimulus[301]),
				.i_mac_data({stimulus[(group_index+6)*33 +: 33], stimulus[(group_index+3)*33 +: 33], stimulus[group_index*33 +: 33]}),
				.i_row_mask(3'b111), .i_bypass(1'b0), .o_ready(vector_ready[group_index]),
				.o_valid(vector_valid[group_index]), .o_data(vector_data[group_index*144 +: 144])
			);
		end
endgenerate
	ksp1_cache ksp1_cache_Inst (
		.i_clk(clk), .i_rstn(stimulus[297]), .i_ce(stimulus[298]),
		.i_column_valid(vector_valid[0]), .i_column_data({vector_data[335:288],vector_data[191:144],vector_data[47:0]}),
		.i_row_last(row_tags[3]), .o_ready(cache_ready),
		.o_column_commit(commit), .o_row_advance(advance), .o_valid(out_valid), .o_data(out_data)
	);

	always #5 clk = ~clk;
	// 仿真适配器只延迟行尾标签；与B1的四级流水使用同一个ce。
	always @(posedge clk) begin
		if (!stimulus[297]) row_tags <= 4'd0;
		else if (stimulus[298]) row_tags <= {row_tags[2:0], stimulus[302]};
	end

	initial begin
		$readmemh("ksp1_cache_vectors.mem", vectors);
		trace_file = $fopen("ksp1_cache_trace.csv", "w");
		if (trace_file == 0) begin test_failed = 1'b1; $display("FAIL trace open"); $finish; end
		$fdisplay(trace_file,"fclk,column_commit,row_advance,output_fire,slot,filled,bank,out_valid,out_data,cache_hex");
		for (cycle = 0; cycle < `KSP1_CACHE_CYCLES; cycle = cycle + 1) begin
			@(negedge clk);
			stimulus = vectors[cycle];
			@(posedge clk);
			sampled_commit = commit;
			sampled_advance = advance;
			sampled_output = stimulus[297] && stimulus[298] && out_valid;
			if (commit !== stimulus[303] || advance !== stimulus[304] ||
			    vector_valid !== {3{vector_valid[0]}} ||
                vector_ready !== {3{vector_ready[0]}} ||
                (stimulus[297] && stimulus[298] && stimulus[299] && vector_ready !== 3'b111) ||
		    (stimulus[297] && stimulus[298] && vector_valid[0] && !cache_ready)) begin
				test_failed = 1'b1; $display("FAIL handshake FCLK=%0d",cycle); $finish;
			end
			if (!stimulus[297]) bank_rotation = 2'd0;
			else if (advance) bank_rotation = (bank_rotation == 2'd2) ? 2'd0 : bank_rotation + 2'd1;
			if (commit) commits = commits + 1;
			if (advance) rows = rows + 1;
			if (sampled_output) outputs = outputs + 1;
			#1;
			if (cache_snapshot !== stimulus[736:305] || out_data !== stimulus[784:737] ||
			    out_valid !== stimulus[785] || ksp1_cache_Inst.reg_slot !== stimulus[787:786] ||
			    ksp1_cache_Inst.reg_filled !== stimulus[789:788] || bank_rotation !== stimulus[791:790]) begin
				test_failed = 1'b1;
				$display("FAIL state FCLK=%0d actual_cache=%h expected_cache=%h",cycle,cache_snapshot,stimulus[736:305]);
				$display("out=%h expected=%h valid=%b expected=%b",out_data,stimulus[784:737],out_valid,stimulus[785]);
				$finish;
			end
			$fdisplay(trace_file,"%0d,%b,%b,%b,%0d,%0d,%0d,%b,%0d,%h",cycle,sampled_commit,sampled_advance,
			          sampled_output,ksp1_cache_Inst.reg_slot,ksp1_cache_Inst.reg_filled,bank_rotation,out_valid,out_data,cache_snapshot);
		end
		$fclose(trace_file);
		if (commits != 20 || outputs != 12 || rows != 4) begin
			test_failed = 1'b1; $display("FAIL counts commits=%0d outputs=%0d rows=%0d",commits,outputs,rows);
		end else begin
			test_done = 1'b1;
			$display("PASS B2 cycles=%0d commits=20 outputs=12 rows=4 baseline_and_stall=PASS",cycle);
		end
		$finish;
	end
	initial begin
		#20000; test_failed = 1'b1; $display("FAIL B2 watchdog"); $finish;
	end
    `WIDTH_CACHE(ksp1_cache_Inst,width_check)
endmodule
