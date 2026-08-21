`timescale 1ns/1ps

module lynx_cpu_bus_bridge (
    input  logic        clk,
    input  logic        reset,

    input  logic        dma_stall,

    input  logic        cpu_bus_request,
    input  logic        cpu_bus_rnw,
    input  logic [15:0] cpu_bus_addr,
    input  logic  [7:0] cpu_bus_datawrite,

    output logic  [7:0] cpu_bus_dataread,
    output logic        cpu_bus_done,

    output logic        core_cpu_cs,
    output logic        core_cpu_we,
    output logic [15:0] core_cpu_addr,
    output logic  [7:0] core_cpu_wdata,
    input  logic  [7:0] core_cpu_rdata
);

    typedef enum logic [3:0] {
        S_IDLE,

        S_WRITE_PULSE,
        S_WRITE_DONE,

        S_READ_SETUP,
        S_READ_WAIT_0,
        S_READ_WAIT_1,

        S_CART_WAIT_0,
        S_CART_WAIT_1,
        S_CART_WAIT_2,
        S_CART_WAIT_3,

        S_DONE,
        S_WAIT_RELEASE
    } state_t;

    state_t state;

    logic        latched_rnw;
    logic [15:0] latched_addr;
    logic [7:0]  latched_wdata;
    logic [7:0]  read_latch;

    logic is_cart_read;

    assign is_cart_read =
        latched_rnw &&
        ((latched_addr == 16'hFCB2) || (latched_addr == 16'hFCB3));

    always_comb begin
        core_cpu_cs    = 1'b0;
        core_cpu_we    = 1'b0;
        core_cpu_addr  = latched_addr;
        core_cpu_wdata = latched_wdata;

        if (!dma_stall) begin
            case (state)

                S_WRITE_PULSE: begin
                    core_cpu_cs    = 1'b1;
                    core_cpu_we    = 1'b1;
                    core_cpu_addr  = latched_addr;
                    core_cpu_wdata = latched_wdata;
                end

                S_READ_SETUP,
                S_READ_WAIT_0,
                S_READ_WAIT_1,
                S_CART_WAIT_0,
                S_CART_WAIT_1,
                S_CART_WAIT_2,
                S_CART_WAIT_3: begin
                    core_cpu_cs    = 1'b1;
                    core_cpu_we    = 1'b0;
                    core_cpu_addr  = latched_addr;
                    core_cpu_wdata = latched_wdata;
                end

                default: begin
                    core_cpu_cs    = 1'b0;
                    core_cpu_we    = 1'b0;
                    core_cpu_addr  = latched_addr;
                    core_cpu_wdata = latched_wdata;
                end
            endcase
        end
    end

    assign cpu_bus_dataread = read_latch;
    assign cpu_bus_done     = (state == S_DONE) && !dma_stall;

    always_ff @(posedge clk) begin
        if (reset) begin
            state         <= S_IDLE;

            latched_rnw   <= 1'b1;
            latched_addr  <= 16'h0000;
            latched_wdata <= 8'h00;
            read_latch    <= 8'h00;
        end else begin
            case (state)

                S_IDLE: begin
                    if (!dma_stall && cpu_bus_request) begin
                        latched_rnw   <= cpu_bus_rnw;
                        latched_addr  <= cpu_bus_addr;
                        latched_wdata <= cpu_bus_datawrite;

                        if (cpu_bus_rnw) begin
                            state <= S_READ_SETUP;
                        end else begin
                            state <= S_WRITE_PULSE;
                        end
                    end
                end

                S_WRITE_PULSE: begin
                    state <= S_WRITE_DONE;
                end

                S_WRITE_DONE: begin
                    if (!dma_stall) begin
                        state <= S_DONE;
                    end
                end

                S_READ_SETUP: begin
                    if (!dma_stall) begin
                        state <= S_READ_WAIT_0;
                    end
                end

                S_READ_WAIT_0: begin
                    if (!dma_stall) begin
                        state <= S_READ_WAIT_1;
                    end
                end

                S_READ_WAIT_1: begin
                    if (!dma_stall) begin
                        if (is_cart_read) begin
                            state <= S_CART_WAIT_0;
                        end else begin
                            read_latch <= core_cpu_rdata;
                            state      <= S_DONE;
                        end
                    end
                end

                S_CART_WAIT_0: begin
                    if (!dma_stall) begin
                        state <= S_CART_WAIT_1;
                    end
                end

                S_CART_WAIT_1: begin
                    if (!dma_stall) begin
                        state <= S_CART_WAIT_2;
                    end
                end

                S_CART_WAIT_2: begin
                    if (!dma_stall) begin
                        state <= S_CART_WAIT_3;
                    end
                end

                S_CART_WAIT_3: begin
                    if (!dma_stall) begin
                        read_latch <= core_cpu_rdata;
                        state      <= S_DONE;
                    end
                end

                S_DONE: begin
                    state <= S_WAIT_RELEASE;
                end

                S_WAIT_RELEASE: begin
                    if (!cpu_bus_request) begin
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule