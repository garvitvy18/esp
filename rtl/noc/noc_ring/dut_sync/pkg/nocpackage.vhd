------------------------------------------------------------------------------
--  This file is part of an extension to the GRLIB VHDL IP library.
--  Copyright (C) 2013, System Level Design (SLD) group @ Columbia University
--
--  GRLIP is a Copyright (C) 2008 - 2013, Aeroflex Gaisler
--
--  This program is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  To receive a copy of the GNU General Public License, write to the Free
--  Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
--  02111-1307  USA.
-----------------------------------------------------------------------------
-- Entity:  nocpackage
-- File:    nocpackage.vhd
-- Authors: Paolo Mantovani - SLD @ Columbia University
-- Description:	NoC constants declaration
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package nocpackage is

-------------------------------------------------------------------------------
-- RTL NOC constants and type
--
-- Addressing is XY; X: from left to right, Y: from top to bottom
--
-- Check the module "router" in router.vhd for details on routing algorithm
--
-------------------------------------------------------------------------------


  -- Header fields
  --
  -- |33        32|31     27|26     22|21     17|16     12|11          9|8          5|4   0|
  -- |  PREAMBLE  |  Src Y  |  Src X  |  Dst Y  |  Dst X  |  Msg. type  |  Reserved  |LEWSN|
  --

  constant HEADER_ROUTE_L : natural := 2;
  constant HEADER_ROUTE_E : natural := 1;
  constant HEADER_ROUTE_W : natural := 0;
--  constant HEADER_ROUTE_S : natural := 1;
 -- constant HEADER_ROUTE_N : natural := 0;
