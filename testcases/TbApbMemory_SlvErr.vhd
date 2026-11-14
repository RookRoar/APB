--
--  Original Author:  Kartik Desai
--
--  Description:
--      PSLVERR (IHI0024E 3.4). Completer side: the PSLVERR option and every
--      error injection mode (EVERY_NTH, ADDRESS_RANGE, PERCENT), ERROR_READ_DATA
--      and ERROR_WRITE_UPDATES both ways. Requester side: the expected PSLVERR
--      ('0', '1', '-') and PSLVERR_ALERT_LEVEL (FAILURE, ERROR, WARNING). Every
--      mismatch is an expected alert on "Transfer Error".
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
architecture SlvErr of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant EXPECTED_ALERTS : AlertCountType                := (FAILURE => 1, ERROR => 2, WARNING => 5);
  constant OLD_DATA        : std_logic_vector(31 downto 0) := X"0000_5A5A";
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_SlvErr");
    SetLogEnable(PASSED, TRUE);
    SetLogEnable(INFO, TRUE);
    wait for 0 ns; wait for 0 ns;
    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    wait until nReset = '1';
    ClearAlerts;
    SetAlertStopCount(FAILURE, integer'right);  -- one FAILURE is expected

    WaitForBarrier(TestDone, 1 ms);
    TranscriptClose;
    EndOfTestReports(ExternalErrors => -EXPECTED_ALERTS, TimeOut => (now >= 1 ms));
    std.env.stop;
    wait;
  end process ControlProc;

  -- One process drives both transaction interfaces
  TestProc : process
    variable ReqID   : AlertLogIDType;
    variable CmpID   : AlertLogIDType;
    variable Data    : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable Updated : integer;

    -- Check through the memory backdoor whether a write updated the memory
    procedure CheckMemory (Addr : integer; Expected : std_logic_vector) is
    begin
      ReadCheck(CompleterRec, to_slv(Addr, ADDR_WIDTH), Expected);
    end procedure CheckMemory;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    GetAlertLogID(RequesterRec, ReqID);
    GetAlertLogID(CompleterRec, CmpID);
    for i in 0 to 16#9C#/4 loop
      Write(CompleterRec, to_slv(4 * i, ADDR_WIDTH), OLD_DATA);
    end loop;

    ------------------------------------------------------------
    log(TbID, "Completer PSLVERR = '1', Requester expects '1': no alerts");
    SetApbOptions(CompleterRec, PSLVERR, '1');
    SetApbOptions(RequesterRec, PSLVERR, '1');
    Write(RequesterRec, X"0000_0000", X"0000_0001");
    CheckMemory(16#00#, OLD_DATA);  -- ERROR_WRITE_UPDATES = FALSE
    Read(RequesterRec, X"0000_0000", Data);
    AffirmIfEqual(TbID, Data, OLD_DATA, "ERROR_READ_DATA = ERROR_DATA_MEMORY");
    -- Read data with PSLVERR = 1 is not checked (IHI0024E 3.4)
    ReadCheck(RequesterRec, X"0000_0000", X"FFFF_FFFF");

    SetApbOptions(CompleterRec, ERROR_READ_DATA, ERROR_DATA_ZERO);
    Read(RequesterRec, X"0000_0000", Data);
    AffirmIfEqual(TbID, Data, X"0000_0000", "ERROR_READ_DATA = ERROR_DATA_ZERO");
    SetApbOptions(CompleterRec, ERROR_READ_DATA, ERROR_DATA_MEMORY);

    SetApbOptions(CompleterRec, ERROR_WRITE_UPDATES, TRUE);
    Write(RequesterRec, X"0000_0004", X"0000_0004");
    CheckMemory(16#04#, X"0000_0004");
    SetApbOptions(CompleterRec, ERROR_WRITE_UPDATES, FALSE);

    log(TbID, "Requester expects '-': no alerts");
    SetApbOptions(RequesterRec, PSLVERR, '-');
    Write(RequesterRec, X"0000_0008", X"0000_0008");

    log(TbID, "Requester expects '0': one alert per PSLVERR_ALERT_LEVEL (expected)");
    SetApbOptions(RequesterRec, PSLVERR, '0');
    Write(RequesterRec, X"0000_0008", X"0000_0008");  -- ERROR (default level)
    SetApbOptions(RequesterRec, PSLVERR_ALERT_LEVEL, WARNING);
    Read(RequesterRec, X"0000_0008", Data);  -- WARNING
    SetApbOptions(RequesterRec, PSLVERR_ALERT_LEVEL, FAILURE);
    Write(RequesterRec, X"0000_0008", X"0000_0008");  -- FAILURE
    SetApbOptions(RequesterRec, PSLVERR_ALERT_LEVEL, ERROR);

    ------------------------------------------------------------
    log(TbID, "Completer PSLVERR = '0', Requester expects '1': one ERROR (expected)");
    SetApbOptions(CompleterRec, PSLVERR, '0');
    SetApbOptions(RequesterRec, PSLVERR, '1');
    Write(RequesterRec, X"0000_000C", X"0000_000C");
    CheckMemory(16#0C#, X"0000_000C");
    SetApbOptions(RequesterRec, PSLVERR, '0');

    ------------------------------------------------------------
    log(TbID, "INJECT_EVERY_NTH, N = 3: the 3rd and 6th write fail (two WARNINGs expected)");
    SetApbOptions(RequesterRec, PSLVERR_ALERT_LEVEL, WARNING);
    SetApbOptions(CompleterRec, PSLVERR_INJECT_N, 3);
    SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_EVERY_NTH);
    for i in 0 to 5 loop
      Write(RequesterRec, to_slv(16#10# + 4 * i, ADDR_WIDTH), to_slv(16#10# + 4 * i, DATA_WIDTH));
    end loop;
    for i in 0 to 5 loop
      if i = 2 or i = 5 then
        CheckMemory(16#10# + 4 * i, OLD_DATA);
      else
        CheckMemory(16#10# + 4 * i, to_slv(16#10# + 4 * i, DATA_WIDTH));
      end if;
    end loop;

    log(TbID, "INJECT_ADDRESS_RANGE 0x30 to 0x37: two of five writes fail (two WARNINGs expected)");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_ADDR_LOW, X"0000_0030");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_ADDR_HIGH, X"0000_0037");
    SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_ADDRESS_RANGE);
    for i in 0 to 4 loop
      Write(RequesterRec, to_slv(16#28# + 4 * i, ADDR_WIDTH), to_slv(16#28# + 4 * i, DATA_WIDTH));
    end loop;
    CheckMemory(16#28#, X"0000_0028");
    CheckMemory(16#2C#, X"0000_002C");
    CheckMemory(16#30#, OLD_DATA);
    CheckMemory(16#34#, OLD_DATA);
    CheckMemory(16#38#, X"0000_0038");
    SetApbOptions(RequesterRec, PSLVERR_ALERT_LEVEL, ERROR);

    log(TbID, "INJECT_PERCENT 100, 0 and 50, with the Requester expecting '-'");
    SetApbOptions(RequesterRec, PSLVERR, '-');
    SetApbOptions(CompleterRec, PSLVERR_INJECT_PERCENT, 100);
    SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_PERCENT);
    for i in 0 to 3 loop
      Write(RequesterRec, to_slv(16#40# + 4 * i, ADDR_WIDTH), to_slv(16#40# + 4 * i, DATA_WIDTH));
      CheckMemory(16#40# + 4 * i, OLD_DATA);
    end loop;
    SetApbOptions(CompleterRec, PSLVERR_INJECT_PERCENT, 0);
    for i in 0 to 3 loop
      Write(RequesterRec, to_slv(16#40# + 4 * i, ADDR_WIDTH), to_slv(16#40# + 4 * i, DATA_WIDTH));
      CheckMemory(16#40# + 4 * i, to_slv(16#40# + 4 * i, DATA_WIDTH));
    end loop;
    SetApbOptions(CompleterRec, PSLVERR_INJECT_PERCENT, 50);
    Updated := 0;
    for i in 0 to 15 loop
      Write(RequesterRec, to_slv(16#50# + 4 * i, ADDR_WIDTH), to_slv(16#50# + 4 * i, DATA_WIDTH));
      Read(CompleterRec, to_slv(16#50# + 4 * i, ADDR_WIDTH), Data);
      if Data /= OLD_DATA then
        Updated := Updated + 1;
      end if;
    end loop;
    AffirmIf(TbID, Updated > 0 and Updated < 16, "INJECT_PERCENT 50: " & to_string(16 - Updated) & " of 16 writes failed");

    SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_NONE);
    SetApbOptions(RequesterRec, PSLVERR, '0');
    Write(RequesterRec, X"0000_0000", X"0000_0001");
    ReadCheck(RequesterRec, X"0000_0000", X"0000_0001");

    AffirmIf(TbID, GetAlertCount(FindAlertLogID("Transfer Error", ReqID)) = EXPECTED_ALERTS,
      "Requester Transfer Error: 1 FAILURE, 2 ERRORs, 5 WARNINGs");
    AffirmIf(TbID, GetAlertCount(ReqID) = EXPECTED_ALERTS, "Requester: no other alerts");
    AffirmIf(TbID, GetAlertCount(CmpID) = AlertCountType'(0, 0, 0), "Completer: no alerts");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture SlvErr;

configuration TbApbMemory_SlvErr of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(SlvErr);
    end for;
  end for;
end TbApbMemory_SlvErr;
