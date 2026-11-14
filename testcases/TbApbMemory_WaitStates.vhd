--
--  Original Author:  Kartik Desai
--
--  Description:
--      Completer wait states, checked to the clock cycle: fixed WAIT_STATES,
--      exactly PREADY_TIME_OUT wait states (still accepted, IHI0024E 3.3.2 allows
--      any number), and random wait states through SetUseRandomDelays on the
--      memory.
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
architecture WaitStates of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant NUM_WORDS   : integer := 4;
  constant WAIT_CYCLES : integer := 3;
  constant NUM_RANDOM  : integer := 40;
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_WaitStates");
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

  -- One process drives both transaction interfaces
  TestProc : process
    variable StartTime : time;
    variable Elapsed   : time;
    variable TimeOut   : integer;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);

    log(TbID, "WAIT_STATES = " & to_string(WAIT_CYCLES));
    SetApbOptions(CompleterRec, WAIT_STATES, WAIT_CYCLES);
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      Write(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#5000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * (2 + WAIT_CYCLES) * tperiod_Clk, "Writes with wait states");
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#5000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * (2 + WAIT_CYCLES) * tperiod_Clk, "Reads with wait states");

    log(TbID, "Exactly PREADY_TIME_OUT wait states is accepted");
    GetApbOptions(RequesterRec, PREADY_TIME_OUT, TimeOut);
    SetApbOptions(CompleterRec, WAIT_STATES, TimeOut);
    StartTime := now;
    Write(RequesterRec, to_slv(16#40#, ADDR_WIDTH), to_slv(16#4040#, DATA_WIDTH));
    AffirmIfEqual(TbID, now - StartTime, (2 + TimeOut) * tperiod_Clk, "Write with PREADY_TIME_OUT wait states");

    log(TbID, "WAIT_STATES = 0");
    SetApbOptions(CompleterRec, WAIT_STATES, 0);
    StartTime := now;
    ReadCheck(RequesterRec, to_slv(16#40#, ADDR_WIDTH), to_slv(16#4040#, DATA_WIDTH));
    AffirmIfEqual(TbID, now - StartTime, 2 * tperiod_Clk, "Read with no wait states");

    log(TbID, "Random wait states: runs with none, then one transfer with 1 to 5");
    SetUseRandomDelays(CompleterRec);
    WaitForClock(RequesterRec, 1);
    StartTime := now;
    for i in 0 to NUM_RANDOM - 1 loop
      Write(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#6000# + i, DATA_WIDTH));
    end loop;
    Elapsed := now - StartTime;
    AffirmIf(TbID, Elapsed >= (NUM_RANDOM * 2 + NUM_RANDOM / 10 - 1) * tperiod_Clk and
                   Elapsed <= NUM_RANDOM * (2 + 5) * tperiod_Clk,
      "Random wait states: " & to_string(Elapsed / tperiod_Clk) & " cycles for " & to_string(NUM_RANDOM) & " transfers");
    for i in 0 to NUM_RANDOM - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#6000# + i, DATA_WIDTH));
    end loop;
    SetUseRandomDelays(CompleterRec, FALSE);

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture WaitStates;

configuration TbApbMemory_WaitStates of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(WaitStates);
    end for;
  end for;
end TbApbMemory_WaitStates;