--   constant HEADER_ROUTE_S : natural := 1;
--   constant HEADER_ROUTE_N : natural := 0;

  constant PREAMBLE_WIDTH      : natural := 2;
  -- 3-bit coordinates/IDs (matches standalone ring testbench)
  constant YX_WIDTH            : natural := 3;
  -- Keep message width consistent with standalone ring NoC generator
  constant MSG_TYPE_WIDTH      : natural := 3;
  constant NEXT_ROUTING_WIDTH  : natural := 3;
  -- Layout (MSB->LSB): preamble | src_id | dst_id | msg | reserved | local_y | local_x | routing
  constant RESERVED_WIDTH      : natural := 14;
  constant NOC_FLIT_SIZE       : natural := PREAMBLE_WIDTH +
                                            2*YX_WIDTH +      -- src/dst ids
                                            MSG_TYPE_WIDTH +
                                            RESERVED_WIDTH +
                                            2*YX_WIDTH +      -- local_y/local_x
                                            NEXT_ROUTING_WIDTH;
  -- Total tiles in the ring (2x2 -> 4); keep configurable here if topology changes
  constant RING_LEN            : natural := 4;

  subtype local_yx is std_logic_vector(2 downto 0);
  subtype noc_preamble_type is std_logic_vector(PREAMBLE_WIDTH-1 downto 0);
  subtype noc_msg_type is std_logic_vector(MSG_TYPE_WIDTH-1 downto 0);
  subtype noc_flit_type is std_logic_vector(NOC_FLIT_SIZE-1 downto 0);
  subtype reserved_field_type is std_logic_vector(RESERVED_WIDTH-1 downto 0);

  type noc_flit_vector is array (natural range <>) of noc_flit_type;

  -- Preamble encoding
  constant PREAMBLE_HEADER : noc_preamble_type := "10";
  constant PREAMBLE_TAIL   : noc_preamble_type := "01";
  constant PREAMBLE_BODY   : noc_preamble_type := "00";
  constant PREAMBLE_1FLIT  : noc_preamble_type := "11";

  -- Message type encoding
  -- Cachable data plane 1 -> request messages
  constant REQ_GETS_B   : noc_msg_type := "000";  --Get Shared (Byte)
  constant REQ_GETS_HW  : noc_msg_type := "001";  --Get Shared (Half Word)
  constant REQ_GETS_W   : noc_msg_type := "010";  --Get Shared (word)
  constant REQ_GETM_B   : noc_msg_type := "011";  --Get Modified (Byte)
  constant REQ_GETM_HW  : noc_msg_type := "100";  --Get Modified (Half word)
  constant REQ_GETM_W   : noc_msg_type := "101";  --Get Modified (word)
  constant REQ_PUTS     : noc_msg_type := "110";  --Put Shared/Exclusive
  constant REQ_PUTM     : noc_msg_type := "111";  --Put Modified
  -- Cachable data plane 2 -> forwarded messages
  constant FWD_GETS     : noc_msg_type := "000";
  constant FWD_GETM     : noc_msg_type := "001";
  constant FWD_INV      : noc_msg_type := "010";  --Invalidation
  constant FWD_PUT_ACK  : noc_msg_type := "011";  --Put Acknowledge
  -- Cachable data plane 3 -> response messages
  constant RSP_DATA     : noc_msg_type := "000";  --CacheLine
  --constant RSP_EDATA    : noc_msg_type := "001";  --Cache Line (Exclusive)
  constant RSP_INV_ACK  : noc_msg_type := "010";  --Invalidation Acknowledge
  -- Non cachable data data plane 4 -> DMA transfers
  constant DMA_TO_DEV   : noc_msg_type := "001";
  constant DMA_FROM_DEV : noc_msg_type := "010";
  -- Configuration plane 5 -> RD/WR registers
  constant REQ_REG_RD   : noc_msg_type := "000";
  constant REQ_REG_WR   : noc_msg_type := "001";
  constant AHB_RD       : noc_msg_type := "010";
  constant AHB_WR       : noc_msg_type := "011";
  constant IRQ_MSG      : noc_msg_type := "100";
  constant RSP_REG_RD   : noc_msg_type := "101";
  constant INTERRUPT    : noc_msg_type := "111";

  constant ROUTE_NOC3 : std_logic_vector(1 downto 0) := "01";
  constant ROUTE_NOC4 : std_logic_vector(1 downto 0) := "10";
  constant ROUTE_NOC5 : std_logic_vector(1 downto 0) := "11";

  -- Ports routing encoding
  -- 4 = Local tile
  -- 3 = East
  -- 2 = West
  -- 1 = South
  -- 0 = North

  -- 0 = AN; 1 = CB
  constant FLOW_CONTROL : integer := 0;
  -- FIFOs depth
  constant ROUTER_DEPTH : integer := 4;

  type yx_vec is array (natural range <>) of std_logic_vector(2 downto 0);

  type tile_mem_info is record
                          x     : local_yx;
                          y     : local_yx;
                          haddr : integer;
                          hmask : integer;
                        end record;

  constant tile_mem_info_none : tile_mem_info := (
    x => (others => '0'),
    y => (others => '0'),
    haddr => 16#000#,
    hmask => 16#000#
    );

  -- TODO: For now we only support 2 memory controllers and one frame buffer
  type tile_mem_info_vector is array (2 downto 0) of tile_mem_info;

  -- Components
  component fifo
    generic (
      depth : integer;
      width : integer);
    port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      rdreq    : in  std_logic;
      wrreq    : in  std_logic;
      data_in  : in  std_logic_vector(width-1 downto 0);
      empty    : out std_logic;
      full     : out std_logic;
      data_out : out std_logic_vector(width-1 downto 0));
  end component;

  component fifo2
    generic (
      depth : integer;
      width : integer);
    port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      rdreq       : in  std_logic;
      wrreq       : in  std_logic;
      data_in     : in  std_logic_vector(width-1 downto 0);
      empty       : out std_logic;
      full        : out std_logic;
      atleast_4slots  : out std_logic;
      exactly_3slots  : out std_logic;
      data_out    : out std_logic_vector(width-1 downto 0));
  end component;

  component sync_noc_transmitter
    generic (
      DATA_WIDTH : integer := NOC_FLIT_SIZE);
    port(
      clock             : in std_logic;
      reset             : in std_logic;
      valid_in          : in std_logic;
      ack               : in std_logic;
      data_in           : in std_logic_vector(DATA_WIDTH-1 downto 0);
      chnl_stop         : in std_logic;
      req               : out std_logic;
      data_out          : out std_logic_vector(DATA_WIDTH-1 downto 0);
      stop_in           : out std_logic);
  end component;

  component sync_transmitter
    generic (
      DATA_WIDTH : integer := NOC_FLIT_SIZE);
    port(
      clock		: in std_logic;
      reset		: in std_logic;
      valid_in		: in std_logic;
      ack		: in std_logic;
      data_in 		: in std_logic_vector(DATA_WIDTH-1 downto 0);
      chnl_stop		: in std_logic;
      req       	: out std_logic;
      data_out		: out std_logic_vector(DATA_WIDTH-1 downto 0);
      stop_in		: out std_logic);
  end component;

  component sync_receiver
    generic (
      DATA_WIDTH : integer := NOC_FLIT_SIZE);
    port(
      clock		: in std_logic;
      reset		: in std_logic;
      req		: in std_logic;
      data_in 		: in std_logic_vector(DATA_WIDTH-1 downto 0);
      stop_out		: in std_logic;
      ack		: out std_logic;
      data_out		: out std_logic_vector(DATA_WIDTH-1 downto 0);
      valid_out		: out std_logic;
      chnl_stop		: out std_logic);
  end component;

  component sync_noc_receiver
    generic (
      DATA_WIDTH : integer := NOC_FLIT_SIZE);
    port(
      clock             : in std_logic;
      reset             : in std_logic;
      req               : in std_logic;
      data_in           : in std_logic_vector(DATA_WIDTH-1 downto 0);
      stop_out          : in std_logic;
      ack               : out std_logic;
      data_out          : out std_logic_vector(DATA_WIDTH-1 downto 0);
      valid_out         : out std_logic;
      chnl_stop         : out std_logic);
  end component;

  component inferred_async_fifo
    generic (
      g_data_width : natural := NOC_FLIT_SIZE;
      g_size       : natural := 6);
    port (
      rst_n_i    : in  std_logic := '1';
      clk_wr_i   : in  std_logic;
      we_i       : in  std_logic;
      d_i        : in  std_logic_vector(g_data_width-1 downto 0);
      wr_full_o  : out std_logic;
      clk_rd_i   : in  std_logic;
      rd_i       : in  std_logic;
      q_o        : out std_logic_vector(g_data_width-1 downto 0);
      rd_empty_o : out std_logic);
  end component;

  -- Helper functions
  function get_origin_y (
    flit : noc_flit_type)
    return local_yx;

  function get_origin_x (
    flit : noc_flit_type)
    return local_yx;

  function get_msg_type (
    flit : noc_flit_type)
    return noc_msg_type;

  function get_preamble (
    flit : noc_flit_type)
    return noc_preamble_type;

  function get_reserved_field (
    flit : noc_flit_type)
    return reserved_field_type;

  function is_gets (
    msg : noc_msg_type)
    return boolean;

  function is_getm (
    msg : noc_msg_type)
    return boolean;

  function idx_to_x (i : integer) return local_yx;
  function idx_to_y (i : integer) return local_yx;
  function get_hamiltonian_index (
    local_y : local_yx;
    local_x : local_yx)
    return integer;

  function create_header (
    local_y           : local_yx;
    local_x           : local_yx;
    remote_y          : local_yx;
    remote_x          : local_yx;
    msg_type          : noc_msg_type;
    reserved          : reserved_field_type)
    return noc_flit_type;

