//=========================================================================
// 5-Stage RISCV Scoreboard
//=========================================================================

`ifndef RISCV_CORE_SCOREBOARD_V
`define RISCV_CORE_SCOREBOARD_V

`define FUNC_UNIT_ALU 1
`define FUNC_UNIT_MEM 2
`define FUNC_UNIT_MUL 3

`include "riscvooo-InstMsg.v"

// Didn't check whether the reg id is 0 or not.
// Thus may have unnecessary stalls

module riscv_CoreScoreboard
(
  input                   clk,
  input                   reset,
  input      [ 4:0]       src0,             // Source register 0
  input                   src0_en,          // Use source register 0
  input      [ 4:0]       src1,             // Source register 1
  input                   src1_en,          // Use source register 1
  input      [ 4:0]       dst,              // Destination register
  input                   dst_en,           // Write to destination register
  input      [ 2:0]       func_unit,        // Functional Unit
  input      [ 4:0]       latency,          // Instruction latency (one-hot)
  input                   inst_val_Dhl,     // Instruction valid
  input                   stall_Dhl,

  input      [`LOG_S-1:0] rob_alloc_slot,   // ROB slot allocated to dst reg
  input      [`LOG_S-1:0] rob_commit_slot,  // ROB slot emptied during commit
  input                   rob_commit_wen,   // ROB slot emptied during commit

  input      [ 4:0]       stalls,           // Input stall signals

  output reg [ 2:0]       src0_byp_mux_sel, // Source reg 0 byp mux
  output     [`LOG_S-1:0] src0_byp_rob_slot,// Source reg 0 ROB slot
  output reg [ 2:0]       src1_byp_mux_sel, // Source reg 1 byp mux
  output     [`LOG_S-1:0] src1_byp_rob_slot,// Source reg 1 ROB slot

  output                  stall_hazard,     // Destination register ready
  output     [ 1:0]       wb_mux_sel,       // Writeback mux sel out
  output                  stall_wb_hazard_M,
  output                  stall_wb_hazard_X
);

  reg              pending         [31:0];
  reg [2:0]        functional_unit [31:0];
  reg [4:0]        reg_latency     [31:0];
  reg [`LOG_S-1:0] reg_rob_slot    [31:0];

  reg [4:0]        wb_alu_latency;
  reg [4:0]        wb_mem_latency;
  reg [4:0]        wb_mul_latency;

  // Store ROB slots (for bypassing) with reset init
  integer i_rs;
  always @(posedge clk) begin
    if (reset) begin
      for (i_rs = 0; i_rs < 32; i_rs = i_rs + 1)
        reg_rob_slot[i_rs] <= {`LOG_S{1'b0}};
    end else if( accept && (!stall_Dhl)) begin
      reg_rob_slot[dst] <= rob_alloc_slot;
    end
  end

  assign src0_byp_rob_slot = reg_rob_slot[src0];
  assign src1_byp_rob_slot = reg_rob_slot[src1];

  // Check if src registers are ready (X-safe)

  function [0:0] is_lt4;
    input [4:0] v;
    begin
      is_lt4 = ((v[4]===1'b0) && (v[3]===1'b0) && (v[2]===1'b0));
    end
  endfunction

  wire pending0      = (pending[src0]   === 1'b1);
  wire pending1      = (pending[src1]   === 1'b1);
  wire src0_en_true  = (src0_en         === 1'b1);
  wire src1_en_true  = (src1_en         === 1'b1);

  wire src0_can_byp  = pending0 && is_lt4(reg_latency[src0]);
  wire src1_can_byp  = pending1 && is_lt4(reg_latency[src1]);

  wire src0_ok = (!pending0) || src0_can_byp || (!src0_en_true);
  wire src1_ok = (!pending1) || src1_can_byp || (!src1_en_true);

  // Sanitize incoming stalls (X-safe)
  wire [4:0] stalls_sanitized = { (stalls[4]===1'b1), (stalls[3]===1'b1),
                                  (stalls[2]===1'b1), (stalls[1]===1'b1), (stalls[0]===1'b1) };
  wire [4:0] stalls_alu    = {3'b0, stalls_sanitized[4], stalls_sanitized[0]};
  wire [4:0] stalls_mem    = {2'b0, stalls_sanitized[4:3], stalls_sanitized[0]};
  wire [4:0] stalls_muldiv = stalls_sanitized;

  wire [4:0] reg_latency_cur = reg_latency[src0];

  always @(*) begin
    if (!pending0 || src0 == 5'b00000 || !src0_en_true)
      src0_byp_mux_sel = 3'b0;
    else if (reg_latency[src0] === 5'b00001)
      src0_byp_mux_sel = 3'd4;
    else if (reg_latency[src0] === 5'b00000)
      src0_byp_mux_sel = 3'd5; // Bypass from ROB when ready
    else
      src0_byp_mux_sel = functional_unit[src0];
  end

  always @(*) begin
    if (!pending1 || src1 == 5'b00000 || !src1_en_true)
      src1_byp_mux_sel = 3'b0;
    else if (reg_latency[src1] === 5'b00001)
      src1_byp_mux_sel = 3'd4;
    else if (reg_latency[src1] === 5'b00000)
      src1_byp_mux_sel = 3'd5;   // Bypass from ROB when ready
    else
      src1_byp_mux_sel = functional_unit[src1];
  end

  // Check for hazards

  // X-safe writeback hazard detection
  wire haz_alu = (((wb_alu_latency >> 1) & latency) !== 5'b00000);
  wire haz_mem = (((wb_mem_latency >> 1) & latency) !== 5'b00000);
  wire haz_mul = (((wb_mul_latency >> 1) & latency) !== 5'b00000);
  wire stall_wb_hazard = haz_alu ? 1'b1 : haz_mem ? 1'b1 : haz_mul ? 1'b1 : 1'b0;

  // Accept core (ignoring inst_valid), and expose stall only when instruction is valid
  wire accept_core = src0_ok && src1_ok && !stall_wb_hazard;
  wire accept      = accept_core && (inst_val_Dhl === 1'b1);
  // Only assert scoreboard stall when we have a valid instruction; unknown/invalid acts as no-stall here
  assign stall_hazard = (inst_val_Dhl === 1'b1) ? ~accept_core : 1'b0;


  
  // Advance one cycle
  
  genvar r;
  generate
  for( r = 0; r < 32; r = r + 1)
  begin: sb_entry
    always @(posedge clk) begin
      if (reset) begin
        reg_latency[r]     <= 5'b0;
        pending[r]         <= 1'b0;
        functional_unit[r] <= 3'b0; 
      end else if ( accept && (r == dst) && (!stall_Dhl)) begin
        reg_latency[r]     <= latency;
        pending[r]         <= 1'b1;
        functional_unit[r] <= func_unit;
      end else begin

        pending[r]         <= pending[r] &&
          !(rob_commit_wen && rob_commit_slot == reg_rob_slot[r]);

        // Depending on what functional unit we're talking about,
        // we need to shift the stall vector over so that its stages
        // line up with the latency vector.
        if ((functional_unit[r] == `FUNC_UNIT_ALU)) begin
          reg_latency[r]     <= ( ( reg_latency[r] & (stalls_alu) ) |
                                ( ( reg_latency[r] & ~(stalls_alu) ) >> 1) );
        end
        else if ( functional_unit[r] == `FUNC_UNIT_MEM ) begin
          reg_latency[r]     <= ( ( reg_latency[r] & (stalls_mem) ) |
                                ( ( reg_latency[r] & ~(stalls_mem) ) >> 1) );
        end
        else begin
          reg_latency[r]     <= ( ( reg_latency[r] & stalls_muldiv ) |
                                ( ( reg_latency[r] & ~stalls_muldiv ) >> 1) );
        end
      end
    end
  end
  endgenerate

  // ALU Latency 

  always @(posedge clk) begin
    if (reset) begin
      wb_alu_latency <= 5'b0;
    end else if (accept && (func_unit == 2'd1) && (!stall_Dhl)) begin
      wb_alu_latency <= 
        (wb_alu_latency & (stalls_alu)) |
        ((wb_alu_latency & ~(stalls_alu)) >> 1) |
        latency;
    end else begin
      wb_alu_latency <= 
        (wb_alu_latency & (stalls_alu)) |
        ((wb_alu_latency & ~(stalls_alu)) >> 1);
    end
  end

  // MEM Latency 

  always @(posedge clk) begin
    if (reset) begin
      wb_mem_latency <= 5'b0;
    end else if (accept && (func_unit == 2'd2) && (!stall_Dhl)) begin
      wb_mem_latency <= 
        (wb_mem_latency & (stalls_mem)) |
        ((wb_mem_latency & ~(stalls_mem)) >> 1) |
        latency;
    end else begin
      wb_mem_latency <= 
        (wb_mem_latency & (stalls_mem)) |
        ((wb_mem_latency & ~(stalls_mem)) >> 1);
    end
  end

  // MUL Latency 

  always @(posedge clk) begin
    if (reset) begin
      wb_mul_latency <= 5'b0;
    end else if (accept && (func_unit == 2'd3) && (!stall_Dhl)) begin
      wb_mul_latency <= 
        (wb_mul_latency & stalls) |
        ((wb_mul_latency & ~stalls) >> 1) |
        latency;
    end else begin
      wb_mul_latency <= 
        (wb_mul_latency & stalls) |
        ((wb_mul_latency & ~stalls) >> 1);
    end
  end

  wire inst_val_is_x = (inst_val_Dhl !== 1'b0) && (inst_val_Dhl !== 1'b1);
  assign stall_wb_hazard_X = inst_val_is_x ? 1'b1 : ((wb_alu_latency[1] === 1'b1) && ((wb_mul_latency[1] === 1'b1) || (wb_mem_latency[1] === 1'b1)));
    assign stall_wb_hazard_M = inst_val_is_x ? 1'b1 : ((wb_mem_latency[1] === 1'b1) && (wb_mul_latency[1] === 1'b1));

  assign wb_mux_sel = (wb_mul_latency[1]) ? 2'd3 :
                      (wb_mem_latency[1]) ? 2'd2 :
                      (wb_alu_latency[1]) ? 2'd1 : 2'd0;

  //----------------------------------------------------------------------
  // Debug: trace X propagation (simulation only)
  //----------------------------------------------------------------------
  `ifndef SYNTHESIS
  always @(posedge clk) begin
    if (!reset) begin
      if ((stall_hazard === 1'bx) || (^wb_alu_latency === 1'bx) ||
          (^wb_mem_latency === 1'bx) || (^wb_mul_latency === 1'bx) ||
          (^stalls === 1'bx)) begin
        $display(" RTL-DEBUG : %m : scoreboard X at time %0t", $time);
        $display("   stalls=%b stalls_alu=%b stalls_mem=%b stalls_muldiv=%b",
                 stalls, stalls_alu, stalls_mem, stalls);
        $display("   wb_alu_lat=%b wb_mem_lat=%b wb_mul_lat=%b stall_hazard=%b accept=%b inst_val_Dhl=%b",
                 wb_alu_latency, wb_mem_latency, wb_mul_latency, stall_hazard, accept, inst_val_Dhl);
        $display("   src0=%0d pend0=%b lat0=%b fu0=%b slot0=%b",
                 src0, pending[src0], reg_latency[src0], functional_unit[src0], reg_rob_slot[src0]);
        $display("   src1=%0d pend1=%b lat1=%b fu1=%b slot1=%b",
                 src1, pending[src1], reg_latency[src1], functional_unit[src1], reg_rob_slot[src1]);
      end
    end
  end
  `endif

endmodule

`endif

//----------------------------------------------------------------------
// Debug instrumentation (simulation only)
//----------------------------------------------------------------------

`ifndef SYNTHESIS
module riscv_CoreScoreboard_debug_stub(); endmodule
`endif

`ifndef SYNTHESIS

`endif

