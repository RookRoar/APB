--
--  Original Author:  Kartik Desai
--
--  Description:
--      Context for tests and harnesses that use the APB verification components
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
context ApbContext is
  library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

  library osvvm_apb;
  use osvvm_apb.ApbSettingsPkg.all;
  use osvvm_apb.ApbInterfacePkg.all;
  use osvvm_apb.ApbModelPkg.all;
  use osvvm_apb.ApbOptionsPkg.all;
  use osvvm_apb.ApbProtocolPkg.all;
  use osvvm_apb.ApbCheckerPkg.all;
  use osvvm_apb.ApbComponentPkg.all;
end context ApbContext;
