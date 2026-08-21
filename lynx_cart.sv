`timescale 1ns/1ps

module lynx_cart_if #(
    parameter int BLOCK_OFFSET_BITS = 9
)(
    input  logic        clk,
    input  logic        reset,

    input  logic        sysctl1_we,
    input  logic        iodir_we,
    input  logic        iodat_we,
    input  logic  [7:0] reg_wdata,

    output logic  [7:0] sysctl1_rdata,
    output logic  [7:0] iodir_rdata,
    output logic  [7:0] iodat_rdata,

    input  logic        rcart0_rd,
    input  logic        rcart1_rd,
    output logic  [7:0] rcart_rdata,

    output logic [20:0] cart_rom_addr,
    input  logic  [7:0] cart_rom_data,

    output logic [7:0]  debug_cart_block,
    output logic [11:0] debug_cart_offset,
    output logic [20:0] debug_cart_addr,
    output logic [7:0]  debug_last_cart_data
);

    logic [7:0]  sysctl1_reg;
    logic [7:0]  iodir_reg;
    logic [7:0]  iodat_reg;

    logic [7:0]  cart_shift_reg;
    logic [7:0]  cart_selected_block;
    logic [2:0]  address_shift_count;

    logic [11:0] ripple_counter;
    logic [11:0] masked_ripple_counter;
    logic [20:0] current_cart_addr;

    logic [7:0]  cart_data_hold;

    logic        read_seen;
    logic        read_seen_d;
    logic        read_done_pulse;

    logic        cart_strobe_line_now;
    logic        cart_strobe_rise;

    logic        effective_serial_bit;
    logic [7:0]  shifted_block_next;

    assign sysctl1_rdata = sysctl1_reg;
    assign iodir_rdata   = iodir_reg;
    assign iodat_rdata   = iodat_reg;

    assign read_seen       = rcart0_rd || rcart1_rd;
    assign read_done_pulse = read_seen_d && !read_seen;

    assign effective_serial_bit = iodat_we ? reg_wdata[1] : iodat_reg[1];
    assign shifted_block_next   = {cart_shift_reg[6:0], effective_serial_bit};

    assign cart_strobe_line_now = sysctl1_we ? reg_wdata[0] : sysctl1_reg[0];
    assign cart_strobe_rise     = sysctl1_we && reg_wdata[0] && !sysctl1_reg[0];

    always_comb begin
        masked_ripple_counter = 12'h000;
        masked_ripple_counter[BLOCK_OFFSET_BITS-1:0] =
            ripple_counter[BLOCK_OFFSET_BITS-1:0];

        current_cart_addr =
            ({13'd0, cart_selected_block} << BLOCK_OFFSET_BITS) |
            {9'd0, masked_ripple_counter};
    end

    assign cart_rom_addr = current_cart_addr;

    assign rcart_rdata = cart_data_hold;

    assign debug_cart_block     = cart_selected_block;
    assign debug_cart_offset    = ripple_counter;
    assign debug_cart_addr      = current_cart_addr;
    assign debug_last_cart_data = cart_data_hold;

    always_ff @(posedge clk) begin
        if (reset) begin
            sysctl1_reg         <= 8'h00;
            iodir_reg           <= 8'h00;
            iodat_reg           <= 8'h00;

            cart_shift_reg      <= 8'h00;
            cart_selected_block <= 8'h00;
            address_shift_count <= 3'd0;

            ripple_counter      <= 12'h000;
            cart_data_hold      <= 8'h00;

            read_seen_d         <= 1'b0;
        end else begin
            if (iodir_we) begin
                iodir_reg <= reg_wdata;
            end

            if (iodat_we) begin
                iodat_reg <= reg_wdata;
            end

            if (sysctl1_we) begin
                sysctl1_reg <= reg_wdata;
            end

            if (read_seen) begin
                cart_data_hold <= cart_rom_data;
            end else if (!cart_strobe_line_now && !cart_strobe_rise) begin
                cart_data_hold <= cart_rom_data;
            end

            if (cart_strobe_rise) begin
                cart_shift_reg <= shifted_block_next;

                if (address_shift_count == 3'd7) begin
                    address_shift_count <= 3'd0;
                    cart_selected_block <= shifted_block_next;
                end else begin
                    address_shift_count <= address_shift_count + 3'd1;
                end

                ripple_counter <= 12'h000;

            end else if (cart_strobe_line_now) begin
                ripple_counter <= 12'h000;

            end else if (read_done_pulse) begin
                ripple_counter <= ripple_counter + 12'd1;
            end

            read_seen_d <= read_seen;
        end
    end

endmodule