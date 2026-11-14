--
--  Original Author:  Kartik Desai
--
--  Description:
--      PREADY timeout: with more Completer wait states than PREADY_TIME_OUT, a
--      write and a read are abandoned with a FAILURE on "No response"
--      (expected); the memory sees each transfer aborted (expected WARNING) and
--      does not update. The Monitor reports each abandoned transfer on APB3-R03
--      (expected ERROR). Transfers work again afterwards, and PREADY_TIME_OUT = 0
--      removes the limit.
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
architecture Timeout of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant TIME_OUT        : integer        := 5;
  constant EXPECTED_ALERTS : AlertCountType := (FAILURE => 2, ERROR => 2, WARNING => 2);
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_Timeout");
    SetLogEnable(PASSED, TRUE);
    SetLogEnable(INFO, TRUE);
    wait for 0 ns; wait for 0 ns;
    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    wait until nReset = '1';
    ClearAlerts;
    SetAlertStopCount(FAILURE, integer'right);  -- the timeout FAILUREs are expected

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
    variable MonitorID : AlertLogIDType;
    variable Data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable StartTime : time;
    variable Count     : integer;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    GetAlertLogID(RequesterRec, ReqID);
    GetAlertLogID(CompleterRec, CmpID);
    MonitorID := FindAlertLogID("ApbMonitor");
    Write(CompleterRec, X"0000_0010", X"0000_0000");

    log(TbID, "Wait states above PREADY_TIME_OUT: write and read time out (expected FAILUREs)");
    SetApbOptions(RequesterRec, PREADY_TIME_OUT, TIME_OUT);
    SetApbOptions(CompleterRec, WAIT_STATES, TIME_OUT + 5);
    WaitForClock(RequesterRec, 1);
    StartTime := now;
    Write(RequesterRec, X"0000_0010", X"0000_1111");
    -- Abandoned once more than PREADY_TIME_OUT wait states have passed
    AffirmIfEqual(TbID, now - StartTime, (TIME_OUT + 2) * tperiod_Clk, "Time to write timeout");
    Read(RequesterRec, X"0000_0010", Data);
    ReadCheck(CompleterRec, X"0000_0010", X"0000_0000");  -- the aborted write did not update

    GetWriteTransactionCount(CompleterRec, Count);
    AffirmIfEqual(TbID, Count, 0, "Memory completed no write");
    GetReadTransactionCount(CompleterRec, Count);
    AffirmIfEqual(TbID, Count, 0, "Memory completed no read");

    log(TbID, "Exactly PREADY_TIME_OUT wait states: transfers work again");
    SetApbOptions(CompleterRec, WAIT_STATES, TIME_OUT);
    Write(RequesterRec, X"0000_0010", X"0000_2222");
    ReadCheck(RequesterRec, X"0000_0010", X"0000_2222");

    log(TbID, "PREADY_TIME_OUT = 0: no limit");
    SetApbOptions(RequesterRec, PREADY_TIME_OUT, 0);
    SetApbOptions(CompleterRec, WAIT_STATES, 100);
    Write(RequesterRec, X"0000_0010", X"0000_3333");
    ReadCheck(RequesterRec, X"0000_0010", X"0000_3333");
    SetApbOptions(CompleterRec, WAIT_STATES, 0);

    AffirmIf(TbID, GetAlertCount(FindAlertLogID("No response", ReqID)) = AlertCountType'(2, 0, 0),
      "Requester No response: two FAILUREs");
    AffirmIf(TbID, GetAlertCount(ReqID) = AlertCountType'(2, 0, 0), "Requester: no other alerts");
    AffirmIf(TbID, GetAlertCount(FindAlertLogID("Protocol Error", CmpID)) = AlertCountType'(0, 0, 2),
      "Memory Protocol Error: two WARNINGs (transfers aborted)");
    AffirmIf(TbID, GetAlertCount(CmpID) = AlertCountType'(0, 0, 2), "Memory: no other alerts");
    -- The Requester leaves ACCESS while PREADY is LOW (IHI0024E 3.1.2)
    AffirmIf(TbID, GetAlertCount(FindAlertLogID("APB3-R03", MonitorID)) = AlertCountType'(0, 2, 0),
      "Monitor APB3-R03: two ERRORs (transfers abandoned)");
    AffirmIf(TbID, GetAlertCount(MonitorID) = AlertCountType'(0, 2, 0), "Monitor: no other alerts");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture Timeout;

configuration TbApbMemory_Timeout of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(Timeout);
    end for;
  end for;
end TbApbMemory_Timeout;
