//=========================================================================
// Lab 1 - Iterative Mul Unit (with per-operand signed control)
//=========================================================================

`ifndef RISCV_INT_MUL_ITERATIVE_V
`define RISCV_INT_MUL_ITERATIVE_V

module imuldiv_IntMulIterative
(
  input                clk,
  input                reset,

  // Operands
  input  [31:0]        mulreq_msg_a,
  input  [31:0]        mulreq_msg_b,

  input                mulreq_signed_a,
  input                mulreq_signed_b,

  // Handshake in
  input                mulreq_val,
  output               mulreq_rdy,

  // Result (full 64-bit) + handshake out
  output [63:0]        mulresp_msg_result,
  output               mulresp_val,
  input                mulresp_rdy
);

  wire    [4:0] counter;
  wire          sign;
  wire          b_lsb;
  wire          sign_en;
  wire          result_en;
  wire          cntr_mux_sel;
  wire          a_mux_sel;
  wire          b_mux_sel;
  wire          result_mux_sel;
  wire          add_mux_sel;
  wire          sign_mux_sel;

  imuldiv_IntMulIterativeDpath dpath
  (
    .clk                (clk),
    .reset              (reset),

    .mulreq_msg_a       (mulreq_msg_a),
    .mulreq_msg_b       (mulreq_msg_b),
    .mulreq_signed_a    (mulreq_signed_a),
    .mulreq_signed_b    (mulreq_signed_b),

    .mulresp_msg_result (mulresp_msg_result),

    .counter            (counter),
    .sign               (sign),
    .b_lsb              (b_lsb),

    .sign_en            (sign_en),
    .result_en          (result_en),
    .cntr_mux_sel       (cntr_mux_sel),
    .a_mux_sel          (a_mux_sel),
    .b_mux_sel          (b_mux_sel),
    .result_mux_sel     (result_mux_sel),
    .add_mux_sel        (add_mux_sel),
    .sign_mux_sel       (sign_mux_sel)
  );

  imuldiv_IntMulIterativeCtrl ctrl
  (
    .clk            (clk),
    .reset          (reset),

    .mulreq_val     (mulreq_val),
    .mulreq_rdy     (mulreq_rdy),

    .mulresp_val    (mulresp_val),
    .mulresp_rdy    (mulresp_rdy),

    .counter        (counter),
    .sign           (sign),
    .b_lsb          (b_lsb),

    .sign_en        (sign_en),
    .result_en      (result_en),
    .cntr_mux_sel   (cntr_mux_sel),
    .a_mux_sel      (a_mux_sel),
    .b_mux_sel      (b_mux_sel),
    .result_mux_sel (result_mux_sel),
    .add_mux_sel    (add_mux_sel),
    .sign_mux_sel   (sign_mux_sel)
  );

endmodule

//------------------------------------------------------------------------
// Datapath
//------------------------------------------------------------------------

