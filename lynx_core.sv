`timescale 1ns/1ps

module lynx_core_top (
    input  logic        clk,
    input  logic        reset,

    input  logic        cpu_cs,
    input  logic        cpu_we,
    input  logic [15:0] cpu_addr,
    input  logic  [7:0] cpu_wdata,
    output logic  [7:0] cpu_rdata,

    input  logic [7:0]  lynx_fcb0_joystick,
    input  logic [2:0]  lynx_fcb1_switches,

    input  logic        mikey_hcount_tick,
    input  logic        mikey_vcount_tick,

    input  logic [7:0]  lynx_x,
    input  logic [6:0]  lynx_y,
    input  logic        lynx_active,

    output logic  [3:0] pix_index,
    output logic        pix_valid,

    output logic  [7:0] rgb_r,
    output logic  [7:0] rgb_g,
    output logic  [7:0] rgb_b,
    output logic        rgb_valid,
    output logic  [7:0] rgb_x,
    output logic  [6:0] rgb_y,
    output logic        mikey_frame_tick,

    output logic        audio_pwm_l,
    output logic        audio_pwm_r,

    output logic        mikey_irq_request,
    output logic        suzy_cpu_sleep_request,

    output logic  [7:0] debug_mapctl,
    output logic [15:0] debug_video_addr,
    output logic  [7:0] debug_video_data,
    output logic  [7:0] debug_mikey_dispctl,
    output logic [15:0] debug_mikey_disp_addr,

    output logic        debug_sel_ram,
    output logic        debug_sel_suzy,
    output logic        debug_sel_mikey,
    output logic        debug_sel_rom,
    output logic        debug_sel_mapctl,
    output logic        debug_sel_vector,

    output logic        debug_audio_addr_write_seen,
    output logic        debug_audio_overlay_write_seen,
    output logic        debug_audio_hw_write_seen,

    output logic [31:0] debug_audio_addr_write_count,
    output logic [31:0] debug_audio_overlay_write_count,
    output logic [31:0] debug_audio_hw_write_count,

    output logic [15:0] debug_audio_last_addr,
    output logic  [7:0] debug_audio_last_data,
    output logic  [7:0] debug_audio_last_mapctl,

    output logic        debug_fcb0_read_seen,
    output logic        debug_fcb1_read_seen,

    output logic [31:0] debug_fcb0_read_count,
    output logic [31:0] debug_fcb1_read_count,

    output logic  [7:0] debug_fcb0_last_value,
    output logic  [2:0] debug_fcb1_last_value,
    output logic [15:0] debug_fcb_last_addr,

    output logic [31:0] debug_fc_read_count,
    output logic [31:0] debug_fc_write_count,
    output logic [31:0] debug_fd_read_count,
    output logic [31:0] debug_fd_write_count,

    output logic [15:0] debug_last_fc_addr,
    output logic  [7:0] debug_last_fc_wdata,
    output logic  [7:0] debug_last_fc_rdata,
    output logic        debug_last_fc_we,

    output logic [15:0] debug_last_fd_addr,
    output logic  [7:0] debug_last_fd_wdata,
    output logic  [7:0] debug_last_fd_rdata,
    output logic        debug_last_fd_we
);

    import lynx_pkg::*;

    logic [7:0] mapctl;

    logic sel_ram;
    logic sel_suzy;
    logic sel_mikey;
    logic sel_rom;
    logic sel_bios;
    logic sel_mapctl;
    logic sel_vector;

    logic is_suzy_range;
    logic is_mikey_range;
    logic is_rom_range;
    logic is_bios_range;
    logic is_vector_range;

    always_ff @(posedge clk) begin
        if (reset) begin
            mapctl <= 8'h00;
        end else begin
            if (cpu_cs && cpu_we && sel_mapctl) begin
                mapctl <= cpu_wdata;
            end
        end
    end

    assign debug_mapctl = mapctl;

    lynx_addr_decode u_addr_decode (
        .cpu_addr        (cpu_addr),
        .mapctl          (mapctl),

        .sel_ram         (sel_ram),
        .sel_suzy        (sel_suzy),
        .sel_mikey       (sel_mikey),
        .sel_rom         (sel_rom),
        .sel_bios        (sel_bios),
        .sel_mapctl      (sel_mapctl),
        .sel_vector      (sel_vector),

        .is_suzy_range   (is_suzy_range),
        .is_mikey_range  (is_mikey_range),
        .is_rom_range    (is_rom_range),
        .is_bios_range   (is_bios_range),
        .is_vector_range (is_vector_range)
    );

    assign debug_sel_ram    = sel_ram;
    assign debug_sel_suzy   = sel_suzy;
    assign debug_sel_mikey  = sel_mikey;
    assign debug_sel_rom    = sel_rom;
    assign debug_sel_mapctl = sel_mapctl;
    assign debug_sel_vector = sel_vector;

    logic unused_decode_flags;
    assign unused_decode_flags =
        is_suzy_range ^
        is_mikey_range ^
        is_rom_range ^
        is_bios_range ^
        is_vector_range;

    logic audio_addr_hit;
    logic audio_addr_write;
    logic audio_overlay_write;
    logic audio_hw_write;

    assign audio_addr_hit =
        ((cpu_addr >= 16'hFD20) && (cpu_addr <= 16'hFD3F)) ||
        (cpu_addr == 16'hFD50);

    assign audio_addr_write    = cpu_cs && cpu_we && audio_addr_hit;
    assign audio_overlay_write = audio_addr_write && sel_ram   && mapctl[1];
    assign audio_hw_write      = audio_addr_write && sel_mikey && !mapctl[1];

    always_ff @(posedge clk) begin
        if (reset) begin
            debug_audio_addr_write_seen    <= 1'b0;
            debug_audio_overlay_write_seen <= 1'b0;
            debug_audio_hw_write_seen      <= 1'b0;

            debug_audio_addr_write_count    <= 32'd0;
            debug_audio_overlay_write_count <= 32'd0;
            debug_audio_hw_write_count      <= 32'd0;

            debug_audio_last_addr   <= 16'h0000;
            debug_audio_last_data   <= 8'h00;
            debug_audio_last_mapctl <= 8'h00;
        end else begin
            if (audio_addr_write) begin
                debug_audio_addr_write_seen  <= 1'b1;
                debug_audio_addr_write_count <= debug_audio_addr_write_count + 32'd1;

                debug_audio_last_addr   <= cpu_addr;
                debug_audio_last_data   <= cpu_wdata;
                debug_audio_last_mapctl <= mapctl;
            end

            if (audio_overlay_write) begin
                debug_audio_overlay_write_seen  <= 1'b1;
                debug_audio_overlay_write_count <= debug_audio_overlay_write_count + 32'd1;
            end

            if (audio_hw_write) begin
                debug_audio_hw_write_seen  <= 1'b1;
                debug_audio_hw_write_count <= debug_audio_hw_write_count + 32'd1;
            end
        end
    end

    logic fcb0_read_hit;
    logic fcb1_read_hit;
    logic fcb0_read_hit_q;
    logic fcb1_read_hit_q;
    logic fcb0_read_start;
    logic fcb1_read_start;

    assign fcb0_read_hit   = cpu_cs && !cpu_we && (cpu_addr == 16'hFCB0);
    assign fcb1_read_hit   = cpu_cs && !cpu_we && (cpu_addr == 16'hFCB1);

    assign fcb0_read_start = fcb0_read_hit && !fcb0_read_hit_q;
    assign fcb1_read_start = fcb1_read_hit && !fcb1_read_hit_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            fcb0_read_hit_q <= 1'b0;
            fcb1_read_hit_q <= 1'b0;

            debug_fcb0_read_seen  <= 1'b0;
            debug_fcb1_read_seen  <= 1'b0;

            debug_fcb0_read_count <= 32'd0;
            debug_fcb1_read_count <= 32'd0;

            debug_fcb0_last_value <= 8'h00;
            debug_fcb1_last_value <= 3'b000;
            debug_fcb_last_addr   <= 16'h0000;
        end else begin
            fcb0_read_hit_q <= fcb0_read_hit;
            fcb1_read_hit_q <= fcb1_read_hit;

            if (fcb0_read_start) begin
                debug_fcb0_read_seen  <= 1'b1;
                debug_fcb0_read_count <= debug_fcb0_read_count + 32'd1;
                debug_fcb0_last_value <= lynx_fcb0_joystick;
                debug_fcb_last_addr   <= cpu_addr;
            end

            if (fcb1_read_start) begin
                debug_fcb1_read_seen  <= 1'b1;
                debug_fcb1_read_count <= debug_fcb1_read_count + 32'd1;
                debug_fcb1_last_value <= lynx_fcb1_switches;
                debug_fcb_last_addr   <= cpu_addr;
            end
        end
    end

    logic fc_range_hit;
    logic fd_range_hit;

    logic fc_trans_hit;
    logic fd_trans_hit;

    logic fc_trans_hit_q;
    logic fd_trans_hit_q;

    logic fc_trans_start;
    logic fd_trans_start;

    assign fc_range_hit = (cpu_addr >= 16'hFC00) && (cpu_addr <= 16'hFCFF);
    assign fd_range_hit = (cpu_addr >= 16'hFD00) && (cpu_addr <= 16'hFDFF);

    assign fc_trans_hit = cpu_cs && fc_range_hit;
    assign fd_trans_hit = cpu_cs && fd_range_hit;

    assign fc_trans_start = fc_trans_hit && !fc_trans_hit_q;
    assign fd_trans_start = fd_trans_hit && !fd_trans_hit_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            fc_trans_hit_q <= 1'b0;
            fd_trans_hit_q <= 1'b0;

            debug_fc_read_count  <= 32'd0;
            debug_fc_write_count <= 32'd0;
            debug_fd_read_count  <= 32'd0;
            debug_fd_write_count <= 32'd0;

            debug_last_fc_addr  <= 16'h0000;
            debug_last_fc_wdata <= 8'h00;
            debug_last_fc_rdata <= 8'h00;
            debug_last_fc_we    <= 1'b0;

            debug_last_fd_addr  <= 16'h0000;
            debug_last_fd_wdata <= 8'h00;
            debug_last_fd_rdata <= 8'h00;
            debug_last_fd_we    <= 1'b0;
        end else begin
            fc_trans_hit_q <= fc_trans_hit;
            fd_trans_hit_q <= fd_trans_hit;

            if (fc_trans_start) begin
                debug_last_fc_addr  <= cpu_addr;
                debug_last_fc_wdata <= cpu_wdata;
                debug_last_fc_rdata <= cpu_rdata;
                debug_last_fc_we    <= cpu_we;

                if (cpu_we) begin
                    debug_fc_write_count <= debug_fc_write_count + 32'd1;
                end else begin
                    debug_fc_read_count <= debug_fc_read_count + 32'd1;
                end
            end

            if (fd_trans_start) begin
                debug_last_fd_addr  <= cpu_addr;
                debug_last_fd_wdata <= cpu_wdata;
                debug_last_fd_rdata <= cpu_rdata;
                debug_last_fd_we    <= cpu_we;

                if (cpu_we) begin
                    debug_fd_write_count <= debug_fd_write_count + 32'd1;
                end else begin
                    debug_fd_read_count <= debug_fd_read_count + 32'd1;
                end
            end
        end
    end

    logic [7:0]  ram_cpu_dout;
    logic        ram_cpu_en;
    logic        ram_cpu_we;

    logic [15:0] video_addr;
    logic [7:0]  video_data;

    logic        suzy_ram_rd_en;
    logic [15:0] suzy_ram_rd_addr;
    logic [7:0]  suzy_ram_rd_data;
    logic        suzy_ram_rd_valid;

    logic        suzy_ram_we;
    logic [15:0] suzy_ram_addr;
    logic [7:0]  suzy_ram_wdata;

    assign ram_cpu_en = cpu_cs && sel_ram;
    assign ram_cpu_we = cpu_cs && cpu_we && sel_ram;

    lynx_ram_64k u_ram (
        .clk           (clk),
        .reset         (reset),

        .cpu_en        (ram_cpu_en),
        .cpu_addr      (cpu_addr),
        .cpu_din       (cpu_wdata),
        .cpu_dout      (ram_cpu_dout),
        .cpu_we        (ram_cpu_we),

        .suzy_rd_en    (suzy_ram_rd_en),
        .suzy_rd_addr  (suzy_ram_rd_addr),
        .suzy_rd_data  (suzy_ram_rd_data),
        .suzy_rd_valid (suzy_ram_rd_valid),

        .suzy_we       (suzy_ram_we),
        .suzy_addr     (suzy_ram_addr),
        .suzy_din      (suzy_ram_wdata),

        .video_addr    (video_addr),
        .video_dout    (video_data)
    );

    assign debug_video_addr = video_addr;
    assign debug_video_data = video_data;

    logic [8:0] bios_addr;
    logic [7:0] bios_rdata;

    assign bios_addr = cpu_addr[8:0];

    lynx_bios_rom u_bios_rom (
        .clk  (clk),
        .addr (bios_addr),
        .data (bios_rdata)
    );

    logic        cart_sysctl1_we;
    logic        cart_iodir_we;
    logic        cart_iodat_we;
    logic [7:0]  cart_reg_wdata;

    logic [7:0]  cart_sysctl1_rdata;
    logic [7:0]  cart_iodir_rdata;
    logic [7:0]  cart_iodat_rdata;

    logic        rcart0_rd;
    logic        rcart1_rd;
    logic        rcart0_rd_raw;
    logic        rcart1_rd_raw;
    logic [7:0]  rcart_rdata;

    logic [20:0] cart_addr;
    logic [7:0]  cart_rom_rdata;

    logic [7:0]  debug_cart_block;
    logic [11:0] debug_cart_offset;
    logic [20:0] debug_cart_addr;
    logic [7:0]  debug_last_cart_data;

    assign rcart0_rd_raw = cpu_cs && !cpu_we && sel_suzy && (cpu_addr == 16'hFCB2);
    assign rcart1_rd_raw = cpu_cs && !cpu_we && sel_suzy && (cpu_addr == 16'hFCB3);

    assign rcart0_rd = rcart0_rd_raw;
    assign rcart1_rd = rcart1_rd_raw;

    lynx_cart_if #(
        .BLOCK_OFFSET_BITS(9)
    ) u_cart_if (
        .clk                  (clk),
        .reset                (reset),

        .sysctl1_we           (cart_sysctl1_we),
        .iodir_we             (cart_iodir_we),
        .iodat_we             (cart_iodat_we),
        .reg_wdata            (cart_reg_wdata),

        .sysctl1_rdata        (cart_sysctl1_rdata),
        .iodir_rdata          (cart_iodir_rdata),
        .iodat_rdata          (cart_iodat_rdata),

        .rcart0_rd            (rcart0_rd),
        .rcart1_rd            (rcart1_rd),
        .rcart_rdata          (rcart_rdata),

        .cart_rom_addr        (cart_addr),
        .cart_rom_data        (cart_rom_rdata),

        .debug_cart_block     (debug_cart_block),
        .debug_cart_offset    (debug_cart_offset),
        .debug_cart_addr      (debug_cart_addr),
        .debug_last_cart_data (debug_last_cart_data)
    );

    lynx_cart_rom #(
        .CART_ROM_ADDR_BITS(17)
    ) u_cart_rom (
        .clk  (clk),
        .addr (cart_addr),
        .data (cart_rom_rdata)
    );

    logic unused_cart_debug;
    assign unused_cart_debug =
        debug_cart_block[0] ^
        debug_cart_offset[0] ^
        debug_cart_addr[0] ^
        debug_last_cart_data[0] ^
        rcart1_rd;

    logic [7:0]  suzy_cpu_rdata;

    logic        suzy_start_pulse;
    logic [24:0] suzy_scb_list_ptr;
    logic [2:0]  suzy_scene_select;
    logic [8:0]  suzy_start_obj_idx;

    logic        suzy_busy;
    logic        suzy_done_sticky;
    logic        suzy_collision_sticky;
    logic [7:0]  suzy_debug_last_write;

    logic [15:0] suzy_debug_vid_base_addr;
    logic [15:0] suzy_debug_scb_addr;
    logic [7:0]  suzy_debug_scb_byte;
    logic [4:0]  suzy_debug_scb_index;
    logic        suzy_debug_scb_read_seen;

    logic [7:0]  suzy_debug_sprctl0;
    logic [7:0]  suzy_debug_scbctl1;
    logic [7:0]  suzy_debug_sprcoll;
    logic [15:0] suzy_debug_next_scb_ptr;
    logic [15:0] suzy_debug_sprite_data_ptr;
    logic [15:0] suzy_debug_hpos;
    logic [15:0] suzy_debug_vpos;
    logic [15:0] suzy_debug_hsize;
    logic [15:0] suzy_debug_vsize;
    logic        suzy_debug_scb_decode_valid;

    assign suzy_cpu_sleep_request = suzy_busy;

    suzy u_suzy (
        .clk                    (clk),
        .reset                  (reset),

        .cpu_cs                 (cpu_cs && sel_suzy),
        .cpu_we                 (cpu_we),
        .cpu_addr               (cpu_addr),
        .cpu_wdata              (cpu_wdata),
        .cpu_rdata              (suzy_cpu_rdata),

        .lynx_fcb0_joystick     (lynx_fcb0_joystick),
        .lynx_fcb1_switches     (lynx_fcb1_switches),

        .suzy_ram_rd_en         (suzy_ram_rd_en),
        .suzy_ram_rd_addr       (suzy_ram_rd_addr),
        .suzy_ram_rd_data       (suzy_ram_rd_data),
        .suzy_ram_rd_valid      (suzy_ram_rd_valid),

        .suzy_ram_we            (suzy_ram_we),
        .suzy_ram_addr          (suzy_ram_addr),
        .suzy_ram_wdata         (suzy_ram_wdata),

        .start_pulse            (suzy_start_pulse),
        .scb_list_ptr           (suzy_scb_list_ptr),
        .scene_select           (suzy_scene_select),
        .start_obj_idx          (suzy_start_obj_idx),

        .suzy_busy              (suzy_busy),
        .suzy_done_sticky       (suzy_done_sticky),
        .collision_sticky       (suzy_collision_sticky),
        .debug_last_write       (suzy_debug_last_write),

        .debug_vid_base_addr    (suzy_debug_vid_base_addr),
        .debug_scb_addr         (suzy_debug_scb_addr),
        .debug_scb_byte         (suzy_debug_scb_byte),
        .debug_scb_index        (suzy_debug_scb_index),
        .debug_scb_read_seen    (suzy_debug_scb_read_seen),

        .debug_sprctl0          (suzy_debug_sprctl0),
        .debug_scbctl1          (suzy_debug_scbctl1),
        .debug_sprcoll          (suzy_debug_sprcoll),
        .debug_next_scb_ptr     (suzy_debug_next_scb_ptr),
        .debug_sprite_data_ptr  (suzy_debug_sprite_data_ptr),
        .debug_hpos             (suzy_debug_hpos),
        .debug_vpos             (suzy_debug_vpos),
        .debug_hsize            (suzy_debug_hsize),
        .debug_vsize            (suzy_debug_vsize),
        .debug_scb_decode_valid (suzy_debug_scb_decode_valid)
    );

    logic unused_suzy_outputs;
    assign unused_suzy_outputs =
        suzy_start_pulse ^
        suzy_scb_list_ptr[0] ^
        suzy_scene_select[0] ^
        suzy_start_obj_idx[0] ^
        suzy_busy ^
        suzy_done_sticky ^
        suzy_collision_sticky ^
        suzy_debug_last_write[0] ^
        suzy_ram_we ^
        suzy_ram_addr[0] ^
        suzy_ram_wdata[0] ^
        suzy_ram_rd_en ^
        suzy_ram_rd_addr[0] ^
        suzy_ram_rd_data[0] ^
        suzy_ram_rd_valid ^
        suzy_debug_vid_base_addr[0] ^
        suzy_debug_scb_addr[0] ^
        suzy_debug_scb_byte[0] ^
        suzy_debug_scb_index[0] ^
        suzy_debug_scb_read_seen ^
        suzy_debug_sprctl0[0] ^
        suzy_debug_scbctl1[0] ^
        suzy_debug_sprcoll[0] ^
        suzy_debug_next_scb_ptr[0] ^
        suzy_debug_sprite_data_ptr[0] ^
        suzy_debug_hpos[0] ^
        suzy_debug_vpos[0] ^
        suzy_debug_hsize[0] ^
        suzy_debug_vsize[0] ^
        suzy_debug_scb_decode_valid;

    logic [7:0] mikey_cpu_rdata;

    logic [7:0] mikey_debug_video_byte;
    logic [3:0] mikey_debug_pix_index;
    logic       mikey_debug_pix_valid;
    logic       mikey_debug_video_enable;
    logic       mikey_debug_fourbit_enable;
    logic       mikey_debug_color_enable;
    logic       mikey_debug_active_pipe;
    logic [3:0] mikey_debug_pal_r_nib;
    logic [3:0] mikey_debug_pal_g_nib;
    logic [3:0] mikey_debug_pal_b_nib;

    mikey u_mikey (
        .clk                (clk),
        .reset              (reset),

        .cpu_cs             (cpu_cs && sel_mikey),
        .cpu_we             (cpu_we),
        .cpu_addr           (cpu_addr),
        .cpu_wdata          (cpu_wdata),
        .cpu_rdata          (mikey_cpu_rdata),

        .hcount_tick        (mikey_hcount_tick),
        .vcount_tick        (mikey_vcount_tick),

        .irq_request        (mikey_irq_request),

        .cart_sysctl1_we    (cart_sysctl1_we),
        .cart_iodir_we      (cart_iodir_we),
        .cart_iodat_we      (cart_iodat_we),
        .cart_reg_wdata     (cart_reg_wdata),

        .cart_sysctl1_rdata (cart_sysctl1_rdata),
        .cart_iodir_rdata   (cart_iodir_rdata),
        .cart_iodat_rdata   (cart_iodat_rdata),

        .lynx_x             (lynx_x),
        .lynx_y             (lynx_y),
        .lynx_active        (lynx_active),

        .video_addr         (video_addr),
        .video_data         (video_data),

        .pix_index          (pix_index),
        .pix_valid          (pix_valid),

        .rgb_r              (rgb_r),
        .rgb_g              (rgb_g),
        .rgb_b              (rgb_b),
        .rgb_valid          (rgb_valid),
        .rgb_x              (rgb_x),
        .rgb_y              (rgb_y),
        .mikey_frame_tick   (mikey_frame_tick),

        .audio_pwm_l        (audio_pwm_l),
        .audio_pwm_r        (audio_pwm_r),

        .debug_dispctl      (debug_mikey_dispctl),
        .debug_disp_addr    (debug_mikey_disp_addr),

        .debug_video_byte     (mikey_debug_video_byte),
        .debug_pix_index      (mikey_debug_pix_index),
        .debug_pix_valid      (mikey_debug_pix_valid),
        .debug_video_enable   (mikey_debug_video_enable),
        .debug_fourbit_enable (mikey_debug_fourbit_enable),
        .debug_color_enable   (mikey_debug_color_enable),
        .debug_active_pipe    (mikey_debug_active_pipe),

        .debug_pal_r_nib      (mikey_debug_pal_r_nib),
        .debug_pal_g_nib      (mikey_debug_pal_g_nib),
        .debug_pal_b_nib      (mikey_debug_pal_b_nib)
    );

    logic unused_mikey_debug;
    assign unused_mikey_debug =
        mikey_debug_video_byte[0] ^
        mikey_debug_pix_index[0] ^
        mikey_debug_pix_valid ^
        mikey_debug_video_enable ^
        mikey_debug_fourbit_enable ^
        mikey_debug_color_enable ^
        mikey_debug_active_pipe ^
        mikey_debug_pal_r_nib[0] ^
        mikey_debug_pal_g_nib[0] ^
        mikey_debug_pal_b_nib[0];

    always_comb begin
        cpu_rdata = 8'h00;

        if (cpu_cs) begin
            if (rcart0_rd_raw || rcart1_rd_raw) begin
                cpu_rdata = rcart_rdata;
            end else if (sel_ram) begin
                cpu_rdata = ram_cpu_dout;
            end else if (sel_suzy) begin
                cpu_rdata = suzy_cpu_rdata;
            end else if (sel_mikey) begin
                cpu_rdata = mikey_cpu_rdata;
            end else if (sel_mapctl) begin
                cpu_rdata = mapctl;
            end else if (sel_bios || sel_vector) begin
                cpu_rdata = bios_rdata;
            end else begin
                cpu_rdata = 8'h00;
            end
        end
    end

endmodule