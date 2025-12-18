-- Copyright (c) 2011-2025 Columbia University, System Level Design Group
-- SPDX-License-Identifier: Apache-2.0

-------------------------------------------------------------------------------
-- Module:      noc_xy
-- Description: Mesh of x columns by y rows RTL routers
--
-- Author:      Paolo Mantovani @ Columbia University
-------------------------------------------------------------------------------
--
-- Addressing is XY; X: from left to right, Y: from top to bottom
--
-- Local mapping for the latency insensitive protocol
-- 0 = North
-- 1 = South
-- 2 = West
-- 3 = East
-- 4 = Local tile
--
-- Check the module "router" in router.vhd for details on routing algorithm
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.monitor_pkg.all;
use work.nocpackage.all;

entity noc32_xy is
  generic (
    XLEN      : integer;
    YLEN      : integer;
    TILES_NUM : integer);
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    input_port    : in  misc_noc_flit_vector(TILES_NUM-1 downto 0);
    data_void_in  : in  std_logic_vector(TILES_NUM-1 downto 0);
    stop_in       : in  std_logic_vector(TILES_NUM-1 downto 0);
    output_port   : out misc_noc_flit_vector(TILES_NUM-1 downto 0);
    data_void_out : out std_logic_vector(TILES_NUM-1 downto 0);
    stop_out      : out std_logic_vector(TILES_NUM-1 downto 0);
    -- Monitor output. Can be left unconnected
    mon_noc       : out monitor_noc_vector(0 to TILES_NUM-1)
    );

end noc32_xy;

architecture ring of noc32_xy is

  type ports_vec is array (TILES_NUM-1 downto 0) of std_logic_vector(2 downto 0);
  type local_vec is array (TILES_NUM-1 downto 0) of local_yx;
  type handshake_vec is array (TILES_NUM-1 downto 0) of
    std_logic_vector(2 downto 0);
  type int_vec is array (natural range <>) of integer;

  function set_router_ports(
    constant XLEN : integer;
    constant YLEN : integer)
    return ports_vec is
    variable ports : ports_vec;
  begin
    ports := (others => (others => '0'));
    --   0,0    - 0,1 - 0,2 - ... -    0,XLEN-1
    --    |        |     |     |          |
    --   1,0    - ...   ...   ... -    1,XLEN-1
    --    |        |     |     |          |
    --   ...    - ...   ...   ... -      ...
    --    |        |     |     |          |
    -- YLEN-1,0 - ...   ...   ... - YLEN-1,XLEN-1
    -- for i in 0 to YLEN-1 loop
      for i in 0 to (XLEN*YLEN)-1 loop
        -- local ports are all set
        ports(i)(2) := '1';
       -- if i /= XLEN-1 then
          -- east ports
        ports(i)(1) := '1';
       -- end if;
       -- if j /= 0 then
          -- west ports
          ports(i)(0) := '1';
       -- end if;
      --  if i /= YLEN-1 then
      --    -- south ports
      --    ports(i * XLEN + j)(1) := '1';
      --  end if;
      --  if i /= 0 then
      --    -- north ports
      --    ports(i * XLEN + j)(0) := '1';
      --  end if;
      -- end loop;  -- j
    end loop;  -- i
    return ports;
  end set_router_ports;

--  function set_tile_x (
--    constant XLEN : integer;
--    constant YLEN : integer;
--    constant id_bits  : integer)
--    return local_vec is
--    variable x : local_vec;
--  begin  -- set_tile_id
--    for i in 0 to YLEN-1 loop
--      for j in 0 to XLEN-1 loop
--        x(i * XLEN + j) := conv_std_logic_vector(j, id_bits);
--      end loop;  -- j
--    end loop;  -- i
--    return x;
--  end set_tile_x;
  function set_tile_x (
    constant XLEN : integer;
    constant YLEN : integer;
    constant id_bits  : integer)
    return local_vec is
    variable x : local_vec;
  begin  -- set_tile_id
    --for i in 0 to YLEN-1 loop
      for i in 0 to TILES_NUM-1 loop
        x(i) := conv_std_logic_vector(i, id_bits);
      end loop;  -- j
   -- end loop;  -- i
    return x;
  end set_tile_x;

--  function set_tile_y (
--    constant XLEN : integer;
--    constant YLEN : integer;
--    constant id_bits  : integer)
--    return local_vec is
--    variable y : local_vec;
--  begin  -- set_tile_id
--    for i in 0 to YLEN-1 loop
--      for j in 0 to XLEN-1 loop
--        y(i * XLEN + j) := conv_std_logic_vector(i, id_bits);
--      end loop;  -- j
--    end loop;  -- i
--    return y;
--  end set_tile_y;
-- Row-major mapping from (x,y) to linear tile ID
  function id_of_xy(x, y, XLEN : integer) return integer is
  begin
    return y*XLEN + x;
  end;

