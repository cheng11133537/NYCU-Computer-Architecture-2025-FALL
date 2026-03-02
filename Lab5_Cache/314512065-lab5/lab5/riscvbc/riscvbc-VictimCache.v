// =========================================================================
// Victim Cache 
// =========================================================================

`ifndef RISCV_VICTIM_CACHE_V
`define RISCV_VICTIM_CACHE_V

`include "riscvbc-CacheMsg.v"

module riscv_VictimCache (
  input                   clk,
  input                   reset,
  input                   vc_ins_val,
  input  [`TAG_BITS-1:0]  vc_ins_tag,
  input  [`IDX_BITS-1:0]  vc_ins_idx,
  input  [`BLK_SIZE-1:0]  vc_ins_data,
  input                   vc_ins_dirty,
  input                   vc_lu_val,
  input  [`TAG_BITS-1:0]  vc_lu_tag,
  input  [`IDX_BITS-1:0]  vc_lu_idx,
  output                  vc_lu_hit,
  output                  vc_lu_way,     
  output [`BLK_SIZE-1:0]  vc_lu_data,
  output                  vc_lu_dirty,
  output                  vc_sel_way,
  output                  vc_evict_val,
  output [`TAG_BITS-1:0]  vc_evict_tag,
  output [`IDX_BITS-1:0]  vc_evict_idx,
  output [`BLK_SIZE-1:0]  vc_evict_data,
  output                  vc_evict_dirty
);

localparam VC_WAY0 = 1'b0;
localparam VC_WAY1 = 1'b1;

localparam ENTRY_SZ = `TAG_BITS + `IDX_BITS + 2; // {tag, idx, dirty, valid}

reg [`BLK_SIZE-1:0] vc_line0_q, vc_line1_q;
reg [`TAG_BITS-1:0] vc_tag0_q,  vc_tag1_q;
reg [`IDX_BITS-1:0] vc_idx0_q,  vc_idx1_q;
reg                 vc_dirty0_q, vc_dirty1_q;
reg                 vc_valid0_q, vc_valid1_q;
reg                 vc_lru_hint;

wire hit_way0 = vc_lu_val && vc_valid0_q &&
                (vc_tag0_q == vc_lu_tag) &&
                (vc_idx0_q == vc_lu_idx);
wire hit_way1 = vc_lu_val && vc_valid1_q &&
                (vc_tag1_q == vc_lu_tag) &&
                (vc_idx1_q == vc_lu_idx);

assign vc_lu_hit   = hit_way0 | hit_way1;
assign vc_lu_way   = hit_way1;
assign vc_lu_data  = hit_way1 ? vc_line1_q : vc_line0_q;
assign vc_lu_dirty = hit_way1 ? vc_dirty1_q : vc_dirty0_q;
assign vc_sel_way  = repl_sel;

wire way0_free = ~vc_valid0_q;
wire way1_free = ~vc_valid1_q;

wire repl_sel =
  way0_free ? VC_WAY0 :
  way1_free ? VC_WAY1 :
              vc_lru_hint;

// Eviction info 
assign vc_evict_val   = vc_ins_val && ((repl_sel == VC_WAY0 && vc_valid0_q) ||
                                       (repl_sel == VC_WAY1 && vc_valid1_q));
assign vc_evict_tag   = (repl_sel == VC_WAY1) ? vc_tag1_q   : vc_tag0_q;
assign vc_evict_idx   = (repl_sel == VC_WAY1) ? vc_idx1_q   : vc_idx0_q;
assign vc_evict_data  = (repl_sel == VC_WAY1) ? vc_line1_q  : vc_line0_q;
assign vc_evict_dirty = (repl_sel == VC_WAY1) ? vc_dirty1_q : vc_dirty0_q;

always @(posedge clk) begin
  if (reset) begin
    vc_line0_q   <= {`BLK_SIZE{1'b0}};
    vc_line1_q   <= {`BLK_SIZE{1'b0}};
    vc_tag0_q    <= {`TAG_BITS{1'b0}};
    vc_tag1_q    <= {`TAG_BITS{1'b0}};
    vc_idx0_q    <= {`IDX_BITS{1'b0}};
    vc_idx1_q    <= {`IDX_BITS{1'b0}};
    vc_dirty0_q  <= 1'b0;
    vc_dirty1_q  <= 1'b0;
    vc_valid0_q  <= 1'b0;
    vc_valid1_q  <= 1'b0;
    vc_lru_hint  <= VC_WAY0;
  end
  else begin
    // Insert path has priority
    if (vc_ins_val) begin
      if (repl_sel == VC_WAY0) begin
        vc_line0_q  <= vc_ins_data;
        vc_tag0_q   <= vc_ins_tag;
        vc_idx0_q   <= vc_ins_idx;
        vc_dirty0_q <= vc_ins_dirty;
        vc_valid0_q <= 1'b1;
      end
      else begin
        vc_line1_q  <= vc_ins_data;
        vc_tag1_q   <= vc_ins_tag;
        vc_idx1_q   <= vc_ins_idx;
        vc_dirty1_q <= vc_ins_dirty;
        vc_valid1_q <= 1'b1;
      end
      // Mark the other way as LRU after an insert
      vc_lru_hint <= ~repl_sel;
    end
    // Lookup hit updates LRU 
    else if (vc_lu_hit) begin
      vc_lru_hint <= ~vc_lu_way;
    end
  end
end

endmodule

`endif /* RISCV_VICTIM_CACHE_V */
