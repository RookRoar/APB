--
--  Original Author:  Kartik Desai
--
--  Description:
--      APB model options: ApbOptionsType, SetApbOptions / GetApbOptions, and the
--      parameter store of the verification components
--
--  Notes:
--      Same pattern as OSVVM Axi4OptionsPkg, in its VHDL-2008 form. Options before
--      OPTIONS_MARKER are parameters, stored directly in the VC's Params singleton.
--      Options after OPTIONS_MARKER are interface defaults, sent to the VC with
--      SET_MODEL_OPTIONS / GET_MODEL_OPTIONS.
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

library osvvm;
context osvvm.OsvvmContext;

library osvvm_common;
context osvvm_common.OsvvmCommonContext;

use work.ApbSettingsPkg.all;

package ApbOptionsPkg is

  type ApbUnresolvedOptionsType is (
    --
    -- Parameters: stored in Params
    --
    -- Requester
    PREADY_TIME_OUT,                    -- integer: maximum wait states accepted, 0 = no limit
    TRANSFER_IDLE_CYCLES,               -- integer: IDLE cycles before each transfer
    PSLVERR_ALERT_LEVEL,                -- AlertType: level of the alert on an unexpected PSLVERR
    PRDATA_X_CHECK,                     -- boolean: check PRDATA validity at read completion
    -- Completer and CompleterMemory
    WAIT_STATES,                        -- integer: minimum PREADY-low cycles
    PSLVERR_INJECT_MODE,                -- ApbErrorInjectType
    PSLVERR_INJECT_N,                   -- integer: INJECT_EVERY_NTH
    PSLVERR_INJECT_PERCENT,             -- integer 0 to 100: INJECT_PERCENT
    PSLVERR_INJECT_ADDR_LOW,            -- std_logic_vector byte address: INJECT_ADDRESS_RANGE, inclusive
    PSLVERR_INJECT_ADDR_HIGH,           -- std_logic_vector byte address: INJECT_ADDRESS_RANGE, inclusive
    -- CompleterMemory
    ERROR_READ_DATA,                    -- ApbErrorReadDataType
    ERROR_WRITE_UPDATES,                -- boolean
    -- APB5 parameters: insert here
    --
    OPTIONS_MARKER,
    --
    -- Interface defaults: sent to the VC
    --
    PSLVERR,                            -- std_logic. Requester: expected value ('-' = don't care).
                                        --            Completer: value returned.
    PPROT,                              -- APB4, reserved
    PSTRB,                              -- APB4, reserved
    -- APB5 interface defaults: insert here
    THE_END
  );
  type ApbUnresolvedOptionsVectorType is array (natural range <>) of ApbUnresolvedOptionsType;
  function resolved_max (A : ApbUnresolvedOptionsVectorType) return ApbUnresolvedOptionsType;
  subtype ApbOptionsType is resolved_max ApbUnresolvedOptionsType;

  type ApbErrorInjectType   is (INJECT_NONE, INJECT_EVERY_NTH, INJECT_PERCENT, INJECT_ADDRESS_RANGE);
  type ApbErrorReadDataType is (ERROR_DATA_MEMORY, ERROR_DATA_ZERO);

  ------------------------------------------------------------
  -- Test API
  procedure SetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; constant OptVal : in boolean);
  procedure SetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; constant OptVal : in std_logic);
  procedure SetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; constant OptVal : in integer);
  procedure SetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; constant OptVal : in std_logic_vector);
  procedure SetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; constant OptVal : in AlertType);
  procedure SetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; constant OptVal : in ApbErrorInjectType);
  procedure SetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; constant OptVal : in ApbErrorReadDataType);

  procedure GetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; variable OptVal : out boolean);
  procedure GetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; variable OptVal : out std_logic);
  procedure GetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; variable OptVal : out integer);
  procedure GetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; variable OptVal : out std_logic_vector);
  procedure GetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; variable OptVal : out AlertType);
  procedure GetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; variable OptVal : out ApbErrorInjectType);
  procedure GetApbOptions (signal TransactionRec : inout AddressBusRecType; constant Option : in ApbOptionsType; variable OptVal : out ApbErrorReadDataType);

  alias SetModelOptions is SetApbOptions[AddressBusRecType, ApbOptionsType, boolean];
  alias SetModelOptions is SetApbOptions[AddressBusRecType, ApbOptionsType, std_logic];
  alias SetModelOptions is SetApbOptions[AddressBusRecType, ApbOptionsType, integer];
  alias SetModelOptions is SetApbOptions[AddressBusRecType, ApbOptionsType, std_logic_vector];
  alias SetModelOptions is SetApbOptions[AddressBusRecType, ApbOptionsType, AlertType];
  alias SetModelOptions is SetApbOptions[AddressBusRecType, ApbOptionsType, ApbErrorInjectType];
  alias SetModelOptions is SetApbOptions[AddressBusRecType, ApbOptionsType, ApbErrorReadDataType];

  alias GetModelOptions is GetApbOptions[AddressBusRecType, ApbOptionsType, boolean];
  alias GetModelOptions is GetApbOptions[AddressBusRecType, ApbOptionsType, std_logic];
  alias GetModelOptions is GetApbOptions[AddressBusRecType, ApbOptionsType, integer];
  alias GetModelOptions is GetApbOptions[AddressBusRecType, ApbOptionsType, std_logic_vector];
  alias GetModelOptions is GetApbOptions[AddressBusRecType, ApbOptionsType, AlertType];
  alias GetModelOptions is GetApbOptions[AddressBusRecType, ApbOptionsType, ApbErrorInjectType];
  alias GetModelOptions is GetApbOptions[AddressBusRecType, ApbOptionsType, ApbErrorReadDataType];

  ------------------------------------------------------------
  -- VC support
  function to_integer (Option : ApbOptionsType) return integer;
  function IsApbParameter (Option : ApbOptionsType) return boolean;

  -- Create the Params singleton for a VC and load the defaults from ApbSettingsPkg
  impure function NewApbParams (Name : string; ParentID : AlertLogIDType) return ModelParametersIDType;

  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return integer;
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return boolean;
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return AlertType;
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return ApbErrorInjectType;
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return ApbErrorReadDataType;
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return std_logic_vector;

  -- Completer error injection: Inject is TRUE when the PSLVERR_INJECT_* parameters
  -- select this transfer for PSLVERR = 1. NthCount and RV belong to the calling VC.
  procedure ApbErrorInjection (
    constant Params   : in    ModelParametersIDType;
    constant Addr     : in    std_logic_vector;
    variable NthCount : inout natural;
    variable RV       : inout RandomPType;
    variable Inject   : out   boolean
  );

