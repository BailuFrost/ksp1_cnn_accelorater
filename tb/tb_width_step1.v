`timescale 1ns / 1ps
`include "width_step1_checks.vh"
module tb_width_step1;
    reg clk=0,rstn=0,ce=0,input_valid=0,first=0,last=0,row_last=0;
    reg [1:0] mode=0;
    reg [95:0] features=0;
    reg [287:0] weights=0;
    wire ready,valid,commit,advance,wready,wvalid,wcommit,wadvance;
    wire [47:0] zero,wzero;
    wire [143:0] one,two,three,wone,wtwo,wthree;
    reg test_done=0,test_failed=0;
    integer m,pattern,depth_case,depth,start,stop,ch,column_index,lane;
    integer outputs=0,case_outputs=0,expected_outputs=0,checks=0,pauses=0;
    reg signed [15:0] x,w;
    reg signed [63:0] product,expected;
    compute_unit dut(clk,rstn,ce,input_valid,first,last,row_last,mode,features,weights,
        ready,valid,zero,one,two,three,commit,advance);
    compute_unit_wide wide(clk,rstn,ce,input_valid,first,last,row_last,mode,features,weights,
        wready,wvalid,wzero,wone,wtwo,wthree,wcommit,wadvance);
    `WIDTH_CU(dut)
    always #5 clk=~clk;
    // 所有沿后端口比较，包含气泡、暂停、复位以及无效期间保留的数据。
    always @(posedge clk or negedge rstn) begin
        #1;
        if ({ready,valid,commit,advance,zero,one,two,three} !==
            {wready,wvalid,wcommit,wadvance,wzero,wone,wtwo,wthree}) begin
            test_failed=1;
            $fatal(1,"WIDTH wide RTL mismatch mode=%0d pattern=%0d depth=%0d",mode,pattern,depth);
        end
        checks=checks+1;
    end
    // 有效结果用64位独立整数点积核对，不依赖原RTL。
    always @(posedge clk) begin
        if (rstn && ce && valid) begin
            if (mode<2) begin
                if ($signed(zero) !== expected) $fatal(1,"WIDTH extreme spatial oracle actual=%0d expected=%0d",$signed(zero),expected);
            end else begin
                for(lane=0;lane<3;lane=lane+1) begin
                    if ($signed(one[lane*48 +:48]) !== expected ||
                        $signed(two[lane*48 +:48]) !== expected ||
                        $signed(three[lane*48 +:48]) !== expected) $fatal(1,"WIDTH extreme bypass oracle");
                end
            end
            outputs=outputs+1;case_outputs=case_outputs+1;
        end
    end
    task idle;
        begin @(negedge clk);ce=1;input_valid=0;first=0;last=0;row_last=0;end
    endtask
    initial begin
        for(m=0;m<4;m=m+1) begin
            for(pattern=0;pattern<4;pattern=pattern+1) begin
                for(depth_case=0;depth_case<5;depth_case=depth_case+1) begin
                    case(depth_case) 0:depth=1;1:depth=3;2:depth=511;3:depth=512;default:depth=513;endcase
                    for(start=0;start<depth;start=start+512) begin
                        stop=depth-start>512 ? start+512 : depth;
                        @(negedge clk);#2;rstn=0;ce=0;mode=m;input_valid=0;
                        @(posedge clk);#2;rstn=1;
                        idle;idle;
                        x=-16'sd32768;
                        w=pattern==1 ? 16'sd32767 : -16'sd32768;
                        product=$signed(x)*$signed(w);
                        expected=pattern==2 ? 0 : (pattern==3 ? product*((stop-start)%2) : product*(stop-start));
                        if(m==0) expected=expected*9;
                        if(m==1) expected=expected*4;
                        case_outputs=0;
                        for(column_index=0;column_index<5;column_index=column_index+1) begin
                            for(ch=start;ch<stop;ch=ch+2) begin
                                @(negedge clk);ce=1;input_valid=1;first=ch==start;last=ch+2>=stop;row_last=last && column_index==4;
                                // 正负抵消用同一对内 +/-32767，奇尾项保留负乘积。
                                if(pattern==3) begin
                                    w=16'sd32767;
                                    product=$signed(x)*$signed(w);
                                    expected=product*((stop-start)%2)*(m==0 ? 9 : (m==1 ? 4 : 1));
                                end
                                for(lane=0;lane<3;lane=lane+1) begin
                                    features[lane*32 +:32]={ch+1<stop ? x : 16'sd0,x};
                                end
                                for(lane=0;lane<9;lane=lane+1) begin
                                    weights[lane*32 +:32]={pattern==2 ? 16'sd0 : (pattern==3 ? -w : w),pattern==2 ? 16'sd0 : w};
                                end
                                if(ch==start+2) begin
                                    ce=0;repeat(2) begin @(negedge clk);pauses=pauses+1;end ce=1;
                                end
                                if(ch==start+4) begin idle;end
                            end
                        end
                        repeat(14) idle;
                        if(case_outputs !== (m==0 ? 3 : (m==1 ? 4 : 5))) $fatal(1,"WIDTH output count %0d",case_outputs);
                        expected_outputs=expected_outputs+case_outputs;
                    end
                end
            end
        end
        if(outputs!=expected_outputs || outputs!=408 || pauses==0) $fatal(1,"WIDTH count coverage outputs=%0d",outputs);
        test_done=1;
        $display("PASS WIDTH modes=4 patterns=4 depths=1,3,511,512,513 results=%0d compared_clocks=%0d pauses=%0d",outputs,checks,pauses);
        $finish;
    end
    initial begin #10000000;$fatal(1,"WIDTH watchdog");end
endmodule
