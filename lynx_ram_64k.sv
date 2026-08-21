`timescale 1ns/1ps

module lynx_ram_64k (
    input  logic        clk,
    input  logic        reset,

    input  logic        cpu_en,
    input  logic [15:0] cpu_addr,
    input  logic  [7:0] cpu_din,
    output logic  [7:0] cpu_dout,
    input  logic        cpu_we,

    input  logic        suzy_rd_en,
    input  logic [15:0] suzy_rd_addr,
    output logic  [7:0] suzy_rd_data,
    output logic        suzy_rd_valid,

    input  logic        suzy_we,
    input  logic [15:0] suzy_addr,
    input  logic  [7:0] suzy_din,

    input  logic [15:0] video_addr,
    output logic  [7:0] video_dout
);

    logic [0:0]  wea;
    logic [0:0]  web;

    logic [15:0] port_a_addr;
    logic [7:0]  port_a_din;
    logic [7:0]  port_a_dout;

    logic suzy_read_grant;
    logic suzy_read_grant_q;

    assign suzy_read_grant = (!cpu_en && !suzy_we && suzy_rd_en);

    always_comb begin
        port_a_addr = 16'h0000;
        port_a_din  = 8'h00;
        wea         = 1'b0;

        if (cpu_en) begin
            port_a_addr = cpu_addr;
            port_a_din  = cpu_din;
            wea         = {cpu_we};
        end else if (suzy_we) begin
            port_a_addr = suzy_addr;
            port_a_din  = suzy_din;
            wea         = 1'b1;
        end else if (suzy_rd_en) begin
            port_a_addr = suzy_rd_addr;
            port_a_din  = 8'h00;
            wea         = 1'b0;
        end
    end

    assign web = 1'b0;

    assign cpu_dout = port_a_dout;

    always_ff @(posedge clk) begin
        if (reset) begin
            suzy_read_grant_q <= 1'b0;
            suzy_rd_valid     <= 1'b0;
            suzy_rd_data      <= 8'h00;
        end else begin
            suzy_read_grant_q <= suzy_read_grant;
            suzy_rd_valid     <= suzy_read_grant_q;

            if (suzy_read_grant_q) begin
                suzy_rd_data <= port_a_dout;
            end
        end
    end

    blk_mem_gen_0 u_bram (
        .clka  (clk),
        .wea   (wea),
        .addra (port_a_addr),
        .dina  (port_a_din),
        .douta (port_a_dout),

        .clkb  (clk),
        .web   (web),
        .addrb (video_addr),
        .dinb  (8'h00),
        .doutb (video_dout)
    );

endmodule