end package ApbOptionsPkg;

package body ApbOptionsPkg is

  ------------------------------------------------------------
  function resolved_max (A : ApbUnresolvedOptionsVectorType) return ApbUnresolvedOptionsType is
  ------------------------------------------------------------
  begin
    return maximum(A);
  end function resolved_max;

  ------------------------------------------------------------
  function to_integer (Option : ApbOptionsType) return integer is
  ------------------------------------------------------------
  begin
    return ApbOptionsType'pos(Option);
  end function to_integer;

  ------------------------------------------------------------
  function IsApbParameter (Option : ApbOptionsType) return boolean is
  ------------------------------------------------------------
  begin
    return Option < OPTIONS_MARKER;
  end function IsApbParameter;

  ------------------------------------------------------------
  procedure SetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    constant OptVal         : in    integer
  ) is
  begin
    if IsApbParameter(Option) then
      Set(TransactionRec.Params, to_integer(Option), OptVal);
    else
      SetModelOptions(TransactionRec, to_integer(Option), OptVal);
    end if;
  end procedure SetApbOptions;

  ------------------------------------------------------------
  procedure SetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    constant OptVal         : in    boolean
  ) is
  begin
    if IsApbParameter(Option) then
      Set(TransactionRec.Params, to_integer(Option), OptVal);
    else
      SetModelOptions(TransactionRec, to_integer(Option), boolean'pos(OptVal));
    end if;
  end procedure SetApbOptions;

  ------------------------------------------------------------
  procedure SetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    constant OptVal         : in    std_logic
  ) is
  begin
    SetApbOptions(TransactionRec, Option, std_ulogic'pos(OptVal));
  end procedure SetApbOptions;

  ------------------------------------------------------------
  procedure SetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    constant OptVal         : in    std_logic_vector
  ) is
  begin
    if IsApbParameter(Option) then
      Set(TransactionRec.Params, to_integer(Option), OptVal);
    else
      SetModelOptions(TransactionRec, to_integer(Option), OptVal);
    end if;
  end procedure SetApbOptions;

  ------------------------------------------------------------
  procedure SetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    constant OptVal         : in    AlertType
  ) is
  begin
    SetApbOptions(TransactionRec, Option, AlertType'pos(OptVal));
  end procedure SetApbOptions;

  ------------------------------------------------------------
  procedure SetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    constant OptVal         : in    ApbErrorInjectType
  ) is
  begin
    SetApbOptions(TransactionRec, Option, ApbErrorInjectType'pos(OptVal));
  end procedure SetApbOptions;

  ------------------------------------------------------------
  procedure SetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    constant OptVal         : in    ApbErrorReadDataType
  ) is
  begin
    SetApbOptions(TransactionRec, Option, ApbErrorReadDataType'pos(OptVal));
  end procedure SetApbOptions;

  ------------------------------------------------------------
  procedure GetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    variable OptVal         : out   integer
  ) is
  begin
    if IsApbParameter(Option) then
      OptVal := Get(TransactionRec.Params, to_integer(Option));
    else
      GetModelOptions(TransactionRec, to_integer(Option), OptVal);
    end if;
  end procedure GetApbOptions;

  ------------------------------------------------------------
  procedure GetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    variable OptVal         : out   boolean
  ) is
    variable IntOptVal : integer;
  begin
    if IsApbParameter(Option) then
      OptVal := Get(TransactionRec.Params, to_integer(Option));
    else
      GetModelOptions(TransactionRec, to_integer(Option), IntOptVal);
      OptVal := IntOptVal >= 1;
    end if;
  end procedure GetApbOptions;

  ------------------------------------------------------------
  procedure GetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    variable OptVal         : out   std_logic
  ) is
    variable IntOptVal : integer;
  begin
    GetApbOptions(TransactionRec, Option, IntOptVal);
    OptVal := std_logic'val(IntOptVal);
  end procedure GetApbOptions;

  ------------------------------------------------------------
  procedure GetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    variable OptVal         : out   std_logic_vector
  ) is
  begin
    if IsApbParameter(Option) then
      OptVal := Get(TransactionRec.Params, to_integer(Option));
    else
      GetModelOptions(TransactionRec, to_integer(Option), OptVal);
    end if;
  end procedure GetApbOptions;

  ------------------------------------------------------------
  procedure GetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    variable OptVal         : out   AlertType
  ) is
    variable IntOptVal : integer;
  begin
    GetApbOptions(TransactionRec, Option, IntOptVal);
    OptVal := AlertType'val(IntOptVal);
  end procedure GetApbOptions;

  ------------------------------------------------------------
  procedure GetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    variable OptVal         : out   ApbErrorInjectType
  ) is
    variable IntOptVal : integer;
  begin
    GetApbOptions(TransactionRec, Option, IntOptVal);
    OptVal := ApbErrorInjectType'val(IntOptVal);
  end procedure GetApbOptions;

  ------------------------------------------------------------
  procedure GetApbOptions (
  ------------------------------------------------------------
    signal   TransactionRec : inout AddressBusRecType;
    constant Option         : in    ApbOptionsType;
    variable OptVal         : out   ApbErrorReadDataType
  ) is
    variable IntOptVal : integer;
  begin
    GetApbOptions(TransactionRec, Option, IntOptVal);
    OptVal := ApbErrorReadDataType'val(IntOptVal);
  end procedure GetApbOptions;

  ------------------------------------------------------------
  -- Local: load the defaults from ApbSettingsPkg
  procedure InitApbOptions (constant Params : in ModelParametersIDType) is
  ------------------------------------------------------------
  begin
    -- Requester
    Set(Params, to_integer(PREADY_TIME_OUT),          APB_DEFAULT_PREADY_TIME_OUT);
    Set(Params, to_integer(TRANSFER_IDLE_CYCLES),     APB_DEFAULT_TRANSFER_IDLE_CYCLES);
    Set(Params, to_integer(PSLVERR_ALERT_LEVEL),      AlertType'pos(APB_DEFAULT_PSLVERR_ALERT_LEVEL));
    Set(Params, to_integer(PRDATA_X_CHECK),           APB_DEFAULT_PRDATA_X_CHECK);
    -- Completer and CompleterMemory
    Set(Params, to_integer(WAIT_STATES),              APB_DEFAULT_WAIT_STATES);
    Set(Params, to_integer(PSLVERR_INJECT_MODE),      ApbErrorInjectType'pos(INJECT_NONE));
    Set(Params, to_integer(PSLVERR_INJECT_N),         1);
    Set(Params, to_integer(PSLVERR_INJECT_PERCENT),   0);
    -- First Set fixes the slot type: 32-bit vectors hold any legal PADDR (APB3-S01)
    Set(Params, to_integer(PSLVERR_INJECT_ADDR_LOW),  std_logic_vector'(31 downto 0 => '0'));
    Set(Params, to_integer(PSLVERR_INJECT_ADDR_HIGH), std_logic_vector'(31 downto 0 => '0'));
    -- CompleterMemory
    Set(Params, to_integer(ERROR_READ_DATA),          ApbErrorReadDataType'pos(ERROR_DATA_MEMORY));
    Set(Params, to_integer(ERROR_WRITE_UPDATES),      FALSE);
  end procedure InitApbOptions;

  ------------------------------------------------------------
  impure function NewApbParams (Name : string; ParentID : AlertLogIDType) return ModelParametersIDType is
  ------------------------------------------------------------
    variable Params : ModelParametersIDType;
  begin
    Params := NewID(Name, to_integer(OPTIONS_MARKER), ParentID);
    InitApbOptions(Params);
    return Params;
  end function NewApbParams;

  ------------------------------------------------------------
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return integer is
  ------------------------------------------------------------
  begin
    return Get(Params, to_integer(Option));
  end function GetApbParameter;

  ------------------------------------------------------------
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return boolean is
  ------------------------------------------------------------
  begin
    return Get(Params, to_integer(Option));
  end function GetApbParameter;

  ------------------------------------------------------------
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return AlertType is
  ------------------------------------------------------------
    constant IntVal : integer := Get(Params, to_integer(Option));
  begin
    return AlertType'val(IntVal);
  end function GetApbParameter;

  ------------------------------------------------------------
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return ApbErrorInjectType is
  ------------------------------------------------------------
    constant IntVal : integer := Get(Params, to_integer(Option));
  begin
    return ApbErrorInjectType'val(IntVal);
  end function GetApbParameter;

  ------------------------------------------------------------
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return ApbErrorReadDataType is
  ------------------------------------------------------------
    constant IntVal : integer := Get(Params, to_integer(Option));
  begin
    return ApbErrorReadDataType'val(IntVal);
  end function GetApbParameter;

  ------------------------------------------------------------
  impure function GetApbParameter (Params : ModelParametersIDType; Option : ApbOptionsType) return std_logic_vector is
  ------------------------------------------------------------
  begin
    return Get(Params, to_integer(Option));
  end function GetApbParameter;

  ------------------------------------------------------------
  procedure ApbErrorInjection (
  ------------------------------------------------------------
    constant Params   : in    ModelParametersIDType;
    constant Addr     : in    std_logic_vector;
    variable NthCount : inout natural;
    variable RV       : inout RandomPType;
    variable Inject   : out   boolean
  ) is
    constant InjectMode : ApbErrorInjectType := GetApbParameter(Params, PSLVERR_INJECT_MODE);
    variable Value      : integer;
  begin
    if InjectMode /= INJECT_EVERY_NTH then
      NthCount := 0;  -- count from the transfer after the mode is selected
    end if;
    case InjectMode is
      when INJECT_EVERY_NTH =>
        Value    := GetApbParameter(Params, PSLVERR_INJECT_N);
        NthCount := NthCount + 1;
        Inject   := NthCount >= Value;
        if NthCount >= Value then
          NthCount := 0;
        end if;
      when INJECT_PERCENT =>
        Value  := GetApbParameter(Params, PSLVERR_INJECT_PERCENT);
        Inject := RV.RandInt(1, 100) <= Value;
      when INJECT_ADDRESS_RANGE =>
        Inject := unsigned(Addr) >= unsigned(std_logic_vector'(GetApbParameter(Params, PSLVERR_INJECT_ADDR_LOW))) and
                  unsigned(Addr) <= unsigned(std_logic_vector'(GetApbParameter(Params, PSLVERR_INJECT_ADDR_HIGH)));
      when others =>
        Inject := FALSE;
    end case;
  end procedure ApbErrorInjection;

end package body ApbOptionsPkg;
