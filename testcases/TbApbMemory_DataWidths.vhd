--
--  Original Author:  Kartik Desai
--
--  Description:
--      ApbRequester to ApbCompleterMemory at every APB data width (8, 16, 32;
--      IHI0024E 2.1.2), set by the harness generic DATA_WIDTH. Full-width writes
--      and reads, and narrow reads that extract single bytes from the bus.
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
architecture DataWidths of TestCtrl is
  signal   TestDone      : BarrierType;
  constant TbRequesterID : AlertLogIDType := NewID("TB Requester Proc");

  constant BYTES     : integer := DATA_WIDTH / 8;
  constant NUM_WORDS : integer := 8;

  -- Word i: byte b holds 16#10# * i + b
  function WordValue (i : integer) return std_logic_vector is
    variable Result : std_logic_vector(DATA_WIDTH - 1 downto 0);
  begin
    for b in 0 to BYTES - 1 loop
      Result(8 * b + 7 downto 8 * b) := to_slv((16#10# * i + b) mod 256, 8);
    end loop;
    return Result;
  end function WordValue;
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_DataWidths");
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
    variable ByteData : std_logic_vector(7 downto 0);
  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);
    log(TbRequesterID, "Data width " & to_string(DATA_WIDTH));

    for i in 0 to NUM_WORDS - 1 loop
      Write(RequesterRec, to_slv(BYTES * i, ADDR_WIDTH), WordValue(i));
    end loop;

    for i in 0 to NUM_WORDS - 1 loop
      ReadCheck(RequesterRec, to_slv(BYTES * i, ADDR_WIDTH), WordValue(i));
    end loop;

    -- Narrow reads: the full bus is read, the requested byte is extracted
    for i in 0 to 1 loop
      for b in 0 to BYTES - 1 loop
        Read(RequesterRec, to_slv(BYTES * i + b, ADDR_WIDTH), ByteData);
        AffirmIfEqual(TbRequesterID, ByteData, to_slv((16#10# * i + b) mod 256, 8),
          "Byte " & to_string(b) & " of word " & to_string(i));
      end loop;
    end loop;

    WaitForClock(RequesterRec, 2);
    WaitForBarrier(TestDone);
    wait;
  end process RequesterProc;

end architecture DataWidths;

configuration TbApbMemory_DataWidths of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(DataWidths);
    end for;
  end for;
end TbApbMemory_DataWidths;
