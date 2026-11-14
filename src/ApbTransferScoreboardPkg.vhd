--
--  Original Author:  Kartik Desai
--
--  Description:
--      OSVVM scoreboard/FIFO for APB transfers (ApbTransferType). ApbMonitor
--      pushes the transfers it observes into one, found by name.
--
--  Notes:
--      Not part of ApbContext: its ScoreboardIDType would hide the one from
--      osvvm.ScoreboardPkg_slv. Use it explicitly, with selected names if a design
--      unit also uses ScoreboardPkg_slv.
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

use work.ApbProtocolPkg.all;

package ApbTransferScoreboardPkg is new osvvm.ScoreboardGenericPkg
  generic map (
    ExpectedType       => ApbTransferType,
    ActualType         => ApbTransferType,
    Match              => work.ApbProtocolPkg.Match,
    expected_to_string => work.ApbProtocolPkg.to_string,
    actual_to_string   => work.ApbProtocolPkg.to_string
  );