end nocpackage;

package body nocpackage is

  function get_origin_y (
    flit : noc_flit_type)
    return local_yx is
    variable ret : local_yx;
  begin  -- get_origin_y
    ret := flit(NOC_FLIT_SIZE - PREAMBLE_WIDTH - 1 downto
                NOC_FLIT_SIZE - PREAMBLE_WIDTH - YX_WIDTH);
    return ret;
  end get_origin_y;

  function get_origin_x (
    flit : noc_flit_type)
    return local_yx is
    variable ret : local_yx;
  begin  -- get_origin_x
    ret := flit(NOC_FLIT_SIZE - PREAMBLE_WIDTH - YX_WIDTH - 1 downto
                NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH);
    return ret;
  end get_origin_x;

  function get_msg_type (
    flit : noc_flit_type)
    return noc_msg_type is
    variable msg : noc_msg_type;
  begin
    msg := flit(NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - 1 downto
                NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH);
    return msg;
  end get_msg_type;

  function get_preamble (
    flit : noc_flit_type)
    return noc_preamble_type is
    variable ret : noc_preamble_type;
  begin
    ret := flit(NOC_FLIT_SIZE - 1 downto NOC_FLIT_SIZE - PREAMBLE_WIDTH);
    return ret;
  end get_preamble;

  function get_reserved_field (
    flit : noc_flit_type)
    return reserved_field_type is
    variable ret : reserved_field_type;
  begin
    ret := flit(NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH - 1 downto
                NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH);
    return ret;
  end get_reserved_field;

  function is_gets (
    msg : noc_msg_type)
    return boolean is
  begin
    if msg = REQ_GETS_W or msg = REQ_GETS_HW or msg = REQ_GETS_B then
      return true;
    else
      return false;
    end if;
  end is_gets;

  function is_getm (
    msg : noc_msg_type)
    return boolean is
  begin
    if msg = REQ_GETM_W or msg = REQ_GETM_HW or msg = REQ_GETM_B then
      return true;
    else
      return false;
    end if;
  end is_getm;

  function idx_to_x (
    i : integer)
    return local_yx is
  begin
    return std_logic_vector(to_unsigned(i mod RING_LEN, YX_WIDTH));
  end idx_to_x;

  function idx_to_y (
    i : integer)
    return local_yx is
  begin
    return std_logic_vector(to_unsigned(i / RING_LEN, YX_WIDTH));
  end idx_to_y;

  -- Column-serpentine Hamiltonian index (even columns 0->YLEN-1, odd columns YLEN-1->0)
  function get_hamiltonian_index (
    local_y : local_yx;
    local_x : local_yx)
    return integer is
    variable col_base : integer;
    variable ly       : integer;
    variable lx       : integer;
  begin
    lx := to_integer(unsigned(local_x));
    ly := to_integer(unsigned(local_y));
    col_base := lx * RING_LEN;
    if local_x(0) = '0' then
      return col_base + ly;
    else
      return col_base + (RING_LEN - 1 - ly);
    end if;
  end get_hamiltonian_index;

  function create_header (
     local_y           : local_yx;
    local_x           : local_yx;
     remote_y          : local_yx;
    remote_x          : local_yx;
    msg_type          : noc_msg_type;
    reserved          : reserved_field_type)
    return noc_flit_type is
    variable header : std_logic_vector(NOC_FLIT_SIZE - 1 downto 0);
    variable routing_bits : std_logic_vector(NEXT_ROUTING_WIDTH - 1 downto 0);
    variable id_loc, id_rem : integer;
    variable ring_len, dist_cw, dist_ccw : integer;
  begin  -- create_header
    header := (others => '0');
    ring_len := RING_LEN;

    -- Hamiltonian (column-serpentine) index
    id_loc := get_hamiltonian_index(local_y, local_x);
    id_rem := get_hamiltonian_index(remote_y, remote_x);

    -- Clamp IDs to ring length to avoid invalid destinations when inputs are out of range
    id_loc := id_loc mod ring_len;
    id_rem := id_rem mod ring_len;

    header(NOC_FLIT_SIZE - 1 downto
           NOC_FLIT_SIZE - PREAMBLE_WIDTH) := PREAMBLE_HEADER;
    header(NOC_FLIT_SIZE - PREAMBLE_WIDTH - 1 downto
           NOC_FLIT_SIZE - PREAMBLE_WIDTH - YX_WIDTH) := std_logic_vector(to_unsigned(id_loc, YX_WIDTH));
    header(NOC_FLIT_SIZE - PREAMBLE_WIDTH - YX_WIDTH - 1 downto
           NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH) := std_logic_vector(to_unsigned(id_rem, YX_WIDTH));
    header(NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - 1 downto
           NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH) := msg_type;
    header(NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH - 1 downto
           NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH) := reserved;
    -- Pack local_y/local_x just below reserved (keeps offsets aligned with standalone generator)
    header(NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH - 1 downto
           NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH - YX_WIDTH) := local_y;
    header(NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH - YX_WIDTH - 1 downto
           NOC_FLIT_SIZE - PREAMBLE_WIDTH - 2*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH - 2*YX_WIDTH) := local_x;

    -- Match standalone ring header generation (go_left/go_right then AND with 011)
    dist_cw  := (id_rem + ring_len - id_loc) mod ring_len;
    dist_ccw := (id_loc + ring_len - id_rem) mod ring_len;
    routing_bits := (others => '0');
    if id_loc < id_rem then
      routing_bits := "010";  -- go_right
    else
      routing_bits := "101";  -- mask out go_right
    end if;

    if id_loc > id_rem then
      routing_bits := routing_bits and "001"; -- go_left
    else
      routing_bits := routing_bits and "110";
    end if;

    routing_bits := routing_bits and "011";
    if id_loc = id_rem then
      routing_bits := "100";
    end if;

    header(NEXT_ROUTING_WIDTH - 1 downto 0) := routing_bits;

    return header;
  end create_header;


end nocpackage;
