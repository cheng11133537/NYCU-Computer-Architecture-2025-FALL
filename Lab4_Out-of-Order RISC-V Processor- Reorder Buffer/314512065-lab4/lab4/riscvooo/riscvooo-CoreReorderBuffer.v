//=========================================================================
// 5-Stage RISCV Scoreboard - Reorder Buffer 
//=========================================================================
`ifndef RISCV_CORE_REORDERBUFFER_V
`define RISCV_CORE_REORDERBUFFER_V

module riscv_CoreReorderBuffer
(
  input         clk,
  input         reset,

  // Allocation interface
  input         rob_alloc_req_val,
  output        rob_alloc_req_rdy,
  input  [ 4:0] rob_alloc_req_preg,
  output [ 3:0] rob_alloc_resp_slot,

  // Fill / writeback (from execution units)
  input         rob_fill_val,
  input  [ 3:0] rob_fill_slot,

  // Commit outputs (registered 1-cycle pulse)
  output        rob_commit_wen,
  output [ 3:0] rob_commit_slot,
  output [ 4:0] rob_commit_rf_waddr
);

  // ------------------------------------------------------------------
  // Storage
  // ------------------------------------------------------------------
  reg [15:0] valid;           // entry valid
  reg [15:0] pending;         // 1 = waiting for writeback
  reg [ 4:0] phys_reg [15:0]; // physical reg (destination)
  reg [ 3:0] head;            // commit pointer
  reg [ 3:0] tail;            // alloc pointer

  // Registered commit outputs (1-cycle pulse)
  reg        commit_wen_r;
  reg  [3:0] commit_slot_r;
  reg  [4:0] commit_preg_r;

  // ------------------------------------------------------------------
  // Usage tracking + counters (for Case A verification)
  // ------------------------------------------------------------------
  // combinational used (tail - head modulo 16)
  wire [3:0] entries_used_comb;
  reg  [3:0] entries_used_r;        // sampled per cycle
  reg  [3:0] max_used_observed;     // maximum observed used
  integer alloc_attempts;
  integer alloc_rejects;

  assign entries_used_comb = tail - head; // unsigned modulo 16 arithmetic works

  // ------------------------------------------------------------------
  // Combinational helpers
  // ------------------------------------------------------------------
  // Detect when a fill in this cycle targets the current head
  wire fill_to_head_true = rob_fill_val && (rob_fill_slot === head);

  // Head valid/pending
  wire head_valid   = valid[head];
  wire head_pending = pending[head];

  // Head ready: valid and not pending OR being filled this cycle
  wire head_ready_true = (head_valid   === 1'b1) && ((head_pending === 1'b0) || fill_to_head_true);

  // Projected next head if commit happens this cycle
  wire [3:0] head_after = head + ((head_ready_true === 1'b1) ? 4'd1 : 4'd0);

  // Projected tail if an allocation were to happen: conservatively assume +1
  wire [3:0] tail_after = tail + 4'd1;

  // Projected full: if after projected increment tail == head_after then full
  wire full_proj = (tail_after === head_after);

  // Allocation ready (combinational): allow alloc if not full under projection
  assign rob_alloc_req_rdy   = ~full_proj;

  // Allocation response slot is the current tail (combinational)
  assign rob_alloc_resp_slot = tail;

  // Commit outputs (combinational from registered values)
  assign rob_commit_wen      = commit_wen_r;
  assign rob_commit_slot     = commit_slot_r;
  assign rob_commit_rf_waddr = commit_preg_r;

  integer i;

  // ------------------------------------------------------------------
  // Runtime debug enable controlled by simulator plusarg +DBG=1
  // ------------------------------------------------------------------
  reg debug_rob_enable;
  initial begin
    // $test$plusargs returns 1 if present; set debug_rob_enable accordingly
    debug_rob_enable = $test$plusargs("DBG=1");
    if (debug_rob_enable) begin
      $display("[ROB] +DBG=1 detected - runtime debug enabled");
    end
  end

  // Helper task for snapshot string (for debug)
  task rob_snapshot;
    integer j;
    begin
      $write("[ROB][%0t] SNAP ", $time);
      for (j = 0; j < 8; j = j + 1) begin
        $write("e%0d:%0d/%0d/%0d ", j, valid[j], pending[j], phys_reg[j]);
      end
      $write(" head=%0d tail=%0d used=%0d rdy=%0d val=%0d\n",
             head, tail, entries_used_r, rob_alloc_req_rdy, rob_alloc_req_val);
    end
  endtask

  always @(posedge clk) begin
    if (reset) begin
      valid <= 16'b0;
      pending <= 16'b0;
      head <= 4'd0;
      tail <= 4'd0;
      commit_wen_r <= 1'b0;
      commit_slot_r <= 4'd0;
      commit_preg_r <= 5'd0;
      entries_used_r <= 4'd0;
      max_used_observed <= 4'd0;
      alloc_attempts <= 0;
      alloc_rejects <= 0;
      // clear phys_reg
      for (i = 0; i < 16; i = i + 1) begin
        phys_reg[i] <= 5'd0;
      end
    end else begin
      // sample current used (combinational)
      entries_used_r <= entries_used_comb;
      if (entries_used_comb > max_used_observed)
        max_used_observed <= entries_used_comb;

      // Default: clear commit pulse by default
      commit_wen_r <= 1'b0;
      commit_slot_r <= 4'd0;
      commit_preg_r <= 5'd0;

      // ------------------ Fill / writeback ------------------
      if (rob_fill_val) begin
        // Defensive: if fill to an invalid slot, print debug (if enabled)
        if (debug_rob_enable) begin
          if (!valid[rob_fill_slot]) begin
            $display("[ROB][%0t] WARN  FILL to invalid slot=%0d (valid=0) head=%0d tail=%0d",
                     $time, rob_fill_slot, head, tail);
          end
        end
        case (rob_fill_slot)
          4'd0:  pending[ 0] <= 1'b0;
          4'd1:  pending[ 1] <= 1'b0;
          4'd2:  pending[ 2] <= 1'b0;
          4'd3:  pending[ 3] <= 1'b0;
          4'd4:  pending[ 4] <= 1'b0;
          4'd5:  pending[ 5] <= 1'b0;
          4'd6:  pending[ 6] <= 1'b0;
          4'd7:  pending[ 7] <= 1'b0;
          4'd8:  pending[ 8] <= 1'b0;
          4'd9:  pending[ 9] <= 1'b0;
          4'd10: pending[10] <= 1'b0;
          4'd11: pending[11] <= 1'b0;
          4'd12: pending[12] <= 1'b0;
          4'd13: pending[13] <= 1'b0;
          4'd14: pending[14] <= 1'b0;
          4'd15: pending[15] <= 1'b0;
          default: ;
        endcase
        if (debug_rob_enable) begin
          $display("[ROB][%0t] FILL   slot=%0d (head=%0d tail=%0d) pending[%0d]<=0",
                   $time, rob_fill_slot, head, tail, rob_fill_slot);
        end
      end

      // ------------------ Commit ------------------
      if (head_ready_true === 1'b1) begin
        // register commit outputs (1-cycle pulse)
        commit_wen_r <= 1'b1;
        commit_slot_r <= head;
        commit_preg_r <= phys_reg[head];

        // mark entry invalid and advance head
        valid[head] <= 1'b0;
        pending[head] <= 1'b0;
        if (debug_rob_enable) begin
          $display("[ROB][%0t] COMMIT start slot=%0d preg=%0d head=%0d tail=%0d",
                   $time, head, phys_reg[head], head, tail);
        end
        head <= head + 4'd1;
        if (debug_rob_enable) begin
          // snapshot after commit decision
          rob_snapshot();
          $display("[ROB][%0t] COMMIT done  next_head=%0d (max_used=%0d)",
                   $time, head + 1, max_used_observed);
        end
      end

      // ------------------ Allocation ------------------
      // Count attempts for diagnostics
      if (rob_alloc_req_val) begin
        alloc_attempts <= alloc_attempts + 1;
        if (debug_rob_enable) begin
          $display("[ROB][%0t] ALLOC_TRY slot=%0d preg=%0d head=%0d tail=%0d used=%0d rdy=%0d",
                   $time, tail, rob_alloc_req_preg, head, tail, entries_used_comb, rob_alloc_req_rdy);
        end
      end

      // Allocate when request is valid and we are ready (combinational rdy used)
      if (rob_alloc_req_val && rob_alloc_req_rdy) begin
        valid[tail] <= 1'b1;
        pending[tail] <= 1'b1; // waiting for writeback
        phys_reg[tail] <= rob_alloc_req_preg;
        if (debug_rob_enable) begin
          $display("[ROB][%0t] ALLOC  slot=%0d preg=%0d (head=%0d tail=%0d) -> accepted",
                   $time, tail, rob_alloc_req_preg, head, tail);
        end
        tail <= tail + 4'd1;
      end else begin
        // show rejected alloc if alloc_val asserted but not rdy
        if (rob_alloc_req_val && !rob_alloc_req_rdy) begin
          alloc_rejects <= alloc_rejects + 1;
          if (debug_rob_enable) begin
            $display("[ROB][%0t] ALLOC  slot=%0d preg=%0d (head=%0d tail=%0d) -> REJECT (FULL) (used=%0d)",
                     $time, tail, rob_alloc_req_preg, head, tail, entries_used_comb);
          end
        end
      end

      // Optional: end-of-test stats print (when sentinel CSR is written you can also check these)
      // print periodic summary every 5000 cycles (example)
      if (debug_rob_enable) begin
        if ($time % 5000 == 0) begin
          $display("[ROB][%0t] STATS attempts=%0d rejects=%0d max_used=%0d",
                   $time, alloc_attempts, alloc_rejects, max_used_observed);
        end
      end
    end
  end

endmodule

`endif // RISCV_CORE_REORDERBUFFER_V


