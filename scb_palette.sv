`timescale 1ns/1ps

module scb_palette (
    input  logic [3:0] src_pen,

    input  logic [7:0] pal0,
    input  logic [7:0] pal1,
    input  logic [7:0] pal2,
    input  logic [7:0] pal3,
    input  logic [7:0] pal4,
    input  logic [7:0] pal5,
    input  logic [7:0] pal6,
    input  logic [7:0] pal7,

    output logic [3:0] mapped_pen
);

   

    always_comb begin
        unique case (src_pen)

            4'h0: mapped_pen = pal0[7:4];
            4'h1: mapped_pen = pal0[3:0];

            4'h2: mapped_pen = pal1[7:4];
            4'h3: mapped_pen = pal1[3:0];

            4'h4: mapped_pen = pal2[7:4];
            4'h5: mapped_pen = pal2[3:0];

            4'h6: mapped_pen = pal3[7:4];
            4'h7: mapped_pen = pal3[3:0];

            4'h8: mapped_pen = pal4[7:4];
            4'h9: mapped_pen = pal4[3:0];

            4'hA: mapped_pen = pal5[7:4];
            4'hB: mapped_pen = pal5[3:0];

            4'hC: mapped_pen = pal6[7:4];
            4'hD: mapped_pen = pal6[3:0];

            4'hE: mapped_pen = pal7[7:4];
            4'hF: mapped_pen = pal7[3:0];

            default: mapped_pen = 4'h0;

        endcase
    end

endmodule