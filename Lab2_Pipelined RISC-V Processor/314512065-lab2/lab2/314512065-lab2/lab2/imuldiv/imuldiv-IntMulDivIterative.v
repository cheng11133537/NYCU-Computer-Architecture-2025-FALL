//========================================================================
// Lab 1 - Iterative Mul/Div Unit
//========================================================================

`ifndef RISCV_INT_MULDIV_ITERATIVE_V
`define RISCV_INT_MULDIV_ITERATIVE_V

`include "imuldiv-MulDivReqMsg.v"
`include "imuldiv-IntMulIterative.v"
`include "imuldiv-IntDivIterative.v"

// ----------------------------------------------------------------------
// Fallback encodings 
// ----------------------------------------------------------------------
`ifndef IMULDIV_MULDIVREQ_MSG_FUNC_MUL
  `define IMULDIV_MULDIVREQ_MSG_FUNC_MUL     3'b000
`endif
`ifndef IMULDIV_MULDIVREQ_MSG_FUNC_MULH
  `define IMULDIV_MULDIVREQ_MSG_FUNC_MULH    3'b001
`endif
`ifndef IMULDIV_MULDIVREQ_MSG_FUNC_MULHSU
  `define IMULDIV_MULDIVREQ_MSG_FUNC_MULHSU  3'b010
`endif
`ifndef IMULDIV_MULDIVREQ_MSG_FUNC_MULHU
  `define IMULDIV_MULDIVREQ_MSG_FUNC_MULHU   3'b011
`endif
`ifndef IMULDIV_MULDIVREQ_MSG_FUNC_DIV
  `define IMULDIV_MULDIVREQ_MSG_FUNC_DIV     3'b100
`endif
`ifndef IMULDIV_MULDIVREQ_MSG_FUNC_REM
  `define IMULDIV_MULDIVREQ_MSG_FUNC_REM     3'b101
`endif
// ----------------------------------------------------------------------

module imuldiv_IntMulDivIterative
(
  input         clk,
  input         reset,

  input   [2:0] muldivreq_msg_fn,
  input  [31:0] muldivreq_msg_a,
  input  [31:0] muldivreq_msg_b,
  input         muldivreq_val,
  output        muldivreq_rdy,

  output [63:0] muldivresp_msg_result,
  output        muldivresp_val,
  input         muldivresp_rdy
);

  //----------------------------------------------------------------------
  // Function decode
  //----------------------------------------------------------------------

  wire is_mul =
       ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MUL    )
    || ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULH   )
    || ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULHSU )
    || ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULHU  );

  wire is_mulh   = ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULH   );
  wire is_mulhsu = ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULHSU );
  wire is_mulhu  = ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULHU  );


  wire mulreq_signed_a = is_mulh | is_mulhsu;   
  wire mulreq_signed_b = is_mulh;               

  //----------------------------------------------------------------------
  // Handshake input select  
  //----------------------------------------------------------------------

  wire        mulreq_rdy;
  wire        divreq_rdy;

  wire mulreq_val = is_mul     && muldivreq_val && divreq_rdy;
  wire divreq_val = (~is_mul)  && muldivreq_val && mulreq_rdy;

  assign muldivreq_rdy = mulreq_rdy && divreq_rdy;

  //----------------------------------------------------------------------
  // Submodule responses
  //----------------------------------------------------------------------

  wire        mulresp_val;
  wire        divresp_val;
  wire [63:0] mulresp_msg_result_full;  
  wire [63:0] divresp_msg_result;

  //----------------------------------------------------------------------
  // Mul/Div Modules
  //----------------------------------------------------------------------

imuldiv_IntMulIterative imul
  (
    .clk                (clk),
    .reset              (reset),
    .mulreq_msg_a       (muldivreq_msg_a),
    .mulreq_msg_b       (muldivreq_msg_b),
    .mulreq_signed_a    (mulreq_signed_a),  
    .mulreq_signed_b    (mulreq_signed_b),  
    .mulreq_val         (mulreq_val),
    .mulreq_rdy         (mulreq_rdy),
    .mulresp_msg_result (mulresp_msg_result_full),
    .mulresp_val        (mulresp_val),
    .mulresp_rdy        (muldivresp_rdy)
  );

  wire divreq_msg_fn_divrem =
       ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_DIV )
    || ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_REM );

  imuldiv_IntDivIterative idiv
  (
    .clk                (clk),
    .reset              (reset),
    .divreq_msg_fn      (divreq_msg_fn_divrem),
    .divreq_msg_a       (muldivreq_msg_a),
    .divreq_msg_b       (muldivreq_msg_b),
    .divreq_val         (divreq_val),
    .divreq_rdy         (divreq_rdy),
    .divresp_msg_result (divresp_msg_result),
    .divresp_val        (divresp_val),
    .divresp_rdy        (muldivresp_rdy)
  );

  //----------------------------------------------------------------------
  // Output select
  //----------------------------------------------------------------------


  wire [31:0] mul_lo32 = mulresp_msg_result_full[31:0];
  wire [31:0] mul_hi32 = mulresp_msg_result_full[63:32];

  wire [63:0] mulresp_msg_result_32sel
    = ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MUL    ) ? { mul_hi32, mul_lo32 } : 
      ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULH   ) ? { 32'b0, mul_hi32 } :
      ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULHSU ) ? { 32'b0, mul_hi32 } :
      ( muldivreq_msg_fn == `IMULDIV_MULDIVREQ_MSG_FUNC_MULHU  ) ? { 32'b0, mul_hi32 } :
                                                                   mulresp_msg_result_full; // default


  assign muldivresp_val        = mulresp_val | divresp_val;
  assign muldivresp_msg_result = mulresp_val ? mulresp_msg_result_full
                                           : divresp_msg_result;

endmodule

`endif


