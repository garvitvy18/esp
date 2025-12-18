-- Copyright (c) 2011-2025 Columbia University, System Level Design Group
-- SPDX-License-Identifier: Apache-2.0

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use work.esp_global.all;
use work.amba.all;
use work.stdlib.all;
use work.sld_devices.all;
use work.devices.all;
use work.gencomp.all;
use work.leon3.all;
use work.net.all;
-- pragma translate_off
use work.sim.all;
library unisim;
use unisim.all;
-- pragma translate_on
use work.monitor_pkg.all;
use work.sldacc.all;
use work.tile.all;
use work.nocpackage.all;
use work.cachepackage.all;
use work.coretypes.all;
use work.grlib_config.all;
use work.socmap.all;
use work.tiles_pkg.all;
use work.tiles_fpga_pkg.all;

entity esp is
  generic (
    SIMULATION : boolean := false);
  port (
    rst               : in    std_logic;
    sys_clk           : in    std_logic_vector(0 to MEM_ID_RANGE_MSB);
    refclk            : in    std_logic;
    uart_rxd          : in    std_logic;  -- UART1_RX (u1i.rxd)
    uart_txd          : out   std_logic;  -- UART1_TX (u1o.txd)
    uart_ctsn         : in    std_logic;  -- UART1_RTSN (u1i.ctsn)
    uart_rtsn         : out   std_logic;  -- UART1_RTSN (u1o.rtsn)
    cpuerr            : out   std_logic;
    ddr_ahbsi         : out ahb_slv_in_vector_type(0 to MEM_ID_RANGE_MSB);
    ddr_ahbso         : in  ahb_slv_out_vector_type(0 to MEM_ID_RANGE_MSB);
    eth0_apbi         : out apb_slv_in_type;
    eth0_apbo         : in  apb_slv_out_type;
    sgmii0_apbi       : out apb_slv_in_type;
    sgmii0_apbo       : in  apb_slv_out_type;
    eth0_ahbmi        : out ahb_mst_in_type;
    eth0_ahbmo        : in  ahb_mst_out_type;
    edcl_ahbmo        : in  ahb_mst_out_type;
    dvi_apbi          : out apb_slv_in_type;
    dvi_apbo          : in  apb_slv_out_type;
    dvi_ahbmi         : out ahb_mst_in_type;
    dvi_ahbmo         : in  ahb_mst_out_type;
    mon_noc           : out monitor_noc_matrix(1 to 6, 0 to CFG_TILES_NUM-1);
    mon_acc           : out monitor_acc_vector(0 to relu(accelerators_num-1));
    mon_mem           : out monitor_mem_vector(0 to CFG_NMEM_TILE + CFG_NSLM_TILE + CFG_NSLMDDR_TILE - 1);
    mon_l2            : out monitor_cache_vector(0 to relu(CFG_NL2 - 1));
    mon_llc           : out monitor_cache_vector(0 to relu(CFG_NLLC - 1));
    mon_dvfs          : out monitor_dvfs_vector(0 to CFG_TILES_NUM-1));
end;


architecture rtl of esp is


constant nocs_num : integer := 6;

type noc_ctrl_matrix is array (1 to nocs_num) of std_logic_vector(CFG_TILES_NUM-1 downto 0);
type handshake_vec is array (CFG_TILES_NUM-1 downto 0) of std_logic_vector(1 downto 0);
type boolean_vec is array (natural range <>) of boolean;
type int_vec is array (natural range <>) of integer;

constant is_io_tile : boolean_vec(0 to CFG_TILES_NUM-1) := (io_tile_id => true, others => false);

signal rst_int       : std_logic;
signal rst_inv       : std_logic;
signal sys_clk_int   : std_logic_vector(0 to MEM_ID_RANGE_MSB);
signal cpuerr_vec    : std_logic_vector(0 to CFG_NCPU_TILE-1);

signal mon_dvfs_out : monitor_dvfs_vector(0 to CFG_TILES_NUM-1);

type mon_noc_vector is array (CFG_TILES_NUM-1 downto 0) of monitor_noc_vector(1 to nocs_num);
signal mon_noc_s    : mon_noc_vector;

signal mon_l2_int : monitor_cache_vector(0 to CFG_TILES_NUM-1);
signal mon_llc_int : monitor_cache_vector(0 to CFG_TILES_NUM-1);

-- DCO config
type dco_clk_delay_sel_vector is array (CFG_TILES_NUM-1 downto 0) of std_logic_vector(11 downto 0);
type dco_freq_sel_vector      is array (CFG_TILES_NUM-1 downto 0) of std_logic_vector(1 downto 0);
type dco_cc_sel_vector        is array (CFG_TILES_NUM-1 downto 0) of std_logic_vector(5 downto 0);
type dco_fc_sel_vector        is array (CFG_TILES_NUM-1 downto 0) of std_logic_vector(5 downto 0);
type dco_div_sel_vector       is array (CFG_TILES_NUM-1 downto 0) of std_logic_vector(2 downto 0);

signal dco_en            : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal dco_clk_sel       : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal dco_cc_sel        : dco_cc_sel_vector;
signal dco_fc_sel        : dco_fc_sel_vector;
signal dco_div_sel       : dco_div_sel_vector;
signal dco_freq_sel      : dco_freq_sel_vector;

-- Global NoC reset and clock
signal tile_clk      : std_logic_vector(CFG_TILES_NUM-1 downto 0);

