--
--  Original Author:  Kartik Desai
--
--  Description:
--      APB Requester phase procedures, Completer procedures and the transfer
--      types. The verification components are built on them, and a testbench
--      process can call them directly.
--
--  Notes:
--      Timing: outputs are driven tpd after a rising edge of Clk,
--      inputs are sampled at a rising edge. Every procedure that starts a phase must
--      be called just after a rising edge.
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

library osvvm;
context osvvm.OsvvmContext;

use work.ApbSettingsPkg.all;
use work.ApbInterfacePkg.all;

package ApbProtocolPkg is

  type ApbStatusType is (
    APB_OK,       -- completed, PSLVERR = 0
    APB_SLVERR,   -- completed, PSLVERR = 1 (IHI0024E 3.4)
    APB_TIMEOUT,  -- Requester: more than ReadyTimeOut wait states; transfer abandoned
    APB_ABORTED   -- ended by reset or by the Requester dropping PSEL
  );

  type ApbTimingType is record
    -- Requester outputs
    PSel    : time;
    PEnable : time;
    PAddr   : time;
    PWrite  : time;
    PWData  : time;
    PProt   : time;
    PStrb   : time;
    -- Completer outputs
    PRData  : time;
    PReady  : time;
    PSlvErr : time;
  end record ApbTimingType;

  function ApbTiming (Delay : time := APB_DEFAULT_DELAY) return ApbTimingType;

  type ApbProcConfigType is record
    Revision         : ApbRevisionType;
    Timing           : ApbTimingType;
    ReadyTimeOut     : natural;         -- Requester: maximum wait states accepted, 0 = no limit
    SlvErrAlert      : boolean;         -- Requester: alert when PSLVERR = 1
    SlvErrAlertLevel : AlertType;
    ReadDataXCheck   : boolean;         -- Requester: PRDATA must be valid at read completion
  end record ApbProcConfigType;

  function ApbProcConfig return ApbProcConfigType;

  -- One completed or observed transfer
  type ApbTransferType is record
    Addr       : std_logic_vector;
    Write      : std_logic;
    WData      : std_logic_vector;
    RData      : std_logic_vector;
    Strb       : std_logic_vector;              -- APB3: all ones
    Prot       : std_logic_vector(2 downto 0);  -- APB3: "000"
    SlvErr     : std_logic;
    WaitStates : natural;
  end record ApbTransferType;

  function to_string (Transfer : ApbTransferType) return string;

  -- Expected transfer for a scoreboard check. Data is PWDATA for a write, PRDATA for a read.
  function ApbTransfer (
    Addr   : std_logic_vector;
    Write  : std_logic;
    Data   : std_logic_vector;
    SlvErr : std_logic := '0'
  ) return ApbTransferType;

  -- Scoreboard match: PADDR, PWRITE, the data of that direction and PSLVERR, with MetaMatch
  -- ('-' matches anything). WaitStates, Strb and Prot are not compared.
  function Match (Actual, Expected : ApbTransferType) return boolean;

  -- Valid: to_X01 gives '0' or '1' ('0', '1', 'L', 'H')
  function IsValid (A : std_logic) return boolean;
  function IsValid (A : std_logic_vector) return boolean;

  ------------------------------------------------------------
  -- Requester: phase procedures
  ------------------------------------------------------------
  -- IDLE: PSEL = 0, PENABLE = 0, other outputs 0 (IHI0024E App. A.1)
  procedure ApbRequesterIdle (
    signal   Req    : inout ApbRequesterRecType;
    constant Config : in    ApbProcConfigType
  );

  -- Drive SETUP and return at the next rising edge
  procedure ApbSetupPhase (
    signal   Clk        : in    std_logic;
    signal   Req        : inout ApbRequesterRecType;
    constant Config     : in    ApbProcConfigType;
    constant Addr       : in    std_logic_vector;
    constant Write      : in    std_logic;
    constant WData      : in    std_logic_vector;
    constant AlertLogID : in    AlertLogIDType := ALERTLOG_DEFAULT_ID
  );

  -- Drive ACCESS and return at the completion edge, with ACCESS still driven.
  -- The caller then calls ApbSetupPhase (back-to-back) or ApbRequesterIdle.
  -- After APB_TIMEOUT or APB_ABORTED the caller must drive IDLE for at least one
  -- cycle before the next SETUP, so the Completer can see the transfer end.
  procedure ApbAccessPhase (
    signal   Clk               : in    std_logic;
    signal   nReset            : in    std_logic;
    signal   Req               : inout ApbRequesterRecType;
    signal   Cmp               : in    ApbCompleterRecType;
    constant Config            : in    ApbProcConfigType;
    variable RData             : out   std_logic_vector;
    variable WaitStates        : out   natural;
    variable Status            : out   ApbStatusType;
    constant AlertLogID        : in    AlertLogIDType := ALERTLOG_DEFAULT_ID;
    -- Timeout FAILURE goes here; ALERTLOG_ID_NOT_ASSIGNED means AlertLogID
    constant TimeOutAlertLogID : in    AlertLogIDType := ALERTLOG_ID_NOT_ASSIGNED
  );

  ------------------------------------------------------------
  -- Completer
  ------------------------------------------------------------
  -- PREADY = 0, PRDATA = 0, PSLVERR = 0 (IHI0024E App. A.1, 3.4)
  procedure ApbCompleterIdle (
    signal   Cmp    : inout ApbCompleterRecType;
    constant Config : in    ApbProcConfigType
  );

  -- Return at the rising edge that samples SETUP (PSEL = 1, PENABLE = 0)
  procedure ApbWaitForTransfer (
    signal   Clk        : in    std_logic;
    signal   nReset     : in    std_logic;
    signal   Req        : in    ApbRequesterRecType;
    constant Config     : in    ApbProcConfigType;
    variable Transfer   : inout ApbTransferType;
    constant AlertLogID : in    AlertLogIDType := ALERTLOG_DEFAULT_ID
  );

  -- Called at the edge that sampled SETUP. Returns at the completion edge with the
  -- Completer outputs back at idle.
  procedure ApbRespond (
    signal   Clk        : in    std_logic;
    signal   nReset     : in    std_logic;
    signal   Req        : in    ApbRequesterRecType;
    signal   Cmp        : inout ApbCompleterRecType;
    constant Config     : in    ApbProcConfigType;
    constant WaitStates : in    natural;
    constant RData      : in    std_logic_vector;
    constant SlvErr     : in    std_logic;
    variable Status     : out   ApbStatusType;
    constant AlertLogID : in    AlertLogIDType := ALERTLOG_DEFAULT_ID
  );

