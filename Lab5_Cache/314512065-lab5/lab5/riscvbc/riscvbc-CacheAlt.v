//=========================================================================
// Cache Alt Design
//=========================================================================

`ifndef RISCV_CACHE_ALT_V
`define RISCV_CACHE_ALT_V

`include "vc-RAMs.v"
`include "riscvbc-CacheMsg.v"
`include "riscvbc-VictimCache.v"

module riscv_CacheAlt (
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

  parameter  num_block = 64;
  parameter  block_addr = 6;
  parameter  memreq_addr = 5;
  parameter  block_size = 512;
  parameter  slot_per_block = 16;
  parameter  tag_size = 21;
  parameter  len_size = 2;

  function [31:0] expand_load_word;
    input [31:0] raw_word;
    input [1:0] size_sel;
    input [1:0] byte_sel;
    reg [31:0] clean_raw;
    begin
      clean_raw = (^raw_word === 1'bx) ? 32'b0 : raw_word;
      if (size_sel == 2'b00)
      begin
        expand_load_word = clean_raw;
      end
      else if (size_sel == 2'b01)
      begin
        if (byte_sel == 2'b00)
          expand_load_word = {24'b0, clean_raw[7:0]};
        else if (byte_sel == 2'b01)
          expand_load_word = {24'b0, clean_raw[15:8]};
        else if (byte_sel == 2'b10)
          expand_load_word = {24'b0, clean_raw[23:16]};
        else
          expand_load_word = {24'b0, clean_raw[31:24]};
      end
      else if (size_sel == 2'b10)
      begin
        if (byte_sel[1])
          expand_load_word = {16'b0, clean_raw[31:16]};
        else
          expand_load_word = {16'b0, clean_raw[15:0]};
      end
      else
      begin
        expand_load_word = clean_raw;
      end
    end
  endfunction

  function [31:0] slice_line_word;
    input [block_size-1:0] block;
    input [3:0] slot_idx;
    begin
      slice_line_word = block[slot_idx*32 +: 32];
    end
  endfunction

  function [block_size-1:0] patch_line_word;
    input [block_size-1:0] block;
    input [3:0] slot_idx;
    input [31:0] word;
    reg [block_size-1:0] tmp;
    begin
      tmp = block;
      tmp[slot_idx*32 +: 32] = word;
      patch_line_word = tmp;
    end
  endfunction

  function [31:0] combine_store_word;
    input [31:0] orig_word;
    input [31:0] store_word;
    input [1:0] len;
    input [1:0] byte_mask;
    begin
      combine_store_word = orig_word;
      case ({len, byte_mask})
        4'b0000: combine_store_word = store_word;
        4'b0001: combine_store_word[31:8]  = store_word[23:0];
        4'b0010: combine_store_word[31:16] = store_word[15:0];
        4'b0011: combine_store_word[31:24] = store_word[7:0];
        4'b0100: combine_store_word[7:0]   = store_word[7:0];
        4'b0101: combine_store_word[15:8]  = store_word[7:0];
        4'b0110: combine_store_word[23:16] = store_word[7:0];
        4'b0111: combine_store_word[31:24] = store_word[7:0];
        4'b1000: combine_store_word[15:0]  = store_word[15:0];
        4'b1001: combine_store_word[23:8]  = store_word[15:0];
        4'b1010: combine_store_word[31:16] = store_word[15:0];
        4'b1011: combine_store_word[31:24] = store_word[7:0];
      endcase
    end
  endfunction

  task automatic update_line_meta;
    input use_way1;
    input is_last_word;
    begin
      if (use_way1)
      begin
        meta_valid_bits[path_addr_way1] <= is_last_word ? 1'b1 : meta_valid_bits[path_addr_way1];
        if (is_last_word && ~req_type_lat)
          meta_dirty_bits[path_addr_way1] <= 1'b0;
        meta_tag_d <= is_last_word ? req_tag_lat : meta_tag_q1;
      end
      else
      begin
        meta_valid_bits[path_addr_way0] <= is_last_word ? 1'b1 : meta_valid_bits[path_addr_way0];
        if (is_last_word && ~req_type_lat)
          meta_dirty_bits[path_addr_way0] <= 1'b0;
        meta_tag_d <= is_last_word ? req_tag_lat : meta_tag_q0;
      end
    end
  endtask


  reg [num_block-1:0] meta_dirty_bits;
  reg [num_block-1:0] meta_valid_bits;
  reg [31:0] meta_age_bits;
  wire [block_addr-1:0] path_addr_way0, path_addr_way1;
  wire set_full_mask, set_half_mask, set_empty_mask;
  assign set_empty_mask = (meta_valid_bits[path_addr_way0] == 0) && (meta_valid_bits[path_addr_way1] == 0);
  assign set_half_mask = (meta_valid_bits[path_addr_way0] == 1) && (meta_valid_bits[path_addr_way1] == 0);
  assign set_full_mask = (meta_valid_bits[path_addr_way0] == 1) && (meta_valid_bits[path_addr_way1] == 1);
  reg meta_fill_hold;
  wire meta_fill_pick;
  wire [block_addr-1:0] meta_fill_addr;
  wire meta_fill_valid;
  wire meta_fill_dirty;
  wire [tag_size-1:0] meta_evict_tag;
  wire [block_size-1:0] meta_evict_line;
  wire [block_addr-1:0] path_wr_addr_mux;
  wire use_saved_index;
  assign use_saved_index = (ctl_phase == FS_IDLE) ? 1'b0 : 1'b1;
  assign path_addr_way0 = (ctl_phase == FS_FLUSHING) ? ctl_flush_line : (use_saved_index ? {1'b0, req_idx_lat} : {1'b0, req_idx_in});
  assign path_addr_way1 = use_saved_index ? {1'b1, req_idx_lat} : {1'b1, req_idx_in};
  assign meta_fill_pick = set_empty_mask ? 1'b0 : (set_half_mask ? 1'b1 : meta_age_pick);
  assign meta_fill_addr = {meta_fill_pick, req_idx_in};
  assign meta_fill_valid = meta_valid_bits[meta_fill_addr];
  assign meta_fill_dirty = meta_dirty_bits[meta_fill_addr];
  assign meta_evict_tag = meta_fill_pick ? meta_tag_q1 : meta_tag_q0;
  assign meta_evict_line = meta_fill_pick ? path_line_q1 : path_line_q0;
  assign path_wr_addr_mux = use_saved_index ? {meta_fill_hold, req_idx_lat} : {hit_way1, req_idx_in};
  wire [tag_size-1:0] meta_tag_q0;
  wire [tag_size-1:0] meta_tag_q1;
  reg [tag_size-1:0] meta_tag_d;
  reg  path_data_we;
  reg  meta_tag_we;

  vc_RAM_1w2r_pf #(
  .DATA_SZ(tag_size),
  .ENTRIES(num_block),
  .ADDR_SZ(block_addr)
  ) tag (
  .clk(clk),
  .raddr0(path_addr_way0),
  .rdata0(meta_tag_q0),
  .raddr1(path_addr_way1),
  .rdata1(meta_tag_q1),

  .wen_p(meta_tag_we),
  .waddr_p(path_wr_addr_mux),
  .wdata_p(meta_tag_d)
  );

  wire [block_size-1:0] path_line_q0, path_line_q1;
  reg [block_size-1:0] path_line_d;
  vc_RAM_1w2r_pf #(
  .DATA_SZ(block_size),
  .ENTRIES(num_block),
  .ADDR_SZ(block_addr)
  ) data (
  .clk(clk),
  .raddr0(path_addr_way0),
  .rdata0(path_line_q0),
  .raddr1(path_addr_way1),
  .rdata1(path_line_q1),

  .wen_p(path_data_we),
  .waddr_p(path_wr_addr_mux),
  .wdata_p(path_line_d)
  );


  wire req_type_in;
  wire [31:0] req_addr_in;
  wire [31:0] req_wdata_in;
  wire [1:0] req_len_in;
  reg  [1:0] req_len_eff;
  always @(*)
  begin
    if (use_saved_index)
      req_len_eff = req_len_lat;
    else
      req_len_eff = req_len_in;
  end

  assign req_type_in = memreq_msg[`VC_MEM_REQ_MSG_TYPE_FIELD(32,32)];
  assign req_addr_in = memreq_msg[`VC_MEM_REQ_MSG_ADDR_FIELD(32,32)];
  assign req_len_in  = memreq_msg[`VC_MEM_REQ_MSG_LEN_FIELD(32,32)];
  assign req_wdata_in = memreq_msg[`VC_MEM_REQ_MSG_DATA_FIELD(32,32)];

  wire [tag_size-1:0] req_tag_in;
  wire [4:0] req_idx_in;
  wire [3:0] req_slot_in;
  wire [1:0] req_byte_in;
  assign req_tag_in = req_addr_in[31:11];
  assign req_idx_in = req_addr_in[10:6];
  assign req_slot_in = req_addr_in[5:2];
  assign req_byte_in = req_addr_in[1:0];

  reg [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] req_msg_lat;
  wire req_type_lat;
  wire [31:0] req_addr_lat;
  wire [31:0] req_data_lat;
  wire [1:0] req_len_lat;

  assign req_type_lat = req_msg_lat[`VC_MEM_REQ_MSG_TYPE_FIELD(32,32)];
  assign req_addr_lat = req_msg_lat[`VC_MEM_REQ_MSG_ADDR_FIELD(32,32)];
  assign req_len_lat  = req_msg_lat[`VC_MEM_REQ_MSG_LEN_FIELD(32,32)];
  assign req_data_lat = req_msg_lat[`VC_MEM_REQ_MSG_DATA_FIELD(32,32)];

  wire [tag_size-1:0] req_tag_lat;
  wire [4:0] req_idx_lat;
  wire [3:0] req_slot_lat;
  wire [1:0] req_byte_lat;
  assign req_tag_lat = req_addr_lat[31:11];
  assign req_idx_lat = req_addr_lat[10:6];
  assign req_slot_lat = req_addr_lat[5:2];
  assign req_byte_lat = req_addr_lat[1:0];

  // Victim cache interface
  wire vict_hit_flag;
  wire vict_way_sel;
  wire [block_size-1:0] vict_data_line;
  wire vict_line_dirty;
  wire vict_sel_way;
  wire vict_evict_val;
  wire [tag_size-1:0] vict_evict_tag;
  wire [4:0] vict_evict_idx;
  wire [block_size-1:0] vict_evict_data;
  wire vict_evict_dirty;
  reg vict_probe_en;

  reg vict_wr_en;
  reg [tag_size-1:0] vict_wr_tag;
  reg [4:0] vict_wr_idx;
  reg [block_size-1:0] vict_wr_data;
  reg vict_wr_dirty;

  riscv_VictimCache victim_cache (
  .clk(clk),
  .reset(reset),
  .vc_ins_val(vict_wr_en),
  .vc_ins_tag(vict_wr_tag),
  .vc_ins_idx(vict_wr_idx),
  .vc_ins_data(vict_wr_data),
  .vc_ins_dirty(vict_wr_dirty),
  .vc_lu_val(vict_probe_en),
  .vc_lu_tag(req_tag_in),
  .vc_lu_idx(req_idx_in),
  .vc_lu_hit(vict_hit_flag),
  .vc_lu_way(vict_way_sel),
  .vc_lu_data(vict_data_line),
  .vc_lu_dirty(vict_line_dirty),
  .vc_sel_way(vict_sel_way),
  .vc_evict_val(vict_evict_val),
  .vc_evict_tag(vict_evict_tag),
  .vc_evict_idx(vict_evict_idx),
  .vc_evict_data(vict_evict_data),
  .vc_evict_dirty(vict_evict_dirty)
  );

  reg vc_hit_lat;
  reg vc_way_lat;
  reg [block_size-1:0] vc_line_lat;
  reg vc_fill_hold;
  reg vc_insert_hold;
  reg evict_valid_lat;
  reg evict_dirty_lat;
  reg [tag_size-1:0] evict_tag_lat;
  reg [block_size-1:0] evict_block_lat;
  reg [4:0] evict_idx_lat;
  reg vc_wb_pending;

  assign memreq_rdy = (ctl_phase == FS_IDLE) && ~(memresp_val_lat && ~memresp_rdy);

  reg [`VC_MEM_RESP_MSG_SZ(32)-1:0] memresp_msg_lat;
  reg memresp_val_lat;

  reg is_read;
  always @(*)
  begin
    if (memreq_val && memreq_rdy)
      is_read = ~req_type_in;
    else
      is_read = 1'b0;
  end

  assign memresp_val = memresp_val_lat;
  assign memresp_msg = memresp_msg_lat;

  wire mem_resp_type_in;
  wire [1:0] mem_resp_len_in;
  wire [31:0] mem_resp_data_in;
  assign {mem_resp_type_in, mem_resp_len_in, mem_resp_data_in} = cacheresp_msg;

  assign cacheresp_rdy = 1'b1;

  reg [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] memreq_out_msg;
  reg memreq_out_val;
  assign cachereq_val = memreq_out_val;
  assign cachereq_msg = memreq_out_msg;

  reg [block_size-1:0] write_block_buffer;
  reg [31:0] path_word_in;
  reg [31:0] path_word_masked;
  reg [3:0] path_word_sel;
  reg [3:0] path_word_hold;
  wire [31:0] vc_word_pick;
  wire [31:0] path_word_way0_lat;
  wire [31:0] path_word_way1_lat;
  wire [31:0] path_resp_word;

  always @(*)
  begin
    if ((ctl_phase == FS_IDLE) && memreq_val && memreq_rdy && req_type_in)
      path_word_sel = req_slot_in;
    else if (ctl_phase == FS_FILL_MEM)
      path_word_sel = ctl_fill_idx;
    else if (ctl_phase == FS_FILL_VICT)
      path_word_sel = ctl_fill_idx;
    else if (ctl_phase == FS_RESPOND || ctl_phase == FS_WAITCPU)
      path_word_sel = req_slot_lat;
    else
      path_word_sel = path_word_hold;
  end

  assign vc_word_pick = vc_line_lat[path_word_sel*32 +: 32];

  assign path_word_way0_lat = slice_line_word(path_line_q0, req_slot_lat);
  assign path_word_way1_lat = slice_line_word(path_line_q1, req_slot_lat);
  assign path_resp_word = meta_fill_hold ? path_word_way1_lat : path_word_way0_lat;

  always @(*)
  begin
    if ((ctl_phase == FS_IDLE) && memreq_val && memreq_rdy && req_type_in)
      path_word_in = req_wdata_in;
    else if (ctl_phase == FS_FILL_MEM)
      path_word_in = mem_resp_data_in;
    else if (ctl_phase == FS_FILL_VICT)
      path_word_in = vc_word_pick;
    else if (ctl_phase == FS_RESPOND || ctl_phase == FS_WAITCPU)
      path_word_in = req_type_lat ? req_data_lat : path_resp_word;
    else
      path_word_in = mem_resp_data_in;
  end

  wire [31:0] path_word_clean = (^path_word_in === 1'bx) ? 32'b0 : path_word_in;

  reg [block_size-1:0] path_line_mux;
  reg [31:0] path_word_mux_out;

  always @(*)
  begin
    if (ctl_phase == FS_IDLE)
    begin
      if (hit_way0)
        path_line_mux = path_line_q0;
      else
        path_line_mux = path_line_q1;
    end
    else
    begin
      if (meta_fill_hold)
        path_line_mux = path_line_q1;
      else
        path_line_mux = path_line_q0;
    end

    path_word_mux_out = slice_line_word(path_line_mux, path_word_sel);
  end

  always @(*)
  begin
    path_word_masked = path_word_clean;
    if ( (ctl_phase == FS_IDLE && memreq_val && memreq_rdy && req_type_in && hit_any) ||
         ((ctl_phase == FS_RESPOND || ctl_phase == FS_WAITCPU) && req_type_lat) )
    begin
      path_word_masked = combine_store_word(path_word_mux_out, path_word_in, req_len_eff, byte_offset_mask);
    end
  end

  wire [1:0] byte_offset_mask;
  assign byte_offset_mask = (use_saved_index) ? req_byte_lat : req_byte_in;

  wire cache_way_pick;
  assign cache_way_pick = (ctl_phase == FS_IDLE) ? hit_way1 : meta_fill_hold;

  reg path_line_we;
  always @(*)
  begin
    path_line_we = 1'b0;
    if ((ctl_phase == FS_FILL_MEM) && cacheresp_val)
      path_line_we = 1'b1;
    else if (ctl_phase == FS_FILL_VICT)
      path_line_we = 1'b1;
    else if ((ctl_phase == FS_RESPOND) && req_type_lat)
      path_line_we = 1'b1;
    else if ((ctl_phase == FS_IDLE) && memreq_val && memreq_rdy && req_type_in && hit_any)
      path_line_we = 1'b1;
  end

  wire [block_size-1:0] path_line_src = cache_way_pick ? path_line_q1 : path_line_q0;

  always @(*)
  begin
    path_line_d = path_line_src;
    if (path_line_we)
    begin
      path_line_d = patch_line_word(path_line_src, path_word_sel, path_word_masked);
    end
  end


  wire [31:0] path_hit_word0, path_hit_word1;
  reg hit_way0, hit_way1, hit_any;

  always @(*)
  begin
    hit_way0 = meta_valid_bits[path_addr_way0] && (meta_tag_q0 == req_tag_in);
    hit_way1 = meta_valid_bits[path_addr_way1] && (meta_tag_q1 == req_tag_in);
    hit_any = hit_way0 || hit_way1;
  end

  always @(*)
  begin
    path_data_we = 1'b0;
    if ((ctl_phase == FS_FILL_MEM) && cacheresp_val)
      path_data_we = 1'b1;
    else if (ctl_phase == FS_FILL_VICT)
      path_data_we = 1'b1;
    else if ((ctl_phase == FS_RESPOND) && req_type_lat)
      path_data_we = 1'b1;
    else if ((ctl_phase == FS_IDLE) && memreq_val && memreq_rdy && req_type_in && hit_any)
      path_data_we = 1'b1;
  end

  always @(*)
  begin
    if ((ctl_phase == FS_IDLE) && memreq_val && memreq_rdy && ~hit_any)
      vict_probe_en = 1'b1;
    else
      vict_probe_en = 1'b0;
  end

  reg meta_age_pick;
  always @(*)
  begin
    meta_age_pick = meta_age_bits[req_idx_in];
  end

  reg [block_addr-1:0] replace_addr_sel;
  always @(*)
  begin
    if (use_saved_index)
      replace_addr_sel = {meta_fill_hold, req_idx_lat};
    else
      replace_addr_sel = meta_fill_addr;
  end

  assign path_hit_word0 = slice_line_word(path_line_q0, req_slot_in);
  assign path_hit_word1 = slice_line_word(path_line_q1, req_slot_in);

  reg [3:0] ctl_wb_idx, ctl_fill_idx;
  reg [3:0] ctl_wb_idx_next, ctl_fill_idx_next;
  always @(*)
  begin
    if (ctl_wb_idx == 4'd15)
      ctl_wb_idx_next = 4'd0;
    else
      ctl_wb_idx_next = ctl_wb_idx + 1;

    if (ctl_fill_idx == 4'd15)
      ctl_fill_idx_next = 4'd0;
    else
      ctl_fill_idx_next = ctl_fill_idx + 1;
  end

  wire [31:0] path_wb_word0, path_wb_word1, path_flush_word;
  assign path_wb_word0  = slice_line_word(path_line_q0, ctl_wb_idx_next);
  assign path_wb_word1 = slice_line_word(path_line_q1, ctl_wb_idx_next);
  assign path_flush_word = slice_line_word(path_line_q0, ctl_flush_word);
  wire [31:0] path_wb_word0_clean = (^path_wb_word0 === 1'bx) ? 32'b0 : path_wb_word0;
  wire [31:0] path_wb_word1_clean = (^path_wb_word1 === 1'bx) ? 32'b0 : path_wb_word1;

  wire [31:0] path_miss_word;
  assign path_miss_word = path_resp_word;


  reg [2:0] ctl_phase;
  reg [2:0] ctl_phase_next;
  reg flush_armed_flag;
  assign flush_done = (ctl_phase == FS_FLUSH_DONE) ? 1'b1 : 1'b0;

  reg [block_addr-1:0] ctl_flush_line;
  reg [3:0] ctl_flush_word;

  localparam FS_IDLE       = 3'd0;
  localparam FS_WRITEBACK = 3'd1;
  localparam FS_FILL_MEM  = 3'd2;
  localparam FS_FILL_VICT= 3'd3;
  localparam FS_RESPOND  = 3'd4;
  localparam FS_WAITCPU   = 3'd5;
  localparam FS_FLUSHING   = 3'd6;
  localparam FS_FLUSH_DONE = 3'd7;

  wire flush_safe = (flush === 1'b1);

  task automatic init_ctrl_state;
    begin
      ctl_phase <= FS_IDLE;
      flush_armed_flag <= 1'b0;
    end
  endtask

  always @(posedge clk)
  begin
    if (reset)
    begin
      init_ctrl_state();
    end
    else
    begin
      ctl_phase <= ctl_phase_next;
      if (ctl_phase == FS_FLUSH_DONE)
      begin
        flush_armed_flag <= 1'b0;
      end
      else if (flush_armed_flag)
      begin
        flush_armed_flag <= 1'b1;
      end
      else
      begin
        flush_armed_flag <= flush_safe;
      end
    end
  end

  always @(*)
  begin
    ctl_phase_next = ctl_phase;
    case (ctl_phase)
      FS_IDLE:
      begin
        if (memreq_val && memreq_rdy)
        begin
          if (hit_any)
            ctl_phase_next = is_read ? FS_IDLE : FS_WAITCPU;
          else if (meta_fill_dirty)
            ctl_phase_next = FS_WRITEBACK;
          else if (vict_hit_flag)
            ctl_phase_next = FS_FILL_VICT;
          else
            ctl_phase_next = FS_FILL_MEM;
        end
        else
        begin
          ctl_phase_next = (flush_armed_flag) ? FS_FLUSHING : FS_IDLE;
        end
      end
      FS_WRITEBACK:
      begin
        if (cacheresp_val && (ctl_wb_idx == 4'd15))
          ctl_phase_next = vc_wb_pending ? FS_FILL_VICT : FS_FILL_MEM;
        else
          ctl_phase_next = FS_WRITEBACK;
      end
      FS_FILL_MEM:
      begin
        if (cacheresp_val && (ctl_fill_idx == 4'd15))
          ctl_phase_next = FS_RESPOND;
        else
          ctl_phase_next = FS_FILL_MEM;
      end
      FS_FILL_VICT:
        ctl_phase_next = (ctl_fill_idx == 4'd15) ? FS_RESPOND : FS_FILL_VICT;
      FS_RESPOND:
        ctl_phase_next = FS_WAITCPU;
      FS_WAITCPU:
      begin
        if (memresp_val && memresp_rdy)
          ctl_phase_next = FS_IDLE;
        else
          ctl_phase_next = FS_WAITCPU;
      end
      FS_FLUSHING:
      begin
        if (ctl_flush_line == 6'd63)
        begin
          if (meta_dirty_bits[ctl_flush_line])
            ctl_phase_next = (cacheresp_val && ctl_flush_word == 4'd15) ? FS_FLUSH_DONE : FS_FLUSHING;
          else
            ctl_phase_next = FS_FLUSH_DONE;
        end
        else
          ctl_phase_next = FS_FLUSHING;
      end
      FS_FLUSH_DONE:
        ctl_phase_next = FS_IDLE;
      default:
        ctl_phase_next = FS_IDLE;
    endcase
  end

  task automatic init_datapath_state;
    begin
      // counters and basic meta
      ctl_wb_idx      <= 4'd0;
      ctl_fill_idx    <= 4'd0;
      meta_dirty_bits <= 0;
      meta_valid_bits <= 0;
      meta_age_bits   <= 0;
      meta_fill_hold  <= 0;
      meta_tag_we     <= 1'b0;

      // cached request + mem side
      req_msg_lat      <= 0;
      memreq_out_val   <= 1'b0;
      memreq_out_msg   <= {`VC_MEM_REQ_MSG_SZ(32,32){1'b0}};
      memresp_val_lat  <= 1'b0;
      memresp_msg_lat  <= {`VC_MEM_RESP_MSG_SZ(32){1'b0}};

      // victim cache tracking
      vc_hit_lat       <= 1'b0;
      vc_way_lat       <= 1'b0;
      vc_line_lat      <= {block_size{1'b0}};
      vc_fill_hold     <= 1'b0;
      vc_insert_hold   <= 1'b0;
      vc_wb_pending    <= 1'b0;

      // eviction bookkeeping
      evict_valid_lat  <= 1'b0;
      evict_dirty_lat  <= 1'b0;
      evict_tag_lat    <= {tag_size{1'b0}};
      evict_block_lat  <= {block_size{1'b0}};
      evict_idx_lat    <= 5'd0;

      // victim cache write staging
      vict_wr_en    <= 1'b0;
      vict_wr_tag   <= {tag_size{1'b0}};
      vict_wr_idx   <= 5'd0;
      vict_wr_data  <= {block_size{1'b0}};
      vict_wr_dirty <= 1'b0;
    end
  endtask

  task automatic act_idle_phase;
    begin
      // defaults
      meta_tag_we     <= 1'b0;
      memreq_out_val  <= 1'b0;
      vc_insert_hold  <= 1'b0;

      if (memreq_val && memreq_rdy)
      begin
        meta_fill_hold   <= meta_fill_pick;
        req_msg_lat      <= memreq_msg;
        vc_hit_lat       <= vict_hit_flag && ~hit_any;
        vc_way_lat       <= vict_way_sel;
        vc_line_lat      <= vict_data_line;
        evict_valid_lat  <= meta_fill_valid;
        evict_dirty_lat  <= meta_fill_dirty;
        evict_tag_lat    <= meta_evict_tag;
        evict_block_lat  <= meta_evict_line;
        evict_idx_lat    <= req_idx_in;
        ctl_wb_idx       <= 4'd0;
        ctl_fill_idx     <= 4'd0;
        vc_fill_hold     <= vict_hit_flag && ~hit_any;
        vc_wb_pending    <= vict_hit_flag && meta_fill_dirty;

        // request classification
        case ({hit_any, req_type_in})
          2'b00: begin
            vc_insert_hold <= meta_fill_valid;
            if (meta_fill_dirty)
            begin
              memreq_out_val <= 1'b1;
              memreq_out_msg <= {1'b1, {meta_evict_tag, req_idx_in, 4'd0, 2'b00}, 2'b0, meta_evict_line[31:0]};
            end
            else if (~vict_hit_flag)
            begin
              memreq_out_val <= 1'b1;
              memreq_out_msg <= {1'b0, {req_tag_in, req_idx_in, 4'd0, 2'b00}, 2'b0, 32'b0};
            end
          end
          2'b01: begin
            vc_insert_hold <= meta_fill_valid;
            if (meta_fill_dirty)
            begin
              memreq_out_val <= 1'b1;
              memreq_out_msg <= {1'b1, {meta_evict_tag, req_idx_in, 4'd0, 2'b00}, 2'b0, meta_evict_line[31:0]};
            end
            else if (~vict_hit_flag)
            begin
              memreq_out_val <= 1'b1;
              memreq_out_msg <= {1'b0, {req_tag_in, req_idx_in, 4'd0, 2'b00}, 2'b0, 32'b0};
            end
          end
          2'b10: begin
            memresp_msg_lat <= hit_way0
              ? {1'b0, 2'b0, expand_load_word(path_hit_word0, req_len_eff, req_byte_in)}
              : {1'b0, 2'b0, expand_load_word(path_hit_word1, req_len_eff, req_byte_in)};
            memresp_val_lat    <= 1'b1;
            meta_age_bits[req_idx_in] <= hit_way0 ? 1'b1 : 1'b0;
            vc_fill_hold       <= 1'b0;
            vc_insert_hold     <= 1'b0;
          end
          2'b11: begin
            if (hit_way0)
              meta_dirty_bits[path_addr_way0] <= 1;
            else
              meta_dirty_bits[path_addr_way1] <= 1;
            meta_age_bits[req_idx_in] <= hit_way0 ? 1'b1 : 1'b0;
            memresp_msg_lat   <= {1'b1, 2'b0, 32'd0};
            meta_fill_hold    <= ~hit_way0;
            vc_fill_hold      <= 1'b0;
            vc_insert_hold    <= 1'b0;
            memresp_val_lat   <= 1'b1;
          end
        endcase
      end
      else if (flush_armed_flag)
      begin
        ctl_flush_word <= 0;
        ctl_flush_line <= 0;
      end
    end
  endtask

  task automatic act_writeback_phase;
    begin
      meta_tag_we    <= 1'b0;
      memreq_out_val <= cachereq_val && ~cachereq_rdy ? memreq_out_val : 1'b0;

      if (~cachereq_val && cacheresp_val)
      begin
        if (ctl_wb_idx == 4'd15)
        begin
          memreq_out_val <= vc_wb_pending ? 1'b0 : 1'b1;
          if (~vc_wb_pending)
            memreq_out_msg <= {1'b0, {req_tag_lat, req_idx_lat, 4'd0, 2'b00}, 2'b0, 32'b0};
        end
        else
        begin
          memreq_out_val <= 1'b1;
          memreq_out_msg <= meta_fill_hold
            ? {1'b1, {meta_tag_q1, req_idx_lat, ctl_wb_idx_next, 2'b00}, 2'b0, path_wb_word1_clean}
            : {1'b1, {meta_tag_q0, req_idx_lat, ctl_wb_idx_next, 2'b00}, 2'b0, path_wb_word0_clean};
        end
        ctl_wb_idx <= (ctl_wb_idx == 4'd15) ?  4'd0 : ctl_wb_idx + 1;
      end
    end
  endtask

  task automatic act_fill_mem_phase;
    begin
      memreq_out_val <= (cachereq_val && ~cachereq_rdy) ? memreq_out_val : 1'b0;
      if (~cachereq_val && cacheresp_val)
      begin
        memreq_out_val <= (ctl_fill_idx == 4'd15) ? 1'b0 : 1'b1;
        memreq_out_msg <= {1'b0, {req_tag_lat, req_idx_lat, ctl_fill_idx_next, 2'b00}, 2'b0, 32'd0};
        ctl_fill_idx   <= (ctl_fill_idx == 4'd15) ? 4'd0 : ctl_fill_idx + 1;
        meta_tag_we    <= (ctl_fill_idx == 4'd15) ? 1'b1 : 1'b0;
        update_line_meta(meta_fill_hold, ctl_fill_idx == 4'd15);
        path_word_hold <= ctl_fill_idx;
      end
    end
  endtask

  task automatic act_fill_vict_phase;
    begin
      memreq_out_val <= 1'b0;
      meta_tag_we    <= (ctl_fill_idx == 4'd15) ? 1'b1 : 1'b0;
      path_word_hold <= ctl_fill_idx;
      ctl_fill_idx   <= (ctl_fill_idx == 4'd15) ? 4'd0 : ctl_fill_idx + 1;
      update_line_meta(meta_fill_hold, ctl_fill_idx == 4'd15);

      if (ctl_fill_idx == 4'd15)
      begin
        vict_wr_en    <= vc_hit_lat || vc_insert_hold;
        vict_wr_tag   <= evict_tag_lat;
        vict_wr_idx   <= evict_idx_lat;
        vict_wr_data  <= evict_block_lat;
        vict_wr_dirty <= evict_dirty_lat;
        vc_insert_hold <= 1'b0;
        vc_fill_hold   <= 1'b0;
        vc_wb_pending  <= 1'b0;
      end
      else
        vict_wr_en <= 1'b0;
    end
  endtask

  task automatic act_response_phase;
    begin
      if (req_type_lat == 1'b0)
        memresp_msg_lat <= {1'b0, 2'b0, expand_load_word(path_miss_word, req_len_eff, req_byte_lat)};
      else
      begin
        memresp_msg_lat <= {1'b1, 2'b0, 32'b0};
        if (meta_fill_hold)
          meta_dirty_bits[path_addr_way1] <= 1'b1;
        else
          meta_dirty_bits[path_addr_way0] <= 1'b1;
      end

      if (vc_insert_hold)
      begin
        vict_wr_en    <= 1'b1;
        vict_wr_tag   <= evict_tag_lat;
        vict_wr_idx   <= evict_idx_lat;
        vict_wr_data  <= evict_block_lat;
        vict_wr_dirty <= evict_dirty_lat;
        vc_insert_hold <= 1'b0;
      end

      meta_age_bits[req_idx_lat] <= (~meta_fill_hold);
      meta_tag_we      <= 1'b0;
      memresp_val_lat  <= 1'b1;
    end
  endtask

  task automatic act_flush_phase;
    begin
      if (meta_dirty_bits[ctl_flush_line])
      begin
        // active write-out sequence
        if (memreq_out_val && cachereq_rdy)
          memreq_out_val <= 1'b0;
        else if (cacheresp_val || ctl_flush_word == 4'd0)
        begin
          memreq_out_val <= 1'b1;
          memreq_out_msg <= {1'b1, {meta_tag_q0, ctl_flush_line[4:0], ctl_flush_word, 2'b00}, 2'b0, path_flush_word};
          ctl_flush_word <= (ctl_flush_word == 4'd15) ? 4'd0 : ctl_flush_word + 1;
          ctl_flush_line <= (ctl_flush_word == 4'd15) ? ctl_flush_line + 1 : ctl_flush_line;
        end
        else
          memreq_out_val <= 1'b0;
      end
      else
      begin
        ctl_flush_line <= (ctl_flush_line == 6'd63) ? 0 : ctl_flush_line + 1;
        ctl_flush_word <= 4'd0;
        memreq_out_val <= 1'b0;
      end
    end
  endtask

  task automatic act_flushdone_phase;
    begin
      memreq_out_val  <= 1'b0;
      meta_dirty_bits <= 0;
    end
  endtask

  task automatic act_waitcpu_phase;
    begin
      meta_tag_we <= 1'b0;
    end
  endtask

  task automatic act_default_phase;
    begin
      ctl_wb_idx   <= 4'd0;
      ctl_fill_idx <= 4'd0;
    end
  endtask

  always @(posedge clk)
  begin
    if (reset)
    begin
      init_datapath_state();
    end
    else
    begin
      if (memresp_val_lat && memresp_rdy)
        memresp_val_lat <= 1'b0;
      vict_wr_en <= 1'b0;
      case (ctl_phase)
        FS_IDLE:        act_idle_phase();
        FS_WRITEBACK:  act_writeback_phase();
        FS_FILL_MEM:   act_fill_mem_phase();
        FS_FILL_VICT: act_fill_vict_phase();
        FS_RESPOND:   act_response_phase();
        FS_FLUSHING:    act_flush_phase();
        FS_FLUSH_DONE:  act_flushdone_phase();
        FS_WAITCPU:    act_waitcpu_phase();
        default:        act_default_phase();
      endcase
    end
  end

endmodule


`endif  /* RISCV_CACHE_ALT_V */
