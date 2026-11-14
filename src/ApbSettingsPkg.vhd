--
--  Original Author:  Kartik Desai
--
--  Description:
--      Default settings for the APB verification components (deferred constants)
--
--  Notes:
--      The package body is chosen by FindSettingsPkgBody in src/build.pro:
--      ApbSettingsPkg_local.vhd in the OSVVM settings directory if it exists,
--      otherwise ApbSettingsPkg_default.vhd.
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

package ApbSettingsPkg is
  constant APB_DEFAULT_DELAY : time;

  -- Requester
  constant APB_DEFAULT_PREADY_TIME_OUT      : integer;  -- maximum wait states accepted
  constant APB_DEFAULT_TRANSFER_IDLE_CYCLES : integer;
  constant APB_DEFAULT_PSLVERR_ALERT_LEVEL  : AlertType;
  constant APB_DEFAULT_PRDATA_X_CHECK       : boolean;

  -- Completer and CompleterMemory
  constant APB_DEFAULT_WAIT_STATES : integer;
end package ApbSettingsPkg;
