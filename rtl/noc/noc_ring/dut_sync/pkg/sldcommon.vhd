------------------------------------------------------------------------------
--  Copyright (C) 2015, System Level Design (SLD) group @ Columbia University
-----------------------------------------------------------------------------
-- Package:     sldcommon
-- File:        sldcommon.vhd
-- Authors:     Paolo Mantovani - SLD @ Columbia University
-- Description: defines SLD components and types
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package sldcommon is

  type monitor_noc_type is record
    clk          : std_ulogic;
    tile_inject  : std_ulogic;
    queue_full   : std_logic_vector(2 downto 0);
  end record;

  type monitor_noc_vector is array (natural range <>) of monitor_noc_type;
  type monitor_noc_matrix is array (natural range <>, natural range <>) of monitor_noc_type;

  constant monitor_noc_none : monitor_noc_type := (
    clk => '0',
    tile_inject => '0',
    queue_full => (others => '0')
    );

  function to_std_logic (i : integer) return std_logic;
end sldcommon;

package body sldcommon is
  function to_std_logic (
    i : integer)
    return std_logic is
  begin  -- to_std_logic
    if i = 0 then
      return '0';
    else
     return '1';
   end if;
  end to_std_logic;
end;
