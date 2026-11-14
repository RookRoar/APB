--
--  Original Author:  Kartik Desai
--
--  Description:
--      APB Requester verification component, driven through the OSVVM
--      AddressBusRecType transaction interface
--
--  Notes:
--      Structure follows OSVVM Axi4LiteManager: a TransactionDispatcher that queues
--      transfers, and a TransferHandler that runs them on the bus with the
--      ApbProtocolPkg phase procedures. Bursts are split into single transfers at
--      incrementing word addresses, as in OSVVM WishboneManager.
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
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;
use ieee.math_real.all;

library osvvm;
context osvvm.OsvvmContext;
use osvvm.ScoreboardPkg_slv.all;

library osvvm_common;
context osvvm_common.OsvvmCommonContext;

use work.ApbSettingsPkg.all;
use work.ApbInterfacePkg.all;
use work.ApbModelPkg.all;
use work.ApbOptionsPkg.all;
use work.ApbProtocolPkg.all;

entity ApbRequester is
  generic (
    MODEL_ID_NAME   : string          := "";
    APB_REVISION    : ApbRevisionType := APB3;

    DEFAULT_DELAY   : time            := APB_DEFAULT_DELAY;

    tpd_Clk_PSel    : time            := DEFAULT_DELAY;
    tpd_Clk_PEnable : time            := DEFAULT_DELAY;
    tpd_Clk_PAddr   : time            := DEFAULT_DELAY;
    tpd_Clk_PWrite  : time            := DEFAULT_DELAY;
    tpd_Clk_PWData  : time            := DEFAULT_DELAY;
    tpd_Clk_PProt   : time            := DEFAULT_DELAY;  -- APB4
    tpd_Clk_PStrb   : time            := DEFAULT_DELAY   -- APB4
  );
  port (
    -- Globals
    Clk      : in    std_logic;
    nReset   : in    std_logic;

    -- APB Requester interface
    ApbBus   : inout ApbRecType;

    -- Testbench transaction interface
    TransRec : inout AddressBusRecType
  );

  -- Derive interface properties from the bus
  constant ADDR_WIDTH : integer := ApbBus.Requester.PAddr'length;
  constant DATA_WIDTH : integer := ApbBus.Requester.PWData'length;

  -- Use MODEL_ID_NAME if set, otherwise the instance label
  constant MODEL_INSTANCE_NAME : string :=
    IfElse(MODEL_ID_NAME /= "", MODEL_ID_NAME, PathTail(to_lower(ApbRequester'PATH_NAME)));

end entity ApbRequester;

architecture behavioral of ApbRequester is

  constant DATA_BYTE_WIDTH : integer                                        := DATA_WIDTH / 8;
  constant BYTE_ADDR_WIDTH : integer                                        := integer(ceil(log2(real(DATA_BYTE_WIDTH))));
  constant ALL_LANES       : std_logic_vector(DATA_BYTE_WIDTH - 1 downto 0) := (others => '1');

  -- AlertLog, parameter and FIFO IDs are constants, created during elaboration:
  -- every process can use them from time 0, and they are created in
  -- declaration order
  constant ModelID         : AlertLogIDType        := NewID(MODEL_INSTANCE_NAME);
  constant ProtocolID      : AlertLogIDType        := NewID("Protocol Error", ModelID);
  constant DataCheckID     : AlertLogIDType        := NewID("Data Check", ModelID);
  constant BusFailedID     : AlertLogIDType        := NewID("No response", ModelID);
  constant TransferErrorID : AlertLogIDType        := NewID("Transfer Error", ModelID);
  constant Params          : ModelParametersIDType := NewApbParams("Parameters", ModelID);

  -- Internal FIFOs
  --   TransferFifo:  PWRITE & expected PSLVERR & PADDR & PWDATA, one entry per APB transfer
  --   WriteAddrFifo: write addresses waiting for their data (WriteAddressAsync)
  --   WriteDataFifo: valid & write data waiting for an address (WriteDataAsync)
  --   ReadAddrFifo:  PADDR of each single read, for byte alignment of the read data
  --   ReadDataFifo:  PSLVERR & PRDATA of each completed read
  constant TransferFifo  : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("TransferFifo",  ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);
  constant WriteAddrFifo : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("WriteAddrFifo", ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);
  constant WriteDataFifo : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("WriteDataFifo", ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);
  constant ReadAddrFifo  : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("ReadAddrFifo",  ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);
  constant ReadDataFifo  : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("ReadDataFifo",  ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);

  -- Burst FIFOs, published to the test through TransRec
  constant WriteBurstFifo : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("WriteBurstFifo", ModelID, Search => PRIVATE_NAME);
  constant ReadBurstFifo  : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("ReadBurstFifo",  ModelID, Search => PRIVATE_NAME);

  -- Delay coverage: one delay point, the IDLE cycles before a transfer.
  -- A signal, because the test can replace it (SetDelayCoverageID).
  signal ArrDelayCovID     : DelayCoverageIDArrayType(1 to 1) :=
    (1 => NewID("TransferDelayCov", ModelID, ReportMode => DISABLED));
  alias  TransferDelayCov  is ArrDelayCovID(1);
  signal UseCoverageDelays : boolean                          := FALSE;

  constant DEFAULT_BURST_MODE : AddressBusFifoBurstModeType := ADDRESS_BUS_BURST_WORD_MODE;
  signal   BurstFifoMode      : AddressBusFifoBurstModeType := DEFAULT_BURST_MODE;

  signal WriteRequestCount    : integer := 0;
  signal WriteDoneCount       : integer := 0;
  signal ReadRequestCount     : integer := 0;
  signal ReadDoneCount        : integer := 0;
  signal TransferRequestCount : integer := 0;

  signal TransactionDone      : boolean;
  signal WriteTransactionDone : boolean;
  signal ReadTransactionDone  : boolean;

begin

  ------------------------------------------------------------
  -- Turn off drivers not used by this model
  ------------------------------------------------------------
  InitApbRec(ApbBus);

  ------------------------------------------------------------
  -- Static interface checks
  ------------------------------------------------------------
  Initialize : process
  begin
    -- Static interface checks (APB3-S01 to S03)
    CheckApbInterface(ModelID, APB_REVISION, ApbBus);
    AlertIf(ModelID, APB_REVISION /= APB3,
            "APB_REVISION " & to_string(APB_REVISION) &
            " is not supported yet. Only APB3 is supported.", FAILURE);
    wait;
  end process Initialize;


  ------------------------------------------------------------
  --  Transaction Dispatcher
  --    Queues transfers for the TransferHandler and returns read data
  ------------------------------------------------------------
  TransactionDispatcher : process
    variable Operation        : AddressBusOperationType;
    variable ApbOption        : ApbOptionsType;
    variable Addr             : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable WData            : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable RData            : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable ExpectedData     : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable SlvErr           : std_logic;
    variable WriteValid       : std_logic;
    variable ExpectedSlvErr   : std_logic := '0';  -- PSLVERR interface option
    variable ByteAddr         : integer;
    variable TransfersInBurst : integer;
    variable BytesToSend      : integer;
    variable BytesToReceive   : integer;
    variable NumIssued        : integer;
    variable OperationCount   : integer   := 0;
  begin
    TransRec.Params         <= Params;
    TransRec.WriteBurstFifo <= WriteBurstFifo;
    TransRec.ReadBurstFifo  <= ReadBurstFifo;

    DispatchLoop : loop
      WaitForTransaction(
        Clk => Clk,
        Rdy => TransRec.Rdy,
        Ack => TransRec.Ack
      );
      Operation      := TransRec.Operation;
      OperationCount := OperationCount + 1;

      case Operation is
        when WRITE_OP | WRITE_ADDRESS | WRITE_DATA | ASYNC_WRITE | ASYNC_WRITE_ADDRESS | ASYNC_WRITE_DATA =>
          Addr := SafeResize(ModelID, TransRec.Address, Addr'length);

          if IsWriteAddress(Operation) then
            Push(WriteAddrFifo, Addr);
          end if;

          if IsWriteData(Operation) then
            -- The address of a write data operation only gives the byte lanes
            ByteAddr := CalculateByteAddress(Addr, BYTE_ADDR_WIDTH);
            CheckDataIsBytes(ModelID, TransRec.DataWidth, "Requester Write: ", OperationCount);
            CheckDataWidth(ModelID, TransRec.DataWidth, ByteAddr, DATA_WIDTH, "Requester Write: ", OperationCount);
            WData    := AlignBytesToDataBus(SafeResize(ModelID, TransRec.DataToModel, WData'length), TransRec.DataWidth, ByteAddr);

            -- APB3 has no PSTRB (IHI0024E Table B-1): every write updates all byte lanes,
            -- so a write that does not cover every lane cannot be issued.
            if CalculateWriteStrobe(WData) /= ALL_LANES then
              Alert(ProtocolID,
                    "APB3 cannot write fewer than all byte lanes (no PSTRB).  PADDR: " & to_hxstring(Addr) &
                    "  DataWidth: " & to_string(TransRec.DataWidth) & "  Write not issued.", ERROR);
              WriteValid := '0';
            else
              WriteValid := '1';
            end if;
            Push(WriteDataFifo, WriteValid & WData);
          end if;

          -- Pair a write address with its write data into one APB transfer
          if not IsEmpty(WriteAddrFifo) and not IsEmpty(WriteDataFifo) then
            Addr                := Pop(WriteAddrFifo);
            (WriteValid, WData) := Pop(WriteDataFifo);
            if WriteValid = '1' then
              Push(TransferFifo, '1' & ExpectedSlvErr & Addr & WData);
              Increment(WriteRequestCount);
              Increment(TransferRequestCount);
            end if;
          end if;

          -- Allow the request counts to update
          wait for 0 ns;
          if (IsBlockOnWriteAddress(Operation) or IsBlockOnWriteData(Operation)) and
              WriteDoneCount /= WriteRequestCount then
            wait until WriteDoneCount = WriteRequestCount;
          end if;

        when WRITE_BURST | ASYNC_WRITE_BURST =>
          Addr     := SafeResize(ModelID, TransRec.Address, Addr'length);
          ByteAddr := CalculateByteAddress(Addr, BYTE_ADDR_WIDTH);
          if BurstFifoMode = ADDRESS_BUS_BURST_BYTE_MODE then
            BytesToSend      := TransRec.DataWidth;
            TransfersInBurst := 1 + CalculateBurstLen(BytesToSend, ByteAddr, DATA_BYTE_WIDTH);
          else
            BytesToSend      := TransRec.DataWidth * DATA_BYTE_WIDTH;
            TransfersInBurst := TransRec.DataWidth;
          end if;
          Log(ModelID,
              "Write Burst.  PADDR: " & to_hxstring(Addr) & "  Transfers in Burst: " &
              to_string(TransfersInBurst), INFO, TransRec.StatusMsgOn);

          NumIssued := 0;
          if ByteAddr /= 0 or BytesToSend mod DATA_BYTE_WIDTH /= 0 then
            -- APB3 has no PSTRB (IHI0024E Table B-1): a burst must start word aligned
            -- and contain whole words. Remove its data so the next burst is not affected.
            Alert(ProtocolID,
                  "APB3 write burst must be word aligned and whole words (no PSTRB).  PADDR: " &
                  to_hxstring(Addr) & "  Bytes: " & to_string(BytesToSend) & "  Burst not issued.", ERROR);
            for i in 1 to TransRec.DataWidth loop
              WData := (others => '0');
              if BurstFifoMode = ADDRESS_BUS_BURST_BYTE_MODE then
                WData(7 downto 0) := Pop(TransRec.WriteBurstFifo);
              else
                WData := Pop(TransRec.WriteBurstFifo);
              end if;
            end loop;
          else
            for BurstLoop in 1 to TransfersInBurst loop
              PopWriteBurstData(TransRec.WriteBurstFifo, BurstFifoMode, WData, BytesToSend, 0);
              if CalculateWriteStrobe(WData) /= ALL_LANES then
                Alert(ProtocolID,
                      "APB3 cannot write fewer than all byte lanes (no PSTRB).  PADDR: " &
                      to_hxstring(Addr) & "  Burst word not issued.", ERROR);
              else
                Push(TransferFifo, '1' & ExpectedSlvErr & Addr & WData);
                NumIssued := NumIssued + 1;
              end if;
              -- PADDR is a byte address (IHI0024E 2.1.1)
              Addr := Addr + DATA_BYTE_WIDTH;
            end loop;
          end if;
          WriteRequestCount    <= WriteRequestCount + NumIssued;
          TransferRequestCount <= TransferRequestCount + NumIssued;

          -- Allow the request counts to update
          wait for 0 ns;
          if IsBlockOnWriteData(Operation) and WriteDoneCount /= WriteRequestCount then
            wait until WriteDoneCount = WriteRequestCount;
          end if;

        when READ_OP | READ_CHECK | READ_ADDRESS | READ_DATA | READ_DATA_CHECK |
             ASYNC_READ_ADDRESS | ASYNC_READ_DATA | ASYNC_READ_DATA_CHECK =>
          if IsReadAddress(Operation) then
            -- The full bus is read at PADDR as given; unaligned PADDR is permitted (2.1.1)
            Addr := SafeResize(ModelID, TransRec.Address, Addr'length);
            Push(TransferFifo, '0' & ExpectedSlvErr & Addr & (WData'range => '0'));
            Push(ReadAddrFifo, Addr);
            Increment(ReadRequestCount);
            Increment(TransferRequestCount);
          end if;
          wait for 0 ns;

          if IsTryReadData(Operation) and IsEmpty(ReadDataFifo) then
            -- Read data not available yet
            TransRec.BoolFromModel <= FALSE;
            TransRec.DataFromModel <= (TransRec.DataFromModel'range => '0');

          elsif IsReadData(Operation) and IsEmpty(ReadAddrFifo) then
            Alert(ModelID, "Read data requested with no read address outstanding", FAILURE);
            TransRec.BoolFromModel <= FALSE;
            TransRec.DataFromModel <= (TransRec.DataFromModel'range => '0');

          elsif IsReadData(Operation) then
            Addr     := Pop(ReadAddrFifo);
            ByteAddr := CalculateByteAddress(Addr, BYTE_ADDR_WIDTH);
            CheckDataIsBytes(ModelID, TransRec.DataWidth, "Requester Read: ", OperationCount);
            CheckDataWidth(ModelID, TransRec.DataWidth, ByteAddr, DATA_WIDTH, "Requester Read: ", OperationCount);

            if IsEmpty(ReadDataFifo) then
              WaitForToggle(ReadDoneCount);
            end if;
            (SlvErr, RData)        := Pop(ReadDataFifo);
            RData                  := AlignDataBusToBytes(RData, TransRec.DataWidth, ByteAddr);
            TransRec.BoolFromModel <= TRUE;
            TransRec.DataFromModel <= SafeResize(ModelID, RData, TransRec.DataFromModel'length);

            if IsReadCheck(Operation) then
              ExpectedData := SafeResize(ModelID, TransRec.DataToModel, ExpectedData'length);
              if SlvErr = '1' then
                -- Read data with an error can be meaningless (IHI0024E 3.4)
                Log(ModelID, "Read Data not checked (PSLVERR = 1).  PADDR: " & to_hxstring(Addr) &
                    "  PRDATA: " & to_hxstring(RData) & "  Expected: " & to_hxstring(ExpectedData), INFO);
              else
                AffirmIf(DataCheckID, MetaMatch(RData, ExpectedData),
                         "Read Data: " & to_hxstring(RData) & "  PADDR: " & to_hxstring(Addr),
                         "  Expected: " & to_hxstring(ExpectedData),
                         TransRec.StatusMsgOn or IsLogEnabled(ModelID, INFO));
              end if;
            else
              Log(ModelID, "Read Data: " & to_hxstring(RData) & "  PADDR: " & to_hxstring(Addr),
                  INFO, TransRec.StatusMsgOn);
            end if;
          end if;

        when READ_BURST =>
          -- Reads may start unaligned and end mid-word: every transfer reads a whole
          -- word at an aligned address, and only the requested bytes are returned
          Addr     := SafeResize(ModelID, TransRec.Address, Addr'length);
          ByteAddr := CalculateByteAddress(Addr, BYTE_ADDR_WIDTH);
          if BurstFifoMode = ADDRESS_BUS_BURST_BYTE_MODE then
            BytesToReceive   := TransRec.DataWidth;
            TransfersInBurst := 1 + CalculateBurstLen(BytesToReceive, ByteAddr, DATA_BYTE_WIDTH);
          else
            BytesToReceive   := TransRec.DataWidth * DATA_BYTE_WIDTH;
            TransfersInBurst := TransRec.DataWidth;
          end if;
          Log(ModelID,
              "Read Burst.  PADDR: " & to_hxstring(Addr) & "  Transfers in Burst: " &
              to_string(TransfersInBurst), INFO, TransRec.StatusMsgOn);

          if BYTE_ADDR_WIDTH > 0 then
            Addr(BYTE_ADDR_WIDTH - 1 downto 0) := (others => '0');
          end if;
          for BurstLoop in 1 to TransfersInBurst loop
            Push(TransferFifo, '0' & ExpectedSlvErr & Addr & (WData'range => '0'));
            Addr := Addr + DATA_BYTE_WIDTH;
          end loop;
          ReadRequestCount     <= ReadRequestCount + TransfersInBurst;
          TransferRequestCount <= TransferRequestCount + TransfersInBurst;
          wait for 0 ns;

          for BurstLoop in 1 to TransfersInBurst loop
            if IsEmpty(ReadDataFifo) then
              WaitForToggle(ReadDoneCount);
            end if;
            (SlvErr, RData) := Pop(ReadDataFifo);
            PushReadBurstData(TransRec.ReadBurstFifo, BurstFifoMode, RData, BytesToReceive, ByteAddr);
            ByteAddr        := 0;
          end loop;

        when SET_MODEL_OPTIONS =>
          ApbOption := ApbOptionsType'val(TransRec.Options);
          if IsApbParameter(ApbOption) then
            Set(Params, TransRec.Options, TransRec.IntToModel);
          elsif ApbOption = PSLVERR then
            SlvErr := std_logic'val(TransRec.IntToModel);
            if SlvErr = '0' or SlvErr = '1' or SlvErr = '-' then
              ExpectedSlvErr := SlvErr;
            else
              Alert(ModelID, "Option PSLVERR must be '0', '1' or '-', not '" & to_string(SlvErr) & "'", FAILURE);
            end if;
          else
            Alert(ModelID, "Option " & to_upper(to_string(ApbOption)) & " is not supported by " & MODEL_INSTANCE_NAME, FAILURE);
          end if;

        when GET_MODEL_OPTIONS =>
          ApbOption := ApbOptionsType'val(TransRec.Options);
          if IsApbParameter(ApbOption) then
            TransRec.IntFromModel <= Get(Params, TransRec.Options);
          elsif ApbOption = PSLVERR then
            TransRec.IntFromModel <= std_logic'pos(ExpectedSlvErr);
          else
            Alert(ModelID, "Option " & to_upper(to_string(ApbOption)) & " is not supported by " & MODEL_INSTANCE_NAME, FAILURE);
            TransRec.IntFromModel <= 0;
          end if;

        when others =>
          -- Standard directives, multiple driver detection and unsupported operations
          DoDirectiveTransactions(
            TransRec              => TransRec,
            Clk                   => Clk,
            ModelID               => ModelID,
            UseCoverageDelays     => UseCoverageDelays,
            DelayCovID            => ArrDelayCovID,
            BurstFifoMode         => BurstFifoMode,
            TransactionDone       => TransactionDone,
            WriteTransactionDone  => WriteTransactionDone,
            ReadTransactionDone   => ReadTransactionDone,
            WriteTransactionCount => WriteDoneCount,
            ReadTransactionCount  => ReadDoneCount
          );
      end case;
    end loop DispatchLoop;
  end process TransactionDispatcher;

  WriteTransactionDone <= WriteRequestCount = WriteDoneCount;
  ReadTransactionDone  <= ReadRequestCount = ReadDoneCount;
  TransactionDone      <= WriteTransactionDone and ReadTransactionDone;


  ------------------------------------------------------------
  --  Transfer Handler
  --    Runs one APB transfer per TransferFifo entry
  ------------------------------------------------------------
  TransferHandler : process
    variable Config        : ApbProcConfigType;
    variable Write         : std_logic;
    variable ExpSlvErr     : std_logic;
    variable Addr          : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable WData         : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable RData         : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable IdleCycles    : integer;
    variable WaitStates    : natural;
    variable Status        : ApbStatusType;
    variable SlvErr        : std_logic;
    variable TransferCount : integer := 0;
  begin
    Config := (
      Revision         => APB_REVISION,
      Timing           => (
        PSel    => tpd_Clk_PSel,
        PEnable => tpd_Clk_PEnable,
        PAddr   => tpd_Clk_PAddr,
        PWrite  => tpd_Clk_PWrite,
        PWData  => tpd_Clk_PWData,
        PProt   => tpd_Clk_PProt,
        PStrb   => tpd_Clk_PStrb,
        PRData  => DEFAULT_DELAY,
        PReady  => DEFAULT_DELAY,
        PSlvErr => DEFAULT_DELAY
      ),
      ReadyTimeOut     => APB_DEFAULT_PREADY_TIME_OUT,
      SlvErrAlert      => FALSE,  -- the expected PSLVERR is checked below
      SlvErrAlertLevel => ERROR,
      ReadDataXCheck   => APB_DEFAULT_PRDATA_X_CHECK
    );
    -- IDLE from time 0: PSEL is always valid (IHI0024E App. A.1)
    ApbRequesterIdle(ApbBus.Requester, Config);
    -- Default random spacing: runs of 2 to 10 back-to-back transfers, then 1 to 5 IDLE cycles
    AddBins(TransferDelayCov.BurstLengthCov, GenBin(2, 10, 1));
    AddBins(TransferDelayCov.BurstDelayCov,  GenBin(1, 5, 1));
    AddBins(TransferDelayCov.BeatDelayCov,   GenBin(0));

    TransferLoop : loop
      if IsEmpty(TransferFifo) then
        WaitForToggle(TransferRequestCount);
      end if;
      (Write, ExpSlvErr, Addr, WData) := Pop(TransferFifo);
      TransferCount                   := TransferCount + 1;

      -- IDLE cycles before the transfer. With none, a transfer queued in the same
      -- time step as the previous completion follows it back-to-back.
      IdleCycles := GetRandDelay(TransferDelayCov) when UseCoverageDelays else
                    GetApbParameter(Params, TRANSFER_IDLE_CYCLES);
      WaitForClock(Clk, IdleCycles);

      -- No transfers during reset. The Requester stays IDLE.
      if to_X01(nReset) /= '1' then
        wait until to_X01(nReset) = '1';
        wait until rising_edge(Clk);
      end if;

      Config.ReadyTimeOut   := GetApbParameter(Params, PREADY_TIME_OUT);
      Config.ReadDataXCheck := GetApbParameter(Params, PRDATA_X_CHECK);

      ApbSetupPhase(Clk, ApbBus.Requester, Config, Addr, Write, WData, ProtocolID);
      ApbAccessPhase(Clk, nReset, ApbBus.Requester, ApbBus.Completer, Config,
                     RData, WaitStates, Status, ProtocolID, BusFailedID);
      -- Back-to-back: if another transfer is queued in this time step, its
      -- ApbSetupPhase replaces these IDLE values (IHI0024E 4.1, ACCESS to SETUP)
      ApbRequesterIdle(ApbBus.Requester, Config);

      SlvErr := '1' when Status = APB_SLVERR else '0';
      -- Only a completed transfer has a response (IHI0024E 3.4)
      if (Status = APB_OK or Status = APB_SLVERR) and not MetaMatch(SlvErr, ExpSlvErr) then
        Alert(TransferErrorID, "PSLVERR: " & to_string(SlvErr) & "  Expected: " & to_string(ExpSlvErr) &
              "  PADDR: "     & to_hxstring(Addr) & "  PWRITE: " & to_string(Write) &
              "  Operation# " & to_string(TransferCount),
              GetApbParameter(Params, PSLVERR_ALERT_LEVEL));
      end if;

      if Write = '1' then
        Log(ModelID, "Write." &
            "  PADDR: "      & to_hxstring(Addr) &
            "  PWDATA: "     & to_hxstring(WData) &
            "  PSLVERR: "    & to_string(SlvErr) &
            "  WaitStates: " & to_string(WaitStates) &
            "  Status: "     & to_string(Status) &
            "  Operation# "  & to_string(TransferCount),
            INFO);
        Increment(WriteDoneCount);
      else
        Log(ModelID, "Read." &
            "  PADDR: "      & to_hxstring(Addr) &
            "  PRDATA: "     & to_hxstring(RData) &
            "  PSLVERR: "    & to_string(SlvErr) &
            "  WaitStates: " & to_string(WaitStates) &
            "  Status: "     & to_string(Status) &
            "  Operation# "  & to_string(TransferCount),
            INFO);
        Push(ReadDataFifo, SlvErr & RData);
        Increment(ReadDoneCount);
      end if;

      if Status = APB_TIMEOUT or Status = APB_ABORTED then
        -- At least one IDLE cycle after an abandoned transfer, so that the
        -- Completer sees it end before the next SETUP
        wait until rising_edge(Clk);
      end if;
      wait for 0 ns;  -- Allow the done counts to update
    end loop TransferLoop;
  end process TransferHandler;

end architecture behavioral;
