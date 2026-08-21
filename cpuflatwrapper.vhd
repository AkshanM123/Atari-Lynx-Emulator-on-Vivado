library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.pexport.all;
use work.pBus_savestates.all;
use work.pReg_savestates.all;

entity cpu_flat_wrapper is
   port (
      clk           : in  std_logic;
      ce            : in  std_logic;
      reset         : in  std_logic;

      cpu_idle      : out std_logic;
      dma_active    : in  std_logic;
      cpu_sleep     : in  std_logic;

      bus_request   : out std_logic;
      bus_rnw       : out std_logic;
      bus_addr      : out std_logic_vector(15 downto 0);
      bus_datawrite : out std_logic_vector(7 downto 0);
      bus_dataread  : in  std_logic_vector(7 downto 0);
      bus_done      : in  std_logic;

      irqrequest_in : in  std_logic;
      irqclear_in   : in  std_logic;
      irqdisabled   : out std_logic;
      irqpending    : out std_logic;
      irqfinish     : out std_logic;

      load_savestate : in  std_logic;
      custom_PCAddr  : in  std_logic_vector(15 downto 0);
      custom_PCuse   : in  std_logic;

      cpu_done      : out std_logic;

      dbg_PC              : out std_logic_vector(15 downto 0);
      dbg_RegA            : out std_logic_vector(7 downto 0);
      dbg_RegX            : out std_logic_vector(7 downto 0);
      dbg_RegY            : out std_logic_vector(7 downto 0);
      dbg_RegS            : out std_logic_vector(7 downto 0);
      dbg_RegP            : out std_logic_vector(7 downto 0);
      dbg_FlagNeg         : out std_logic;
      dbg_FlagOvf         : out std_logic;
      dbg_FlagBrk         : out std_logic;
      dbg_FlagDez         : out std_logic;
      dbg_FlagIrq         : out std_logic;
      dbg_FlagZer         : out std_logic;
      dbg_FlagCar         : out std_logic;
      dbg_sleep           : out std_logic;
      dbg_irqrequest      : out std_logic;
      dbg_opcodebyte_last : out std_logic_vector(7 downto 0)
   );
end entity;

architecture rtl of cpu_flat_wrapper is
   signal cpu_export_s  : cpu_export_type;
   signal cpu_bus_addr  : unsigned(15 downto 0);

   signal ssbus_din  : std_logic_vector(SSBUS_buswidth-1 downto 0) := (others => '0');
   signal ssbus_adr  : std_logic_vector(SSBUS_busadr-1 downto 0)   := (others => '0');
   signal ssbus_wren : std_logic := '0';
   signal ssbus_rst  : std_logic := '0';
   signal ssbus_dout : std_logic_vector(SSBUS_buswidth-1 downto 0);
begin

   u_cpu : entity work.cpu
      port map (
         clk            => clk,
         ce             => ce,
         reset          => reset,

         cpu_idle       => cpu_idle,
         dma_active     => dma_active,
         cpu_sleep      => cpu_sleep,

         bus_request    => bus_request,
         bus_rnw        => bus_rnw,
         bus_addr       => cpu_bus_addr,
         bus_datawrite  => bus_datawrite,
         bus_dataread   => bus_dataread,
         bus_done       => bus_done,

         irqrequest_in  => irqrequest_in,
         irqclear_in    => irqclear_in,
         irqdisabled    => irqdisabled,
         irqpending     => irqpending,
         irqfinish      => irqfinish,

         load_savestate => load_savestate,
         custom_PCAddr  => custom_PCAddr,
         custom_PCuse   => custom_PCuse,

         cpu_done       => cpu_done,
         cpu_export     => cpu_export_s,

         SSBUS_Din      => ssbus_din,
         SSBUS_Adr      => ssbus_adr,
         SSBUS_wren     => ssbus_wren,
         SSBUS_rst      => ssbus_rst,
         SSBUS_Dout     => ssbus_dout
      );

   bus_addr <= std_logic_vector(cpu_bus_addr);

   dbg_PC              <= std_logic_vector(cpu_export_s.PC);
   dbg_RegA            <= std_logic_vector(cpu_export_s.RegA);
   dbg_RegX            <= std_logic_vector(cpu_export_s.RegX);
   dbg_RegY            <= std_logic_vector(cpu_export_s.RegY);
   dbg_RegS            <= std_logic_vector(cpu_export_s.RegS);
   dbg_RegP            <= std_logic_vector(cpu_export_s.RegP);
   dbg_FlagNeg         <= cpu_export_s.FlagNeg;
   dbg_FlagOvf         <= cpu_export_s.FlagOvf;
   dbg_FlagBrk         <= cpu_export_s.FlagBrk;
   dbg_FlagDez         <= cpu_export_s.FlagDez;
   dbg_FlagIrq         <= cpu_export_s.FlagIrq;
   dbg_FlagZer         <= cpu_export_s.FlagZer;
   dbg_FlagCar         <= cpu_export_s.FlagCar;
   dbg_sleep           <= cpu_export_s.sleep;
   dbg_irqrequest      <= cpu_export_s.irqrequest;
   dbg_opcodebyte_last <= cpu_export_s.opcodebyte_last;

end architecture;