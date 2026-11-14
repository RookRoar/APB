#
#  Original Author:  Kartik Desai
#
#  Description:
#      Run all verification component tests
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
RunTest TbApbMemory_BasicReadWrite.vhd
RunTest TbApbMemory_DataWidths.vhd [generic DATA_WIDTH 8]
RunTest TbApbMemory_DataWidths.vhd [generic DATA_WIDTH 16]
RunTest TbApbMemory_DataWidths.vhd [generic DATA_WIDTH 32]
RunTest TbApbMemory_ReadCheck.vhd
RunTest TbApbMemory_ReadPoll.vhd
RunTest TbApbMemory_Async.vhd
RunTest TbApbMemory_Burst.vhd
RunTest TbApbMemory_Spacing.vhd
RunTest TbApbMemory_NarrowAccess.vhd
RunTest TbApbMemory_WaitStates.vhd
RunTest TbApbMemory_SlvErr.vhd
RunTest TbApbMemory_Timeout.vhd
RunTest TbApbMemory_Options.vhd
RunTest TbApbMemory_Reset.vhd
RunTest TbApbMemory_RandomCoverage.vhd
RunTest TbApb_BasicReadWrite.vhd
RunTest TbApb_SplitOps.vhd
RunTest TbApb_PerTransferResponse.vhd
RunTest TbApb_PrequeuedRead.vhd
RunTest TbApb_NoAnswer.vhd