-- NOC Signals
--signal noc1_data_n_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc1_data_s_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_w_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_e_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_void_in    : handshake_vec;
signal noc1_stop_in         : handshake_vec;
--signal noc1_data_n_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc1_data_s_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_w_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_e_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_void_out   : handshake_vec;
signal noc1_stop_out        : handshake_vec;
--signal noc2_data_n_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc2_data_s_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_w_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_e_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_void_in    : handshake_vec;
signal noc2_stop_in         : handshake_vec;
--signal noc2_data_n_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc2_data_s_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_w_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_e_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_void_out   : handshake_vec;
signal noc2_stop_out        : handshake_vec;
--signal noc3_data_n_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc3_data_s_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_w_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_e_in       : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_void_in    : handshake_vec;
signal noc3_stop_in         : handshake_vec;
--signal noc3_data_n_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc3_data_s_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_w_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_e_out      : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_void_out   : handshake_vec;
signal noc3_stop_out        : handshake_vec;
--signal noc4_data_n_in       : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc4_data_s_in       : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_w_in       : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_e_in       : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_void_in    : handshake_vec;
signal noc4_stop_in         : handshake_vec;
--signal noc4_data_n_out      : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc4_data_s_out      : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_w_out      : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_e_out      : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_void_out   : handshake_vec;
signal noc4_stop_out        : handshake_vec;
--signal noc5_data_n_in       : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc5_data_s_in       : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_w_in       : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_e_in       : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_void_in    : handshake_vec;
signal noc5_stop_in         : handshake_vec;
--signal noc5_data_n_out      : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc5_data_s_out      : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_w_out      : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_e_out      : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_void_out   : handshake_vec;
signal noc5_stop_out        : handshake_vec;
--signal noc6_data_n_in       : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc6_data_s_in       : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_w_in       : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_e_in       : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_void_in    : handshake_vec;
signal noc6_stop_in         : handshake_vec;
--signal noc6_data_n_out      : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
--signal noc6_data_s_out      : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_w_out      : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_e_out      : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_void_out   : handshake_vec;
signal noc6_stop_out        : handshake_vec;

signal noc1_data_l_in          : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_l_out         : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_void_in_tile  : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_data_void_out_tile : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_stop_in_tile       : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc1_stop_out_tile      : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_l_in          : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_l_out         : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_void_in_tile  : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_data_void_out_tile : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_stop_in_tile       : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc2_stop_out_tile      : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_l_in          : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_l_out         : coh_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_void_in_tile  : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_data_void_out_tile : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_stop_in_tile       : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc3_stop_out_tile      : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_l_in          : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_l_out         : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_void_in_tile  : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_data_void_out_tile : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_stop_in_tile       : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc4_stop_out_tile      : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_l_in          : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_l_out         : misc_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_void_in_tile  : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_data_void_out_tile : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_stop_in_tile       : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc5_stop_out_tile      : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_l_in          : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_l_out         : dma_noc_flit_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_void_in_tile  : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_data_void_out_tile : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_stop_in_tile       : std_logic_vector(CFG_TILES_NUM-1 downto 0);
signal noc6_stop_out_tile      : std_logic_vector(CFG_TILES_NUM-1 downto 0);

-- Ring ordering helpers (serpentine)
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