end package ApbProtocolPkg;

package body ApbProtocolPkg is

  ------------------------------------------------------------
  function ApbTiming (Delay : time := APB_DEFAULT_DELAY) return ApbTimingType is
  ------------------------------------------------------------
  begin
    return (others => Delay);
  end function ApbTiming;

  ------------------------------------------------------------
  function ApbProcConfig return ApbProcConfigType is
  ------------------------------------------------------------
  begin
    return (
      Revision         => APB3,
      Timing           => ApbTiming(APB_DEFAULT_DELAY),
      ReadyTimeOut     => APB_DEFAULT_PREADY_TIME_OUT,
      SlvErrAlert      => TRUE,
      SlvErrAlertLevel => APB_DEFAULT_PSLVERR_ALERT_LEVEL,
      ReadDataXCheck   => APB_DEFAULT_PRDATA_X_CHECK
    );
  end function ApbProcConfig;

  ------------------------------------------------------------
  function to_string (Transfer : ApbTransferType) return string is
  ------------------------------------------------------------
  begin
    if Transfer.Write = '1' then
      return "Write  PADDR: " & to_hxstring(Transfer.Addr) &
             "  PWDATA: "     & to_hxstring(Transfer.WData) &
             "  PSLVERR: "    & to_string(Transfer.SlvErr) &
             "  WaitStates: " & to_string(Transfer.WaitStates);
    else
      return "Read  PADDR: "  & to_hxstring(Transfer.Addr) &
             "  PRDATA: "     & to_hxstring(Transfer.RData) &
             "  PSLVERR: "    & to_string(Transfer.SlvErr) &
             "  WaitStates: " & to_string(Transfer.WaitStates);
    end if;
  end function to_string;

  ------------------------------------------------------------
  function ApbTransfer (
  ------------------------------------------------------------
    Addr   : std_logic_vector;
    Write  : std_logic;
    Data   : std_logic_vector;
    SlvErr : std_logic := '0'
  ) return ApbTransferType is
    constant ZERO_DATA : std_logic_vector(Data'length - 1 downto 0) := (others => '0');
  begin
    return (
      Addr       => Addr,
      Write      => Write,
      WData      => IfElse(Write = '1', Data, ZERO_DATA),
      RData      => IfElse(Write = '1', ZERO_DATA, Data),
      Strb       => (Data'length / 8 - 1 downto 0 => '1'),
      Prot       => "000",
      SlvErr     => SlvErr,
      WaitStates => 0
    );
  end function ApbTransfer;

  ------------------------------------------------------------
  function Match (Actual, Expected : ApbTransferType) return boolean is
  ------------------------------------------------------------
  begin
    if not (MetaMatch(Actual.Addr, Expected.Addr) and MetaMatch(Actual.Write, Expected.Write) and
            MetaMatch(Actual.SlvErr, Expected.SlvErr)) then
      return FALSE;
    elsif to_X01(Expected.Write) = '1' then
      return MetaMatch(Actual.WData, Expected.WData);
    else
      return MetaMatch(Actual.RData, Expected.RData);
    end if;
  end function Match;

  ------------------------------------------------------------
  function IsValid (A : std_logic) return boolean is
  ------------------------------------------------------------
  begin
    return to_X01(A) /= 'X';
  end function IsValid;

  ------------------------------------------------------------
  function IsValid (A : std_logic_vector) return boolean is
  ------------------------------------------------------------
  begin
    return not is_X(A);
  end function IsValid;

  ------------------------------------------------------------
  -- Local: APB3 has no PPROT and PSTRB (IHI0024E Table B-1), so they are not driven
  procedure DriveProtStrb (
  ------------------------------------------------------------
    signal   Req    : inout ApbRequesterRecType;
    constant Config : in    ApbProcConfigType;
    constant Write  : in    std_logic
  ) is
  begin
    if Config.Revision = APB3 then
      Req.PProt <= (Req.PProt'range => 'Z');
      Req.PStrb <= (Req.PStrb'range => 'Z');
    else
      -- APB4 (not yet supported): PPROT and PSTRB from the transfer. PSTRB is LOW for reads (3.2)
      Req.PProt <= (Req.PProt'range => '0')   after Config.Timing.PProt;
      Req.PStrb <= (Req.PStrb'range => Write) after Config.Timing.PStrb;
    end if;
  end procedure DriveProtStrb;

  ------------------------------------------------------------
  procedure ApbRequesterIdle (
  ------------------------------------------------------------
    signal   Req    : inout ApbRequesterRecType;
    constant Config : in    ApbProcConfigType
  ) is
  begin
    Req.PSel    <= '0' after Config.Timing.PSel;
    Req.PEnable <= '0' after Config.Timing.PEnable;
    Req.PAddr   <= (Req.PAddr'range => '0') after Config.Timing.PAddr;
    Req.PWrite  <= '0' after Config.Timing.PWrite;
    Req.PWData  <= (Req.PWData'range => '0') after Config.Timing.PWData;
    DriveProtStrb(Req, Config, '0');
  end procedure ApbRequesterIdle;

  ------------------------------------------------------------
  procedure ApbSetupPhase (
  ------------------------------------------------------------
    signal   Clk        : in    std_logic;
    signal   Req        : inout ApbRequesterRecType;
    constant Config     : in    ApbProcConfigType;
    constant Addr       : in    std_logic_vector;
    constant Write      : in    std_logic;
    constant WData      : in    std_logic_vector;
    constant AlertLogID : in    AlertLogIDType := ALERTLOG_DEFAULT_ID
  ) is
  begin
    -- SETUP: PSEL = 1, PENABLE = 0 (IHI0024E 4.1). PADDR, PWRITE and PWDATA valid (3.1.1)
    Req.PSel    <= '1' after Config.Timing.PSel;
    Req.PEnable <= '0' after Config.Timing.PEnable;
    Req.PAddr   <= SafeResize(AlertLogID, Addr, Req.PAddr'length) after Config.Timing.PAddr;
    Req.PWrite  <= Write after Config.Timing.PWrite;
    if Write = '1' then
      Req.PWData <= SafeResize(AlertLogID, WData, Req.PWData'length) after Config.Timing.PWData;
    else
      -- PWDATA is not required to be valid for reads: drive 0 (App. A.1)
      Req.PWData <= (Req.PWData'range => '0') after Config.Timing.PWData;
    end if;
    DriveProtStrb(Req, Config, Write);

    -- SETUP lasts exactly one cycle (4.1, APB3-R01)
    wait until rising_edge(Clk);
  end procedure ApbSetupPhase;

  ------------------------------------------------------------
  procedure ApbAccessPhase (
  ------------------------------------------------------------
    signal   Clk               : in    std_logic;
    signal   nReset            : in    std_logic;
    signal   Req               : inout ApbRequesterRecType;
    signal   Cmp               : in    ApbCompleterRecType;
    constant Config            : in    ApbProcConfigType;
    variable RData             : out   std_logic_vector;
    variable WaitStates        : out   natural;
    variable Status            : out   ApbStatusType;
    constant AlertLogID        : in    AlertLogIDType := ALERTLOG_DEFAULT_ID;
    -- Timeout FAILURE goes here; ALERTLOG_ID_NOT_ASSIGNED means AlertLogID
    constant TimeOutAlertLogID : in    AlertLogIDType := ALERTLOG_ID_NOT_ASSIGNED
  ) is
    variable vWaitStates   : natural := 0;
    variable ReadyReported : boolean := FALSE;
    variable IsRead        : boolean;
  begin
    IsRead := to_X01(Req.PWrite) = '0';
    RData  := (RData'range => '0');

    -- ACCESS: PENABLE = 1. PADDR, PWRITE and PWDATA stay unchanged (4.1, APB3-R05 to R07)
    Req.PEnable <= '1' after Config.Timing.PEnable;

    loop
      wait until rising_edge(Clk);

      if to_X01(nReset) = '0' then
        Alert(AlertLogID, "APB transfer aborted by reset.  PADDR: " & to_hxstring(Req.PAddr), WARNING);
        WaitStates := vWaitStates;
        Status     := APB_ABORTED;
        return;
      end if;

      -- PREADY must be valid when PSEL and PENABLE are HIGH (App. A.1, APB3-V06)
      case to_X01(Cmp.PReady) is
        when '1' =>
          exit;
        when '0' =>
          null;
        when others =>
          if not ReadyReported then
            Alert(AlertLogID, "APB3-V06: PREADY not valid in ACCESS: " & to_string(Cmp.PReady) &
                  "  PADDR: " & to_hxstring(Req.PAddr), ERROR);
            ReadyReported := TRUE;
          end if;
      end case;

      vWaitStates := vWaitStates + 1;
      if Config.ReadyTimeOut > 0 and vWaitStates > Config.ReadyTimeOut then
        Alert(IfElse(TimeOutAlertLogID /= ALERTLOG_ID_NOT_ASSIGNED, TimeOutAlertLogID, AlertLogID),
              "PREADY timeout: no PREADY after " & to_string(Config.ReadyTimeOut) &
              " wait states.  PADDR: "           & to_hxstring(Req.PAddr), FAILURE);
        WaitStates := vWaitStates;
        Status     := APB_TIMEOUT;
        return;
      end if;
    end loop;

    -- Completion: PSLVERR valid (App. A.1, APB3-V07)
    WaitStates := vWaitStates;
    if not IsValid(Cmp.PSlvErr) then
      Alert(AlertLogID, "APB3-V07: PSLVERR not valid at completion: " & to_string(Cmp.PSlvErr) &
            "  PADDR: " & to_hxstring(Req.PAddr), ERROR);
    end if;

    if IsRead then
      -- PRDATA valid at read completion, also with PSLVERR = 1 (App. A.1, APB3-V08)
      if Config.ReadDataXCheck and not IsValid(Cmp.PRData) then
        Alert(AlertLogID, "APB3-V08: PRDATA not valid at read completion: " & to_hxstring(Cmp.PRData) &
              "  PADDR: " & to_hxstring(Req.PAddr), ERROR);
      end if;
      RData := SafeResize(AlertLogID, Cmp.PRData, RData'length);
    end if;

    if to_X01(Cmp.PSlvErr) = '1' then
      Status := APB_SLVERR;
      if Config.SlvErrAlert then
        Alert(AlertLogID, "PSLVERR = 1 (transfer error).  PADDR: " & to_hxstring(Req.PAddr), Config.SlvErrAlertLevel);
      end if;
    else
      Status := APB_OK;
    end if;
  end procedure ApbAccessPhase;

  ------------------------------------------------------------
  procedure ApbCompleterIdle (
  ------------------------------------------------------------
    signal   Cmp    : inout ApbCompleterRecType;
    constant Config : in    ApbProcConfigType
  ) is
  begin
    Cmp.PReady  <= '0' after Config.Timing.PReady;
    Cmp.PRData  <= (Cmp.PRData'range => '0') after Config.Timing.PRData;
    Cmp.PSlvErr <= '0' after Config.Timing.PSlvErr;
  end procedure ApbCompleterIdle;

  ------------------------------------------------------------
  procedure ApbWaitForTransfer (
  ------------------------------------------------------------
    signal   Clk        : in    std_logic;
    signal   nReset     : in    std_logic;
    signal   Req        : in    ApbRequesterRecType;
    constant Config     : in    ApbProcConfigType;
    variable Transfer   : inout ApbTransferType;
    constant AlertLogID : in    AlertLogIDType := ALERTLOG_DEFAULT_ID
  ) is
  begin
    -- SETUP is sampled at the rising edge that ends it (IHI0024E 4.1)
    loop
      wait until rising_edge(Clk);
      exit when to_X01(nReset) = '1' and to_X01(Req.PSel) = '1' and to_X01(Req.PEnable) = '0';
    end loop;

    -- PADDR and PWRITE valid when PSEL is HIGH (App. A.1, APB3-V02, V04)
    if not IsValid(Req.PAddr) then
      Alert(AlertLogID, "APB3-V02: PADDR not valid in SETUP: " & to_hxstring(Req.PAddr), ERROR);
    end if;
    if not IsValid(Req.PWrite) then
      Alert(AlertLogID, "APB3-V04: PWRITE not valid in SETUP: " & to_string(Req.PWrite), ERROR);
    end if;

    Transfer.Addr       := SafeResize(AlertLogID, Req.PAddr, Transfer.Addr'length);
    Transfer.Write      := to_X01(Req.PWrite);
    Transfer.RData      := (Transfer.RData'range => '0');
    Transfer.SlvErr     := '0';
    Transfer.WaitStates := 0;

    if Transfer.Write = '1' then
      -- PWDATA valid for writes (App. A.1, APB3-V05). APB3: all byte lanes are active
      if not IsValid(Req.PWData) then
        Alert(AlertLogID, "APB3-V05: PWDATA not valid in SETUP of a write: " & to_hxstring(Req.PWData), ERROR);
      end if;
      Transfer.WData := SafeResize(AlertLogID, Req.PWData, Transfer.WData'length);
    else
      Transfer.WData := (Transfer.WData'range => '0');
    end if;

    if Config.Revision = APB3 then
      Transfer.Strb := (Transfer.Strb'range => '1');
      Transfer.Prot := "000";
    else
      Transfer.Strb := SafeResize(AlertLogID, Req.PStrb, Transfer.Strb'length);
      Transfer.Prot := Req.PProt;
    end if;
  end procedure ApbWaitForTransfer;

  ------------------------------------------------------------
  procedure ApbRespond (
  ------------------------------------------------------------
    signal   Clk        : in    std_logic;
    signal   nReset     : in    std_logic;
    signal   Req        : in    ApbRequesterRecType;
    signal   Cmp        : inout ApbCompleterRecType;
    constant Config     : in    ApbProcConfigType;
    constant WaitStates : in    natural;
    constant RData      : in    std_logic_vector;
    constant SlvErr     : in    std_logic;
    variable Status     : out   ApbStatusType;
    constant AlertLogID : in    AlertLogIDType := ALERTLOG_DEFAULT_ID
  ) is
    constant IsRead : boolean := to_X01(Req.PWrite) = '0';

    -- The Requester left ACCESS before completion (reset, PSEL LOW, or PENABLE LOW)
    impure function Aborted return boolean is
    begin
      return to_X01(nReset) = '0' or to_X01(Req.PSel) /= '1' or to_X01(Req.PEnable) /= '1';
    end function Aborted;
  begin
    -- Wait states: PREADY LOW in ACCESS extends the transfer (IHI0024E 3.1.2, 3.3.2)
    if WaitStates > 0 then
      ApbCompleterIdle(Cmp, Config);
      for i in 1 to WaitStates loop
        wait until rising_edge(Clk);
        if Aborted then
          Alert(AlertLogID, "APB transfer aborted by the Requester or by reset during wait states", WARNING);
          ApbCompleterIdle(Cmp, Config);
          Status := APB_ABORTED;
          return;
        end if;
      end loop;
    end if;

    -- Completing cycle. PSLVERR and PRDATA only here (3.4 recommendation, App. A.1)
    Cmp.PReady  <= '1' after Config.Timing.PReady;
    Cmp.PSlvErr <= SlvErr after Config.Timing.PSlvErr;
    if IsRead then
      Cmp.PRData <= SafeResize(AlertLogID, RData, Cmp.PRData'length) after Config.Timing.PRData;
    else
      Cmp.PRData <= (Cmp.PRData'range => '0') after Config.Timing.PRData;
    end if;

    wait until rising_edge(Clk);
    ApbCompleterIdle(Cmp, Config);

    if Aborted then
      Alert(AlertLogID, "APB transfer aborted by the Requester or by reset in the completing cycle", WARNING);
      Status := APB_ABORTED;
    elsif to_X01(SlvErr) = '1' then
      Status := APB_SLVERR;
    else
      Status := APB_OK;
    end if;
  end procedure ApbRespond;

end package body ApbProtocolPkg;
