`timescale 1ns/1ps

module mikey (
    input  logic        clk,
    input  logic        reset,

    input  logic        cpu_cs,
    input  logic        cpu_we,
    input  logic [15:0] cpu_addr,
    input  logic  [7:0] cpu_wdata,
    output logic  [7:0] cpu_rdata,

    input  logic        hcount_tick,
    input  logic        vcount_tick,

    output logic        irq_request,

    output logic        cart_sysctl1_we,
    output logic        cart_iodir_we,
    output logic        cart_iodat_we,
    output logic  [7:0] cart_reg_wdata,

    input  logic  [7:0] cart_sysctl1_rdata,
    input  logic  [7:0] cart_iodir_rdata,
    input  logic  [7:0] cart_iodat_rdata,

    input  logic [7:0]  lynx_x,
    input  logic [6:0]  lynx_y,
    input  logic        lynx_active,

    output logic [15:0] video_addr,
    input  logic  [7:0] video_data,

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

    output logic  [7:0] debug_dispctl,
    output logic [15:0] debug_disp_addr,

    output logic  [7:0] debug_video_byte,
    output logic  [3:0] debug_pix_index,
    output logic        debug_pix_valid,
    output logic        debug_video_enable,
    output logic        debug_fourbit_enable,
    output logic        debug_color_enable,
    output logic        debug_active_pipe,

    output logic  [3:0] debug_pal_r_nib,
    output logic  [3:0] debug_pal_g_nib,
    output logic  [3:0] debug_pal_b_nib
);

    logic [7:0]  dispctl;
    logic [15:0] disp_addr;
    logic        display_visible;
    logic        display_vblank;
    logic [6:0]  display_line;
    logic        dispaddr_latch;
    logic        timer7_audio_link_tick;

    logic [7:0]  mikey_scan_x;
    logic [6:0]  mikey_scan_y;
    logic        mikey_scan_active;

    logic [7:0]  pix_x;
    logic [6:0]  pix_y;

    logic [3:0] green [0:15];
    logic [3:0] red   [0:15];
    logic [3:0] blue  [0:15];

    logic [7:0] regs_cpu_rdata;
    logic [7:0] audio_cpu_rdata;
    logic       audio_cs;
    logic signed [9:0] audio_sample_l;
    logic signed [9:0] audio_sample_r;

    localparam logic [7:0] REG_SYSCTL1 = 8'h87;
    localparam logic [7:0] REG_IODIR   = 8'h8A;
    localparam logic [7:0] REG_IODAT   = 8'h8B;

    logic [7:0] mikey_off;

    assign mikey_off = cpu_addr[7:0];
    assign audio_cs = cpu_cs && (((mikey_off >= 8'h20) && (mikey_off <= 8'h3F)) || (mikey_off == 8'h50));

    assign cart_sysctl1_we = cpu_cs && cpu_we && (mikey_off == REG_SYSCTL1);
    assign cart_iodir_we   = cpu_cs && cpu_we && (mikey_off == REG_IODIR);
    assign cart_iodat_we   = cpu_cs && cpu_we && (mikey_off == REG_IODAT);
    assign cart_reg_wdata  = cpu_wdata;

    mikey_regs u_regs (
        .clk          (clk),
        .reset        (reset),

        .cpu_cs       (cpu_cs),
        .cpu_we       (cpu_we),
        .cpu_addr     (cpu_addr),
        .cpu_wdata    (cpu_wdata),
        .cpu_rdata    (regs_cpu_rdata),

        .hcount_tick  (hcount_tick),
        .vcount_tick  (vcount_tick),

        .irq_request  (irq_request),
        .timer7_audio_link_tick (timer7_audio_link_tick),

        .dispctl      (dispctl),
        .disp_addr    (disp_addr),

        .display_visible (display_visible),
        .display_vblank  (display_vblank),
        .display_line    (display_line),
        .dispaddr_latch  (dispaddr_latch),
        .mikey_frame_tick (mikey_frame_tick),

        .mikey_scan_x      (mikey_scan_x),
        .mikey_scan_y      (mikey_scan_y),
        .mikey_scan_active (mikey_scan_active),

        .green        (green),
        .red          (red),
        .blue         (blue)
    );

    always_comb begin
        cpu_rdata = regs_cpu_rdata;

        if (cpu_cs && !cpu_we) begin
            if (audio_cs) begin
                cpu_rdata = audio_cpu_rdata;
            end else begin
                case (mikey_off)
                    REG_SYSCTL1: cpu_rdata = cart_sysctl1_rdata;
                    REG_IODIR:   cpu_rdata = cart_iodir_rdata;
                    REG_IODAT:   cpu_rdata = cart_iodat_rdata;
                    default:     cpu_rdata = regs_cpu_rdata;
                endcase
            end
        end
    end

    mikey_audio u_audio (
        .clk              (clk),
        .reset            (reset),

        .cpu_cs           (audio_cs),
        .cpu_we           (cpu_we),
        .cpu_addr         (mikey_off),
        .cpu_wdata        (cpu_wdata),
        .cpu_rdata        (audio_cpu_rdata),

        .timer7_link_tick (timer7_audio_link_tick),

        .pwm_l            (audio_pwm_l),
        .pwm_r            (audio_pwm_r),

        .sample_l         (audio_sample_l),
        .sample_r         (audio_sample_r)
    );

    mikey_video u_video (
        .clk                  (clk),
        .reset                (reset),

        .mikey_scan_x         (mikey_scan_x),
        .mikey_scan_y         (mikey_scan_y),
        .mikey_scan_active    (mikey_scan_active),

        .dispctl              (dispctl),
        .disp_addr            (disp_addr),
        .display_visible      (display_visible),
        .display_vblank       (display_vblank),
        .display_line         (display_line),

        .video_addr           (video_addr),
        .video_data           (video_data),

        .pix_index            (pix_index),
        .pix_valid            (pix_valid),
        .pix_x                (pix_x),
        .pix_y                (pix_y),

        .debug_video_byte     (debug_video_byte),
        .debug_pix_index      (debug_pix_index),
        .debug_pix_valid      (debug_pix_valid),
        .debug_video_enable   (debug_video_enable),
        .debug_fourbit_enable (debug_fourbit_enable),
        .debug_color_enable   (debug_color_enable),
        .debug_active_pipe    (debug_active_pipe)
    );

    lynx_palette #(
        .RGB_BITS(8)
    ) u_palette (
        .clk             (clk),
        .reset           (reset),

        .pix_index       (pix_index),
        .pix_valid       (pix_valid),

        .green           (green),
        .red             (red),
        .blue            (blue),

        .rgb_r           (rgb_r),
        .rgb_g           (rgb_g),
        .rgb_b           (rgb_b),
        .rgb_valid       (rgb_valid),

        .debug_pix_index (),
        .debug_pix_valid (),
        .debug_r_nib     (debug_pal_r_nib),
        .debug_g_nib     (debug_pal_g_nib),
        .debug_b_nib     (debug_pal_b_nib)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_x <= 8'd0;
            rgb_y <= 7'd0;
        end else begin
            rgb_x <= pix_x;
            rgb_y <= pix_y;
        end
    end

    assign debug_dispctl   = dispctl;
    assign debug_disp_addr = disp_addr;

    logic unused_display_debug;
    assign unused_display_debug =
        dispaddr_latch ^
        display_line[0] ^
        lynx_x[0] ^
        lynx_y[0] ^
        lynx_active ^
        audio_sample_l[0] ^
        audio_sample_r[0];

endmodule