function build_next_of(order : int_vec) return int_vec is
  variable next_of : int_vec(0 to order'length-1);
  variable N       : integer := order'length;
begin
  for i in 0 to N-1 loop
    next_of(order(i)) := order((i+1) mod N);
  end loop;
  return next_of;
end;

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

constant RING_ORDER : int_vec(0 to CFG_TILES_NUM-1) := build_ring_order(CFG_XLEN, CFG_YLEN);
constant RING_NEXT  : int_vec(0 to CFG_TILES_NUM-1) := build_next_of(RING_ORDER);
constant RING_PREV  : int_vec(0 to CFG_TILES_NUM-1) := build_prev_of(RING_ORDER);


begin

  rst_int <= rst;
  rst_inv <= not rst;
  clk_int_gen: for i in 0 to MEM_ID_RANGE_MSB generate
    sys_clk_int(i) <= sys_clk(i);
  end generate clk_int_gen;

  cpuerr <= cpuerr_vec(0);

  -----------------------------------------------------------------------------
  -- NOC CONNECTIONS
  -----------------------------------------------------------------------------
  ring_wiring: for k in 0 to CFG_TILES_NUM-1 generate
    constant nxt : integer := RING_NEXT(k);
    constant prv : integer := RING_PREV(k);
  begin

    -- NoC1 ring wiring
    noc1_data_w_in(k)         <= noc1_data_e_out(prv);
    noc1_data_void_in(k)(0)   <= noc1_data_void_out(prv)(1);
    noc1_stop_in(k)(0)        <= noc1_stop_out(prv)(1);
    noc1_data_e_in(k)         <= noc1_data_w_out(nxt);
    noc1_data_void_in(k)(1)   <= noc1_data_void_out(nxt)(0);
    noc1_stop_in(k)(1)        <= noc1_stop_out(nxt)(0);

    -- NoC2 ring wiring
    noc2_data_w_in(k)         <= noc2_data_e_out(prv);
    noc2_data_void_in(k)(0)   <= noc2_data_void_out(prv)(1);
    noc2_stop_in(k)(0)        <= noc2_stop_out(prv)(1);
    noc2_data_e_in(k)         <= noc2_data_w_out(nxt);
    noc2_data_void_in(k)(1)   <= noc2_data_void_out(nxt)(0);
    noc2_stop_in(k)(1)        <= noc2_stop_out(nxt)(0);

    -- NoC3 ring wiring
    noc3_data_w_in(k)         <= noc3_data_e_out(prv);
    noc3_data_void_in(k)(0)   <= noc3_data_void_out(prv)(1);
    noc3_stop_in(k)(0)        <= noc3_stop_out(prv)(1);
    noc3_data_e_in(k)         <= noc3_data_w_out(nxt);
    noc3_data_void_in(k)(1)   <= noc3_data_void_out(nxt)(0);
    noc3_stop_in(k)(1)        <= noc3_stop_out(nxt)(0);

    -- NoC4 ring wiring
    noc4_data_w_in(k)         <= noc4_data_e_out(prv);
    noc4_data_void_in(k)(0)   <= noc4_data_void_out(prv)(1);
    noc4_stop_in(k)(0)        <= noc4_stop_out(prv)(1);
    noc4_data_e_in(k)         <= noc4_data_w_out(nxt);
    noc4_data_void_in(k)(1)   <= noc4_data_void_out(nxt)(0);
    noc4_stop_in(k)(1)        <= noc4_stop_out(nxt)(0);

    -- NoC5 ring wiring
    noc5_data_w_in(k)         <= noc5_data_e_out(prv);
    noc5_data_void_in(k)(0)   <= noc5_data_void_out(prv)(1);
    noc5_stop_in(k)(0)        <= noc5_stop_out(prv)(1);
    noc5_data_e_in(k)         <= noc5_data_w_out(nxt);
    noc5_data_void_in(k)(1)   <= noc5_data_void_out(nxt)(0);
    noc5_stop_in(k)(1)        <= noc5_stop_out(nxt)(0);

    -- NoC6 ring wiring
    noc6_data_w_in(k)         <= noc6_data_e_out(prv);
    noc6_data_void_in(k)(0)   <= noc6_data_void_out(prv)(1);
    noc6_stop_in(k)(0)        <= noc6_stop_out(prv)(1);
    noc6_data_e_in(k)         <= noc6_data_w_out(nxt);
    noc6_data_void_in(k)(1)   <= noc6_data_void_out(nxt)(0);
    noc6_stop_in(k)(1)        <= noc6_stop_out(nxt)(0);
  end generate;


  router_gen : for i in 0 to CFG_TILES_NUM - 1 generate
    noc_domain_socket_i : noc_domain_socket
      generic map (
        this_has_token_pm => 0,
        is_tile_io        => is_io_tile(i),
        SIMULATION        => SIMULATION,
        ROUTER_PORTS      => set_router_ports(CFG_FABTECH, CFG_XLEN, CFG_YLEN, tile_x(i)), -- tile_y(i)),
        HAS_SYNC          => 1)
      port map (
        rst                     => rst_inv,
        noc_clk_lock            => '1',
        tile_rstn               => rst_int,
        noc_clk                 => sys_clk_int(0),
        tile_clk                => tile_clk(i),
        noc_rstn                => open,
        raw_rstn                => open,
        acc_clk                 => open,
        -- DCO config
        dco_freq_sel            => dco_freq_sel(i),
        dco_div_sel             => dco_div_sel(i),
        dco_fc_sel              => dco_fc_sel(i),
        dco_cc_sel              => dco_cc_sel(i),
        dco_clk_sel             => dco_clk_sel(i),
        dco_en                  => dco_en(i),
        dco_clk_delay_sel       => open,
        -- pad config
        pad_cfg                 => open,
        -- NoC
--        noc1_data_n_in          => noc1_data_n_in(i),
--        noc1_data_s_in          => noc1_data_s_in(i),
        noc1_data_w_in          => noc1_data_w_in(i),
        noc1_data_e_in          => noc1_data_e_in(i),
        noc1_data_void_in       => noc1_data_void_in(i),
        noc1_stop_in            => noc1_stop_in(i),
--        noc1_data_n_out         => noc1_data_n_out(i),
--        noc1_data_s_out         => noc1_data_s_out(i),
        noc1_data_w_out         => noc1_data_w_out(i),
        noc1_data_e_out         => noc1_data_e_out(i),
        noc1_data_void_out      => noc1_data_void_out(i),
        noc1_stop_out           => noc1_stop_out(i),
--        noc2_data_n_in          => noc2_data_n_in(i),
--        noc2_data_s_in          => noc2_data_s_in(i),
        noc2_data_w_in          => noc2_data_w_in(i),
        noc2_data_e_in          => noc2_data_e_in(i),
        noc2_data_void_in       => noc2_data_void_in(i),
        noc2_stop_in            => noc2_stop_in(i),
--        noc2_data_n_out         => noc2_data_n_out(i),
--        noc2_data_s_out         => noc2_data_s_out(i),
        noc2_data_w_out         => noc2_data_w_out(i),
        noc2_data_e_out         => noc2_data_e_out(i),
        noc2_data_void_out      => noc2_data_void_out(i),
        noc2_stop_out           => noc2_stop_out(i),
--        noc3_data_n_in          => noc3_data_n_in(i),
--        noc3_data_s_in          => noc3_data_s_in(i),
        noc3_data_w_in          => noc3_data_w_in(i),
        noc3_data_e_in          => noc3_data_e_in(i),
        noc3_data_void_in       => noc3_data_void_in(i),
        noc3_stop_in            => noc3_stop_in(i),
--        noc3_data_n_out         => noc3_data_n_out(i),
--        noc3_data_s_out         => noc3_data_s_out(i),
        noc3_data_w_out         => noc3_data_w_out(i),
        noc3_data_e_out         => noc3_data_e_out(i),
        noc3_data_void_out      => noc3_data_void_out(i),
        noc3_stop_out           => noc3_stop_out(i),
--        noc4_data_n_in          => noc4_data_n_in(i),
--        noc4_data_s_in          => noc4_data_s_in(i),
        noc4_data_w_in          => noc4_data_w_in(i),
        noc4_data_e_in          => noc4_data_e_in(i),
        noc4_data_void_in       => noc4_data_void_in(i),
        noc4_stop_in            => noc4_stop_in(i),
--        noc4_data_n_out         => noc4_data_n_out(i),
--        noc4_data_s_out         => noc4_data_s_out(i),
        noc4_data_w_out         => noc4_data_w_out(i),
        noc4_data_e_out         => noc4_data_e_out(i),
        noc4_data_void_out      => noc4_data_void_out(i),
        noc4_stop_out           => noc4_stop_out(i),
--        noc5_data_n_in          => noc5_data_n_in(i),
--        noc5_data_s_in          => noc5_data_s_in(i),
        noc5_data_w_in          => noc5_data_w_in(i),
        noc5_data_e_in          => noc5_data_e_in(i),
        noc5_data_void_in       => noc5_data_void_in(i),
        noc5_stop_in            => noc5_stop_in(i),
--        noc5_data_n_out         => noc5_data_n_out(i),
--        noc5_data_s_out         => noc5_data_s_out(i),
        noc5_data_w_out         => noc5_data_w_out(i),
        noc5_data_e_out         => noc5_data_e_out(i),
        noc5_data_void_out      => noc5_data_void_out(i),
        noc5_stop_out           => noc5_stop_out(i),
--        noc6_data_n_in          => noc6_data_n_in(i),
--        noc6_data_s_in          => noc6_data_s_in(i),
        noc6_data_w_in          => noc6_data_w_in(i),
        noc6_data_e_in          => noc6_data_e_in(i),
        noc6_data_void_in       => noc6_data_void_in(i),
        noc6_stop_in            => noc6_stop_in(i),
--        noc6_data_n_out         => noc6_data_n_out(i),
--        noc6_data_s_out         => noc6_data_s_out(i),
        noc6_data_w_out         => noc6_data_w_out(i),
        noc6_data_e_out         => noc6_data_e_out(i),
        noc6_data_void_out      => noc6_data_void_out(i),
        noc6_stop_out           => noc6_stop_out(i),
        -- monitors
        mon_noc                 => mon_noc_s(i),
        acc_activity            => '0',
        -- synchronizers out to tile
        noc1_output_port_tile   => noc1_data_l_out(i),
        noc1_data_void_out_tile => noc1_data_void_out_tile(i),
        noc1_stop_in_tile       => noc1_stop_in_tile(i),
        noc2_output_port_tile   => noc2_data_l_out(i),
        noc2_data_void_out_tile => noc2_data_void_out_tile(i),
        noc2_stop_in_tile       => noc2_stop_in_tile(i),
        noc3_output_port_tile   => noc3_data_l_out(i),
        noc3_data_void_out_tile => noc3_data_void_out_tile(i),
        noc3_stop_in_tile       => noc3_stop_in_tile(i),
        noc4_output_port_tile   => noc4_data_l_out(i),
        noc4_data_void_out_tile => noc4_data_void_out_tile(i),
        noc4_stop_in_tile       => noc4_stop_in_tile(i),
        noc5_output_port_tile   => noc5_data_l_out(i),
        noc5_data_void_out_tile => noc5_data_void_out_tile(i),
        noc5_stop_in_tile       => noc5_stop_in_tile(i),
        noc6_output_port_tile   => noc6_data_l_out(i),
        noc6_data_void_out_tile => noc6_data_void_out_tile(i),
        noc6_stop_in_tile       => noc6_stop_in_tile(i),
       -- tile to synchronizers in
        noc1_input_port_tile    => noc1_data_l_in(i),
        noc1_data_void_in_tile  => noc1_data_void_in_tile(i),
        noc1_stop_out_tile      => noc1_stop_out_tile(i),
        noc2_input_port_tile    => noc2_data_l_in(i),
        noc2_data_void_in_tile  => noc2_data_void_in_tile(i),
        noc2_stop_out_tile      => noc2_stop_out_tile(i),
        noc3_input_port_tile    => noc3_data_l_in(i),
        noc3_data_void_in_tile  => noc3_data_void_in_tile(i),
        noc3_stop_out_tile      => noc3_stop_out_tile(i),
        noc4_input_port_tile    => noc4_data_l_in(i),
        noc4_data_void_in_tile  => noc4_data_void_in_tile(i),
        noc4_stop_out_tile      => noc4_stop_out_tile(i),
        noc5_input_port_tile    => noc5_data_l_in(i),
        noc5_data_void_in_tile  => noc5_data_void_in_tile(i),
        noc5_stop_out_tile      => noc5_stop_out_tile(i),
        noc6_input_port_tile    => noc6_data_l_in(i),
        noc6_data_void_in_tile  => noc6_data_void_in_tile(i),
        noc6_stop_out_tile      => noc6_stop_out_tile(i));

  end generate router_gen;


  -----------------------------------------------------------------------------
  -- TILES
  -----------------------------------------------------------------------------
  tiles_gen: for i in 0 to CFG_TILES_NUM - 1  generate

    empty_tile: if tile_type(i) = 0 generate
    tile_empty_i: fpga_tile_empty
      generic map (
        SIMULATION   => SIMULATION,
        ROUTER_PORTS => set_router_ports(CFG_FABTECH, CFG_XLEN, CFG_YLEN, tile_x(i)), -- tile_y(i)),
        HAS_SYNC     => CFG_HAS_SYNC)
      port map (
        rst                => rst_int,
        clk                => sys_clk_int(0),
	noc_clk            => sys_clk_int(0),
        tile_clk           => tile_clk(i),
        tile_rstn          => open,
        -- Test interface
        tdi                => '0',
        tdo                => open,
        tms                => '0',
        tclk               => '0',
        -- DCO config
        dco_freq_sel            => dco_freq_sel(i),
        dco_div_sel             => dco_div_sel(i),
        dco_fc_sel              => dco_fc_sel(i),
        dco_cc_sel              => dco_cc_sel(i),
        dco_clk_sel             => dco_clk_sel(i),
        dco_en                  => dco_en(i),
        -- NOC
        noc1_stop_in_tile       => noc1_stop_in_tile(i),
        noc1_stop_out_tile      => noc1_stop_out_tile(i),
        noc1_data_void_in_tile  => noc1_data_void_in_tile(i),
        noc1_data_void_out_tile => noc1_data_void_out_tile(i),
        noc2_stop_in_tile       => noc2_stop_in_tile(i),
        noc2_stop_out_tile      => noc2_stop_out_tile(i),
        noc2_data_void_in_tile  => noc2_data_void_in_tile(i),
        noc2_data_void_out_tile => noc2_data_void_out_tile(i),
        noc3_stop_in_tile       => noc3_stop_in_tile(i),
        noc3_stop_out_tile      => noc3_stop_out_tile(i),
        noc3_data_void_in_tile  => noc3_data_void_in_tile(i),
        noc3_data_void_out_tile => noc3_data_void_out_tile(i),
        noc4_stop_in_tile       => noc4_stop_in_tile(i),
        noc4_stop_out_tile      => noc4_stop_out_tile(i),
        noc4_data_void_in_tile  => noc4_data_void_in_tile(i),
        noc4_data_void_out_tile => noc4_data_void_out_tile(i),
        noc5_stop_in_tile       => noc5_stop_in_tile(i),
        noc5_stop_out_tile      => noc5_stop_out_tile(i),
        noc5_data_void_in_tile  => noc5_data_void_in_tile(i),
        noc5_data_void_out_tile => noc5_data_void_out_tile(i),
        noc6_stop_in_tile       => noc6_stop_in_tile(i),
        noc6_stop_out_tile      => noc6_stop_out_tile(i),
        noc6_data_void_in_tile  => noc6_data_void_in_tile(i),
        noc6_data_void_out_tile => noc6_data_void_out_tile(i),
        noc1_input_port_tile    => noc1_data_l_in(i),
        noc2_input_port_tile    => noc2_data_l_in(i),
        noc3_input_port_tile    => noc3_data_l_in(i),
        noc4_input_port_tile    => noc4_data_l_in(i),
        noc5_input_port_tile    => noc5_data_l_in(i),
        noc6_input_port_tile    => noc6_data_l_in(i),
        noc1_output_port_tile   => noc1_data_l_out(i),
        noc2_output_port_tile   => noc2_data_l_out(i),
        noc3_output_port_tile   => noc3_data_l_out(i),
        noc4_output_port_tile   => noc4_data_l_out(i),
        noc5_output_port_tile   => noc5_data_l_out(i),
        noc6_output_port_tile   => noc6_data_l_out(i),
        mon_noc            => mon_noc_s(i),
	mon_dvfs_out       => mon_dvfs_out(i));
    end generate empty_tile;


    cpu_tile: if tile_type(i) = 1 generate
