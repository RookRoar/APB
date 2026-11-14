--
--  Original Author:  Kartik Desai
--
--  Description:
--      Randomised Requester <-> CompleterMemory traffic driven by intelligent
--      coverage, until every bin of both ApbMonitor coverage models has been
--      hit MONITOR_GOAL times.
--
--      Each transfer picks a direction, a wait-state count, a PSLVERR value
--      and a spacing (IDLE-separated or back-to-back) from a stimulus model
--      with the Monitor's bins, plus a random address and data. Writes are
--      full words (APB3 has no PSTRB). Reads are full words or 1 to 3 byte
--      narrow reads, checked against a shadow memory. A write with PSLVERR
--      updates the memory or not (ERROR_WRITE_UPDATES), and a read with
--      PSLVERR returns memory data or zeros (ERROR_READ_DATA), both random.
--
--  Notes:
--      Parameters are set in zero time, so they can change between two
--      back-to-back transfers. The CompleterMemory PSLVERR option is a
--      transaction that waits for a clock edge, so PSLVERR is selected with
--      error injection instead (INJECT_EVERY_NTH with N = 1, or INJECT_NONE).
--      ERROR_WRITE_UPDATES is read when a write completes, so it changes only
--      after the IDLE cycles of an IDLE-separated transfer.
--      The seeds come from InitSeed and are logged at the start.
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
architecture RandomCoverage of TestCtrl is
  signal   TestDone  : BarrierType;
  constant TbID      : AlertLogIDType := NewID("TB");
  constant StimCovID : CoverageIDType := NewID("Stimulus Coverage");

  constant MONITOR_NAME  : string  := "ApbMonitor";
  constant MONITOR_GOAL  : integer := 4;     -- hits needed in every Monitor bin
  constant STIM_AT_LEAST : integer := 2;     -- per stimulus bin; 2 spacings x 2 = MONITOR_GOAL
  constant MAX_TRANSFERS : integer := 2000;  -- the goal must be reached before this
  constant MAX_WAIT      : integer := 20;    -- upper end of the Monitor's ">= 16" bin
  constant NUM_WORDS     : integer := 8;     -- small, so reads often hit written words
  constant DATA_BYTES    : integer := DATA_WIDTH / 8;

  constant DIR_READ     : integer := 0;
  constant DIR_WRITE    : integer := 1;
  constant SPACING_IDLE : integer := 0;
  constant SPACING_B2B  : integer := 1;
