--
--  Original Author:  Kartik Desai
--
--  Description:
--      APB Completer verification component driven by the test through the OSVVM
--      AddressBusRecType responder transactions (GetWrite, SendRead, ...)
--
--  Notes:
--      Structure follows OSVVM Axi4LiteSubordinate. Each transfer waits in ACCESS
--      with PREADY LOW until the test has taken the write or supplied the read
--      data; WAIT_STATES is the minimum number of wait states.
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

entity ApbCompleter is
  generic (
    MODEL_ID_NAME   : string          := "";
    APB_REVISION    : ApbRevisionType := APB3;

    DEFAULT_DELAY   : time            := APB_DEFAULT_DELAY;

    tpd_Clk_PReady  : time            := DEFAULT_DELAY;
    tpd_Clk_PRData  : time            := DEFAULT_DELAY;
    tpd_Clk_PSlvErr : time            := DEFAULT_DELAY
  );
  port (
    -- Globals
    Clk      : in    std_logic;
    nReset   : in    std_logic;

    -- APB Completer interface
    ApbBus   : inout ApbRecType;

    -- Testbench transaction interface
    TransRec : inout AddressBusRecType
  );

  -- Derive interface properties from the bus
  constant ADDR_WIDTH : integer := ApbBus.Requester.PAddr'length;
  constant DATA_WIDTH : integer := ApbBus.Requester.PWData'length;

  -- Use MODEL_ID_NAME if set, otherwise the instance label
  constant MODEL_INSTANCE_NAME : string :=
    IfElse(MODEL_ID_NAME /= "", MODEL_ID_NAME, PathTail(to_lower(ApbCompleter'PATH_NAME)));

end entity ApbCompleter;

architecture behavioral of ApbCompleter is

  constant DATA_BYTE_WIDTH : integer := DATA_WIDTH / 8;
  constant BYTE_ADDR_WIDTH : integer := integer(ceil(log2(real(DATA_BYTE_WIDTH))));

  -- AlertLog, parameter and FIFO IDs are constants, created during elaboration:
  -- every process can use them from time 0, and they are created in
  -- declaration order
  constant ModelID    : AlertLogIDType        := NewID(MODEL_INSTANCE_NAME);
  constant ProtocolID : AlertLogIDType        := NewID("Protocol Error", ModelID);
  constant Params     : ModelParametersIDType := NewApbParams("Parameters", ModelID);

  -- Internal FIFOs. APB has one transfer at a time, so the write FIFOs hold at
  -- most the current write; read data may be queued before the read arrives.
  --   WriteAddrFifo: PADDR of the current write, until the test takes it
  --   WriteDataFifo: PADDR & PWDATA of the current write, until the test takes it
  --   WriteRespFifo: PSLVERR option when the test has taken the whole write
  --   ReadAddrFifo:  PADDR of each read, until the test takes it
  --   ReadDataFifo:  PSLVERR option & data width & data from the test
  constant WriteAddrFifo : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("WriteAddrFifo", ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);
  constant WriteDataFifo : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("WriteDataFifo", ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);
  constant WriteRespFifo : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("WriteRespFifo", ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);
  constant ReadAddrFifo  : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("ReadAddrFifo",  ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);
  constant ReadDataFifo  : osvvm.ScoreboardPkg_slv.ScoreboardIDType :=
    NewID("ReadDataFifo",  ModelID, ReportMode => DISABLED, Search => PRIVATE_NAME);

  -- Delay coverage: one delay point, the minimum PREADY wait states.
  -- A signal, because the test can replace it (SetDelayCoverageID).
  signal ArrDelayCovID     : DelayCoverageIDArrayType(1 to 1) :=
    (1 => NewID("WaitStateDelayCov", ModelID, ReportMode => DISABLED));
  alias  WaitStateDelayCov is ArrDelayCovID(1);
  signal UseCoverageDelays : boolean                          := FALSE;
  signal BurstFifoMode     : AddressBusFifoBurstModeType      := ADDRESS_BUS_BURST_WORD_MODE;

  -- PSLVERR interface option: the response when no error injection applies
  signal SlvErrOption : std_logic := '0';

  -- Transfers seen on the bus, and answers from the test
  signal WriteReceiveCount : integer := 0;
  signal ReadReceiveCount  : integer := 0;
  signal AnswerCount       : integer := 0;

  -- Directives on completion are not used: the test answers each transfer
  signal TransactionDone      : boolean := TRUE;
  signal WriteTransactionDone : boolean := TRUE;
  signal ReadTransactionDone  : boolean := TRUE;

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
  --    Hands transfers to the test and takes its answers
  ------------------------------------------------------------
  TransactionDispatcher : process
    variable Operation      : AddressBusOperationType;
    variable ApbOption      : ApbOptionsType;
    variable Addr           : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable WData          : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable SlvErr         : std_logic;
    variable Available      : boolean;
    variable ByteAddr       : integer;
    variable OperationCount : integer := 0;
  begin
    TransRec.Params <= Params;

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
          Available := not ((IsTryWriteAddress(Operation) and IsEmpty(WriteAddrFifo)) or
                            (IsTryWriteData(Operation)    and IsEmpty(WriteDataFifo)));
          TransRec.BoolFromModel <= Available;
          if not Available then
            TransRec.DataFromModel <= (TransRec.DataFromModel'range => '0');
          end if;

          if Available and IsWriteAddress(Operation) then
            if IsEmpty(WriteAddrFifo) then
              WaitForToggle(WriteReceiveCount);
            end if;
            Addr             := Pop(WriteAddrFifo);
            TransRec.Address <= SafeResize(ModelID, Addr, TransRec.Address'length);
          end if;

          if Available and IsWriteData(Operation) then
            if IsEmpty(WriteDataFifo) then
              WaitForToggle(WriteReceiveCount);
            end if;
            -- The write's own PADDR selects the byte lanes returned
            (Addr, WData)          := Pop(WriteDataFifo);
            ByteAddr               := CalculateByteAddress(Addr, BYTE_ADDR_WIDTH);
            CheckDataIsBytes(ModelID, TransRec.DataWidth, "Completer GetWrite: ", OperationCount);
            CheckDataWidth(ModelID, TransRec.DataWidth, ByteAddr, DATA_WIDTH, "Completer GetWrite: ", OperationCount);
            WData                  := AlignDataBusToBytes(WData, TransRec.DataWidth, ByteAddr);
            TransRec.DataFromModel <= SafeResize(ModelID, WData, TransRec.DataFromModel'length);
          end if;

          -- The whole write is taken: answer it with the PSLVERR option in force now
          if Available and IsEmpty(WriteAddrFifo) and IsEmpty(WriteDataFifo) and
             WriteReceiveCount > 0 and GetFifoCount(WriteRespFifo) = 0 then
            Push(WriteRespFifo, "" & SlvErrOption);
            Increment(AnswerCount);
          end if;

        when READ_OP | READ_ADDRESS | READ_DATA | ASYNC_READ | ASYNC_READ_ADDRESS | ASYNC_READ_DATA =>
          Available              := not (IsTryReadAddress(Operation) and IsEmpty(ReadAddrFifo));
          TransRec.BoolFromModel <= Available;

          if Available and IsReadAddress(Operation) then
            if IsEmpty(ReadAddrFifo) then
              WaitForToggle(ReadReceiveCount);
            end if;
            Addr             := Pop(ReadAddrFifo);
            TransRec.Address <= SafeResize(ModelID, Addr, TransRec.Address'length);
          end if;

          if Available and IsReadData(Operation) then
            -- Aligned to the byte lanes of the read's PADDR when the response is driven
            CheckDataIsBytes(ModelID, TransRec.DataWidth, "Completer SendRead: ", OperationCount);
            Push(ReadDataFifo, SlvErrOption & to_slv(TransRec.DataWidth, 16) &
                               SafeResize(ModelID, TransRec.DataToModel, DATA_WIDTH));
            Increment(AnswerCount);
          end if;

        when WAIT_FOR_TRANSACTION =>
          -- Wait for a write or a read to be available
          loop
            exit when not IsEmpty(WriteDataFifo) or not IsEmpty(ReadAddrFifo);
            wait on WriteReceiveCount, ReadReceiveCount;
          end loop;

        when WAIT_FOR_WRITE_TRANSACTION =>
          if IsEmpty(WriteDataFifo) then
            WaitForToggle(WriteReceiveCount);
          end if;

        when WAIT_FOR_READ_TRANSACTION =>
          if IsEmpty(ReadAddrFifo) then
            WaitForToggle(ReadReceiveCount);
          end if;

        when SET_MODEL_OPTIONS =>
          ApbOption := ApbOptionsType'val(TransRec.Options);
          if IsApbParameter(ApbOption) then
            Set(Params, TransRec.Options, TransRec.IntToModel);
          elsif ApbOption = PSLVERR then
            -- The Completer drives PSLVERR, so it must be valid (IHI0024E App. A.1)
            SlvErr := std_logic'val(TransRec.IntToModel);
            if SlvErr = '0' or SlvErr = '1' then
              SlvErrOption <= SlvErr;
            else
              Alert(ModelID, "Option PSLVERR must be '0' or '1', not '" & to_string(SlvErr) & "'", FAILURE);
            end if;
          else
            Alert(ModelID, "Option " & to_upper(to_string(ApbOption)) & " is not supported by " & MODEL_INSTANCE_NAME, FAILURE);
          end if;

        when GET_MODEL_OPTIONS =>
          ApbOption := ApbOptionsType'val(TransRec.Options);
          if IsApbParameter(ApbOption) then
            TransRec.IntFromModel <= Get(Params, TransRec.Options);
          elsif ApbOption = PSLVERR then
            TransRec.IntFromModel <= std_logic'pos(SlvErrOption);
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
            BurstFifoMode         => BurstFifoMode,  -- bursts are not supported
            TransactionDone       => TransactionDone,
            WriteTransactionDone  => WriteTransactionDone,
            ReadTransactionDone   => ReadTransactionDone,
            WriteTransactionCount => WriteReceiveCount,
            ReadTransactionCount  => ReadReceiveCount
          );
      end case;

      -- Allow the counts to update before the next transaction
      wait for 0 ns;
    end loop DispatchLoop;
  end process TransactionDispatcher;


  ------------------------------------------------------------
  --  Bus Handler
  --    Holds each transfer in ACCESS until the test answers it
  ------------------------------------------------------------
  BusHandler : process
    variable Config        : ApbProcConfigType;
    variable Transfer      : ApbTransferType(
      Addr(ADDR_WIDTH - 1 downto 0),
      WData(DATA_WIDTH - 1 downto 0),
      RData(DATA_WIDTH - 1 downto 0),
      Strb(DATA_BYTE_WIDTH - 1 downto 0)
    );
    variable RData         : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable DataWidth     : std_logic_vector(15 downto 0);
    variable MinWaitStates : natural;
    variable Elapsed       : natural;
    variable WaitStates    : natural;
    variable Status        : ApbStatusType;
    variable SlvErr        : std_logic;
    variable Inject        : boolean;
    variable NthCount      : natural := 0;
    variable RV            : RandomPType;
    variable Discard       : std_logic_vector(ADDR_WIDTH + DATA_WIDTH - 1 downto 0);
    variable Resp          : std_logic_vector(0 downto 0);

    -- The Requester left ACCESS before completion (reset, PSEL LOW, or PENABLE LOW)
    impure function Aborted return boolean is
    begin
      return to_X01(nReset) = '0' or to_X01(ApbBus.Requester.PSel) /= '1' or
             to_X01(ApbBus.Requester.PEnable) /= '1';
    end function Aborted;

    impure function Answered return boolean is
    begin
      if Transfer.Write = '1' then
        return not IsEmpty(WriteRespFifo);
      else
        return not IsEmpty(ReadDataFifo);
      end if;
    end function Answered;
  begin
    RV.InitSeed(MODEL_INSTANCE_NAME);
    Config := (
      Revision         => APB_REVISION,
      Timing           => (
        PSel    => DEFAULT_DELAY,
        PEnable => DEFAULT_DELAY,
        PAddr   => DEFAULT_DELAY,
        PWrite  => DEFAULT_DELAY,
        PWData  => DEFAULT_DELAY,
        PProt   => DEFAULT_DELAY,
        PStrb   => DEFAULT_DELAY,
        PRData  => tpd_Clk_PRData,
        PReady  => tpd_Clk_PReady,
        PSlvErr => tpd_Clk_PSlvErr
      ),
      ReadyTimeOut     => 0,
      SlvErrAlert      => FALSE,
      SlvErrAlertLevel => ERROR,
      ReadDataXCheck   => FALSE
    );
    ApbCompleterIdle(ApbBus.Completer, Config);
    -- Default random minimum: runs of 2 to 10 transfers with none, then one with 1 to 5
    AddBins(WaitStateDelayCov.BurstLengthCov, GenBin(2, 10, 1));
    AddBins(WaitStateDelayCov.BurstDelayCov,  GenBin(1, 5, 1));
    AddBins(WaitStateDelayCov.BeatDelayCov,   GenBin(0));

    BusLoop : loop
      ApbWaitForTransfer(Clk, nReset, ApbBus.Requester, Config, Transfer, ProtocolID);
      MinWaitStates := GetRandDelay(WaitStateDelayCov) when UseCoverageDelays else
                       GetApbParameter(Params, WAIT_STATES);

      -- Hand the transfer to the test
      if Transfer.Write = '1' then
        Push(WriteAddrFifo, Transfer.Addr);
        Push(WriteDataFifo, Transfer.Addr & Transfer.WData);
        Increment(WriteReceiveCount);
      else
        Push(ReadAddrFifo, Transfer.Addr);
        Increment(ReadReceiveCount);
      end if;
      wait for 0 ns;

      -- Wait states until the test answers: PREADY LOW in ACCESS (IHI0024E 3.3.2)
      Elapsed := 0;
      Status  := APB_OK;
      ApbCompleterIdle(ApbBus.Completer, Config);
      while not Answered loop
        wait on Clk, AnswerCount;
        if rising_edge(Clk) then
          Elapsed := Elapsed + 1;
          if Aborted then
            Status := APB_ABORTED;
            exit;
          end if;
        end if;
      end loop;

      if Status = APB_ABORTED then
        Alert(ProtocolID, "APB transfer aborted by the Requester or by reset while waiting for the test.  PADDR: " &
              to_hxstring(Transfer.Addr), WARNING);
        -- Drop what the test has not taken of the aborted write
        if Transfer.Write = '1' then
          if not IsEmpty(WriteAddrFifo) then
            Discard(ADDR_WIDTH - 1 downto 0) := Pop(WriteAddrFifo);
          end if;
          if not IsEmpty(WriteDataFifo) then
            Discard := Pop(WriteDataFifo);
          end if;
          if not IsEmpty(WriteRespFifo) then
            Resp := Pop(WriteRespFifo);
          end if;
        end if;
        next BusLoop;
      end if;

      -- Error injection, else the PSLVERR option in force when the test answered
      ApbErrorInjection(Params, Transfer.Addr, NthCount, RV, Inject);
      if Transfer.Write = '1' then
        Resp   := Pop(WriteRespFifo);
        SlvErr := Resp(0);
        RData  := (others => '0');
      else
        (SlvErr, DataWidth, RData) := Pop(ReadDataFifo);
        -- Place the test's data on the byte lanes of PADDR
        CheckDataWidth(ModelID, to_integer(DataWidth), CalculateByteAddress(Transfer.Addr, BYTE_ADDR_WIDTH),
                       DATA_WIDTH, "Completer SendRead: ", ReadReceiveCount);
        RData := AlignBytesToDataBus(RData, to_integer(DataWidth), CalculateByteAddress(Transfer.Addr, BYTE_ADDR_WIDTH));
        -- Lanes the test did not supply are driven as zero: PRDATA must be valid (App. A.1)
        for i in RData'range loop
          if RData(i) = 'U' then
            RData(i) := '0';
          end if;
        end loop;
      end if;
      SlvErr := '1' when Inject else SlvErr;

      WaitStates := MinWaitStates - Elapsed when MinWaitStates > Elapsed else 0;
      ApbRespond(Clk, nReset, ApbBus.Requester, ApbBus.Completer, Config,
                 WaitStates, RData, SlvErr, Status, ProtocolID);

      if Status /= APB_ABORTED then
        if Transfer.Write = '1' then
          Log(ModelID, "Write." &
              "  PADDR: "      & to_hxstring(Transfer.Addr) &
              "  PWDATA: "     & to_hxstring(Transfer.WData) &
              "  PSLVERR: "    & to_string(SlvErr) &
              "  WaitStates: " & to_string(Elapsed + WaitStates) &
              "  Operation# "  & to_string(WriteReceiveCount),
              INFO);
        else
          Log(ModelID, "Read." &
              "  PADDR: "      & to_hxstring(Transfer.Addr) &
              "  PRDATA: "     & to_hxstring(RData) &
              "  PSLVERR: "    & to_string(SlvErr) &
              "  WaitStates: " & to_string(Elapsed + WaitStates) &
              "  Operation# "  & to_string(ReadReceiveCount), INFO);
        end if;
      end if;
    end loop BusLoop;
  end process BusHandler;

end architecture behavioral;
