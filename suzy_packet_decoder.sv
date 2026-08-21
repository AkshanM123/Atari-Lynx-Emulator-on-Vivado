`timescale 1ns/1ps

module suzy_packet_decoder #(
    parameter int MAX_LINE_BYTES = 128
)(
    input  logic                          clk,
    input  logic                          reset,

    input  logic                          start,
    output logic                          busy,
    output logic                          done,

    input  logic [2:0]                    bits_per_pixel,
    input  logic                          totally_literal,

    input  logic [15:0]                   line_bits_total,
    input  logic [(MAX_LINE_BYTES*8)-1:0] line_data_flat,

    output logic                          pen_valid,
    input  logic                          pen_ready,
    output logic [3:0]                    src_pen,

    output logic [15:0]                   debug_bit_pos,
    output logic [4:0]                    debug_packet_header,
    output logic                          debug_literal_packet,
    output logic                          debug_packed_packet,
    output logic                          debug_totally_literal
);

    typedef enum logic [3:0] {
        PD_IDLE,
        PD_HEADER_CAPTURE,
        PD_HEADER_EVAL,
        PD_PACKED_LOAD_PEN,
        PD_LITERAL_LOAD_PEN,
        PD_TOT_LITERAL_LOAD_PEN,
        PD_EMIT,
        PD_AFTER_EMIT,
        PD_DONE
    } pd_state_t;

    pd_state_t state;

    logic [15:0] bit_pos;

    logic [4:0] packet_header;
    logic       header_literal;
    logic [3:0] header_count_minus_1;

    logic [7:0] count_remaining;

    logic [3:0] current_pen;
    logic [3:0] packed_pen;

    logic mode_literal;
    logic mode_packed;
    logic mode_totally_literal;

    logic [2:0] bpp_eff;

    assign debug_bit_pos          = bit_pos;
    assign debug_packet_header    = packet_header;
    assign debug_literal_packet   = mode_literal;
    assign debug_packed_packet    = mode_packed;
    assign debug_totally_literal  = mode_totally_literal;

    always_comb begin
        case (bits_per_pixel)
            3'd1: bpp_eff = 3'd1;
            3'd2: bpp_eff = 3'd2;
            3'd3: bpp_eff = 3'd3;
            3'd4: bpp_eff = 3'd4;
            default: bpp_eff = 3'd4;
        endcase
    end

    function automatic logic get_stream_bit;
        input integer stream_bit;

        integer byte_index;
        integer bit_index_in_byte;
        integer physical_bit;
        begin
            if ((stream_bit >= 0) && (stream_bit < (MAX_LINE_BYTES * 8))) begin
                byte_index        = stream_bit / 8;
                bit_index_in_byte = stream_bit % 8;
                physical_bit      = (byte_index * 8) + (7 - bit_index_in_byte);

                get_stream_bit = line_data_flat[physical_bit];
            end else begin
                get_stream_bit = 1'b0;
            end
        end
    endfunction

    function automatic logic [4:0] get_header_msb_first;
        input integer start_bit;

        integer k;
        logic [4:0] value;
        begin
            value = 5'b00000;

            for (k = 0; k < 5; k = k + 1) begin
                value = {value[3:0], get_stream_bit(start_bit + k)};
            end

            get_header_msb_first = value;
        end
    endfunction

    function automatic logic [3:0] get_pen_msb_first;
        input integer start_bit;
        input logic [2:0] bpp;

        integer k;
        logic [3:0] value;
        begin
            value = 4'h0;

            for (k = 0; k < 4; k = k + 1) begin
                if (k < bpp) begin
                    value = {value[2:0], get_stream_bit(start_bit + k)};
                end
            end

            get_pen_msb_first = value;
        end
    endfunction

    function automatic logic [15:0] remaining_bits;
        input logic [15:0] total_bits;
        input logic [15:0] pos;
        begin
            if (pos >= total_bits) begin
                remaining_bits = 16'd0;
            end else begin
                remaining_bits = total_bits - pos;
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= PD_IDLE;

            busy <= 1'b0;
            done <= 1'b0;

            bit_pos <= 16'd0;

            packet_header        <= 5'b00000;
            header_literal       <= 1'b0;
            header_count_minus_1 <= 4'd0;

            count_remaining <= 8'd0;

            current_pen <= 4'h0;
            packed_pen  <= 4'h0;

            mode_literal         <= 1'b0;
            mode_packed          <= 1'b0;
            mode_totally_literal <= 1'b0;

            pen_valid <= 1'b0;
            src_pen   <= 4'h0;

        end else begin
            done <= 1'b0;

            case (state)

                PD_IDLE: begin
                    busy      <= 1'b0;
                    pen_valid <= 1'b0;
                    src_pen   <= 4'h0;

                    mode_literal         <= 1'b0;
                    mode_packed          <= 1'b0;
                    mode_totally_literal <= 1'b0;

                    if (start) begin
                        busy <= 1'b1;

                        bit_pos <= 16'd0;

                        packet_header        <= 5'b00000;
                        header_literal       <= 1'b0;
                        header_count_minus_1 <= 4'd0;

                        count_remaining <= 8'd0;

                        current_pen <= 4'h0;
                        packed_pen  <= 4'h0;

                        pen_valid <= 1'b0;
                        src_pen   <= 4'h0;

                        if (line_bits_total == 16'd0) begin
                            state <= PD_DONE;
                        end else if (totally_literal) begin
                            mode_totally_literal <= 1'b1;
                            mode_literal         <= 1'b0;
                            mode_packed          <= 1'b0;
                            state <= PD_TOT_LITERAL_LOAD_PEN;
                        end else begin
                            mode_totally_literal <= 1'b0;
                            mode_literal         <= 1'b0;
                            mode_packed          <= 1'b0;
                            state <= PD_HEADER_CAPTURE;
                        end
                    end
                end

                PD_HEADER_CAPTURE: begin
                    pen_valid <= 1'b0;
                    mode_literal <= 1'b0;
                    mode_packed  <= 1'b0;

                    if ((bit_pos + 16'd5) > line_bits_total) begin
                        state <= PD_DONE;
                    end else begin
                        packet_header <= get_header_msb_first(bit_pos);
                        state <= PD_HEADER_EVAL;
                    end
                end

                PD_HEADER_EVAL: begin
                    if (packet_header == 5'b00000) begin
                        state <= PD_DONE;
                    end else begin
                        header_literal       <= packet_header[4];
                        header_count_minus_1 <= packet_header[3:0];

                        count_remaining <= {4'b0000, packet_header[3:0]} + 8'd1;
                        bit_pos         <= bit_pos + 16'd5;

                        if (packet_header[4]) begin
                            mode_literal <= 1'b1;
                            mode_packed  <= 1'b0;
                            state        <= PD_LITERAL_LOAD_PEN;
                        end else begin
                            mode_literal <= 1'b0;
                            mode_packed  <= 1'b1;
                            state        <= PD_PACKED_LOAD_PEN;
                        end
                    end
                end

                PD_PACKED_LOAD_PEN: begin
                    if ((bit_pos + {13'd0, bpp_eff}) > line_bits_total) begin
                        state <= PD_DONE;
                    end else begin
                        packed_pen  <= get_pen_msb_first(bit_pos, bpp_eff);
                        current_pen <= get_pen_msb_first(bit_pos, bpp_eff);
                        src_pen     <= get_pen_msb_first(bit_pos, bpp_eff);

                        bit_pos <= bit_pos + {13'd0, bpp_eff};

                        state <= PD_EMIT;
                    end
                end

                PD_LITERAL_LOAD_PEN: begin
                    if (count_remaining == 8'd0) begin
                        state <= PD_HEADER_CAPTURE;
                    end else if ((bit_pos + {13'd0, bpp_eff}) > line_bits_total) begin
                        state <= PD_DONE;
                    end else begin
                        current_pen <= get_pen_msb_first(bit_pos, bpp_eff);
                        src_pen     <= get_pen_msb_first(bit_pos, bpp_eff);

                        bit_pos <= bit_pos + {13'd0, bpp_eff};

                        state <= PD_EMIT;
                    end
                end

                PD_TOT_LITERAL_LOAD_PEN: begin
                    if (bit_pos >= line_bits_total) begin
                        state <= PD_DONE;
                    end else begin
                        current_pen <= get_pen_msb_first(bit_pos, bpp_eff);
                        src_pen     <= get_pen_msb_first(bit_pos, bpp_eff);

                        if (remaining_bits(line_bits_total, bit_pos) >= {13'd0, bpp_eff}) begin
                            bit_pos <= bit_pos + {13'd0, bpp_eff};
                        end else begin
                            bit_pos <= line_bits_total;
                        end

                        state <= PD_EMIT;
                    end
                end

                PD_EMIT: begin
                    if (!pen_valid) begin
                        pen_valid <= 1'b1;
                        src_pen   <= current_pen;
                    end else if (pen_ready) begin
                        pen_valid <= 1'b0;
                        state     <= PD_AFTER_EMIT;
                    end
                end

                PD_AFTER_EMIT: begin
                    pen_valid <= 1'b0;

                    if (mode_totally_literal) begin
                        state <= PD_TOT_LITERAL_LOAD_PEN;

                    end else if (mode_packed) begin
                        if (count_remaining <= 8'd1) begin
                            count_remaining <= 8'd0;
                            state <= PD_HEADER_CAPTURE;
                        end else begin
                            count_remaining <= count_remaining - 8'd1;
                            current_pen <= packed_pen;
                            src_pen     <= packed_pen;
                            state <= PD_EMIT;
                        end

                    end else if (mode_literal) begin
                        if (count_remaining <= 8'd1) begin
                            count_remaining <= 8'd0;
                            state <= PD_HEADER_CAPTURE;
                        end else begin
                            count_remaining <= count_remaining - 8'd1;
                            state <= PD_LITERAL_LOAD_PEN;
                        end

                    end else begin
                        state <= PD_DONE;
                    end
                end

                PD_DONE: begin
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    pen_valid <= 1'b0;
                    src_pen   <= 4'h0;

                    mode_literal         <= 1'b0;
                    mode_packed          <= 1'b0;
                    mode_totally_literal <= 1'b0;

                    state <= PD_IDLE;
                end

                default: begin
                    busy      <= 1'b0;
                    done      <= 1'b0;
                    pen_valid <= 1'b0;
                    src_pen   <= 4'h0;

                    mode_literal         <= 1'b0;
                    mode_packed          <= 1'b0;
                    mode_totally_literal <= 1'b0;

                    state <= PD_IDLE;
                end

            endcase
        end
    end

endmodule