--
--  Original Author:  Kartik Desai
--
--  Description:
--      Test controller entity for the APB verification component tests. Each test
--      is an architecture of TestCtrl plus a configuration of a test harness.
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
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;

library osvvm;
context osvvm.OsvvmContext;

library osvvm_apb;
context osvvm_apb.ApbContext;

entity TestCtrl is
  generic (
    tperiod_Clk : time := 10 ns
  );
  port (
    -- Globals
    Clk          : in    std_logic;
    nReset       : in    std_logic;
    ForceReset   : out   std_logic := '0';  -- '1' asserts nReset (for reset tests)

    -- Transaction interfaces
    RequesterRec : inout AddressBusRecType;
    CompleterRec : inout AddressBusRecType
  );
  constant ADDR_WIDTH : integer := RequesterRec.Address'length;
  constant DATA_WIDTH : integer := RequesterRec.DataToModel'length;
end entity TestCtrl;
