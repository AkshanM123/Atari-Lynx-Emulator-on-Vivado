module cpu_wrapper (
    input  logic        clk,
    input  logic        ce,
    input  logic        reset,

    output logic        cpu_idle,
    input  logic        dma_active,
    input  logic        cpu_sleep,

    output logic        bus_request,
    output logic        bus_rnw,
    output logic [15:0] bus_addr,
    output logic [7:0]  bus_datawrite,
    input  logic [7:0]  bus_dataread,
    input  logic        bus_done,

    input  logic        irqrequest_in,
    input  logic        irqclear_in,
    output logic        irqdisabled,
    output logic        irqpending,
    output logic        irqfinish,

    input  logic        load_savestate,
    input  logic [15:0] custom_PCAddr,
    input  logic        custom_PCuse,

    output logic        cpu_done,

    output logic [15:0] dbg_PC,
    output logic [7:0]  dbg_RegA,
    output logic [7:0]  dbg_RegX,
    output logic [7:0]  dbg_RegY,
    output logic [7:0]  dbg_RegS,
    output logic [7:0]  dbg_RegP,
    output logic        dbg_FlagNeg,
    output logic        dbg_FlagOvf,
    output logic        dbg_FlagBrk,
    output logic        dbg_FlagDez,
    output logic        dbg_FlagIrq,
    output logic        dbg_FlagZer,
    output logic        dbg_FlagCar,
    output logic        dbg_sleep,
    output logic        dbg_irqrequest,
    output logic [7:0]  dbg_opcodebyte_last
);

    cpu_flat_wrapper u_cpu_flat (
        .clk(clk),
        .ce(ce),
        .reset(reset),

        .cpu_idle(cpu_idle),
        .dma_active(dma_active),
        .cpu_sleep(cpu_sleep),

        .bus_request(bus_request),
        .bus_rnw(bus_rnw),
        .bus_addr(bus_addr),
        .bus_datawrite(bus_datawrite),
        .bus_dataread(bus_dataread),
        .bus_done(bus_done),

        .irqrequest_in(irqrequest_in),
        .irqclear_in(irqclear_in),
        .irqdisabled(irqdisabled),
        .irqpending(irqpending),
        .irqfinish(irqfinish),

        .load_savestate(load_savestate),
        .custom_PCAddr(custom_PCAddr),
        .custom_PCuse(custom_PCuse),

        .cpu_done(cpu_done),

        .dbg_PC(dbg_PC),
        .dbg_RegA(dbg_RegA),
        .dbg_RegX(dbg_RegX),
        .dbg_RegY(dbg_RegY),
        .dbg_RegS(dbg_RegS),
        .dbg_RegP(dbg_RegP),
        .dbg_FlagNeg(dbg_FlagNeg),
        .dbg_FlagOvf(dbg_FlagOvf),
        .dbg_FlagBrk(dbg_FlagBrk),
        .dbg_FlagDez(dbg_FlagDez),
        .dbg_FlagIrq(dbg_FlagIrq),
        .dbg_FlagZer(dbg_FlagZer),
        .dbg_FlagCar(dbg_FlagCar),
        .dbg_sleep(dbg_sleep),
        .dbg_irqrequest(dbg_irqrequest),
        .dbg_opcodebyte_last(dbg_opcodebyte_last)
    );

endmodule