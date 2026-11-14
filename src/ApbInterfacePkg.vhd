--
--  Original Author:  Kartik Desai
--
--  Description:
--      APB interface: bus record types, InitApbRec and static interface checks
--
--  Notes:
--      The record is split by signal source (IHI0024E Table 2-1) so that each side
--      drives only its own sub-record. A procedure with a whole-record signal
--      parameter would otherwise create drivers on the other side's signals.
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

package ApbInterfacePkg is

  -- APB5: add APB5 here
  type ApbRevisionType is (APB3, APB4);

  -- Signals driven by the Requester (IHI0024E Table 2-1, Source = Requester)
  type ApbRequesterRecType is record
    PSel    : std_logic;
    PEnable : std_logic;
    PAddr   : std_logic_vector;              -- 1 to 32 bits (APB3-S01)
    PWrite  : std_logic;
    PWData  : std_logic_vector;              -- 8, 16 or 32 bits (APB3-S02)
    PProt   : std_logic_vector(2 downto 0);  -- APB4 only (Table B-1)
    PStrb   : std_logic_vector;              -- APB4 only, DATA_WIDTH/8 bits
    -- APB5 insertion point: PNSE, PWAKEUP, PAUSER, PWUSER, check signals
  end record ApbRequesterRecType;

  -- Signals driven by the Completer (IHI0024E Table 2-1, Source = Completer)
  type ApbCompleterRecType is record
    PRData  : std_logic_vector;  -- same width as PWDATA (APB3-S03)
    PReady  : std_logic;
    PSlvErr : std_logic;
    -- APB5 insertion point: PRUSER, PBUSER, check signals
  end record ApbCompleterRecType;

  type ApbRecType is record
    Requester : ApbRequesterRecType;
    Completer : ApbCompleterRecType;
  end record ApbRecType;

  -- Drive every field 'Z'. Each VC calls this concurrently, then drives only its own fields.
  procedure InitApbRec (signal ApbBus : inout ApbRecType);

  -- Static interface checks (APB3-S01, S02, S03; APB4-S01). FAILURE on violation.
  -- One alert ID per rule; the overload below uses a single ID for all of them.
  procedure CheckApbInterface (
    constant AddrWidthID     : in AlertLogIDType;  -- APB3-S01
    constant DataWidthID     : in AlertLogIDType;  -- APB3-S02
    constant ReadDataWidthID : in AlertLogIDType;  -- APB3-S03
    constant StrbWidthID     : in AlertLogIDType;  -- APB4-S01
    constant Revision        : in ApbRevisionType;
    constant ApbBus          : in ApbRecType
  );

  procedure CheckApbInterface (
    constant AlertLogID : in AlertLogIDType;
    constant Revision   : in ApbRevisionType;
    constant ApbBus     : in ApbRecType
  );

end package ApbInterfacePkg;

