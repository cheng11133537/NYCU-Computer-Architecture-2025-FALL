//========================================================================
// Lab 1 - Three Input Iterative Mul Unit 
//========================================================================
`ifndef RISCV_INT_MULDIV_THREEINPUT_V
`define RISCV_INT_MULDIV_THREEINPUT_V

module imuldiv_IntMulThreeInput
(
  input         clk,
  input         reset,

  input   [2:0] muldivreq_msg_fn,     
  input  [31:0] muldivreq_msg_a,
  input  [31:0] muldivreq_msg_b,
  input  [31:0] muldivreq_msg_c,
  input         muldivreq_val,
  output        muldivreq_rdy,

  output [95:0] muldivresp_msg_result,
  output        muldivresp_val,
  input         muldivresp_rdy
);
  reg        s1_buf_val;
  wire       s1_buf_rdy;
  reg [63:0] s1_buf_P;   
  reg [31:0] s1_buf_c;   
  reg         s0_valid;
  reg  [63:0] s0_P_reg;  
  reg  [31:0] s0_c_reg;
  wire s1_buf_can_take = (~s1_buf_val);
  assign muldivreq_rdy = (~s0_valid) && s1_buf_can_take;
  wire signed [63:0] ab64 = $signed(muldivreq_msg_a) * $signed(muldivreq_msg_b);
  wire s0_fire = muldivreq_val && muldivreq_rdy;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      s0_valid   <= 1'b0;
      s0_P_reg   <= 64'd0;
      s0_c_reg   <= 32'd0;
      s1_buf_val <= 1'b0;
      s1_buf_P   <= 64'd0;
      s1_buf_c   <= 32'd0;
    end
    else begin
      if (s0_fire) begin
        s0_valid <= 1'b1;
        s0_P_reg <= ab64;                 
        s0_c_reg <= muldivreq_msg_c;
      end
      if (s0_valid && s1_buf_can_take) begin
        s1_buf_val <= 1'b1;
        s1_buf_P   <= s0_P_reg;
        s1_buf_c   <= s0_c_reg;
        s0_valid   <= 1'b0;               
      end
      else if (s1_buf_val && s1_buf_rdy) begin
        s1_buf_val <= 1'b0;
      end
    end
  end
  wire        s1_req_val = s1_buf_val;
  wire [63:0] s1_req_P   = s1_buf_P;
  wire [31:0] s1_req_c   = s1_buf_c;
  wire        s1_resp_val;
  wire [95:0] s1_resp_result;

  imuldiv_IntMul64x32BoothR4 u_mul64x32 (
    .clk                 (clk),
    .reset               (reset),

    .mulreq_msg_P        (s1_req_P),
    .mulreq_msg_c        (s1_req_c),
    .mulreq_val          (s1_req_val),
    .mulreq_rdy          (s1_buf_rdy),

    .mulresp_msg_result  (s1_resp_result),
    .mulresp_val         (s1_resp_val),
    .mulresp_rdy         (muldivresp_rdy)
  );

  assign muldivresp_msg_result = s1_resp_result;
  assign muldivresp_val        = s1_resp_val;

endmodule

module imuldiv_IntMul64x32BoothR4
(
  input         clk,
  input         reset,
  input  [63:0] mulreq_msg_P,  
  input  [31:0] mulreq_msg_c,   
  input         mulreq_val,
  output        mulreq_rdy,
  output [95:0] mulresp_msg_result,
  output        mulresp_val,
  input         mulresp_rdy
);
  localparam IDLE=2'b00, RUN=2'b01, RESP=2'b10;
  reg [1:0] state, nstate;
  reg  [63:0] P_reg;
  reg  [95:0] acc;       
  reg  [34:0] C_ext;     
  reg   [4:0] iter;      
  assign mulreq_rdy  = (state == IDLE);
  assign mulresp_val = (state == RESP);
  wire [95:0] P_base = { {32{P_reg[63]}}, P_reg };
  wire [2:0] booth_win = C_ext[2:0];
  wire [6:0] sh = {iter, 1'b0};  
  wire [95:0] A     = P_base << sh;
  wire [95:0] twoA  = A << 1;
  wire [95:0] negA  = (~A)    + 96'd1;
  wire [95:0] neg2A = (~twoA) + 96'd1;
  reg  [95:0] booth_add;
  always @(*) begin
    case (booth_win)
      3'b000, 3'b111: booth_add = 96'd0;
      3'b001, 3'b010: booth_add = A;
      3'b011:         booth_add = twoA;
      3'b100:         booth_add = neg2A;
      3'b101, 3'b110: booth_add = negA;
      default:        booth_add = 96'd0;
    endcase
  end

  wire [95:0] next_acc = acc + booth_add;

  always @(*) begin
    nstate = state;
    case (state)
      IDLE: if (mulreq_val)    nstate = RUN;
      RUN : if (iter == 5'd15) nstate = RESP;
      RESP: if (mulresp_rdy)   nstate = IDLE;
    endcase
  end

  always @(posedge clk or posedge reset) begin
    if (reset) state <= IDLE;
    else       state <= nstate;
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      P_reg <= 64'd0;
      acc   <= 96'd0;
      C_ext <= 35'd0;
      iter  <= 5'd0;
    end else begin
      case (state)
        IDLE: if (mulreq_val) begin
          P_reg <= mulreq_msg_P;                                  
          acc   <= 96'd0;
          C_ext <= { mulreq_msg_c[31], mulreq_msg_c[31], mulreq_msg_c, 1'b0 };
          iter  <= 5'd0;
        end
        RUN: begin
          acc   <= next_acc;
          C_ext <= { {2{C_ext[34]}}, C_ext[34:2] };
          iter  <= iter + 5'd1;
        end
        RESP: begin
        end
      endcase
    end
  end
  assign mulresp_msg_result = acc;
endmodule
`endif
