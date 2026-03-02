//=========================================================================
// Cache Base Design
//=========================================================================

`ifndef RISCV_CACHE_BASE_V
`define RISCV_CACHE_BASE_V

`include "vc-RAMs.v"

module riscv_CacheBase (
input clk,
input reset,
input                                  memreq_val,
output                                 memreq_rdy,
input  [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] memreq_msg,
output                               memresp_val,
input                                memresp_rdy,
output [`VC_MEM_RESP_MSG_SZ(32)-1:0] memresp_msg,
output                                 cachereq_val,
input                                  cachereq_rdy,
output [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] cachereq_msg,
input                                cacheresp_val,
output                               cacheresp_rdy,
input  [`VC_MEM_RESP_MSG_SZ(32)-1:0] cacheresp_msg,
input  flush,
output flush_done
);

// interface adapter 
wire                    cpu_req_val   = memreq_val;
wire [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] cpu_req_msg  = memreq_msg;
wire                    cpu_resp_rdy  = memresp_rdy;
wire                    mem_side_req_val;
wire                    mem_side_req_rdy = cachereq_rdy;
wire [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] mem_side_req_msg;
wire                    mem_side_resp_val = cacheresp_val;
wire                    mem_side_resp_rdy = cacheresp_rdy;
wire [`VC_MEM_RESP_MSG_SZ(32)-1:0]   mem_side_resp_msg = cacheresp_msg;

assign memresp_val  = memresp_val_reg;
assign memresp_msg  = memresp_msg_reg;
assign cachereq_val = mem_side_req_val;
assign cachereq_msg = mem_side_req_msg;
assign cacheresp_rdy= 1'b1;
assign mem_side_req_val = cachereq_val_reg;
assign mem_side_req_msg = cachereq_msg_reg;

parameter num_block      = 32;
parameter block_addr     = 5;
parameter block_size     = 512;
parameter slot_per_block = 16;
parameter tag_size       = 21;
    parameter len_size       = 2;
    localparam slot_bits  = $clog2(slot_per_block);
    localparam last_slot  = slot_per_block-1;
    localparam last_block = num_block-1;

    // metadata & address mux
    reg  [num_block-1:0] line_meta_dirty;
    reg  [num_block-1:0] line_meta_valid;
    wire [block_addr-1:0] line_addr_r;
    wire [block_addr-1:0] line_addr_w;
    wire use_lat_idx;

    assign use_lat_idx = (phase_state != PHASE_IDLE);
    assign line_addr_r  = (flush_state == FLUSH_WRITE) ? slot_ctl_flush_idx
    : (use_lat_idx ? core_index_lat : core_index_now);
    assign line_addr_w  = use_lat_idx ? core_index_lat : core_index_now;

    // tag storage
    wire [tag_size-1:0] line_meta_tag_q;
    reg  [tag_size-1:0] line_meta_tag_d;
    reg  line_meta_tag_we;

    vc_RAM_1w1r_pf #(
    .DATA_SZ(tag_size),
    .ENTRIES(num_block),
    .ADDR_SZ(block_addr)
    ) tag (
    .clk(clk),
    .raddr(line_addr_r),
    .rdata(line_meta_tag_q),
    .wen_p(line_meta_tag_we),
    .waddr_p(line_addr_w),
    .wdata_p(line_meta_tag_d)
    );

    // data storage
    wire [block_size-1:0] line_data_q;
    reg  [block_size-1:0] line_data_d;
    reg  line_data_we;

    vc_RAM_1w1r_pf #(
    .DATA_SZ(block_size),
    .ENTRIES(num_block),
    .ADDR_SZ(block_addr)
    ) data (
    .clk(clk),
    .raddr(line_addr_r),
    .rdata(line_data_q),

    .wen_p(line_data_we),
    .waddr_p(line_addr_w),
    .wdata_p(line_data_d)
    );

wire cpu_wr_req;
wire [31:0] cpu_addr_req;
wire [31:0] cpu_wdata_req;
wire [1:0] cpu_len_req;

