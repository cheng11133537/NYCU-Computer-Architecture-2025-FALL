`ifndef RISCV_CORE_SCOREBOARD_V
`define RISCV_CORE_SCOREBOARD_V

module riscv_CoreScoreboard
(
  input            clk,
  input            reset,

  input            inst_val_Dhl,

  input      [4:0] src00, input src00_en,
  input      [4:0] src01, input src01_en,
  input      [4:0] src10, input src10_en,
  input      [4:0] src11, input src11_en,

  output           stall_0_hazard,
  output           stall_1_hazard,

  output reg [3:0] src00_byp_mux_sel,
  output reg [3:0] src01_byp_mux_sel,
  output reg [3:0] src10_byp_mux_sel,
  output reg [3:0] src11_byp_mux_sel,

  input      [4:0] dstA,
  input            dstA_en,
  input            stall_A_Dhl,     
  input            is_muldiv_A,
  input            is_load_A,

  input      [4:0] dstB,
  input            dstB_en,
  input            stall_B_Dhl,     
  input            is_muldiv_B,     
  input            is_load_B,       

  input            stall_X0hl,
  input            stall_X1hl,

  input            wbA_wen, 
  input [4:0] wbA_dst,
  input            wbB_wen, 
  input [4:0] wbB_dst
);

  localparam [3:0] BYP_RF   = 4'd0;

  localparam [3:0] BYP_A_X0 = 4'd1;   // aluA_out_X0hl
  localparam [3:0] BYP_A_X1 = 4'd2;   // memexA_mux_out_X1hl
  localparam [3:0] BYP_A_X2 = 4'd3;   // memexA_mux_out_X2hl
  localparam [3:0] BYP_A_X3 = 4'd4;   // executeA_mux_out_X3hl (含 mul/div)
  localparam [3:0] BYP_A_W  = 4'd5;   // wbA_mux_out_Whl

  localparam [3:0] BYP_B_X0 = 4'd6;   // aluB_out_X0hl
  localparam [3:0] BYP_B_X1 = 4'd7;   // memexB_mux_out_X1hl
  localparam [3:0] BYP_B_X2 = 4'd8;   // memexB_mux_out_X2hl
  localparam [3:0] BYP_B_X3 = 4'd9;   // memexB_mux_out_X3hl
  localparam [3:0] BYP_B_W  = 4'd10;  // wbB_mux_out_Whl


  reg [4:0] stage    [31:0]; // {W,X3,X2,X1,X0}
  reg       is_ld    [31:0];
  reg       is_md    [31:0];
  reg       prod_isB [31:0]; // 0:A 1:B

  integer i;

  task insert_into_X0 (
    input [4:0] rd,
    input       rd_en,
    input       isload,
    input       ismuldiv,
    input       isB_producer
  );
  begin
    if (rd_en && (rd!=5'd0)) begin
      stage[rd]    <= 5'b00001; // X0
      is_ld[rd]    <= isload;
      is_md[rd]    <= ismuldiv;
      prod_isB[rd] <= isB_producer;
    end
  end
  endtask

  reg [4:0] cur;
  reg [4:0] nxt;
  integer j;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      for (i=0; i<32; i=i+1) begin
        stage[i]    <= 5'b0;
        is_ld[i]    <= 1'b0;
        is_md[i]    <= 1'b0;
        prod_isB[i] <= 1'b0;
      end
    end
    else begin
      for (j=0; j<32; j=j+1) begin
        cur = stage[j];
        nxt = 5'b0;

        // X3 -> W
        if (cur[3]) nxt[4] = 1'b1;

        // X2 -> X3
        if (cur[2]) nxt[3] = 1'b1;

        // X1 -> X2
        if (cur[1]) begin
          if (!stall_X1hl) nxt[2] = 1'b1;
          else             nxt[1] = 1'b1;
        end

        // X0 -> X1
        if (cur[0]) begin
          if (!stall_X1hl && !stall_X0hl) nxt[1] = 1'b1;
          else                            nxt[0] = 1'b1;
        end

        stage[j] <= nxt;

        if (nxt==5'b0) begin
          is_ld[j]    <= 1'b0;
          is_md[j]    <= 1'b0;
          prod_isB[j] <= 1'b0;
        end
      end

      if (!stall_A_Dhl && !stall_X0hl && inst_val_Dhl && dstA_en && dstA!=5'd0 && (stage[dstA]==5'b0))
        insert_into_X0(dstA, 1'b1, is_load_A, is_muldiv_A, 1'b0);

      if (!stall_B_Dhl && !stall_X0hl && inst_val_Dhl && dstB_en && dstB!=5'd0 && (stage[dstB]==5'b0))
        insert_into_X0(dstB, 1'b1, is_load_B, is_muldiv_B, 1'b1);
    end
  end

  function can_bypass_from_X0;
    input isload;
    input ismuldiv;
    begin
      can_bypass_from_X0 = (!isload && !ismuldiv); 
    end
  endfunction
  function can_bypass_from_X1;
    input isload;
    input ismuldiv;
    begin
      can_bypass_from_X1 = (!ismuldiv);          // ALU、Load
    end
  endfunction
  function can_bypass_from_X2;
    input isload;
    input ismuldiv;
    begin
      can_bypass_from_X2 = (!ismuldiv);          // ALU、Load
    end
  endfunction
  function can_bypass_from_X3;
    input isload;
    input ismuldiv;
    begin
      can_bypass_from_X3 = 1'b1;                 // ALU、Load、MulDiv
    end
  endfunction

  function [4:0] resolve_src_f;
    input        valid;     
    input  [4:0] stg;      
    input        isload;    
    input        ismd;      
    input        isBprod;   // 0:A,1:B
    reg          stall;
    reg  [3:0]   byp;
    begin
      stall = 1'b0;
      byp   = BYP_RF;

      if (!valid) begin
        resolve_src_f = {stall, byp};
      end
      else begin

        if (stg[4]) begin
          byp   = isBprod ? BYP_B_W  : BYP_A_W;
          stall = 1'b0;
        end
        else if (stg[3]) begin
          if (can_bypass_from_X3(isload, ismd)) begin
            byp   = isBprod ? BYP_B_X3 : BYP_A_X3;
            stall = 1'b0;
          end else begin
            byp   = BYP_RF;
            stall = 1'b1;
          end
        end
        else if (stg[2]) begin
          if (can_bypass_from_X2(isload, ismd)) begin
            byp   = isBprod ? BYP_B_X2 : BYP_A_X2;
            stall = 1'b0;
          end else begin
            byp   = BYP_RF;
            stall = 1'b1;
          end
        end
        else if (stg[1]) begin
          if (can_bypass_from_X1(isload, ismd)) begin
            byp   = isBprod ? BYP_B_X1 : BYP_A_X1;
            stall = 1'b0;
          end else begin
            byp   = BYP_RF;
            stall = 1'b1;
          end
        end
        else if (stg[0]) begin
          if (can_bypass_from_X0(isload, ismd)) begin
            byp   = isBprod ? BYP_B_X0 : BYP_A_X0;
            stall = 1'b0;
          end else begin
            byp   = BYP_RF;
            stall = 1'b1;
          end
        end
        else begin
          byp   = BYP_RF;
          stall = 1'b0;
        end

        resolve_src_f = {stall, byp};
      end
    end
  endfunction

  function [3:0] compress_sel;
    input [3:0] raw;
    begin
      case (raw)
        BYP_A_W,  BYP_B_W:                        compress_sel = 4'd1; // WB
        BYP_A_X1, BYP_A_X2, BYP_B_X1, BYP_B_X2:    compress_sel = 4'd2; // MEM
        BYP_A_X0, BYP_A_X3, BYP_B_X0, BYP_B_X3:    compress_sel = 4'd3; // EX
        default:                                   compress_sel = 4'd0; // RF
      endcase
    end
  endfunction

  reg         stall00, stall01, stall10, stall11;
  reg  [3:0]  byp00,   byp01,   byp10,   byp11;

  reg  [4:0]  stg00, stg01, stg10, stg11;
  reg         ld00,  ld01,  ld10,  ld11;
  reg         md00,  md01,  md10,  md11;
  reg         isB00, isB01, isB10, isB11;

  wire a_will_issue = inst_val_Dhl && dstA_en && !stall_A_Dhl && !stall_X0hl;
  wire b_will_issue = inst_val_Dhl && dstB_en && !stall_B_Dhl && !stall_X0hl;

  wire pair_waw  = a_will_issue && b_will_issue && (dstA!=5'd0) && (dstA==dstB);
  wire pair_raw1 = a_will_issue && (dstA!=5'd0) &&
                   ((src10_en && (src10==dstA)) || (src11_en && (src11==dstA))); 
  wire pair_raw0 = b_will_issue && (dstB!=5'd0) &&
                   ((src00_en && (src00==dstB)) || (src01_en && (src01==dstB))); 

  wire hitWB00 = (src00_en && (src00!=5'd0)) &&
                 ((wbA_wen && (wbA_dst==src00)) || (wbB_wen && (wbB_dst==src00)));
  wire hitWB01 = (src01_en && (src01!=5'd0)) &&
                 ((wbA_wen && (wbA_dst==src01)) || (wbB_wen && (wbB_dst==src01)));
  wire hitWB10 = (src10_en && (src10!=5'd0)) &&
                 ((wbA_wen && (wbA_dst==src10)) || (wbB_wen && (wbB_dst==src10)));
  wire hitWB11 = (src11_en && (src11!=5'd0)) &&
                 ((wbA_wen && (wbA_dst==src11)) || (wbB_wen && (wbB_dst==src11)));

  wire dstA_busy_now = (dstA_en && dstA!=5'd0 && stage[dstA]!=5'b0);
  wire dstB_busy_now = (dstB_en && dstB!=5'd0 && stage[dstB]!=5'b0);
  wire dstB_conflict_with_A_issue = b_will_issue && a_will_issue && (dstB==dstA) && (dstB!=5'd0);

  wire dstA_hazard = a_will_issue && dstA_busy_now;
  wire dstB_hazard = b_will_issue && (dstB_busy_now || dstB_conflict_with_A_issue);

  always @* begin
    stg00 = (src00_en && (src00!=5'd0)) ? stage[src00]    : 5'b0;
    stg01 = (src01_en && (src01!=5'd0)) ? stage[src01]    : 5'b0;
    stg10 = (src10_en && (src10!=5'd0)) ? stage[src10]    : 5'b0;
    stg11 = (src11_en && (src11!=5'd0)) ? stage[src11]    : 5'b0;

    ld00  = (src00_en && (src00!=5'd0)) ? is_ld[src00]    : 1'b0;
    ld01  = (src01_en && (src01!=5'd0)) ? is_ld[src01]    : 1'b0;
    ld10  = (src10_en && (src10!=5'd0)) ? is_ld[src10]    : 1'b0;
    ld11  = (src11_en && (src11!=5'd0)) ? is_ld[src11]    : 1'b0;

    md00  = (src00_en && (src00!=5'd0)) ? is_md[src00]    : 1'b0;
    md01  = (src01_en && (src01!=5'd0)) ? is_md[src01]    : 1'b0;
    md10  = (src10_en && (src10!=5'd0)) ? is_md[src10]    : 1'b0;
    md11  = (src11_en && (src11!=5'd0)) ? is_md[src11]    : 1'b0;

    isB00 = (src00_en && (src00!=5'd0)) ? prod_isB[src00] : 1'b0;
    isB01 = (src01_en && (src01!=5'd0)) ? prod_isB[src01] : 1'b0;
    isB10 = (src10_en && (src10!=5'd0)) ? prod_isB[src10] : 1'b0;
    isB11 = (src11_en && (src11!=5'd0)) ? prod_isB[src11] : 1'b0;

    if (src00_en && (src00!=5'd0) && inst_val_Dhl) begin
      if (a_will_issue && (dstA!=5'd0) && (src00==dstA)) begin
        stg00 = 5'b00001; isB00 = 1'b0; ld00 = is_load_A; md00 = is_muldiv_A;
      end
      if (b_will_issue && (dstB!=5'd0) && (src00==dstB)) begin
        stg00 = 5'b00001; isB00 = 1'b1; ld00 = is_load_B; md00 = is_muldiv_B;
      end
    end
    if (src01_en && (src01!=5'd0) && inst_val_Dhl) begin
      if (a_will_issue && (dstA!=5'd0) && (src01==dstA)) begin
        stg01 = 5'b00001; isB01 = 1'b0; ld01 = is_load_A; md01 = is_muldiv_A;
      end
      if (b_will_issue && (dstB!=5'd0) && (src01==dstB)) begin
        stg01 = 5'b00001; isB01 = 1'b1; ld01 = is_load_B; md01 = is_muldiv_B;
      end
    end
    if (src10_en && (src10!=5'd0) && inst_val_Dhl) begin
      if (a_will_issue && (dstA!=5'd0) && (src10==dstA)) begin
        stg10 = 5'b00001; isB10 = 1'b0; ld10 = is_load_A; md10 = is_muldiv_A;
      end
      if (b_will_issue && (dstB!=5'd0) && (src10==dstB)) begin
        stg10 = 5'b00001; isB10 = 1'b1; ld10 = is_load_B; md10 = is_muldiv_B;
      end
    end
    if (src11_en && (src11!=5'd0) && inst_val_Dhl) begin
      if (a_will_issue && (dstA!=5'd0) && (src11==dstA)) begin
        stg11 = 5'b00001; isB11 = 1'b0; ld11 = is_load_A; md11 = is_muldiv_A;
      end
      if (b_will_issue && (dstB!=5'd0) && (src11==dstB)) begin
        stg11 = 5'b00001; isB11 = 1'b1; ld11 = is_load_B; md11 = is_muldiv_B;
      end
    end

    {stall00, byp00} = resolve_src_f(src00_en && (src00!=5'd0), stg00, ld00, md00, isB00);
    {stall01, byp01} = resolve_src_f(src01_en && (src01!=5'd0), stg01, ld01, md01, isB01);
    {stall10, byp10} = resolve_src_f(src10_en && (src10!=5'd0), stg10, ld10, md10, isB10);
    {stall11, byp11} = resolve_src_f(src11_en && (src11!=5'd0), stg11, ld11, md11, isB11);

    if (hitWB00) begin
      stall00 = 1'b0;
      byp00   = (wbA_wen && (wbA_dst==src00)) ? BYP_A_W : BYP_B_W;
    end
    if (hitWB01) begin
      stall01 = 1'b0;
      byp01   = (wbA_wen && (wbA_dst==src01)) ? BYP_A_W : BYP_B_W;
    end
    if (hitWB10) begin
      stall10 = 1'b0;
      byp10   = (wbA_wen && (wbA_dst==src10)) ? BYP_A_W : BYP_B_W;
    end
    if (hitWB11) begin
      stall11 = 1'b0;
      byp11   = (wbA_wen && (wbA_dst==src11)) ? BYP_A_W : BYP_B_W;
    end

    src00_byp_mux_sel = byp00;
    src01_byp_mux_sel = byp01;
    src10_byp_mux_sel = byp10;
    src11_byp_mux_sel = byp11;
  end

  assign stall_0_hazard = (stall00 | stall01) | pair_raw0 | dstA_hazard;             
  assign stall_1_hazard = (stall10 | stall11) | pair_waw | pair_raw1 | dstB_hazard;  

  integer dbg_sb;
  initial begin
    if ( !$value$plusargs("dbg_sb=%d", dbg_sb) ) dbg_sb = 0;
  end

  // helper to coerce X/Z to 0 for debug printing
  function [0:0] to01;
    input b;
    begin
      to01 = (b===1'b1) ? 1'b1 : 1'b0;
    end
  endfunction

  // helper to print a compact line each cycle
  always @(posedge clk) if (!reset && (dbg_sb>=1)) begin
    $display({
      "[SB t=%0t] H0=%0b H1=%0b | ",
      "A:will=%0b rd=%0d ld=%0b md=%0b | ",
      "B:will=%0b rd=%0d ld=%0b md=%0b | ",
      "S00 sel=%0d S01 sel=%0d S10 sel=%0d S11 sel=%0d"
    },
    $time,
    to01(stall_0_hazard), to01(stall_1_hazard),
    to01(inst_val_Dhl && dstA_en && !stall_A_Dhl && !stall_X0hl), dstA, to01(is_load_A), to01(is_muldiv_A),
    to01(inst_val_Dhl && dstB_en && !stall_B_Dhl && !stall_X0hl), dstB, to01(is_load_B), to01(is_muldiv_B),
    compress_sel(byp00), compress_sel(byp01), compress_sel(byp10), compress_sel(byp11));
  end

  // Raw scoreboard decisions (bypass + stall per source) each cycle
  // Printed when dbg_sb>=2 to aid pinpointing wrong bypass or missing stall
  always @(posedge clk) if (!reset && (dbg_sb>=2)) begin
    $display({
      "[SB-RAW t=%0t] ",
      "S00: src=x%0d en=%0b stg=%05b byp=%0d stall=%0b | ",
      "S01: src=x%0d en=%0b stg=%05b byp=%0d stall=%0b | ",
      "S10: src=x%0d en=%0b stg=%05b byp=%0d stall=%0b | ",
      "S11: src=x%0d en=%0b stg=%05b byp=%0d stall=%0b"
    },
    $time,
    src00, to01(src00_en && (src00!=5'd0)), stg00, byp00, to01(stall00),
    src01, to01(src01_en && (src01!=5'd0)), stg01, byp01, to01(stall01),
    src10, to01(src10_en && (src10!=5'd0)), stg10, byp10, to01(stall10),
    src11, to01(src11_en && (src11!=5'd0)), stg11, byp11, to01(stall11));
  end

  // verbose pending-regs snapshot
  integer r_sb;
  always @(posedge clk) if (!reset && (dbg_sb>=2)) begin
    $display("[SB t=%0t] pending regs: ", $time);
    for (r_sb=0; r_sb<32; r_sb=r_sb+1) begin
      if (stage[r_sb] != 5'b0) begin
        $display("  x%0d : [W=%0b X3=%0b X2=%0b X1=%0b X0=%0b] ld=%0d md=%0d FU=%s",
                 r_sb,
                 stage[r_sb][4], stage[r_sb][3], stage[r_sb][2], stage[r_sb][1], stage[r_sb][0],
                 is_ld[r_sb], is_md[r_sb], (prod_isB[r_sb]?"B":"A"));
      end
    end
  end

  // ================================================================
  // Scoreboard trace/report (simulation only)
  // ================================================================
`ifdef SCOREBOARD_TRACE
  reg [4:0] stage_prev5, stage_prev6;
  always @(posedge clk) begin
    if (reset) begin
      stage_prev5 <= 5'b0;
      stage_prev6 <= 5'b0;
    end else begin
      if (stage[5] != stage_prev5 || stage[6] != stage_prev6) begin
        $display("[t=%0t] x5:[W=%0b X3=%0b X2=%0b X1=%0b X0=%0b] ld=%0d md=%0d P=%s  |  x6:[W=%0b X3=%0b X2=%0b X1=%0b X0=%0b] ld=%0d md=%0d P=%s",
                 $time,
                 stage[5][4], stage[5][3], stage[5][2], stage[5][1], stage[5][0], is_ld[5], is_md[5], (prod_isB[5]?"B":"A"),
                 stage[6][4], stage[6][3], stage[6][2], stage[6][1], stage[6][0], is_ld[6], is_md[6], (prod_isB[6]?"B":"A"));
        stage_prev5 <= stage[5];
        stage_prev6 <= stage[6];
      end
    end
  end

  integer r_trace;
  always @(posedge clk) if (!reset) begin
    $display("[t=%0t] SCOREBOARD (pending regs):", $time);
    for (r_trace=0; r_trace<32; r_trace=r_trace+1) begin
      if (stage[r_trace] != 5'b0) begin
        $display("  x%0d : [W=%0b X3=%0b X2=%0b X1=%0b X0=%0b]  ld=%0d md=%0d  FU=%s",
                 r_trace, stage[r_trace][4], stage[r_trace][3], stage[r_trace][2], stage[r_trace][1], stage[r_trace][0],
                 is_ld[r_trace], is_md[r_trace], (prod_isB[r_trace]?"B":"A"));
      end
    end
  end
`endif

`ifdef SCOREBOARD_REPORT
  integer r_full;
  always @(posedge clk) if (!reset) begin
    integer any;
    any = 0;
    for (r_full=0; r_full<32; r_full=r_full+1)
      if (stage[r_full]!=5'b0) any = 1;

    if (any) begin
      $display("======== [t=%0t] SCOREBOARD ========", $time);
      $display("Dest.Reg | Pending | Functional Unit | 4  3  2  1  0 | ld md");
      for (r_full=0; r_full<32; r_full=r_full+1) begin
        if (stage[r_full] != 5'b0) begin
          $display("x%02d     |   1     |       %s        | %0b  %0b  %0b  %0b  %0b |  %0d  %0d",
                   r_full, (prod_isB[r_full]?"B":"A"),
                   stage[r_full][4], stage[r_full][3], stage[r_full][2], stage[r_full][1], stage[r_full][0],
                   is_ld[r_full], is_md[r_full]);
        end
      end
    end
  end
`endif

endmodule
`endif // RISCV_CORE_SCOREBOARD_V