`timescale 1ns/1ps

module lynx_addr_decode (
    input  logic [15:0] cpu_addr,
    input  logic  [7:0] mapctl,

    output logic        sel_ram,
    output logic        sel_suzy,
    output logic        sel_mikey,
    output logic        sel_rom,
    output logic        sel_bios,
    output logic        sel_mapctl,
    output logic        sel_vector,

    output logic        is_suzy_range,
    output logic        is_mikey_range,
    output logic        is_rom_range,
    output logic        is_bios_range,
    output logic        is_vector_range
);

    always_comb begin
        is_suzy_range   = (cpu_addr >= 16'hFC00) && (cpu_addr <= 16'hFCFF);
        is_mikey_range  = (cpu_addr >= 16'hFD00) && (cpu_addr <= 16'hFDFF);
        is_bios_range   = (cpu_addr >= 16'hFE00) && (cpu_addr <= 16'hFFFF);
        is_vector_range = (cpu_addr >= 16'hFFFA) && (cpu_addr <= 16'hFFFF);

        is_rom_range = 1'b0;

        sel_mapctl = (cpu_addr == 16'hFFF9);

        sel_suzy = is_suzy_range && !mapctl[0];
        sel_mikey = is_mikey_range && !mapctl[1];

        sel_vector = is_vector_range && !sel_mapctl && !mapctl[3];

        sel_bios = is_bios_range &&
                   !sel_mapctl &&
                   !sel_vector &&
                   !(cpu_addr == 16'hFFF8) &&
                   (is_vector_range ? !mapctl[3] : !mapctl[2]);

        sel_rom = 1'b0;

        sel_ram = (cpu_addr == 16'hFFF8) ||
                  (is_suzy_range && mapctl[0]) ||
                  (is_mikey_range && mapctl[1]) ||
                  (is_bios_range && !is_vector_range && !sel_mapctl && mapctl[2]) ||
                  (is_vector_range && !sel_mapctl && mapctl[3]) ||
                  (!is_suzy_range && !is_mikey_range && !is_bios_range && !sel_mapctl && !sel_rom);
    end

endmodule