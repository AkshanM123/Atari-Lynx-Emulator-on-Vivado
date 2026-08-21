`timescale 1ns/1ps

module lynx_display_top (
    input  logic clk,
    input  logic reset,

    input  logic [7:0] lynx_fcb0_joystick,
    input  logic [2:0] lynx_fcb1_switches,

    output logic hs,
    output logic vs,
    output logic sync,
    output logic active_video,

    output logic [3:0] vga_r,
    output logic [3:0] vga_g,
    output logic [3:0] vga_b,

    output logic       SPKL,
    output logic       SPKR
);

    import lynx_pkg::*;

    logic [9:0] drawX;
    logic [9:0] drawY;
    logic       active_nblank;

    vga_controller u_vga (
        .pixel_clk      (clk),
        .reset          (reset),

        .hs             (hs),
        .vs             (vs),
        .active_nblank  (active_nblank),
        .sync           (sync),

        .drawX          (drawX),
        .drawY          (drawY)
    );

    assign active_video = active_nblank;

    logic [7:0] lynx_x;
    logic [6:0] lynx_y;
    logic       lynx_active;

    logic        cpu_idle;
    logic        dma_active;
    logic        cpu_sleep;

    logic        cpu_bus_request;
    logic        cpu_bus_rnw;
    logic [15:0] cpu_bus_addr;
    logic [7:0]  cpu_bus_datawrite;
    logic [7:0]  cpu_bus_dataread;
    logic        cpu_bus_done;

    logic        irqrequest_in;
    logic        irqclear_in;
    logic        irqdisabled;
    logic        irqpending;
    logic        irqfinish;

    logic        load_savestate;
    logic [15:0] custom_PCAddr;
    logic        custom_PCuse;

    logic        cpu_done;

    logic [15:0] dbg_PC;
    logic [7:0]  dbg_RegA;
    logic [7:0]  dbg_RegX;
    logic [7:0]  dbg_RegY;
    logic [7:0]  dbg_RegS;
    logic [7:0]  dbg_RegP;
    logic        dbg_FlagNeg;
    logic        dbg_FlagOvf;
    logic        dbg_FlagBrk;
    logic        dbg_FlagDez;
    logic        dbg_FlagIrq;
    logic        dbg_FlagZer;
    logic        dbg_FlagCar;
    logic        dbg_sleep;
    logic        dbg_irqrequest;
    logic [7:0]  dbg_opcodebyte_last;

    logic        suzy_cpu_sleep_request;

    assign dma_active = 1'b0;
    assign cpu_sleep  = 1'b0;

    assign irqclear_in = 1'b0;

    assign load_savestate = 1'b0;
    assign custom_PCAddr  = 16'h0000;
    assign custom_PCuse   = 1'b0;

    cpu_wrapper u_cpu (
        .clk                 (clk),
        .ce                  (1'b1),
        .reset               (reset),

        .cpu_idle            (cpu_idle),
        .dma_active          (dma_active),
        .cpu_sleep           (cpu_sleep),

        .bus_request         (cpu_bus_request),
        .bus_rnw             (cpu_bus_rnw),
        .bus_addr            (cpu_bus_addr),
        .bus_datawrite       (cpu_bus_datawrite),
        .bus_dataread        (cpu_bus_dataread),
        .bus_done            (cpu_bus_done),

        .irqrequest_in       (irqrequest_in),
        .irqclear_in         (irqclear_in),
        .irqdisabled         (irqdisabled),
        .irqpending          (irqpending),
        .irqfinish           (irqfinish),

        .load_savestate      (load_savestate),
        .custom_PCAddr       (custom_PCAddr),
        .custom_PCuse        (custom_PCuse),

        .cpu_done            (cpu_done),

        .dbg_PC              (dbg_PC),
        .dbg_RegA            (dbg_RegA),
        .dbg_RegX            (dbg_RegX),
        .dbg_RegY            (dbg_RegY),
        .dbg_RegS            (dbg_RegS),
        .dbg_RegP            (dbg_RegP),
        .dbg_FlagNeg         (dbg_FlagNeg),
        .dbg_FlagOvf         (dbg_FlagOvf),
        .dbg_FlagBrk         (dbg_FlagBrk),
        .dbg_FlagDez         (dbg_FlagDez),
        .dbg_FlagIrq         (dbg_FlagIrq),
        .dbg_FlagZer         (dbg_FlagZer),
        .dbg_FlagCar         (dbg_FlagCar),
        .dbg_sleep           (dbg_sleep),
        .dbg_irqrequest      (dbg_irqrequest),
        .dbg_opcodebyte_last (dbg_opcodebyte_last)
    );

    logic        core_cpu_cs;
    logic        core_cpu_we;
    logic [15:0] core_cpu_addr;
    logic [7:0]  core_cpu_wdata;
    logic [7:0]  core_cpu_rdata;

    lynx_cpu_bus_bridge u_cpu_bridge (
        .clk                (clk),
        .reset              (reset),

        .dma_stall          (suzy_cpu_sleep_request),

        .cpu_bus_request    (cpu_bus_request),
        .cpu_bus_rnw        (cpu_bus_rnw),
        .cpu_bus_addr       (cpu_bus_addr),
        .cpu_bus_datawrite  (cpu_bus_datawrite),
        .cpu_bus_dataread   (cpu_bus_dataread),
        .cpu_bus_done       (cpu_bus_done),

        .core_cpu_cs        (core_cpu_cs),
        .core_cpu_we        (core_cpu_we),
        .core_cpu_addr      (core_cpu_addr),
        .core_cpu_wdata     (core_cpu_wdata),
        .core_cpu_rdata     (core_cpu_rdata)
    );

    logic [3:0] pix_index;
    logic       pix_valid;

    logic [7:0] lynx_r;
    logic [7:0] lynx_g;
    logic [7:0] lynx_b;
    logic       lynx_rgb_valid;
    logic [7:0] lynx_rgb_x;
    logic [6:0] lynx_rgb_y;

    logic       audio_pwm_l;
    logic       audio_pwm_r;

    logic       mikey_irq_request;
    logic       mikey_frame_tick;

    logic [7:0]  debug_mapctl;
    logic [15:0] debug_video_addr;
    logic [7:0]  debug_video_data;
    logic [7:0]  debug_mikey_dispctl;
    logic [15:0] debug_mikey_disp_addr;

    logic debug_sel_ram;
    logic debug_sel_suzy;
    logic debug_sel_mikey;
    logic debug_sel_rom;
    logic debug_sel_mapctl;
    logic debug_sel_vector;

    always_comb begin
        lynx_active = active_nblank &&
                      (drawX < 10'd640) &&
                      (drawY < 10'd408);

        lynx_x = drawX[9:2];
        lynx_y = drawY[8:2];
    end

    logic mikey_hcount_tick;
    logic mikey_vcount_tick;

    always_ff @(posedge clk) begin
        if (reset) begin
            mikey_hcount_tick <= 1'b0;
            mikey_vcount_tick <= 1'b0;
        end else begin
            mikey_hcount_tick <= active_nblank &&
                                 (drawX < 10'd640) &&
                                 (drawY < 10'd408) &&
                                 (drawX[1:0] == 2'b00) &&
                                 (drawY[1:0] == 2'b00);

            mikey_vcount_tick <= active_nblank &&
                                 (drawX == 10'd0) &&
                                 (drawY < 10'd408) &&
                                 (drawY[1:0] == 2'b00);
        end
    end

    lynx_core_top u_lynx (
        .clk                   (clk),
        .reset                 (reset),

        .cpu_cs                (core_cpu_cs),
        .cpu_we                (core_cpu_we),
        .cpu_addr              (core_cpu_addr),
        .cpu_wdata             (core_cpu_wdata),
        .cpu_rdata             (core_cpu_rdata),

        .lynx_fcb0_joystick    (lynx_fcb0_joystick),
        .lynx_fcb1_switches    (lynx_fcb1_switches),

        .mikey_hcount_tick     (mikey_hcount_tick),
        .mikey_vcount_tick     (mikey_vcount_tick),

        .lynx_x                (lynx_x),
        .lynx_y                (lynx_y),
        .lynx_active           (lynx_active),

        .pix_index             (pix_index),
        .pix_valid             (pix_valid),

        .rgb_r                 (lynx_r),
        .rgb_g                 (lynx_g),
        .rgb_b                 (lynx_b),
        .rgb_valid             (lynx_rgb_valid),
        .rgb_x                 (lynx_rgb_x),
        .rgb_y                 (lynx_rgb_y),
        .mikey_frame_tick      (mikey_frame_tick),

        .audio_pwm_l           (audio_pwm_l),
        .audio_pwm_r           (audio_pwm_r),

        .mikey_irq_request     (mikey_irq_request),
        .suzy_cpu_sleep_request(suzy_cpu_sleep_request),

        .debug_mapctl          (debug_mapctl),
        .debug_video_addr      (debug_video_addr),
        .debug_video_data      (debug_video_data),
        .debug_mikey_dispctl   (debug_mikey_dispctl),
        .debug_mikey_disp_addr (debug_mikey_disp_addr),

        .debug_sel_ram         (debug_sel_ram),
        .debug_sel_suzy        (debug_sel_suzy),
        .debug_sel_mikey       (debug_sel_mikey),
        .debug_sel_rom         (debug_sel_rom),
        .debug_sel_mapctl      (debug_sel_mapctl),
        .debug_sel_vector      (debug_sel_vector)
    );

    assign irqrequest_in = mikey_irq_request;

    assign SPKL = audio_pwm_l;
    assign SPKR = audio_pwm_r;

    localparam int LCD_FB_PIXELS = LYNX_WIDTH * LYNX_HEIGHT;

    logic [11:0] lcd_fb0 [0:LCD_FB_PIXELS-1];
    logic [11:0] lcd_fb1 [0:LCD_FB_PIXELS-1];

    logic        lcd_write_bank;
    logic        lcd_display_bank;

    logic [7:0]  vga_lcd_x;
    logic [6:0]  vga_lcd_y;
    logic        vga_lcd_active;

    logic [13:0] lcd_wr_addr;
    logic [13:0] lcd_rd_addr;
    logic [11:0] vga_rgb_q;

    assign vga_lcd_active = active_nblank &&
                            (drawX < 10'd640) &&
                            (drawY < 10'd408);

    assign vga_lcd_x = drawX[9:2];
    assign vga_lcd_y = drawY[8:2];

    always_comb begin
        lcd_wr_addr = ({7'd0, lynx_rgb_y} << 7) +
                      ({7'd0, lynx_rgb_y} << 5) +
                      {6'd0, lynx_rgb_x};

        lcd_rd_addr = ({7'd0, vga_lcd_y} << 7) +
                      ({7'd0, vga_lcd_y} << 5) +
                      {6'd0, vga_lcd_x};
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            lcd_write_bank   <= 1'b0;
            lcd_display_bank <= 1'b1;
            vga_rgb_q        <= 12'h000;
        end else begin
            if (mikey_frame_tick) begin
                lcd_display_bank <= lcd_write_bank;
                lcd_write_bank   <= ~lcd_write_bank;
            end

            if (lynx_rgb_valid &&
                (lynx_rgb_x < 8'd160) &&
                (lynx_rgb_y < 7'd102)) begin
                if (lcd_write_bank) begin
                    lcd_fb1[lcd_wr_addr] <= {lynx_r[7:4], lynx_g[7:4], lynx_b[7:4]};
                end else begin
                    lcd_fb0[lcd_wr_addr] <= {lynx_r[7:4], lynx_g[7:4], lynx_b[7:4]};
                end
            end

            if (vga_lcd_active) begin
                if (lcd_display_bank) begin
                    vga_rgb_q <= lcd_fb1[lcd_rd_addr];
                end else begin
                    vga_rgb_q <= lcd_fb0[lcd_rd_addr];
                end
            end else begin
                vga_rgb_q <= 12'h000;
            end
        end
    end

    always_comb begin
        if (active_nblank) begin
            vga_r = vga_rgb_q[11:8];
            vga_g = vga_rgb_q[7:4];
            vga_b = vga_rgb_q[3:0];
        end else begin
            vga_r = 4'h0;
            vga_g = 4'h0;
            vga_b = 4'h0;
        end
    end

    logic unused_top_debug;
    assign unused_top_debug =
        cpu_idle ^
        cpu_done ^
        irqdisabled ^
        irqpending ^
        irqfinish ^
        dbg_PC[0] ^
        dbg_RegA[0] ^
        dbg_RegX[0] ^
        dbg_RegY[0] ^
        dbg_RegS[0] ^
        dbg_RegP[0] ^
        dbg_FlagNeg ^
        dbg_FlagOvf ^
        dbg_FlagBrk ^
        dbg_FlagDez ^
        dbg_FlagIrq ^
        dbg_FlagZer ^
        dbg_FlagCar ^
        dbg_sleep ^
        dbg_irqrequest ^
        dbg_opcodebyte_last[0] ^
        pix_index[0] ^
        pix_valid ^
        debug_mapctl[0] ^
        debug_video_addr[0] ^
        debug_video_data[0] ^
        debug_mikey_dispctl[0] ^
        debug_mikey_disp_addr[0] ^
        debug_sel_ram ^
        debug_sel_suzy ^
        debug_sel_mikey ^
        debug_sel_rom ^
        debug_sel_mapctl ^
        debug_sel_vector;

endmodule