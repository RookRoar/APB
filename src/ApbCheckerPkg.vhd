--
--  Original Author:  Kartik Desai
--
--  Description:
--      APB protocol checker: one rule per AlertLog ID, checked at every rising
--      edge of PCLK from the sampled bus. Used by ApbMonitor.
--
--  Notes:
--      Rules are grouped by revision. CheckApb3Cycle checks the APB3 rules; a later
--      revision adds its own procedure and rule IDs without changing these.
--      Validity rules (Vnn) alert at most once per transfer. V01 and the
--      recommendations (Wnn) alert once per stretch of cycles and re-arm when the
--      signal is valid (V01) or zero (Wnn) again. The other rules are events.
--      A rule whose AlertLog ID is disabled (SetAlertEnable) is not reported.
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

package ApbCheckerPkg is

  -- Checker rules. Each gets an AlertLog ID named as the rule (APB3_R01 -> "APB3-R01").
  -- APB4: add the APB4 rules after APB3_W02
  type ApbRuleType is (
    APB3_S01, APB3_S02, APB3_S03,             -- static, FAILURE
    APB3_R01, APB3_R02, APB3_R03, APB3_R04,   -- transitions, ERROR
    APB3_R05, APB3_R06, APB3_R07,             -- stability, ERROR
    APB3_V01, APB3_V02, APB3_V03, APB3_V04,   -- validity, ERROR
    APB3_V05, APB3_V06, APB3_V07, APB3_V08,
    APB3_W01, APB3_W02                        -- recommendations, WARNING
  );

  type ApbRuleIDArrayType is array (ApbRuleType) of AlertLogIDType;
  type ApbRuleFlagsType   is array (ApbRuleType) of boolean;

  function ApbRuleName (Rule : ApbRuleType) return string; -- "APB3-R01"
  function ApbRuleLevel (Rule : ApbRuleType) return AlertType;

  -- One child ID of ParentID per rule. APB3-W02 starts disabled; enable it with
  -- SetAlertEnable(GetAlertLogID("APB3-W02", ParentID), WARNING, TRUE).
  impure function NewApbRuleIDs (ParentID : AlertLogIDType) return ApbRuleIDArrayType;

  -- Static interface checks (APB3-S01 to S03) on the rule IDs. APB4-S01 goes to ModelID.
  procedure CheckApbInterface (
    constant ModelID  : in AlertLogIDType;
    constant RuleID   : in ApbRuleIDArrayType;
    constant Revision : in ApbRevisionType;
    constant ApbBus   : in ApbRecType
  );

  -- Bus phase at a rising edge. IDLE is PSEL LOW, whatever PENABLE is (IHI0024E 4.1)
  type ApbPhaseType is (APB_PHASE_IDLE, APB_PHASE_SETUP, APB_PHASE_ACCESS);

  -- How the transfer in progress ended at this edge
  type ApbTransferEndType is (
    APB_NO_END,     -- no transfer ended
    APB_COMPLETED,  -- SETUP, ACCESS, completion
    APB_ABANDONED,  -- the Requester left SETUP or ACCESS before completion (APB3-R01, R03)
    APB_NO_SETUP,   -- completion of an ACCESS that had no SETUP (APB3-R02, R04)
    APB_RESET       -- aborted by reset
  );

  -- Signals that APB3-W02 checks for zero when they are not required to be valid
  type ApbZeroCheckType is (ZERO_PENABLE, ZERO_PADDR, ZERO_PWRITE, ZERO_PWDATA, ZERO_PREADY, ZERO_PRDATA);
  type ApbZeroFlagsType is array (ApbZeroCheckType) of boolean;

  -- Checker state, one per interface. Constrain PADDR and PWDATA from the bus.
  type ApbCheckerStateType is record
    Phase        : ApbPhaseType;      -- phase at the previous edge
    Completed    : boolean;           -- the previous edge completed a transfer
    InTransfer   : boolean;           -- the transfer in progress started with SETUP
    BackToBack   : boolean;           -- its SETUP directly followed a completion (PSEL held)
    WaitStates   : natural;           -- ACCESS cycles with PREADY not HIGH so far
    PAddr        : std_logic_vector;  -- samples at the previous edge
    PWrite       : std_logic;
    PWData       : std_logic_vector;
    Reported     : ApbRuleFlagsType;  -- alert already given for this occurrence
    ZeroReported : ApbZeroFlagsType;  -- per signal, for APB3-W02
  end record ApbCheckerStateType;

  -- Back to IDLE, as after reset. Keeps the APB3-V01 state (checked during reset too).
  procedure InitApbChecker (variable State : inout ApbCheckerStateType);

  -- Check the APB3 rules for the samples at one rising edge and update State.
  -- When a transfer ends, TransferEnd says how, and Transfer holds it: the samples at
  -- completion, or the SETUP values and wait states so far for an incomplete transfer.
  procedure CheckApb3Cycle (
    constant RuleID      : in    ApbRuleIDArrayType;
    variable State       : inout ApbCheckerStateType;
    constant nReset      : in    std_logic;
    constant ApbBus      : in    ApbRecType;
    variable Transfer    : inout ApbTransferType;
    variable TransferEnd : out   ApbTransferEndType
  );

