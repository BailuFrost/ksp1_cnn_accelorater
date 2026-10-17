`ifndef WIDTH_STEP1_CHECKS_VH
`define WIDTH_STEP1_CHECKS_VH
`define WIDTH_COLUMN(P,N) \
    width_column_check N(P.i_clk,P.i_rstn,P.i_ce,P.i_mac_valid,P.o_ready,P.i_first,P.i_last, \
        P.i_mac_data,P.flag_valid,P.flag_first,P.sum_top,P.sum_middle,P.sum_bottom);
`define WIDTH_CACHE(P,N) \
    width_cache_check N(P.i_clk,P.i_rstn,P.i_ce,P.i_column_valid,P.o_ready,P.i_column_data);
`define WIDTH_ACC(P,N) \
    width_acc_check N(P.i_clk,P.i_rstn,P.i_ce,P.flag_vector_first_valid,P.flag_bypass,P.flag_small,P.reg_vector_data);
`define WIDTH_CU(P) \
    `WIDTH_COLUMN(P.three_stage_acc_Inst.column_acc_first_Inst,width_first) \
    `WIDTH_COLUMN(P.three_stage_acc_Inst.column_acc_middle_Inst,width_middle) \
    `WIDTH_COLUMN(P.three_stage_acc_Inst.column_acc_last_Inst,width_last) \
    `WIDTH_CACHE(P.three_stage_acc_Inst.ksp1_cache_Inst,width_cache) \
    `WIDTH_ACC(P.three_stage_acc_Inst,width_acc)
`endif
