--
--  Original Author:  Kartik Desai
--
--  Description:
--      Narrow and unaligned accesses on a 32-bit APB3 bus. APB3 has no PSTRB
--      (IHI0024E Table B-1), so writes of fewer than all byte lanes are rejected
--      with an ERROR on "Protocol Error" and not issued (four expected errors,
--      from Write, WriteAsync and a split WriteAddressAsync/WriteDataAsync).
--      Narrow and unaligned reads work: PADDR need not be aligned (2.1.1).
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
architecture NarrowAccess of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant EXPECTED_ERRORS : AlertCountType := (FAILURE => 0, ERROR => 4, WARNING => 0);
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_NarrowAccess");
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

    Write(RequesterRec, X"0000_0000", X"4433_2211");
    Write(RequesterRec, X"0000_0008", X"0000_0000");

    log(TbID, "Narrow and unaligned writes are rejected (expected errors)");
    StartTime := now;
    Write(RequesterRec, X"0000_0000", X"AA");
    Write(RequesterRec, X"0000_0002", X"BBBB");
    AffirmIfEqual(TbID, now, StartTime, "Rejected blocking writes return at once");
    WriteAsync(RequesterRec, X"0000_0004", X"12");
    WaitForWriteTransaction(RequesterRec);
    AffirmIfEqual(TbID, now, StartTime, "No write outstanding after a rejected WriteAsync");

    log(TbID, "A rejected split write drops its address: the next pair is not mixed up");
    WriteAddressAsync(RequesterRec, X"0000_0008");
    WriteDataAsync(RequesterRec, X"0000_0008", X"34");
    WriteAddressAsync(RequesterRec, X"0000_000C");
    WriteDataAsync(RequesterRec, X"0C0C_0C0C");
    WaitForWriteTransaction(RequesterRec);
    ReadCheck(RequesterRec, X"0000_000C", X"0C0C_0C0C");
    ReadCheck(RequesterRec, X"0000_0008", X"0000_0000");
    ReadCheck(RequesterRec, X"0000_0000", X"4433_2211");

    GetWriteTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbID, Count, 3, "Only full-width writes were issued");

    log(TbID, "Narrow and unaligned reads (PADDR as given, IHI0024E 2.1.1)");
    ReadCheck(RequesterRec, X"0000_0000", X"11");
    ReadCheck(RequesterRec, X"0000_0001", X"22");
    ReadCheck(RequesterRec, X"0000_0002", X"33");
    ReadCheck(RequesterRec, X"0000_0003", X"44");
    ReadCheck(RequesterRec, X"0000_0000", X"2211");
    ReadCheck(RequesterRec, X"0000_0001", X"3322");
    ReadCheck(RequesterRec, X"0000_0002", X"4433");
    ReadCheck(RequesterRec, X"0000_0001", X"44_3322");

    AffirmIf(TbID, GetAlertCount(FindAlertLogID("Protocol Error", ReqID)) = EXPECTED_ERRORS,
      "Requester Protocol Error: four ERRORs");
    AffirmIf(TbID, GetAlertCount(ReqID) = EXPECTED_ERRORS, "Requester: no other alerts");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

end architecture NarrowAccess;

configuration TbApbMemory_NarrowAccess of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(NarrowAccess);
    end for;
  end for;
end TbApbMemory_NarrowAccess;
