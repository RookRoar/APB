--
--  Original Author:  Kartik Desai
--
--  Description:
--      Reset in the middle of traffic. Eight async writes are queued; reset is
--      asserted during the ACCESS phase of the third. That transfer is aborted on
--      both sides (expected WARNINGs, IHI0024E does not define this case) and the
--      memory is not updated. The Requester stays IDLE during reset and runs the
--      queued writes after it, checked to the clock cycle.
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
architecture Reset of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant NUM_WORDS       : integer        := 8;
  constant ABORTED_WORD    : integer        := 2;
  constant RESET_CYCLES    : integer        := 3;
  constant EXPECTED_ALERTS : AlertCountType := (FAILURE => 0, ERROR => 0, WARNING => 2);
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_Reset");
    SetLogEnable(PASSED, TRUE);
    SetLogEnable(INFO, TRUE);
    wait for 0 ns; wait for 0 ns;
    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    wait until nReset = '1';
    ClearAlerts;

    WaitForBarrier(TestDone, 1 ms);
    TranscriptClose;
    EndOfTestReports(ExternalErrors => -EXPECTED_ALERTS, TimeOut => (now >= 1 ms));
    std.env.stop;
    wait;
  end process ControlProc;

  -- One process drives both transaction interfaces and ForceReset
  TestProc : process
    variable ReqID     : AlertLogIDType;
    variable CmpID     : AlertLogIDType;
    variable StartTime : time;
    variable Count     : integer;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    GetAlertLogID(RequesterRec, ReqID);
    GetAlertLogID(CompleterRec, CmpID);
    for i in 0 to NUM_WORDS - 1 loop
      Write(CompleterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(0, DATA_WIDTH));
    end loop;
    WaitForClock(RequesterRec, 1);

    log(TbID, "Queue " & to_string(NUM_WORDS) & " writes, then reset during the third");
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      WriteAsync(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#B000# + i, DATA_WIDTH));
    end loop;
    -- Transfer n is in SETUP at edge 2n and in ACCESS at edge 2n+1
    for i in 1 to 2 * ABORTED_WORD + 1 loop
      wait until rising_edge(Clk);
    end loop;
    ForceReset <= '1';
    for i in 1 to RESET_CYCLES loop
      wait until rising_edge(Clk);
    end loop;
    ForceReset <= '0';

    WaitForWriteTransaction(RequesterRec);
    -- Reset released after edge 2*ABORTED_WORD + 1 + RESET_CYCLES; the next
    -- transfer starts at the following edge and the rest run back-to-back
    AffirmIfEqual(TbID, now - StartTime,
      (2 * ABORTED_WORD + 1 + RESET_CYCLES + 1 + 2 * (NUM_WORDS - ABORTED_WORD - 1)) * tperiod_Clk,
      "Queued writes completed after reset");

    GetWriteTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbID, Count, NUM_WORDS, "Requester counts the aborted write as done");
    GetWriteTransactionCount(CompleterRec, Count);
    AffirmIfEqual(TbID, Count, NUM_WORDS - 1, "Memory completed every write except the aborted one");
    for i in 0 to NUM_WORDS - 1 loop
      if i = ABORTED_WORD then
        ReadCheck(CompleterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(0, DATA_WIDTH));
      else
        ReadCheck(CompleterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#B000# + i, DATA_WIDTH));
      end if;
    end loop;

    log(TbID, "Normal transfers after reset");
    Write(RequesterRec, to_slv(4 * ABORTED_WORD, ADDR_WIDTH), to_slv(16#B000# + ABORTED_WORD, DATA_WIDTH));
    for i in 0 to NUM_WORDS - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#B000# + i, DATA_WIDTH));
    end loop;

    AffirmIf(TbID, GetAlertCount(FindAlertLogID("Protocol Error", ReqID)) = AlertCountType'(0, 0, 1),
      "Requester Protocol Error: one WARNING (aborted)");
    AffirmIf(TbID, GetAlertCount(ReqID) = AlertCountType'(0, 0, 1), "Requester: no other alerts");
    AffirmIf(TbID, GetAlertCount(FindAlertLogID("Protocol Error", CmpID)) = AlertCountType'(0, 0, 1),
      "Memory Protocol Error: one WARNING (aborted)");
    AffirmIf(TbID, GetAlertCount(CmpID) = AlertCountType'(0, 0, 1), "Memory: no other alerts");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture Reset;

configuration TbApbMemory_Reset of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(Reset);
    end for;
  end for;
end TbApbMemory_Reset;
