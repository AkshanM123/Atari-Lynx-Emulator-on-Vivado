`timescale 1ns/1ps

module suzy (
    input  logic        clk,
    input  logic        reset,

    input  logic        cpu_cs,
    input  logic        cpu_we,
    input  logic [15:0] cpu_addr,
    input  logic [7:0]  cpu_wdata,
    output logic [7:0]  cpu_rdata,

    input  logic [7:0]  lynx_fcb0_joystick,
    input  logic [2:0]  lynx_fcb1_switches,

    output logic        suzy_ram_rd_en,
    output logic [15:0] suzy_ram_rd_addr,
    input  logic [7:0]  suzy_ram_rd_data,
    input  logic        suzy_ram_rd_valid,

    output logic        suzy_ram_we,
    output logic [15:0] suzy_ram_addr,
    output logic [7:0]  suzy_ram_wdata,

    output logic        start_pulse,
    output logic [24:0] scb_list_ptr,
    output logic [2:0]  scene_select,
    output logic [8:0]  start_obj_idx,

    output logic        suzy_busy,
    output logic        suzy_done_sticky,
    output logic        collision_sticky,
    output logic [7:0]  debug_last_write,

    output logic [15:0] debug_vid_base_addr,
    output logic [15:0] debug_scb_addr,
    output logic [7:0]  debug_scb_byte,
    output logic [4:0]  debug_scb_index,
    output logic        debug_scb_read_seen,

    output logic [7:0]  debug_sprctl0,
    output logic [7:0]  debug_scbctl1,
    output logic [7:0]  debug_sprcoll,
    output logic [15:0] debug_next_scb_ptr,
    output logic [15:0] debug_sprite_data_ptr,
    output logic [15:0] debug_hpos,
    output logic [15:0] debug_vpos,
    output logic [15:0] debug_hsize,
    output logic [15:0] debug_vsize,
    output logic        debug_scb_decode_valid
);

    logic [7:0] suzy_addr_low;
    logic       wr_en;
    logic       rd_en;

    assign suzy_addr_low = cpu_addr[7:0];
    assign wr_en = cpu_cs &&  cpu_we;
    assign rd_en = cpu_cs && !cpu_we;

    logic [7:0] reg_fc00;
    logic [7:0] reg_fc01;
    logic [7:0] reg_fc04;
    logic [7:0] reg_fc05;
    logic [7:0] reg_fc06;
    logic [7:0] reg_fc07;
    logic [7:0] reg_fc08;
    logic [7:0] reg_fc09;
    logic [7:0] reg_fc10;
    logic [7:0] reg_fc11;

    logic [7:0] reg_fc18;
    logic [7:0] reg_fc19;
    logic [7:0] reg_fc1a;
    logic [7:0] reg_fc1b;

    logic [7:0] reg_fc28;
    logic [7:0] reg_fc29;
    logic [7:0] reg_fc2a;
    logic [7:0] reg_fc2b;

    logic [7:0] reg_fc90;
    logic [7:0] reg_fc91;
    logic [7:0] reg_fc92;

    logic [15:0] hoff_reg;
    logic [15:0] voff_reg;

    logic [15:0] vid_base_addr;
    logic [15:0] coll_base_addr;
    logic [15:0] coll_off;
    logic [15:0] scb_next_addr;

    logic [15:0] spr_hsize_reg;
    logic [15:0] spr_vsize_reg;
    logic [15:0] hsizoff_reg;
    logic [15:0] vsizoff_reg;

    logic core_frame_done;
    logic core_collision_seen;

    logic suzy_force_stop_pulse;

    logic decoder_collision_seen;

    assign core_collision_seen = decoder_collision_seen;

    assign scb_list_ptr  = {9'd0, scb_next_addr};
    assign scene_select  = 3'd0;
    assign start_obj_idx = 9'd0;

    assign debug_vid_base_addr = vid_base_addr;

    typedef enum logic [3:0] {
        ENG_IDLE,
        ENG_SCB_REQ,
        ENG_SCB_WAIT,
        ENG_SCB_ADVANCE,
        ENG_SCB_DECODE,
        ENG_DECODER_START,
        ENG_DECODER_WAIT,
        ENG_CHAIN_NEXT,
        ENG_DONE
    } engine_state_t;

    engine_state_t engine_state;

    logic [15:0] scb_addr_latched;
    logic [4:0]  scb_index;
    logic [4:0]  scb_last_index;

    logic        scb_ram_rd_en;
    logic [15:0] scb_ram_rd_addr;

    logic [7:0] scb_sprctl0;
    logic [7:0] scb_scbctl1;
    logic [7:0] scb_sprcoll;

    logic [7:0] scb_next_lo;
    logic [7:0] scb_next_hi;

    logic [7:0] scb_data_lo;
    logic [7:0] scb_data_hi;

    logic [7:0] scb_hpos_lo;
    logic [7:0] scb_hpos_hi;

    logic [7:0] scb_vpos_lo;
    logic [7:0] scb_vpos_hi;

    logic [7:0] scb_hsize_lo;
    logic [7:0] scb_hsize_hi;

    logic [7:0] scb_vsize_lo;
    logic [7:0] scb_vsize_hi;

    logic [7:0] scb_stretch_lo;
    logic [7:0] scb_stretch_hi;

    logic [7:0] scb_tilt_lo;
    logic [7:0] scb_tilt_hi;

    logic [15:0] decoded_next_scb_ptr;
    logic [15:0] decoded_sprite_data_ptr;
    logic [15:0] decoded_hpos;
    logic [15:0] decoded_vpos;
    logic [15:0] decoded_hsize;
    logic [15:0] decoded_vsize;

    assign decoded_next_scb_ptr    = {scb_next_hi,  scb_next_lo};
    assign decoded_sprite_data_ptr = {scb_data_hi,  scb_data_lo};
    assign decoded_hpos            = {scb_hpos_hi,  scb_hpos_lo};
    assign decoded_vpos            = {scb_vpos_hi,  scb_vpos_lo};
    assign decoded_hsize           = {scb_hsize_hi, scb_hsize_lo};
    assign decoded_vsize           = {scb_vsize_hi, scb_vsize_lo};

    logic [7:0] scb_pal0;
    logic [7:0] scb_pal1;
    logic [7:0] scb_pal2;
    logic [7:0] scb_pal3;
    logic [7:0] scb_pal4;
    logic [7:0] scb_pal5;
    logic [7:0] scb_pal6;
    logic [7:0] scb_pal7;

    logic        debug_palette_loaded;
    logic        debug_palette_reused;
    logic [15:0] debug_palette_block_addr;
    logic [4:0]  debug_dynamic_scb_last_index;
    logic [3:0]  debug_palette_byte_count;
    logic [4:0]  debug_palette_start_index;

    function automatic logic scb_chain_end;
        input logic [15:0] ptr;
        begin
            scb_chain_end = (ptr == 16'h0000) || (ptr == 16'h0001);
        end
    endfunction

    function automatic logic [3:0] palette_byte_count_from_sprctl0;
        input logic [7:0] sprctl0;
        begin
            case (sprctl0[7:6])
                2'b00: palette_byte_count_from_sprctl0 = 4'd1;
                2'b01: palette_byte_count_from_sprctl0 = 4'd2;
                2'b10: palette_byte_count_from_sprctl0 = 4'd4;
                2'b11: palette_byte_count_from_sprctl0 = 4'd8;
                default: palette_byte_count_from_sprctl0 = 4'd8;
            endcase
        end
    endfunction

    function automatic logic [3:0] reload_extra_bytes_from_scbctl1;
        input logic [7:0] scbctl1;
        begin
            case (scbctl1[5:4])
                2'b00: reload_extra_bytes_from_scbctl1 = 4'd0;
                2'b01: reload_extra_bytes_from_scbctl1 = 4'd4;
                2'b10: reload_extra_bytes_from_scbctl1 = 4'd6;
                2'b11: reload_extra_bytes_from_scbctl1 = 4'd8;
                default: reload_extra_bytes_from_scbctl1 = 4'd0;
            endcase
        end
    endfunction

    function automatic logic [4:0] palette_start_index_from_scbctl1;
        input logic [7:0] scbctl1;
        begin
            palette_start_index_from_scbctl1 =
                5'd11 + {1'b0, reload_extra_bytes_from_scbctl1(scbctl1)};
        end
    endfunction

    function automatic logic [4:0] scb_last_index_from_controls;
        input logic [7:0] sprctl0;
        input logic [7:0] scbctl1;

        logic [4:0] pal_start;
        logic [3:0] pal_count;
        begin
            pal_start = palette_start_index_from_scbctl1(scbctl1);
            pal_count = palette_byte_count_from_sprctl0(sprctl0);

            if (scbctl1[3]) begin
                if (pal_start == 5'd0) begin
                    scb_last_index_from_controls = 5'd10;
                end else begin
                    scb_last_index_from_controls = pal_start - 5'd1;
                end
            end else begin
                scb_last_index_from_controls = pal_start + {1'b0, pal_count} - 5'd1;
            end
        end
    endfunction

    function automatic logic [3:0] palette_slot_for_index;
        input logic [4:0] idx;
        input logic [4:0] pal_start;
        begin
            if (idx >= pal_start) begin
                palette_slot_for_index = idx - pal_start;
            end else begin
                palette_slot_for_index = 4'hF;
            end
        end
    endfunction

    logic        decoder_start;
    logic        decoder_active;
    logic        decoder_busy;
    logic        decoder_done;

    logic        decoder_ram_rd_en;
    logic [15:0] decoder_ram_rd_addr;

    logic        decoder_ram_we;
    logic [15:0] decoder_ram_addr;
    logic [7:0]  decoder_ram_wdata;

    logic [15:0] decoder_debug_last_fb_addr;
    logic [7:0]  decoder_debug_last_fb_data;
    logic [15:0] decoder_debug_pixel_count;
    logic        decoder_debug_write_seen;

    assign suzy_ram_rd_en   = decoder_active ? decoder_ram_rd_en   : scb_ram_rd_en;
    assign suzy_ram_rd_addr = decoder_active ? decoder_ram_rd_addr : scb_ram_rd_addr;

    assign suzy_ram_we      = decoder_active ? decoder_ram_we      : 1'b0;
    assign suzy_ram_addr    = decoder_active ? decoder_ram_addr    : 16'h0000;
    assign suzy_ram_wdata   = decoder_active ? decoder_ram_wdata   : 8'h00;

    task automatic store_palette_byte;
        input logic [3:0] slot;
        input logic [7:0] data;
        begin
            case (slot)
                4'd0: scb_pal0 <= data;
                4'd1: scb_pal1 <= data;
                4'd2: scb_pal2 <= data;
                4'd3: scb_pal3 <= data;
                4'd4: scb_pal4 <= data;
                4'd5: scb_pal5 <= data;
                4'd6: scb_pal6 <= data;
                4'd7: scb_pal7 <= data;
                default: begin
                end
            endcase
        end
    endtask

    task automatic reset_reloadable_registers;
        begin
            scb_hsize_lo   <= 8'h00;
            scb_hsize_hi   <= 8'h01;
            scb_vsize_lo   <= 8'h00;
            scb_vsize_hi   <= 8'h01;

            scb_stretch_lo <= 8'h00;
            scb_stretch_hi <= 8'h00;
            scb_tilt_lo    <= 8'h00;
            scb_tilt_hi    <= 8'h00;
        end
    endtask

    task automatic preload_reloadable_registers_from_cpu_regs;
        begin
            if (spr_hsize_reg == 16'h0000) begin
                scb_hsize_lo <= 8'h00;
                scb_hsize_hi <= 8'h01;
            end else begin
                scb_hsize_lo <= spr_hsize_reg[7:0];
                scb_hsize_hi <= spr_hsize_reg[15:8];
            end

            if (spr_vsize_reg == 16'h0000) begin
                scb_vsize_lo <= 8'h00;
                scb_vsize_hi <= 8'h01;
            end else begin
                scb_vsize_lo <= spr_vsize_reg[7:0];
                scb_vsize_hi <= spr_vsize_reg[15:8];
            end

            scb_stretch_lo <= 8'h00;
            scb_stretch_hi <= 8'h00;

            scb_tilt_lo <= 8'h00;
            scb_tilt_hi <= 8'h00;
        end
    endtask

    task automatic clear_scb_working_registers;
        begin
            scb_sprctl0 <= 8'h00;
            scb_scbctl1 <= 8'h00;
            scb_sprcoll <= 8'h00;

            scb_next_lo <= 8'h00;
            scb_next_hi <= 8'h00;

            scb_data_lo <= 8'h00;
            scb_data_hi <= 8'h00;

            scb_hpos_lo <= 8'h00;
            scb_hpos_hi <= 8'h00;

            scb_vpos_lo <= 8'h00;
            scb_vpos_hi <= 8'h00;
        end
    endtask

    task automatic begin_scb_fetch;
        input logic [15:0] ptr;
        begin
            scb_addr_latched       <= ptr;
            debug_scb_addr         <= ptr;
            debug_scb_read_seen    <= 1'b0;
            debug_scb_decode_valid <= 1'b0;

            scb_index      <= 5'd0;
            scb_last_index <= 5'd10;

            decoder_active <= 1'b0;
            decoder_start  <= 1'b0;

            clear_scb_working_registers();

            engine_state <= ENG_SCB_REQ;
        end
    endtask

    task automatic store_scb_byte;
        input logic [4:0] idx;
        input logic [7:0] data;

        logic [4:0] pal_start;
        logic [3:0] pal_slot;
        begin
            pal_start = palette_start_index_from_scbctl1(scb_scbctl1);
            pal_slot  = palette_slot_for_index(idx, pal_start);

            case (idx)
                5'd0:  scb_sprctl0 <= data;
                5'd1:  scb_scbctl1 <= data;
                5'd2:  scb_sprcoll <= data;

                5'd3:  scb_next_lo <= data;
                5'd4:  scb_next_hi <= data;

                5'd5:  scb_data_lo <= data;
                5'd6:  scb_data_hi <= data;

                5'd7:  scb_hpos_lo <= data;
                5'd8:  scb_hpos_hi <= data;

                5'd9:  scb_vpos_lo <= data;
                5'd10: scb_vpos_hi <= data;

                default: begin
                    case (scb_scbctl1[5:4])
                        2'b00: begin
                        end

                        2'b01: begin
                            if (idx == 5'd11) scb_hsize_lo <= data;
                            if (idx == 5'd12) scb_hsize_hi <= data;
                            if (idx == 5'd13) scb_vsize_lo <= data;
                            if (idx == 5'd14) scb_vsize_hi <= data;
                        end

                        2'b10: begin
                            if (idx == 5'd11) scb_hsize_lo <= data;
                            if (idx == 5'd12) scb_hsize_hi <= data;
                            if (idx == 5'd13) scb_vsize_lo <= data;
                            if (idx == 5'd14) scb_vsize_hi <= data;
                            if (idx == 5'd15) scb_stretch_lo <= data;
                            if (idx == 5'd16) scb_stretch_hi <= data;
                        end

                        2'b11: begin
                            if (idx == 5'd11) scb_hsize_lo <= data;
                            if (idx == 5'd12) scb_hsize_hi <= data;
                            if (idx == 5'd13) scb_vsize_lo <= data;
                            if (idx == 5'd14) scb_vsize_hi <= data;
                            if (idx == 5'd15) scb_stretch_lo <= data;
                            if (idx == 5'd16) scb_stretch_hi <= data;
                            if (idx == 5'd17) scb_tilt_lo <= data;
                            if (idx == 5'd18) scb_tilt_hi <= data;
                        end

                        default: begin
                        end
                    endcase

                    if (!scb_scbctl1[3] && (idx >= pal_start)) begin
                        store_palette_byte(pal_slot, data);
                    end
                end
            endcase
        end
    endtask

    always_ff @(posedge clk) begin
        if (reset) begin
            engine_state <= ENG_IDLE;

            scb_ram_rd_en   <= 1'b0;
            scb_ram_rd_addr <= 16'h0000;

            core_frame_done <= 1'b0;

            scb_addr_latched <= 16'h0000;
            scb_index        <= 5'd0;
            scb_last_index   <= 5'd10;

            decoder_start  <= 1'b0;
            decoder_active <= 1'b0;

            debug_scb_addr      <= 16'h0000;
            debug_scb_byte      <= 8'h00;
            debug_scb_index     <= 5'd0;
            debug_scb_read_seen <= 1'b0;

            debug_sprctl0          <= 8'h00;
            debug_scbctl1          <= 8'h00;
            debug_sprcoll          <= 8'h00;
            debug_next_scb_ptr     <= 16'h0000;
            debug_sprite_data_ptr  <= 16'h0000;
            debug_hpos             <= 16'h0000;
            debug_vpos             <= 16'h0000;
            debug_hsize            <= 16'h0100;
            debug_vsize            <= 16'h0100;
            debug_scb_decode_valid <= 1'b0;

            clear_scb_working_registers();
            reset_reloadable_registers();

            scb_pal0 <= 8'h00;
            scb_pal1 <= 8'h00;
            scb_pal2 <= 8'h00;
            scb_pal3 <= 8'h00;
            scb_pal4 <= 8'h00;
            scb_pal5 <= 8'h00;
            scb_pal6 <= 8'h00;
            scb_pal7 <= 8'h00;

            debug_palette_loaded          <= 1'b0;
            debug_palette_reused          <= 1'b0;
            debug_palette_block_addr      <= 16'h0000;
            debug_dynamic_scb_last_index  <= 5'd10;
            debug_palette_byte_count      <= 4'd0;
            debug_palette_start_index     <= 5'd0;

        end else begin
            scb_ram_rd_en          <= 1'b0;
            core_frame_done        <= 1'b0;
            decoder_start          <= 1'b0;
            debug_palette_loaded   <= 1'b0;
            debug_palette_reused   <= 1'b0;
            debug_scb_decode_valid <= 1'b0;

            if (suzy_force_stop_pulse) begin
                engine_state   <= ENG_IDLE;
                scb_ram_rd_en  <= 1'b0;
                decoder_active <= 1'b0;
                decoder_start  <= 1'b0;

            end else begin
                case (engine_state)

                    ENG_IDLE: begin
                        scb_index      <= 5'd0;
                        decoder_active <= 1'b0;

                        if (start_pulse) begin
                            preload_reloadable_registers_from_cpu_regs();

                            if (scb_chain_end(scb_next_addr)) begin
                                engine_state <= ENG_DONE;
                            end else begin
                                begin_scb_fetch(scb_next_addr);
                            end
                        end
                    end

                    ENG_SCB_REQ: begin
                        scb_ram_rd_en   <= 1'b1;
                        scb_ram_rd_addr <= scb_addr_latched + {11'd0, scb_index};
                        engine_state    <= ENG_SCB_WAIT;
                    end

                    ENG_SCB_WAIT: begin
                        scb_ram_rd_en   <= 1'b1;
                        scb_ram_rd_addr <= scb_addr_latched + {11'd0, scb_index};

                        if (suzy_ram_rd_valid) begin
                            scb_ram_rd_en <= 1'b0;

                            store_scb_byte(scb_index, suzy_ram_rd_data);

                            debug_scb_byte      <= suzy_ram_rd_data;
                            debug_scb_index     <= scb_index;
                            debug_scb_read_seen <= 1'b1;

                            if (scb_index == 5'd1) begin
                                if (suzy_ram_rd_data[2]) begin
                                    scb_last_index <= 5'd4;
                                end else begin
                                    scb_last_index <= scb_last_index_from_controls(
                                        scb_sprctl0,
                                        suzy_ram_rd_data
                                    );
                                end
                            end

                            engine_state <= ENG_SCB_ADVANCE;
                        end
                    end

                    ENG_SCB_ADVANCE: begin
                        scb_ram_rd_en <= 1'b0;

                        if (scb_index == scb_last_index) begin
                            engine_state <= ENG_SCB_DECODE;
                        end else begin
                            scb_index    <= scb_index + 5'd1;
                            engine_state <= ENG_SCB_REQ;
                        end
                    end

                    ENG_SCB_DECODE: begin
                        debug_sprctl0          <= scb_sprctl0;
                        debug_scbctl1          <= scb_scbctl1;
                        debug_sprcoll          <= scb_sprcoll;
                        debug_next_scb_ptr     <= decoded_next_scb_ptr;
                        debug_sprite_data_ptr  <= decoded_sprite_data_ptr;
                        debug_hpos             <= decoded_hpos;
                        debug_vpos             <= decoded_vpos;
                        debug_hsize            <= decoded_hsize;
                        debug_vsize            <= decoded_vsize;

                        debug_palette_start_index    <= palette_start_index_from_scbctl1(scb_scbctl1);
                        debug_palette_byte_count     <= palette_byte_count_from_sprctl0(scb_sprctl0);
                        debug_dynamic_scb_last_index <= scb_last_index;
                        debug_palette_block_addr     <= scb_addr_latched +
                                                        {11'd0, palette_start_index_from_scbctl1(scb_scbctl1)};

                        if (scb_scbctl1[3]) begin
                            debug_palette_reused <= 1'b1;
                        end else begin
                            debug_palette_loaded <= 1'b1;
                        end

                        debug_scb_decode_valid <= 1'b1;

                        if (scb_scbctl1[2]) begin
                            engine_state <= ENG_CHAIN_NEXT;
                        end else begin
                            engine_state <= ENG_DECODER_START;
                        end
                    end

                    ENG_DECODER_START: begin
                        decoder_active <= 1'b1;
                        decoder_start  <= 1'b1;
                        engine_state   <= ENG_DECODER_WAIT;
                    end

                    ENG_DECODER_WAIT: begin
                        if (decoder_done) begin
                            decoder_active <= 1'b0;
                            engine_state   <= ENG_CHAIN_NEXT;
                        end
                    end

                    ENG_CHAIN_NEXT: begin
                        decoder_active <= 1'b0;

                        if (scb_chain_end(decoded_next_scb_ptr)) begin
                            engine_state <= ENG_DONE;
                        end else begin
                            begin_scb_fetch(decoded_next_scb_ptr);
                        end
                    end

                    ENG_DONE: begin
                        core_frame_done <= 1'b1;
                        engine_state    <= ENG_IDLE;
                    end

                    default: begin
                        engine_state <= ENG_IDLE;
                    end

                endcase
            end
        end
    end

    suzy_decoder u_suzy_decoder (
        .clk                (clk),
        .reset              (reset),

        .start              (decoder_start),
        .busy               (decoder_busy),
        .done               (decoder_done),

        .vid_base_addr      (vid_base_addr),
        .coll_base_addr     (coll_base_addr),
        .coll_off           (coll_off),
        .scb_addr           (scb_addr_latched),
        .everon_enable      (reg_fc91[2]),
        .hoff               (hoff_reg),
        .voff               (voff_reg),
        .sprite_data_ptr    (debug_sprite_data_ptr),
        .hpos               (debug_hpos),
        .vpos               (debug_vpos),
        .hsize              (debug_hsize),
        .vsize              (debug_vsize),
        .hsizoff            (hsizoff_reg),
        .vsizoff            (vsizoff_reg),
        .stretch            ({scb_stretch_hi, scb_stretch_lo}),
        .tilt               ({scb_tilt_hi, scb_tilt_lo}),
        .sprctl0            (debug_sprctl0),
        .scbctl1            (debug_scbctl1),
        .sprcoll            (debug_sprcoll),
        .sprsys             (reg_fc92),

        .pal0               (scb_pal0),
        .pal1               (scb_pal1),
        .pal2               (scb_pal2),
        .pal3               (scb_pal3),
        .pal4               (scb_pal4),
        .pal5               (scb_pal5),
        .pal6               (scb_pal6),
        .pal7               (scb_pal7),

        .ram_rd_en          (decoder_ram_rd_en),
        .ram_rd_addr        (decoder_ram_rd_addr),
        .ram_rd_data        (suzy_ram_rd_data),
        .ram_rd_valid       (suzy_ram_rd_valid),

        .ram_we             (decoder_ram_we),
        .ram_addr           (decoder_ram_addr),
        .ram_wdata          (decoder_ram_wdata),

        .collision_seen     (decoder_collision_seen),

        .debug_last_fb_addr (decoder_debug_last_fb_addr),
        .debug_last_fb_data (decoder_debug_last_fb_data),
        .debug_pixel_count  (decoder_debug_pixel_count),
        .debug_write_seen   (decoder_debug_write_seen)
    );

    suzy_regs u_suzy_regs (
        .clk                 (clk),
        .reset               (reset),

        .addr                (suzy_addr_low),

        .cpu_dout            (cpu_wdata),
        .cpu_din             (cpu_rdata),

        .wr_en               (wr_en),
        .rd_en               (rd_en),

        .lynx_fcb0_joystick  (lynx_fcb0_joystick),
        .lynx_fcb1_switches  (lynx_fcb1_switches),

        .start_pulse         (start_pulse),
        .force_stop_pulse    (suzy_force_stop_pulse),

        .reg_fc00            (reg_fc00),
        .reg_fc01            (reg_fc01),
        .reg_fc04            (reg_fc04),
        .reg_fc05            (reg_fc05),
        .reg_fc06            (reg_fc06),
        .reg_fc07            (reg_fc07),
        .reg_fc08            (reg_fc08),
        .reg_fc09            (reg_fc09),
        .reg_fc10            (reg_fc10),
        .reg_fc11            (reg_fc11),

        .reg_fc18            (reg_fc18),
        .reg_fc19            (reg_fc19),
        .reg_fc1a            (reg_fc1a),
        .reg_fc1b            (reg_fc1b),

        .reg_fc28            (reg_fc28),
        .reg_fc29            (reg_fc29),
        .reg_fc2a            (reg_fc2a),
        .reg_fc2b            (reg_fc2b),

        .reg_fc90            (reg_fc90),
        .reg_fc91            (reg_fc91),
        .reg_fc92            (reg_fc92),

        .hoff                (hoff_reg),
        .voff                (voff_reg),

        .vid_base_addr       (vid_base_addr),
        .coll_base_addr      (coll_base_addr),
        .coll_off            (coll_off),
        .scb_next_addr       (scb_next_addr),

        .spr_hsize           (spr_hsize_reg),
        .spr_vsize           (spr_vsize_reg),
        .hsizoff             (hsizoff_reg),
        .vsizoff             (vsizoff_reg),

        .core_frame_done     (core_frame_done),
        .core_collision_seen (core_collision_seen),

        .suzy_busy           (suzy_busy),
        .suzy_done_sticky    (suzy_done_sticky),
        .collision_sticky    (collision_sticky),

        .debug_last_write    (debug_last_write)
    );

    logic unused_refs;

    assign unused_refs =
        reg_fc00[0] ^
        reg_fc01[0] ^
        reg_fc04[0] ^
        reg_fc05[0] ^
        reg_fc06[0] ^
        reg_fc07[0] ^
        reg_fc08[0] ^
        reg_fc09[0] ^
        coll_base_addr[0] ^
        coll_off[0] ^
        reg_fc10[0] ^
        reg_fc11[0] ^
        reg_fc18[0] ^
        reg_fc19[0] ^
        reg_fc1a[0] ^
        reg_fc1b[0] ^
        reg_fc28[0] ^
        reg_fc29[0] ^
        reg_fc2a[0] ^
        reg_fc2b[0] ^
        reg_fc90[0] ^
        reg_fc91[0] ^
        reg_fc92[0] ^
        spr_hsize_reg[0] ^
        spr_vsize_reg[0] ^
        hsizoff_reg[0] ^
        vsizoff_reg[0] ^
        scb_stretch_lo[0] ^
        scb_stretch_hi[0] ^
        scb_tilt_lo[0] ^
        scb_tilt_hi[0] ^
        scb_pal0[0] ^
        scb_pal1[0] ^
        scb_pal2[0] ^
        scb_pal3[0] ^
        scb_pal4[0] ^
        scb_pal5[0] ^
        scb_pal6[0] ^
        scb_pal7[0] ^
        debug_palette_loaded ^
        debug_palette_reused ^
        debug_palette_block_addr[0] ^
        debug_dynamic_scb_last_index[0] ^
        debug_palette_byte_count[0] ^
        debug_palette_start_index[0] ^
        decoder_busy ^
        decoder_debug_last_fb_addr[0] ^
        decoder_debug_last_fb_data[0] ^
        decoder_debug_pixel_count[0] ^
        decoder_debug_write_seen;

endmodule