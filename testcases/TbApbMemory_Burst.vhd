--
--  Original Author:  Kartik Desai
--
--  Description:
--      Bursts as back-to-back single transfers at incrementing word addresses,
--      in word and byte burst FIFO mode. Read bursts may start unaligned and end
--      mid-word. APB3 write bursts must be word aligned and whole words (no
--      PSTRB): three rejected write bursts are expected errors, and their data is
--      removed from the burst FIFO.
--
--  Notes:
--      Written for DATA_WIDTH 32.
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
architecture Burst of TestCtrl is
  signal   TestDone   : BarrierType;
  signal   WritesDone : BarrierType;
  constant TbID       : AlertLogIDType := NewID("TB");

  constant EXPECTED_ERRORS : AlertCountType := (FAILURE => 0, ERROR => 3, WARNING => 0);
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_Burst");
    SetLogEnable(PASSED, TRUE);
    SetLogEnable(INFO, TRUE);
    wait for 0 ns; wait for 0 ns;
    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    wait until nReset = '1';
    ClearAlerts;

    WaitForBarrier(TestDone, 1 ms);
    TranscriptClose;
    EndOfTestReports(ExternalErrors => -EXPECTED_ERRORS, TimeOut => (now >= 1 ms));
    std.env.stop;
    wait;
  end process ControlProc;

  RequesterProc : process
    variable ReqID     : AlertLogIDType;
    variable Count     : integer;
    variable StartTime : time;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    GetAlertLogID(RequesterRec, ReqID);

    log(TbID, "Word mode: 8-word burst runs back-to-back");
    StartTime := now;
    WriteBurstIncrement(RequesterRec, X"0000_0100", X"0000_1000", 8);
    AffirmIfEqual(TbID, now - StartTime, 8 * 2 * tperiod_Clk, "8 back-to-back transfers");
    ReadCheckBurstIncrement(RequesterRec, X"0000_0100", X"0000_1000", 8);

    WriteBurstVector(RequesterRec, X"0000_0200", (16#11#, 16#22#, 16#33#, 16#44#), DATA_WIDTH);
    ReadCheckBurstVector(RequesterRec, X"0000_0200", (16#11#, 16#22#, 16#33#, 16#44#), DATA_WIDTH);

    WriteBurstRandomAsync(RequesterRec, X"0000_0300", X"1234_5678", 5);
    WaitForWriteTransaction(RequesterRec);
    ReadCheckBurstRandom(RequesterRec, X"0000_0300", X"1234_5678", 5);

    GetWriteTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbID, Count, 8 + 4 + 5, "Write transfers in word mode");
    WaitForBarrier(WritesDone);

    log(TbID, "Byte mode: whole-word write bursts, any read bursts");
    SetBurstMode(RequesterRec, ADDRESS_BUS_BURST_BYTE_MODE);
    WriteBurstVector(RequesterRec, X"0000_0400", (1, 2, 3, 4, 5, 6, 7, 8), 8);
    ReadCheckBurstVector(RequesterRec, X"0000_0400", (1, 2, 3, 4, 5, 6, 7, 8), 8);
    -- Unaligned start, ending mid-word: reads at 0x400 and 0x404
    ReadCheckBurstVector(RequesterRec, X"0000_0401", (2, 3, 4, 5, 6), 8);
    ReadCheckBurstVector(RequesterRec, X"0000_0400", (1, 2, 3), 8);

    log(TbID, "Byte mode: unaligned and partial-word write bursts are rejected (expected errors)");
    WriteBurstVector(RequesterRec, X"0000_0501", (16#A1#, 16#A2#, 16#A3#, 16#A4#), 8);
    WriteBurstVector(RequesterRec, X"0000_0500", (16#B1#, 16#B2#, 16#B3#), 8);
    -- The rejected bursts' data was removed: the next burst writes its own data
    WriteBurstVector(RequesterRec, X"0000_0500", (16#C1#, 16#C2#, 16#C3#, 16#C4#), 8);
    ReadCheckBurstVector(RequesterRec, X"0000_0500", (16#C1#, 16#C2#, 16#C3#, 16#C4#), 8);

    log(TbID, "Word mode: unaligned write burst is rejected (expected error)");
    SetBurstMode(RequesterRec, ADDRESS_BUS_BURST_WORD_MODE);
    WriteBurstIncrement(RequesterRec, X"0000_0602", X"0000_6000", 2);
    WriteBurstIncrement(RequesterRec, X"0000_0600", X"0000_7000", 2);
    ReadCheckBurstIncrement(RequesterRec, X"0000_0600", X"0000_7000", 2);

    GetWriteTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbID, Count, 17 + 2 + 1 + 2, "Write transfers in total");
    AffirmIf(TbID, GetAlertCount(FindAlertLogID("Protocol Error", ReqID)) = EXPECTED_ERRORS,
      "Requester Protocol Error: three ERRORs");
    AffirmIf(TbID, GetAlertCount(ReqID) = EXPECTED_ERRORS, "Requester: no other alerts");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

  CompleterProc : process
  begin
    wait until nReset = '1';
    WaitForBarrier(WritesDone);
    log(TbID, "Word-mode bursts at incrementing word addresses (IHI0024E 2.1.1: byte addresses)");
    for i in 0 to 7 loop
      ReadCheck(CompleterRec, to_slv(16#100# + 4 * i, ADDR_WIDTH), to_slv(16#1000# + i, DATA_WIDTH));
    end loop;
    ReadCheck(CompleterRec, X"0000_020C", X"0000_0044");
    WaitForBarrier(TestDone);
    wait;
  end process CompleterProc;

end architecture Burst;

configuration TbApbMemory_Burst of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(Burst);
    end for;
  end for;
end TbApbMemory_Burst;