-- pragma translate_off
      assert tile_cpu_id(i) /= -1 report "Undefined CPU ID for CPU tile" severity error;
-- pragma translate_on
      tile_cpu_i: fpga_tile_cpu

      generic map (
        SIMULATION         => SIMULATION,
        ROUTER_PORTS       => set_router_ports(CFG_FABTECH, CFG_XLEN, CFG_YLEN, tile_x(i)), -- tile_y(i)),
        HAS_SYNC           => CFG_HAS_SYNC)
      port map (
        rst                => rst_int,
        clk                => refclk,
        noc_clk            => sys_clk_int(0),
        tile_clk           => tile_clk(i),
        tile_rstn          => open,
        cpuerr             => cpuerr_vec(tile_cpu_id(i)),
        -- Test interface
        tdi                => '0',
        tdo                => open,
        tms                => '0',
        tclk               => '0',
        -- DCO config
        dco_freq_sel            => dco_freq_sel(i),
        dco_div_sel             => dco_div_sel(i),
        dco_fc_sel              => dco_fc_sel(i),
        dco_cc_sel              => dco_cc_sel(i),
        dco_clk_sel             => dco_clk_sel(i),
        dco_en                  => dco_en(i),
        -- NOC
        noc1_stop_in_tile       => noc1_stop_in_tile(i),
        noc1_stop_out_tile      => noc1_stop_out_tile(i),
        noc1_data_void_in_tile  => noc1_data_void_in_tile(i),
        noc1_data_void_out_tile => noc1_data_void_out_tile(i),
        noc2_stop_in_tile       => noc2_stop_in_tile(i),
        noc2_stop_out_tile      => noc2_stop_out_tile(i),
        noc2_data_void_in_tile  => noc2_data_void_in_tile(i),
        noc2_data_void_out_tile => noc2_data_void_out_tile(i),
        noc3_stop_in_tile       => noc3_stop_in_tile(i),
        noc3_stop_out_tile      => noc3_stop_out_tile(i),
        noc3_data_void_in_tile  => noc3_data_void_in_tile(i),
        noc3_data_void_out_tile => noc3_data_void_out_tile(i),
        noc4_stop_in_tile       => noc4_stop_in_tile(i),
        noc4_stop_out_tile      => noc4_stop_out_tile(i),
        noc4_data_void_in_tile  => noc4_data_void_in_tile(i),
        noc4_data_void_out_tile => noc4_data_void_out_tile(i),
        noc5_stop_in_tile       => noc5_stop_in_tile(i),
        noc5_stop_out_tile      => noc5_stop_out_tile(i),
        noc5_data_void_in_tile  => noc5_data_void_in_tile(i),
        noc5_data_void_out_tile => noc5_data_void_out_tile(i),
        noc6_stop_in_tile       => noc6_stop_in_tile(i),
        noc6_stop_out_tile      => noc6_stop_out_tile(i),
        noc6_data_void_in_tile  => noc6_data_void_in_tile(i),
        noc6_data_void_out_tile => noc6_data_void_out_tile(i),
        noc1_input_port_tile    => noc1_data_l_in(i),
        noc2_input_port_tile    => noc2_data_l_in(i),
        noc3_input_port_tile    => noc3_data_l_in(i),
        noc4_input_port_tile    => noc4_data_l_in(i),
        noc5_input_port_tile    => noc5_data_l_in(i),
        noc6_input_port_tile    => noc6_data_l_in(i),
        noc1_output_port_tile   => noc1_data_l_out(i),
        noc2_output_port_tile   => noc2_data_l_out(i),
        noc3_output_port_tile   => noc3_data_l_out(i),
        noc4_output_port_tile   => noc4_data_l_out(i),
        noc5_output_port_tile   => noc5_data_l_out(i),
        noc6_output_port_tile   => noc6_data_l_out(i),
        mon_noc            => mon_noc_s(i),
        mon_cache          => mon_l2_int(i),
        mon_dvfs           => mon_dvfs_out(i));
    end generate cpu_tile;


    accelerator_tile: if tile_type(i) = 2 generate
