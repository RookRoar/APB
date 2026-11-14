--
--  Original Author:  Kartik Desai
--
--  Description:
--      ReadCheck and ReadCheckData: matching data passes, don't-care bits ('-')
--      match anything, and two mismatches are reported on "Data Check" as
--      expected errors.
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
architecture CheckReads of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant NUM_WORDS       : integer        := 4;
  constant EXPECTED_ERRORS : AlertCountType := (FAILURE => 0, ERROR => 2, WARNING => 0);
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_ReadCheck");
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
    variable ReqID    : AlertLogIDType;
    variable Expected : std_logic_vector(DATA_WIDTH - 1 downto 0);
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    GetAlertLogID(RequesterRec, ReqID);

    for i in 0 to NUM_WORDS - 1 loop
      Write(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#A000# + i, DATA_WIDTH));
    end loop;

    log(TbID, "Matching data passes");
    for i in 0 to NUM_WORDS - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#A000# + i, DATA_WIDTH));
    end loop;
    ReadAddressAsync(RequesterRec, to_slv(4, ADDR_WIDTH));
    ReadCheckData(RequesterRec, to_slv(16#A001#, DATA_WIDTH));

    log(TbID, "Don't-care bits match anything");
    Expected             := to_slv(16#A002#, DATA_WIDTH);
    Expected(3 downto 0) := "----";
    ReadCheck(RequesterRec, to_slv(8, ADDR_WIDTH), Expected);

    log(TbID, "Two mismatches: expected errors on Data Check");
    ReadCheck(RequesterRec, to_slv(4, ADDR_WIDTH), to_slv(16#BAD1#, DATA_WIDTH));
    ReadAddressAsync(RequesterRec, to_slv(12, ADDR_WIDTH));
    ReadCheckData(RequesterRec, to_slv(16#BAD3#, DATA_WIDTH));

    AffirmIf(TbID, GetAlertCount(FindAlertLogID("Data Check", ReqID)) = EXPECTED_ERRORS,
      "Requester Data Check: two ERRORs");
    AffirmIf(TbID, GetAlertCount(ReqID) = EXPECTED_ERRORS, "Requester: no other alerts");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

end architecture CheckReads;

configuration TbApbMemory_ReadCheck of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(CheckReads);
    end for;
  end for;
end TbApbMemory_ReadCheck;