assign cpu_wr_req    = cpu_req_msg[`VC_MEM_REQ_MSG_TYPE_FIELD(32,32)];
assign cpu_addr_req  = cpu_req_msg[`VC_MEM_REQ_MSG_ADDR_FIELD(32,32)];
assign cpu_len_req   = cpu_req_msg[`VC_MEM_REQ_MSG_LEN_FIELD(32,32)];
assign cpu_wdata_req = cpu_req_msg[`VC_MEM_REQ_MSG_DATA_FIELD(32,32)];

    wire [tag_size-1:0] core_tag_now;
    wire [4:0] core_index_now;
    wire [3:0] core_slot_now;
    wire [1:0] core_byte_now;
    assign core_tag_now = cpu_addr_req[31:11];
    assign core_index_now = cpu_addr_req[10:6];
    assign core_slot_now = cpu_addr_req[5:2];
    assign core_byte_now = cpu_addr_req[1:0];

reg [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] memreq_msg_reg;
wire cpu_wr_lat;
wire [31:0] cpu_addr_lat;
wire [31:0] cpu_wdata_lat;
wire [1:0] cpu_len_lat;

    assign cpu_wr_lat = memreq_msg_reg[`VC_MEM_REQ_MSG_TYPE_FIELD(32,32)];
    assign cpu_addr_lat = memreq_msg_reg[`VC_MEM_REQ_MSG_ADDR_FIELD(32,32)];
    assign cpu_len_lat  = memreq_msg_reg[`VC_MEM_REQ_MSG_LEN_FIELD(32,32)];
    assign cpu_wdata_lat = memreq_msg_reg[`VC_MEM_REQ_MSG_DATA_FIELD(32,32)];

    // FSM encoding
    localparam PHASE_IDLE         = 3'd0;
    localparam PHASE_WRITEBACK    = 3'd1;
    localparam PHASE_FILL         = 3'd2;
    localparam PHASE_RESPOND      = 3'd3;
    localparam PHASE_WAIT         = 3'd4;

    localparam FLUSH_IDLE    = 2'd0;
    localparam FLUSH_WRITE   = 2'd1;
    localparam FLUSH_DONE    = 2'd2;

    reg [2:0] phase_state;
    reg [2:0] phase_next;
    reg [1:0] flush_state;
    reg [1:0] flush_next;
    reg       flush_pending;

    // decoded CPU request 
    wire        req_kind_live;
    wire [31:0] req_addr_live;
    wire [31:0] req_data_live;
    wire [1:0]  req_size_live;
    wire        req_kind_lat;
    wire [31:0] req_addr_lat;
    wire [31:0] req_data_lat;
    wire [1:0]  req_size_lat;

    assign req_kind_live = cpu_wr_req;
    assign req_addr_live = cpu_addr_req;
    assign req_data_live = cpu_wdata_req;
    assign req_size_live = cpu_len_req;
    assign req_kind_lat  = cpu_wr_lat;
    assign req_addr_lat  = cpu_addr_lat;
    assign req_data_lat  = cpu_wdata_lat;
    assign req_size_lat  = cpu_len_lat;

    wire [tag_size-1:0] core_tag_lat;
    wire [4:0] core_index_lat;
    wire [3:0] core_slot_lat;
    wire [1:0] core_byte_lat;
    assign core_tag_lat = req_addr_lat[31:11];
    assign core_index_lat = req_addr_lat[10:6];
    assign core_slot_lat = req_addr_lat[5:2];
    assign core_byte_lat = req_addr_lat[1:0];

