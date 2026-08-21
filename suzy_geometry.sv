`timescale 1ns/1ps

module suzy_geometry (
    input  logic [15:0] vid_base_addr,

    input  logic [15:0] hoff,
    input  logic [15:0] voff,

    input  logic [15:0] hpos,
    input  logic [15:0] vpos,

    input  logic [15:0] out_x,
    input  logic [15:0] out_y,

    input  logic        draw_left,
    input  logic        draw_up,

    output logic signed [10:0] world_x,
    output logic signed [10:0] world_y,

    output logic signed [10:0] screen_x,
    output logic signed [10:0] screen_y,

    output logic        visible,
    output logic [15:0] fb_addr,
    output logic        pixel_is_odd
);

    localparam logic [15:0] SCREEN_BYTES_PER_LINE = 16'd80;
    localparam logic [15:0] SCREEN_WIDTH_PIXELS   = 16'd160;
    localparam logic [15:0] SCREEN_HEIGHT_LINES   = 16'd102;

    logic [15:0] world_x_u16;
    logic [15:0] world_y_u16;

    logic [15:0] screen_x_u16;
    logic [15:0] screen_y_u16;

    always_comb begin
        if (draw_left) begin
            world_x_u16 = hpos - out_x;
        end else begin
            world_x_u16 = hpos + out_x;
        end

        if (draw_up) begin
            world_y_u16 = vpos - out_y;
        end else begin
            world_y_u16 = vpos + out_y;
        end

        screen_x_u16 = world_x_u16 - hoff;
        screen_y_u16 = world_y_u16 - voff;

        visible = (screen_x_u16 < SCREEN_WIDTH_PIXELS) &&
                  (screen_y_u16 < SCREEN_HEIGHT_LINES);

        pixel_is_odd = screen_x_u16[0];

        if (visible) begin
            fb_addr = vid_base_addr +
                      (screen_y_u16[7:0] * SCREEN_BYTES_PER_LINE) +
                      (screen_x_u16[7:0] >> 1);
        end else begin
            fb_addr = 16'h0000;
        end

        world_x  = $signed({1'b0, world_x_u16[9:0]});
        world_y  = $signed({1'b0, world_y_u16[9:0]});
        screen_x = $signed({1'b0, screen_x_u16[9:0]});
        screen_y = $signed({1'b0, screen_y_u16[9:0]});
    end

endmodule