--
--  Original Author:  Kartik Desai
--
--  Description:
--      Test harness: ApbRequester connected to ApbCompleterMemory
--
--  Copyright (c) 2026 by Kartik Desai
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      https://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--
library ieee;
use ieee.std_logic_1164.all;

library osvvm;
context osvvm.OsvvmContext;

library osvvm_apb;
context osvvm_apb.ApbContext;

entity TbApbMemory is
  generic (
    ADDR_WIDTH : integer := 32;
    DATA_WIDTH : integer := 32
  );
end entity TbApbMemory;

architecture TestHarness of TbApbMemory is
  constant tperiod_Clk : time := 10 ns;
  constant tpd         : time := 2 ns;

  signal Clk        : std_logic;
  signal nResetInit : std_logic;
  signal nReset     : std_logic;
  signal ForceReset : std_logic;

  signal RequesterRec : AddressBusRecType(
    Address(ADDR_WIDTH - 1 downto 0),
    DataToModel(DATA_WIDTH - 1 downto 0),
    DataFromModel(DATA_WIDTH - 1 downto 0)
  );
  signal CompleterRec : AddressBusRecType(
    Address(ADDR_WIDTH - 1 downto 0),
    DataToModel(DATA_WIDTH - 1 downto 0),
    DataFromModel(DATA_WIDTH - 1 downto 0)
  );

  signal ApbBus : ApbRecType(
    Requester(PAddr(ADDR_WIDTH - 1 downto 0),
              PWData(DATA_WIDTH - 1 downto 0),
              PStrb(DATA_WIDTH / 8 - 1 downto 0)),
    Completer(PRData(DATA_WIDTH - 1 downto 0))
  );

  component TestCtrl is
    generic (
      tperiod_Clk : time := 10 ns
    );
    port (
      Clk          : in    std_logic;
      nReset       : in    std_logic;
      ForceReset   : out   std_logic := '0';
      RequesterRec : inout AddressBusRecType;
      CompleterRec : inout AddressBusRecType
    );
  end component TestCtrl;

begin

  -- First, so that the test's AlertLog IDs come first on every simulator
  TestCtrl_1 : TestCtrl
    generic map (
      tperiod_Clk => tperiod_Clk
    )
    port map (
      Clk          => Clk,
      nReset       => nReset,
      ForceReset   => ForceReset,
      RequesterRec => RequesterRec,
      CompleterRec => CompleterRec
    );

  Osvvm.ClockResetPkg.CreateClock(
    Clk    => Clk,
    Period => tperiod_Clk
  );

  Osvvm.ClockResetPkg.CreateReset(
    Reset       => nResetInit,
    ResetActive => '0',
    Clk         => Clk,
    Period      => 7 * tperiod_Clk,
    tpd         => tpd
  );

  -- PRESETn is active LOW (IHI0024E Table 2-1)
  nReset <= nResetInit and not ForceReset;

  ApbRequester_1 : ApbRequester
    port map (
      Clk      => Clk,
      nReset   => nReset,
      ApbBus   => ApbBus,
      TransRec => RequesterRec
    );

  ApbCompleterMemory_1 : ApbCompleterMemory
    port map (
      Clk      => Clk,
      nReset   => nReset,
      ApbBus   => ApbBus,
      TransRec => CompleterRec
    );

  ApbMonitor_1 : ApbMonitor
    generic map (
      MODEL_ID_NAME => "ApbMonitor"
    )
    port map (
      Clk    => Clk,
      nReset => nReset,
      ApbBus => ApbBus
    );

end architecture TestHarness;
