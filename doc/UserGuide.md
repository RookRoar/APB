# OSVVM APB Verification Components: User Guide

This guide is for engineers who already write OSVVM testbenches (TestCtrl, test
harness, `.pro` scripts, AlertLogPkg, the `AddressBusRecType` transactions). It
describes the `osvvm_apb` library: an AMBA APB3 Requester, two Completers, a
passive Monitor with a protocol checker, and the protocol procedures they are
built on.

The protocol reference is the *AMBA APB Protocol Specification*, ARM IHI 0024E.
Section, table and figure numbers in this guide refer to it.

## Contents

1. [Overview](#1-overview)
2. [Building](#2-building)
3. [The APB interface](#3-the-apb-interface)
4. [Timing](#4-timing)
5. [ApbRequester](#5-apbrequester)
6. [ApbCompleterMemory](#6-apbcompletermemory)
7. [ApbCompleter](#7-apbcompleter)
8. [ApbMonitor](#8-apbmonitor)
9. [Options and parameters](#9-options-and-parameters)
10. [Alerts and logging](#10-alerts-and-logging)
11. [Protocol rules](#11-protocol-rules)
12. [Layer 1: protocol procedures](#12-layer-1-protocol-procedures)
13. [Writing tests](#13-writing-tests)
14. [Notes and pitfalls](#14-notes-and-pitfalls)

---

## 1. Overview

| Component | Role | Transaction interface |
|---|---|---|
| `ApbRequester` | Drives APB transfers. The `Axi4LiteManager` operation set plus bursts. | `AddressBusRecType` (manager calls: `Write`, `Read`, `ReadCheck`, ...) |
| `ApbCompleterMemory` | Answers every transfer on its own from an OSVVM `MemoryPkg` memory. Wait states and PSLVERR error injection. | `AddressBusRecType` (backdoor `Write`/`Read`, options) |
| `ApbCompleter` | Test-driven Completer: each transfer waits until the test takes the write or supplies the read data. | `AddressBusRecType` (responder calls: `GetWrite`, `SendRead`, ...) |
| `ApbMonitor` | Passive. Checks every APB3 protocol rule at every rising edge, collects coverage, and can publish completed transfers into a FIFO. | none (generics and the AlertLog API) |

The library has two layers:

- **Layer 1**, `ApbProtocolPkg`: protocol procedures (Requester phases, Completer
  response) that any process can call without a VC or a
  transaction record. All protocol timing lives here.
- **Layer 2**: the four VCs above, built on Layer 1 and structured like the OSVVM
  AXI4-Lite VCs. A test written against `Axi4LiteManager` or `Axi4LiteMemory` uses
  the same calls against `ApbRequester` and `ApbCompleterMemory`.

Packages (VHDL library `osvvm_apb`):

| Package | Contents |
|---|---|
| `ApbInterfacePkg` | `ApbRecType` and its two sub-records, `InitApbRec`, `CheckApbInterface`, `ApbRevisionType` |
| `ApbProtocolPkg` | Layer 1 procedures and types (`ApbTransferType`, `ApbStatusType`, `ApbProcConfigType`) |
| `ApbOptionsPkg` | `ApbOptionsType`, `SetApbOptions`/`GetApbOptions` |
| `ApbSettingsPkg` | Default values of the parameters, as deferred constants |
| `ApbCheckerPkg` | The APB3 protocol checker used by `ApbMonitor` |
| `ApbModelPkg` | Byte-lane and burst helpers (a modified copy of OSVVM `Axi4ModelPkg` subprograms) |
| `ApbTransferScoreboardPkg` | OSVVM scoreboard/FIFO of `ApbTransferType` (Monitor output). **Not** in `ApbContext`, see [8.5](#85-transfer-fifo). |
| `ApbComponentPkg` | Component declarations of the four VCs |
| `ApbContext` | Context: `osvvm_common.OsvvmCommonContext` and every package above except `ApbTransferScoreboardPkg` |

A testbench file starts with:

```vhdl
library osvvm ;
  context osvvm.OsvvmContext ;

library osvvm_apb ;
  context osvvm_apb.ApbContext ;
```

The library supports APB3. Every VC has an `APB_REVISION` generic. Use the default,
`APB3`. Any other value gives a FAILURE at time 0.

---

## 2. Building

### 2.1 Requirements

- OSVVM 2026.09. The `osvvm` and `osvvm_common` libraries must be built first.
- VHDL-2008. The sources are tested on GHDL 6.0.0 and on NVC 1.23.1.

### 2.2 Scripts

| Script | Builds |
|---|---|
| `build.pro` | Library `osvvm_apb` (the `src/` files, in dependency order) |
| `RunAllTests.pro` | `osvvm_apb` and every test in the repository |
| `testbench/build.pro` | The VC test harnesses, library `osvvm_TbApb` |

In your own project, build OSVVM, then `osvvm_apb`, then your testbench:

```tcl
source <path>/OsvvmLibraries/Scripts/StartUp.tcl   ;# StartGHDL.tcl / StartNVC.tcl for GHDL / NVC
build  <path>/OsvvmLibraries/osvvm
build  <path>/OsvvmLibraries/Common
build  <path>/osvvm_apb/build.pro
build  <path>/MyTestbench/build.pro
```

`StartUp.tcl` detects Questa/ModelSim, Riviera-PRO and ActiveHDL. GHDL and NVC are
run from `tclsh` with `StartGHDL.tcl` or `StartNVC.tcl`. See the OSVVM Script User
Guide for the simulator-specific start-up.

### 2.3 Changing the defaults

The parameter defaults (section [9](#9-options-and-parameters)) are deferred
constants in `ApbSettingsPkg`. `build.pro` analyses the package body found by
OSVVM's `FindSettingsPkgBody`:

- `ApbSettingsPkg_local.vhd` in the OSVVM settings directory, if it exists,
- otherwise `src/ApbSettingsPkg_default.vhd`.

To change a default for a whole project, copy `ApbSettingsPkg_default.vhd` to
`ApbSettingsPkg_local.vhd` in the settings directory and edit the values. The
settings directory is chosen by OSVVM (the Tcl variable `OsvvmSettingsDirectory`,
the environment variable `OSVVM_SETTINGS_DIR`, or `OsvvmLibraries/../OsvvmSettings`;
see the OSVVM Settings User Guide). The `_local.vset` form of OSVVM settings is not
supported for this package.

---

## 3. The APB interface

### 3.1 Record

```vhdl
type ApbRequesterRecType is record   -- driven by the Requester (Table 2-1)
  PSel     : std_logic ;
  PEnable  : std_logic ;
  PAddr    : std_logic_vector ;              -- 1 to 32 bits
  PWrite   : std_logic ;
  PWData   : std_logic_vector ;              -- 8, 16 or 32 bits
  PProt    : std_logic_vector(2 downto 0) ;
  PStrb    : std_logic_vector ;              -- PWData'length / 8 bits
end record ;

type ApbCompleterRecType is record   -- driven by the Completer (Table 2-1)
  PRData   : std_logic_vector ;              -- same width as PWData
  PReady   : std_logic ;
  PSlvErr  : std_logic ;
end record ;

type ApbRecType is record
  Requester : ApbRequesterRecType ;
  Completer : ApbCompleterRecType ;
end record ;
```

One `ApbRecType` signal connects every VC on a bus. The address and data widths come
from its constraints, so the VCs have no width generics:

```vhdl
signal ApbBus : ApbRecType(
  Requester(PAddr(ADDR_WIDTH-1 downto 0), PWData(DATA_WIDTH-1 downto 0), PStrb(DATA_WIDTH/8-1 downto 0)),
  Completer(PRData(DATA_WIDTH-1 downto 0))
) ;
```

- Legal widths (checked at time 0, rules APB3-S01 to S03): PADDR up to 32 bits;
  PWDATA 8, 16 or 32 bits; PRDATA the same width as PWDATA (2.1.2).
- PProt and PStrb are part of the record but are not APB3 signals (Table B-1). The VCs
  leave them at 'Z' and never read them. Constrain PStrb to `DATA_WIDTH/8` bits.
- The record is split by signal source because a procedure with a whole-record
  signal parameter would create drivers on every field. Each side passes only its
  own sub-record (`ApbBus.Requester` or `ApbBus.Completer`). Every VC calls
  `InitApbRec(ApbBus)` concurrently, which drives every field 'Z', and then drives
  only its own fields.

To connect a DUT, map the record fields to its ports in the test harness, for
example `PADDR => ApbBus.Requester.PAddr` and `PREADY => ApbBus.Completer.PReady`.

### 3.2 Completers without PREADY or PSLVERR

PREADY and PSLVERR are optional for a Completer (Table B-1). For a DUT Completer that
does not have them, tie the record fields in the harness:

```vhdl
ApbBus.Completer.PReady  <= '1' ;   -- no wait states (3.3)
ApbBus.Completer.PSlvErr <= '0' ;   -- no errors (3.4)
```

Rule APB3-W02 (signals not required to be valid are driven to zero) would warn about
PREADY held HIGH outside ACCESS. It is disabled by default ([8.3](#83-enabling-and-disabling-rules)).

### 3.3 Clock and reset

Every VC has the ports `Clk` (PCLK) and `nReset` (PRESETn, active LOW, Table 2-1).
`nReset` is taken as active whenever it is not '1'. OSVVM `ClockResetPkg`
(`CreateClock`, `CreateReset` with `ResetActive => '0'`) creates both.

---

## 4. Timing

- Every output is driven `tpd` after a rising edge of `Clk`. Every input is sampled
  at a rising edge (3.1, 3.3).
- The output delays are the `tpd_Clk_*` generics of each VC. They default to
  `DEFAULT_DELAY`, which defaults to `APB_DEFAULT_DELAY` (1 ns).
- Every wait and timeout counts clock edges, so the VCs need no clock-period generic
  (unlike the OSVVM AXI VCs, they have no `tperiod_Clk`).
- A transfer is SETUP, then ACCESS until PREADY is HIGH, so at least two cycles (1.1,
  Figure 3-1). Each wait state adds one cycle (3.3.2).
- Back-to-back: when the Requester has another transfer queued at the completion
  edge, it goes from ACCESS straight to SETUP with PSEL held HIGH (4.1, Figure 4-1).
  With the default `TRANSFER_IDLE_CYCLES = 0`, two blocking calls in a row from the
  test are back-to-back, because OSVVM's `WaitForTransaction` does not re-align to
  the clock when no simulation time has passed.

---

## 5. ApbRequester

### 5.1 Entity

```vhdl
entity ApbRequester is
generic (
  MODEL_ID_NAME   : string          := "" ;      -- default: the instance label
  APB_REVISION    : ApbRevisionType := APB3 ;
  DEFAULT_DELAY   : time            := APB_DEFAULT_DELAY ;
  tpd_Clk_PSel    : time := DEFAULT_DELAY ;
  tpd_Clk_PEnable : time := DEFAULT_DELAY ;
  tpd_Clk_PAddr   : time := DEFAULT_DELAY ;
  tpd_Clk_PWrite  : time := DEFAULT_DELAY ;
  tpd_Clk_PWData  : time := DEFAULT_DELAY ;
  tpd_Clk_PProt   : time := DEFAULT_DELAY ;      -- not used (PPROT stays 'Z')
  tpd_Clk_PStrb   : time := DEFAULT_DELAY        -- not used (PSTRB stays 'Z')
) ;
port (
  Clk      : in    std_logic ;
  nReset   : in    std_logic ;
  ApbBus   : inout ApbRecType ;
  TransRec : inout AddressBusRecType
) ;
```

The Requester drives IDLE (PSEL and PENABLE LOW, its other outputs zero) from time 0,
so PSEL is always valid (App. A.1).

### 5.2 Operations

| Test calls | Notes |
|---|---|
| `Write`, `WriteAsync` | One write transfer. |
| `WriteAddressAsync`, `WriteDataAsync` | Address and data queued separately and paired into one transfer, in order, in either call order (as `Axi4LiteManager`). The address given to `WriteDataAsync` only selects the byte lanes. |
| `Read`, `ReadCheck`, `ReadPoll` | One read transfer. `ReadPoll` is OSVVM's, built on `Read`. |
| `ReadAddressAsync`, `ReadData`, `ReadCheckData`, `TryReadData`, `TryReadCheckData` | Split read. `ReadData`/`ReadCheckData` wait for the data; the `Try` calls return `Available = FALSE` if the read has not completed. Read data with no read address outstanding is a FAILURE. |
| `WriteBurst`, `WriteBurstAsync`, `ReadBurst`, and OSVVM's burst helpers built on them (`WriteBurstVector`, `WriteBurstIncrement`, `WriteBurstRandom`, `ReadCheckBurstVector`, `ReadCheckBurstIncrement`, `ReadCheckBurstRandom`, ...) | One transfer per bus word at incrementing word addresses, back-to-back. See [5.4](#54-bursts). |
| `SetApbOptions`, `GetApbOptions` (aliases `SetModelOptions`, `GetModelOptions`) | Section [9](#9-options-and-parameters). |
| `WaitForClock`, `WaitForTransaction`, `WaitForWriteTransaction`, `WaitForReadTransaction`, `GetTransactionCount`, `GetWriteTransactionCount`, `GetReadTransactionCount`, `GetAlertLogID`, `SetUseRandomDelays`, `GetUseRandomDelays`, `SetDelayCoverageID`, `GetDelayCoverageID`, `SetBurstMode`, `GetBurstMode` | OSVVM directives. `WaitForTransaction` waits until every queued transfer has completed. |
| Anything else (`WriteAndRead`, ...) | FAILURE "unimplemented operation", as in OSVVM. |

The transaction counts count completed bus transfers.

### 5.3 Data and byte lanes

The Requester follows OSVVM `Axi4ModelPkg` semantics.

- PADDR is driven exactly as given.
- Writes: the data is placed on the byte lanes of PADDR. APB3 has no PSTRB, so every
  write updates all byte lanes (Table B-1). A write that does not cover every lane
  (a narrow or unaligned write) is not issued: ERROR on "Protocol Error", and the
  call returns without a bus transfer.
- Reads: the full bus is read at PADDR as given, and the requested bytes are
  extracted from the byte lanes of PADDR. Narrow and unaligned reads are allowed;
  an unaligned PADDR is permitted, and its result is UNPREDICTABLE (2.1.1).
- Data that runs past the end of the bus word is a FAILURE, as in OSVVM.

### 5.4 Bursts

APB has no burst transfer. A burst call is split into single transfers, one per bus
word, at incrementing word addresses (PADDR is a byte address, 2.1.1). The transfers
are back-to-back unless spacing is configured.

- Burst FIFO mode: word mode (default; the burst length is a number of bus words) or
  byte mode (`SetBurstMode(Rec, ADDRESS_BUS_BURST_BYTE_MODE)`; the length is a
  number of bytes), as in OSVVM.
- Write bursts must start word aligned and contain whole words. Otherwise: ERROR on
  "Protocol Error", none of the burst is issued, and its data is removed from the
  write burst FIFO so the next burst is not affected.
- Read bursts may start unaligned and end mid-word. Every transfer reads a whole word
  at the aligned address, and only the requested bytes go into the read burst FIFO.
- Read data comes back in order through one FIFO, so let outstanding
  `ReadAddressAsync` reads finish before a `ReadBurst`.

### 5.5 PSLVERR

- Each completed transfer's PSLVERR is compared with the expected value: the PSLVERR
  interface option ('0' by default, '1', or '-' for don't care). The value in force
  when the transfer is queued applies.
- A mismatch is an alert on "Transfer Error" at the level `PSLVERR_ALERT_LEVEL`
  (default ERROR).
- `ReadCheck` does not compare the data of a read that completed with PSLVERR HIGH,
  because such data may be meaningless (3.4). It logs the skipped check at INFO.
- `PRDATA_X_CHECK` (default TRUE) reports PRDATA that is not '0'/'1' at the completion
  of a read, including reads with PSLVERR HIGH (App. A.1): ERROR on "Protocol Error".

### 5.6 Wait states, timeout and reset

- The Requester accepts up to `PREADY_TIME_OUT` wait states (default 64; 0 = no
  limit). After that it abandons the transfer: FAILURE on "No response", then at
  least one IDLE cycle before the next transfer. The abandoned transfer has no
  response, so PSLVERR is not compared. Abandoning ACCESS breaks APB3-R03, so an
  `ApbMonitor` on the bus reports it.
- A PREADY that is not valid in ACCESS is an ERROR on "Protocol Error" (APB3-V06) and
  counts as not ready.
- While `nReset` is active the Requester drives IDLE and starts no transfer. Queued
  transfers start after reset. Reset during a transfer aborts it: WARNING on
  "Protocol Error". IHI0024E does not define this case.

### 5.7 Transfer spacing

- `TRANSFER_IDLE_CYCLES` (default 0) IDLE cycles are inserted before every transfer,
  also the first one after an idle bus. N blocking calls in a row therefore take
  N × (2 + idle cycles + wait states) cycles.
- `SetUseRandomDelays(Rec)` switches to random spacing from OSVVM `DelayCoveragePkg`.
  The default bins give runs of 2 to 10 back-to-back transfers, then 1 to 5 IDLE
  cycles. `SetDelayCoverageID` selects other bins.

---

## 6. ApbCompleterMemory

### 6.1 Entity

```vhdl
entity ApbCompleterMemory is
generic (
  MODEL_ID_NAME   : string          := "" ;      -- default: the instance label
  MEMORY_NAME     : string          := "" ;      -- default: "<model>:memory"
  APB_REVISION    : ApbRevisionType := APB3 ;
  DEFAULT_DELAY   : time            := APB_DEFAULT_DELAY ;
  tpd_Clk_PReady  : time := DEFAULT_DELAY ;
  tpd_Clk_PRData  : time := DEFAULT_DELAY ;
  tpd_Clk_PSlvErr : time := DEFAULT_DELAY
) ;
port (
  Clk      : in    std_logic ;
  nReset   : in    std_logic ;
  ApbBus   : inout ApbRecType ;
  TransRec : inout AddressBusRecType
) ;
```

### 6.2 Behaviour

- The memory is an OSVVM `MemoryPkg` memory, byte wide, with byte addresses. It is
  found by name (`MEMORY_NAME`), so several models, or the test, can share it, as with
  `Axi4LiteMemory`.
- Every transfer is answered without help from the test.
  - A write stores every byte lane. APB3 has no PSTRB, so all lanes are valid
    (Table B-1).
  - A read returns the stored bytes.
  - An unaligned PADDR is aligned to the bus width first (2.1.1 permits this).
- A location that was never written reads as 'U' (OSVVM `MemoryPkg`) and is driven on
  PRDATA. The Requester reports it (`PRDATA_X_CHECK`, APB3-V08). Write or preload the
  memory before reading it.
- Wait states: `WAIT_STATES` (default 0), or random after `SetUseRandomDelays`. The
  default random bins give runs of 2 to 10 transfers with no wait states, then one
  transfer with 1 to 5.
- PSLVERR: error injection decides first; otherwise the PSLVERR interface option
  ('0' or '1') is returned. See [9.3](#93-pslverr-error-injection).
- On an error (3.4):
  - `ERROR_READ_DATA`: a read with PSLVERR HIGH returns the memory data
    (`ERROR_DATA_MEMORY`, default) or zeros (`ERROR_DATA_ZERO`).
  - `ERROR_WRITE_UPDATES`: a write with PSLVERR HIGH updates the memory (TRUE) or
    not (FALSE, default).
- PRDATA and PSLVERR are zero outside the completing cycle, and PREADY is LOW outside
  ACCESS (App. A.1, 3.4).
- Reset during a transfer aborts it: WARNING on "Protocol Error".

### 6.3 Operations

| Test calls | Notes |
|---|---|
| `Write`, `Read`, `ReadCheck` | Backdoor access to the memory: no bus cycle, no simulation time. |
| `WaitForTransaction`, `WaitForWriteTransaction`, `WaitForReadTransaction` | Wait until the next bus transfer (of that kind) has completed. |
| `GetTransactionCount`, `GetWriteTransactionCount`, `GetReadTransactionCount` | Completed bus transfers. |
| `SetApbOptions`, `GetApbOptions`, `WaitForClock`, `GetAlertLogID`, `SetUseRandomDelays`, `SetDelayCoverageID`, ... | Options and OSVVM directives. |
| Anything else | FAILURE "unimplemented operation". |

---

## 7. ApbCompleter

### 7.1 Entity

The same generics and ports as `ApbCompleterMemory`, without `MEMORY_NAME`.

### 7.2 Behaviour

The test answers every transfer through the OSVVM responder calls, as with
`Axi4LiteSubordinate`.

- The Completer detects SETUP, hands the transfer to the test, and holds PREADY LOW
  in ACCESS (3.3.2) until the test answers:
  - a write is answered when the test has taken all of it (`GetWrite`, or
    `GetWriteAddress` and `GetWriteData`);
  - a read is answered when the test has supplied its data (`SendRead`,
    `SendReadData` or `SendReadDataAsync`).
- `SendRead` and `SendReadData` return when the data is queued, not when the bus
  read completes (as in `Axi4LiteSubordinate`).
- `WAIT_STATES` (or the random delay) is the minimum number of wait states. A test
  that is already waiting answers in the same cycle, so zero wait states are possible.
- PSLVERR: error injection decides first; otherwise the PSLVERR option ('0' or '1')
  in force *when the test answers* is returned. To set PSLVERR for one transfer, set
  the option before the matching `GetWrite` or `SendRead`.
- `GetWriteData` returns the data aligned to the write's own PADDR.
- Read data can be queued before the read arrives (`SendReadDataAsync`). It is placed
  on the byte lanes of the read's PADDR when the response is driven. Lanes the test
  did not supply are driven '0', so PRDATA is valid (App. A.1).
- If no test process answers, the Requester times out. The Completer then reports the
  aborted transfer (WARNING on "Protocol Error"). An aborted write is dropped, so the
  test never sees it. An aborted read's address stays queued and is returned by the
  next `GetReadAddress`.
- While `nReset` is active the Completer drives its outputs LOW and ignores the bus.

### 7.3 Operations

| Test calls | Notes |
|---|---|
| `GetWrite`, `TryGetWrite` | Address and data of the next write. |
| `GetWriteAddress`, `TryGetWriteAddress`, `GetWriteData`, `TryGetWriteData` | Split write. |
| `SendRead`, `TrySendRead` | Address of the next read, and its data. |
| `GetReadAddress`, `TryGetReadAddress`, `SendReadData`, `SendReadDataAsync` | Split read. |
| `WaitForTransaction`, `WaitForWriteTransaction`, `WaitForReadTransaction` | Wait until a transfer (of that kind) is available to the test. |
| `SetApbOptions`, `GetApbOptions`, other directives | As for the memory. |
| Bursts and anything else | FAILURE "unimplemented operation". |

---

## 8. ApbMonitor

### 8.1 Entity

```vhdl
entity ApbMonitor is
generic (
  MODEL_ID_NAME     : string          := "" ;     -- default: the instance label
  APB_REVISION      : ApbRevisionType := APB3 ;
  PUBLISH_TRANSFERS : boolean         := FALSE ;  -- push completed transfers into a FIFO
  COLLECT_COVERAGE  : boolean         := TRUE
) ;
port (
  Clk    : in std_logic ;
  nReset : in std_logic ;
  ApbBus : in ApbRecType
) ;
```

The Monitor has no transaction record. It is configured through its generics and the
OSVVM AlertLog API.

### 8.2 Checking

- Every APB3 rule of section [11](#11-protocol-rules) is checked at every rising edge,
  through `CheckApb3Cycle` in `ApbCheckerPkg`.
- Each rule has its own AlertLog ID, a child of the Monitor's ID named as the rule
  (`"APB3-R01"`). A test can therefore check that exactly the expected rule fired:

  ```vhdl
  MonitorID := GetAlertLogID("ApbMonitor") ;   -- the MODEL_ID_NAME
  AffirmIfEqual(GetAlertCount(GetAlertLogID("APB3-R03", MonitorID)), 2, "two APB3-R03") ;
  ```

- Alert levels: S rules FAILURE, W rules WARNING, all other rules ERROR.
- Alert rate: V02 to V08 at most once per rule per transfer (SETUP to completion).
  V01, W01 and W02 once per stretch, re-armed when the signal is valid (V01) or zero
  (W01, W02) again. R rules once per event.
- While `nReset` is active the transition and stability rules are not checked.
  APB3-V01 (PSEL valid) is checked at every edge, also during reset.
- The static rules S01 to S03 are checked one delta cycle after time 0, so a test
  that expects one of them can raise the FAILURE stop count at time 0 first
  ([13.3](#133-expected-alerts)).
- Completed transfers are logged at INFO.

### 8.3 Enabling and disabling rules

A rule is switched off with `SetAlertEnable` on its ID and level:

```vhdl
SetAlertEnable(GetAlertLogID("APB3-W01", MonitorID), WARNING, FALSE) ;  -- off
SetAlertEnable(GetAlertLogID("APB3-W02", MonitorID), WARNING, TRUE) ;   -- on
```

- **A disabled rule is not reported at all.** OSVVM counts alerts to a disabled ID and
  by default fails the test on them (`FailOnDisabledErrors`), so the checker calls
  `Alert` only for enabled rules.
- APB3-W02 is **disabled by default**: many correct designs keep their last values on
  signals that need not be valid, and a Completer with PREADY tied HIGH
  ([3.2](#32-completers-without-pready-or-pslverr)) would warn on every IDLE cycle.
  All other rules are enabled.

### 8.4 Incomplete transfers

A transfer abandoned by the Requester (APB3-R01, R03; for example after the PREADY
timeout), aborted by reset, or an ACCESS without a SETUP (R02, R04) gets its rule alert
(none for reset) and an INFO log line. It is not published and not covered. The FIFO
and the coverage models see only transfers that went SETUP, ACCESS, completion.

### 8.5 Transfer FIFO

With `PUBLISH_TRANSFERS => TRUE`, each completed transfer is pushed into the FIFO
`"<model> Transfers"`, an OSVVM scoreboard of `ApbTransferType` from
`ApbTransferScoreboardPkg`. The test finds it by name:

```vhdl
variable TransferFifo : osvvm_apb.ApbTransferScoreboardPkg.ScoreboardIDType ;
...
TransferFifo := osvvm_apb.ApbTransferScoreboardPkg.NewID("ApbMonitor Transfers", Search => NAME) ;
osvvm_apb.ApbTransferScoreboardPkg.CheckExpected(TransferFifo, ApbTransfer(X"0000_0010", '1', X"1234_5678")) ;
```

- `ApbTransferScoreboardPkg` is not in `ApbContext`: its `ScoreboardIDType` and
  subprograms would clash with those of `osvvm.ScoreboardPkg_slv` from
  `OsvvmCommonContext`. Use selected names, as above, in any design unit that also
  uses `ApbContext` or `ScoreboardPkg_slv`.
- `ApbTransfer(Addr, Write, Data, SlvErr => '0')` (in `ApbProtocolPkg`) builds an expected
  transfer. Data is PWDATA for a write and PRDATA for a read.
- `Match` compares PADDR, PWRITE, the data of that direction and PSLVERR with
  `MetaMatch`, so '-' matches anything. The wait states are not compared.
- The FIFO holds actual transfers, so check them with `CheckExpected` and an expected
  transfer, or `Pop` them and compare yourself.
- The default is FALSE, so a FIFO that nobody empties cannot grow.

`ApbTransferType` fields: `Addr`, `Write`, `WData`, `RData`, `Strb` (all ones in APB3),
`Prot` ("000" in APB3), `SlvErr`, `WaitStates` (ACCESS cycles with PREADY LOW).

### 8.6 Coverage

With `COLLECT_COVERAGE => TRUE` (default) the Monitor records every completed transfer
in two OSVVM `CoveragePkg` models, created with `Search => NAME`:

| Model | Bins |
|---|---|
| `"<model> Coverage"` | Cross of direction (read, write) × wait states (0, 1, 2–3, 4–15, ≥16) × PSLVERR (0, 1): 20 bins |
| `"<model> Spacing Coverage"` | "Idle separated", "Back-to-back" (SETUP directly after a completion, PSEL held HIGH) |

A test gets the same models by name, for example to stop when coverage is reached:

```vhdl
CovID := NewID("ApbMonitor Coverage", Search => NAME) ;
...
exit when GetMinCount(CovID) >= 4 ;
```

`testcases/TbApbMemory_RandomCoverage.vhd` is a complete example: intelligent-coverage
stimulus that stops when every bin of both Monitor models has four hits.

---

## 9. Options and parameters

### 9.1 Setting options

```vhdl
SetApbOptions(RequesterRec, TRANSFER_IDLE_CYCLES, 2) ;
SetApbOptions(CompleterRec, PSLVERR_INJECT_MODE, INJECT_PERCENT) ;
GetApbOptions(RequesterRec, PREADY_TIME_OUT, Value) ;
```

`SetApbOptions`/`GetApbOptions` have overloads for integer, boolean, std_logic,
std_logic_vector, AlertType, `ApbErrorInjectType` and `ApbErrorReadDataType`.
`SetModelOptions`/`GetModelOptions` are aliases.

There are two kinds of option, separated in `ApbOptionsType` by `OPTIONS_MARKER`:

- **Parameters** (before the marker) are written by the test straight into the VC's
  parameter store. This takes no simulation time and is not a transaction. A VC
  ignores parameters it does not use.
- **Interface options** (after the marker: `PSLVERR`) are sent to the VC as
  `SET_MODEL_OPTIONS`/`GET_MODEL_OPTIONS` transactions. Like any OSVVM transaction,
  one issued after simulation time has passed since the VC's previous transaction
  waits for the next clock edge. An interface option that a VC does not support
  (PPROT, PSTRB) is a FAILURE.

A VC reads its parameters at the start of each transfer (and `ERROR_WRITE_UPDATES`
when the write completes), so a change applies from the next transfer.

### 9.2 Option table

| Option | Used by | Type | Default | Meaning |
|---|---|---|---|---|
| `PREADY_TIME_OUT` | Requester | integer ≥ 0 | 64 | Maximum wait states accepted; more gives FAILURE on "No response". 0 = no limit. |
| `TRANSFER_IDLE_CYCLES` | Requester | integer ≥ 0 | 0 | IDLE cycles before each transfer. |
| `PSLVERR_ALERT_LEVEL` | Requester | AlertType | ERROR | Level of the alert on an unexpected PSLVERR. |
| `PRDATA_X_CHECK` | Requester | boolean | TRUE | Check that PRDATA is valid at read completion (APB3-V08). |
| `WAIT_STATES` | Completer, Memory | integer ≥ 0 | 0 | Wait states (Memory) or minimum wait states (Completer). |
| `PSLVERR_INJECT_MODE` | Completer, Memory | `ApbErrorInjectType` | `INJECT_NONE` | Error injection mode, [9.3](#93-pslverr-error-injection). |
| `PSLVERR_INJECT_N` | Completer, Memory | integer ≥ 1 | 1 | `INJECT_EVERY_NTH`: every Nth transfer fails. |
| `PSLVERR_INJECT_PERCENT` | Completer, Memory | integer 0 to 100 | 0 | `INJECT_PERCENT`: chance that a transfer fails. |
| `PSLVERR_INJECT_ADDR_LOW`, `PSLVERR_INJECT_ADDR_HIGH` | Completer, Memory | std_logic_vector (byte address, up to 32 bits) | 0, 0 | `INJECT_ADDRESS_RANGE`: inclusive range. |
| `ERROR_READ_DATA` | Memory | `ApbErrorReadDataType` | `ERROR_DATA_MEMORY` | PRDATA of a read with PSLVERR HIGH: memory data or zeros (`ERROR_DATA_ZERO`). |
| `ERROR_WRITE_UPDATES` | Memory | boolean | FALSE | Whether a write with PSLVERR HIGH updates the memory. |
| `PSLVERR` (interface) | Requester | std_logic | '0' | Expected PSLVERR: '0', '1' or '-' (don't care). |
| `PSLVERR` (interface) | Completer, Memory | std_logic | '0' | PSLVERR returned when error injection does not apply: '0' or '1'. |

Other values of the PSLVERR option are a FAILURE, and the value is not changed. The
defaults come from `ApbSettingsPkg` ([2.3](#23-changing-the-defaults)), except those of
the injection parameters and `ERROR_*`, which are fixed.

### 9.3 PSLVERR error injection

The Completer and the memory decide PSLVERR per transfer as follows: if the injection
mode selects the transfer, PSLVERR is HIGH; otherwise the PSLVERR option is returned.

| `PSLVERR_INJECT_MODE` | A transfer fails when |
|---|---|
| `INJECT_NONE` | never (the PSLVERR option applies) |
| `INJECT_EVERY_NTH` | it is the Nth, 2Nth, ... transfer counted from the first one after this mode was selected (`PSLVERR_INJECT_N`; N = 1 fails every transfer) |
| `INJECT_PERCENT` | a random number 1 to 100 is ≤ `PSLVERR_INJECT_PERCENT`. The generator is seeded from the model name, so runs are reproducible. |
| `INJECT_ADDRESS_RANGE` | PADDR, as unsigned, is in `PSLVERR_INJECT_ADDR_LOW` to `PSLVERR_INJECT_ADDR_HIGH`, inclusive |

Because the injection settings are parameters, they can be changed between two
back-to-back transfers. The PSLVERR option cannot be changed that fast on a Completer
whose previous transaction lies in the past ([9.1](#91-setting-options)).

---

## 10. Alerts and logging

Every message goes through AlertLogPkg.

| AlertLog ID | Child of | Reports | Level |
|---|---|---|---|
| `<model>` | (top) | Interface widths (S01–S03, except in the Monitor), unsupported operation or option, `APB_REVISION` other than APB3, read data with no read outstanding | FAILURE |
| `Protocol Error` | Requester, Completer, Memory | Requester: invalid PREADY/PSLVERR/PRDATA, narrow or unaligned write, unaligned write burst. Completers: invalid PADDR/PWRITE/PWDATA in SETUP. Any VC: transfer aborted by reset or by the Requester. | ERROR; WARNING for an abort |
| `Data Check` | Requester, Memory | Requester: `ReadCheck`, `ReadCheckData`, burst checks. Memory: backdoor `ReadCheck`. | ERROR on mismatch |
| `No response` | Requester | PREADY timeout | FAILURE |
| `Transfer Error` | Requester | PSLVERR different from the expected value | `PSLVERR_ALERT_LEVEL` |
| `APB3-S01` ... `APB3-W02` | Monitor | One ID per rule, section [11](#11-protocol-rules) | S: FAILURE, W: WARNING, others ERROR |

Logging: each VC logs one INFO line per completed transfer (enable with
`SetLogEnable(INFO, TRUE)` or per ID). `TransRec.StatusMsgOn` forces the messages of
one transaction, as in OSVVM.

---

## 11. Protocol rules

The Monitor checks the S, R, V and W rules; the VCs follow all of them. The P rules
list behaviour that is legal and that the Monitor accepts without an alert. The D rules
are design facts the library follows.

### 11.1 Static rules (FAILURE at time 0)

| Rule | Requirement | IHI0024E |
|---|---|---|
| APB3-S01 | PADDR is at most 32 bits wide | Table 2-1 |
| APB3-S02 | PWDATA and PRDATA are 8, 16 or 32 bits wide | 2.1.2, Table 2-1 |
| APB3-S03 | PRDATA has the same width as PWDATA | 2.1.2 |

### 11.2 Transition and stability rules (ERROR)

| Rule | Requirement | IHI0024E |
|---|---|---|
| APB3-R01 | SETUP lasts exactly one cycle: the cycle after SETUP is ACCESS (PSEL and PENABLE HIGH) | 4.1 |
| APB3-R02 | ACCESS is entered only from SETUP (or continues from ACCESS with PREADY LOW); ACCESS directly after IDLE is illegal | 4.1, 3.1.1 |
| APB3-R03 | While PREADY is LOW in ACCESS, the interface stays in ACCESS: PSEL and PENABLE stay HIGH | 4.1, 3.1.2, 3.3.2 |
| APB3-R04 | After completion, PENABLE is LOW: the next cycle is IDLE or SETUP | 3.1.1, 4.1 |
| APB3-R05 | PADDR does not change from SETUP to the end of ACCESS | 4.1, 3.1.1, 3.1.2, 3.3.2 |
| APB3-R06 | PWRITE does not change from SETUP to the end of ACCESS | 4.1, 3.1.2, 3.3.2 |
| APB3-R07 | PWDATA does not change from SETUP to the end of ACCESS, for writes | 4.1, 3.1.2 |

### 11.3 Validity rules (ERROR)

A signal is valid when it is '0' or '1' after `to_X01` ('0', '1', 'L', 'H').

| Rule | Requirement | IHI0024E |
|---|---|---|
| APB3-V01 | PSEL is always valid, also during reset | App. A.1 |
| APB3-V02 | PADDR is valid when PSEL is HIGH | App. A.1, 3.1.1 |
| APB3-V03 | PENABLE is valid when PSEL is HIGH | App. A.1 |
| APB3-V04 | PWRITE is valid when PSEL is HIGH | App. A.1, 3.1.1 |
| APB3-V05 | PWDATA is valid when PSEL and PWRITE are HIGH (in APB3 all byte lanes are active) | App. A.1, 3.1.1 |
| APB3-V06 | PREADY is valid when PSEL and PENABLE are HIGH | App. A.1 |
| APB3-V07 | PSLVERR is valid at completion | App. A.1, 3.4 |
| APB3-V08 | PRDATA is valid at the completion of a read, also when PSLVERR is HIGH | App. A.1, 3.3.1 |

### 11.4 Recommendations (WARNING)

| Rule | Recommendation | IHI0024E | Default |
|---|---|---|---|
| APB3-W01 | PSLVERR is LOW when PSEL, PENABLE or PREADY is LOW | 3.4 | enabled |
| APB3-W02 | Signals that are not required to be valid are driven to zero: PENABLE, PADDR, PWRITE, PWDATA while PSEL is LOW; PWDATA during reads; PREADY outside ACCESS; PRDATA except at read completion | App. A.1 | **disabled** |

### 11.5 Permitted behaviour (no alert)

| Rule | Permitted | IHI0024E |
|---|---|---|
| APB3-P01 | PREADY takes any value, including X, while PENABLE is LOW | 3.1.2 |
| APB3-P02 | PENABLE takes any value while PSEL is LOW | 4.1 |
| APB3-P03 | PSEL stays HIGH from the completion of one transfer into the SETUP of the next (back-to-back) | 3.1.1, 4.1 |
| APB3-P04 | PADDR need not be aligned to the data width (the result is UNPREDICTABLE) | 2.1.1 |
| APB3-P05 | Any number of wait states, from zero upwards. The Requester's PREADY timeout is a VC setting, not a protocol rule. | 3.3.2 |
| APB3-P06 | PWDATA takes any value during reads | 4.1, App. A.1 |
| APB3-P07 | PRDATA takes any value except at the completion of a read | App. A.1 |
| APB3-P08 | PSLVERR takes any value except at completion (APB3-W01 only warns) | 3.4 |
| APB3-P09 | A read with PSLVERR HIGH may return meaningless, but valid, data | 3.4 |
| APB3-P10 | A transfer with PSLVERR HIGH may or may not have changed the Completer's state | 3.4 |

### 11.6 Design rules

| Rule | Fact | IHI0024E |
|---|---|---|
| APB3-D01 | All signals are timed against the rising edge of PCLK | Table 2-1, 3.1, 3.3 |
| APB3-D02 | PRESETn is active LOW | Table 2-1 |
| APB3-D03 | PADDR is a byte address | 2.1.1 |
| APB3-D04 | PPROT and PSTRB are not APB3 signals; the VCs leave them at 'Z' and do not read them | Table B-1 |
| APB3-D05 | A Completer without PREADY has it tied HIGH; without PSLVERR, tied LOW ([3.2](#32-completers-without-pready-or-pslverr)) | Table B-1, 3.4 |
| APB3-D06 | Read and write data use separate buses; a transfer is a read or a write | 2.1.2 |
| APB3-D07 | Every transfer takes at least two cycles (SETUP and ACCESS) | 1.1 |

---

## 12. Layer 1: protocol procedures

`ApbProtocolPkg` holds the procedures the VCs are built on. Use them to drive or answer
APB from a plain process, for example in a unit-level testbench without OSVVM VCs.

### 12.1 Calling convention

- Each Requester or Completer process passes only its own sub-record as a signal
  parameter: `ApbBus.Requester` for the Requester, `ApbBus.Completer` for the Completer
  ([3.1](#31-record)).
- Every procedure that starts a phase must be called just after a rising edge (same
  time step). The procedures add no alignment cycle. Call `wait until rising_edge(Clk)`
  once before the first call.
- `ApbProcConfigType` holds the settings: `Revision` (APB3), `Timing` (per-signal output
  delays, `ApbTiming(Delay)` sets them all), `ReadyTimeOut` (maximum wait states, 0 =
  no limit), `SlvErrAlert` and `SlvErrAlertLevel` (alert on PSLVERR HIGH),
  `ReadDataXCheck` (APB3-V08). `ApbProcConfig` returns the defaults: APB3, 1 ns, 64,
  TRUE, ERROR, TRUE.
- `ApbStatusType`: `APB_OK`, `APB_SLVERR` (completed with PSLVERR HIGH), `APB_TIMEOUT`
  (more than `ReadyTimeOut` wait states; transfer abandoned), `APB_ABORTED` (reset, or
  the Requester left ACCESS).

### 12.2 Requester

| Procedure | Does |
|---|---|
| `ApbRequesterIdle(Req, Config)` | Drive IDLE: PSEL and PENABLE LOW, other outputs zero. |
| `ApbSetupPhase(Clk, Req, Config, Addr, Write, WData, AlertLogID)` | Drive SETUP; return at the next rising edge. |
| `ApbAccessPhase(Clk, nReset, Req, Cmp, Config, RData, WaitStates, Status, AlertLogID, TimeOutAlertLogID)` | Drive ACCESS, wait for PREADY; return at the completion edge with ACCESS still driven. |

After `ApbAccessPhase`, call `ApbSetupPhase` for a back-to-back transfer or
`ApbRequesterIdle`. After `APB_TIMEOUT` or `APB_ABORTED`, drive IDLE for at least one
cycle before the next SETUP; otherwise the Completer misses that SETUP.

### 12.3 Completer

| Procedure | Does |
|---|---|
| `ApbCompleterIdle(Cmp, Config)` | PREADY, PRDATA and PSLVERR LOW. |
| `ApbWaitForTransfer(Clk, nReset, Req, Config, Transfer, AlertLogID)` | Return at the rising edge that samples SETUP, with `Transfer` filled (Addr, Write, WData). Invalid PADDR, PWRITE or PWDATA is an ERROR. |
| `ApbRespond(Clk, nReset, Req, Cmp, Config, WaitStates, RData, SlvErr, Status, AlertLogID)` | Call at the edge that sampled SETUP. Drive `WaitStates` wait states, then PREADY HIGH with PSLVERR and (reads) PRDATA; return at the completion edge with the outputs LOW again. |

For your own monitor, `ApbCheckerPkg` provides the checker: `NewApbRuleIDs(ParentID)`
creates the rule IDs, `InitApbChecker(State)` resets the per-interface state, and
`CheckApb3Cycle(RuleID, State, nReset, ApbBus, Transfer, TransferEnd)`, called at every
rising edge, checks the rules and returns how a transfer ended (`APB_NO_END`,
`APB_COMPLETED`, `APB_ABANDONED`, `APB_NO_SETUP`, `APB_RESET`).

### 12.4 Example

```vhdl
RequesterProc : process
  constant Config     : ApbProcConfigType := ApbProcConfig ;
  variable RData      : std_logic_vector(31 downto 0) ;
  variable WaitStates : natural ;
  variable Status     : ApbStatusType ;
begin
  ApbRequesterIdle(ApbBus.Requester, Config) ;
  wait until nReset = '1' ;
  wait until rising_edge(Clk) ;
  -- A write followed back-to-back by a read of the same address
  ApbSetupPhase(Clk, ApbBus.Requester, Config, X"0000_0010", '1', X"1234_5678", ReqID) ;
  ApbAccessPhase(Clk, nReset, ApbBus.Requester, ApbBus.Completer, Config,
                 RData, WaitStates, Status, ReqID) ;
  ApbSetupPhase(Clk, ApbBus.Requester, Config, X"0000_0010", '0', X"0000_0000", ReqID) ;
  ApbAccessPhase(Clk, nReset, ApbBus.Requester, ApbBus.Completer, Config,
                 RData, WaitStates, Status, ReqID) ;
  ApbRequesterIdle(ApbBus.Requester, Config) ;
  AffirmIfEqual(ReqID, RData, X"1234_5678", "read data") ;
  ...
```

Convenience procedures that run a whole transfer in one call (`ApbWrite`, `ApbRead`,
`ApbReadCheck`) and a transfer sampler (`ApbSampleTransfer`) are provided by the separate
`osvvm_apb_bfm` library, which is built on this package.

---

## 13. Writing tests

### 13.1 Test harness

```vhdl
signal RequesterRec, CompleterRec : AddressBusRecType(
  Address(ADDR_WIDTH-1 downto 0),
  DataToModel(DATA_WIDTH-1 downto 0),
  DataFromModel(DATA_WIDTH-1 downto 0)
) ;
...
ApbRequester_1 : ApbRequester
  port map (Clk => Clk, nReset => nReset, ApbBus => ApbBus, TransRec => RequesterRec) ;

ApbCompleterMemory_1 : ApbCompleterMemory
  port map (Clk => Clk, nReset => nReset, ApbBus => ApbBus, TransRec => CompleterRec) ;

ApbMonitor_1 : ApbMonitor
  generic map (MODEL_ID_NAME => "ApbMonitor")
  port map (Clk => Clk, nReset => nReset, ApbBus => ApbBus) ;
```

`testbench/TbApbMemory.vhd` (Requester, memory, Monitor) and `testbench/TbApb.vhd`
(Requester, test-driven Completer, Monitor) are complete harnesses. In TestCtrl,
declare the transaction ports `inout AddressBusRecType`, as in the OSVVM examples.

### 13.2 Test

```vhdl
TestProc : process
begin
  wait until nReset = '1' ;
  WaitForClock(RequesterRec, 2) ;
  Write(RequesterRec, X"0000_0010", X"1234_5678") ;
  ReadCheck(RequesterRec, X"0000_0010", X"1234_5678") ;
  ReadCheck(RequesterRec, X"0000_0011", X"56") ;          -- narrow read
  SetApbOptions(CompleterRec, WAIT_STATES, 3) ;
  Write(RequesterRec, X"0000_0014", X"0000_0001") ;       -- three wait states
  ...
```

With a test-driven `ApbCompleter`, a second process answers on `CompleterRec`:

```vhdl
CompleterProc : process
  variable Addr : std_logic_vector(ADDR_WIDTH-1 downto 0) ;
  variable Data : std_logic_vector(DATA_WIDTH-1 downto 0) ;
begin
  GetWrite(CompleterRec, Addr, Data) ;
  AffirmIfEqual(Data, X"1234_5678", "write data") ;
  SendRead(CompleterRec, Addr, X"1234_5678") ;
  ...
```

Only one process may call transactions on a given record. A process may drive both
records if it uses the Requester's asynchronous calls, so that it is free to answer
on the Completer record.

The `testcases/` folder has one test per feature; each file is a TestCtrl architecture
and a configuration, run from `testcases/RunAllTests.pro`.

### 13.3 Expected alerts

- Count expected alerts per AlertLog ID with `GetAlertCount`, and cancel them at the
  end with `EndOfTestReports(ExternalErrors => -AlertCountType'(...))`.
- A test that expects a FAILURE (for example the PREADY timeout) calls
  `SetAlertStopCount(FAILURE, integer'right)` first, so the simulation does not stop.
- A test that expects a static-rule FAILURE (APB3-S01 to S03) must raise the FAILURE
  stop count at time 0, before the Monitor's check one delta later, and must not call
  `ClearAlerts` afterwards, which would clear the expected alert.

---

## 14. Notes and pitfalls

- **Never-written memory reads 'U'.** Write or preload `ApbCompleterMemory` (backdoor
  `Write`) before reading; otherwise `PRDATA_X_CHECK` reports APB3-V08.
- **APB3 writes are full width.** Narrow or unaligned writes, and write bursts that are
  unaligned or not whole words, are not issued (ERROR on "Protocol Error").
- **Finish `ReadAddressAsync` reads before a `ReadBurst`.** Read data returns through
  one FIFO, in order.
- **Interface options take a clock edge.** Setting the PSLVERR option on a VC whose last
  transaction lies in the past waits for the next clock edge, which can break
  back-to-back traffic. Parameters, including the error-injection settings, take no
  time ([9.1](#91-setting-options)).
- **`ApbCompleter`:** `SendRead` returns when the data is queued, not when the read
  completes. The PSLVERR option is taken when the test answers. An aborted read's
  address stays in the queue.
- **Completers without PREADY/PSLVERR:** tie PREADY HIGH and PSLVERR LOW
  ([3.2](#32-completers-without-pready-or-pslverr)).
- **Monitor transfer FIFO:** use `ApbTransferScoreboardPkg` with selected names
  ([8.5](#85-transfer-fifo)).
- **Disabled rules are silent**, and APB3-W02 is disabled by default ([8.3](#83-enabling-and-disabling-rules)).
- **Paths with spaces:** the OSVVM scripts cannot analyse sources from a path that
  contains spaces. Keep the library, the OSVVM libraries and the build directory on
  paths without spaces.
- **Settings directory:** the OSVVM scripts write generated settings files into the
  settings directory, which defaults to a folder inside the OSVVM installation. Set
  `OSVVM_SETTINGS_DIR` to a writable folder of your own if the installation is shared or
  read-only; `ApbSettingsPkg_local.vhd` goes into that same folder.
