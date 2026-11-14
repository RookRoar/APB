--
--  Original Author:  Kartik Desai
--
--  Description:
--      Transfer spacing, checked to the clock cycle: back-to-back transfers
--      (ACCESS straight to SETUP, IHI0024E 4.1) from blocking calls in the same
--      time step and from async calls, TRANSFER_IDLE_CYCLES IDLE cycles before
--      each transfer, and random spacing through SetUseRandomDelays.
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
architecture Spacing of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant NUM_WORDS   : integer := 4;
  constant IDLE_CYCLES : integer := 3;
  constant NUM_RANDOM  : integer := 40;
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_Spacing");
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

  RequesterProc : process
    variable StartTime : time;
    variable Elapsed   : time;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);

    log(TbID, "No IDLE cycles: two cycles per transfer");
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      Write(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#D000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * 2 * tperiod_Clk, "Blocking writes back-to-back");
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#D000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * 2 * tperiod_Clk, "Blocking reads back-to-back");
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      WriteAsync(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#E000# + i, DATA_WIDTH));
    end loop;
    WaitForWriteTransaction(RequesterRec);
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * 2 * tperiod_Clk, "Async writes back-to-back");

    log(TbID, "TRANSFER_IDLE_CYCLES = " & to_string(IDLE_CYCLES) & " before each transfer");
    SetApbOptions(RequesterRec, TRANSFER_IDLE_CYCLES, IDLE_CYCLES);
    WaitForClock(RequesterRec, 1);
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      Write(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#F000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * (2 + IDLE_CYCLES) * tperiod_Clk, "Blocking writes with IDLE cycles");
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#F000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * (2 + IDLE_CYCLES) * tperiod_Clk, "Blocking reads with IDLE cycles");
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      WriteAsync(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#F100# + i, DATA_WIDTH));
    end loop;
    WaitForWriteTransaction(RequesterRec);
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * (2 + IDLE_CYCLES) * tperiod_Clk, "Async writes with IDLE cycles");
    SetApbOptions(RequesterRec, TRANSFER_IDLE_CYCLES, 0);

    log(TbID, "Random spacing: runs of back-to-back transfers with 1 to 5 IDLE cycles between runs");
    SetUseRandomDelays(RequesterRec);
    StartTime := now;
    for i in 0 to NUM_RANDOM - 1 loop
      WriteAsync(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#9000# + i, DATA_WIDTH));
    end loop;
    WaitForWriteTransaction(RequesterRec);
    Elapsed := now - StartTime;
    -- At most 10 transfers per run, so at least NUM_RANDOM/10 - 1 gaps
    AffirmIf(TbID, Elapsed >= (NUM_RANDOM * 2 + NUM_RANDOM / 10 - 1) * tperiod_Clk and
                   Elapsed <= NUM_RANDOM * (2 + 5) * tperiod_Clk,
      "Random spacing: " & to_string(Elapsed / tperiod_Clk) & " cycles for " & to_string(NUM_RANDOM) & " transfers");
    SetUseRandomDelays(RequesterRec, FALSE);
    for i in 0 to NUM_RANDOM - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#9000# + i, DATA_WIDTH));
    end loop;

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

end architecture Spacing;

configuration TbApbMemory_Spacing of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(Spacing);
    end for;
  end for;
end TbApbMemory_Spacing;
