--
--  Original Author:  Jim Lewis, SynthWorks Design Inc.
--
--  Description:
--      Byte-lane and data-width helpers for the APB verification components
--
--  Notes:
--      Derived from OSVVM 2026.09 AXI4/common/src/Axi4ModelPkg.vhd (SynthWorks).
--      Modified by Kartik Desai, 2026: package renamed to ApbModelPkg; only the
--      address, strobe, alignment, data-width and burst FIFO helpers are kept
--      (AXI delay IDs, FilterUndrivenData and the protected-type FIFO versions
--      are removed). CalculateByteAddress returns 0 when there are no byte
--      address bits (8-bit data bus) instead of converting a null slice. The
--      other kept subprograms are unchanged. This keeps osvvm_apb independent of
--      the osvvm_axi4 library.
--
--  Copyright (c) 2017 - 2025 by SynthWorks Design Inc.
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

package ApbModelPkg is
  ------------------------------------------------------------
  function CalculateByteAddress (
  -- Fetch the address and data the Completer sees for a write
  ------------------------------------------------------------
    constant Address         : in std_logic_vector;
    constant AddrBitsPerWord : in integer
  ) return integer;

  ------------------------------------------------------------
  function CalculateBurstLen (
  ------------------------------------------------------------
    constant NumBytes    : in integer;
    constant ByteAddress : in integer;
    constant ByteWidth   : in integer
  ) return integer;

--!!  -- Keep for now
--!!  ------------------------------------------------------------
--!!  function CalculateWriteStrobe (
--!!  ------------------------------------------------------------
--!!    constant ByteAddr      : In  integer ;
--!!    constant NumberOfBytes : In  integer ;
--!!    constant MaxBytes      : In  integer
--!!  ) return std_logic_vector ;

  ------------------------------------------------------------
  function CalculateWriteStrobe (
  ------------------------------------------------------------
    constant Data : in std_logic_vector
  ) return std_logic_vector;

  ------------------------------------------------------------
  function AlignBytesToDataBus (
  -- Shift Data to Align it.
  ------------------------------------------------------------
    constant Data      : in std_logic_vector;
    constant DataWidth : in integer;
    constant ByteAddr  : in integer
  ) return std_logic_vector;

  ------------------------------------------------------------
  procedure CheckDataIsBytes (
  -- Check AXI Write Data Width - BYTE and < WordWidth adjusted for ByteAddr
  ------------------------------------------------------------
    constant ModelID        : in AlertLogIDType;
    constant DataWidth      : in integer;
    constant MessagePrefix  : in string  := "";
    constant TransferNumber : in integer := -1
  );

  ------------------------------------------------------------
  procedure CheckDataWidth (
  -- Check AXI Write Data Width - BYTE and < WordWidth adjusted for ByteAddr
  ------------------------------------------------------------
    constant ModelID        : in AlertLogIDType;
    constant DataWidth      : in integer;
    constant ByteAddr       : in integer;
    constant MaxDataBits    : in integer;
    constant MessagePrefix  : in string  := "";
    constant TransferNumber : in integer := -1
  );

  ------------------------------------------------------------
  procedure PopWriteBurstData (
  ------------------------------------------------------------
    constant WriteBurstFifo : in    osvvm.ScoreboardPkg_slv.ScoreboardIdType;
    constant BurstFifoMode  : in    AddressBusFifoBurstModeType;
    variable WriteData      : inout std_logic_vector;
--!!    variable WriteStrb       : InOut std_logic_vector ;
    variable BytesToSend    : inout integer;
    constant ByteAddress    : in    integer := 0
  );

  ------------------------------------------------------------
  procedure PushReadBurstData (
  -- Push Burst Data into Byte Burst FIFO.
  ------------------------------------------------------------
    constant ReadBurstFifo  : in    osvvm.ScoreboardPkg_slv.ScoreboardIdType;
    constant BurstFifoMode  : in    AddressBusFifoBurstModeType;
    variable ReadData       : inout std_logic_vector;
    variable BytesToReceive : inout integer;
    constant ByteAddress    : in    integer := 0
  );

  ------------------------------------------------------------
  function AlignDataBusToBytes (
  -- Shift Data Right and MASK unused bytes.
  ------------------------------------------------------------
    constant Data      : in std_logic_vector;
    constant DataWidth : in integer;
    constant ByteAddr  : in integer
  ) return std_logic_vector;