function build_ring_order(XLEN, YLEN : integer) return int_vec is
  variable order : int_vec(0 to XLEN*YLEN-1);
  variable p     : integer := 0;
begin
  for x in 0 to XLEN-1 loop
    if (x mod 2) = 0 then
      for y in 0 to YLEN-1 loop
        order(p) := id_of_xy(x, y, XLEN);  p := p + 1;
      end loop;
    else
      for y in YLEN-1 downto 0 loop
        order(p) := id_of_xy(x, y, XLEN);  p := p + 1;
      end loop;
    end if;
  end loop;
  return order;
end;


  -- For each tile k, who is the next tile on the ring?
  function build_next_of(order : int_vec) return int_vec is
    variable next_of : int_vec(0 to order'length-1);
    variable N       : integer := order'length;
  begin
    for i in 0 to N-1 loop
      next_of(order(i)) := order((i+1) mod N);
    end loop;
    return next_of;
  end;

  -- For each tile k, who is the previous tile on the ring?
  function build_prev_of(order : int_vec) return int_vec is
    variable prev_of : int_vec(0 to order'length-1);
    variable N       : integer := order'length;
    variable pm1     : integer;
  begin
    for i in 0 to N-1 loop
      pm1 := (i-1+N) mod N;
      prev_of(order(i)) := order(pm1);
    end loop;
    return prev_of;
  end;

function build_ring_localx(order : int_vec) return local_vec is
  variable v : local_vec;  -- local_vec is already constrained by TILES_NUM
begin
  for i in 0 to order'length-1 loop
    v(order(i)) := conv_std_logic_vector(i, YX_WIDTH);
  end loop;
  return v;
end;
  constant ROUTER_PORTS : ports_vec := set_router_ports(XLEN, YLEN);
  constant RING_ORDER : int_vec(0 to TILES_NUM-1) := build_ring_order(XLEN, YLEN);
  constant RING_NEXT  : int_vec(0 to TILES_NUM-1) := build_next_of(RING_ORDER);
  constant RING_PREV  : int_vec(0 to TILES_NUM-1) := build_prev_of(RING_ORDER);
--  constant localy       : local_vec := set_tile_y(XLEN, YLEN, 3);
  -- Keep the SAME constant name 'ring_coord' but auto-generate it now
  constant ring_coord : local_vec := build_ring_localx(RING_ORDER);
  constant flit_size  : integer := MISC_NOC_FLIT_SIZE;

 component router
    generic (
      flow_control : integer;
      width        : integer;
      depth        : integer;
      ports        : std_logic_vector(2 downto 0));
    port (
      clk           : in  std_logic;
      rst           : in  std_logic;
      CONST_localx  : in  std_logic_vector(2 downto 0);
--      CONST_localy  : in  std_logic_vector(2 downto 0);
     -- data_n_in     : in  std_logic_vector(width-1 downto 0);
     -- data_s_in     : in  std_logic_vector(width-1 downto 0);
      data_w_in     : in  std_logic_vector(width-1 downto 0);
      data_e_in     : in  std_logic_vector(width-1 downto 0);
      data_p_in     : in  std_logic_vector(width-1 downto 0);
      data_void_in  : in  std_logic_vector(2 downto 0);
      stop_in       : in  std_logic_vector(2 downto 0);
    --  data_n_out    : out std_logic_vector(width-1 downto 0);
    --  data_s_out    : out std_logic_vector(width-1 downto 0);
      data_w_out    : out std_logic_vector(width-1 downto 0);
      data_e_out    : out std_logic_vector(width-1 downto 0);
      data_p_out    : out std_logic_vector(width-1 downto 0);
      data_void_out : out std_logic_vector(2 downto 0);
      stop_out      : out std_logic_vector(2 downto 0));
  end component;

 -- signal data_n_in     : misc_noc_flit_vector(TILES_NUM-1 downto 0);
 -- signal data_s_in     : misc_noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_w_in     : misc_noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_e_in     : misc_noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_p_in     : misc_noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_void_in_i  : handshake_vec;
  signal stop_in_i       : handshake_vec;
 -- signal data_n_out    : misc_noc_flit_vector(TILES_NUM-1 downto 0);
 -- signal data_s_out    : misc_noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_w_out    : misc_noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_e_out    : misc_noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_p_out    : misc_noc_flit_vector(TILES_NUM-1 downto 0);
  signal data_void_out_i : handshake_vec;
  signal stop_out_i      : handshake_vec;
  -- Debug helper: flag invalid 3'b011 routing injected from tiles
  -- (same instrumentation used in noc_ring/dut_sync/noc_xy.vhd)

begin
  -- Generic ring wiring for any XLEN×YLEN:
  -- West input of k comes from East output of PREV(k)
  -- East input of k comes from West output of NEXT(k)
  ring_wiring: for k in 0 to TILES_NUM-1 generate
    constant nxt : integer := RING_NEXT(k);
    constant prv : integer := RING_PREV(k);
  begin

    -- W lane (index 0) is driven by E lane (index 1) of PREV
    data_w_in(k)         <= data_e_out(prv);
    data_void_in_i(k)(0) <= data_void_out_i(prv)(1);
    stop_in_i(k)(0)      <= stop_out_i(prv)(1);

    -- E lane (index 1) is driven by W lane (index 0) of NEXT
    data_e_in(k)         <= data_w_out(nxt);
    data_void_in_i(k)(1) <= data_void_out_i(nxt)(0);
    stop_in_i(k)(1)      <= stop_out_i(nxt)(0);
  end generate;


  routerinst: for k in 0 to TILES_NUM-1 generate
    data_p_in(k) <= input_port(k);
    output_port(k) <= data_p_out(k);

    data_void_in_i(k)(2) <= data_void_in(k);
    stop_in_i(k)(2) <= stop_in(k);
    data_void_out(k) <= data_void_out_i(k)(2);
    stop_out(k) <= stop_out_i(k)(2);

    router_ij: router
        generic map (
          flow_control => FLOW_CONTROL,
          width        => flit_size,
          depth        => ROUTER_DEPTH,
          ports        => ROUTER_PORTS(k))
      port map (
          clk           => clk,
          rst           => rst,
          CONST_localx  => ring_coord(k)(2 downto 0),
--          CONST_localy  => localy(k),
         -- data_n_in     => data_n_in(k),
         -- data_s_in     => data_s_in(k),
          data_w_in     => data_w_in(k),
          data_e_in     => data_e_in(k),
          data_p_in     => data_p_in(k),
          data_void_in  => data_void_in_i(k),
          stop_in       => stop_in_i(k),
         -- data_n_out    => data_n_out(k),
         -- data_s_out    => data_s_out(k),
          data_w_out    => data_w_out(k),
          data_e_out    => data_e_out(k),
          data_p_out    => data_p_out(k),
          data_void_out => data_void_out_i(k),
          stop_out      => stop_out_i(k));

    -- Monitor signals
    mon_noc(k).clk          <= clk;
    mon_noc(k).tile_inject  <= not data_void_in(k);

    mon_noc(k).queue_full(2) <= data_void_out_i(k)(2) nand data_void_in_i(k)(2);
    mon_noc(k).queue_full(1) <= not data_void_out_i(k)(1);
    mon_noc(k).queue_full(0) <= not data_void_out_i(k)(0);
  --  mon_noc(k).queue_full(1) <= not data_void_out_i(k)(1);
  --  mon_noc(k).queue_full(0) <= not data_void_out_i(k)(0);
--    mon_noc(k).queue_full   <= (stop_out_i(k) or stop_in_i(k)) and ROUTER_PORTS(k);

    -- Debug: flag invalid routing (multiple bits) injected from tile k
    debug_invalid_routing: process(clk)
      variable src_id, dst_id, msg_val : integer;
    begin
      if rising_edge(clk) then
        if rst = '0' then
          if data_void_in(k) = '0' and data_p_in(k)(NEXT_ROUTING_WIDTH-1 downto 0) = "011" then
            src_id  := to_integer(unsigned(data_p_in(k)(flit_size - PREAMBLE_WIDTH - 1 downto flit_size - PREAMBLE_WIDTH - RING_ID_WIDTH)));
            dst_id  := to_integer(unsigned(data_p_in(k)(flit_size - PREAMBLE_WIDTH - RING_ID_WIDTH - 1 downto flit_size - PREAMBLE_WIDTH - 2*RING_ID_WIDTH)));
            msg_val := to_integer(unsigned(data_p_in(k)(flit_size - PREAMBLE_WIDTH - 2*RING_ID_WIDTH - 1 downto flit_size - PREAMBLE_WIDTH - 2*RING_ID_WIDTH - MSG_TYPE_WIDTH)));
            report "[NOC_RING_DBG] tile=" & integer'image(k) &
                   " ring_id=" & integer'image(to_integer(unsigned(ring_coord(k)(2 downto 0)))) &
                   " src_id=" & integer'image(src_id) &
                   " dst_id=" & integer'image(dst_id) &
                   " msg=" & integer'image(msg_val) &
                   " routing=011"
              severity note;
          end if;
        end if;
      end if;
    end process debug_invalid_routing;
  end generate routerinst;

end ring;
