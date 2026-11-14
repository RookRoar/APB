--
--  Original Author:  Kartik Desai
--
--  Description:
--      Split and Try operations on the test-driven ApbCompleter:
--      GetWriteAddress / GetWriteData, GetReadAddress / SendReadData, TryGetWrite,
--      TryGetWriteAddress, TryGetWriteData, TryGetReadAddress, TrySendRead, and
--      the WaitForTransaction directives. A test that answers late adds wait
--      states, checked to the clock cycle.
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
architecture CmpSplitOps of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant LATE : integer := 5;
begin

  ControlProc : process
  begin
    SetTestName("TbApb_SplitOps");
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
    variable Data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable Available : boolean;
    variable StartTime : time;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);

    log(TbID, "Nothing available yet: every Try returns FALSE");
    TryGetWrite(CompleterRec, Addr, Data, Available);
    AffirmIf(TbID, not Available, "TryGetWrite: not available");
    TryGetWriteAddress(CompleterRec, Addr, Available);
    AffirmIf(TbID, not Available, "TryGetWriteAddress: not available");
    TryGetWriteData(CompleterRec, Data, Available);
    AffirmIf(TbID, not Available, "TryGetWriteData: not available");
    TryGetReadAddress(CompleterRec, Addr, Available);
    AffirmIf(TbID, not Available, "TryGetReadAddress: not available");
    TrySendRead(CompleterRec, Addr, X"0000_0000", Available);
    AffirmIf(TbID, not Available, "TrySendRead: not available");

    log(TbID, "GetWriteAddress then GetWriteData, answered " & to_string(LATE) & " cycles late");
    WaitForClock(RequesterRec, 1);
    StartTime := now;
    WriteAsync(RequesterRec, X"0000_0010", X"1234_5678");
    WaitForWriteTransaction(CompleterRec);
    WaitForClock(CompleterRec, LATE);
    GetWriteAddress(CompleterRec, Addr);
    AffirmIfEqual(TbID, Addr, X"0000_0010", "GetWriteAddress");
    TryGetWriteAddress(CompleterRec, Addr, Available);
    AffirmIf(TbID, not Available, "Address already taken");
    GetWriteData(CompleterRec, Data(15 downto 0));
    AffirmIfEqual(TbID, Data(15 downto 0), X"5678", "GetWriteData, 2 bytes");
    WaitForWriteTransaction(RequesterRec);
    -- SETUP, LATE wait states while the test is late, then the completing cycle
    AffirmIfEqual(TbID, now - StartTime, (2 + LATE) * tperiod_Clk, "Write answered late");

    log(TbID, "TryGetWrite once the write is available");
    WriteAsync(RequesterRec, X"0000_0014", X"AAAA_5555");
    WaitForTransaction(CompleterRec);
    TryGetWrite(CompleterRec, Addr, Data, Available);
    AffirmIf(TbID, Available, "TryGetWrite: available");
    AffirmIfEqual(TbID, Addr, X"0000_0014", "TryGetWrite address");
    AffirmIfEqual(TbID, Data, X"AAAA_5555", "TryGetWrite data");
    WaitForWriteTransaction(RequesterRec);

    log(TbID, "TryGetWriteAddress and TryGetWriteData");
    WriteAsync(RequesterRec, X"0000_0018", X"0F0F_F0F0");
    WaitForWriteTransaction(CompleterRec);
    TryGetWriteData(CompleterRec, Data, Available);
    AffirmIf(TbID, Available, "TryGetWriteData: available");
    AffirmIfEqual(TbID, Data, X"0F0F_F0F0", "TryGetWriteData data");
    TryGetWriteAddress(CompleterRec, Addr, Available);
    AffirmIf(TbID, Available, "TryGetWriteAddress: available");
    AffirmIfEqual(TbID, Addr, X"0000_0018", "TryGetWriteAddress address");
    WaitForWriteTransaction(RequesterRec);

    log(TbID, "GetReadAddress then SendReadData");
    ReadAddressAsync(RequesterRec, X"0000_0020");
    GetReadAddress(CompleterRec, Addr);
    AffirmIfEqual(TbID, Addr, X"0000_0020", "GetReadAddress");
    SendReadData(CompleterRec, X"CAFE_F00D");
    ReadCheckData(RequesterRec, X"CAFE_F00D");

    log(TbID, "TryGetReadAddress and TrySendRead once the read is available");
    ReadAddressAsync(RequesterRec, X"0000_0024");
    WaitForReadTransaction(CompleterRec);
    TryGetReadAddress(CompleterRec, Addr, Available);
    AffirmIf(TbID, Available, "TryGetReadAddress: available");
    AffirmIfEqual(TbID, Addr, X"0000_0024", "TryGetReadAddress");
    SendReadData(CompleterRec, X"0000_0024");
    ReadCheckData(RequesterRec, X"0000_0024");
    ReadAddressAsync(RequesterRec, X"0000_0028");
    WaitForTransaction(CompleterRec);
    TrySendRead(CompleterRec, Addr, X"0000_0028", Available);
    AffirmIf(TbID, Available, "TrySendRead: available");
    AffirmIfEqual(TbID, Addr, X"0000_0028", "TrySendRead address");
    ReadCheckData(RequesterRec, X"0000_0028");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture CmpSplitOps;

configuration TbApb_SplitOps of TbApb is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(CmpSplitOps);
    end for;
  end for;
end TbApb_SplitOps;
