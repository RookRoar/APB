--
--  Original Author:  Kartik Desai
--
--  Description:
--      The test does not answer a transfer on the ApbCompleter: the Requester
--      times out (expected FAILURE on "No response"), the Completer reports the
--      aborted transfer (expected WARNING on "Protocol Error"), and the Monitor
--      reports the abandoned transfer (expected ERROR on APB3-R03). The aborted
--      write is dropped, so the test does not see it; an aborted read's address
--      stays queued. Transfers work again afterwards.
--
--  Notes:
--      One process drives both transaction interfaces.
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
architecture CmpNoAnswer of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant TIME_OUT        : integer        := 5;
  constant EXPECTED_ALERTS : AlertCountType := (FAILURE => 2, ERROR => 2, WARNING => 2);
begin

  ControlProc : process
  begin
    SetTestName("TbApb_NoAnswer");
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

  TestProc : process
    variable ReqID     : AlertLogIDType;
    variable CmpID     : AlertLogIDType;
    variable MonitorID : AlertLogIDType;
    variable Addr      : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable Data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable Available : boolean;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    GetAlertLogID(RequesterRec, ReqID);
    GetAlertLogID(CompleterRec, CmpID);
    MonitorID := FindAlertLogID("ApbMonitor");
    SetApbOptions(RequesterRec, PREADY_TIME_OUT, TIME_OUT);

    log(TbID, "Unanswered write: Requester timeout (expected FAILURE), Completer abort (expected WARNING)");
    Write(RequesterRec, X"0000_0010", X"DEAD_BEEF");
    WaitForClock(RequesterRec, 2);
    TryGetWrite(CompleterRec, Addr, Data, Available);
    AffirmIf(TbID, not Available, "The aborted write was dropped");

    log(TbID, "Unanswered read: same alerts; its address stays queued");
    Read(RequesterRec, X"0000_0020", Data);
    WaitForClock(RequesterRec, 2);
    TryGetReadAddress(CompleterRec, Addr, Available);
    AffirmIf(TbID, Available, "The aborted read's address is still queued");
    AffirmIfEqual(TbID, Addr, X"0000_0020", "Aborted read address");

    log(TbID, "Answered transfers work again");
    WriteAsync(RequesterRec, X"0000_0030", X"0000_3030");
    GetWrite(CompleterRec, Addr, Data);
    AffirmIfEqual(TbID, Addr, X"0000_0030", "Write address after the timeouts");
    AffirmIfEqual(TbID, Data, X"0000_3030", "Write data after the timeouts");
    WaitForWriteTransaction(RequesterRec);
    ReadAddressAsync(RequesterRec, X"0000_0034");
    SendRead(CompleterRec, Addr, X"0000_3434");
    AffirmIfEqual(TbID, Addr, X"0000_0034", "Read address after the timeouts");
    ReadCheckData(RequesterRec, X"0000_3434");

    AffirmIf(TbID, GetAlertCount(FindAlertLogID("No response", ReqID)) = AlertCountType'(2, 0, 0),
      "Requester No response: two FAILUREs");
    AffirmIf(TbID, GetAlertCount(ReqID) = AlertCountType'(2, 0, 0), "Requester: no other alerts");
    AffirmIf(TbID, GetAlertCount(FindAlertLogID("Protocol Error", CmpID)) = AlertCountType'(0, 0, 2),
      "Completer Protocol Error: two WARNINGs (aborted)");
    AffirmIf(TbID, GetAlertCount(CmpID) = AlertCountType'(0, 0, 2), "Completer: no other alerts");
    -- The Requester leaves ACCESS while PREADY is LOW (IHI0024E 3.1.2)
    AffirmIf(TbID, GetAlertCount(FindAlertLogID("APB3-R03", MonitorID)) = AlertCountType'(0, 2, 0),
      "Monitor APB3-R03: two ERRORs (transfers abandoned)");
    AffirmIf(TbID, GetAlertCount(MonitorID) = AlertCountType'(0, 2, 0), "Monitor: no other alerts");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture CmpNoAnswer;

configuration TbApb_NoAnswer of TbApb is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(CmpNoAnswer);
    end for;
  end for;
end TbApb_NoAnswer;
