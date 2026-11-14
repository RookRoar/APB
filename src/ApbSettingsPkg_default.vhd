--
--  Original Author:  Kartik Desai
--
--  Description:
--      Default package body for ApbSettingsPkg
--
--  Notes:
--      To change a default for a project, copy this file to
--      <OSVVM settings directory>/ApbSettingsPkg_local.vhd and edit the copy.
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
library osvvm;
context osvvm.OsvvmContext;

package body ApbSettingsPkg is
  constant APB_DEFAULT_DELAY : time := 1 ns;

  constant APB_DEFAULT_PREADY_TIME_OUT      : integer   := 64;
  constant APB_DEFAULT_TRANSFER_IDLE_CYCLES : integer   := 0;  -- back-to-back
  constant APB_DEFAULT_PSLVERR_ALERT_LEVEL  : AlertType := ERROR;
  constant APB_DEFAULT_PRDATA_X_CHECK       : boolean   := TRUE;

  constant APB_DEFAULT_WAIT_STATES : integer := 0;
end package body ApbSettingsPkg;
