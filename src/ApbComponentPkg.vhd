--
--  Original Author:  Kartik Desai
--
--  Description:
--      Component declarations for the APB verification components
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

library osvvm_common;
context osvvm_common.OsvvmCommonContext;

use work.ApbSettingsPkg.all;
use work.ApbInterfacePkg.all;

package ApbComponentPkg is

  ------------------------------------------------------------
  component ApbRequester is
  ------------------------------------------------------------
    generic (
      MODEL_ID_NAME   : string          := "";
      APB_REVISION    : ApbRevisionType := APB3;

      DEFAULT_DELAY   : time            := APB_DEFAULT_DELAY;

      tpd_Clk_PSel    : time            := DEFAULT_DELAY;
      tpd_Clk_PEnable : time            := DEFAULT_DELAY;
      tpd_Clk_PAddr   : time            := DEFAULT_DELAY;
      tpd_Clk_PWrite  : time            := DEFAULT_DELAY;
      tpd_Clk_PWData  : time            := DEFAULT_DELAY;
      tpd_Clk_PProt   : time            := DEFAULT_DELAY;
      tpd_Clk_PStrb   : time            := DEFAULT_DELAY
    );
    port (
      Clk      : in    std_logic;
      nReset   : in    std_logic;
      ApbBus   : inout ApbRecType;
      TransRec : inout AddressBusRecType
    );
  end component ApbRequester;

  ------------------------------------------------------------
  component ApbCompleterMemory is
  ------------------------------------------------------------
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
      Clk      : in    std_logic;
      nReset   : in    std_logic;
      ApbBus   : inout ApbRecType;
      TransRec : inout AddressBusRecType
    );
  end component ApbCompleterMemory;

  ------------------------------------------------------------
  component ApbCompleter is
  ------------------------------------------------------------
    generic (
      MODEL_ID_NAME   : string          := "";
      APB_REVISION    : ApbRevisionType := APB3;

      DEFAULT_DELAY   : time            := APB_DEFAULT_DELAY;

      tpd_Clk_PReady  : time            := DEFAULT_DELAY;
      tpd_Clk_PRData  : time            := DEFAULT_DELAY;
      tpd_Clk_PSlvErr : time            := DEFAULT_DELAY
    );
    port (
      Clk      : in    std_logic;
      nReset   : in    std_logic;
      ApbBus   : inout ApbRecType;
      TransRec : inout AddressBusRecType
    );
  end component ApbCompleter;

  ------------------------------------------------------------
  component ApbMonitor is
  ------------------------------------------------------------
    generic (
      MODEL_ID_NAME     : string          := "";
      APB_REVISION      : ApbRevisionType := APB3;
      PUBLISH_TRANSFERS : boolean         := FALSE;
      COLLECT_COVERAGE  : boolean         := TRUE
    );
    port (
      Clk    : in std_logic;
      nReset : in std_logic;
      ApbBus : in ApbRecType
    );
  end component ApbMonitor;

end package ApbComponentPkg;
