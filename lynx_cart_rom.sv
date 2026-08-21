`timescale 1ns/1ps

module lynx_cart_rom #(

    parameter int CART_ROM_ADDR_BITS = 17
)(
    input  logic        clk,
    input  logic [20:0] addr,
    output logic  [7:0] data
);

    blk_mem_gen_1 u_cart_rom (
        .clka  (clk),
        .addra (addr[CART_ROM_ADDR_BITS-1:0]),
        .douta (data)
    );

endmodule