end package ApbCheckerPkg;

package body ApbCheckerPkg is

  ------------------------------------------------------------
  function ApbRuleName (Rule : ApbRuleType) return string is
  ------------------------------------------------------------
    constant IMAGE : string := to_upper(ApbRuleType'image(Rule));
    variable Name  : string(1 to IMAGE'length) := IMAGE;
  begin
    for i in Name'range loop
      if Name(i) = '_' then
        Name(i) := '-';
      end if;
    end loop;
    return Name;
  end function ApbRuleName;

  ------------------------------------------------------------
  function ApbRuleLevel (Rule : ApbRuleType) return AlertType is
  ------------------------------------------------------------
  begin
    case Rule is
      when APB3_S01 | APB3_S02 | APB3_S03 => return FAILURE;
      when APB3_W01 | APB3_W02            => return WARNING;
      when others                         => return ERROR;
    end case;
  end function ApbRuleLevel;

  ------------------------------------------------------------
  impure function NewApbRuleIDs (ParentID : AlertLogIDType) return ApbRuleIDArrayType is
  ------------------------------------------------------------
    variable RuleID : ApbRuleIDArrayType;
  begin
    for Rule in ApbRuleType loop
      RuleID(Rule) := NewID(ApbRuleName(Rule), ParentID => ParentID);
    end loop;
    -- Many correct designs hold their last values instead of driving zeros
    SetAlertEnable(RuleID(APB3_W02), WARNING, FALSE);
    return RuleID;
  end function NewApbRuleIDs;

  ------------------------------------------------------------
  procedure CheckApbInterface (
  ------------------------------------------------------------
    constant ModelID  : in AlertLogIDType;
    constant RuleID   : in ApbRuleIDArrayType;
    constant Revision : in ApbRevisionType;
    constant ApbBus   : in ApbRecType
  ) is
  begin
    CheckApbInterface(
      AddrWidthID     => RuleID(APB3_S01),
      DataWidthID     => RuleID(APB3_S02),
      ReadDataWidthID => RuleID(APB3_S03),
      StrbWidthID     => ModelID,
      Revision        => Revision,
      ApbBus          => ApbBus
    );
  end procedure CheckApbInterface;

  ------------------------------------------------------------
  procedure InitApbChecker (variable State : inout ApbCheckerStateType) is
  ------------------------------------------------------------
    constant V01Reported : boolean := State.Reported(APB3_V01);
  begin
    State.Phase              := APB_PHASE_IDLE;
    State.Completed          := FALSE;
    State.InTransfer         := FALSE;
    State.BackToBack         := FALSE;
    State.WaitStates         := 0;
    State.PAddr              := (State.PAddr'range => '0');
    State.PWrite             := '0';
    State.PWData             := (State.PWData'range => '0');
    State.Reported           := (others => FALSE);
    State.Reported(APB3_V01) := V01Reported;
    State.ZeroReported       := (others => FALSE);
  end procedure InitApbChecker;

  ------------------------------------------------------------
  -- Local
  function PhaseName (Phase : ApbPhaseType) return string is
  ------------------------------------------------------------
  begin
    case Phase is
      when APB_PHASE_IDLE   => return "IDLE";
      when APB_PHASE_SETUP  => return "SETUP";
      when APB_PHASE_ACCESS => return "ACCESS";
    end case;
  end function PhaseName;

  ------------------------------------------------------------
  -- Local: every bit is '0' or 'L'
  function IsZero (A : std_logic_vector) return boolean is
  ------------------------------------------------------------
  begin
    for i in A'range loop
      if to_X01(A(i)) /= '0' then
        return FALSE;
      end if;
    end loop;
    return TRUE;
  end function IsZero;

  ------------------------------------------------------------
  procedure CheckApb3Cycle (
  ------------------------------------------------------------
    constant RuleID      : in    ApbRuleIDArrayType;
    variable State       : inout ApbCheckerStateType;
    constant nReset      : in    std_logic;
    constant ApbBus      : in    ApbRecType;
    variable Transfer    : inout ApbTransferType;
    variable TransferEnd : out   ApbTransferEndType
  ) is
    alias    Req       : ApbRequesterRecType is ApbBus.Requester;
    alias    Cmp       : ApbCompleterRecType is ApbBus.Completer;
    variable Phase     : ApbPhaseType;
    variable Completed : boolean;
    variable Continues : boolean;  -- the previous edge was SETUP or an ACCESS wait state
    variable IsWrite   : boolean;
    variable IsRead    : boolean;
    variable First     : boolean;

    -- A rule whose alert is disabled is not reported at all, so it does not count as a
    -- disabled error (OSVVM fails a test on disabled errors by default)
    procedure RuleAlert (Rule : ApbRuleType; Message : string) is
    begin
      if GetAlertEnable(RuleID(Rule), ApbRuleLevel(Rule)) then
        Alert(RuleID(Rule), Message, ApbRuleLevel(Rule));
      end if;
    end procedure RuleAlert;

    -- First is TRUE on the first edge of a violation. ReArm: a stretch rule, which
    -- alerts again after an edge without the violation.
    procedure Violation (Rule : ApbRuleType; Violated, ReArm : boolean; First : out boolean) is
    begin
      First := Violated and not State.Reported(Rule);
      if Violated then
        State.Reported(Rule) := TRUE;
      elsif ReArm then
        State.Reported(Rule) := FALSE;
      end if;
    end procedure Violation;

    -- APB3-W02, once per stretch for each signal. Applies: Value is not required to be valid.
    procedure CheckZero (Check : ApbZeroCheckType; Applies : boolean; Name : string; Value : std_logic) is
      constant Violated : boolean := Applies and to_X01(Value) /= '0';
    begin
      if Violated and not State.ZeroReported(Check) then
        RuleAlert(APB3_W02, Name & " not driven to zero while it is not required to be valid: " &
              to_string(Value) & " (IHI0024E App. A.1)");
      end if;
      State.ZeroReported(Check) := Violated;
    end procedure CheckZero;

    procedure CheckZero (Check : ApbZeroCheckType; Applies : boolean; Name : string; Value : std_logic_vector) is
      constant Violated : boolean := Applies and not IsZero(Value);
    begin
      if Violated and not State.ZeroReported(Check) then
        RuleAlert(APB3_W02, Name & " not driven to zero while it is not required to be valid: " &
              to_hxstring(Value) & " (IHI0024E App. A.1)");
      end if;
      State.ZeroReported(Check) := Violated;
    end procedure CheckZero;

    -- The transfer in progress, from the samples of its earlier edges
    procedure EndIncomplete (EndType : ApbTransferEndType) is
    begin
      if State.InTransfer then
        Transfer.Addr       := SafeResize(State.PAddr, Transfer.Addr'length);
        Transfer.Write      := to_X01(State.PWrite);
        Transfer.WData      := SafeResize(State.PWData, Transfer.WData'length);
        Transfer.RData      := (Transfer.RData'range => '0');
        Transfer.SlvErr     := '0';
        Transfer.WaitStates := State.WaitStates;
        TransferEnd         := EndType;
      end if;
      State.InTransfer := FALSE;
    end procedure EndIncomplete;

  begin
    TransferEnd := APB_NO_END;

    -- APB3-V01: PSEL is always valid, also during reset (App. A.1)
    Violation(APB3_V01, not IsValid(Req.PSel), TRUE, First);
    if First then
      RuleAlert(APB3_V01, "PSEL not valid: " & to_string(Req.PSel) & " (IHI0024E App. A.1)");
    end if;

    -- Reset: the bus is IDLE and no other rule applies. A transfer in progress is aborted.
    if to_X01(nReset) /= '1' then
      EndIncomplete(APB_RESET);
      InitApbChecker(State);
      return;
    end if;

    Continues := State.Phase = APB_PHASE_SETUP or (State.Phase = APB_PHASE_ACCESS and not State.Completed);

    -- Phase at this edge (IHI0024E 4.1). An invalid PENABLE (APB3-V03) is taken as the
    -- phase the protocol expects, so it does not also break a transition rule.
    if to_X01(Req.PSel) /= '1' then
      Phase := APB_PHASE_IDLE;
    else
      case to_X01(Req.PEnable) is
        when '0'    => Phase := APB_PHASE_SETUP;
        when '1'    => Phase := APB_PHASE_ACCESS;
        when others => Phase := APB_PHASE_ACCESS when Continues else APB_PHASE_SETUP;
      end case;
    end if;
    Completed := Phase = APB_PHASE_ACCESS and to_X01(Cmp.PReady) = '1';
    IsWrite   := to_X01(Req.PWrite) = '1';
    IsRead    := to_X01(Req.PWrite) = '0';

    -- A new transfer: validity rules alert again
    if Phase /= APB_PHASE_ACCESS then
      for Rule in APB3_V02 to APB3_V08 loop
        State.Reported(Rule) := FALSE;
      end loop;
    end if;

    ------------------------------------------------------------
    -- State transitions (IHI0024E 4.1, Figure 4-1)
    ------------------------------------------------------------
    -- APB3-R01: SETUP lasts one cycle, then ACCESS
    if State.Phase = APB_PHASE_SETUP and Phase /= APB_PHASE_ACCESS then
      RuleAlert(APB3_R01, "SETUP not followed by ACCESS: the next cycle is " & PhaseName(Phase) &
            " (IHI0024E 4.1).  PADDR: " & to_hxstring(State.PAddr));
      EndIncomplete(APB_ABANDONED);
    end if;

    -- APB3-R02: ACCESS only follows SETUP or an ACCESS wait state
    if State.Phase = APB_PHASE_IDLE and Phase = APB_PHASE_ACCESS then
      RuleAlert(APB3_R02, "ACCESS without SETUP: PSEL and PENABLE HIGH directly after IDLE" &
            " (IHI0024E 4.1).  PADDR: " & to_hxstring(Req.PAddr));
    end if;

    -- APB3-R03: while PREADY is LOW the transfer stays in ACCESS
    if State.Phase = APB_PHASE_ACCESS and not State.Completed and Phase /= APB_PHASE_ACCESS then
      RuleAlert(APB3_R03, "Transfer left ACCESS before PREADY was HIGH: the next cycle is " &
            PhaseName(Phase) & " (IHI0024E 3.1.2, 4.1).  PADDR: " & to_hxstring(State.PAddr) &
            "  WaitStates: " & to_string(State.WaitStates));
      EndIncomplete(APB_ABANDONED);
    end if;

    -- APB3-R04: PENABLE is deasserted after completion
    if State.Completed and Phase = APB_PHASE_ACCESS then
      RuleAlert(APB3_R04, "PENABLE still HIGH in the cycle after completion" &
            " (IHI0024E 3.1.1, 4.1).  PADDR: " & to_hxstring(Req.PAddr));
    end if;

    ------------------------------------------------------------
    -- Stability from SETUP through ACCESS (IHI0024E 4.1, 3.1.2, 3.3.2)
    ------------------------------------------------------------
    if Phase = APB_PHASE_ACCESS and Continues then
      -- APB3-R05
      if to_X01(Req.PAddr) /= to_X01(State.PAddr) then
        RuleAlert(APB3_R05, "PADDR changed during the transfer: " & to_hxstring(State.PAddr) &
              " -> " & to_hxstring(Req.PAddr) & " (IHI0024E 4.1)");
      end if;
      -- APB3-R06
      if to_X01(Req.PWrite) /= to_X01(State.PWrite) then
        RuleAlert(APB3_R06, "PWRITE changed during the transfer: " & to_string(State.PWrite) &
              " -> " & to_string(Req.PWrite) & " (IHI0024E 4.1).  PADDR: " & to_hxstring(Req.PAddr));
      end if;
      -- APB3-R07: write transfers only
      if IsWrite and to_X01(State.PWrite) = '1' and to_X01(Req.PWData) /= to_X01(State.PWData) then
        RuleAlert(APB3_R07, "PWDATA changed during a write: " & to_hxstring(State.PWData) &
              " -> " & to_hxstring(Req.PWData) & " (IHI0024E 4.1).  PADDR: " & to_hxstring(Req.PAddr));
      end if;
    end if;

    ------------------------------------------------------------
    -- Validity (IHI0024E App. A.1), once per transfer
    ------------------------------------------------------------
    if Phase /= APB_PHASE_IDLE then
      -- APB3-V02 to V05: PSEL HIGH
      Violation(APB3_V02, not IsValid(Req.PAddr), FALSE, First);
      if First then
        RuleAlert(APB3_V02, "PADDR not valid while PSEL is HIGH: " & to_hxstring(Req.PAddr) &
              " (IHI0024E App. A.1)");
      end if;
      Violation(APB3_V03, not IsValid(Req.PEnable), FALSE, First);
      if First then
        RuleAlert(APB3_V03, "PENABLE not valid while PSEL is HIGH: " & to_string(Req.PEnable) &
              " (IHI0024E App. A.1).  PADDR: " & to_hxstring(Req.PAddr));
      end if;
      Violation(APB3_V04, not IsValid(Req.PWrite), FALSE, First);
      if First then
        RuleAlert(APB3_V04, "PWRITE not valid while PSEL is HIGH: " & to_string(Req.PWrite) &
              " (IHI0024E App. A.1).  PADDR: " & to_hxstring(Req.PAddr));
      end if;
      -- APB3 has no PSTRB, so every write data lane is active
      Violation(APB3_V05, IsWrite and not IsValid(Req.PWData), FALSE, First);
      if First then
        RuleAlert(APB3_V05, "PWDATA not valid in a write: " & to_hxstring(Req.PWData) &
              " (IHI0024E App. A.1).  PADDR: " & to_hxstring(Req.PAddr));
      end if;

      -- APB3-V06: PSEL and PENABLE HIGH
      Violation(APB3_V06, to_X01(Req.PEnable) = '1' and not IsValid(Cmp.PReady), FALSE, First);
      if First then
        RuleAlert(APB3_V06, "PREADY not valid in ACCESS: " & to_string(Cmp.PReady) &
              " (IHI0024E App. A.1).  PADDR: " & to_hxstring(Req.PAddr));
      end if;

      -- APB3-V07, V08: PSEL, PENABLE and PREADY HIGH
      Violation(APB3_V07, Completed and not IsValid(Cmp.PSlvErr), FALSE, First);
      if First then
        RuleAlert(APB3_V07, "PSLVERR not valid at completion: " & to_string(Cmp.PSlvErr) &
              " (IHI0024E App. A.1, 3.4).  PADDR: " & to_hxstring(Req.PAddr));
      end if;
      Violation(APB3_V08, Completed and IsRead and not IsValid(Cmp.PRData), FALSE, First);
      if First then
        RuleAlert(APB3_V08, "PRDATA not valid at read completion: " & to_hxstring(Cmp.PRData) &
              " (IHI0024E App. A.1).  PADDR: " & to_hxstring(Req.PAddr));
      end if;
    end if;

    ------------------------------------------------------------
    -- Recommendations, once per stretch
    ------------------------------------------------------------
    -- APB3-W01: PSLVERR LOW when PSEL, PENABLE or PREADY is LOW (IHI0024E 3.4)
    if not Completed then
      Violation(APB3_W01, to_X01(Cmp.PSlvErr) /= '0', TRUE, First);
      if First then
        RuleAlert(APB3_W01, "PSLVERR not LOW outside the completing cycle: " & to_string(Cmp.PSlvErr) &
              " (IHI0024E 3.4)");
      end if;
    end if;

    -- APB3-W02: signals not required to be valid are driven to zero (App. A.1).
    -- PSLVERR is covered by APB3-W01. Not checked while disabled (the default).
    if GetAlertEnable(RuleID(APB3_W02), WARNING) then
      CheckZero(ZERO_PENABLE, Phase = APB_PHASE_IDLE,           "PENABLE", Req.PEnable);
      CheckZero(ZERO_PADDR,   Phase = APB_PHASE_IDLE,           "PADDR",   Req.PAddr);
      CheckZero(ZERO_PWRITE,  Phase = APB_PHASE_IDLE,           "PWRITE",  Req.PWrite);
      CheckZero(ZERO_PWDATA,  Phase = APB_PHASE_IDLE or IsRead, "PWDATA",  Req.PWData);
      CheckZero(ZERO_PREADY,  Phase /= APB_PHASE_ACCESS,        "PREADY",  Cmp.PReady);
      CheckZero(ZERO_PRDATA,  not (Completed and IsRead),       "PRDATA",  Cmp.PRData);
    else
      State.ZeroReported := (others => FALSE);
    end if;

    ------------------------------------------------------------
    -- Transfer tracking
    ------------------------------------------------------------
    if Phase = APB_PHASE_SETUP then
      State.InTransfer := TRUE;
      State.BackToBack := State.Completed;
      State.WaitStates := 0;
    elsif Phase = APB_PHASE_ACCESS then
      if not Continues then
        -- ACCESS without SETUP (APB3-R02, R04): checked, but not a transfer
        State.InTransfer := FALSE;
        State.WaitStates := 0;
      end if;
      if Completed then
        Transfer.Addr       := SafeResize(Req.PAddr, Transfer.Addr'length);
        Transfer.Write      := to_X01(Req.PWrite);
        Transfer.SlvErr     := to_X01(Cmp.PSlvErr);
        Transfer.WaitStates := State.WaitStates;
        if IsWrite then
          Transfer.WData := SafeResize(Req.PWData, Transfer.WData'length);
          Transfer.RData := (Transfer.RData'range => '0');
        else
          Transfer.WData := (Transfer.WData'range => '0');
          Transfer.RData := SafeResize(Cmp.PRData, Transfer.RData'length);
        end if;
        Transfer.Strb    := (Transfer.Strb'range => '1');
        Transfer.Prot    := "000";
        TransferEnd      := APB_COMPLETED when State.InTransfer else APB_NO_SETUP;
        State.InTransfer := FALSE;
      else
        State.WaitStates := State.WaitStates + 1;
      end if;
    end if;

    State.Phase     := Phase;
    State.Completed := Completed;
    State.PAddr     := Req.PAddr;
    State.PWrite    := Req.PWrite;
    State.PWData    := Req.PWData;
  end procedure CheckApb3Cycle;

end package body ApbCheckerPkg;
