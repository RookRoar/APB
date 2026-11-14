--
--  Original Author:  Kartik Desai
--
--  Description:
--      ReadPoll: the Requester polls a status word until a bit set later
--      through the memory backdoor reads as '1', then until it is cleared.
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
architecture PollStatus of TestCtrl is
  signal   TestDone   : BarrierType;
  signal   StatusInit : BarrierType;
  constant TbID       : AlertLogIDType := NewID("TB");
  signal   SetTime    : time           := 0 ns;
  signal   ClearTime  : time           := 0 ns;

  constant STATUS_ADDR : integer := 16#20#;
  constant READY_BIT   : integer := 5;
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_ReadPoll");
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
    variable Data  : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable Count : integer;
  begin
    wait until nReset = '1';
    WaitForBarrier(StatusInit);
    WaitForClock(RequesterRec, 2);

    log(TbID, "Poll until the ready bit is set");
    ReadPoll(RequesterRec, to_slv(STATUS_ADDR, ADDR_WIDTH), Data, READY_BIT, '1', WaitTime => 2);
    AffirmIfEqual(TbID, Data(READY_BIT), '1', "Ready bit after poll");
    AffirmIf(TbID, SetTime > 0 ns and now > SetTime, "Poll ended after the bit was set");
    GetReadTransactionCount(RequesterRec, Count);
    AffirmIf(TbID, Count > 1, "More than one read while polling: " & to_string(Count));

    log(TbID, "Poll until the ready bit is cleared");
    ReadPoll(RequesterRec, to_slv(STATUS_ADDR, ADDR_WIDTH), READY_BIT, '0', WaitTime => 2);
    AffirmIf(TbID, ClearTime > SetTime and now > ClearTime, "Poll ended after the bit was cleared");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

  CompleterProc : process
  begin
    wait until nReset = '1';
    -- A never-written location reads as 'U', so initialise the status word
    Write(CompleterRec, to_slv(STATUS_ADDR, ADDR_WIDTH), to_slv(0, DATA_WIDTH));
    WaitForBarrier(StatusInit);

    WaitForClock(CompleterRec, 30);
    Write(CompleterRec, to_slv(STATUS_ADDR, ADDR_WIDTH), to_slv(2**READY_BIT, DATA_WIDTH));
    SetTime <= now;

    WaitForClock(CompleterRec, 20);
    Write(CompleterRec, to_slv(STATUS_ADDR, ADDR_WIDTH), to_slv(0, DATA_WIDTH));
    ClearTime <= now;

    WaitForBarrier(TestDone);
    wait;
  end process CompleterProc;

end architecture PollStatus;

configuration TbApbMemory_ReadPoll of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(PollStatus);
    end for;
  end for;
end TbApbMemory_ReadPoll;
