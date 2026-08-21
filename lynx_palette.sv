`timescale 1ns/1ps

module lynx_palette #(
    parameter int RGB_BITS = 8
) (
    input  logic        clk,
    input  logic        reset,

    input  logic  [3:0] pix_index,
    input  logic        pix_valid,

    input  logic  [3:0] green [0:15],
    input  logic  [3:0] red   [0:15],
    input  logic  [3:0] blue  [0:15],

    output logic [RGB_BITS-1:0] rgb_r,
    output logic [RGB_BITS-1:0] rgb_g,
    output logic [RGB_BITS-1:0] rgb_b,
    output logic                rgb_valid,

    output logic  [3:0] debug_pix_index,
    output logic        debug_pix_valid,
    output logic  [3:0] debug_r_nib,
    output logic  [3:0] debug_g_nib,
    output logic  [3:0] debug_b_nib
);

    logic [3:0] r_nib;
    logic [3:0] g_nib;
    logic [3:0] b_nib;

    function automatic logic [RGB_BITS-1:0] expand_4_to_rgb_bits(
        input logic [3:0] nib
    );
        logic [7:0] expanded8;
        begin
            expanded8 = {nib, nib};

            if (RGB_BITS >= 8) begin
                expand_4_to_rgb_bits = expanded8[RGB_BITS-1:0];
            end else begin
                expand_4_to_rgb_bits = expanded8[7 -: RGB_BITS];
            end
        end
    endfunction

    always_comb begin
        r_nib = red[pix_index];
        g_nib = green[pix_index];
        b_nib = blue[pix_index];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            rgb_r     <= '0;
            rgb_g     <= '0;
            rgb_b     <= '0;
            rgb_valid <= 1'b0;
        end else begin
            if (pix_valid) begin
                rgb_r     <= expand_4_to_rgb_bits(r_nib);
                rgb_g     <= expand_4_to_rgb_bits(g_nib);
                rgb_b     <= expand_4_to_rgb_bits(b_nib);
                rgb_valid <= 1'b1;
            end else begin
                rgb_r     <= '0;
                rgb_g     <= '0;
                rgb_b     <= '0;
                rgb_valid <= 1'b0;
            end
        end
    end

    assign debug_pix_index = pix_index;
    assign debug_pix_valid = pix_valid;
    assign debug_r_nib     = r_nib;
    assign debug_g_nib     = g_nib;
    assign debug_b_nib     = b_nib;

endmodule