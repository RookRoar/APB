--
--  Original Author:  Kartik Desai
--
--  Description:
--      APB monitor. Passive: checks every protocol rule at every rising edge of
--      PCLK (ApbCheckerPkg), logs each completed transfer, and optionally publishes
--      the transfers into a FIFO and collects coverage.
--
--  Notes:
--      No transaction record, as the OSVVM AXI monitors. Each rule has its own
--      AlertLog ID under the model ID, named as the rule ("APB3-R01"), so a test can
--      check or disable one rule. APB3-W02 is disabled by default.
--      PUBLISH_TRANSFERS: completed transfers go into the ApbTransferScoreboardPkg
--      FIFO "<model> Transfers" (Search => NAME). Transfers that were abandoned,
--      aborted by reset or had no SETUP are only logged.
--      COLLECT_COVERAGE: "<model> Coverage" crosses direction, wait states and
--      PSLVERR; "<model> Spacing Coverage" counts back-to-back and idle-separated
--      transfers.
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

use work.ApbInterfacePkg.all;
use work.ApbProtocolPkg.all;
use work.ApbCheckerPkg.all;
use work.ApbTransferScoreboardPkg.all;

entity ApbMonitor is
  generic (
    MODEL_ID_NAME     : string          := "";
    APB_REVISION      : ApbRevisionType := APB3;
    PUBLISH_TRANSFERS : boolean         := FALSE;
    COLLECT_COVERAGE  : boolean         := TRUE
  );
  port (
    -- Globals
    Clk    : in std_logic;
    nReset : in std_logic;

    -- APB interface, observed only
    ApbBus : in ApbRecType
  );

  -- Use MODEL_ID_NAME if set, otherwise the instance label
  constant MODEL_INSTANCE_NAME : string :=
    IfElse(MODEL_ID_NAME /= "", MODEL_ID_NAME, PathTail(to_lower(ApbMonitor'PATH_NAME)));

end entity ApbMonitor;

architecture Monitor of ApbMonitor is

  constant DIRECTION_READ  : integer := 0;
  constant DIRECTION_WRITE : integer := 1;

begin

  ------------------------------------------------------------
  -- Check every edge, record completed transfers
  ------------------------------------------------------------
  MonitorProc : process
    -- Created during elaboration.
    -- The FIFO and coverage IDs are variables: they exist only when enabled.
    constant ModelID       : AlertLogIDType     := NewID(MODEL_INSTANCE_NAME);
    constant RuleID        : ApbRuleIDArrayType := NewApbRuleIDs(ModelID);
    variable TransferFifo  : ScoreboardIDType;
    variable CovID         : CoverageIDType;
    variable SpacingCovID  : CoverageIDType;
    variable State         : ApbCheckerStateType(
      PAddr(ApbBus.Requester.PAddr'range),
      PWData(ApbBus.Requester.PWData'range)
    );
    variable Transfer      : ApbTransferType(
      Addr(ApbBus.Requester.PAddr'range),
      WData(ApbBus.Requester.PWData'range),
      RData(ApbBus.Completer.PRData'range),
      Strb(ApbBus.Requester.PStrb'range)
    );
    variable TransferEnd   : ApbTransferEndType;
    variable TransferCount : natural            := 0;
  begin
    if PUBLISH_TRANSFERS then
      TransferFifo := NewID(MODEL_INSTANCE_NAME & " Transfers", ParentID => ModelID, Search => NAME);
    end if;

    if COLLECT_COVERAGE then
      CovID := NewID(MODEL_INSTANCE_NAME & " Coverage", ParentID => ModelID, Search => NAME);
      AddCross(CovID,
               GenBin(DIRECTION_READ, DIRECTION_WRITE),
               GenBin(0) & GenBin(1) & GenBin(2, 3, 1) & GenBin(4, 15, 1) &
               GenBin(16, integer'high, 1), GenBin(0, 1));
      SetItemBinNames(CovID, "Write", "WaitStates", "PSLVERR");

      SpacingCovID := NewID(MODEL_INSTANCE_NAME & " Spacing Coverage", ParentID => ModelID, Search => NAME);
      AddBins(SpacingCovID, "Idle separated", GenBin(0));
      AddBins(SpacingCovID, "Back-to-back", GenBin(1));
    end if;

    AlertIf(ModelID, APB_REVISION /= APB3,
            "APB_REVISION " & to_string(APB_REVISION) &
            " is not supported yet. Only APB3 is supported.", FAILURE);

    -- Static interface checks one delta later, so a test can raise the FAILURE stop
    -- count at time 0 first
    wait for 0 ns;
    CheckApbInterface(ModelID, RuleID, APB_REVISION, ApbBus);
    InitApbChecker(State);

    loop
      wait until rising_edge(Clk);
      CheckApb3Cycle(RuleID, State, nReset, ApbBus, Transfer, TransferEnd);

      case TransferEnd is
        when APB_COMPLETED =>
          TransferCount := TransferCount + 1;
          Log(ModelID, "Transfer " & to_string(TransferCount) & ": " & to_string(Transfer), INFO);
          if PUBLISH_TRANSFERS then
            Push(TransferFifo, Transfer);
          end if;
          if COLLECT_COVERAGE then
            ICover(CovID, (IfElse(Transfer.Write = '1', DIRECTION_WRITE, DIRECTION_READ),
                           Transfer.WaitStates, IfElse(Transfer.SlvErr = '1', 1, 0)));
            ICover(SpacingCovID, IfElse(State.BackToBack, 1, 0));
          end if;

        when APB_ABANDONED =>
          Log(ModelID, "Transfer abandoned by the Requester, not recorded.  PADDR: " &
              to_hxstring(Transfer.Addr) & "  WaitStates: " & to_string(Transfer.WaitStates), INFO);

        when APB_NO_SETUP =>
          Log(ModelID, "Completion of an ACCESS without SETUP, not recorded.  PADDR: " &
              to_hxstring(Transfer.Addr), INFO);

        when APB_RESET =>
          Log(ModelID, "Transfer aborted by reset, not recorded.  PADDR: " &
              to_hxstring(Transfer.Addr) & "  WaitStates: " & to_string(Transfer.WaitStates), INFO);

        when APB_NO_END =>
          null;
      end case;
    end loop;
  end process MonitorProc;

end architecture Monitor;