module imuldiv_IntMulIterativeDpath
(
  input                clk,
  input                reset,

  // Operands and Result
  input  [31:0]        mulreq_msg_a,
  input  [31:0]        mulreq_msg_b,
  input                mulreq_signed_a,
  input                mulreq_signed_b,
  output [63:0]        mulresp_msg_result,

  // Datapath Outputs
  output  [4:0]        counter,
  output               sign,
  output               b_lsb,

  // Control Inputs
  input                sign_en,
  input                result_en,
  input                cntr_mux_sel,
  input                a_mux_sel,
  input                b_mux_sel,
  input                result_mux_sel,
  input                add_mux_sel,
  input                sign_mux_sel
);

  //------
  // Control enums (for DP)
  //------
  localparam op_x     = 1'dx;
  localparam op_load  = 1'd0;
  localparam op_next  = 1'd1;

  localparam add_x    = 1'dx;
  localparam add_old  = 1'd0;
  localparam add_next = 1'd1;

  localparam sign_x   = 1'dx;
  localparam sign_u   = 1'd0;
  localparam sign_s   = 1'd1;

  //------
  // Pre-flop logic
  //------

  // Counter (32 iterations total: 31..0)
  reg  [4:0] counter_reg;
  wire [4:0] counter_mux_out
    = ( cntr_mux_sel == op_load ) ? 5'd31
    : ( cntr_mux_sel == op_next ) ? counter_reg - 1'b1
    :                               counter_reg;
  assign counter = counter_reg;

  // Decide negativity only when that operand is signed
  wire a_neg = mulreq_signed_a & mulreq_msg_a[31];
  wire b_neg = mulreq_signed_b & mulreq_msg_b[31];

  // Result sign = XOR of effective signs
  reg sign_reg;
  wire sign_next = a_neg ^ b_neg;
  assign sign    = sign_reg;

  // Take absolute value only for signed-negative operands
  wire [31:0] unsigned_a = a_neg ? (~mulreq_msg_a + 32'd1) : mulreq_msg_a;
  wire [31:0] unsigned_b = b_neg ? (~mulreq_msg_b + 32'd1) : mulreq_msg_b;

  // Operand regs
  reg  [63:0] a_reg;
  reg  [31:0] b_reg;

  // Shifted versions
  wire [63:0] a_shift_out = a_reg << 1;
  wire [31:0] b_shift_out = b_reg >> 1;

  // Operand muxes
  wire [63:0] a_mux_out
    = ( a_mux_sel == op_load ) ? { 32'b0, unsigned_a }
    : ( a_mux_sel == op_next ) ? a_shift_out
    :                            a_reg;

  wire [31:0] b_mux_out
    = ( b_mux_sel == op_load ) ? unsigned_b
    : ( b_mux_sel == op_next ) ? b_shift_out
    :                            b_reg;

  // Result reg and adder
  reg  [63:0] result_reg;
  wire [63:0] add_out     = result_reg + a_reg;
  wire [63:0] add_mux_out
    = ( add_mux_sel == add_old )  ? result_reg
    : ( add_mux_sel == add_next ) ? add_out
    :                               result_reg;

  wire [63:0] result_mux_out
    = ( result_mux_sel == op_load ) ? 64'b0
    : ( result_mux_sel == op_next ) ? add_mux_out
    :                                 result_reg;

  //------
  // Sequential
  //------
  always @ ( posedge clk ) begin
    if ( reset ) begin
      sign_reg    <= 1'b0;
      result_reg  <= 64'b0;
      counter_reg <= 5'd0;
      a_reg       <= 64'b0;
      b_reg       <= 32'b0;
    end
    else begin
      if ( sign_en )    sign_reg   <= sign_next;
      if ( result_en )  result_reg <= result_mux_out;
      counter_reg       <= counter_mux_out;
      a_reg             <= a_mux_out;
      b_reg             <= b_mux_out;
    end
  end

  //------
  // Post-flop logic
  //------
  assign b_lsb = b_reg[0];

  // Final sign-fix (two's complement if negative) is applied only
  // in SIGN phase via sign_mux_sel from the controller.
  wire [63:0] result_fixed
    = ( sign_mux_sel == sign_s ) ? (~result_reg + 64'd1)
    :                              result_reg;

  assign mulresp_msg_result = result_fixed;

endmodule

//------------------------------------------------------------------------
// Control Logic
//------------------------------------------------------------------------

module imuldiv_IntMulIterativeCtrl
(
  input        clk,
  input        reset,

  // Request val/rdy
  input        mulreq_val,
  output       mulreq_rdy,

  // Response val/rdy
  output       mulresp_val,
  input        mulresp_rdy,

  // Datapath Inputs
  input  [4:0] counter,
  input        sign,
  input        b_lsb,

  // Control Outputs
  output       sign_en,
  output       result_en,
  output       cntr_mux_sel,
  output       a_mux_sel,
  output       b_mux_sel,
  output       result_mux_sel,
  output       add_mux_sel,
  output       sign_mux_sel
);

  //------
  // FSM
  //------
  localparam STATE_IDLE = 2'd0;
  localparam STATE_CALC = 2'd1;
  localparam STATE_SIGN = 2'd2;

  reg [1:0] state_reg, state_next;

  always @ ( posedge clk ) begin
    if ( reset )
      state_reg <= STATE_IDLE;
    else
      state_reg <= state_next;
  end

  wire mulreq_go    = mulreq_val  && mulreq_rdy;
  wire mulresp_go   = mulresp_val && mulresp_rdy;
  wire is_calc_done = ( counter == 5'd0 );

  always @ ( * ) begin
    state_next = state_reg;
    case ( state_reg )
      STATE_IDLE: if ( mulreq_go )     state_next = STATE_CALC;
      STATE_CALC: if ( is_calc_done )  state_next = STATE_SIGN;
      STATE_SIGN: if ( mulresp_go )    state_next = STATE_IDLE;
      default   :                      state_next = STATE_IDLE;
    endcase
  end

  //------
  // Enums for CTRL 
  //------
  localparam op_load  = 1'd0;
  localparam op_next  = 1'd1;

  localparam add_old  = 1'd0;
  localparam add_next = 1'd1;

  localparam sign_u   = 1'd0;
  localparam sign_s   = 1'd1;

  //------
  // Output control
  //------
  localparam n = 1'd0;
  localparam y = 1'd1;

  reg mulreq_rdy_r, mulresp_val_r;
  reg sign_en_r, result_en_r;
  reg cntr_mux_sel_r, a_mux_sel_r, b_mux_sel_r, result_mux_sel_r;
  reg add_mux_sel_r, sign_mux_sel_r;

  always @(*) begin
    // defaults
    mulreq_rdy_r     = n;
    mulresp_val_r    = n;
    sign_en_r        = n;
    result_en_r      = n;
    cntr_mux_sel_r   = op_load;
    a_mux_sel_r      = op_load;
    b_mux_sel_r      = op_load;
    result_mux_sel_r = op_load;
    add_mux_sel_r    = add_old;
    sign_mux_sel_r   = sign_u;   

    case (state_reg)
      STATE_IDLE: begin
        mulreq_rdy_r = y;
        if ( mulreq_go ) begin
          sign_en_r        = y;
          result_en_r      = y;        
          cntr_mux_sel_r   = op_load;  
          a_mux_sel_r      = op_load;  
          b_mux_sel_r      = op_load;  
          result_mux_sel_r = op_load;  
        end
      end
      STATE_CALC: begin
        result_en_r      = y;
        cntr_mux_sel_r   = op_next;    
        a_mux_sel_r      = op_next;    
        b_mux_sel_r      = op_next;    
        result_mux_sel_r = op_next;    
        add_mux_sel_r    = b_lsb;      
      end
      STATE_SIGN: begin
        mulresp_val_r   = y;
        sign_mux_sel_r  = sign ? sign_s : sign_u;
      end

      default: begin
        mulreq_rdy_r = y;
      end
    endcase
  end

  assign mulreq_rdy     = mulreq_rdy_r;
  assign mulresp_val    = mulresp_val_r;
  assign sign_en        = sign_en_r;
  assign result_en      = result_en_r;
  assign cntr_mux_sel   = cntr_mux_sel_r;
  assign a_mux_sel      = a_mux_sel_r;
  assign b_mux_sel      = b_mux_sel_r;
  assign result_mux_sel = result_mux_sel_r;
  assign add_mux_sel    = add_mux_sel_r;
  assign sign_mux_sel   = sign_mux_sel_r;

endmodule

`endif
//revise ok
