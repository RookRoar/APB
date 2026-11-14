#
#  Original Author:  Kartik Desai
#
#  Description:
#      Analyse the osvvm_apb sources
#
#  Copyright (c) 2026 by Kartik Desai
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
library osvvm_apb
analyze ApbSettingsPkg.vhd
analyze [FindSettingsPkgBody ApbSettingsPkg]  ;# ApbSettingsPkg_local.vhd in the settings dir, else _default
analyze ApbInterfacePkg.vhd
analyze ApbOptionsPkg.vhd
analyze ApbProtocolPkg.vhd
analyze ApbModelPkg.vhd
analyze ApbCheckerPkg.vhd
analyze ApbTransferScoreboardPkg.vhd
analyze ApbRequester.vhd
analyze ApbCompleterMemory.vhd
analyze ApbCompleter.vhd
analyze ApbMonitor.vhd
analyze ApbComponentPkg.vhd
analyze ApbContext.vhd