begin

  ControlProc : process
  begin
    SetTestName("TbApbMemory_RandomCoverage");
    wait for 0 ns; wait for 0 ns;
    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    wait until nReset = '1';
    ClearAlerts;

    WaitForBarrier(TestDone, 5 ms);
    TranscriptClose;
    EndOfTestReports(TimeOut => (now >= 5 ms));
    std.env.stop;
    wait;
  end process ControlProc;

  -- One process drives both transaction interfaces
  TestProc : process
    type     WordArrayType is array (0 to NUM_WORDS - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable Shadow        : WordArrayType;
    variable RV            : RandomPType;
    -- The Monitor creates its coverage models at time 0: looked up after reset
    variable MonCovID      : CoverageIDType;
    variable MonSpacingID  : CoverageIDType;
    variable Point         : integer_vector(1 to 4);
    variable Dir           : integer;
    variable Spacing       : integer;
    variable SlvErr        : integer;
    variable SlvErrVal     : std_logic;
    variable ErrWriteUpd   : boolean;
    variable ErrReadZero   : boolean;
    variable ErrReadData   : ApbErrorReadDataType;
    variable TransferCount : integer;
    variable WordIndex     : integer;
    variable Size          : integer;
    variable Data          : std_logic_vector(DATA_WIDTH - 1 downto 0);

    impure function MonitorGoalReached return boolean is
    begin
      return GetMinCount(MonCovID) >= MONITOR_GOAL and GetMinCount(MonSpacingID) >= MONITOR_GOAL;
    end function MonitorGoalReached;

    -- Read Size bytes at byte Offset of word WordIndex and check them
    procedure DoRead (WordIndex, Offset, Size : integer) is
      variable Addr     : std_logic_vector(ADDR_WIDTH - 1 downto 0);
      variable Expected : std_logic_vector(8 * Size - 1 downto 0);
      variable RData    : std_logic_vector(8 * Size - 1 downto 0);
    begin
      Addr := to_slv(DATA_BYTES * WordIndex + Offset, ADDR_WIDTH);
      if SlvErr = 1 and ErrReadZero then
        Expected := (others => '0');
      else
        Expected := Shadow(WordIndex)(8 * (Offset + Size) - 1 downto 8 * Offset);
      end if;
      if SlvErr = 0 then
        ReadCheck(RequesterRec, Addr, Expected);
      else
        -- The Requester does not check read data with PSLVERR (IHI0024E 3.4)
        Read(RequesterRec, Addr, RData);
        AffirmIfEqual(TbID, RData, Expected, "Read with PSLVERR at " & to_hxstring(Addr));
      end if;
    end procedure DoRead;

  begin
    wait until nReset = '1';
    WaitForClock(RequesterRec, 2);

    RV.InitSeed("TbApbMemory_RandomCoverage");
    AddCross(StimCovID, STIM_AT_LEAST,
      GenBin(DIR_READ, DIR_WRITE),
      GenBin(0) & GenBin(1) & GenBin(2, 3, 1) & GenBin(4, 15, 1) & GenBin(16, MAX_WAIT, 1),
      GenBin(0, 1),
      GenBin(SPACING_IDLE, SPACING_B2B));
    SetItemBinNames(StimCovID, "Write", "WaitStates", "PSLVERR", "BackToBack");
    MonCovID     := NewID(MONITOR_NAME & " Coverage", Search => NAME);
    MonSpacingID := NewID(MONITOR_NAME & " Spacing Coverage", Search => NAME);
    Log(TbID, "Seeds: RandomPType " & to_string(RV.GetSeed) &
              ", Stimulus Coverage " & to_string(GetSeed(StimCovID)));

    -- Preload the memory through the backdoor so no read returns 'U'
    for i in Shadow'range loop
      Shadow(i) := RV.RandSlv(DATA_WIDTH);
      Write(CompleterRec, to_slv(DATA_BYTES * i, ADDR_WIDTH), Shadow(i));
    end loop;
    -- With N = 1, INJECT_EVERY_NTH gives PSLVERR on every transfer
    SetApbOptions(CompleterRec, PSLVERR_INJECT_N, 1);
    ErrWriteUpd := FALSE;

    TransferCount := 0;
    while not MonitorGoalReached and TransferCount < MAX_TRANSFERS loop
      Point  := GetRandPoint(StimCovID);
      Dir    := Point(1);
      SlvErr := Point(3);
      -- The first transfer follows an idle bus
      Spacing := SPACING_IDLE when TransferCount = 0 else Point(4);

      if Spacing = SPACING_IDLE then
        WaitForClock(RequesterRec, RV.RandInt(1, 3));
        ErrWriteUpd := RV.RandBool;
        SetApbOptions(CompleterRec, ERROR_WRITE_UPDATES, ErrWriteUpd);
      end if;

      -- Settings for this transfer, all in zero time
      ErrReadZero := RV.RandBool;
      ErrReadData := ERROR_DATA_ZERO when ErrReadZero else ERROR_DATA_MEMORY;
      SlvErrVal   := '1' when SlvErr = 1 else '0';
      SetApbOptions(CompleterRec, WAIT_STATES, Point(2));
      SetApbOptions(CompleterRec, ERROR_READ_DATA, ErrReadData);
      if SlvErr = 1 then
        SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_EVERY_NTH);
      else
        SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_NONE);
      end if;
      SetApbOptions(RequesterRec, PSLVERR, SlvErrVal);

      WordIndex := RV.RandInt(0, NUM_WORDS - 1);
      if Dir = DIR_WRITE then
        Data := RV.RandSlv(DATA_WIDTH);
        Write(RequesterRec, to_slv(DATA_BYTES * WordIndex, ADDR_WIDTH), Data);
        -- A write with an error may or may not update the memory (IHI0024E 3.4)
        if SlvErr = 0 or ErrWriteUpd then
          Shadow(WordIndex) := Data;
        end if;
      elsif RV.RandBool then
        DoRead(WordIndex, 0, DATA_BYTES);
      else
        Size := RV.RandInt(1, DATA_BYTES - 1);
        DoRead(WordIndex, RV.RandInt(0, DATA_BYTES - Size), Size);
      end if;

      ICover(StimCovID, (Dir, Point(2), SlvErr, Spacing));
      TransferCount := TransferCount + 1;
    end loop;

    -- Every word against the shadow memory, through the backdoor
    for i in Shadow'range loop
      ReadCheck(CompleterRec, to_slv(DATA_BYTES * i, ADDR_WIDTH), Shadow(i));
    end loop;

    -- Let the Monitor see the last completion
    WaitForClock(RequesterRec, 2);
    Log(TbID, to_string(TransferCount) & " transfers");
    AffirmIf(TbID, MonitorGoalReached,
      "Every Monitor coverage bin hit at least " & to_string(MONITOR_GOAL) & " times");
    WriteBin(MonCovID);
    WriteBin(MonSpacingID);

    WaitForBarrier(TestDone);
    wait;
  end process TestProc;

end architecture RandomCoverage;

configuration TbApbMemory_RandomCoverage of TbApbMemory is
  for TestHarness
    for TestCtrl_1 : TestCtrl
      use entity work.TestCtrl(RandomCoverage);
    end for;
  end for;
end TbApbMemory_RandomCoverage;