package body ApbInterfacePkg is

  ------------------------------------------------------------
  -- Local
  function InitApbRequesterRec (Req : ApbRequesterRecType; InitVal : std_logic := 'Z') return ApbRequesterRecType is
  ------------------------------------------------------------
  begin
    return (
      PSel    => InitVal,
      PEnable => InitVal,
      PAddr   => (Req.PAddr'range => InitVal),
      PWrite  => InitVal,
      PWData  => (Req.PWData'range => InitVal),
      PProt   => (others => InitVal),
      PStrb   => (Req.PStrb'range => InitVal)
    );
  end function InitApbRequesterRec;

  ------------------------------------------------------------
  -- Local
  function InitApbCompleterRec (Cmp : ApbCompleterRecType; InitVal : std_logic := 'Z') return ApbCompleterRecType is
  ------------------------------------------------------------
  begin
    return (
      PRData  => (Cmp.PRData'range => InitVal),
      PReady  => InitVal,
      PSlvErr => InitVal
    );
  end function InitApbCompleterRec;

  ------------------------------------------------------------
  -- Local
  function InitApbRec (ApbBus : ApbRecType; InitVal : std_logic := 'Z') return ApbRecType is
  ------------------------------------------------------------
  begin
    return (
      Requester => InitApbRequesterRec(ApbBus.Requester, InitVal),
      Completer => InitApbCompleterRec(ApbBus.Completer, InitVal)
    );
  end function InitApbRec;

  ------------------------------------------------------------
  procedure InitApbRec (signal ApbBus : inout ApbRecType) is
  ------------------------------------------------------------
  begin
    ApbBus <= InitApbRec(ApbBus, 'Z');
  end procedure InitApbRec;

  ------------------------------------------------------------
  -- Local: the checks, one alert ID per rule
  procedure CheckApbWidths (
  ------------------------------------------------------------
    constant AddrWidthID     : in AlertLogIDType;
    constant DataWidthID     : in AlertLogIDType;
    constant ReadDataWidthID : in AlertLogIDType;
    constant StrbWidthID     : in AlertLogIDType;
    constant Revision        : in ApbRevisionType;
    constant AddrWidth       : in natural;
    constant DataWidth       : in natural;
    constant ReadDataWidth   : in natural;
    constant StrbWidth       : in natural
  ) is
  begin
    -- APB3-S01: IHI0024E Table 2-1, PADDR can be up to 32 bits wide
    AlertIf(AddrWidthID, AddrWidth < 1 or AddrWidth > 32,
            "APB3-S01: PADDR width " & to_string(AddrWidth) & " is not in 1 to 32 (IHI0024E Table 2-1)",
            FAILURE);

    -- APB3-S02: IHI0024E 2.1.2, data buses are 8, 16 or 32 bits wide
    AlertIf(DataWidthID, DataWidth /= 8 and DataWidth /= 16 and DataWidth /= 32,
            "APB3-S02: PWDATA width " & to_string(DataWidth) & " is not 8, 16 or 32 (IHI0024E 2.1.2)",
            FAILURE);

    -- APB3-S03: IHI0024E 2.1.2, read and write data buses must have the same width
    AlertIf(ReadDataWidthID, ReadDataWidth /= DataWidth,
            "APB3-S03: PRDATA width " & to_string(ReadDataWidth) &
            " /= PWDATA width " & to_string(DataWidth) & " (IHI0024E 2.1.2)",
            FAILURE);

    if Revision >= APB4 then
      -- APB4-S01: IHI0024E Table 2-1, PSTRB is DATA_WIDTH/8 bits wide
      AlertIf(StrbWidthID, StrbWidth /= DataWidth / 8,
              "APB4-S01: PSTRB width " & to_string(StrbWidth) &
              " /= PWDATA width / 8 (IHI0024E Table 2-1)",
              FAILURE);
    end if;
  end procedure CheckApbWidths;

  ------------------------------------------------------------
  procedure CheckApbInterface (
  ------------------------------------------------------------
    constant AddrWidthID     : in AlertLogIDType;
    constant DataWidthID     : in AlertLogIDType;
    constant ReadDataWidthID : in AlertLogIDType;
    constant StrbWidthID     : in AlertLogIDType;
    constant Revision        : in ApbRevisionType;
    constant ApbBus          : in ApbRecType
  ) is
  begin
    CheckApbWidths(
      AddrWidthID     => AddrWidthID,
      DataWidthID     => DataWidthID,
      ReadDataWidthID => ReadDataWidthID,
      StrbWidthID     => StrbWidthID,
      Revision        => Revision,
      AddrWidth       => ApbBus.Requester.PAddr'length,
      DataWidth       => ApbBus.Requester.PWData'length,
      ReadDataWidth   => ApbBus.Completer.PRData'length,
      StrbWidth       => ApbBus.Requester.PStrb'length
    );
  end procedure CheckApbInterface;

  ------------------------------------------------------------
  procedure CheckApbInterface (
  ------------------------------------------------------------
    constant AlertLogID : in AlertLogIDType;
    constant Revision   : in ApbRevisionType;
    constant ApbBus     : in ApbRecType
  ) is
  begin
    CheckApbWidths(
      AddrWidthID     => AlertLogID,
      DataWidthID     => AlertLogID,
      ReadDataWidthID => AlertLogID,
      StrbWidthID     => AlertLogID,
      Revision        => Revision,
      AddrWidth       => ApbBus.Requester.PAddr'length,
      DataWidth       => ApbBus.Requester.PWData'length,
      ReadDataWidth   => ApbBus.Completer.PRData'length,
      StrbWidth       => ApbBus.Requester.PStrb'length
    );
  end procedure CheckApbInterface;

end package body ApbInterfacePkg;
