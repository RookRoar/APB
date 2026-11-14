# OSVVM APB Verification Components

Verification components for the AMBA APB3 protocol (ARM IHI 0024E), written for
[OSVVM](https://github.com/OSVVM/OsvvmLibraries) 2026.09.

| Component | Role |
|---|---|
| `ApbRequester` | Drives APB transfers through the OSVVM `AddressBusRecType` interface: `Write`, `Read`, `ReadCheck`, `ReadPoll`, async and split operations, and bursts (as single transfers). |
| `ApbCompleterMemory` | Answers every transfer from an OSVVM `MemoryPkg` memory, with configurable or random wait states and PSLVERR error injection. Backdoor access from the test. |
| `ApbCompleter` | Test-driven Completer: the test takes each write and supplies each read's data (`GetWrite`, `SendRead`, ...). |
| `ApbMonitor` | Passive. Checks every APB3 protocol rule at every clock edge (one AlertLog ID per rule), collects coverage, and can publish completed transfers into a scoreboard FIFO. |
| `ApbProtocolPkg` | The protocol procedures the components are built on, usable from any process without a component. |

Tests written for the OSVVM AXI4-Lite components use the same calls with these
components.

## Requirements

- OSVVM 2026.09 (`osvvm` and `osvvm_common` libraries).
- A VHDL-2008 simulator supported by the OSVVM scripts.

## Layout

| Path | Contents |
|---|---|
| `src/` | The library `osvvm_apb`; `src/build.pro` lists the files in build order |
| `testbench/` | Test harnesses: Requester with memory, and Requester with test-driven Completer, each with a Monitor |
| `testcases/` | One test per feature, including a coverage-driven random test |
| `doc/UserGuide.md` | Reference for every component, the options, and the protocol rules |

## Building and running the tests

Start the OSVVM scripts in your simulator, build OSVVM, then run the tests. Use paths
without spaces: the OSVVM scripts cannot analyse sources from a path that contains
spaces.

GHDL or NVC (from `tclsh`, in a build directory of your choice):  
Questa / ModelSim (in the simulator's Tcl console, in a build directory):

```tcl
source <path>/OsvvmLibraries/Scripts/StartUp.tcl
build  <path>/OsvvmLibraries/osvvm
build  <path>/OsvvmLibraries/Common
build  <path>/osvvm_apb/build.pro
build  <path>/osvvm_apb/RunAllTests.pro
```

To build only the library for your own testbench, use `build <path>/osvvm_apb/build.pro`.
The results are in the usual OSVVM HTML and YAML reports.

## Using the components

```vhdl
library osvvm_apb ;
  context osvvm_apb.ApbContext ;
...
signal ApbBus : ApbRecType(
  Requester(PAddr(31 downto 0), PWData(31 downto 0), PStrb(3 downto 0)),
  Completer(PRData(31 downto 0))
) ;
...
ApbRequester_1 : ApbRequester
  port map (Clk => Clk, nReset => nReset, ApbBus => ApbBus, TransRec => RequesterRec) ;

ApbCompleterMemory_1 : ApbCompleterMemory
  port map (Clk => Clk, nReset => nReset, ApbBus => ApbBus, TransRec => CompleterRec) ;

ApbMonitor_1 : ApbMonitor
  port map (Clk => Clk, nReset => nReset, ApbBus => ApbBus) ;
```

In the test:

```vhdl
Write(RequesterRec, X"0000_0010", X"1234_5678") ;
ReadCheck(RequesterRec, X"0000_0010", X"1234_5678") ;
SetApbOptions(CompleterRec, WAIT_STATES, 3) ;
```

See [doc/UserGuide.md](doc/UserGuide.md) for the details.

## License

Apache License 2.0, see [LICENSE](LICENSE). `src/ApbModelPkg.vhd` contains code
adapted from OSVVM (Copyright SynthWorks Design Inc., Apache License 2.0).
