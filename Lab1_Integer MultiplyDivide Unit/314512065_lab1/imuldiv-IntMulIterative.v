//========================================================================
// Lab 1 - Iterative Mul Unit 
//========================================================================

`ifndef RISCV_INT_MUL_ITERATIVE_V
`define RISCV_INT_MUL_ITERATIVE_V

module imuldiv_IntMulIterative
(
  input                clk,
  input                reset,

  input  [31:0] mulreq_msg_a,
  input  [31:0] mulreq_msg_b,
  input         mulreq_val,
  output        mulreq_rdy,

  output [63:0] mulresp_msg_result,
  output        mulresp_val,
  input         mulresp_rdy
);

  wire        a_en, b_en, result_en, sign_en, ctr_en;
  wire        a_mux_sel, b_mux_sel;
  wire        result_mux_sel;
  wire        cntr_mux_sel, sign_mux_sel,add_mux_sel;
  wire        b_lsb, ctr_done;

  // ---- Dpath ----
  imuldiv_IntMulIterativeDpath dpath (
    .clk               (clk),
    .reset             (reset),
    .mulreq_msg_a      (mulreq_msg_a),
    .mulreq_msg_b      (mulreq_msg_b),
    .a_en              (a_en),
    .b_en              (b_en),
    .result_en         (result_en),
    .sign_en           (sign_en),
    .ctr_en            (ctr_en),
    .a_mux_sel         (a_mux_sel),
    .b_mux_sel         (b_mux_sel),
    .result_mux_sel    (result_mux_sel),
    .cntr_mux_sel      (cntr_mux_sel),
    .sign_mux_sel      (sign_mux_sel),
    .add_mux_sel       (add_mux_sel),
    .b_lsb             (b_lsb),
    .ctr_done          (ctr_done),
    .mulresp_msg_result(mulresp_msg_result)
  );

  // ---- Ctrl ----
  imuldiv_IntMulIterativeCtrl ctrl (
    .clk               (clk),
    .reset             (reset),
    .mulreq_val        (mulreq_val),
    .mulreq_rdy        (mulreq_rdy),
    .mulresp_val       (mulresp_val),
    .mulresp_rdy       (mulresp_rdy),
    .b_lsb             (b_lsb),
    .ctr_done          (ctr_done),
    .a_en              (a_en),
    .b_en              (b_en),
    .result_en         (result_en),
    .sign_en           (sign_en),
    .ctr_en            (ctr_en),
    .a_mux_sel         (a_mux_sel),
    .b_mux_sel         (b_mux_sel),
    .result_mux_sel    (result_mux_sel),
    .cntr_mux_sel      (cntr_mux_sel),
    .sign_mux_sel      (sign_mux_sel),
    .add_mux_sel        (add_mux_sel)
  );

endmodule

