`timescale 1ns/1ps

module mikey_regs (
    input  logic        clk,
    input  logic        reset,

    input  logic        cpu_cs,
    input  logic        cpu_we,
    input  logic [15:0] cpu_addr,
    input  logic  [7:0] cpu_wdata,
    output logic  [7:0] cpu_rdata,

    input  logic        hcount_tick,
    input  logic        vcount_tick,

    output logic        irq_request,
    output logic        timer7_audio_link_tick,

    output logic  [7:0] dispctl,
    output logic [15:0] disp_addr,

    output logic        display_visible,
    output logic        display_vblank,
    output logic  [6:0] display_line,
    output logic        dispaddr_latch,
    output logic        mikey_frame_tick,

    output logic  [7:0] mikey_scan_x,
    output logic  [6:0] mikey_scan_y,
    output logic        mikey_scan_active,

    output logic  [3:0] green  [0:15],
    output logic  [3:0] red    [0:15],
    output logic  [3:0] blue   [0:15]
);

    import lynx_pkg::*;

    localparam int TIMER_COUNT = 8;

    localparam int MIKEY_VISIBLE_LINES         = LYNX_VISIBLE_LINES;
    localparam int MIKEY_TOTAL_LINES           = LYNX_TOTAL_LINES;
    localparam int MIKEY_DISPADDR_LATCH_LINE  = LYNX_DISPADDR_RELOAD_LINE;

    localparam int ATARI_TICK_NUMERATOR        = 16;
    localparam int SYSTEM_TICK_DENOMINATOR     = 25;
    localparam int ROW_TICKS                   = 1920;
    localparam int TICKS_PER_PIXEL             = 12;
    localparam int VISIBLE_PIXELS_PER_LINE     = 160;

    logic [7:0] green_reg   [0:15];
    logic [7:0] bluered_reg [0:15];

    logic [15:0] disp_addr_backup;

    logic [7:0] pbkup;
    logic [7:0] mtest0;
    logic [7:0] mtest1;
    logic [7:0] mtest2;

    logic [6:0] mikey_line;
    logic       mikey_vblank;
    logic       mikey_line_tick;
    logic       dispaddr_latch_pulse;

    assign mikey_vblank    = (mikey_line >= MIKEY_VISIBLE_LINES[6:0]);
    assign display_vblank  = mikey_vblank;
    assign display_visible = !mikey_vblank;
    assign display_line    = mikey_line;
    assign dispaddr_latch  = dispaddr_latch_pulse;

    logic [7:0] interrupt_flags;

    localparam int CTLA_IRQ_ENABLE_BIT     = 7;
    localparam int CTLA_RESET_DONE_BIT     = 6;
    localparam int CTLA_RELOAD_BIT         = 4;
    localparam int CTLA_COUNT_ENABLE_BIT   = 3;
    localparam int CTLB_TIMER_DONE_BIT     = 3;

    logic [7:0] timer_backup [0:TIMER_COUNT-1];
    logic [7:0] timer_ctla   [0:TIMER_COUNT-1];
    logic [7:0] timer_count  [0:TIMER_COUNT-1];
    logic [7:0] timer_ctlb   [0:TIMER_COUNT-1];

    logic [15:0] timer_divcnt [0:TIMER_COUNT-1];

    logic [TIMER_COUNT-1:0] timer_underflow_pulse;
    logic [TIMER_COUNT-1:0] timer_tick_pulse;

    logic [TIMER_COUNT-1:0] timer_underflow_now;

    logic [5:0]  atari_tick_accum;
    logic        atari_tick_now;
    logic [15:0] scan_line_tick;
    logic        scan_line_visible;
    logic        scan_pixels_started;
    logic [7:0]  scan_pixel_count;
    logic [3:0]  scan_pixel_subtick;
    logic        timer0_line_event;

    integer i;

    logic unused_display_ticks;
    assign unused_display_ticks = hcount_tick ^ vcount_tick;

    function automatic logic timer_addr_hit;
        input logic [7:0] off;
        begin
            timer_addr_hit = (off >= 8'h00) && (off <= 8'h1F);
        end
    endfunction

    function automatic logic [2:0] timer_index_from_off;
        input logic [7:0] off;
        begin
            timer_index_from_off = off[4:2];
        end
    endfunction

    function automatic logic [1:0] timer_reg_from_off;
        input logic [7:0] off;
        begin
            timer_reg_from_off = off[1:0];
        end
    endfunction

    function automatic logic timer_irq_capable;
        input logic [2:0] idx;
        begin
            timer_irq_capable = (idx != 3'd4);
        end
    endfunction

    function automatic logic linked_timer_source;
        input logic [2:0] idx;
        begin
            linked_timer_source = (timer_ctla[idx][2:0] == 3'd7);
        end
    endfunction

    function automatic logic [15:0] source_period_cycles;
        input logic [2:0] src;
        begin
            unique case (src)
                3'd0: source_period_cycles = 16'd25;
                3'd1: source_period_cycles = 16'd50;
                3'd2: source_period_cycles = 16'd100;
                3'd3: source_period_cycles = 16'd200;
                3'd4: source_period_cycles = 16'd400;
                3'd5: source_period_cycles = 16'd800;
                3'd6: source_period_cycles = 16'd1600;
                3'd7: source_period_cycles = 16'd1;
                default: source_period_cycles = 16'd25;
            endcase
        end
    endfunction

    function automatic logic [15:0] pbkup_dma_offset_ticks;
        input logic [7:0] value;
        logic [15:0] h;
        begin
            h = ((({8'd0, value} + 16'd1) * 16'd15) + 16'd2) >> 2;
            pbkup_dma_offset_ticks = (h << 4) - 16'd1920;
        end
    endfunction

    assign irq_request = (interrupt_flags != 8'h00);

    assign timer7_audio_link_tick = timer_underflow_pulse[7];

    always_comb begin
        timer_tick_pulse = '0;

        for (int t = 0; t < TIMER_COUNT; t = t + 1) begin
            if (!linked_timer_source(t[2:0])) begin
                if (atari_tick_now && (timer_divcnt[t] == 16'd0)) begin
                    timer_tick_pulse[t] = 1'b1;
                end
            end
        end

        if (linked_timer_source(3'd2) && timer_underflow_now[0]) begin
            timer_tick_pulse[2] = 1'b1;
        end

        if (linked_timer_source(3'd4) && timer_underflow_now[2]) begin
            timer_tick_pulse[4] = 1'b1;
        end

        if (linked_timer_source(3'd3) && timer_underflow_now[1]) begin
            timer_tick_pulse[3] = 1'b1;
        end

        if (linked_timer_source(3'd5) && timer_underflow_now[3]) begin
            timer_tick_pulse[5] = 1'b1;
        end

        if (linked_timer_source(3'd7) && timer_underflow_now[5]) begin
            timer_tick_pulse[7] = 1'b1;
        end
    end

    assign timer0_line_event = timer_ctla[0][CTLA_COUNT_ENABLE_BIT] &&
                               timer_tick_pulse[0] &&
                               !(timer_ctlb[0][CTLB_TIMER_DONE_BIT] &&
                                 !timer_ctla[0][CTLA_RELOAD_BIT]) &&
                               (timer_count[0] == 8'h00);

    assign atari_tick_now = (atari_tick_accum >=
                             (SYSTEM_TICK_DENOMINATOR - ATARI_TICK_NUMERATOR));

    logic [7:0] cpu_off;
    logic [2:0] wr_timer_idx;
    logic [1:0] wr_timer_reg;

    assign cpu_off      = cpu_addr[7:0];
    assign wr_timer_idx = timer_index_from_off(cpu_addr[7:0]);
    assign wr_timer_reg = timer_reg_from_off(cpu_addr[7:0]);

    always_ff @(posedge clk) begin
        if (reset) begin
            dispctl              <= 8'h00;
            disp_addr_backup     <= 16'h0000;
            disp_addr            <= 16'h0000;
            pbkup                <= 8'h00;
            mtest0               <= 8'h00;
            mtest1               <= 8'h00;
            mtest2               <= 8'h00;

            interrupt_flags      <= 8'h00;

            mikey_line           <= 7'd0;
            mikey_line_tick      <= 1'b0;
            mikey_frame_tick     <= 1'b0;
            dispaddr_latch_pulse <= 1'b0;

            timer_underflow_now  <= '0;

            atari_tick_accum     <= 6'd0;
            scan_line_tick       <= 16'd0;
            scan_line_visible    <= 1'b0;
            scan_pixels_started  <= 1'b0;
            scan_pixel_count     <= 8'd0;
            scan_pixel_subtick   <= 4'd0;
            mikey_scan_x         <= 8'd0;
            mikey_scan_y         <= 7'd0;
            mikey_scan_active    <= 1'b0;

            for (i = 0; i < 16; i = i + 1) begin
                green_reg[i]   <= 8'h00;
                bluered_reg[i] <= 8'h00;
            end

            for (i = 0; i < TIMER_COUNT; i = i + 1) begin
                timer_backup[i]          <= 8'h00;
                timer_ctla[i]            <= 8'h00;
                timer_count[i]           <= 8'h00;
                timer_ctlb[i]            <= 8'h00;
                timer_divcnt[i]          <= source_period_cycles(3'd0) - 16'd1;
                timer_underflow_pulse[i] <= 1'b0;
            end

        end else begin
            timer_underflow_now  <= '0;
            mikey_scan_active    <= 1'b0;

            if (atari_tick_now) begin
                atari_tick_accum <= atari_tick_accum + ATARI_TICK_NUMERATOR - SYSTEM_TICK_DENOMINATOR;
            end else begin
                atari_tick_accum <= atari_tick_accum + ATARI_TICK_NUMERATOR;
            end

            for (i = 0; i < TIMER_COUNT; i = i + 1) begin
                timer_underflow_pulse[i] <= 1'b0;
            end

            mikey_line_tick      <= 1'b0;
            mikey_frame_tick     <= 1'b0;
            dispaddr_latch_pulse <= 1'b0;

            for (i = 0; i < TIMER_COUNT; i = i + 1) begin
                if (linked_timer_source(i[2:0])) begin
                    timer_divcnt[i] <= source_period_cycles(timer_ctla[i][2:0]) - 16'd1;
                end else begin
                    if (timer_ctla[i][CTLA_COUNT_ENABLE_BIT]) begin
                        if (atari_tick_now) begin
                            if (timer_divcnt[i] == 16'd0) begin
                                timer_divcnt[i] <= source_period_cycles(timer_ctla[i][2:0]) - 16'd1;
                            end else begin
                                timer_divcnt[i] <= timer_divcnt[i] - 16'd1;
                            end
                        end
                    end else begin
                        timer_divcnt[i] <= source_period_cycles(timer_ctla[i][2:0]) - 16'd1;
                    end
                end
            end

            for (i = 0; i < TIMER_COUNT; i = i + 1) begin
                if (timer_ctla[i][CTLA_COUNT_ENABLE_BIT] && timer_tick_pulse[i]) begin
                    if (!(timer_ctlb[i][CTLB_TIMER_DONE_BIT] &&
                          !timer_ctla[i][CTLA_RELOAD_BIT])) begin

                        if (timer_count[i] == 8'h00) begin
                            timer_underflow_now[i]   <= 1'b1;
                            timer_underflow_pulse[i] <= 1'b1;
                            timer_ctlb[i][CTLB_TIMER_DONE_BIT] <= 1'b1;

                            if (timer_ctla[i][CTLA_IRQ_ENABLE_BIT] &&
                                timer_irq_capable(i[2:0])) begin
                                interrupt_flags[i] <= 1'b1;
                            end

                            if (timer_ctla[i][CTLA_RELOAD_BIT]) begin
                                timer_count[i] <= timer_backup[i];
                            end
                        end else begin
                            timer_count[i] <= timer_count[i] - 8'd1;
                        end
                    end
                end
            end

            if (timer0_line_event) begin

                mikey_line_tick     <= 1'b1;

                scan_line_tick      <= 16'd0;
                scan_line_visible   <= (mikey_line < MIKEY_VISIBLE_LINES[6:0]);
                scan_pixels_started <= 1'b0;
                scan_pixel_count    <= 8'd0;
                scan_pixel_subtick  <= 4'd0;
                mikey_scan_x        <= 8'd0;
                mikey_scan_y        <= mikey_line;

                if (mikey_line == (MIKEY_TOTAL_LINES - 1)) begin
                    mikey_line       <= 7'd0;
                    mikey_frame_tick <= 1'b1;
                end else begin
                    if (mikey_line == (MIKEY_DISPADDR_LATCH_LINE - 1)) begin
                        disp_addr            <= disp_addr_backup;
                        dispaddr_latch_pulse <= 1'b1;
                    end

                    mikey_line <= mikey_line + 7'd1;
                end
            end else if (atari_tick_now) begin
                if (!scan_pixels_started) begin
                    if (scan_line_visible &&
                        (scan_line_tick == pbkup_dma_offset_ticks(pbkup))) begin
                        scan_pixels_started <= 1'b1;
                        scan_pixel_count    <= 8'd0;
                        scan_pixel_subtick  <= 4'd0;
                        mikey_scan_x        <= 8'd0;
                        mikey_scan_active   <= 1'b1;
                    end
                end else begin
                    if (scan_pixel_count < (VISIBLE_PIXELS_PER_LINE - 1)) begin
                        if (scan_pixel_subtick == (TICKS_PER_PIXEL - 1)) begin
                            scan_pixel_subtick <= 4'd0;
                            scan_pixel_count   <= scan_pixel_count + 8'd1;
                            mikey_scan_x       <= scan_pixel_count + 8'd1;
                            mikey_scan_active  <= 1'b1;
                        end else begin
                            scan_pixel_subtick <= scan_pixel_subtick + 4'd1;
                        end
                    end
                end

                scan_line_tick <= scan_line_tick + 16'd1;
            end

            if (cpu_cs && cpu_we) begin
                unique case (cpu_addr)

                    MIKEY_INTRST: begin
                        interrupt_flags <= interrupt_flags & ~cpu_wdata;
                    end

                    MIKEY_INTSET: begin
                        interrupt_flags <= interrupt_flags | cpu_wdata;
                    end

                    MIKEY_DISPCTL: begin
                        dispctl <= cpu_wdata;
                    end

                    MIKEY_PBKUP: begin
                        pbkup <= cpu_wdata;
                    end

                    MIKEY_DISPADR_L: begin
                        disp_addr_backup[7:0] <= {cpu_wdata[7:2], 2'b00};
                    end

                    MIKEY_DISPADR_H: begin
                        disp_addr_backup[15:8] <= cpu_wdata;
                    end

                    MIKEY_MTEST0: begin
                        mtest0 <= cpu_wdata;
                    end

                    MIKEY_MTEST1: begin
                        mtest1 <= cpu_wdata;
                    end

                    MIKEY_MTEST2: begin
                        mtest2 <= cpu_wdata;

                        if (cpu_wdata[MTEST2_VBLANKEF_BIT]) begin
                            disp_addr            <= disp_addr_backup;
                            dispaddr_latch_pulse <= 1'b1;
                        end
                    end

                    default: begin
                        if (timer_addr_hit(cpu_off)) begin
                            unique case (wr_timer_reg)
                                2'd0: begin
                                    timer_backup[wr_timer_idx] <= cpu_wdata;
                                end

                                2'd1: begin
                                    timer_ctla[wr_timer_idx] <= {
                                        cpu_wdata[7],
                                        1'b0,
                                        cpu_wdata[5],
                                        cpu_wdata[4],
                                        cpu_wdata[3],
                                        cpu_wdata[2:0]
                                    };

                                    if (cpu_wdata[CTLA_RESET_DONE_BIT]) begin
                                        timer_ctlb[wr_timer_idx][CTLB_TIMER_DONE_BIT] <= 1'b0;
                                        interrupt_flags[wr_timer_idx] <= 1'b0;
                                    end

                                    timer_divcnt[wr_timer_idx] <=
                                        source_period_cycles(cpu_wdata[2:0]) - 16'd1;
                                end

                                2'd2: begin
                                    timer_count[wr_timer_idx] <= cpu_wdata;
                                end

                                2'd3: begin
                                    timer_ctlb[wr_timer_idx] <= {
                                        cpu_wdata[7:4],
                                        timer_ctlb[wr_timer_idx][CTLB_TIMER_DONE_BIT],
                                        cpu_wdata[2:0]
                                    };
                                end

                                default: begin
                                end
                            endcase

                        end else if ((cpu_addr >= MIKEY_GREEN_BASE) &&
                                     (cpu_addr <= MIKEY_GREEN_END)) begin
                            green_reg[cpu_addr[3:0]] <= cpu_wdata;

                        end else if ((cpu_addr >= MIKEY_BLUERED_BASE) &&
                                     (cpu_addr <= MIKEY_BLUERED_END)) begin
                            bluered_reg[cpu_addr[3:0]] <= cpu_wdata;
                        end
                    end
                endcase
            end
        end
    end

    always_comb begin
        cpu_rdata = 8'h00;

        if (cpu_cs) begin
            unique case (cpu_addr)

                MIKEY_INTRST: begin
                    cpu_rdata = interrupt_flags;
                end

                MIKEY_INTSET: begin
                    cpu_rdata = interrupt_flags;
                end

                MIKEY_DISPCTL: begin
                    cpu_rdata = dispctl;
                end

                MIKEY_PBKUP: begin
                    cpu_rdata = pbkup;
                end

                MIKEY_DISPADR_L: begin
                    cpu_rdata = disp_addr_backup[7:0];
                end

                MIKEY_DISPADR_H: begin
                    cpu_rdata = disp_addr_backup[15:8];
                end

                MIKEY_MTEST0: begin
                    cpu_rdata = mtest0;
                end

                MIKEY_MTEST1: begin
                    cpu_rdata = mtest1;
                end

                MIKEY_MTEST2: begin
                    cpu_rdata = mtest2;
                end

                default: begin
                    if (timer_addr_hit(cpu_off)) begin
                        unique case (timer_reg_from_off(cpu_off))
                            2'd0: begin
                                cpu_rdata = timer_backup[timer_index_from_off(cpu_off)];
                            end

                            2'd1: begin
                                cpu_rdata = {
                                    timer_ctla[timer_index_from_off(cpu_off)][7],
                                    1'b0,
                                    timer_ctla[timer_index_from_off(cpu_off)][5:0]
                                };
                            end

                            2'd2: begin
                                cpu_rdata = timer_count[timer_index_from_off(cpu_off)];
                            end

                            2'd3: begin
                                cpu_rdata = timer_ctlb[timer_index_from_off(cpu_off)];
                            end

                            default: begin
                                cpu_rdata = 8'h00;
                            end
                        endcase

                    end else if ((cpu_addr >= MIKEY_GREEN_BASE) &&
                                 (cpu_addr <= MIKEY_GREEN_END)) begin
                        cpu_rdata = green_reg[cpu_addr[3:0]];

                    end else if ((cpu_addr >= MIKEY_BLUERED_BASE) &&
                                 (cpu_addr <= MIKEY_BLUERED_END)) begin
                        cpu_rdata = bluered_reg[cpu_addr[3:0]];

                    end else begin
                        cpu_rdata = 8'h00;
                    end
                end
            endcase
        end
    end

    always_comb begin
        for (int p = 0; p < 16; p = p + 1) begin
            green[p] = green_reg[p][3:0];
            blue[p]  = bluered_reg[p][7:4];
            red[p]   = bluered_reg[p][3:0];
        end
    end

    logic unused_timing_state;
    assign unused_timing_state =
        mikey_vblank ^
        mikey_line_tick ^
        mikey_frame_tick ^
        dispaddr_latch_pulse ^
        display_visible ^
        display_vblank ^
        dispaddr_latch ^
        mtest0[0] ^
        mtest1[0] ^
        mtest2[0] ^
        display_line[0] ^
        mikey_line[0] ^
        timer_underflow_now[0] ^
        scan_line_tick[0] ^
        scan_pixels_started ^
        ROW_TICKS[0];

endmodule