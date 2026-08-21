`timescale 1ns/1ps

module lynx_bios_rom (
    input  logic        clk,
    input  logic [8:0]  addr,
    output logic [7:0]  data
);

   
    bios_rom u_bios_rom (
        .clka  (clk),
        .addra (addr),
        .douta (data)
    );

endmodule