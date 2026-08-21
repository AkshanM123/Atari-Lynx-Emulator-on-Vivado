`timescale 1ns/1ps

module mikey_audio (
    input  logic        clk,
    input  logic        reset,

    input  logic        cpu_cs,
    input  logic        cpu_we,
    input  logic  [7:0] cpu_addr,
    input  logic  [7:0] cpu_wdata,
    output logic  [7:0] cpu_rdata,

    input  logic        timer7_link_tick,

    output logic        pwm_l,
    output logic        pwm_r,

    output logic signed [9:0] sample_l,
    output logic signed [9:0] sample_r
);

    localparam int AUDIO_CHANNELS = 4;

    localparam logic [7:0] AUDIO_BASE = 8'h20;
    localparam logic [7:0] AUDIO_END  = 8'h3F;
    localparam logic [7:0] MSTEREO    = 8'h50;

    logic [7:0] volume_reg   [0:AUDIO_CHANNELS-1];
    logic [7:0] feedback_reg [0:AUDIO_CHANNELS-1];
    logic [7:0] output_reg   [0:AUDIO_CHANNELS-1];
    logic [7:0] backup_reg   [0:AUDIO_CHANNELS-1];
    logic [7:0] control_reg  [0:AUDIO_CHANNELS-1];
    logic [7:0] counter_reg  [0:AUDIO_CHANNELS-1];

    logic [11:0] shift_reg [0:AUDIO_CHANNELS-1];

    logic [15:0] divcnt [0:AUDIO_CHANNELS-1];
    logic [AUDIO_CHANNELS-1:0] underflow_pulse;

    logic [7:0] stereo_disable;

    logic [9:0] pwm_accum_l;
    logic [9:0] pwm_accum_r;

    integer i;

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

    function automatic logic audio_addr_hit;
        input logic [7:0] addr;
        begin
            audio_addr_hit = ((addr >= AUDIO_BASE) && (addr <= AUDIO_END)) ||
                             (addr == MSTEREO);
        end
    endfunction

    function automatic logic [1:0] audio_chan_from_addr;
        input logic [7:0] addr;
        begin
            audio_chan_from_addr = addr[4:3];
        end
    endfunction

    function automatic logic [2:0] audio_reg_from_addr;
        input logic [7:0] addr;
        begin
            audio_reg_from_addr = addr[2:0];
        end
    endfunction

    function automatic logic polynomial_feedback_bit;
        input logic [11:0] sh;
        input logic [7:0]  fb;
        input logic        extra_tap;
        logic xor_value;
        begin
            xor_value = 1'b0;

            if (extra_tap) xor_value = xor_value ^ sh[7];

            if (fb[7]) xor_value = xor_value ^ sh[11];
            if (fb[6]) xor_value = xor_value ^ sh[10];
            if (fb[5]) xor_value = xor_value ^ sh[5];
            if (fb[4]) xor_value = xor_value ^ sh[4];
            if (fb[3]) xor_value = xor_value ^ sh[3];
            if (fb[2]) xor_value = xor_value ^ sh[2];
            if (fb[1]) xor_value = xor_value ^ sh[1];
            if (fb[0]) xor_value = xor_value ^ sh[0];

            polynomial_feedback_bit = ~xor_value;
        end
    endfunction

    function automatic logic [7:0] twos_complement8;
        input logic [7:0] value;
        begin
            twos_complement8 = (~value) + 8'd1;
        end
    endfunction

    function automatic logic signed [8:0] signed_extend8;
        input logic [7:0] value;
        begin
            signed_extend8 = $signed({value[7], value});
        end
    endfunction

    function automatic logic [7:0] signed_saturating_add8;
        input logic [7:0] a;
        input logic [7:0] b;
        logic signed [8:0] a_s;
        logic signed [8:0] b_s;
        logic signed [8:0] sum_s;
        begin
            a_s   = signed_extend8(a);
            b_s   = signed_extend8(b);
            sum_s = a_s + b_s;

            if (sum_s > 9'sd127) begin
                signed_saturating_add8 = 8'h7F;
            end else if (sum_s < -9'sd128) begin
                signed_saturating_add8 = 8'h80;
            end else begin
                signed_saturating_add8 = sum_s[7:0];
            end
        end
    endfunction

    function automatic logic signed [9:0] signed_output_sample;
        input logic [7:0] value;
        begin
            signed_output_sample = $signed({value[7], value}) <<< 1;
        end
    endfunction

    logic [7:0] addr_off;
    logic [1:0] wr_ch;
    logic [2:0] wr_reg;

    assign addr_off = cpu_addr;
    assign wr_ch    = audio_chan_from_addr(cpu_addr);
    assign wr_reg   = audio_reg_from_addr(cpu_addr);

    logic [AUDIO_CHANNELS-1:0] linked_tick;

    always_comb begin
        linked_tick[0] = timer7_link_tick;
        linked_tick[1] = underflow_pulse[0];
        linked_tick[2] = underflow_pulse[1];
        linked_tick[3] = underflow_pulse[2];
    end

    logic [AUDIO_CHANNELS-1:0] channel_tick;

    always_comb begin
        channel_tick = '0;

        for (int c = 0; c < AUDIO_CHANNELS; c = c + 1) begin
            if (control_reg[c][2:0] == 3'd7) begin
                channel_tick[c] = linked_tick[c];
            end else begin
                channel_tick[c] = (divcnt[c] == 16'd0);
            end
        end
    end

    logic [AUDIO_CHANNELS-1:0] poly_bit;

    always_comb begin
        for (int c = 0; c < AUDIO_CHANNELS; c = c + 1) begin
            poly_bit[c] = polynomial_feedback_bit(
                shift_reg[c],
                feedback_reg[c],
                control_reg[c][7]
            );
        end
    end

    always_comb begin
        sample_l = 10'sd0;
        sample_r = 10'sd0;

        for (int c = 0; c < AUDIO_CHANNELS; c = c + 1) begin
            if (!stereo_disable[4 + c]) begin
                sample_l = sample_l + (signed_output_sample(output_reg[c]) >>> 2);
            end

            if (!stereo_disable[c]) begin
                sample_r = sample_r + (signed_output_sample(output_reg[c]) >>> 2);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            stereo_disable  <= 8'h00;
            pwm_accum_l     <= 10'd0;
            pwm_accum_r     <= 10'd0;
            pwm_l           <= 1'b0;
            pwm_r           <= 1'b0;
            cpu_rdata       <= 8'h00;
            underflow_pulse <= '0;

            for (i = 0; i < AUDIO_CHANNELS; i = i + 1) begin
                volume_reg[i]   <= 8'h00;
                feedback_reg[i] <= 8'h00;
                output_reg[i]   <= 8'h00;
                backup_reg[i]   <= 8'h00;
                control_reg[i]  <= 8'h00;
                counter_reg[i]  <= 8'h00;
                shift_reg[i]    <= 12'h000;
                divcnt[i]       <= source_period_cycles(3'd0) - 16'd1;
            end
        end else begin
            underflow_pulse <= '0;

            pwm_accum_l <= pwm_accum_l[8:0] + {~sample_l[9], sample_l[8:0]};
            pwm_accum_r <= pwm_accum_r[8:0] + {~sample_r[9], sample_r[8:0]};
            pwm_l       <= pwm_accum_l[9];
            pwm_r       <= pwm_accum_r[9];

            for (i = 0; i < AUDIO_CHANNELS; i = i + 1) begin
                if (control_reg[i][2:0] == 3'd7) begin
                    divcnt[i] <= source_period_cycles(control_reg[i][2:0]) - 16'd1;
                end else if (control_reg[i][3]) begin
                    if (divcnt[i] == 16'd0) begin
                        divcnt[i] <= source_period_cycles(control_reg[i][2:0]) - 16'd1;
                    end else begin
                        divcnt[i] <= divcnt[i] - 16'd1;
                    end
                end else begin
                    divcnt[i] <= source_period_cycles(control_reg[i][2:0]) - 16'd1;
                end
            end

            for (i = 0; i < AUDIO_CHANNELS; i = i + 1) begin
                if (control_reg[i][3] && channel_tick[i]) begin
                    if (counter_reg[i] == 8'h00) begin
                        underflow_pulse[i] <= 1'b1;

                        if (control_reg[i][4]) begin
                            counter_reg[i] <= backup_reg[i];
                        end

                        if (control_reg[i][5]) begin
                            if (poly_bit[i]) begin
                                output_reg[i] <= signed_saturating_add8(
                                    output_reg[i],
                                    volume_reg[i]
                                );
                            end else begin
                                output_reg[i] <= signed_saturating_add8(
                                    output_reg[i],
                                    twos_complement8(volume_reg[i])
                                );
                            end
                        end else begin
                            if (poly_bit[i]) begin
                                output_reg[i] <= volume_reg[i];
                            end else begin
                                output_reg[i] <= twos_complement8(volume_reg[i]);
                            end
                        end

                        shift_reg[i] <= {poly_bit[i], shift_reg[i][11:1]};
                    end else begin
                        counter_reg[i] <= counter_reg[i] - 8'd1;
                    end
                end
            end

            if (cpu_cs && cpu_we && audio_addr_hit(addr_off)) begin
                if (addr_off == MSTEREO) begin
                    stereo_disable <= cpu_wdata;
                end else begin
                    unique case (wr_reg)
                        3'd0: begin
                            volume_reg[wr_ch] <= cpu_wdata;
                        end

                        3'd1: begin
                            feedback_reg[wr_ch] <= cpu_wdata;
                        end

                        3'd2: begin
                            output_reg[wr_ch] <= cpu_wdata;
                        end

                        3'd3: begin
                            shift_reg[wr_ch][7:0] <= cpu_wdata;
                        end

                        3'd4: begin
                            backup_reg[wr_ch] <= cpu_wdata;
                        end

                        3'd5: begin
                            control_reg[wr_ch] <= cpu_wdata;
                            divcnt[wr_ch]      <= source_period_cycles(cpu_wdata[2:0]) - 16'd1;
                        end

                        3'd6: begin
                            counter_reg[wr_ch] <= cpu_wdata;
                        end

                        3'd7: begin
                            shift_reg[wr_ch][11:8] <= cpu_wdata[7:4];
                        end

                        default: begin
                        end
                    endcase
                end
            end

            if (cpu_cs && !cpu_we && audio_addr_hit(addr_off)) begin
                if (addr_off == MSTEREO) begin
                    cpu_rdata <= stereo_disable;
                end else begin
                    unique case (audio_reg_from_addr(addr_off))
                        3'd0: begin
                            cpu_rdata <= volume_reg[audio_chan_from_addr(addr_off)];
                        end

                        3'd1: begin
                            cpu_rdata <= feedback_reg[audio_chan_from_addr(addr_off)];
                        end

                        3'd2: begin
                            cpu_rdata <= output_reg[audio_chan_from_addr(addr_off)];
                        end

                        3'd3: begin
                            cpu_rdata <= shift_reg[audio_chan_from_addr(addr_off)][7:0];
                        end

                        3'd4: begin
                            cpu_rdata <= backup_reg[audio_chan_from_addr(addr_off)];
                        end

                        3'd5: begin
                            cpu_rdata <= control_reg[audio_chan_from_addr(addr_off)];
                        end

                        3'd6: begin
                            cpu_rdata <= counter_reg[audio_chan_from_addr(addr_off)];
                        end

                        3'd7: begin
                            cpu_rdata <= {
                                shift_reg[audio_chan_from_addr(addr_off)][11:8],
                                1'b0,
                                divcnt[audio_chan_from_addr(addr_off)] == 16'd0,
                                1'b0,
                                underflow_pulse[audio_chan_from_addr(addr_off)]
                            };
                        end

                        default: begin
                            cpu_rdata <= 8'h00;
                        end
                    endcase
                end
            end
        end
    end

endmodule