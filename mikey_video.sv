`timescale 1ns/1ps

module mikey_video (
    input  logic        clk,
    input  logic        reset,

    input  logic [7:0]  mikey_scan_x,
    input  logic [6:0]  mikey_scan_y,
    input  logic        mikey_scan_active,

    input  logic  [7:0] dispctl,
    input  logic [15:0] disp_addr,
    input  logic        display_visible,
    input  logic        display_vblank,
    input  logic  [6:0] display_line,

    output logic [15:0] video_addr,
    input  logic  [7:0] video_data,

    output logic  [3:0] pix_index,
    output logic        pix_valid,
    output logic  [7:0] pix_x,
    output logic  [6:0] pix_y,

    output logic  [7:0] debug_video_byte,
    output logic  [3:0] debug_pix_index,
    output logic        debug_pix_valid,
    output logic        debug_video_enable,
    output logic        debug_fourbit_enable,
    output logic        debug_color_enable,
    output logic        debug_active_pipe
);

    import lynx_pkg::*;

    logic video_dma_enable_now;
    logic flip_now;
    logic fourbit_now;
    logic color_now;

    assign video_dma_enable_now = dispctl[DISPCTL_VIDEO_DMA_BIT];
    assign flip_now             = dispctl[DISPCTL_FLIP_BIT];
    assign fourbit_now          = dispctl[DISPCTL_FOURBIT_BIT];
    assign color_now            = dispctl[DISPCTL_COLOR_BIT];

    logic [15:0] aligned_disp_addr;
    assign aligned_disp_addr = {disp_addr[15:2], 2'b00};

    function automatic logic [15:0] line_base_4bpp(input logic [6:0] y);
        begin
            line_base_4bpp = ({9'd0, y} << 6) + ({9'd0, y} << 4);
        end
    endfunction

    function automatic logic [15:0] line_base_2bpp(input logic [6:0] y);
        begin
            line_base_2bpp = ({9'd0, y} << 5) + ({9'd0, y} << 3);
        end
    endfunction

    function automatic logic [15:0] byte_offset_for_pixel(
        input logic       fourbit,
        input logic [7:0] x,
        input logic [6:0] y
    );
        begin
            if (fourbit) begin
                byte_offset_for_pixel = line_base_4bpp(y) + {9'd0, x[7:1]};
            end else begin
                byte_offset_for_pixel = line_base_2bpp(y) + {10'd0, x[7:2]};
            end
        end
    endfunction

    function automatic logic [15:0] byte_addr_for_pixel(
        input logic [15:0] base_addr,
        input logic        flip,
        input logic        fourbit,
        input logic [7:0]  x,
        input logic [6:0]  y
    );
        logic [15:0] byte_offset;
        begin
            byte_offset = byte_offset_for_pixel(fourbit, x, y);

            if (flip) begin
                byte_addr_for_pixel = base_addr - byte_offset;
            end else begin
                byte_addr_for_pixel = base_addr + byte_offset;
            end
        end
    endfunction

    function automatic logic [3:0] pen_from_byte(
        input logic [7:0] data_byte,
        input logic       fourbit,
        input logic       flip,
        input logic       x_lsb,
        input logic [1:0] x_pair
    );
        begin
            if (fourbit) begin
                if (!flip) begin
                    if (x_lsb == 1'b0) begin
                        pen_from_byte = data_byte[7:4];
                    end else begin
                        pen_from_byte = data_byte[3:0];
                    end
                end else begin
                    if (x_lsb == 1'b0) begin
                        pen_from_byte = data_byte[3:0];
                    end else begin
                        pen_from_byte = data_byte[7:4];
                    end
                end
            end else begin
                unique case (x_pair)
                    2'd0: pen_from_byte = {2'b00, data_byte[7:6]};
                    2'd1: pen_from_byte = {2'b00, data_byte[5:4]};
                    2'd2: pen_from_byte = {2'b00, data_byte[3:2]};
                    2'd3: pen_from_byte = {2'b00, data_byte[1:0]};
                    default: pen_from_byte = 4'h0;
                endcase
            end
        end
    endfunction

    logic       req_d0_valid;
    logic [7:0] req_d0_x;
    logic [6:0] req_d0_y;
    logic       req_d0_fourbit;
    logic       req_d0_flip;
    logic       req_d0_x_lsb;
    logic [1:0] req_d0_x_pair;
    logic       req_d0_dma_enable;

    logic       req_d1_valid;
    logic [7:0] req_d1_x;
    logic [6:0] req_d1_y;
    logic       req_d1_fourbit;
    logic       req_d1_flip;
    logic       req_d1_x_lsb;
    logic [1:0] req_d1_x_pair;
    logic       req_d1_dma_enable;

    logic       req_d2_valid;
    logic [7:0] req_d2_x;
    logic [6:0] req_d2_y;
    logic       req_d2_fourbit;
    logic       req_d2_flip;
    logic       req_d2_x_lsb;
    logic [1:0] req_d2_x_pair;
    logic       req_d2_dma_enable;

    logic       issue_pixel;
    logic [15:0] issue_addr;

    always_comb begin
        issue_pixel = mikey_scan_active;

        issue_addr = byte_addr_for_pixel(aligned_disp_addr,
                                         flip_now,
                                         fourbit_now,
                                         mikey_scan_x,
                                         mikey_scan_y);
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            video_addr <= 16'h0000;

            req_d0_valid      <= 1'b0;
            req_d0_x          <= 8'd0;
            req_d0_y          <= 7'd0;
            req_d0_fourbit    <= 1'b0;
            req_d0_flip       <= 1'b0;
            req_d0_x_lsb      <= 1'b0;
            req_d0_x_pair     <= 2'd0;
            req_d0_dma_enable <= 1'b0;

            req_d1_valid      <= 1'b0;
            req_d1_x          <= 8'd0;
            req_d1_y          <= 7'd0;
            req_d1_fourbit    <= 1'b0;
            req_d1_flip       <= 1'b0;
            req_d1_x_lsb      <= 1'b0;
            req_d1_x_pair     <= 2'd0;
            req_d1_dma_enable <= 1'b0;

            req_d2_valid      <= 1'b0;
            req_d2_x          <= 8'd0;
            req_d2_y          <= 7'd0;
            req_d2_fourbit    <= 1'b0;
            req_d2_flip       <= 1'b0;
            req_d2_x_lsb      <= 1'b0;
            req_d2_x_pair     <= 2'd0;
            req_d2_dma_enable <= 1'b0;

            pix_index <= 4'h0;
            pix_valid <= 1'b0;
            pix_x     <= 8'd0;
            pix_y     <= 7'd0;
        end else begin
            if (issue_pixel) begin
                video_addr <= issue_addr;
            end

            req_d0_valid      <= issue_pixel;
            req_d0_x          <= mikey_scan_x;
            req_d0_y          <= mikey_scan_y;
            req_d0_fourbit    <= fourbit_now;
            req_d0_flip       <= flip_now;
            req_d0_x_lsb      <= mikey_scan_x[0];
            req_d0_x_pair     <= mikey_scan_x[1:0];
            req_d0_dma_enable <= video_dma_enable_now;

            req_d1_valid      <= req_d0_valid;
            req_d1_x          <= req_d0_x;
            req_d1_y          <= req_d0_y;
            req_d1_fourbit    <= req_d0_fourbit;
            req_d1_flip       <= req_d0_flip;
            req_d1_x_lsb      <= req_d0_x_lsb;
            req_d1_x_pair     <= req_d0_x_pair;
            req_d1_dma_enable <= req_d0_dma_enable;

            req_d2_valid      <= req_d1_valid;
            req_d2_x          <= req_d1_x;
            req_d2_y          <= req_d1_y;
            req_d2_fourbit    <= req_d1_fourbit;
            req_d2_flip       <= req_d1_flip;
            req_d2_x_lsb      <= req_d1_x_lsb;
            req_d2_x_pair     <= req_d1_x_pair;
            req_d2_dma_enable <= req_d1_dma_enable;

            if (req_d2_valid && req_d2_dma_enable) begin
                pix_valid <= 1'b1;
                pix_x     <= req_d2_x;
                pix_y     <= req_d2_y;
                pix_index <= pen_from_byte(video_data,
                                           req_d2_fourbit,
                                           req_d2_flip,
                                           req_d2_x_lsb,
                                           req_d2_x_pair);
            end else begin
                pix_valid <= 1'b0;
                pix_x     <= 8'd0;
                pix_y     <= 7'd0;
                pix_index <= 4'h0;
            end
        end
    end

    assign debug_video_byte      = video_data;
    assign debug_pix_index       = pix_index;
    assign debug_pix_valid       = pix_valid;
    assign debug_video_enable    = video_dma_enable_now;
    assign debug_fourbit_enable  = fourbit_now;
    assign debug_color_enable    = color_now;
    assign debug_active_pipe     = mikey_scan_active;

    logic unused_real_display_state;
    assign unused_real_display_state =
        display_line[0] ^
        req_d0_valid ^
        req_d1_valid ^
        req_d2_valid ^
        req_d0_x[0] ^
        req_d1_x[0] ^
        req_d2_x[0];

endmodule