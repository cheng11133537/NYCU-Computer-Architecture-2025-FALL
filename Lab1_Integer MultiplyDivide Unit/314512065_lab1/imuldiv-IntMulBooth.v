//========================================================================
// Lab 1 - Booth Iterative Mul Unit
//========================================================================

`ifndef RISCV_INT_MUL_BOOTH_V
`define RISCV_INT_MUL_BOOTH_V

module imuldiv_IntMulBooth
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
  wire        [2:0]b_lsb;
  wire        ctr_done;

  imuldiv_IntMulBoothDpath dpath
  (
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
    .b_lsb             (b_lsb),
    .ctr_done          (ctr_done),
    .mulresp_msg_result(mulresp_msg_result)
  );

  imuldiv_IntMulBoothCtrl ctrl
  (
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
    .sign_mux_sel      (sign_mux_sel)
  );

endmodule

//------------------------------------------------------------------------
// Datapath
//------------------------------------------------------------------------

module imuldiv_IntMulBoothDpath
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

  output [2:0]  b_lsb,
  output        ctr_done,

  output [63:0] mulresp_msg_result
);

  //----------------------------------------------------------------------
  // Sequential Logic
  //----------------------------------------------------------------------
  reg [63:0] a_reg;
  reg [32:0] b_reg;
  reg [63:0] result_reg;
  reg [4:0]  counter;
  reg        sign_reg;
  wire sign_a = mulreq_msg_a[31];
  wire sign_b = mulreq_msg_b[31];
  wire [31:0] unsigned_a = sign_a ? (~mulreq_msg_a + 32'd1) : mulreq_msg_a;
  wire [31:0] unsigned_b = sign_b ? (~mulreq_msg_b + 32'd1) : mulreq_msg_b;
  wire        sign_calc  = sign_a ^ sign_b;
  wire [63:0] a_load      = {32'd0, unsigned_a};
  wire [63:0] a_shift_out = a_reg << 2;        //shift
  wire [32:0] b_load      = {unsigned_b,1'b0};
  wire [32:0] b_shift_out   = b_reg >> 2;      //shift
  wire [63:0] a_next = (a_mux_sel==1'b0) ? a_load : a_shift_out ;
  wire [32:0] b_next = (b_mux_sel==1'b0) ? b_load :b_shift_out;
  wire [2:0] win = b_reg[2:0];
  wire [63:0] plus_A   = a_reg;
  wire [63:0] plus_2A  = a_reg << 1;
  wire [63:0] minus_A  = ~a_reg + 64'd1;
  wire [63:0] minus_2A = ~(a_reg << 1) + 64'd1;
  reg  [63:0] booth_add;

  always @(*) begin
    case (win)
      3'b000, 3'b111: booth_add = 64'd0;
      3'b001, 3'b010: booth_add = plus_A;
      3'b011:         booth_add = plus_2A;
      3'b100:         booth_add = minus_2A;
      3'b101, 3'b110: booth_add = minus_A;
      default:        booth_add = 64'd0;
    endcase
  end

  wire [63:0] result_acc = result_reg + booth_add;
  wire [63:0] result_next= (result_mux_sel == 1'b0) ? 64'd0 : result_acc;
  wire [4:0]  counter_next = (cntr_mux_sel == 1'b0) ? 5'd0 : (counter + 5'd1);
  // Sequential
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      a_reg      <= 64'd0;
      b_reg      <= 33'd0;
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
  assign b_lsb = b_reg[2:0];
  assign ctr_done = (counter == 5'd15); 
  wire [63:0] signed_result = sign_reg ? (~result_reg + 64'd1) : result_reg;
  assign mulresp_msg_result = (sign_mux_sel==1'b1) ? signed_result : result_reg;
endmodule

//------------------------------------------------------------------------
// Control Logic
//------------------------------------------------------------------------

module imuldiv_IntMulBoothCtrl
(
  input  clk,
  input  reset,

  input  mulreq_val,
  output reg mulreq_rdy,
  output reg mulresp_val,
  input  mulresp_rdy,

  input  [2:0] b_lsb,
  input        ctr_done,

  output reg a_en,
  output reg b_en,
  output reg result_en,
  output reg sign_en,
  output reg ctr_en,

  output reg a_mux_sel,
  output reg b_mux_sel,
  output reg result_mux_sel,
  output reg cntr_mux_sel,
  output reg sign_mux_sel
);

  localparam IDLE = 2'b00;
  localparam RUN  = 2'b01;
  localparam RESP = 2'b10;

  reg [1:0] state, nstate;

  always @(posedge clk or posedge reset)
    if (reset) state <= IDLE;
    else       state <= nstate;

  always @(*) begin
    // defaults
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

    nstate         = state;
    case (state)
      IDLE: begin
        mulreq_rdy = 1'b1;
        if (mulreq_val) begin
          a_en           = 1'b1;
          b_en           = 1'b1;
          result_en      = 1'b1;
          ctr_en         = 1'b1;
          sign_en        = 1'b1;

          a_mux_sel      = 1'b0; 
          b_mux_sel      = 1'b0; 
          result_mux_sel = 1'b0; 
          cntr_mux_sel   = 1'b0; 
          nstate         = RUN;
        end
      end
      RUN: begin
        a_en           = 1'b1;
        b_en           = 1'b1;
        result_en      = 1'b1;
        ctr_en         = 1'b1;
        a_mux_sel      = 1'b1; 
        b_mux_sel      = 1'b1; 
        result_mux_sel = 1'b1; 
        cntr_mux_sel   = 1'b1; 
        if (ctr_done) begin
          a_en         = 1'b0;
          b_en         = 1'b0;
          ctr_en       = 1'b0;
          sign_mux_sel = 1'b1;
          nstate       = RESP;
        end
      end
      RESP: begin
        sign_mux_sel = 1'b1;
        mulresp_val  = 1'b1;
        if (mulresp_rdy) begin
          nstate = IDLE;
        end
      end
    endcase
  end
endmodule
`endif

