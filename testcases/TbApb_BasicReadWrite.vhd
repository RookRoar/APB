--
--  Original Author:  Kartik Desai
--
--  Description:
--      ApbRequester to the test-driven ApbCompleter: GetWrite and SendRead with
--      exact address and data. Uses the same transaction calls as OSVVM's
--      TbAxi4_BasicReadWrite, with full-width writes only (APB3 has no PSTRB)
--      and the same narrow reads at byte addresses 0 to 3.
--
--  Notes:
--      Written for ADDR_WIDTH 32 and DATA_WIDTH 32.
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
architecture CmpBasicReadWrite of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");
begin

  ControlProc : process
  begin
    SetTestName("TbApb_BasicReadWrite");
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
    variable StartTime : time;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);

    log(TbID, "Write and Read with ByteAddr = 0, 4 Bytes");
    Write(RequesterRec, X"AAAA_AAA0", X"5555_5555");
    Read(RequesterRec, X"1111_1110", Data);
    AffirmIfEqual(TbID, Data, X"2222_2222", "Requester Read Data: ");

    log(TbID, "Read 1 Byte with ByteAddr = 0, 1, 2, 3");
    Read(RequesterRec, X"1111_1110", Data(7 downto 0));
    AffirmIfEqual(TbID, Data(7 downto 0), X"AA", "Requester Read Data: ");
    Read(RequesterRec, X"1111_1111", Data(7 downto 0));
    AffirmIfEqual(TbID, Data(7 downto 0), X"BB", "Requester Read Data: ");
    Read(RequesterRec, X"1111_1112", Data(7 downto 0));
    AffirmIfEqual(TbID, Data(7 downto 0), X"CC", "Requester Read Data: ");
    Read(RequesterRec, X"1111_1113", Data(7 downto 0));
    AffirmIfEqual(TbID, Data(7 downto 0), X"DD", "Requester Read Data: ");

    log(TbID, "Read 2 Bytes with ByteAddr = 0, 1, 2");
    Read(RequesterRec, X"1111_1110", Data(15 downto 0));
    AffirmIfEqual(TbID, Data(15 downto 0), X"BBAA", "Requester Read Data: ");
    Read(RequesterRec, X"1111_1111", Data(15 downto 0));
    AffirmIfEqual(TbID, Data(15 downto 0), X"CCBB", "Requester Read Data: ");
    Read(RequesterRec, X"1111_1112", Data(15 downto 0));
    AffirmIfEqual(TbID, Data(15 downto 0), X"DDCC", "Requester Read Data: ");

    log(TbID, "Read 3 Bytes with ByteAddr = 0, 1");
    Read(RequesterRec, X"1111_1110", Data(23 downto 0));
    AffirmIfEqual(TbID, Data(23 downto 0), X"CC_BBAA", "Requester Read Data: ");
    Read(RequesterRec, X"1111_1111", Data(23 downto 0));
    AffirmIfEqual(TbID, Data(23 downto 0), X"DDCC_BB", "Requester Read Data: ");

    log(TbID, "Back-to-back writes: the waiting test answers at once, so no wait states");
    StartTime := now;
    for i in 0 to 3 loop
      Write(RequesterRec, to_slv(16#100# + 4 * i, ADDR_WIDTH), to_slv(16#1000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now - StartTime, 4 * 2 * tperiod_Clk, "Four writes in eight cycles");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

  CompleterProc : process
    variable Addr  : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable Data  : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable Count : integer;
  begin
    WaitForClock(CompleterRec, 2);
    GetWrite(CompleterRec, Addr, Data);
    AffirmIfEqual(TbID, Addr, X"AAAA_AAA0", "Completer Write Addr: ");
    AffirmIfEqual(TbID, Data, X"5555_5555", "Completer Write Data: ");
    SendRead(CompleterRec, Addr, X"2222_2222");
    AffirmIfEqual(TbID, Addr, X"1111_1110", "Completer Read Addr: ");

    SendRead(CompleterRec, Addr, X"0000_00AA");
    AffirmIfEqual(TbID, Addr, X"1111_1110", "Completer Read Addr: ");
    SendRead(CompleterRec, Addr, X"0000_BB00");
    AffirmIfEqual(TbID, Addr, X"1111_1111", "Completer Read Addr: ");
    SendRead(CompleterRec, Addr, X"00CC_0000");
    AffirmIfEqual(TbID, Addr, X"1111_1112", "Completer Read Addr: ");
    SendRead(CompleterRec, Addr, X"DD00_0000");
    AffirmIfEqual(TbID, Addr, X"1111_1113", "Completer Read Addr: ");

    SendRead(CompleterRec, Addr, X"0000_BBAA");
    AffirmIfEqual(TbID, Addr, X"1111_1110", "Completer Read Addr: ");
    SendRead(CompleterRec, Addr, X"00CC_BB00");
    AffirmIfEqual(TbID, Addr, X"1111_1111", "Completer Read Addr: ");
    SendRead(CompleterRec, Addr, X"DDCC_0000");
    AffirmIfEqual(TbID, Addr, X"1111_1112", "Completer Read Addr: ");

    SendRead(CompleterRec, Addr, X"00CC_BBAA");
    AffirmIfEqual(TbID, Addr, X"1111_1110", "Completer Read Addr: ");
    SendRead(CompleterRec, Addr, X"DDCC_BB00");
    AffirmIfEqual(TbID, Addr, X"1111_1111", "Completer Read Addr: ");

    for i in 0 to 3 loop
      GetWrite(CompleterRec, Addr, Data);
      AffirmIfEqual(TbID, Addr, to_slv(16#100# + 4 * i, ADDR_WIDTH), "Completer Write Addr: ");
      AffirmIfEqual(TbID, Data, to_slv(16#1000# + i, DATA_WIDTH), "Completer Write Data: ");
    end loop;

    GetWriteTransactionCount(CompleterRec, Count);
    AffirmIfEqual(TbID, Count, 5, "Completer write transaction count");
    GetReadTransactionCount(CompleterRec, Count);
    AffirmIfEqual(TbID, Count, 10, "Completer read transaction count");

    WaitForClock(CompleterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process CompleterProc;

end architecture CmpBasicReadWrite;

configuration TbApb_BasicReadWrite of TbApb is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(CmpBasicReadWrite);
    end for;
  end for;
end TbApb_BasicReadWrite;