//------------------------------------------------------------------------
// Datapath
//------------------------------------------------------------------------
module imuldiv_IntMulIterativeDpath
(
  input         clk,
  input         reset,

  input  [31:0] mulreq_msg_a,
  input  [31:0] mulreq_msg_b,

  input         a_en,
  input         b_en,
  input         result_en,
  input         sign_en,
  input         ctr_en,

  input         a_mux_sel,
  input         b_mux_sel,
  input         result_mux_sel,
  input         cntr_mux_sel,
  input         sign_mux_sel,
  input         add_mux_sel,

  output        b_lsb,
  output        ctr_done,

  output [63:0] mulresp_msg_result
);

  reg [63:0] a_reg;
  reg [31:0] b_reg;
  reg [63:0] result_reg;
  reg [4:0]  counter;
  reg        sign_reg;

  wire sign_a = mulreq_msg_a[31];
  wire sign_b = mulreq_msg_b[31];
  wire [31:0] unsigned_a = sign_a ? (~mulreq_msg_a + 32'd1) : mulreq_msg_a;
  wire [31:0] unsigned_b = sign_b ? (~mulreq_msg_b + 32'd1) : mulreq_msg_b;
  wire        sign_calc  = sign_a ^ sign_b;

  wire [63:0] a_load      = {32'b0, unsigned_a};
  wire [63:0] a_shift_out = a_reg << 1;        //shift

  wire [31:0] b_load      = unsigned_b;
  wire [31:0] b_shift_out   = b_reg >> 1;      //shift
  wire [63:0] a_next = (a_mux_sel==1'b0) ? a_load : (a_reg << 1) ;
  wire [31:0] b_next = (b_mux_sel==1'b0) ? b_load :(b_reg >> 1);
  wire [63:0] result_next =(result_mux_sel==1'b0)?64'd0:add_next;
  wire [63:0] add_next=(add_mux_sel==1'b0)?result_reg:(result_reg + a_reg);
  wire [4:0] counter_next = (cntr_mux_sel==1'b0) ? 5'd0 : (counter + 5'd1);

  // Sequential
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      a_reg      <= 64'd0;
      b_reg      <= 32'd0;
      result_reg <= 64'd0;
      counter    <= 5'd0;
      sign_reg   <= 1'b0;
    end else begin
      if (a_en)       a_reg      <= a_next;
      if (b_en)       b_reg      <= b_next;
      if (result_en)  result_reg <= result_next;
      if (ctr_en)     counter    <= counter_next;
      if (sign_en)    sign_reg   <= sign_calc;
    end
  end
  
  assign b_lsb    = b_reg[0];
  assign ctr_done = (counter == 5'd31); 
  wire [63:0] signed_result = sign_reg ? (~result_reg + 64'd1) : result_reg;
  assign mulresp_msg_result = (sign_mux_sel==1'b1) ? signed_result : result_reg;

endmodule

//------------------------------------------------------------------------
// Control Logic 
//------------------------------------------------------------------------
module imuldiv_IntMulIterativeCtrl
(
  input  clk,
  input  reset,
  input  mulreq_val,
  output reg mulreq_rdy,
  output reg mulresp_val,
  input  mulresp_rdy,
  input  b_lsb,
  input  ctr_done,
  output reg a_en,
  output reg b_en,
  output reg result_en,
  output reg sign_en,
  output reg ctr_en,
  output reg  a_mux_sel,
  output reg  b_mux_sel,
  output reg  result_mux_sel,
  output reg cntr_mux_sel,
  output reg sign_mux_sel,
  output reg add_mux_sel
);

  localparam IDLE = 2'b00;
  localparam RUN  = 2'b01;
  localparam RESP = 2'b10;
  reg [1:0] curr_state, next_state;
  always @(posedge clk or posedge reset) begin
    if (reset) curr_state <= IDLE;
    else       curr_state <= next_state;
  end

  always @(*) begin
    mulreq_rdy     = 1'b0;
    mulresp_val    = 1'b0;
    a_en           = 1'b0;
    b_en           = 1'b0;
    result_en      = 1'b0;
    sign_en        = 1'b0;
    ctr_en         = 1'b0;
    a_mux_sel      = 1'b0;
    b_mux_sel      = 1'b0;
    result_mux_sel = 1'b0;
    cntr_mux_sel   = 1'b0;
    sign_mux_sel   = 1'b0;
    add_mux_sel    = 1'b0;
    next_state     = curr_state;

    case(curr_state)

      IDLE: begin
        mulreq_rdy = 1'b1;
        if (mulreq_val) begin
          a_mux_sel      = 1'b0; 
          b_mux_sel      = 1'b0; 
          result_mux_sel = 1'b0; 
          cntr_mux_sel   = 1'b0;
          add_mux_sel    = 1'b0;  
          a_en           = 1'b1;
          b_en           = 1'b1;
          result_en      = 1'b1;
          ctr_en         = 1'b1;
          sign_en        = 1'b1;  
          next_state     = RUN;
        end
      end

      RUN: begin
        if (b_lsb) begin
          result_mux_sel = 1'b1;
          add_mux_sel =  1'b1;
          result_en      = 1'b1;
        end
        a_mux_sel    = 1'b1;
        b_mux_sel    = 1'b1;
        cntr_mux_sel = 1'b1;
        a_en         = 1'b1;
        b_en         = 1'b1;
        ctr_en       = 1'b1;
        if (ctr_done) begin
          a_en         = 1'b0;
          b_en         = 1'b0;
          ctr_en       = 1'b0;
          sign_mux_sel = 1'b1;
          next_state = RESP;
        end
      end
      RESP: begin
        sign_mux_sel = 1'b1;      
        mulresp_val  = 1'b1;     
        if (mulresp_rdy) begin  
          next_state = IDLE;
        end
      end
    endcase
  end

endmodule

`endif
