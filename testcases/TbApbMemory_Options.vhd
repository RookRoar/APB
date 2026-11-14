--
--  Original Author:  Kartik Desai
--
--  Description:
--      Model options: the defaults from ApbSettingsPkg, Set and Get of every
--      option on the Requester and the memory (parameters and the PSLVERR
--      interface option), parameters set through the generic OSVVM
--      SetModelOptions, and unsupported options and invalid PSLVERR values
--      (four FAILUREs expected).
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
architecture Options of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant EXPECTED_ALERTS : AlertCountType := (FAILURE => 4, ERROR => 0, WARNING => 0);
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_Options");
    SetLogEnable(PASSED, TRUE);
    SetLogEnable(INFO, TRUE);
    wait for 0 ns; wait for 0 ns;
    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    wait until nReset = '1';
    ClearAlerts;
    SetAlertStopCount(FAILURE, integer'right);  -- four FAILUREs are expected

    WaitForBarrier(TestDone, 1 ms);
    TranscriptClose;
    EndOfTestReports(ExternalErrors => -EXPECTED_ALERTS, TimeOut => (now >= 1 ms));
    std.env.stop;
    wait;
  end process ControlProc;

  -- One process drives both transaction interfaces
  TestProc : process
    variable ReqID     : AlertLogIDType;
    variable CmpID     : AlertLogIDType;
    variable IntVal    : integer;
    variable BoolVal   : boolean;
    variable SlVal     : std_logic;
    variable SlvVal    : std_logic_vector(31 downto 0);
    variable AlertVal  : AlertType;
    variable InjectVal : ApbErrorInjectType;
    variable ReadVal   : ApbErrorReadDataType;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    GetAlertLogID(RequesterRec, ReqID);
    GetAlertLogID(CompleterRec, CmpID);

    ------------------------------------------------------------
    log(TbID, "Defaults from ApbSettingsPkg");
    GetApbOptions(RequesterRec, PREADY_TIME_OUT, IntVal);
    AffirmIfEqual(TbID, IntVal, APB_DEFAULT_PREADY_TIME_OUT, "PREADY_TIME_OUT default");
    GetApbOptions(RequesterRec, TRANSFER_IDLE_CYCLES, IntVal);
    AffirmIfEqual(TbID, IntVal, APB_DEFAULT_TRANSFER_IDLE_CYCLES, "TRANSFER_IDLE_CYCLES default");
    GetApbOptions(RequesterRec, PSLVERR_ALERT_LEVEL, AlertVal);
    AffirmIf(TbID, AlertVal = APB_DEFAULT_PSLVERR_ALERT_LEVEL, "PSLVERR_ALERT_LEVEL default: " & to_string(AlertVal));
    GetApbOptions(RequesterRec, PRDATA_X_CHECK, BoolVal);
    AffirmIfEqual(TbID, BoolVal, APB_DEFAULT_PRDATA_X_CHECK, "PRDATA_X_CHECK default");
    GetApbOptions(RequesterRec, PSLVERR, SlVal);
    AffirmIfEqual(TbID, SlVal, '0', "Requester PSLVERR default");

    GetApbOptions(CompleterRec, WAIT_STATES, IntVal);
    AffirmIfEqual(TbID, IntVal, APB_DEFAULT_WAIT_STATES, "WAIT_STATES default");
    GetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, InjectVal);
    AffirmIf(TbID, InjectVal = INJECT_NONE, "PSLVERR_INJECT_MODE default: " & to_string(InjectVal));
    GetApbOptions(CompleterRec, PSLVERR_INJECT_N, IntVal);
    AffirmIfEqual(TbID, IntVal, 1, "PSLVERR_INJECT_N default");
    GetApbOptions(CompleterRec, PSLVERR_INJECT_PERCENT, IntVal);
    AffirmIfEqual(TbID, IntVal, 0, "PSLVERR_INJECT_PERCENT default");
    GetApbOptions(CompleterRec, PSLVERR_INJECT_ADDR_LOW, SlvVal);
    AffirmIfEqual(TbID, SlvVal, X"0000_0000", "PSLVERR_INJECT_ADDR_LOW default");
    GetApbOptions(CompleterRec, PSLVERR_INJECT_ADDR_HIGH, SlvVal);
    AffirmIfEqual(TbID, SlvVal, X"0000_0000", "PSLVERR_INJECT_ADDR_HIGH default");
    GetApbOptions(CompleterRec, ERROR_READ_DATA, ReadVal);
    AffirmIf(TbID, ReadVal = ERROR_DATA_MEMORY, "ERROR_READ_DATA default: " & to_string(ReadVal));
    GetApbOptions(CompleterRec, ERROR_WRITE_UPDATES, BoolVal);
    AffirmIfEqual(TbID, BoolVal, FALSE, "ERROR_WRITE_UPDATES default");
    GetApbOptions(CompleterRec, PSLVERR, SlVal);
    AffirmIfEqual(TbID, SlVal, '0', "Memory PSLVERR default");

    ------------------------------------------------------------
    log(TbID, "Set and Get every Requester option");
    SetApbOptions(RequesterRec, PREADY_TIME_OUT, 17);
    GetApbOptions(RequesterRec, PREADY_TIME_OUT, IntVal);
    AffirmIfEqual(TbID, IntVal, 17, "PREADY_TIME_OUT");
    SetApbOptions(RequesterRec, TRANSFER_IDLE_CYCLES, 2);
    GetApbOptions(RequesterRec, TRANSFER_IDLE_CYCLES, IntVal);
    AffirmIfEqual(TbID, IntVal, 2, "TRANSFER_IDLE_CYCLES");
    SetApbOptions(RequesterRec, PSLVERR_ALERT_LEVEL, WARNING);
    GetApbOptions(RequesterRec, PSLVERR_ALERT_LEVEL, AlertVal);
    AffirmIf(TbID, AlertVal = WARNING, "PSLVERR_ALERT_LEVEL: " & to_string(AlertVal));
    SetApbOptions(RequesterRec, PRDATA_X_CHECK, FALSE);
    GetApbOptions(RequesterRec, PRDATA_X_CHECK, BoolVal);
    AffirmIfEqual(TbID, BoolVal, FALSE, "PRDATA_X_CHECK");
    SetApbOptions(RequesterRec, PSLVERR, '-');
    GetApbOptions(RequesterRec, PSLVERR, SlVal);
    AffirmIfEqual(TbID, SlVal, '-', "Requester PSLVERR");

    log(TbID, "Set and Get every memory option");
    SetApbOptions(CompleterRec, WAIT_STATES, 3);
    GetApbOptions(CompleterRec, WAIT_STATES, IntVal);
    AffirmIfEqual(TbID, IntVal, 3, "WAIT_STATES");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_ADDRESS_RANGE);
    GetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, InjectVal);
    AffirmIf(TbID, InjectVal = INJECT_ADDRESS_RANGE, "PSLVERR_INJECT_MODE: " & to_string(InjectVal));
    SetApbOptions(CompleterRec, PSLVERR_INJECT_N, 7);
    GetApbOptions(CompleterRec, PSLVERR_INJECT_N, IntVal);
    AffirmIfEqual(TbID, IntVal, 7, "PSLVERR_INJECT_N");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_PERCENT, 25);
    GetApbOptions(CompleterRec, PSLVERR_INJECT_PERCENT, IntVal);
    AffirmIfEqual(TbID, IntVal, 25, "PSLVERR_INJECT_PERCENT");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_ADDR_LOW, X"8000_0000");
    GetApbOptions(CompleterRec, PSLVERR_INJECT_ADDR_LOW, SlvVal);
    AffirmIfEqual(TbID, SlvVal, X"8000_0000", "PSLVERR_INJECT_ADDR_LOW");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_ADDR_HIGH, X"FFFF_FFFF");
    GetApbOptions(CompleterRec, PSLVERR_INJECT_ADDR_HIGH, SlvVal);
    AffirmIfEqual(TbID, SlvVal, X"FFFF_FFFF", "PSLVERR_INJECT_ADDR_HIGH");
    SetApbOptions(CompleterRec, ERROR_READ_DATA, ERROR_DATA_ZERO);
    GetApbOptions(CompleterRec, ERROR_READ_DATA, ReadVal);
    AffirmIf(TbID, ReadVal = ERROR_DATA_ZERO, "ERROR_READ_DATA: " & to_string(ReadVal));
    SetApbOptions(CompleterRec, ERROR_WRITE_UPDATES, TRUE);
    GetApbOptions(CompleterRec, ERROR_WRITE_UPDATES, BoolVal);
    AffirmIfEqual(TbID, BoolVal, TRUE, "ERROR_WRITE_UPDATES");
    SetApbOptions(CompleterRec, PSLVERR, '1');
    GetApbOptions(CompleterRec, PSLVERR, SlVal);
    AffirmIfEqual(TbID, SlVal, '1', "Memory PSLVERR");

    log(TbID, "Parameters through the generic OSVVM SetModelOptions / GetModelOptions transactions");
    SetModelOptions(RequesterRec, to_integer(TRANSFER_IDLE_CYCLES), 4);
    GetApbOptions(RequesterRec, TRANSFER_IDLE_CYCLES, IntVal);
    AffirmIfEqual(TbID, IntVal, 4, "TRANSFER_IDLE_CYCLES through SetModelOptions");
    GetModelOptions(CompleterRec, to_integer(PSLVERR_INJECT_N), IntVal);
    AffirmIfEqual(TbID, IntVal, 7, "PSLVERR_INJECT_N through GetModelOptions");

    ------------------------------------------------------------
    log(TbID, "Unsupported options and invalid PSLVERR values (four FAILUREs expected)");
    SetApbOptions(RequesterRec, PPROT, 1);
    GetApbOptions(CompleterRec, PSTRB, IntVal);
    SetApbOptions(RequesterRec, PSLVERR, 'X');
    SetApbOptions(CompleterRec, PSLVERR, '-');
    GetApbOptions(RequesterRec, PSLVERR, SlVal);
    AffirmIfEqual(TbID, SlVal, '-', "Requester PSLVERR unchanged");
    GetApbOptions(CompleterRec, PSLVERR, SlVal);
    AffirmIfEqual(TbID, SlVal, '1', "Memory PSLVERR unchanged");

    AffirmIf(TbID, GetAlertCount(ReqID) = AlertCountType'(2, 0, 0), "Requester: two FAILUREs");
    AffirmIf(TbID, GetAlertCount(CmpID) = AlertCountType'(2, 0, 0), "Memory: two FAILUREs");

    ------------------------------------------------------------
    log(TbID, "Transfers with the changed options: memory always answers PSLVERR = 1");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_NONE);
    Write(RequesterRec, X"0000_0000", X"0000_00AA");  -- updates: ERROR_WRITE_UPDATES = TRUE
    ReadCheck(CompleterRec, X"0000_0000", X"0000_00AA");
    ReadCheck(RequesterRec, X"0000_0000", X"0000_00AA");  -- PSLVERR = 1: not checked

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture Options;

configuration TbApbMemory_Options of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(Options);
    end for;
  end for;
end TbApbMemory_Options;
