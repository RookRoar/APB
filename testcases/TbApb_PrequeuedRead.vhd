--
--  Original Author:  Kartik Desai
--
--  Description:
--      Read data queued before the reads with SendReadDataAsync: the reads
--      complete with the configured wait states only (none, then two), checked
--      to the clock cycle. Narrow queued data is placed on the byte lanes of the
--      read's PADDR. The read addresses stay queued for GetReadAddress.
--
--  Notes:
--      One process drives both transaction interfaces. Written for DATA_WIDTH 32.
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
architecture CmpPrequeuedRead of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant NUM_READS : integer := 4;
begin

  ControlProc : process
  begin
    SetTestName("TbApb_PrequeuedRead");
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
    variable Addr      : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable Available : boolean;
    variable StartTime : time;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);

    log(TbID, "Queued data, no wait states: two cycles per read");
    for i in 0 to NUM_READS - 1 loop
      SendReadDataAsync(CompleterRec, to_slv(16#7000# + i, DATA_WIDTH));
    end loop;
    WaitForClock(RequesterRec, 1);
    StartTime := now;
    for i in 0 to NUM_READS - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#7000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, NUM_READS * 2 * tperiod_Clk, "Back-to-back reads");

    log(TbID, "The read addresses stay queued for GetReadAddress");
    for i in 0 to NUM_READS - 1 loop
      GetReadAddress(CompleterRec, Addr);
      AffirmIfEqual(TbID, Addr, to_slv(4 * i, ADDR_WIDTH), "Queued read address");
    end loop;
    TryGetReadAddress(CompleterRec, Addr, Available);
    AffirmIf(TbID, not Available, "No more read addresses");

    log(TbID, "Queued data with WAIT_STATES = 2");
    SetApbOptions(CompleterRec, WAIT_STATES, 2);
    for i in 0 to NUM_READS - 1 loop
      SendReadDataAsync(CompleterRec, to_slv(16#7100# + i, DATA_WIDTH));
    end loop;
    WaitForClock(RequesterRec, 1);
    StartTime := now;
    for i in 0 to NUM_READS - 1 loop
      ReadCheck(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#7100# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, NUM_READS * (2 + 2) * tperiod_Clk, "Reads with two wait states");
    SetApbOptions(CompleterRec, WAIT_STATES, 0);

    log(TbID, "Narrow queued data goes to the byte lanes of PADDR");
    SendReadDataAsync(CompleterRec, X"AB");
    SendReadDataAsync(CompleterRec, X"CDEF");
    ReadCheck(RequesterRec, X"0000_0102", X"AB");
    ReadCheck(RequesterRec, X"0000_0105", X"CDEF");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture CmpPrequeuedRead;

configuration TbApb_PrequeuedRead of TbApb is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(CmpPrequeuedRead);
    end for;
  end for;
end TbApb_PrequeuedRead;
