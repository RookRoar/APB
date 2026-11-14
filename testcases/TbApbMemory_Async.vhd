--
--  Original Author:  Kartik Desai
--
--  Description:
--      Non-blocking and split operations: WriteAsync, WriteAddressAsync and
--      WriteDataAsync in both orders, ReadAddressAsync with ReadData,
--      ReadCheckData, TryReadData and TryReadCheckData, and the
--      WaitForTransaction directives.
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
architecture Async of TestCtrl is
  signal   TestDone : BarrierType;
  constant TbID     : AlertLogIDType := NewID("TB");

  constant NUM_WORDS : integer := 8;
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_Async");
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
    variable Available : boolean;
    variable Count     : integer;
    variable StartTime : time;
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);

    log(TbID, "WriteAsync returns at once; the writes run back-to-back");
    StartTime := now;
    for i in 0 to NUM_WORDS - 1 loop
      WriteAsync(RequesterRec, to_slv(4 * i, ADDR_WIDTH), to_slv(16#C000# + i, DATA_WIDTH));
    end loop;
    AffirmIfEqual(TbID, now, StartTime, "WriteAsync does not block");
    WaitForWriteTransaction(RequesterRec);
    AffirmIfEqual(TbID, now - StartTime, NUM_WORDS * 2 * tperiod_Clk, "Back-to-back async writes");
    GetWriteTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbID, Count, NUM_WORDS, "Write transaction count");

    log(TbID, "Split write: address first, then data");
    WriteAddressAsync(RequesterRec, to_slv(16#40#, ADDR_WIDTH));
    WaitForClock(RequesterRec, 3);
    GetWriteTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbID, Count, NUM_WORDS, "No transfer for an address without data");
    WriteDataAsync(RequesterRec, to_slv(16#40#, ADDR_WIDTH), to_slv(16#4040#, DATA_WIDTH));

    log(TbID, "Split write: data first, then address");
    WriteDataAsync(RequesterRec, to_slv(16#4444#, DATA_WIDTH));
    WriteAddressAsync(RequesterRec, to_slv(16#44#, ADDR_WIDTH));
    WaitForWriteTransaction(RequesterRec);
    GetWriteTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbID, Count, NUM_WORDS + 2, "Write transaction count after split writes");
    ReadCheck(RequesterRec, to_slv(16#40#, ADDR_WIDTH), to_slv(16#4040#, DATA_WIDTH));
    ReadCheck(RequesterRec, to_slv(16#44#, ADDR_WIDTH), to_slv(16#4444#, DATA_WIDTH));

    log(TbID, "ReadAddressAsync, then ReadData, ReadCheckData, TryReadData, TryReadCheckData");
    for i in 0 to 3 loop
      ReadAddressAsync(RequesterRec, to_slv(4 * i, ADDR_WIDTH));
    end loop;
    TryReadData(RequesterRec, Data, Available);
    AffirmIf(TbID, not Available, "TryReadData before any read completed: not available");
    ReadData(RequesterRec, Data);
    AffirmIfEqual(TbID, Data, to_slv(16#C000#, DATA_WIDTH), "ReadData");
    ReadCheckData(RequesterRec, to_slv(16#C001#, DATA_WIDTH));
    WaitForReadTransaction(RequesterRec);
    TryReadData(RequesterRec, Data, Available);
    AffirmIf(TbID, Available, "TryReadData after the reads completed: available");
    AffirmIfEqual(TbID, Data, to_slv(16#C002#, DATA_WIDTH), "TryReadData");
    TryReadCheckData(RequesterRec, to_slv(16#C003#, DATA_WIDTH), Available);
    AffirmIf(TbID, Available, "TryReadCheckData: available");
    TryReadData(RequesterRec, Data, Available);
    AffirmIf(TbID, not Available, "TryReadData with no read outstanding: not available");

    log(TbID, "WaitForTransaction waits for writes and reads");
    WriteAsync(RequesterRec, to_slv(16#48#, ADDR_WIDTH), to_slv(16#4848#, DATA_WIDTH));
    ReadAddressAsync(RequesterRec, to_slv(16#48#, ADDR_WIDTH));
    StartTime := now;
    WaitForTransaction(RequesterRec);
    AffirmIfEqual(TbID, now - StartTime, 2 * 2 * tperiod_Clk, "WaitForTransaction");
    ReadCheckData(RequesterRec, to_slv(16#4848#, DATA_WIDTH));

    GetReadTransactionCount(RequesterRec, Count);
    AffirmIfEqual(TbID, Count, 2 + 4 + 1, "Read transaction count");

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

end architecture Async;

configuration TbApbMemory_Async of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(Async);
    end for;
  end for;
end TbApbMemory_Async;
