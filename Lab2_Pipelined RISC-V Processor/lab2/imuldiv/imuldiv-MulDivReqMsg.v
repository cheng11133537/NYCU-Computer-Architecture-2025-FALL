//========================================================================
// imuldiv-MulDivReqMsg : Multiplier/Divider Request Message (Extended)
//========================================================================

`ifndef IMULDIV_MULDIVREQ_MSG_V
`define IMULDIV_MULDIVREQ_MSG_V

//------------------------------------------------------------------------
// Message defines
//------------------------------------------------------------------------

`define IMULDIV_MULDIVREQ_MSG_SZ         67

//------------------------------------------------------------------------
// Function field (3 bits)
//------------------------------------------------------------------------

`define IMULDIV_MULDIVREQ_MSG_FUNC_SZ    3
`define IMULDIV_MULDIVREQ_MSG_FUNC_MUL     3'd0
`define IMULDIV_MULDIVREQ_MSG_FUNC_MULH    3'd1
`define IMULDIV_MULDIVREQ_MSG_FUNC_MULHSU  3'd2
`define IMULDIV_MULDIVREQ_MSG_FUNC_MULHU   3'd3
`define IMULDIV_MULDIVREQ_MSG_FUNC_DIV     3'd4
`define IMULDIV_MULDIVREQ_MSG_FUNC_DIVU    3'd5
`define IMULDIV_MULDIVREQ_MSG_FUNC_REM     3'd6
`define IMULDIV_MULDIVREQ_MSG_FUNC_REMU    3'd7

//------------------------------------------------------------------------
// Operand field sizes
//------------------------------------------------------------------------

`define IMULDIV_MULDIVREQ_MSG_A_SZ       32
`define IMULDIV_MULDIVREQ_MSG_B_SZ       32

//------------------------------------------------------------------------
// Bitfield layout
//------------------------------------------------------------------------

`define IMULDIV_MULDIVREQ_MSG_FUNC_FIELD 66:64
`define IMULDIV_MULDIVREQ_MSG_A_FIELD    63:32
`define IMULDIV_MULDIVREQ_MSG_B_FIELD    31:0

//------------------------------------------------------------------------
// Convert message to bits
//------------------------------------------------------------------------

module imuldiv_MulDivReqMsgToBits
(
  input [`IMULDIV_MULDIVREQ_MSG_FUNC_SZ-1:0] func,
  input [`IMULDIV_MULDIVREQ_MSG_A_SZ-1:0]    a,
  input [`IMULDIV_MULDIVREQ_MSG_B_SZ-1:0]    b,
  output [`IMULDIV_MULDIVREQ_MSG_SZ-1:0]     bits
);
  assign bits[`IMULDIV_MULDIVREQ_MSG_FUNC_FIELD] = func;
  assign bits[`IMULDIV_MULDIVREQ_MSG_A_FIELD]    = a;
  assign bits[`IMULDIV_MULDIVREQ_MSG_B_FIELD]    = b;
endmodule

//------------------------------------------------------------------------
// Convert message from bits
//------------------------------------------------------------------------

module imuldiv_MulDivReqMsgFromBits
(
  input  [`IMULDIV_MULDIVREQ_MSG_SZ-1:0] bits,
  output [`IMULDIV_MULDIVREQ_MSG_FUNC_SZ-1:0] func,
  output [`IMULDIV_MULDIVREQ_MSG_A_SZ-1:0]    a,
  output [`IMULDIV_MULDIVREQ_MSG_B_SZ-1:0]    b
);
  assign func = bits[`IMULDIV_MULDIVREQ_MSG_FUNC_FIELD];
  assign a    = bits[`IMULDIV_MULDIVREQ_MSG_A_FIELD];
  assign b    = bits[`IMULDIV_MULDIVREQ_MSG_B_FIELD];
endmodule

//------------------------------------------------------------------------
// Convert message to string (for simulation debug)
//------------------------------------------------------------------------

`ifndef SYNTHESIS
module imuldiv_MulDivReqMsgToStr
(
  input [`IMULDIV_MULDIVREQ_MSG_SZ-1:0] msg
);

  wire [`IMULDIV_MULDIVREQ_MSG_FUNC_SZ-1:0] func = msg[`IMULDIV_MULDIVREQ_MSG_FUNC_FIELD];
  wire [`IMULDIV_MULDIVREQ_MSG_A_SZ-1:0]    a    = msg[`IMULDIV_MULDIVREQ_MSG_A_FIELD];
  wire [`IMULDIV_MULDIVREQ_MSG_B_SZ-1:0]    b    = msg[`IMULDIV_MULDIVREQ_MSG_B_FIELD];

  reg [20*8-1:0] full_str;

  always @(*) begin
    case (func)
      3'd0: $sformat(full_str, "mul     %d, %d", a, b);
      3'd1: $sformat(full_str, "mulh    %d, %d", a, b);
      3'd2: $sformat(full_str, "mulhsu  %d, %d", a, b);
      3'd3: $sformat(full_str, "mulhu   %d, %d", a, b);
      3'd4: $sformat(full_str, "div     %d, %d", a, b);
      3'd5: $sformat(full_str, "divu    %d, %d", a, b);
      3'd6: $sformat(full_str, "rem     %d, %d", a, b);
      3'd7: $sformat(full_str, "remu    %d, %d", a, b);
      default: $sformat(full_str, "undefined");
    endcase
  end

endmodule
`endif

`endif