end package ApbModelPkg;

package body ApbModelPkg is

  ------------------------------------------------------------
  function CalculateByteAddress (
  ------------------------------------------------------------
    constant Address         : in std_logic_vector;
    constant AddrBitsPerWord : in integer
  ) return integer is
    alias aAddr : std_logic_vector(Address'length downto 1) is Address;
  begin
    if Address'length = 0 or AddrBitsPerWord = 0 then
      -- 8-bit data bus: every address is word aligned
      return 0;
    else
      return to_integer(aAddr(AddrBitsPerWord downto 1) );
    end if;
  end function CalculateByteAddress;

  ------------------------------------------------------------
  function CalculateBurstLen (
  ------------------------------------------------------------
    constant NumBytes    : in integer;
    constant ByteAddress : in integer;
    constant ByteWidth   : in integer
  ) return integer is
    variable BytesInFirstTransfer    : integer;
    variable BytesAfterFirstTransfer : integer;
  begin
    BytesInFirstTransfer := ByteWidth - ByteAddress;
    if BytesInFirsttransfer > NumBytes then
      return 0;  -- only one word in transfer
    else
      BytesAfterFirstTransfer := NumBytes - BytesInFirstTransfer;
      return 0 + integer(ceil(real(BytesAfterFirstTransfer) / real(ByteWidth)));
    end if;
  end function CalculateBurstLen;

  ------------------------------------------------------------
  function CalculateWriteStrobe (
  ------------------------------------------------------------
    constant Data : in std_logic_vector
  ) return std_logic_vector is
    variable WriteStrobe : std_logic_vector(Data'length / 8 - 1 downto 0) := (others => '0');
    alias    aData       : std_logic_vector(Data'length - 1 downto 0) is Data;
  begin
    for i in WriteStrobe'reverse_range loop
      if aData(i * 8) /= 'U' then
        WriteStrobe(i) := '1';
      end if;
    end loop;
    return WriteStrobe;
  end function CalculateWriteStrobe;

  ------------------------------------------------------------
  function AlignBytesToDataBus (
  ------------------------------------------------------------
    constant Data      : in std_logic_vector;
    constant DataWidth : in integer;
    constant ByteAddr  : in integer
  ) return std_logic_vector is
    constant DATA_LEFT : integer                              := Data'length - 1;
    alias    aData     : std_logic_vector(DATA_LEFT downto 0) is Data;
    variable result    : std_logic_vector(DATA_LEFT downto 0) := (others => 'U');
  begin
    if DataWidth < Data'length then
      Result(DataWidth + ByteAddr * 8 - 1 downto ByteAddr * 8) := aData(DataWidth - 1 downto 0);
      return Result;
    else
      -- Make Bits to the Right of ByteAddr a U
      Result(DATA_LEFT downto ByteAddr * 8) := aData(DATA_LEFT downto ByteAddr * 8);
      return Result;
    end if;
  end function AlignBytesToDataBus;

  ------------------------------------------------------------
  function AlignDataBusToBytes (
  -- Shift Data Right and MASK unused bytes.
  ------------------------------------------------------------
    constant Data      : in std_logic_vector;
    constant DataWidth : in integer;
    constant ByteAddr  : in integer
  ) return std_logic_vector is
    constant DATA_LEFT : integer                              := Data'length - 1;
    alias    aData     : std_logic_vector(DATA_LEFT downto 0) is Data;
    variable Result    : std_logic_vector(DATA_LEFT downto 0) := (others => '0');
  begin
    if DataWidth < Data'length then
      Result(DataWidth - 1 downto 0) := aData(DataWidth + ByteAddr * 8 - 1 downto ByteAddr * 8);
      return Result;
    else
      -- Make Bits to the Right of ByteAddr a 0
      Result(DATA_LEFT downto ByteAddr * 8) := aData(DATA_LEFT downto ByteAddr * 8);
      return Result;
    end if;
  end function AlignDataBusToBytes;

  ------------------------------------------------------------
  procedure CheckDataIsBytes (
  -- Check that DataWidth is byte oriented
  ------------------------------------------------------------
    constant ModelID        : in AlertLogIDType;
    constant DataWidth      : in integer;
    constant MessagePrefix  : in string  := "";
    constant TransferNumber : in integer := -1
  ) is
  begin
    if DataWidth mod 8 /= 0 then
      if TransferNumber > 0 then
        Alert(ModelID,
              MessagePrefix &
              "Data not on a byte boundary." &
              "  DataWidth: "      & to_string(DataWidth) &
              "  TransferNumber: " & to_string(TransferNumber),
              FAILURE);
      else
        Alert(ModelID,
              MessagePrefix &
              "Data not on a byte boundary." &
              "  DataWidth: " & to_string(DataWidth),
              FAILURE);
      end if;
    end if;
  end procedure CheckDataIsBytes;

  ------------------------------------------------------------
  procedure CheckDataWidth (
  -- Check AXI Write Data Width - BYTE and < WordWidth adjusted for ByteAddr
  ------------------------------------------------------------
    constant ModelID        : in AlertLogIDType;
    constant DataWidth      : in integer;
    constant ByteAddr       : in integer;
    constant MaxDataBits    : in integer;
    constant MessagePrefix  : in string  := "";
    constant TransferNumber : in integer := -1
  ) is
  begin
    if DataWidth + ByteAddr * 8 > MaxDataBits and DataWidth /= MaxDataBits then
      AlertIf(ModelID, DataWidth + ByteAddr * 8 > MaxDataBits,
              MessagePrefix & "Data length too large." &
              "  ByteAddr: "       & to_string(ByteAddr) & " * 8" &
              "  + DataWidth: "    & to_string(DataWidth) &
              "  > MaxDataBits: "  & to_string(MaxDataBits) &
              "  TransferNumber: " & to_string(TransferNumber),
              FAILURE);
    end if;
  end procedure CheckDataWidth;

  ------------------------------------------------------------
  -- Local
  procedure PopWriteBurstByteData (
  ------------------------------------------------------------
    constant WriteBurstFifo : in    osvvm.ScoreboardPkg_slv.ScoreboardIdType;
    variable WriteData      : inout std_logic_vector;
--!!    variable WriteStrb       : InOut std_logic_vector ;
    variable BytesToSend    : inout integer;
    constant ByteAddress    : in    integer := 0
  ) is
    constant DataLeft   : integer := WriteData'length - 1;
    alias    aWriteData : std_logic_vector(DataLeft downto 0) is WriteData;
--!!    alias aWriteStrb : std_logic_vector(WriteStrb'length-1 downto 0) is WriteStrb ;
    variable DataIndex  : integer := ByteAddress * 8;
    variable StrbIndex  : integer := ByteAddress;
  begin
    aWriteData := (others => 'U');
--!!    aWriteStrb := (others => '0') ;
    -- First Byte is put in right side of word
    PopByte : while DataIndex <= DataLeft loop
      aWriteData(DataIndex + 7 downto DataIndex) := Pop(WriteBurstFifo);
--!!      if aWriteData(DataIndex) /= 'U' then
--!!        aWriteStrb(StrbIndex) := '1' ;
--!!      end if ;
      BytesToSend := BytesToSend - 1;
      exit when BytesToSend = 0;
      DataIndex := DataIndex + 8;
      StrbIndex := StrbIndex + 1;
    end loop PopByte;
  end procedure PopWriteBurstByteData;

  ------------------------------------------------------------
  -- Local
  procedure PopWriteBurstWordData (
  ------------------------------------------------------------
    constant WriteBurstFifo : in    osvvm.ScoreboardPkg_slv.ScoreboardIdType;
    variable WriteData      : inout std_logic_vector;
--!!    variable WriteStrb       : InOut std_logic_vector ;
    constant ByteAddress    : in    integer := 0
  ) is
    alias    aWriteData : std_logic_vector(WriteData'length - 1 downto 0) is WriteData;
--!!    alias aWriteStrb : std_logic_vector(WriteStrb'length-1 downto 0) is WriteStrb ;
    variable DataIndex  : integer := 0;
  begin
    aWriteData := Pop(WriteBurstFifo);
--!!    aWriteStrb := (others => '0') ;

    for i in 0 to ByteAddress - 1 loop
      aWriteData(DataIndex + 7 downto DataIndex) := (others => 'U');
      DataIndex                                  := DataIndex + 8;
    end loop;

--!!    for i in ByteAddress to WriteStrb'length-1 loop
--!!      if aWriteData(DataIndex) /= 'U' then
--!!        aWriteStrb(i) := '1' ;
--!!      end if ;
--!!      DataIndex := DataIndex + 8 ;
--!!    end loop ;
  end procedure PopWriteBurstWordData;

  ------------------------------------------------------------
  procedure PopWriteBurstData (
  ------------------------------------------------------------
    constant WriteBurstFifo : in    osvvm.ScoreboardPkg_slv.ScoreboardIdType;
    constant BurstFifoMode  : in    AddressBusFifoBurstModeType;
    variable WriteData      : inout std_logic_vector;
--!!    variable WriteStrb       : InOut std_logic_vector ;
    variable BytesToSend    : inout integer;
    constant ByteAddress    : in    integer := 0
  ) is
  begin
    case BurstFifoMode is
      when ADDRESS_BUS_BURST_BYTE_MODE =>
--!!        PopWriteBurstByteData(WriteBurstFifo, WriteData, WriteStrb, BytesToSend, ByteAddress) ;
        PopWriteBurstByteData(WriteBurstFifo, WriteData, BytesToSend, ByteAddress);

      when ADDRESS_BUS_BURST_WORD_MODE =>
--!!        PopWriteBurstWordData(WriteBurstFifo, WriteData, WriteStrb, ByteAddress) ;
        PopWriteBurstWordData(WriteBurstFifo, WriteData, ByteAddress);

      when others =>
        -- Already checked, this should never happen
        Alert("PopWriteBurstData: BurstFifoMode Invalid Mode: " & to_string(BurstFifoMode), FAILURE);

    end case;
  end procedure PopWriteBurstData;

  ------------------------------------------------------------
  procedure PushReadBurstByteData (
  -- Push Burst Data into Byte Burst FIFO.
  ------------------------------------------------------------
    constant ReadBurstFifo  : in    osvvm.ScoreboardPkg_slv.ScoreboardIdType;
    variable ReadData       : inout std_logic_vector;
    variable BytesToReceive : inout integer;
    constant ByteAddress    : in    integer := 0
  ) is
    constant DataLeft  : integer := ReadData'length - 1;
    alias    aReadData : std_logic_vector(DataLeft downto 0) is ReadData;
    variable DataIndex : integer := ByteAddress * 8;
  begin
    -- First Byte is put in right side of word
    PushByte : while DataIndex <= DataLeft loop
      Push(ReadBurstFifo, aReadData(DataIndex + 7 downto DataIndex));
      BytesToReceive := BytesToReceive - 1;
      exit when BytesToReceive = 0;
      DataIndex      := DataIndex + 8;
    end loop PushByte;
  end procedure PushReadBurstByteData;

  ------------------------------------------------------------
  procedure PushReadBurstData (
  -- Push Burst Data into Byte Burst FIFO.
  ------------------------------------------------------------
    constant ReadBurstFifo  : in    osvvm.ScoreboardPkg_slv.ScoreboardIdType;
    constant BurstFifoMode  : in    AddressBusFifoBurstModeType;
    variable ReadData       : inout std_logic_vector;
    variable BytesToReceive : inout integer;
    constant ByteAddress    : in    integer := 0
  ) is
  begin
    case BurstFifoMode is
      when ADDRESS_BUS_BURST_BYTE_MODE =>
        PushReadBurstByteData(ReadBurstFifo, ReadData, BytesToReceive, ByteAddress);

      when ADDRESS_BUS_BURST_WORD_MODE =>
        Push(ReadBurstFifo, ReadData);

      when others =>
        -- Already checked, this should never happen
        Alert("PushReadBurstData: BurstFifoMode Invalid Mode: " & to_string(BurstFifoMode), FAILURE);
    end case;
  end procedure PushReadBurstData;

end package body ApbModelPkg;
