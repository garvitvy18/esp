
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.sldcommon.all;
use work.nocpackage.all;


entity sync_wrap is
  generic (
    XLEN      : integer := 4;
    YLEN      : integer := 0;
    TILES_NUM : integer := 4;
    flit_size : integer := 34);

  port (
    clk           : in  std_logic;
    rstn          : in  std_logic;
    input_data_i  : in  std_logic_vector(flit_size*TILES_NUM-1 downto 0);
    input_req_i   : in  std_logic_vector(TILES_NUM-1 downto 0);
    input_ack_o   : out std_logic_vector(TILES_NUM-1 downto 0);
    output_data_o : out std_logic_vector(flit_size*TILES_NUM-1 downto 0);
    output_req_o  : out std_logic_vector(TILES_NUM-1 downto 0);
    output_ack_i  : in  std_logic_vector(TILES_NUM-1 downto 0)
    );


end sync_wrap;


architecture rtl of sync_wrap is

  signal input_data  : noc_flit_vector(TILES_NUM-1 downto 0);
  signal output_data : noc_flit_vector(TILES_NUM-1 downto 0);

  component noc_xy is
    generic (
      XLEN      : integer;
      YLEN      : integer;
      TILES_NUM : integer;
      flit_size : integer);
    port (
      clk           : in  std_logic;
      rst           : in  std_logic;
      input_port    : in  noc_flit_vector(TILES_NUM-1 downto 0);
      data_void_in  : in  std_logic_vector(TILES_NUM-1 downto 0);
      stop_in       : in  std_logic_vector(TILES_NUM-1 downto 0);
      output_port   : out noc_flit_vector(TILES_NUM-1 downto 0);
      data_void_out : out std_logic_vector(TILES_NUM-1 downto 0);
      stop_out      : out std_logic_vector(TILES_NUM-1 downto 0);
      mon_noc       : out monitor_noc_vector(0 to TILES_NUM-1));
  end component noc_xy;

  signal input_port    : noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_void_in  : std_logic_vector(TILES_NUM-1 downto 0);
  signal stop_in       : std_logic_vector(TILES_NUM-1 downto 0);
  signal output_port   : noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_void_out : std_logic_vector(TILES_NUM-1 downto 0);
  signal stop_out      : std_logic_vector(TILES_NUM-1 downto 0);
  signal mon_noc       : monitor_noc_vector(0 to TILES_NUM-1);

begin

  noc_xy_1: noc_xy
    generic map (
      XLEN      => XLEN,
      YLEN      => YLEN,
      TILES_NUM => TILES_NUM,
      flit_size => flit_size)
    port map (
      clk           => clk,
      rst           => rstn,
      input_port    => input_port,
      data_void_in  => data_void_in,
      stop_in       => stop_in,
      output_port   => output_port,
      data_void_out => data_void_out,
      stop_out      => stop_out,
      mon_noc       => mon_noc);

  input_port      <= input_data;
  data_void_in    <= not input_req_i;
  input_ack_o     <= not stop_out;

  output_data   <= output_port;
  output_req_o    <= not data_void_out;
  stop_in         <= not output_ack_i;

  array_to_packed_vector: for i in TILES_NUM-1 downto 0 generate
    output_data_o((i + 1) * flit_size - 1 downto i * flit_size) <= output_data(i);
    input_data(i) <= input_data_i((i + 1) * flit_size - 1 downto flit_size * i);
  end generate array_to_packed_vector;

end;