wire cpu_req_rdy_internal = (phase_state == PHASE_IDLE) && ~(memresp_val_reg && ~cpu_resp_rdy);
assign memreq_rdy = cpu_req_rdy_internal;

    reg [`VC_MEM_RESP_MSG_SZ(32)-1:0] memresp_msg_reg;
    reg memresp_val_reg;

wire is_read;
assign is_read = (cpu_req_val && cpu_req_rdy_internal) ? ~req_kind_live : 1'b0;

wire hit_resp_en = ctl_hit && cpu_req_val && cpu_req_rdy_internal;
wire [`VC_MEM_RESP_MSG_SZ(32)-1:0] hit_resp_msg = req_kind_live ? {1'b1, 2'b0, 32'd0}
: {1'b0, 2'b0, hit_data};

wire cacheresp_msg_type;
wire [1:0] cacheresp_msg_len;
wire [31:0] cacheresp_msg_data;
assign {cacheresp_msg_type, cacheresp_msg_len, cacheresp_msg_data} = mem_side_resp_msg;

    reg [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] cachereq_msg_reg;
    reg cachereq_val_reg;

    reg [block_size-1:0] write_block;
    wire  [31:0] cache_slot_data;
    wire  [3:0]  cache_slot_addr;
    reg   [3:0]  slot_ctl_addr_lat;
assign cache_slot_data = (phase_state == PHASE_IDLE && (cpu_req_val && cpu_req_rdy_internal && cpu_wr_req)) ? cpu_wdata_req :
                         (phase_state == PHASE_FILL) ? cacheresp_msg_data :
                         (phase_state == PHASE_RESPOND && cpu_wr_lat) ? cpu_wdata_lat : cacheresp_msg_data;
assign cache_slot_addr = (phase_state == PHASE_IDLE && (cpu_req_val && cpu_req_rdy_internal && cpu_wr_req)) ? core_slot_now :
                         (phase_state == PHASE_FILL) ? slot_ctl_addr_lat :
                         (phase_state == PHASE_RESPOND && cpu_wr_lat) ? core_slot_lat : slot_ctl_addr_lat;

    function [block_size-1:0] splice_slot_word;
    input [block_size-1:0] line_in;
    input [3:0]            slot_sel;
    input [31:0]           slot_word;
    reg   [block_size-1:0] line_tmp;
    begin
    line_tmp = line_in;
    line_tmp[slot_sel*32 +: 32] = slot_word;
    splice_slot_word = line_tmp;
    end
    endfunction

    always @(*) begin
    if ((phase_state == PHASE_IDLE) || (phase_state == PHASE_RESPOND) || (phase_state == PHASE_FILL))
    line_data_d = splice_slot_word(line_data_q, cache_slot_addr, cache_slot_data);
    else
    line_data_d = line_data_q;
    end

    // slot helpers
    function [31:0] slot_pick_word;
    input [block_size-1:0] line_bits;
    input [slot_bits-1:0]  slot_idx;
    begin
    slot_pick_word = line_bits[slot_idx*32 +: 32];
    end
    endfunction

    function [slot_bits-1:0] bump_slot;
    input [slot_bits-1:0] s;
    begin
      bump_slot = (s == last_slot) ? {slot_bits{1'b0}} : s + 1'b1;
    end
    endfunction

    function is_wrap;
    input [slot_bits-1:0] s;
    begin
      is_wrap = (s == last_slot);
    end
    endfunction

    function [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] build_mem_req;
    input        write_bit;
    input [tag_size-1:0]   tag_bits;
    input [block_addr-1:0] idx_bits;
    input [3:0]            slot_bits;
    input [31:0]           data_bits;
    begin
    build_mem_req = { write_bit, {tag_bits, idx_bits, slot_bits, 2'b00}, 2'b0, data_bits };
    end
    endfunction

    function [`VC_MEM_RESP_MSG_SZ(32)-1:0] build_cpu_resp;
    input        write_bit;
    input [31:0] data_bits;
    begin
    build_cpu_resp = { write_bit, 2'b0, data_bits };
    end
    endfunction

    wire [31:0] hit_data;
    wire ctl_hit, ctl_dirty;
    assign ctl_hit      = line_meta_valid[core_index_now] ? (line_meta_tag_q == core_tag_now) : 1'b0;
    assign ctl_dirty = (line_meta_dirty[core_index_now] == 1'b1);
    assign hit_data = slot_pick_word(line_data_q, core_slot_now);

    reg [slot_bits-1:0] slot_ctl_wb, slot_ctl_fill;
    wire [slot_bits-1:0] slot_ctl_wb_next, slot_ctl_fill_next;
    assign slot_ctl_wb_next   = bump_slot(slot_ctl_wb);
    assign slot_ctl_fill_next = bump_slot(slot_ctl_fill);

    wire [31:0] slot_ctl_wb_data, flush_wdata;
    assign slot_ctl_wb_data  = slot_pick_word(line_data_q, slot_ctl_wb_next);

    wire [31:0] response_slot_data;
    assign response_slot_data = slot_pick_word(line_data_q, core_slot_lat);

    wire [31:0] miss_resp_data;
    assign miss_resp_data = slot_pick_word(line_data_d, core_slot_lat);

    assign flush_wdata = slot_pick_word(line_data_q, slot_ctl_flush_slot);

    assign flush_done = (flush_state == FLUSH_DONE);

    task automatic compute_phase_next;
      begin
        phase_next = phase_state;
        case (phase_state)
          PHASE_IDLE: begin
            if (cpu_req_val && cpu_req_rdy_internal) begin
              if (ctl_hit)
                phase_next = PHASE_IDLE;
              else if (ctl_dirty)
                phase_next = PHASE_WRITEBACK;
              else
                phase_next = PHASE_FILL;
            end
          end
          PHASE_WRITEBACK: begin
            if (mem_side_resp_val && (slot_ctl_wb == last_slot))
              phase_next = PHASE_FILL;
          end
          PHASE_FILL: begin
            if (mem_side_resp_val && (slot_ctl_fill == last_slot))
              phase_next = PHASE_RESPOND;
          end
          PHASE_RESPOND: begin
            phase_next = PHASE_WAIT;
          end
          PHASE_WAIT: begin
            if (memresp_val_reg && cpu_resp_rdy)
              phase_next = PHASE_IDLE;
          end
          default: phase_next = PHASE_IDLE;
        endcase
      end
    endtask

    task automatic compute_flush_next;
      begin
        flush_next = flush_state;
        case (flush_state)
          FLUSH_IDLE: begin
            if (flush_pending)
              flush_next = FLUSH_WRITE;
          end
          FLUSH_WRITE: begin
            if (slot_ctl_flush_idx == last_block) begin
              if (line_meta_dirty[slot_ctl_flush_idx]) begin
                if (mem_side_resp_val && slot_ctl_flush_slot == last_slot)
                  flush_next = FLUSH_DONE;
              end
              else
                flush_next = FLUSH_DONE;
            end
          end
          FLUSH_DONE: flush_next = FLUSH_IDLE;
          default: flush_next = FLUSH_IDLE;
        endcase
      end
    endtask

    // state & flush tracking
    always @(posedge clk) begin
      if (reset) begin
        phase_state  <= PHASE_IDLE;
        flush_state  <= FLUSH_IDLE;
        flush_pending<= 1'b0;
      end
      else begin
        compute_phase_next();
        phase_state <= phase_next;
        compute_flush_next();
        flush_state <= flush_next;
        if (flush_next == FLUSH_DONE)
          flush_pending <= 1'b0;
        else if (flush_pending)
          flush_pending <= 1'b1;
        else
          flush_pending <= flush;
        if ((flush_state == FLUSH_IDLE) && (flush_next == FLUSH_WRITE)) begin
          slot_ctl_flush_idx  <= {block_addr{1'b0}};
          slot_ctl_flush_slot <= {slot_bits{1'b0}};
        end
      end
    end

    // flush bookkeeping 
    reg [block_addr-1:0] slot_ctl_flush_idx;
    reg [slot_bits-1:0]  slot_ctl_flush_slot;

    task automatic do_state_idle;
      begin
        line_data_we     <= 1'b0;
        line_meta_tag_we <= 1'b0;
        if (cpu_req_val && cpu_req_rdy_internal) begin
          case ({ctl_hit, req_kind_live})
            2'b00: begin
              cachereq_val_reg <= 1'b1;
              cachereq_msg_reg <= ctl_dirty
                                   ? build_mem_req(1'b1, line_meta_tag_q, core_index_now, {slot_bits{1'b0}}, line_data_q[31:0])
                                   : build_mem_req(1'b0, core_tag_now, core_index_now, {slot_bits{1'b0}}, 32'b0);
              slot_ctl_wb      <= {slot_bits{1'b0}};
              slot_ctl_fill    <= {slot_bits{1'b0}};
              memreq_msg_reg   <= cpu_req_msg;
            end
            2'b01: begin
              cachereq_val_reg <= 1'b1;
              cachereq_msg_reg <= ctl_dirty
                                   ? build_mem_req(1'b1, line_meta_tag_q, core_index_now, {slot_bits{1'b0}}, line_data_q[31:0])
                                   : build_mem_req(1'b0, core_tag_now, core_index_now, {slot_bits{1'b0}}, 32'b0);
              slot_ctl_wb      <= {slot_bits{1'b0}};
              slot_ctl_fill    <= {slot_bits{1'b0}};
              memreq_msg_reg   <= cpu_req_msg;
            end
            2'b10: begin
              memresp_msg_reg <= build_cpu_resp(1'b0, hit_data);
              memresp_val_reg <= 1'b1;
            end
            2'b11: begin
              line_meta_dirty[core_index_now] <= 1'b1;
              line_data_we       <= 1'b1;
              memresp_msg_reg    <= build_cpu_resp(1'b1, 32'd0);
              memresp_val_reg    <= 1'b1;
            end
        endcase
        end
      end
    endtask

    task automatic do_state_wb;
      begin
        line_meta_tag_we <= 1'b0;
        if (mem_side_req_val) begin
          if (mem_side_req_rdy)
            cachereq_val_reg <= 1'b0;
        end
        else if (mem_side_resp_val) begin
          cachereq_val_reg <= 1'b1;
          cachereq_msg_reg <= (slot_ctl_wb == last_slot)
                              ? build_mem_req(1'b0, core_tag_lat, core_index_lat, {slot_bits{1'b0}}, 32'b0)
                              : build_mem_req(1'b1, line_meta_tag_q, core_index_lat, slot_ctl_wb_next, slot_ctl_wb_data);
          slot_ctl_wb <= bump_slot(slot_ctl_wb);
        end
        else begin
          cachereq_val_reg <= 1'b0;
        end
      end
    endtask

    task automatic do_state_fill;
      begin
        if (mem_side_req_val) begin
          if (mem_side_req_rdy)
            cachereq_val_reg <= 1'b0;
          line_data_we     <= 1'b0;
          line_meta_tag_we <= 1'b0;
        end
        else if (mem_side_resp_val) begin
          cachereq_val_reg <= is_wrap(slot_ctl_fill) ? 1'b0 : 1'b1;
          cachereq_msg_reg <= build_mem_req(1'b0, core_tag_lat, core_index_lat, slot_ctl_fill_next, 32'd0);
          slot_ctl_fill    <= bump_slot(slot_ctl_fill);
          if (is_wrap(slot_ctl_fill)) begin
            line_meta_valid[core_index_lat] <= 1'b1;
            if (~req_kind_lat)
              line_meta_dirty[core_index_lat] <= 1'b0;
          end
          line_meta_tag_d   <= (is_wrap(slot_ctl_fill)) ? core_tag_lat : line_meta_tag_q;
          line_data_we      <= 1'b1;
          slot_ctl_addr_lat <= slot_ctl_fill;
          line_meta_tag_we  <= (is_wrap(slot_ctl_fill)) ? 1'b1 : 1'b0;
        end
        else begin
          line_data_we     <= 1'b0;
          line_meta_tag_we <= 1'b0;
          cachereq_val_reg <= 1'b0;
        end
      end
    endtask

    task automatic do_state_resp;
      begin
        if (req_kind_lat == 1'b0) begin
          memresp_msg_reg <= build_cpu_resp(1'b0, miss_resp_data);
          line_data_we     <= 1'b0;
          line_meta_tag_we <= 1'b0;
        end
        else begin
          memresp_msg_reg <= build_cpu_resp(1'b1, 32'b0);
          line_meta_dirty[core_index_lat] <= 1'b1;
          line_data_we     <= 1'b1;
          line_meta_tag_we <= 1'b0;
        end
        memresp_val_reg <= 1'b1;
      end
    endtask

    task automatic do_state_wait;
      begin
        line_data_we     <= 1'b0;
        line_meta_tag_we <= 1'b0;
        if (cpu_resp_rdy)
          memresp_val_reg <= 1'b0;
      end
    endtask

    task automatic do_flush_write;
      begin
        if (line_meta_dirty[slot_ctl_flush_idx]) begin
          if (cachereq_val_reg) begin
            if (mem_side_req_rdy)
              cachereq_val_reg <= 1'b0;
          end
          else begin
            if (mem_side_resp_val) begin
              cachereq_val_reg <= 1'b1;
              cachereq_msg_reg <= build_mem_req(1'b1, line_meta_tag_q, slot_ctl_flush_idx[4:0], slot_ctl_flush_slot, flush_wdata);
              slot_ctl_flush_slot  <= bump_slot(slot_ctl_flush_slot);
              slot_ctl_flush_idx   <= is_wrap(slot_ctl_flush_slot) ? slot_ctl_flush_idx + 1'b1 : slot_ctl_flush_idx;
            end
            else if (slot_ctl_flush_slot == {slot_bits{1'b0}}) begin
              cachereq_val_reg <= 1'b1;
              cachereq_msg_reg <= build_mem_req(1'b1, line_meta_tag_q, slot_ctl_flush_idx[4:0], slot_ctl_flush_slot, flush_wdata);
              slot_ctl_flush_slot  <= bump_slot(slot_ctl_flush_slot);
            end
            else begin
              cachereq_val_reg <= 1'b0;
            end
          end
        end
        else begin
          slot_ctl_flush_idx  <= (slot_ctl_flush_idx == last_block) ? {block_addr{1'b0}} : slot_ctl_flush_idx + 1'b1;
          slot_ctl_flush_slot <= {slot_bits{1'b0}};
          cachereq_val_reg    <= 1'b0;
        end
      end
    endtask

    task automatic do_flush_done;
      begin
        cachereq_val_reg <= 1'b0;
        line_meta_dirty  <= 0;
      end
    endtask

    task automatic do_state_default;
      begin
        slot_ctl_wb   <= {slot_bits{1'b0}};
        slot_ctl_fill <= {slot_bits{1'b0}};
      end
    endtask

    always @(posedge clk) begin
      if (reset) begin
        slot_ctl_wb        <= {slot_bits{1'b0}};
        slot_ctl_fill      <= {slot_bits{1'b0}};
        line_meta_dirty    <= 0;
        line_meta_valid    <= 0;
        memreq_msg_reg     <= 0;
        cachereq_val_reg   <= 1'b0;
        memreq_msg_reg     <= 0;
        line_data_we       <= 1'b0;
        line_meta_tag_we   <= 1'b0;
        memresp_val_reg    <= 1'b0;
      end
      else begin
        memresp_val_reg <= memresp_val_reg; // hold by default
        case (phase_state)
          PHASE_IDLE:      do_state_idle();
          PHASE_WRITEBACK: do_state_wb();
          PHASE_FILL:      do_state_fill();
          PHASE_RESPOND:   do_state_resp();
          PHASE_WAIT:      do_state_wait();
          default:         do_state_default();
        endcase
        case (flush_state)
          FLUSH_WRITE: do_flush_write();
          FLUSH_DONE:  do_flush_done();
          default:     ; // remain idle
        endcase
      end
    end

    endmodule


    `endif  /* RISCV_CACHE_BASE_V */