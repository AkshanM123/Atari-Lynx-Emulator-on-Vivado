`timescale 1ns/1ps

module suzy_regs (
input  logic        clk,
input  logic        reset,

input  logic [7:0]  addr,

input  logic [7:0]  cpu_dout,
output logic [7:0]  cpu_din,

input  logic        wr_en,
input  logic        rd_en,

input  logic [7:0]  lynx_fcb0_joystick,
input  logic [2:0]  lynx_fcb1_switches,

output logic        start_pulse,
output logic        force_stop_pulse,

output logic [7:0]  reg_fc00,
output logic [7:0]  reg_fc01,
output logic [7:0]  reg_fc04,
output logic [7:0]  reg_fc05,
output logic [7:0]  reg_fc06,
output logic [7:0]  reg_fc07,
output logic [7:0]  reg_fc08,
output logic [7:0]  reg_fc09,
output logic [7:0]  reg_fc10,
output logic [7:0]  reg_fc11,

output logic [7:0]  reg_fc18,
output logic [7:0]  reg_fc19,
output logic [7:0]  reg_fc1a,
output logic [7:0]  reg_fc1b,

output logic [7:0]  reg_fc28,
output logic [7:0]  reg_fc29,
output logic [7:0]  reg_fc2a,
output logic [7:0]  reg_fc2b,

output logic [7:0]  reg_fc90,
output logic [7:0]  reg_fc91,
output logic [7:0]  reg_fc92,

output logic [15:0] hoff,
output logic [15:0] voff,

output logic [15:0] vid_base_addr,
output logic [15:0] coll_base_addr,
output logic [15:0] coll_off,
output logic [15:0] scb_next_addr,

output logic [15:0] spr_hsize,
output logic [15:0] spr_vsize,
output logic [15:0] hsizoff,
output logic [15:0] vsizoff,

input  logic        core_frame_done,
input  logic        core_collision_seen,

output logic        suzy_busy,
output logic        suzy_done_sticky,
output logic        collision_sticky,

output logic [7:0]  debug_last_write
);

logic [7:0] regs [0:255];

integer i;

localparam logic [7:0] REG_SUZY_HREV    = 8'h88;
localparam logic [7:0] REG_SPRINIT      = 8'h90;
localparam logic [7:0] REG_SPRGO        = 8'h91;
localparam logic [7:0] REG_SPRSYS       = 8'h92;

localparam logic [7:0] REG_JOYSTICK     = 8'hB0;
localparam logic [7:0] REG_SWITCHES     = 8'hB1;
localparam logic [7:0] REG_RCART0       = 8'hB2;
localparam logic [7:0] REG_RCART1       = 8'hB3;

localparam logic [7:0] REG_MATHD        = 8'h52;
localparam logic [7:0] REG_MATHC        = 8'h53;
localparam logic [7:0] REG_MATHB        = 8'h54;
localparam logic [7:0] REG_MATHA        = 8'h55;
localparam logic [7:0] REG_MATHP        = 8'h56;
localparam logic [7:0] REG_MATHN        = 8'h57;

localparam logic [7:0] REG_MATHH        = 8'h60;
localparam logic [7:0] REG_MATHG        = 8'h61;
localparam logic [7:0] REG_MATHF        = 8'h62;
localparam logic [7:0] REG_MATHE        = 8'h63;

localparam logic [7:0] REG_MATHM        = 8'h6C;
localparam logic [7:0] REG_MATHL        = 8'h6D;
localparam logic [7:0] REG_MATHK        = 8'h6E;
localparam logic [7:0] REG_MATHJ        = 8'h6F;

localparam logic [7:0] SUZY_HWREV_VALUE = 8'h01;

localparam logic [7:0] RCART_IDLE_VALUE = 8'h00;

logic        math_busy;
logic        mathbit;
logic [9:0]  math_countdown;

function automatic logic [4:0] leading_zero_count16;
    input logic [15:0] value;
    begin
        if (value[15]) begin
            leading_zero_count16 = 5'd0;
        end else if (value[14]) begin
            leading_zero_count16 = 5'd1;
        end else if (value[13]) begin
            leading_zero_count16 = 5'd2;
        end else if (value[12]) begin
            leading_zero_count16 = 5'd3;
        end else if (value[11]) begin
            leading_zero_count16 = 5'd4;
        end else if (value[10]) begin
            leading_zero_count16 = 5'd5;
        end else if (value[9]) begin
            leading_zero_count16 = 5'd6;
        end else if (value[8]) begin
            leading_zero_count16 = 5'd7;
        end else if (value[7]) begin
            leading_zero_count16 = 5'd8;
        end else if (value[6]) begin
            leading_zero_count16 = 5'd9;
        end else if (value[5]) begin
            leading_zero_count16 = 5'd10;
        end else if (value[4]) begin
            leading_zero_count16 = 5'd11;
        end else if (value[3]) begin
            leading_zero_count16 = 5'd12;
        end else if (value[2]) begin
            leading_zero_count16 = 5'd13;
        end else if (value[1]) begin
            leading_zero_count16 = 5'd14;
        end else if (value[0]) begin
            leading_zero_count16 = 5'd15;
        end else begin
            leading_zero_count16 = 5'd16;
        end
    end
endfunction

assign reg_fc00 = regs[8'h00];
assign reg_fc01 = regs[8'h01];

assign reg_fc04 = regs[8'h04];
assign reg_fc05 = regs[8'h05];

assign reg_fc06 = regs[8'h06];
assign reg_fc07 = regs[8'h07];

assign reg_fc08 = regs[8'h08];
assign reg_fc09 = regs[8'h09];

assign reg_fc10 = regs[8'h10];
assign reg_fc11 = regs[8'h11];

assign reg_fc18 = regs[8'h18];
assign reg_fc19 = regs[8'h19];
assign reg_fc1a = regs[8'h1A];
assign reg_fc1b = regs[8'h1B];

assign reg_fc28 = regs[8'h28];
assign reg_fc29 = regs[8'h29];
assign reg_fc2a = regs[8'h2A];
assign reg_fc2b = regs[8'h2B];

assign reg_fc90 = regs[8'h90];
assign reg_fc91 = regs[8'h91];
assign reg_fc92 = regs[8'h92];

assign hoff = {regs[8'h05], regs[8'h04]};
assign voff = {regs[8'h07], regs[8'h06]};

assign vid_base_addr  = {regs[8'h09], regs[8'h08]};
assign coll_base_addr = {regs[8'h0B], regs[8'h0A]};
assign coll_off       = {regs[8'h25], regs[8'h24]};
assign scb_next_addr  = {regs[8'h11], regs[8'h10]};

assign spr_hsize = {regs[8'h19], regs[8'h18]};
assign spr_vsize = {regs[8'h1B], regs[8'h1A]};

assign hsizoff = {regs[8'h29], regs[8'h28]};
assign vsizoff = {regs[8'h2B], regs[8'h2A]};

always_ff @(posedge clk) begin
    if (reset) begin
        start_pulse      <= 1'b0;
        force_stop_pulse <= 1'b0;

        suzy_busy        <= 1'b0;
        suzy_done_sticky <= 1'b0;
        collision_sticky <= 1'b0;
        debug_last_write <= 8'h00;
        cpu_din          <= 8'h00;

        math_busy        <= 1'b0;
        mathbit          <= 1'b0;
        math_countdown   <= 10'd0;

        for (i = 0; i < 256; i = i + 1) begin
            regs[i] <= 8'h00;
        end

        regs[REG_SUZY_HREV] <= SUZY_HWREV_VALUE;

        regs[REG_RCART0] <= RCART_IDLE_VALUE;
        regs[REG_RCART1] <= RCART_IDLE_VALUE;

    end else begin
        logic [15:0] mult_ab;
        logic [15:0] mult_cd;
        logic [31:0] mult_product;
        logic [31:0] accum_old;
        logic [32:0] accum_sum;
        logic [31:0] div_dividend;
        logic [15:0] div_divisor;
        logic [31:0] div_quotient;
        logic [15:0] div_remainder;
        logic [4:0]  div_lz;
        logic [9:0]  div_ticks;

        start_pulse      <= 1'b0;
        force_stop_pulse <= 1'b0;

        if (math_busy) begin
            if (math_countdown > 10'd1) begin
                math_countdown <= math_countdown - 10'd1;
            end else begin
                math_countdown <= 10'd0;
                math_busy      <= 1'b0;
            end
        end

        if (core_frame_done) begin
            suzy_busy        <= 1'b0;
            suzy_done_sticky <= 1'b1;

            regs[REG_SPRGO][0] <= 1'b0;
        end

        if (core_collision_seen) begin
            collision_sticky <= 1'b1;
        end

        if (wr_en) begin
            regs[addr]       <= cpu_dout;
            debug_last_write <= cpu_dout;

            if (addr == REG_MATHD) begin
                regs[REG_MATHC] <= 8'h00;
            end

            if (addr == REG_MATHB) begin
                regs[REG_MATHA] <= 8'h00;
            end

            if (addr == REG_MATHH) begin
                regs[REG_MATHG] <= 8'h00;
            end

            if (addr == REG_MATHF) begin
                regs[REG_MATHE] <= 8'h00;
            end

            if (addr == REG_MATHM) begin
                regs[REG_MATHL] <= 8'h00;
                mathbit <= 1'b0;
            end

            if (addr == REG_MATHK) begin
                regs[REG_MATHJ] <= 8'h00;
            end

            if ((addr == REG_MATHA) && !math_busy) begin
                mult_ab = {cpu_dout, regs[REG_MATHB]};
                mult_cd = {regs[REG_MATHC], regs[REG_MATHD]};

                if (regs[REG_SPRSYS][7]) begin
                    mult_product = $signed(mult_ab) * $signed(mult_cd);
                end else begin
                    mult_product = mult_ab * mult_cd;
                end

                regs[REG_MATHH] <= mult_product[7:0];
                regs[REG_MATHG] <= mult_product[15:8];
                regs[REG_MATHF] <= mult_product[23:16];
                regs[REG_MATHE] <= mult_product[31:24];

                if (regs[REG_SPRSYS][6]) begin
                    accum_old = {
                        regs[REG_MATHJ],
                        regs[REG_MATHK],
                        regs[REG_MATHL],
                        regs[REG_MATHM]
                    };

                    accum_sum = {1'b0, accum_old} + {1'b0, mult_product};

                    regs[REG_MATHM] <= accum_sum[7:0];
                    regs[REG_MATHL] <= accum_sum[15:8];
                    regs[REG_MATHK] <= accum_sum[23:16];
                    regs[REG_MATHJ] <= accum_sum[31:24];

                    mathbit <= accum_sum[32];
                end else begin
                    mathbit <= 1'b0;
                end

                math_busy <= 1'b1;

                if (regs[REG_SPRSYS][7] || regs[REG_SPRSYS][6]) begin
                    math_countdown <= 10'd54;
                end else begin
                    math_countdown <= 10'd44;
                end
            end

            if ((addr == REG_MATHE) && !math_busy) begin
                div_dividend = {cpu_dout, regs[REG_MATHF], regs[REG_MATHG], regs[REG_MATHH]};
                div_divisor  = {regs[REG_MATHN], regs[REG_MATHP]};

                div_lz = leading_zero_count16(div_divisor);
                div_ticks = 10'd176 + ({5'd0, div_lz} * 10'd14);

                if (div_divisor == 16'h0000) begin
                    div_quotient  = 32'hFFFFFFFF;
                    div_remainder = 16'h0000;
                    mathbit       <= 1'b1;
                end else begin
                    div_quotient  = div_dividend / div_divisor;
                    div_remainder = div_dividend % div_divisor;
                    mathbit       <= 1'b0;
                end

                regs[REG_MATHD] <= div_quotient[7:0];
                regs[REG_MATHC] <= div_quotient[15:8];
                regs[REG_MATHB] <= div_quotient[23:16];
                regs[REG_MATHA] <= div_quotient[31:24];

                regs[REG_MATHM] <= div_remainder[7:0];
                regs[REG_MATHL] <= div_remainder[15:8];
                regs[REG_MATHK] <= 8'h00;
                regs[REG_MATHJ] <= 8'h00;

                math_busy      <= 1'b1;
                math_countdown <= div_ticks;
            end

            if (addr == REG_SPRGO) begin
                if (cpu_dout[0]) begin
                    if (!suzy_busy && regs[REG_SPRINIT][0]) begin
                        start_pulse      <= 1'b1;
                        suzy_busy        <= 1'b1;
                        suzy_done_sticky <= 1'b0;
                        collision_sticky <= 1'b0;

                        regs[REG_SPRGO][0] <= 1'b1;
                    end else begin
                        if (suzy_busy) begin
                            regs[REG_SPRGO][0] <= 1'b1;
                        end
                    end
                end else begin
                    force_stop_pulse <= 1'b1;
                    suzy_busy        <= 1'b0;

                    regs[REG_SPRGO][0] <= 1'b0;
                end
            end

            if (addr == REG_SPRSYS) begin
                regs[REG_SPRSYS] <= cpu_dout;
            end
        end

        if (rd_en) begin
            case (addr)

                REG_SUZY_HREV: begin
                    cpu_din <= SUZY_HWREV_VALUE;
                end

                REG_SPRINIT: begin
                    cpu_din <= regs[REG_SPRINIT];
                end

                REG_SPRGO: begin
                    cpu_din <= {
                        regs[REG_SPRGO][7:2],
                        suzy_done_sticky,
                        suzy_busy
                    };
                end

                REG_SPRSYS: begin
                    cpu_din <= {
                        math_busy,
                        mathbit,
                        regs[REG_SPRSYS][5],
                        regs[REG_SPRSYS][4],
                        regs[REG_SPRSYS][3],
                        regs[REG_SPRSYS][2],
                        regs[REG_SPRSYS][1],
                        suzy_busy
                    };
                end

                REG_JOYSTICK: begin
                    cpu_din <= lynx_fcb0_joystick;
                end

                REG_SWITCHES: begin
                    cpu_din <= {5'b00000, lynx_fcb1_switches};
                end

                REG_RCART0: begin
                    cpu_din <= RCART_IDLE_VALUE;
                end

                REG_RCART1: begin
                    cpu_din <= RCART_IDLE_VALUE;
                end

                default: begin
                    cpu_din <= regs[addr];
                end

            endcase
        end
    end
end

endmodule