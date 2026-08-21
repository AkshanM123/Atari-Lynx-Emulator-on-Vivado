// Board-level FPGA wrapper.
// Takes the FPGA board Clk and reset_rtl_0.
// Uses clk_wiz_0 IP to generate a 25 MHz clock for the Lynx/video path
// and a 125 MHz clock for HDMI serialization.
// Uses mb_block_wrapper to receive USB keyboard data into
// gpio_usb_keycode_0 and gpio_usb_keycode_1.
// Shows the keycodes on the two FPGA hex displays.
// Converts USB keycodes into Lynx joystick/switch signals:
// lynx_fcb0_joystick and lynx_fcb1_switches.
// Runs lynx_display_top, which uses the Lynx inputs and produces
// video signals red, green, blue, hs, vs, and active_video.
// Uses hdmi_tx_0 to convert those video signals into HDMI TMDS outputs:
// hdmi_tmds_clk_p/n and hdmi_tmds_data_p/n.
// Passes Lynx audio output to SPKL and SPKR.
`timescale 1ns/1ps
module mb_usb_hdmi_top(
    input  logic Clk,
    input  logic reset_rtl_0,

    input  logic [0:0] gpio_usb_int_tri_i,
    output logic       gpio_usb_rst_tri_o,
    input  logic       usb_spi_miso,
    output logic       usb_spi_mosi,
    output logic       usb_spi_sclk,
    output logic       usb_spi_ss,

    input  logic uart_rtl_0_rxd,
    output logic uart_rtl_0_txd,

    output logic       hdmi_tmds_clk_n,
    output logic       hdmi_tmds_clk_p,
    output logic [2:0] hdmi_tmds_data_n,
    output logic [2:0] hdmi_tmds_data_p,

    output logic       SPKL,
    output logic       SPKR,

    output logic [7:0] hex_segA,
    output logic [3:0] hex_gridA,
    output logic [7:0] hex_segB,
    output logic [3:0] hex_gridB
);

    logic clk_ibuf;
    logic clk_100MHz_buf;

    IBUF u_clk_ibuf (
        .I (Clk),
        .O (clk_ibuf)
    );

    BUFG u_clk_bufg (
        .I (clk_ibuf),
        .O (clk_100MHz_buf)
    );

    logic clk_25MHz;
    logic clk_125MHz;
    logic locked;
    logic reset_ah;

    assign reset_ah = reset_rtl_0 | ~locked;

    clk_wiz_0 clk_wiz (
        .clk_out1 (clk_25MHz),
        .clk_out2 (clk_125MHz),
        .reset    (reset_rtl_0),
        .locked   (locked),
        .clk_in1  (clk_100MHz_buf)
    );

    logic [31:0] gpio_usb_keycode_0;
    logic [31:0] gpio_usb_keycode_1;
    logic [0:0]  gpio_usb_rst_from_mb;
    logic [0:0]  usb_spi_ss_from_mb;

    mb_block_wrapper u_mb_block (
        .clk_100Mhz                (clk_100MHz_buf),

        .gpio_usb_int_tri_i        (gpio_usb_int_tri_i),
        .gpio_usb_keycode_0_tri_o  (gpio_usb_keycode_0),
        .gpio_usb_keycode_1_tri_o  (gpio_usb_keycode_1),
        .gpio_usb_rst_tri_o        (gpio_usb_rst_from_mb),

        .reset_rtl_0               (~reset_ah),

        .uart_rtl_0_rxd            (uart_rtl_0_rxd),
        .uart_rtl_0_txd            (uart_rtl_0_txd),

        .usb_spi_miso              (usb_spi_miso),
        .usb_spi_mosi              (usb_spi_mosi),
        .usb_spi_sclk              (usb_spi_sclk),
        .usb_spi_ss                (usb_spi_ss_from_mb)
    );

    assign gpio_usb_rst_tri_o = gpio_usb_rst_from_mb[0];
    assign usb_spi_ss         = usb_spi_ss_from_mb[0];

    logic [3:0] hexA_in [4];
    logic [3:0] hexB_in [4];

    always_comb begin
        hexA_in[0] = gpio_usb_keycode_0[15:12];
        hexA_in[1] = gpio_usb_keycode_0[11:8];
        hexA_in[2] = gpio_usb_keycode_0[7:4];
        hexA_in[3] = gpio_usb_keycode_0[3:0];

        hexB_in[0] = gpio_usb_keycode_1[15:12];
        hexB_in[1] = gpio_usb_keycode_1[11:8];
        hexB_in[2] = gpio_usb_keycode_1[7:4];
        hexB_in[3] = gpio_usb_keycode_1[3:0];
    end

    hex_driver HexA (
        .clk      (clk_25MHz),
        .reset    (reset_ah),
        .in       (hexA_in),
        .hex_seg  (hex_segA),
        .hex_grid (hex_gridA)
    );

    hex_driver HexB (
        .clk      (clk_25MHz),
        .reset    (reset_ah),
        .in       (hexB_in),
        .hex_seg  (hex_segB),
        .hex_grid (hex_gridB)
    );

    logic [7:0] lynx_fcb0_joystick;
    logic [2:0] lynx_fcb1_switches;

    keycode_to_lynx u_keycode_to_lynx (
        .gpio_usb_keycode_0 (gpio_usb_keycode_0),
        .gpio_usb_keycode_1 (gpio_usb_keycode_1),

        .lynx_fcb0_joystick (lynx_fcb0_joystick),
        .lynx_fcb1_switches (lynx_fcb1_switches)
    );

    logic       hs;
    logic       vs;
    logic       sync_unused;
    logic       active_video;

    logic [3:0] red;
    logic [3:0] green;
    logic [3:0] blue;

    lynx_display_top u_lynx_display (
        .clk                 (clk_25MHz),
        .reset               (reset_ah),

        .lynx_fcb0_joystick  (lynx_fcb0_joystick),
        .lynx_fcb1_switches  (lynx_fcb1_switches),

        .hs                  (hs),
        .vs                  (vs),
        .sync                (sync_unused),
        .active_video        (active_video),

        .vga_r               (red),
        .vga_g               (green),
        .vga_b               (blue),

        .SPKL                (SPKL),
        .SPKR                (SPKR)
    );

    hdmi_tx_0 vga_to_hdmi (
        .pix_clk        (clk_25MHz),
        .pix_clkx5      (clk_125MHz),
        .pix_clk_locked (locked),
        .rst            (reset_ah),

        .red            (red),
        .green          (green),
        .blue           (blue),

        .hsync          (hs),
        .vsync          (vs),
        .vde            (active_video),

        .aux0_din       (4'b0000),
        .aux1_din       (4'b0000),
        .aux2_din       (4'b0000),
        .ade            (1'b0),

        .TMDS_CLK_P     (hdmi_tmds_clk_p),
        .TMDS_CLK_N     (hdmi_tmds_clk_n),
        .TMDS_DATA_P    (hdmi_tmds_data_p),
        .TMDS_DATA_N    (hdmi_tmds_data_n)
    );

endmodule