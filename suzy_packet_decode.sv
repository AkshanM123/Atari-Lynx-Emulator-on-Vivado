`timescale 1ns/1ps

module suzy_decoder 
(input  logic clk,
input logic reset,
input  logic        start,
output logic        busy,
output logic        done,

input  logic [15:0] vid_base_addr,
input  logic [15:0] coll_base_addr,
input  logic [15:0] coll_off,
input  logic [15:0] scb_addr,
input  logic        everon_enable,
input  logic [15:0] hoff,
input  logic [15:0] voff,
input  logic [15:0] sprite_data_ptr,
input  logic [15:0] hpos,
input  logic [15:0] vpos,
input  logic [15:0] hsize,
input  logic [15:0] vsize,
input  logic [15:0] hsizoff,
input  logic [15:0] vsizoff,
input  logic [15:0] stretch,
input  logic [15:0] tilt,
input  logic [7:0]  sprctl0,
input  logic [7:0]  scbctl1,
input  logic [7:0]  sprcoll,
input  logic [7:0]  sprsys,

input  logic [7:0]  pal0,
input  logic [7:0]  pal1,
input  logic [7:0]  pal2,
input  logic [7:0]  pal3,
input  logic [7:0]  pal4,
input  logic [7:0]  pal5,
input  logic [7:0]  pal6,
input  logic [7:0]  pal7,

output logic        ram_rd_en,
output logic [15:0] ram_rd_addr,
input  logic [7:0]  ram_rd_data,
input  logic        ram_rd_valid,

output logic        ram_we,
output logic [15:0] ram_addr,
output logic [7:0]  ram_wdata,

output logic        collision_seen,

output logic [15:0] debug_last_fb_addr,
output logic [7:0]  debug_last_fb_data,
output logic [15:0] debug_pixel_count,
output logic        debug_write_seen

);

localparam int MAX_LINE_BYTES = 254;
localparam logic [7:0] MAX_LINE_BYTES_U8 = 8'd254;

typedef enum logic [4:0] {
    DEC_IDLE,

    DEC_LINE_OFFSET_REQ,
    DEC_LINE_OFFSET_WAIT,

    DEC_LINE_DATA_REQ,
    DEC_LINE_DATA_WAIT,
    DEC_LINE_DATA_ADVANCE,

    DEC_PACKET_START,
    DEC_PACKET_WAIT_ACTIVE,
    DEC_PACKET_RUN,

    DEC_EMIT_PIXEL,
    DEC_RMW_READ_REQ,
    DEC_RMW_READ_WAIT,
    DEC_COLL_READ_REQ,
    DEC_COLL_READ_WAIT,
    DEC_COLL_WRITE,
    DEC_RMW_WRITE,
    DEC_PIXEL_DONE,

    DEC_FLUSH_LINE,
    DEC_ADVANCE_LINE,

    DEC_COLL_DEPOSIT_WRITE,
    DEC_DONE
} dec_state_t;

dec_state_t state;
dec_state_t after_emit_state;

logic [15:0] base_latched;
logic [15:0] coll_base_latched;
logic [15:0] coll_off_latched;
logic [15:0] scb_addr_latched;
logic        everon_latched;
logic [15:0] hoff_latched;
logic [15:0] voff_latched;
logic [15:0] sprite_ptr_latched;
logic [15:0] hpos_latched;
logic [15:0] vpos_latched;
logic [15:0] hsize_latched;
logic [15:0] vsize_latched;
logic [15:0] hsizoff_latched;
logic [15:0] vsizoff_latched;
logic [15:0] stretch_latched;
logic [15:0] tilt_latched;
logic [15:0] tilt_accum_latched;

logic [7:0] sprctl0_latched;
logic [7:0] scbctl1_latched;
logic [7:0] sprcoll_latched;
logic [7:0] sprsys_latched;

logic [15:0] line_start_addr;
logic [15:0] next_line_addr;

logic [7:0] line_offset;
logic [7:0] line_offset_abs;
logic [7:0] line_data_count;
logic [7:0] line_data_index;

logic [7:0] line_buf [0:MAX_LINE_BYTES-1];
logic [(MAX_LINE_BYTES*8)-1:0] line_data_flat;

logic [15:0] pixel_x;
logic [15:0] line_y;

logic [15:0] h_accum;
logic [15:0] v_accum;

logic [8:0] x_emit_rem;
logic [8:0] y_emit_rem;

logic [15:0] line_bits_total;

logic [3:0] current_src_pen;
logic [3:0] current_mapped_pen;

logic [15:0] current_fb_addr;
logic        current_pixel_is_odd;
logic        current_pixel_visible;
logic [7:0]  old_fb_byte;
logic [7:0]  new_fb_byte;

logic [15:0] current_coll_addr;
logic        current_video_write_enable;
logic        current_collision_access_enable;
logic        current_collision_detect_enable;
logic [7:0]  old_coll_byte;
logic [7:0]  new_coll_byte;
logic [3:0]  old_collision_number;
logic [3:0]  fred;
logic [3:0]  sprite_collision_number;

logic signed [10:0] current_world_x;
logic signed [10:0] current_world_y;
logic signed [10:0] current_screen_x;
logic signed [10:0] current_screen_y;

logic [2:0] bits_per_pixel;
logic       totally_literal_mode;
logic       skip_sprite;

logic draw_left;
logic draw_up;

logic [2:0] direction_change_count;

logic [15:0] debug_line_start_addr;
logic [15:0] debug_next_line_addr;
logic [7:0]  debug_line_offset;
logic [7:0]  debug_line_offset_abs;
logic [7:0]  debug_line_data_count;
logic [7:0]  debug_line_y;
logic [7:0]  debug_line_b0;
logic [7:0]  debug_line_b1;
logic [7:0]  debug_line_b2;
logic [7:0]  debug_line_b3;
logic        debug_line_ready;
logic        debug_direction_change_seen;

logic [8:0]  debug_h_emit_count;
logic [8:0]  debug_v_emit_count;
logic [15:0] debug_h_accum;
logic [15:0] debug_v_accum;

logic [7:0] debug_geo_print_count;

logic pkt_seen_active;
logic pkt_done_seen;

integer j;
integer flat_i;

always_comb begin
    case (sprctl0_latched[7:6])
        2'b00: bits_per_pixel = 3'd1;
        2'b01: bits_per_pixel = 3'd2;
        2'b10: bits_per_pixel = 3'd3;
        2'b11: bits_per_pixel = 3'd4;
        default: bits_per_pixel = 3'd4;
    endcase
end

assign totally_literal_mode = scbctl1_latched[7];
assign skip_sprite          = scbctl1_latched[2];

always_comb begin
    line_data_flat = '0;

    for (flat_i = 0; flat_i < MAX_LINE_BYTES; flat_i = flat_i + 1) begin
        line_data_flat[(flat_i * 8) +: 8] = line_buf[flat_i];
    end
end

scb_palette u_scb_palette (
    .src_pen    (current_src_pen),

    .pal0       (pal0),
    .pal1       (pal1),
    .pal2       (pal2),
    .pal3       (pal3),
    .pal4       (pal4),
    .pal5       (pal5),
    .pal6       (pal6),
    .pal7       (pal7),

    .mapped_pen (current_mapped_pen)
);

logic signed [10:0] geo_world_x;
logic signed [10:0] geo_world_y;
logic signed [10:0] geo_screen_x;
logic signed [10:0] geo_screen_y;
logic               geo_visible;
logic [15:0]        geo_fb_addr;
logic               geo_pixel_is_odd;

suzy_geometry u_suzy_geometry (
    .vid_base_addr (base_latched),

    .hoff          (hoff_latched),
    .voff          (voff_latched),

    .hpos          (hpos_latched),
    .vpos          (vpos_latched),

    .out_x         (pixel_x),
    .out_y         (line_y),

    .draw_left     (draw_left),
    .draw_up       (draw_up),

    .world_x       (geo_world_x),
    .world_y       (geo_world_y),

    .screen_x      (geo_screen_x),
    .screen_y      (geo_screen_y),

    .visible       (geo_visible),
    .fb_addr       (geo_fb_addr),
    .pixel_is_odd  (geo_pixel_is_odd)
);

logic       pkt_start;
logic       pkt_busy;
logic       pkt_done;
logic       pkt_pen_valid;
logic       pkt_pen_ready;
logic [3:0] pkt_src_pen;

logic [15:0] pkt_debug_bit_pos;
logic [4:0]  pkt_debug_packet_header;
logic        pkt_debug_literal_packet;
logic        pkt_debug_packed_packet;
logic        pkt_debug_totally_literal;

suzy_packet_decoder #(
    .MAX_LINE_BYTES(MAX_LINE_BYTES)
) u_suzy_packet_decoder (
    .clk                   (clk),
    .reset                 (reset),

    .start                 (pkt_start),
    .busy                  (pkt_busy),
    .done                  (pkt_done),

    .bits_per_pixel        (bits_per_pixel),
    .totally_literal       (totally_literal_mode),

    .line_bits_total       (line_bits_total),
    .line_data_flat        (line_data_flat),

    .pen_valid             (pkt_pen_valid),
    .pen_ready             (pkt_pen_ready),
    .src_pen               (pkt_src_pen),

    .debug_bit_pos         (pkt_debug_bit_pos),
    .debug_packet_header   (pkt_debug_packet_header),
    .debug_literal_packet  (pkt_debug_literal_packet),
    .debug_packed_packet   (pkt_debug_packed_packet),
    .debug_totally_literal (pkt_debug_totally_literal)
);

function automatic logic [7:0] abs_offset8;
    input logic [7:0] value;
    begin
        if (value[7]) begin
            abs_offset8 = (~value) + 8'd1;
        end else begin
            abs_offset8 = value;
        end
    end
endfunction

function automatic logic [15:0] scale_abs_8_8;
    input logic [15:0] size_value;
    begin
        if (size_value[15]) begin
            scale_abs_8_8 = (~size_value) + 16'd1;
        end else begin
            scale_abs_8_8 = size_value;
        end
    end
endfunction

function automatic logic signed [15:0] tilt_delta_signed;
    input logic [15:0] tilt_sum;
    begin
        tilt_delta_signed = {{8{tilt_sum[15]}}, tilt_sum[15:8]};
    end
endfunction

function automatic logic [8:0] scale_emit_count;
    input logic [15:0] size_value;
    input logic [15:0] accum_value;

    logic [15:0] mag_value;
    logic [16:0] sum_value;
    logic [8:0]  raw_count;
    begin
        mag_value = scale_abs_8_8(size_value);

        sum_value = {1'b0, accum_value[7:0]} + {1'b0, mag_value};
        raw_count = {1'b0, sum_value[16:8]};

        scale_emit_count = raw_count;
    end
endfunction

function automatic logic [15:0] scale_next_accum;
    input logic [15:0] size_value;
    input logic [15:0] accum_value;

    logic [15:0] mag_value;
    logic [16:0] sum_value;
    begin
        mag_value = scale_abs_8_8(size_value);

        sum_value = {1'b0, accum_value[7:0]} + {1'b0, mag_value};
        scale_next_accum = {8'h00, sum_value[7:0]};
    end
endfunction

function automatic logic [15:0] initial_h_accum_for_direction;
    input logic draw_left_value;
    begin
        if (draw_left_value) begin
            initial_h_accum_for_direction = 16'h0000;
        end else begin
            initial_h_accum_for_direction = hsizoff_latched;
        end
    end
endfunction

function automatic logic [15:0] initial_v_accum_for_direction;
    input logic draw_up_value;
    begin
        if (draw_up_value) begin
            initial_v_accum_for_direction = 16'h0000;
        end else begin
            initial_v_accum_for_direction = vsizoff_latched;
        end
    end
endfunction

function automatic logic destination_line_visible;
    input logic [15:0] line_index;

    logic [15:0] world_y_u16;
    logic [15:0] screen_y_u16;
    begin
        if (draw_up) begin
            world_y_u16 = vpos_latched - line_index;
        end else begin
            world_y_u16 = vpos_latched + line_index;
        end

        screen_y_u16 = world_y_u16 - voff_latched;
        destination_line_visible = (screen_y_u16 < 16'd102);
    end
endfunction

function automatic logic initial_draw_up_from_controls;
    input logic [7:0] scbctl1_value;
    input logic [7:0] sprctl0_value;
    begin
        initial_draw_up_from_controls = scbctl1_value[1] ^ sprctl0_value[4];
    end
endfunction

function automatic logic initial_draw_left_from_controls;
    input logic [7:0] scbctl1_value;
    input logic [7:0] sprctl0_value;
    begin
        initial_draw_left_from_controls = scbctl1_value[0] ^ sprctl0_value[5];
    end
endfunction

function automatic logic next_draw_up;
    input logic cur_up;
    input logic cur_left;
    begin
        case ({cur_up, cur_left})
            2'b00: next_draw_up = 1'b1;
            2'b10: next_draw_up = 1'b1;
            2'b11: next_draw_up = 1'b0;
            2'b01: next_draw_up = 1'b0;
            default: next_draw_up = 1'b0;
        endcase
    end
endfunction

function automatic logic next_draw_left;
    input logic cur_up;
    input logic cur_left;
    begin
        case ({cur_up, cur_left})
            2'b00: next_draw_left = 1'b0;
            2'b10: next_draw_left = 1'b1;
            2'b11: next_draw_left = 1'b1;
            2'b01: next_draw_left = 1'b0;
            default: next_draw_left = 1'b0;
        endcase
    end
endfunction

function automatic logic sprite_type_f_is_opaque;
    input logic [2:0] sprite_type;
    begin
        unique case (sprite_type)
            3'b010: sprite_type_f_is_opaque = 1'b0;
            3'b011: sprite_type_f_is_opaque = 1'b0;
            default: sprite_type_f_is_opaque = 1'b1;
        endcase
    end
endfunction

function automatic logic sprite_type_zero_writes_video;
    input logic [2:0] sprite_type;
    begin
        unique case (sprite_type)
            3'b000: sprite_type_zero_writes_video = 1'b1;
            3'b001: sprite_type_zero_writes_video = 1'b1;
            default: sprite_type_zero_writes_video = 1'b0;
        endcase
    end
endfunction

function automatic logic sprite_type_uses_xor_video;
    input logic [2:0] sprite_type;
    begin
        sprite_type_uses_xor_video = (sprite_type == 3'b110);
    end
endfunction

function automatic logic sprite_pixel_writes_video;
    input logic [7:0] sprctl0_value;
    input logic [3:0] mapped_pen_value;

    logic [2:0] sprite_type;
    begin
        sprite_type = sprctl0_value[2:0];

        if ((mapped_pen_value == 4'h0) && !sprite_type_zero_writes_video(sprite_type)) begin
            sprite_pixel_writes_video = 1'b0;
        end else if ((mapped_pen_value == 4'hF) && !sprite_type_f_is_opaque(sprite_type)) begin
            sprite_pixel_writes_video = 1'b0;
        end else begin
            sprite_pixel_writes_video = 1'b1;
        end
    end
endfunction

function automatic logic sprite_type_allows_collision_detect;
    input logic [2:0] sprite_type;
    begin
        unique case (sprite_type)
            3'b111: sprite_type_allows_collision_detect = 1'b1;
            3'b010: sprite_type_allows_collision_detect = 1'b1;
            3'b100: sprite_type_allows_collision_detect = 1'b1;
            3'b011: sprite_type_allows_collision_detect = 1'b1;
            3'b110: sprite_type_allows_collision_detect = 1'b1;
            default: sprite_type_allows_collision_detect = 1'b0;
        endcase
    end
endfunction

function automatic logic sprite_type_allows_collision_buffer_access;
    input logic [2:0] sprite_type;
    begin
        unique case (sprite_type)
            3'b111: sprite_type_allows_collision_buffer_access = 1'b1;
            3'b010: sprite_type_allows_collision_buffer_access = 1'b1;
            3'b100: sprite_type_allows_collision_buffer_access = 1'b1;
            3'b011: sprite_type_allows_collision_buffer_access = 1'b1;
            3'b000: sprite_type_allows_collision_buffer_access = 1'b1;
            3'b110: sprite_type_allows_collision_buffer_access = 1'b1;
            default: sprite_type_allows_collision_buffer_access = 1'b0;
        endcase
    end
endfunction

function automatic logic sprite_type_e_is_collideable;
    input logic [2:0] sprite_type;
    begin
        unique case (sprite_type)
            3'b100: sprite_type_e_is_collideable = 1'b1;
            3'b011: sprite_type_e_is_collideable = 1'b1;
            default: sprite_type_e_is_collideable = 1'b0;
        endcase
    end
endfunction

function automatic logic sprite_type_zero_is_collideable;
    input logic [2:0] sprite_type;
    begin





        unique case (sprite_type)
            3'b100: sprite_type_zero_is_collideable = 1'b0;
            3'b011: sprite_type_zero_is_collideable = 1'b0;
            default: sprite_type_zero_is_collideable = 1'b0;
        endcase
    end
endfunction

function automatic logic sprite_pixel_accesses_collision_buffer;
    input logic [7:0] sprctl0_value;
    input logic [3:0] mapped_pen_value;

    logic [2:0] sprite_type;
    begin
        sprite_type = sprctl0_value[2:0];

        if (!sprite_type_allows_collision_buffer_access(sprite_type)) begin
            sprite_pixel_accesses_collision_buffer = 1'b0;
        end else if (sprite_type == 3'b000) begin
            sprite_pixel_accesses_collision_buffer = (mapped_pen_value != 4'hE);
        end else if (mapped_pen_value == 4'h0) begin
            sprite_pixel_accesses_collision_buffer = sprite_type_zero_is_collideable(sprite_type);
        end else if (mapped_pen_value == 4'hE) begin
            sprite_pixel_accesses_collision_buffer = sprite_type_e_is_collideable(sprite_type);
        end else begin
            sprite_pixel_accesses_collision_buffer = 1'b1;
        end
    end
endfunction

function automatic logic sprite_collision_disabled;
    input logic [7:0] sprcoll_value;
    input logic [7:0] sprsys_value;
    begin
        sprite_collision_disabled = sprcoll_value[5] | sprsys_value[5];
    end
endfunction

function automatic logic sprite_depository_write_enabled;
    input logic [7:0] sprctl0_value;
    input logic [7:0] sprcoll_value;
    input logic [7:0] sprsys_value;
    input logic       everon_value;
    begin
        sprite_depository_write_enabled = everon_value |
            (!sprite_collision_disabled(sprcoll_value, sprsys_value) &&
             sprite_type_allows_collision_detect(sprctl0_value[2:0]));
    end
endfunction

always_comb begin
    if (sprite_type_uses_xor_video(sprctl0_latched[2:0])) begin
        if (current_pixel_is_odd) begin
            new_fb_byte = {old_fb_byte[7:4], old_fb_byte[3:0] ^ current_mapped_pen};
        end else begin
            new_fb_byte = {old_fb_byte[7:4] ^ current_mapped_pen, old_fb_byte[3:0]};
        end
    end else begin
        if (current_pixel_is_odd) begin
            new_fb_byte = {old_fb_byte[7:4], current_mapped_pen};
        end else begin
            new_fb_byte = {current_mapped_pen, old_fb_byte[3:0]};
        end
    end
end

always_comb begin
    if (current_pixel_is_odd) begin
        old_collision_number = old_coll_byte[3:0];
        new_coll_byte = {old_coll_byte[7:4], sprite_collision_number};
    end else begin
        old_collision_number = old_coll_byte[7:4];
        new_coll_byte = {sprite_collision_number, old_coll_byte[3:0]};
    end
end

always_ff @(posedge clk) begin
    if (reset) begin
        state <= DEC_IDLE;
        after_emit_state <= DEC_PACKET_RUN;

        busy <= 1'b0;
        done <= 1'b0;
        collision_seen <= 1'b0;

        ram_rd_en <= 1'b0;
        ram_rd_addr <= 16'h0000;

        ram_we <= 1'b0;
        ram_addr <= 16'h0000;
        ram_wdata <= 8'h00;

        pkt_start <= 1'b0;
        pkt_pen_ready <= 1'b0;
        pkt_seen_active <= 1'b0;
        pkt_done_seen <= 1'b0;

        base_latched <= 16'h0000;
        coll_base_latched <= 16'h0000;
        coll_off_latched <= 16'h0000;
        scb_addr_latched <= 16'h0000;
        everon_latched <= 1'b0;
        hoff_latched <= 16'h0000;
        voff_latched <= 16'h0000;
        sprite_ptr_latched <= 16'h0000;
        hpos_latched <= 16'h0000;
        vpos_latched <= 16'h0000;
        hsize_latched <= 16'h0100;
        vsize_latched <= 16'h0100;
        hsizoff_latched <= 16'h007F;
        vsizoff_latched <= 16'h007F;
        stretch_latched <= 16'h0000;
        tilt_latched <= 16'h0000;
        tilt_accum_latched <= 16'h0000;

        sprctl0_latched <= 8'h00;
        scbctl1_latched <= 8'h00;
        sprcoll_latched <= 8'h00;
        sprsys_latched <= 8'h00;

        line_start_addr <= 16'h0000;
        next_line_addr <= 16'h0000;
        line_offset <= 8'h00;
        line_offset_abs <= 8'h00;
        line_data_count <= 8'd0;
        line_data_index <= 8'd0;

        pixel_x <= 16'd0;
        line_y <= 16'd0;

        h_accum <= 16'h0000;
        v_accum <= 16'h0000;
        x_emit_rem <= 9'd0;
        y_emit_rem <= 9'd0;

        line_bits_total <= 16'd0;

        current_src_pen <= 4'h0;

        current_fb_addr <= 16'h0000;
        current_pixel_is_odd <= 1'b0;
        current_pixel_visible <= 1'b0;

        current_world_x <= 11'sd0;
        current_world_y <= 11'sd0;
        current_screen_x <= 11'sd0;
        current_screen_y <= 11'sd0;

        old_fb_byte <= 8'h00;

        current_coll_addr <= 16'h0000;
        current_video_write_enable <= 1'b0;
        current_collision_access_enable <= 1'b0;
        current_collision_detect_enable <= 1'b0;
        old_coll_byte <= 8'h00;
        fred <= 4'h0;
        sprite_collision_number <= 4'h0;

        draw_left <= 1'b0;
        draw_up <= 1'b0;
        direction_change_count <= 3'd0;

        debug_last_fb_addr <= 16'h0000;
        debug_last_fb_data <= 8'h00;
        debug_pixel_count <= 16'd0;
        debug_write_seen <= 1'b0;

        debug_line_start_addr <= 16'h0000;
        debug_next_line_addr <= 16'h0000;
        debug_line_offset <= 8'h00;
        debug_line_offset_abs <= 8'h00;
        debug_line_data_count <= 8'h00;
        debug_line_y <= 8'h00;
        debug_line_b0 <= 8'h00;
        debug_line_b1 <= 8'h00;
        debug_line_b2 <= 8'h00;
        debug_line_b3 <= 8'h00;
        debug_line_ready <= 1'b0;
        debug_direction_change_seen <= 1'b0;

        debug_h_emit_count <= 9'd0;
        debug_v_emit_count <= 9'd0;
        debug_h_accum <= 16'h0000;
        debug_v_accum <= 16'h0000;
        debug_geo_print_count <= 8'd0;

        for (j = 0; j < MAX_LINE_BYTES; j = j + 1) begin
            line_buf[j] <= 8'h00;
        end

    end else begin
        ram_rd_en <= 1'b0;
        ram_we <= 1'b0;
        done <= 1'b0;
        collision_seen <= 1'b0;
        pkt_start <= 1'b0;
        pkt_pen_ready <= 1'b0;

        debug_line_ready <= 1'b0;
        debug_direction_change_seen <= 1'b0;

        if (pkt_done) begin
            pkt_done_seen <= 1'b1;
        end

        if (pkt_busy) begin
            pkt_seen_active <= 1'b1;
        end

        case (state)

            DEC_IDLE: begin
                busy <= 1'b0;
                pkt_seen_active <= 1'b0;
                pkt_done_seen <= 1'b0;

                if (start) begin
                    busy <= 1'b1;

                    base_latched <= vid_base_addr;
                    coll_base_latched <= coll_base_addr;
                    coll_off_latched <= coll_off;
                    scb_addr_latched <= scb_addr;
                    everon_latched <= everon_enable;
                    hoff_latched <= hoff;
                    voff_latched <= voff;
                    sprite_ptr_latched <= sprite_data_ptr;
                    hpos_latched <= hpos;
                    vpos_latched <= vpos;
                    hsize_latched <= hsize;
                    vsize_latched <= vsize;
                    hsizoff_latched <= hsizoff;
                    vsizoff_latched <= vsizoff;
                    stretch_latched <= stretch;
                    tilt_latched <= tilt;
                    tilt_accum_latched <= 16'h0000;

                    sprctl0_latched <= sprctl0;
                    scbctl1_latched <= scbctl1;
                    sprcoll_latched <= sprcoll;
                    sprsys_latched <= sprsys;
                    sprite_collision_number <= sprcoll[3:0];
                    fred <= 4'h0;

                    line_start_addr <= sprite_data_ptr;
                    line_y <= 16'd0;
                    pixel_x <= 16'd0;

                    h_accum <= (initial_draw_left_from_controls(scbctl1, sprctl0) ? 16'h0000 : hsizoff);
                    v_accum <= (initial_draw_up_from_controls(scbctl1, sprctl0) ? 16'h0000 : vsizoff);
                    x_emit_rem <= 9'd0;
                    y_emit_rem <= 9'd0;

                    draw_up <= initial_draw_up_from_controls(scbctl1, sprctl0);
                    draw_left <= initial_draw_left_from_controls(scbctl1, sprctl0);
                    direction_change_count <= 3'd0;

                    debug_pixel_count <= 16'd0;
                    debug_write_seen <= 1'b0;
                    debug_geo_print_count <= 8'd0;

                    if (scbctl1[2]) begin
                        state <= DEC_COLL_DEPOSIT_WRITE;
                    end else begin
                        state <= DEC_LINE_OFFSET_REQ;
                    end
                end
            end

            DEC_LINE_OFFSET_REQ: begin
                ram_rd_en <= 1'b1;
                ram_rd_addr <= line_start_addr;
                state <= DEC_LINE_OFFSET_WAIT;
            end

            DEC_LINE_OFFSET_WAIT: begin
                ram_rd_en <= 1'b0;

                if (ram_rd_valid) begin
                    line_offset <= ram_rd_data;
                    line_offset_abs <= abs_offset8(ram_rd_data);

                    debug_line_start_addr <= line_start_addr;
                    debug_line_offset <= ram_rd_data;
                    debug_line_offset_abs <= abs_offset8(ram_rd_data);
                    debug_line_y <= line_y[7:0];

                    if (ram_rd_data == 8'h00) begin
                        state <= DEC_COLL_DEPOSIT_WRITE;

                    end else if (ram_rd_data == 8'h01) begin
                        if (direction_change_count >= 3'd3) begin
                            state <= DEC_COLL_DEPOSIT_WRITE;
                        end else begin
                            draw_up <= next_draw_up(draw_up, draw_left);
                            draw_left <= next_draw_left(draw_up, draw_left);

                            direction_change_count <= direction_change_count + 3'd1;
                            debug_direction_change_seen <= 1'b1;

                            line_start_addr <= line_start_addr + 16'd1;




                            pixel_x <= 16'd0;
                            line_y  <= 16'd0;

                            h_accum <= initial_h_accum_for_direction(next_draw_left(draw_up, draw_left));
                            v_accum <= initial_v_accum_for_direction(next_draw_up(draw_up, draw_left));
                            y_emit_rem <= 9'd0;

                            state <= DEC_LINE_OFFSET_REQ;
                        end

                    end else begin
                        next_line_addr <= line_start_addr + {8'h00, ram_rd_data};

                        if (ram_rd_data <= 8'd1) begin
                            line_data_count <= 8'd0;
                        end else if (ram_rd_data > (MAX_LINE_BYTES_U8 + 8'd1)) begin
                            line_data_count <= MAX_LINE_BYTES_U8;
                        end else begin
                            line_data_count <= ram_rd_data - 8'd1;
                        end

                        debug_next_line_addr <= line_start_addr + {8'h00, ram_rd_data};

                        if (ram_rd_data <= 8'd1) begin
                            debug_line_data_count <= 8'd0;
                        end else if (ram_rd_data > (MAX_LINE_BYTES_U8 + 8'd1)) begin
                            debug_line_data_count <= MAX_LINE_BYTES_U8;
                        end else begin
                            debug_line_data_count <= ram_rd_data - 8'd1;
                        end

                        line_data_index <= 8'd0;

                        debug_line_b0 <= 8'h00;
                        debug_line_b1 <= 8'h00;
                        debug_line_b2 <= 8'h00;
                        debug_line_b3 <= 8'h00;

                        for (j = 0; j < MAX_LINE_BYTES; j = j + 1) begin
                            line_buf[j] <= 8'h00;
                        end

                        state <= DEC_LINE_DATA_REQ;
                    end
                end
            end

            DEC_LINE_DATA_REQ: begin
                if (line_data_count == 8'd0) begin
                    state <= DEC_FLUSH_LINE;
                end else begin
                    ram_rd_en <= 1'b1;
                    ram_rd_addr <= line_start_addr + 16'd1 + {8'd0, line_data_index};
                    state <= DEC_LINE_DATA_WAIT;
                end
            end

            DEC_LINE_DATA_WAIT: begin
                ram_rd_en <= 1'b0;

                if (ram_rd_valid) begin
                    if (line_data_index < MAX_LINE_BYTES_U8) begin
                        line_buf[line_data_index] <= ram_rd_data;

                        case (line_data_index)
                            8'd0: debug_line_b0 <= ram_rd_data;
                            8'd1: debug_line_b1 <= ram_rd_data;
                            8'd2: debug_line_b2 <= ram_rd_data;
                            8'd3: debug_line_b3 <= ram_rd_data;
                            default: begin
                            end
                        endcase
                    end

                    state <= DEC_LINE_DATA_ADVANCE;
                end
            end

            DEC_LINE_DATA_ADVANCE: begin
                if ((line_data_index + 8'd1) >= line_data_count) begin
                    line_bits_total <= {8'd0, line_data_count} << 3;
                    pixel_x <= 16'd0;

                    debug_v_emit_count <= scale_emit_count(vsize_latched, v_accum);
                    debug_v_accum <= v_accum;

                    y_emit_rem <= scale_emit_count(vsize_latched, v_accum);
                    v_accum <= scale_next_accum(vsize_latched, v_accum);

                    debug_line_ready <= 1'b1;

                    if (scale_emit_count(vsize_latched, v_accum) == 9'd0) begin
                        state <= DEC_FLUSH_LINE;
                    end else begin
                        state <= DEC_PACKET_START;
                    end
                end else begin
                    line_data_index <= line_data_index + 8'd1;
                    state <= DEC_LINE_DATA_REQ;
                end
            end

            DEC_PACKET_START: begin
                pixel_x <= 16'd0;
                h_accum <= initial_h_accum_for_direction(draw_left);

                pkt_seen_active <= 1'b0;
                pkt_done_seen <= 1'b0;

                if (!destination_line_visible(line_y)) begin
                    state <= DEC_FLUSH_LINE;
                end else begin
                    pkt_start <= 1'b1;
                    state <= DEC_PACKET_WAIT_ACTIVE;
                end
            end

            DEC_PACKET_WAIT_ACTIVE: begin
                if (pkt_done) begin
                    pkt_done_seen <= 1'b1;
                    state <= DEC_FLUSH_LINE;
                end else if (pkt_busy) begin
                    pkt_seen_active <= 1'b1;
                    state <= DEC_PACKET_RUN;
                end
            end

            DEC_PACKET_RUN: begin
                if (pkt_done || pkt_done_seen) begin
                    state <= DEC_FLUSH_LINE;

                end else if (pkt_pen_valid) begin
                    current_src_pen <= pkt_src_pen;
                    pkt_pen_ready <= 1'b1;

                    debug_h_emit_count <= scale_emit_count(hsize_latched, h_accum);
                    debug_h_accum <= h_accum;

                    x_emit_rem <= scale_emit_count(hsize_latched, h_accum);
                    h_accum <= scale_next_accum(hsize_latched, h_accum);

                    after_emit_state <= DEC_PACKET_RUN;
                    state <= DEC_EMIT_PIXEL;

                end else if (pkt_seen_active && !pkt_busy && !pkt_pen_valid) begin
                    state <= DEC_FLUSH_LINE;
                end
            end

            DEC_EMIT_PIXEL: begin
                if (x_emit_rem == 9'd0) begin
                    debug_pixel_count <= debug_pixel_count + 16'd1;
                    state <= after_emit_state;

                end else begin
                    current_pixel_visible <= geo_visible;
                    current_fb_addr <= geo_fb_addr;
                    current_pixel_is_odd <= geo_pixel_is_odd;
                    current_coll_addr <= coll_base_latched + (geo_fb_addr - base_latched);

                    current_world_x <= geo_world_x;
                    current_world_y <= geo_world_y;
                    current_screen_x <= geo_screen_x;
                    current_screen_y <= geo_screen_y;

                    current_video_write_enable <= sprite_pixel_writes_video(
                        sprctl0_latched,
                        current_mapped_pen
                    );

                    current_collision_access_enable <=
                        geo_visible &&
                        !sprite_collision_disabled(sprcoll_latched, sprsys_latched) &&
                        sprite_pixel_accesses_collision_buffer(
                            sprctl0_latched,
                            current_mapped_pen
                        );

                    current_collision_detect_enable <=
                        geo_visible &&
                        !sprite_collision_disabled(sprcoll_latched, sprsys_latched) &&
                        sprite_type_allows_collision_detect(sprctl0_latched[2:0]) &&
                        sprite_pixel_accesses_collision_buffer(
                            sprctl0_latched,
                            current_mapped_pen
                        );

                    if (!geo_visible) begin
                        state <= DEC_PIXEL_DONE;
                    end else if (sprite_pixel_writes_video(sprctl0_latched, current_mapped_pen)) begin
                        state <= DEC_RMW_READ_REQ;
                    end else if (!sprite_collision_disabled(sprcoll_latched, sprsys_latched) &&
                                 sprite_pixel_accesses_collision_buffer(sprctl0_latched, current_mapped_pen)) begin
                        state <= DEC_COLL_READ_REQ;
                    end else begin
                        state <= DEC_PIXEL_DONE;
                    end
                end
            end

            DEC_RMW_READ_REQ: begin
                ram_rd_en <= 1'b1;
                ram_rd_addr <= current_fb_addr;
                state <= DEC_RMW_READ_WAIT;
            end

            DEC_RMW_READ_WAIT: begin
                ram_rd_en <= 1'b0;

                if (ram_rd_valid) begin
                    old_fb_byte <= ram_rd_data;

                    if (current_collision_access_enable) begin
                        state <= DEC_COLL_READ_REQ;
                    end else begin
                        state <= DEC_RMW_WRITE;
                    end
                end
            end

            DEC_COLL_READ_REQ: begin
                ram_rd_en <= 1'b1;
                ram_rd_addr <= current_coll_addr;
                state <= DEC_COLL_READ_WAIT;
            end

            DEC_COLL_READ_WAIT: begin
                ram_rd_en <= 1'b0;

                if (ram_rd_valid) begin
                    old_coll_byte <= ram_rd_data;

                    if (current_collision_detect_enable &&
                        ((current_pixel_is_odd ? ram_rd_data[3:0] : ram_rd_data[7:4]) > fred)) begin
                        fred <= current_pixel_is_odd ? ram_rd_data[3:0] : ram_rd_data[7:4];

                        if ((current_pixel_is_odd ? ram_rd_data[3:0] : ram_rd_data[7:4]) != 4'h0) begin
                            collision_seen <= 1'b1;
                        end
                    end

                    state <= DEC_COLL_WRITE;
                end
            end

            DEC_COLL_WRITE: begin
                ram_we <= 1'b1;
                ram_addr <= current_coll_addr;
                ram_wdata <= new_coll_byte;

                if (current_video_write_enable) begin
                    state <= DEC_RMW_WRITE;
                end else begin
                    state <= DEC_PIXEL_DONE;
                end
            end

            DEC_RMW_WRITE: begin
                ram_we <= 1'b1;
                ram_addr <= current_fb_addr;
                ram_wdata <= new_fb_byte;

                debug_last_fb_addr <= current_fb_addr;
                debug_last_fb_data <= new_fb_byte;
                debug_write_seen <= 1'b1;

                state <= DEC_PIXEL_DONE;
            end

            DEC_PIXEL_DONE: begin
                debug_pixel_count <= debug_pixel_count + 16'd1;

                if (debug_geo_print_count < 8'hff) begin
                    debug_geo_print_count <= debug_geo_print_count + 8'd1;
                end

                if (x_emit_rem > 9'd1) begin
                    x_emit_rem <= x_emit_rem - 9'd1;
                    pixel_x <= pixel_x + 9'd1;
                    state <= DEC_EMIT_PIXEL;
                end else begin
                    x_emit_rem <= 9'd0;
                    pixel_x <= pixel_x + 9'd1;
                    state <= after_emit_state;
                end
            end

            DEC_FLUSH_LINE: begin
                pkt_seen_active <= 1'b0;
                pkt_done_seen <= 1'b0;

                if (scbctl1_latched[5:4] >= 2'b10) begin
                    hsize_latched <= hsize_latched + stretch_latched;
                end

                if (sprsys_latched[4]) begin
                    vsize_latched <= vsize_latched + stretch_latched;
                end

                if (scbctl1_latched[5:4] == 2'b11) begin
                    tilt_accum_latched <= tilt_accum_latched + tilt_latched;
                    hpos_latched <= hpos_latched + tilt_delta_signed(tilt_accum_latched + tilt_latched);
                end

                state <= DEC_ADVANCE_LINE;
            end

            DEC_ADVANCE_LINE: begin
                if (y_emit_rem > 9'd1) begin
                    y_emit_rem <= y_emit_rem - 9'd1;
                    line_y <= line_y + 16'd1;
                    pixel_x <= 16'd0;
                    state <= DEC_PACKET_START;

                end else begin
                    line_start_addr <= next_line_addr;

                    if (y_emit_rem == 9'd1) begin
                        line_y <= line_y + 16'd1;
                    end

                    y_emit_rem <= 9'd0;
                    pixel_x <= 16'd0;
                    state <= DEC_LINE_OFFSET_REQ;
                end
            end

            DEC_COLL_DEPOSIT_WRITE: begin
                if (sprite_depository_write_enabled(
                        sprctl0_latched,
                        sprcoll_latched,
                        sprsys_latched,
                        everon_latched
                    )) begin
                    ram_we <= 1'b1;
                    ram_addr <= scb_addr_latched + coll_off_latched;
                    ram_wdata <= {4'h0, fred};

                    if (fred != 4'h0) begin
                        collision_seen <= 1'b1;
                    end
                end

                state <= DEC_DONE;
            end

            DEC_DONE: begin
                busy <= 1'b0;
                done <= 1'b1;
                pkt_seen_active <= 1'b0;
                pkt_done_seen <= 1'b0;
                state <= DEC_IDLE;
            end

            default: begin
                state <= DEC_IDLE;
            end

        endcase
    end
end

logic unused_inputs;

assign unused_inputs =
    coll_base_latched[0] ^
    coll_off_latched[0] ^
    scb_addr_latched[0] ^
    everon_latched ^
    current_coll_addr[0] ^
    current_video_write_enable ^
    current_collision_access_enable ^
    current_collision_detect_enable ^
    old_coll_byte[0] ^
    new_coll_byte[0] ^
    old_collision_number[0] ^
    fred[0] ^
    sprite_collision_number[0] ^
    sprite_ptr_latched[0] ^
    hsize_latched[0] ^
    vsize_latched[0] ^
    hsizoff_latched[0] ^
    vsizoff_latched[0] ^
    stretch_latched[0] ^
    tilt_latched[0] ^
    tilt_accum_latched[0] ^
    hoff_latched[0] ^
    voff_latched[0] ^
    line_offset_abs[0] ^
    direction_change_count[0] ^
    h_accum[0] ^
    v_accum[0] ^
    debug_line_start_addr[0] ^
    debug_next_line_addr[0] ^
    debug_line_offset[0] ^
    debug_line_offset_abs[0] ^
    debug_line_data_count[0] ^
    debug_line_y[0] ^
    debug_line_b0[0] ^
    debug_line_b1[0] ^
    debug_line_b2[0] ^
    debug_line_b3[0] ^
    debug_line_ready ^
    debug_direction_change_seen ^
    debug_h_emit_count[0] ^
    debug_v_emit_count[0] ^
    debug_h_accum[0] ^
    debug_v_accum[0] ^
    current_world_x[0] ^
    current_world_y[0] ^
    current_screen_x[0] ^
    current_screen_y[0] ^
    debug_geo_print_count[0] ^
    pkt_busy ^
    pkt_seen_active ^
    pkt_done_seen ^
    pkt_debug_bit_pos[0] ^
    pkt_debug_packet_header[0] ^
    pkt_debug_literal_packet ^
    pkt_debug_packed_packet ^
    pkt_debug_totally_literal ^
    sprctl0[0] ^
    scbctl1[0] ^
    sprcoll[0] ^
    sprsys[0] ^
    sprctl0_latched[0] ^
    scbctl1_latched[0] ^
    sprcoll_latched[0] ^
    sprsys_latched[0];

endmodule