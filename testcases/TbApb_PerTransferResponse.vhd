--
--  Original Author:  Kartik Desai
--
--  Description:
--      Per-transfer response control on the test-driven ApbCompleter: the
--      PSLVERR option in force when the test answers, error injection, and
--      WAIT_STATES as the minimum number of wait states, checked to the clock
--      cycle. The Requester's expected PSLVERR follows each transfer, so no
--      alerts are expected.
--
--  Notes:
--      One process drives both transaction interfaces, using the Requester's
--      async operations.
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
architecture CmpPerTransferResponse of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");
begin

  ControlProc : process
  begin
    SetTestName("TbApb_PerTransferResponse");
    SetLogEnable(PASSED, TRUE);
    SetLogEnable(INFO, TRUE);
    wait for 0 ns; wait for 0 ns;
    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    wait until nReset = '1';
    ClearAlerts;

    WaitForBarrier(TestDone, 1 ms);
    TranscriptClose;
    EndOfTestReports(TimeOut => (now >= 1 ms));
    std.env.stop;
    wait;
  end process ControlProc;

  TestProc : process
    variable ReqID     : AlertLogIDType;
    variable CmpID     : AlertLogIDType;
    variable Addr      : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable Data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable StartTime : time;

    -- One write: the Completer answers with PSLVERR CmpSlvErr, the Requester expects ReqSlvErr
    procedure DoWrite (A : integer; CmpSlvErr, ReqSlvErr : std_logic) is
    begin
      SetApbOptions(RequesterRec, PSLVERR, ReqSlvErr);
      WriteAsync(RequesterRec, to_slv(A, ADDR_WIDTH), to_slv(A, DATA_WIDTH));
      SetApbOptions(CompleterRec, PSLVERR, CmpSlvErr);
      GetWrite(CompleterRec, Addr, Data);
      -- Changing the option after the answer does not affect this write
      SetApbOptions(CompleterRec, PSLVERR, not CmpSlvErr);
      AffirmIfEqual(TbID, Addr, to_slv(A, ADDR_WIDTH), "Write address");
      WaitForWriteTransaction(RequesterRec);
    end procedure DoWrite;

    -- One read, as DoWrite
    procedure DoRead (A : integer; CmpSlvErr, ReqSlvErr : std_logic) is
    begin
      SetApbOptions(RequesterRec, PSLVERR, ReqSlvErr);
      ReadAddressAsync(RequesterRec, to_slv(A, ADDR_WIDTH));
      SetApbOptions(CompleterRec, PSLVERR, CmpSlvErr);
      SendRead(CompleterRec, Addr, to_slv(A, DATA_WIDTH));
      SetApbOptions(CompleterRec, PSLVERR, not CmpSlvErr);
      AffirmIfEqual(TbID, Addr, to_slv(A, ADDR_WIDTH), "Read address");
      ReadData(RequesterRec, Data);
      AffirmIfEqual(TbID, Data, to_slv(A, DATA_WIDTH), "Read data");
    end procedure DoRead;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    GetAlertLogID(RequesterRec, ReqID);
    GetAlertLogID(CompleterRec, CmpID);

    log(TbID, "PSLVERR option in force when the test answers");
    DoWrite(16#00#, '0', '0');
    DoWrite(16#04#, '1', '1');
    DoWrite(16#08#, '0', '0');
    DoRead(16#0C#, '1', '1');
    DoRead(16#10#, '0', '0');
    SetApbOptions(CompleterRec, PSLVERR, '0');

    log(TbID, "Error injection: every 2nd transfer");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_N, 2);
    SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_EVERY_NTH);
    DoWrite(16#20#, '0', '0');
    DoWrite(16#24#, '0', '1');
    DoRead(16#28#, '0', '0');
    DoRead(16#2C#, '0', '1');
    SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_NONE);
    SetApbOptions(CompleterRec, PSLVERR, '0');
    SetApbOptions(RequesterRec, PSLVERR, '0');

    log(TbID, "WAIT_STATES is the minimum: per-transfer values, test answering at once");
    for WaitStates in 0 to 3 loop
      SetApbOptions(CompleterRec, WAIT_STATES, WaitStates);
      WaitForClock(RequesterRec, 1);
      StartTime := now;
      WriteAsync(RequesterRec, to_slv(16#40# + 4 * WaitStates, ADDR_WIDTH), to_slv(WaitStates, DATA_WIDTH));
      GetWrite(CompleterRec, Addr, Data);
      WaitForWriteTransaction(RequesterRec);
      AffirmIfEqual(TbID, now - StartTime, (2 + WaitStates) * tperiod_Clk,
        "Write with WAIT_STATES = " & to_string(WaitStates));
    end loop;

    log(TbID, "WAIT_STATES = 3, test answering 5 cycles late: 5 wait states, not 8");
    WaitForClock(RequesterRec, 1);
    StartTime := now;
    WriteAsync(RequesterRec, X"0000_0050", X"0000_0050");
    WaitForWriteTransaction(CompleterRec);
    WaitForClock(CompleterRec, 5);
    GetWrite(CompleterRec, Addr, Data);
    WaitForWriteTransaction(RequesterRec);
    AffirmIfEqual(TbID, now - StartTime, (2 + 5) * tperiod_Clk, "Late answer covers the minimum");
    SetApbOptions(CompleterRec, WAIT_STATES, 0);

    AffirmIf(TbID, GetAlertCount(ReqID) = AlertCountType'(0, 0, 0), "Requester: no alerts");
    AffirmIf(TbID, GetAlertCount(CmpID) = AlertCountType'(0, 0, 0), "Completer: no alerts");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture CmpPerTransferResponse;

configuration TbApb_PerTransferResponse of TbApb is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(CmpPerTransferResponse);
    end for;
  end for;
end TbApb_PerTransferResponse;
