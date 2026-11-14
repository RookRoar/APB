--
--  Original Author:  Kartik Desai
--
--  Description:
--      APB Completer memory verification component. Answers every transfer on
--      its own from an OSVVM MemoryPkg memory. The test can read and write the
--      memory directly (backdoor) through the AddressBusRecType interface.
--
--  Notes:
--      Structure follows OSVVM Axi4LiteMemory. The memory is byte wide with byte
--      addresses, and can be shared with other models by MEMORY_NAME.
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

library osvvm_common;
context osvvm_common.OsvvmCommonContext;

use work.ApbSettingsPkg.all;
use work.ApbInterfacePkg.all;
use work.ApbOptionsPkg.all;
use work.ApbProtocolPkg.all;

entity ApbCompleterMemory is
  generic (
    MODEL_ID_NAME   : string          := "";
    MEMORY_NAME     : string          := "";
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
    IfElse(MODEL_ID_NAME /= "", MODEL_ID_NAME, PathTail(to_lower(ApbCompleterMemory'PATH_NAME)));

  constant LOCAL_MEMORY_NAME : string :=
    IfElse(MEMORY_NAME /= "", MEMORY_NAME, MODEL_INSTANCE_NAME & ":memory");

end entity ApbCompleterMemory;

architecture behavioral of ApbCompleterMemory is

  constant DATA_BYTE_WIDTH : integer := DATA_WIDTH / 8;
  constant BYTE_ADDR_WIDTH : integer := integer(ceil(log2(real(DATA_BYTE_WIDTH))));

  -- AlertLog, parameter and memory IDs are constants, created during elaboration:
  -- every process can use them from time 0, and they are created in
  -- declaration order
  constant ModelID     : AlertLogIDType        := NewID(MODEL_INSTANCE_NAME);
  constant ProtocolID  : AlertLogIDType        := NewID("Protocol Error", ModelID);
  constant DataCheckID : AlertLogIDType        := NewID("Data Check", ModelID);
  constant Params      : ModelParametersIDType := NewApbParams("Parameters", ModelID);

  -- As in Axi4LiteMemory: a memory shared by name is not a child of this model
  constant MemoryID : MemoryIDType := NewID(
    Name      => LOCAL_MEMORY_NAME,
    AddrWidth => ADDR_WIDTH,  -- byte address (IHI0024E 2.1.1)
    DataWidth => 8,           -- byte wide
    ParentID  => IfElse(MODEL_INSTANCE_NAME /= LOCAL_MEMORY_NAME, ModelID, ALERTLOG_BASE_ID),
    Search    => NAME
  );

  -- Delay coverage: one delay point, the PREADY wait states.
  -- A signal, because the test can replace it (SetDelayCoverageID).
  signal ArrDelayCovID     : DelayCoverageIDArrayType(1 to 1) :=
    (1 => NewID("WaitStateDelayCov", ModelID, ReportMode => DISABLED));
  alias  WaitStateDelayCov is ArrDelayCovID(1);
  signal UseCoverageDelays : boolean                          := FALSE;
  signal BurstFifoMode     : AddressBusFifoBurstModeType      := ADDRESS_BUS_BURST_WORD_MODE;

  -- PSLVERR interface option: the response when no error injection applies
  signal SlvErrOption : std_logic := '0';

  -- Completed bus transfers
  signal WriteReceiveCount : integer := 0;
  signal ReadReceiveCount  : integer := 0;

  -- A memory never has outstanding work; WAIT_FOR_* are handled in the dispatcher
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
  --    Backdoor access to the memory, options and directives
  ------------------------------------------------------------
  TransactionDispatcher : process
    variable Addr         : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable Data         : std_logic_vector(TransRec.DataToModel'range);
    variable ExpectedData : std_logic_vector(TransRec.DataToModel'range);
    variable ByteData     : std_logic_vector(7 downto 0);
    variable NumBytes     : integer;
    variable Count        : integer;
    variable ApbOption    : ApbOptionsType;
    variable SlvErr       : std_logic;
  begin
    TransRec.Params <= Params;

    DispatchLoop : loop
      WaitForTransaction(
        Clk => Clk,
        Rdy => TransRec.Rdy,
        Ack => TransRec.Ack
      );

      case TransRec.Operation is
        -- Backdoor: no bus cycle
        when WRITE_OP =>
          Addr     := SafeResize(ModelID, TransRec.Address, Addr'length);
          Data     := SafeResize(ModelID, TransRec.DataToModel, Data'length);
          NumBytes := TransRec.DataWidth / 8;
          for i in 0 to NumBytes - 1 loop
            MemWrite(MemoryID, Addr + i, Data(8 * i + 7 downto 8 * i));
          end loop;
          Log(ModelID, "Backdoor Write.  Address: " & to_hxstring(Addr) &
              "  Data: " & to_hxstring(Data(TransRec.DataWidth - 1 downto 0)), DEBUG);

        when READ_OP | READ_CHECK =>
          Addr     := SafeResize(ModelID, TransRec.Address, Addr'length);
          Data     := (others => '0');
          NumBytes := TransRec.DataWidth / 8;
          for i in 0 to NumBytes - 1 loop
            MemRead(MemoryID, Addr + i, ByteData);
            Data(8 * i + 7 downto 8 * i) := ByteData;
          end loop;
          TransRec.DataFromModel <= SafeResize(ModelID, Data, TransRec.DataFromModel'length);

          if IsReadCheck(TransRec.Operation) then
            ExpectedData := SafeResize(ModelID, TransRec.DataToModel, ExpectedData'length);
            AffirmIf(DataCheckID, MetaMatch(Data, ExpectedData),
                     "Backdoor Read.  Address: " & to_hxstring(Addr) & "  Data: " & to_hxstring(Data),
                     "  Expected: " & to_hxstring(ExpectedData),
                     TransRec.StatusMsgOn or IsLogEnabled(ModelID, INFO));
          else
            Log(ModelID, "Backdoor Read.  Address: " & to_hxstring(Addr) &
                "  Data: " & to_hxstring(Data), INFO, TransRec.StatusMsgOn);
          end if;

        when WAIT_FOR_TRANSACTION =>
          Count := WriteReceiveCount + ReadReceiveCount;
          wait until WriteReceiveCount + ReadReceiveCount = Count + 1;

        when WAIT_FOR_WRITE_TRANSACTION =>
          Count := WriteReceiveCount;
          wait until WriteReceiveCount = Count + 1;

        when WAIT_FOR_READ_TRANSACTION =>
          Count := ReadReceiveCount;
          wait until ReadReceiveCount = Count + 1;

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
          DoDirectiveTransactions(
            TransRec              => TransRec,
            Clk                   => Clk,
            ModelID               => ModelID,
            UseCoverageDelays     => UseCoverageDelays,
            DelayCovID            => ArrDelayCovID,
            BurstFifoMode         => BurstFifoMode,  -- not used by a memory
            TransactionDone       => TransactionDone,
            WriteTransactionDone  => WriteTransactionDone,
            ReadTransactionDone   => ReadTransactionDone,
            WriteTransactionCount => WriteReceiveCount,
            ReadTransactionCount  => ReadReceiveCount
          );
      end case;
    end loop DispatchLoop;
  end process TransactionDispatcher;


  ------------------------------------------------------------
  --  Bus Handler
  --    Answers each APB transfer from the memory
  ------------------------------------------------------------
  BusHandler : process
    variable Config       : ApbProcConfigType;
    variable Transfer     : ApbTransferType(
      Addr(ADDR_WIDTH - 1 downto 0),
      WData(DATA_WIDTH - 1 downto 0),
      RData(DATA_WIDTH - 1 downto 0),
      Strb(DATA_BYTE_WIDTH - 1 downto 0)
    );
    variable WordAddr     : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    variable RData        : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable ByteData     : std_logic_vector(7 downto 0);
    variable WaitStates   : natural;
    variable Status       : ApbStatusType;
    variable SlvErr       : std_logic;
    variable Inject       : boolean;
    variable NthCount     : natural := 0;
    variable UpdateMemory : boolean;
    variable RV           : RandomPType;
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
    -- Default random wait states: runs of 2 to 10 transfers with none, then one with 1 to 5
    AddBins(WaitStateDelayCov.BurstLengthCov, GenBin(2, 10, 1));
    AddBins(WaitStateDelayCov.BurstDelayCov,  GenBin(1, 5, 1));
    AddBins(WaitStateDelayCov.BeatDelayCov,   GenBin(0));

    BusLoop : loop
      ApbWaitForTransfer(Clk, nReset, ApbBus.Requester, Config, Transfer, ProtocolID);

      -- Unaligned PADDR is UNPREDICTABLE (IHI0024E 2.1.1); the memory uses the aligned address
      WordAddr   := Transfer.Addr(ADDR_WIDTH - 1 downto BYTE_ADDR_WIDTH) & (BYTE_ADDR_WIDTH - 1 downto 0 => '0');
      WaitStates := GetRandDelay(WaitStateDelayCov) when UseCoverageDelays else
                    GetApbParameter(Params, WAIT_STATES);

      -- Error injection, else the PSLVERR option
      ApbErrorInjection(Params, Transfer.Addr, NthCount, RV, Inject);
      SlvErr := '1' when Inject else SlvErrOption;

      -- Read data must be valid even with an error (IHI0024E App. A.1); its value
      -- may be meaningless (3.4), so ERROR_READ_DATA selects memory data or zeros
      if Transfer.Write = '1' or
         (SlvErr = '1' and GetApbParameter(Params, ERROR_READ_DATA) = ERROR_DATA_ZERO) then
        RData := (others => '0');
      else
        for i in 0 to DATA_BYTE_WIDTH - 1 loop
          MemRead(MemoryID, WordAddr + i, ByteData);
          RData(8 * i + 7 downto 8 * i) := ByteData;
        end loop;
      end if;

      ApbRespond(Clk, nReset, ApbBus.Requester, ApbBus.Completer, Config,
                 WaitStates, RData, SlvErr, Status, ProtocolID);

      if Status /= APB_ABORTED then
        if Transfer.Write = '1' then
          -- A write with an error may or may not update the memory (IHI0024E 3.4)
          UpdateMemory := SlvErr = '0' or GetApbParameter(Params, ERROR_WRITE_UPDATES);
          if UpdateMemory then
            -- APB3 has no PSTRB, so every byte lane is written (IHI0024E Table 3-1)
            for i in 0 to DATA_BYTE_WIDTH - 1 loop
              MemWrite(MemoryID, WordAddr + i, Transfer.WData(8 * i + 7 downto 8 * i));
            end loop;
          end if;
          Log(ModelID, "Memory Write." &
              "  PADDR: "          & to_hxstring(Transfer.Addr) &
              "  PWDATA: "         & to_hxstring(Transfer.WData) &
              "  PSLVERR: "        & to_string(SlvErr) &
              "  Memory updated: " & to_string(UpdateMemory) &
              "  WaitStates: "     & to_string(WaitStates) &
              "  Operation# "      & to_string(WriteReceiveCount + 1),
              INFO);
          Increment(WriteReceiveCount);
        else
          Log(ModelID, "Memory Read." &
              "  PADDR: "      & to_hxstring(Transfer.Addr) &
              "  PRDATA: "     & to_hxstring(RData) &
              "  PSLVERR: "    & to_string(SlvErr) &
              "  WaitStates: " & to_string(WaitStates) &
              "  Operation# "  & to_string(ReadReceiveCount + 1),
              INFO);
          Increment(ReadReceiveCount);
        end if;
      end if;
    end loop BusLoop;
  end process BusHandler;

end architecture behavioral;
