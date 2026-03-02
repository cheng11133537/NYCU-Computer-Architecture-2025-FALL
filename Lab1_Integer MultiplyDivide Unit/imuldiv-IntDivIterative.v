//========================================================================
// Lab 1 - Iterative Div Unit 
//========================================================================

`ifndef RISCV_INT_DIV_ITERATIVE_V
`define RISCV_INT_DIV_ITERATIVE_V

`include "imuldiv-DivReqMsg.v"

module imuldiv_IntDivIterative
(
  input         clk,
  input         reset,

  input         divreq_msg_fn,      
  input  [31:0] divreq_msg_a,
  input  [31:0] divreq_msg_b,
  input         divreq_val,
  output        divreq_rdy,

  output [63:0] divresp_msg_result, 
  output        divresp_val,
  input         divresp_rdy
);

  wire        a_en, b_en, sign_en, ctr_en;
  wire        a_mux_sel, reg_sign_mux_sel, div_sign_mux_sel, sub_mux_sel;
  wire        sub_neg, ctr_done;

  imuldiv_IntDivIterativeDpath dpath (
    .clk                 (clk),
    .reset               (reset),
    .divreq_msg_a        (divreq_msg_a),
    .divreq_msg_b        (divreq_msg_b),
    .a_en                (a_en),
    .b_en                (b_en),
    .sign_en             (sign_en),
    .ctr_en              (ctr_en),
    .a_mux_sel           (a_mux_sel),
    .reg_sign_mux_sel    (reg_sign_mux_sel),
    .div_sign_mux_sel    (div_sign_mux_sel),
    .sub_mux_sel         (sub_mux_sel),
    .sub_neg             (sub_neg),
    .ctr_done            (ctr_done),
    .divresp_msg_result  (divresp_msg_result)
  );

  imuldiv_IntDivIterativeCtrl ctrl (
    .clk                 (clk),
    .reset               (reset),
    .divreq_val          (divreq_val),
    .divreq_rdy          (divreq_rdy),
    .divresp_val         (divresp_val),
    .divresp_rdy         (divresp_rdy),
    .is_signed           (divreq_msg_fn),
    .sub_neg             (sub_neg),
    .ctr_done            (ctr_done),
    .a_en                (a_en),
    .b_en                (b_en),
    .sign_en             (sign_en),
    .ctr_en              (ctr_en),
    .a_mux_sel           (a_mux_sel),
    .reg_sign_mux_sel    (reg_sign_mux_sel),
    .div_sign_mux_sel    (div_sign_mux_sel),
    .sub_mux_sel         (sub_mux_sel)
  );

endmodule

//------------------------------------------------------------------------
// Datapath
//------------------------------------------------------------------------

module imuldiv_IntDivIterativeDpath
(
  input         clk,
  input         reset,

  input  [31:0] divreq_msg_a,
  input  [31:0] divreq_msg_b,

  input         a_en,
  input         b_en,
  input         sign_en,
  input         ctr_en,
  input         a_mux_sel,           
  input         reg_sign_mux_sel,    
  input         div_sign_mux_sel,   
  input         sub_mux_sel,        

  output        sub_neg,
  output        ctr_done,

  output [63:0] divresp_msg_result
);

  reg  [64:0] a_reg;    
  reg  [64:0] b_reg;     
  reg  [4:0]  counter;
  reg         div_sign_reg, rem_sign_reg;
  wire sign_a = divreq_msg_a[31];
  wire sign_b = divreq_msg_b[31];
  wire [31:0] abs_a =(reg_sign_mux_sel && sign_a) ? (~divreq_msg_a + 32'd1) : divreq_msg_a;
  wire [31:0] abs_b =(reg_sign_mux_sel && sign_b) ? (~divreq_msg_b + 32'd1) : divreq_msg_b;
  wire        div_sign = reg_sign_mux_sel ? (sign_a ^ sign_b) : 1'b0;
  wire        rem_sign = reg_sign_mux_sel ? sign_a            : 1'b0;
  wire [64:0] a_load      = {33'b0, abs_a};          
  wire [64:0] a_shift_out = a_reg << 1;               
  wire [64:0] b_load      = {1'b0, abs_b, 32'b0};     
  wire [64:0] sub_out   = a_shift_out - b_reg;       
  assign      sub_neg   = sub_out[64];                
  wire [64:0] a_accept  = {sub_out[64:1], 1'b1};      
  wire [64:0] a_restore = a_shift_out;                
  wire [64:0] a_next    = (a_mux_sel == 1'b0) ? a_load : (sub_mux_sel ? a_accept : a_restore);
  wire clear_counter = (a_en && (a_mux_sel == 1'b0));
  assign ctr_done = (counter == 5'd31);

  // Sequential 
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      a_reg         <= 65'd0;
      b_reg         <= 65'd0;
      counter       <= 5'd0;
      div_sign_reg  <= 1'b0;
      rem_sign_reg  <= 1'b0;
    end else begin
      if (a_en) a_reg <= a_next;
      if (b_en) b_reg <= b_load;         
      if (clear_counter) counter <= 5'd0;
      else if (ctr_en)   counter <= counter + 5'd1;
      if (sign_en) begin
        div_sign_reg <= div_sign;
        rem_sign_reg <= rem_sign;
      end
    end
  end
  wire [31:0] quot_u = a_reg[31:0];
  wire [31:0] rem_u  = a_reg[63:32];
  wire [31:0] quot_s = div_sign_reg ? (~quot_u + 32'd1) : quot_u;
  wire [31:0] rem_s  = rem_sign_reg ? (~rem_u  + 32'd1) : rem_u;
  wire [31:0] quot_final = div_sign_mux_sel ? quot_s : quot_u;
  wire [31:0] rem_final  = reg_sign_mux_sel ? rem_s  : rem_u;
  assign divresp_msg_result = {rem_final, quot_final};

endmodule
//------------------------------------------------------------------------
// Control 
//------------------------------------------------------------------------
module imuldiv_IntDivIterativeCtrl
(
  input  clk,
  input  reset,
  input  divreq_val,
  output reg divreq_rdy,
  output reg divresp_val,
  input  divresp_rdy,

  input  is_signed,
  input  sub_neg,
  input  ctr_done,

  output reg a_en,
  output reg b_en,
  output reg sign_en,
  output reg ctr_en,
  output reg a_mux_sel,
  output reg reg_sign_mux_sel,
  output reg div_sign_mux_sel,
  output reg sub_mux_sel
);

  localparam IDLE = 2'b00;
  localparam RUN  = 2'b01;
  localparam RESP = 2'b10;

  reg [1:0] state, nstate;
  always @(posedge clk or posedge reset)
    if (reset) state <= IDLE;
    else       state <= nstate;

  always @* begin
    // defaults
    divreq_rdy        = 1'b0;
    divresp_val       = 1'b0;
    a_en              = 1'b0;
    b_en              = 1'b0;
    sign_en           = 1'b0;
    ctr_en            = 1'b0;
    a_mux_sel         = 1'b0;
    reg_sign_mux_sel  = is_signed;
    div_sign_mux_sel  = is_signed;
    sub_mux_sel       = 1'b0;
    nstate            = state;

    case (state)
      IDLE: begin
        divreq_rdy = 1'b1;
        if (divreq_val) begin
          a_mux_sel  = 1'b0;  
          a_en       = 1'b1;
          b_en       = 1'b1;
          sign_en    = is_signed; 
          nstate     = RUN;
        end
      end
      RUN: begin
        a_mux_sel    = 1'b1;      
        a_en         = 1'b1;
        ctr_en       = 1'b1;
        sub_mux_sel  = ~sub_neg;  
        if (ctr_done) nstate = RESP;
      end
      RESP: begin
        divresp_val = 1'b1;
        if (divresp_rdy) nstate = IDLE;
      end
    endcase
  end
endmodule
`endif