-- pragma translate_off
      assert tile_device(i) /= 0 report "Undefined device ID for accelerator tile" severity error;
-- pragma translate_on
      tile_acc_i: fpga_tile_acc
      generic map (
        SIMULATION         => SIMULATION,
        this_hls_conf      => tile_design_point(i),
        this_device        => tile_device(i),
        this_irq_type      => tile_irq_type(i),
        this_has_l2        => tile_has_l2(i),
        this_has_token_pm  => tile_has_tdvfs(i),
        ROUTER_PORTS       => set_router_ports(CFG_FABTECH, CFG_XLEN, CFG_YLEN, tile_x(i)), -- tile_y(i)),
        HAS_SYNC           => CFG_HAS_SYNC)
      port map (
        rst                => rst_int,
        clk                => refclk,
        noc_clk            => sys_clk_int(0),
        tile_clk           => tile_clk(i),
        tile_rstn          => open,
        -- Test interface
        tdi                => '0',
        tdo                => open,
        tms                => '0',
        tclk               => '0',
        -- DCO config
        dco_freq_sel            => dco_freq_sel(i),
        dco_div_sel             => dco_div_sel(i),
        dco_fc_sel              => dco_fc_sel(i),
        dco_cc_sel              => dco_cc_sel(i),
        dco_clk_sel             => dco_clk_sel(i),
        dco_en                  => dco_en(i),
        -- NOC
        noc1_stop_in_tile       => noc1_stop_in_tile(i),
        noc1_stop_out_tile      => noc1_stop_out_tile(i),
        noc1_data_void_in_tile  => noc1_data_void_in_tile(i),
        noc1_data_void_out_tile => noc1_data_void_out_tile(i),
        noc2_stop_in_tile       => noc2_stop_in_tile(i),
        noc2_stop_out_tile      => noc2_stop_out_tile(i),
        noc2_data_void_in_tile  => noc2_data_void_in_tile(i),
        noc2_data_void_out_tile => noc2_data_void_out_tile(i),
        noc3_stop_in_tile       => noc3_stop_in_tile(i),
        noc3_stop_out_tile      => noc3_stop_out_tile(i),
        noc3_data_void_in_tile  => noc3_data_void_in_tile(i),
        noc3_data_void_out_tile => noc3_data_void_out_tile(i),
        noc4_stop_in_tile       => noc4_stop_in_tile(i),
        noc4_stop_out_tile      => noc4_stop_out_tile(i),
        noc4_data_void_in_tile  => noc4_data_void_in_tile(i),
        noc4_data_void_out_tile => noc4_data_void_out_tile(i),
        noc5_stop_in_tile       => noc5_stop_in_tile(i),
        noc5_stop_out_tile      => noc5_stop_out_tile(i),
        noc5_data_void_in_tile  => noc5_data_void_in_tile(i),
        noc5_data_void_out_tile => noc5_data_void_out_tile(i),
        noc6_stop_in_tile       => noc6_stop_in_tile(i),
        noc6_stop_out_tile      => noc6_stop_out_tile(i),
        noc6_data_void_in_tile  => noc6_data_void_in_tile(i),
        noc6_data_void_out_tile => noc6_data_void_out_tile(i),
        noc1_input_port_tile    => noc1_data_l_in(i),
        noc2_input_port_tile    => noc2_data_l_in(i),
        noc3_input_port_tile    => noc3_data_l_in(i),
        noc4_input_port_tile    => noc4_data_l_in(i),
        noc5_input_port_tile    => noc5_data_l_in(i),
        noc6_input_port_tile    => noc6_data_l_in(i),
        noc1_output_port_tile   => noc1_data_l_out(i),
        noc2_output_port_tile   => noc2_data_l_out(i),
        noc3_output_port_tile   => noc3_data_l_out(i),
        noc4_output_port_tile   => noc4_data_l_out(i),
        noc5_output_port_tile   => noc5_data_l_out(i),
        noc6_output_port_tile   => noc6_data_l_out(i),
        mon_noc            => mon_noc_s(i),
        --Monitor signals
        mon_acc            => mon_acc(tile_acc_id(i)),
        mon_cache          => mon_l2_int(i),
        mon_dvfs           => mon_dvfs_out(i)
        );
    end generate accelerator_tile;


    io_tile: if tile_type(i) = 3 generate
      tile_io_i : fpga_tile_io
      generic map (
        SIMULATION   => SIMULATION,
        ROUTER_PORTS => set_router_ports(CFG_FABTECH, CFG_XLEN, CFG_YLEN, tile_x(i)), -- tile_y(i)),
        HAS_SYNC     => CFG_HAS_SYNC)
      port map (
	rst                => rst_int,
	clk                => refclk,
	noc_clk            => sys_clk_int(0),
        tile_clk           => tile_clk(i),
        tile_rstn          => open,
        -- Test interface
        tdi                => '0',
        tdo                => open,
        tms                => '0',
        tclk               => '0',
        -- I/O bus interfaces
	eth0_apbi          => eth0_apbi,
	eth0_apbo          => eth0_apbo,
	sgmii0_apbi        => sgmii0_apbi,
	sgmii0_apbo        => sgmii0_apbo,
	eth0_ahbmi         => eth0_ahbmi,
	eth0_ahbmo         => eth0_ahbmo,
	edcl_ahbmo         => edcl_ahbmo,
	dvi_apbi           => dvi_apbi,
	dvi_apbo           => dvi_apbo,
	dvi_ahbmi          => dvi_ahbmi,
	dvi_ahbmo          => dvi_ahbmo,
	uart_rxd           => uart_rxd,
	uart_txd           => uart_txd,
	uart_ctsn          => uart_ctsn,
	uart_rtsn          => uart_rtsn,
        -- DCO config
        dco_freq_sel            => dco_freq_sel(i),
        dco_div_sel             => dco_div_sel(i),
        dco_fc_sel              => dco_fc_sel(i),
        dco_cc_sel              => dco_cc_sel(i),
        dco_clk_sel             => dco_clk_sel(i),
        dco_en                  => dco_en(i),
	-- NOC
        noc1_stop_in_tile       => noc1_stop_in_tile(i),
        noc1_stop_out_tile      => noc1_stop_out_tile(i),
        noc1_data_void_in_tile  => noc1_data_void_in_tile(i),
        noc1_data_void_out_tile => noc1_data_void_out_tile(i),
        noc2_stop_in_tile       => noc2_stop_in_tile(i),
        noc2_stop_out_tile      => noc2_stop_out_tile(i),
        noc2_data_void_in_tile  => noc2_data_void_in_tile(i),
        noc2_data_void_out_tile => noc2_data_void_out_tile(i),
        noc3_stop_in_tile       => noc3_stop_in_tile(i),
        noc3_stop_out_tile      => noc3_stop_out_tile(i),
        noc3_data_void_in_tile  => noc3_data_void_in_tile(i),
        noc3_data_void_out_tile => noc3_data_void_out_tile(i),
        noc4_stop_in_tile       => noc4_stop_in_tile(i),
        noc4_stop_out_tile      => noc4_stop_out_tile(i),
        noc4_data_void_in_tile  => noc4_data_void_in_tile(i),
        noc4_data_void_out_tile => noc4_data_void_out_tile(i),
        noc5_stop_in_tile       => noc5_stop_in_tile(i),
        noc5_stop_out_tile      => noc5_stop_out_tile(i),
        noc5_data_void_in_tile  => noc5_data_void_in_tile(i),
        noc5_data_void_out_tile => noc5_data_void_out_tile(i),
        noc6_stop_in_tile       => noc6_stop_in_tile(i),
        noc6_stop_out_tile      => noc6_stop_out_tile(i),
        noc6_data_void_in_tile  => noc6_data_void_in_tile(i),
        noc6_data_void_out_tile => noc6_data_void_out_tile(i),
        noc1_input_port_tile    => noc1_data_l_in(i),
        noc2_input_port_tile    => noc2_data_l_in(i),
        noc3_input_port_tile    => noc3_data_l_in(i),
        noc4_input_port_tile    => noc4_data_l_in(i),
        noc5_input_port_tile    => noc5_data_l_in(i),
        noc6_input_port_tile    => noc6_data_l_in(i),
        noc1_output_port_tile   => noc1_data_l_out(i),
        noc2_output_port_tile   => noc2_data_l_out(i),
        noc3_output_port_tile   => noc3_data_l_out(i),
        noc4_output_port_tile   => noc4_data_l_out(i),
        noc5_output_port_tile   => noc5_data_l_out(i),
        noc6_output_port_tile   => noc6_data_l_out(i),
        mon_noc            => mon_noc_s(i),
	mon_dvfs           => mon_dvfs_out(i));
    end generate io_tile;


    mem_tile: if tile_type(i) = 4 generate
      tile_mem_i: fpga_tile_mem
      generic map (
        ROUTER_PORTS => set_router_ports(CFG_FABTECH, CFG_XLEN, CFG_YLEN, tile_x(i)), -- tile_y(i)),
        HAS_SYNC     => CFG_HAS_SYNC)
      port map (
	rst                => rst_int,
	clk                => sys_clk_int(tile_mem_id(i)),
	noc_clk            => sys_clk_int(0),
        tile_clk           => tile_clk(i),
        tile_rstn          => open,
        -- DDR controller ports (this_has_ddr -> 1)
	ddr_ahbsi          => ddr_ahbsi(tile_mem_id(i)),
	ddr_ahbso          => ddr_ahbso(tile_mem_id(i)),
                -- Test interface
        tdi                => '0',
        tdo                => open,
        tms                => '0',
        tclk               => '0',
        -- DCO config
        dco_freq_sel            => dco_freq_sel(i),
        dco_div_sel             => dco_div_sel(i),
        dco_fc_sel              => dco_fc_sel(i),
        dco_cc_sel              => dco_cc_sel(i),
        dco_clk_sel             => dco_clk_sel(i),
        dco_en                  => dco_en(i),
	-- NOC
        noc1_stop_in_tile       => noc1_stop_in_tile(i),
        noc1_stop_out_tile      => noc1_stop_out_tile(i),
        noc1_data_void_in_tile  => noc1_data_void_in_tile(i),
        noc1_data_void_out_tile => noc1_data_void_out_tile(i),
        noc2_stop_in_tile       => noc2_stop_in_tile(i),
        noc2_stop_out_tile      => noc2_stop_out_tile(i),
        noc2_data_void_in_tile  => noc2_data_void_in_tile(i),
        noc2_data_void_out_tile => noc2_data_void_out_tile(i),
        noc3_stop_in_tile       => noc3_stop_in_tile(i),
        noc3_stop_out_tile      => noc3_stop_out_tile(i),
        noc3_data_void_in_tile  => noc3_data_void_in_tile(i),
        noc3_data_void_out_tile => noc3_data_void_out_tile(i),
        noc4_stop_in_tile       => noc4_stop_in_tile(i),
        noc4_stop_out_tile      => noc4_stop_out_tile(i),
        noc4_data_void_in_tile  => noc4_data_void_in_tile(i),
        noc4_data_void_out_tile => noc4_data_void_out_tile(i),
        noc5_stop_in_tile       => noc5_stop_in_tile(i),
        noc5_stop_out_tile      => noc5_stop_out_tile(i),
        noc5_data_void_in_tile  => noc5_data_void_in_tile(i),
        noc5_data_void_out_tile => noc5_data_void_out_tile(i),
        noc6_stop_in_tile       => noc6_stop_in_tile(i),
        noc6_stop_out_tile      => noc6_stop_out_tile(i),
        noc6_data_void_in_tile  => noc6_data_void_in_tile(i),
        noc6_data_void_out_tile => noc6_data_void_out_tile(i),
        noc1_input_port_tile    => noc1_data_l_in(i),
        noc2_input_port_tile    => noc2_data_l_in(i),
        noc3_input_port_tile    => noc3_data_l_in(i),
        noc4_input_port_tile    => noc4_data_l_in(i),
        noc5_input_port_tile    => noc5_data_l_in(i),
        noc6_input_port_tile    => noc6_data_l_in(i),
        noc1_output_port_tile   => noc1_data_l_out(i),
        noc2_output_port_tile   => noc2_data_l_out(i),
        noc3_output_port_tile   => noc3_data_l_out(i),
        noc4_output_port_tile   => noc4_data_l_out(i),
        noc5_output_port_tile   => noc5_data_l_out(i),
        noc6_output_port_tile   => noc6_data_l_out(i),
        mon_noc            => mon_noc_s(i),
	mon_mem            => mon_mem(tile_mem_id(i)),
	mon_cache          => mon_llc_int(i),
	mon_dvfs           => mon_dvfs_out(i));
    end generate mem_tile;

    slm_tile: if tile_type(i) = 5 generate
      tile_slm_i: fpga_tile_slm
        generic map (
          SIMULATION   => SIMULATION,
          ROUTER_PORTS => set_router_ports(CFG_FABTECH, CFG_XLEN, CFG_YLEN, tile_x(i)), -- tile_y(i)),
          HAS_SYNC     => CFG_HAS_SYNC)
        port map (
          rst                => rst_int,
          clk                => refclk,
          noc_clk            => sys_clk_int(0),
          tile_clk           => tile_clk(i),
          tile_rstn          => open,
          -- DDR controller ports (disaled in generic ESP top)
          ddr_ahbsi          => open,
          ddr_ahbso          => ahbs_none,
                    -- Test interface
          tdi                => '0',
          tdo                => open,
          tms                => '0',
          tclk               => '0',
          -- DCO config
          dco_freq_sel            => dco_freq_sel(i),
          dco_div_sel             => dco_div_sel(i),
          dco_fc_sel              => dco_fc_sel(i),
          dco_cc_sel              => dco_cc_sel(i),
          dco_clk_sel             => dco_clk_sel(i),
          dco_en                  => dco_en(i),
          -- NOC
          noc1_stop_in_tile       => noc1_stop_in_tile(i),
          noc1_stop_out_tile      => noc1_stop_out_tile(i),
          noc1_data_void_in_tile  => noc1_data_void_in_tile(i),
          noc1_data_void_out_tile => noc1_data_void_out_tile(i),
          noc2_stop_in_tile       => noc2_stop_in_tile(i),
          noc2_stop_out_tile      => noc2_stop_out_tile(i),
          noc2_data_void_in_tile  => noc2_data_void_in_tile(i),
          noc2_data_void_out_tile => noc2_data_void_out_tile(i),
          noc3_stop_in_tile       => noc3_stop_in_tile(i),
          noc3_stop_out_tile      => noc3_stop_out_tile(i),
          noc3_data_void_in_tile  => noc3_data_void_in_tile(i),
          noc3_data_void_out_tile => noc3_data_void_out_tile(i),
          noc4_stop_in_tile       => noc4_stop_in_tile(i),
          noc4_stop_out_tile      => noc4_stop_out_tile(i),
          noc4_data_void_in_tile  => noc4_data_void_in_tile(i),
          noc4_data_void_out_tile => noc4_data_void_out_tile(i),
          noc5_stop_in_tile       => noc5_stop_in_tile(i),
          noc5_stop_out_tile      => noc5_stop_out_tile(i),
          noc5_data_void_in_tile  => noc5_data_void_in_tile(i),
          noc5_data_void_out_tile => noc5_data_void_out_tile(i),
          noc6_stop_in_tile       => noc6_stop_in_tile(i),
          noc6_stop_out_tile      => noc6_stop_out_tile(i),
          noc6_data_void_in_tile  => noc6_data_void_in_tile(i),
          noc6_data_void_out_tile => noc6_data_void_out_tile(i),
          noc1_input_port_tile    => noc1_data_l_in(i),
          noc2_input_port_tile    => noc2_data_l_in(i),
          noc3_input_port_tile    => noc3_data_l_in(i),
          noc4_input_port_tile    => noc4_data_l_in(i),
          noc5_input_port_tile    => noc5_data_l_in(i),
          noc6_input_port_tile    => noc6_data_l_in(i),
          noc1_output_port_tile   => noc1_data_l_out(i),
          noc2_output_port_tile   => noc2_data_l_out(i),
          noc3_output_port_tile   => noc3_data_l_out(i),
          noc4_output_port_tile   => noc4_data_l_out(i),
          noc5_output_port_tile   => noc5_data_l_out(i),
          noc6_output_port_tile   => noc6_data_l_out(i),
          mon_noc            => mon_noc_s(i),
          mon_mem            => mon_mem(CFG_NMEM_TILE + tile_slm_id(i)),
          mon_dvfs           => mon_dvfs_out(i));
    end generate slm_tile;

  end generate tiles_gen;

  no_mem_tile_gen: if CFG_NMEM_TILE = 0 generate
    ddr_ahbsi(0) <= ahbs_in_none;
  end generate no_mem_tile_gen;

  monitor_noc_gen: for i in 1 to nocs_num generate
    monitor_noc_tiles_gen: for j in 0 to CFG_TILES_NUM-1 generate
      mon_noc(i,j) <= mon_noc_s(j)(i);
    end generate monitor_noc_tiles_gen;
  end generate monitor_noc_gen;

  monitor_l2_gen: for i in 0 to CFG_NL2 - 1 generate
    mon_l2(i) <= mon_l2_int(cache_tile_id(i));
  end generate monitor_l2_gen;

  monitor_llc_gen: for i in 0 to CFG_NLLC - 1 generate
    mon_llc(i) <= mon_llc_int(llc_tile_id(i));
  end generate monitor_llc_gen;


  -- Handle cases with no accelerators, no l2, no llc
  mon_acc_noacc_gen: if accelerators_num = 0 generate
    mon_acc(0) <= monitor_acc_none;
  end generate mon_acc_noacc_gen;

  mon_l2_nol2_gen: if CFG_NL2 = 0 generate
    mon_l2(0) <= monitor_cache_none;
  end generate mon_l2_nol2_gen;

  mon_llc_nollc_gen: if CFG_NLLC = 0 generate
    mon_llc(0) <= monitor_cache_none;
  end generate mon_llc_nollc_gen;

  mon_dvfs <= mon_dvfs_out;

end rtl;
