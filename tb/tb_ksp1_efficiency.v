`timescale 1ns / 1ps
// C4固定12×12、3×3、stride1、pad0；实际C0/C1/B2，TB替代列MAC点积。
module tb_ksp1_efficiency;
	reg clk=1'b0, rst_n=1'b0, ce=1'b1;
	reg wr_valid=1'b0, rd_valid=1'b0, column_valid=1'b0, row_last=1'b0;
	reg [1:0]wr_bank=2'd0, role=2'd0, response_role=2'd0;
	reg [11:0]wr_addr=12'd0;
	reg [12:0]rd_addr=13'd0;
	reg [63:0]wr_data=64'd0;
	reg [143:0]column_data=144'd0;
	wire wr_ready, rd_ready, cache_valid, selected_valid, ready, commit, advance, out_valid;
	wire [95:0]cache_data, selected_data;
	wire signed [47:0]out_data;
	reg [63:0]features[0:143];
	reg [95:0]expected_selected[0:119];
	reg [15:0]weights[0:17];
	reg [47:0]expected_results[0:99];
	reg signed [15:0]feature_value, weight_value;
	reg signed [47:0]partial;
	reg test_done=1'b0, test_failed=1'b0;
	integer fclk=0, run_index=0, y, x, r, d, k;
	integer reads=0, commits=0, outputs=0, row_advances=0, writes=0;
	integer baseline_reads=0, baseline_commits=0, baseline_outputs=0;
	integer pause_cycles=0, trace_file;
	reg [95:0]held_selection;
	reg [143:0]held_column;
	reg [431:0]held_cache;
	reg [431:0]cache_snapshot;

	feature_buffer feature_buffer_Inst(
		.i_clk(clk),.i_rstn(rst_n),.i_ce(ce),.i_wr_valid(wr_valid),.i_wr_safe(1'b1),
		.i_wr_bank(wr_bank),.i_wr_addr(wr_addr),.i_wr_data(wr_data),.o_wr_ready(wr_ready),
		.i_rd_valid(rd_valid),.i_rd_addr(rd_addr),.o_rd_ready(rd_ready),
		.o_out_valid(cache_valid),.o_out_data(cache_data)
	);
	fout_selector fout_selector_Inst(
		.i_in_valid(cache_valid),.i_in_data(cache_data),.i_mode(2'd0),.i_row_select(response_role),
		.i_row_mask(3'b111),.i_column_valid(1'b1),.i_pair_mask(2'b11),
		.o_out_valid(selected_valid),.o_out_data(selected_data)
	);
	ksp1_cache ksp1_cache_Inst(
		.i_clk(clk),.i_rstn(rst_n),.i_ce(ce),.i_column_valid(column_valid),
		.i_column_data(column_data),.i_row_last(row_last),.o_ready(ready),
		.o_column_commit(commit),.o_row_advance(advance),.o_valid(out_valid),.o_data(out_data)
	);
	always #5 clk=~clk;
	// 请求标签与同步BRAM在同沿接受，不能使用下一请求角色。
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) response_role<=2'd0;
		else if (ce && rd_valid && rd_ready) response_role<=role;
	end

	// 从实际握手和B2事件计数，暂停保持的valid不能重复计入。
	always @(posedge clk) begin
		fclk=fclk+1;
		if (rst_n) begin
			if (wr_valid && wr_ready) writes=writes+1;
			if (rd_valid && rd_ready) reads=reads+1;
			if (commit) commits=commits+1;
			if (advance) row_advances=row_advances+1;
			if (ce && out_valid) begin
				if (outputs>=100 || out_data!==expected_results[outputs]) begin
					test_failed=1'b1;$fatal(1,"C4 output %0d actual=%0d expected=%0d",outputs,out_data,$signed(expected_results[outputs]));
				end
				outputs=outputs+1;
			end
			$fdisplay(trace_file,"%0d,%0d,%0d,%0d,%b,%b,%b,%b,%b,%0d,%0d,%0d",run_index,fclk,y,x,ce,
				rd_valid&&rd_ready,commit,advance,ce&&out_valid,reads,commits,outputs);
		end
	end

	initial begin
		$readmemh("c4_features.mem",features);
		$readmemh("c4_selected.mem",expected_selected);
		$readmemh("c4_weights.mem",weights);
		$readmemh("c4_results.mem",expected_results);
		trace_file=$fopen("c4_trace.csv","w");
		if (!trace_file) begin test_failed=1'b1;$fatal(1,"C4 trace open failed");end
		$fdisplay(trace_file,"run,fclk,output_row,scan_col,ce,common_read,column_commit,row_advance,output_fire,reads,commits,outputs");
		// 仅同一固定尺寸做正常与暂停两次运行，不扫描其他网络尺寸。
		for (run_index=0;run_index<2;run_index=run_index+1) begin
			@(negedge clk);rst_n=1'b0;rd_valid=1'b0;column_valid=1'b0;ce=1'b1;
			reads=0;commits=0;outputs=0;row_advances=0;writes=0;role=2'd0;
			@(posedge clk);rst_n<=1'b1;
			@(negedge clk);
			// 首三行初装，之后只在整行完成并排空后覆盖最旧物理bank。
			for (r=0;r<3;r=r+1) begin
				for (x=0;x<12;x=x+1) begin
					wr_valid=1'b1;wr_bank=r;wr_addr=x;wr_data=features[r*12+x];
					#1;if (!wr_ready) begin test_failed=1'b1;$fatal(1,"C4 initial load rejected");end
					@(posedge clk);@(negedge clk);
				end
			end
			wr_valid=1'b0;
			for (y=0;y<10;y=y+1) begin
				for (x=0;x<12;x=x+1) begin
					rd_valid=1'b1;rd_addr=x*2;
					@(posedge clk);#1;
					if (!selected_valid || selected_data!==expected_selected[y*12+x]) begin
						test_failed=1'b1;$fatal(1,"C4 C1 selected pair mismatch row=%0d col=%0d",y,x);
					end
					// 用实际C1输出模拟三核列的完整深度点积，不统计为DDR事务。
					for (k=0;k<3;k=k+1) begin
						partial=48'sd0;
						for (r=0;r<3;r=r+1) begin
							for (d=0;d<2;d=d+1) begin
								feature_value=selected_data[(r*2+d)*16+:16];
								weight_value=weights[(r*3+k)*2+d];
								partial=partial+feature_value*weight_value;
							end
						end
						column_data[k*48+:48]=partial;
					end
					@(negedge clk);rd_valid=1'b0;column_valid=1'b1;row_last=(x==11);
					if (run_index==1 && x%4==2) begin
						ce=1'b0;held_selection=selected_data;held_column=column_data;
						cache_snapshot={ksp1_cache_Inst.reg_cache_third_right,ksp1_cache_Inst.reg_cache_third_middle,ksp1_cache_Inst.reg_cache_third_left,
							ksp1_cache_Inst.reg_cache_second_right,ksp1_cache_Inst.reg_cache_second_middle,ksp1_cache_Inst.reg_cache_second_left,
							ksp1_cache_Inst.reg_cache_first_right,ksp1_cache_Inst.reg_cache_first_middle,ksp1_cache_Inst.reg_cache_first_left};
						held_cache=cache_snapshot;
						repeat(3) begin
							@(posedge clk);#1;pause_cycles=pause_cycles+1;
							cache_snapshot={ksp1_cache_Inst.reg_cache_third_right,ksp1_cache_Inst.reg_cache_third_middle,ksp1_cache_Inst.reg_cache_third_left,
								ksp1_cache_Inst.reg_cache_second_right,ksp1_cache_Inst.reg_cache_second_middle,ksp1_cache_Inst.reg_cache_second_left,
								ksp1_cache_Inst.reg_cache_first_right,ksp1_cache_Inst.reg_cache_first_middle,ksp1_cache_Inst.reg_cache_first_left};
							if (rd_ready || ready || commit || advance || selected_data!==held_selection || column_data!==held_column || cache_snapshot!==held_cache) begin
								test_failed=1'b1;$fatal(1,"C4 pause changed request/cache state");
							end
							@(negedge clk);
						end
						ce=1'b1;
					end
					#1;if (!ready) begin test_failed=1'b1;$fatal(1,"C4 B2 not ready for column");end
					@(posedge clk);@(negedge clk);column_valid=1'b0;row_last=1'b0;
				end
				// 清完最后列流水再轮换，禁止将缓存提交沿混同于请求接受沿。
				repeat(5) begin @(posedge clk);@(negedge clk);end
				if (commits!=(y+1)*12 || outputs!=(y+1)*10 || row_advances!=y+1) begin
					test_failed=1'b1;$fatal(1,"C4 row count mismatch row=%0d",y);
				end
				if (y<9) begin
					for (x=0;x<12;x=x+1) begin
						wr_valid=1'b1;wr_bank=role;wr_addr=x;wr_data=features[(y+3)*12+x];
						#1;if (!wr_ready) begin test_failed=1'b1;$fatal(1,"C4 safe row refill rejected");end
						@(posedge clk);@(negedge clk);
					end
					wr_valid=1'b0;role=(role==2) ? 0 : role+1'b1;
				end
			end
			if (reads!=120 || reads*3!=360 || commits!=120 || outputs!=100 || writes!=144 || row_advances!=10) begin
				test_failed=1'b1;$fatal(1,"C4 total efficiency/coverage mismatch");
			end
			if (run_index==0) begin baseline_reads=reads;baseline_commits=commits;baseline_outputs=outputs;end
			else if (reads!=baseline_reads || commits!=baseline_commits || outputs!=baseline_outputs || pause_cycles!=90) begin
				test_failed=1'b1;$fatal(1,"C4 stalls changed counted requests");
			end
			$display("PASS C4 run=%0d common_reads=%0d vector_reads=%0d commits=%0d outputs=%0d writes=%0d row_advances=%0d",run_index,reads,reads*3,commits,outputs,writes,row_advances);
		end
		$fclose(trace_file);test_done=1'b1;$finish;
	end
	initial begin #100000;test_failed=1'b1;$fatal(1,"C4 watchdog timeout");end
endmodule
