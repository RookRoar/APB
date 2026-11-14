--
--  Original Author:  Kartik Desai
--
--  Description:
--      ApbRequester to ApbCompleterMemory: blocking Write, Read and ReadCheck,
--      backdoor access to the memory, transaction counts, and back-to-back
--      transfers from blocking calls made in the same time step.
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
architecture BasicReadWrite of TestCtrl is
  signal   TestDone      : BarrierType;
  signal   WritesDone    : BarrierType;
  constant TbRequesterID : AlertLogIDType := NewID("TB Requester Proc");
  constant TbCompleterID : AlertLogIDType := NewID("TB Completer Proc");

  constant NUM_WORDS : integer := 16;
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_BasicReadWrite");
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
    variable Data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable Count     : integer;
    variable StartTime : time;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);

    log(TbRequesterID, "Write " & to_string(NUM_WORDS) & " words");
    Write(RequesterRec, to_slv(0, ADDR_WIDTH), to_slv(16#1000#, DATA_WIDTH));
    -- Blocking calls in the same time step run back-to-back: ACCESS goes straight to
    -- SETUP (IHI0024E 4.1), so every further write takes exactly two cycles
    StartTime := now;
    for i in 1 to NUM_WORDS - 1 loop
      Write(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#1000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbRequesterID, now - StartTime, (NUM_WORDS - 1) * 2 * tperiod_Clk,
      "Back-to-back blocking writes");
    WaitForBarrier(WritesDone);

    log(TbRequesterID, "Read back with ReadCheck and Read");
    for i in 0 to NUM_WORDS - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#1000# + i, DATA_WIDTH));
    end loop;
    Read(RequesterRec, to_slv(4 * 5, ADDR_WIDTH), Data);
    AffirmIfEqual(TbRequesterID, Data, to_slv(16#1005#, DATA_WIDTH), "Read data");

    log(TbRequesterID, "Read a location written through the memory backdoor");
    ReadCheck(RequesterRec, to_slv(16#100#, ADDR_WIDTH), to_slv(16#CAFE#, DATA_WIDTH));

    GetWriteTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbRequesterID, Count, NUM_WORDS, "Requester write transaction count");
    GetReadTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbRequesterID, Count, NUM_WORDS + 2, "Requester read transaction count");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

  CompleterProc : process
    variable Count : integer;
  begin
    wait until nReset = '1';
    -- Backdoor write, read later over the bus
    Write(CompleterRec, to_slv(16#100#, ADDR_WIDTH), to_slv(16#CAFE#, DATA_WIDTH));

    WaitForBarrier(WritesDone);
    log(TbCompleterID, "Check the bus writes through the memory backdoor");
    for i in 0 to NUM_WORDS - 1 loop
      ReadCheck(CompleterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#1000# + i, DATA_WIDTH));
    end loop;
    GetWriteTransactionCount(CompleterRec, Count);
    AffirmIfEqual(TbCompleterID, Count, NUM_WORDS, "Memory write transaction count");

    WaitForBarrier(TestDone);
    wait;
  end process CompleterProc;

end architecture BasicReadWrite;

configuration TbApbMemory_BasicReadWrite of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(BasicReadWrite);
    end for;
  end for;
end TbApbMemory_BasicReadWrite;
