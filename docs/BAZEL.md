# Building and verifying with Bazel

[Back to README](../README.md). Bazel runs every step that `run_compile.sh`,
`testbench/regression_test.sh` and `example_demo/axku3/Makefile` run. It gets
the open-source tools itself, so a checkout needs only Bazel. Each check is a
separate test, so the checks run in parallel, and Bazel caches each result
until one of its inputs changes.

The scripts themselves are unchanged and still work. Where Bazel runs a step
that needs Vivado, it calls the repository's own `run_xsim.sh` or `build.tcl`.

## Without Vivado

Install [Bazelisk](https://github.com/bazelbuild/bazelisk) as `bazel`. It
reads `.bazelversion` and fetches that Bazel. Then run, from the repository
root:

```bash
bazel test //...
```

That runs lint, the compile checks, the ASCII check, and both formal suites,
34 tasks in all. On the first run, Bazel downloads one dated OSS CAD Suite
release, about 750 MB, which is pinned by checksum in `MODULE.bazel`. It
provides Verilator, Icarus Verilog, Yosys, SymbiYosys and its solvers. The
only thing taken from the machine is Perl, which Verilator's front end needs.

| `run_compile.sh` | Bazel |
| --- | --- |
| `--lint` | `bazel test //rtl:lint //:ascii` |
| `--compile` | `bazel test //rtl:compile` |
| `--formal` | `bazel test //formal:single` |
| `--formal-regr` | `bazel test //formal:multi` |
| `--no-sim` | `bazel test //:no_sim` |
| `--sim <case>` | `bazel test //testbench:sim_<case>` |
| `--sim-regr` | `bazel test //testbench:sim_regression` |
| `--all` | `bazel test //... //testbench:sim_regression` |

Each formal task is a test of its own, for example
`//formal:multi_ddr4_2400_x16_map1`. The four tasks that prove to depth 28
take about 12 minutes each. The other tasks take under a minute.

A failing test prints its tool log. All the logs stay in
`bazel-testlogs/<package>/<test>/test.outputs/`. That is where
`run_compile.sh` used to write them, in its `build_logs/` directory.

## With Vivado

These targets need Vivado. They are tagged `manual`, so `bazel test //...`
skips them, and you have to name them:

| Make or script | Bazel |
| --- | --- |
| `testbench/setup_micron_model.sh` | `bazel build //testbench:micron_model` |
| `run_compile.sh --sim baseline` | `bazel test //testbench:sim_baseline` |
| `PHY_IMPL=native ... run_xsim.sh` | `bazel test //testbench:sim_native_baseline` |
| `regression_test.sh` | `bazel test //testbench:sim_regression` |
| `PHY_IMPL=native regression_test.sh` | `bazel test //testbench:sim_native_regression` |
| `make` in `example_demo/axku3` | `bazel build //example_demo/axku3:bitstream` |
| `make ALLOW_FAILING_TIMING=1` | `bazel build //example_demo/axku3:bitstream_allow_failing_timing` |
| `make synth` | `bazel build //example_demo/axku3:synth` |
| `make program` | `bazel run //example_demo/axku3:program` |

There is one simulation per case in the `ALL_TESTS` table of
`regression_test.sh`, each with that case's name. The Bazel build reads
each case's parameters from that table, so the table stays the only place
they are set. The verdict is the one `regression_test.sh` gives:
- `run_xsim.sh` exits 0;
- the log shows a pass marker and no failure marker;
- the Micron model reports no timing violation.

The simulation itself is a cached build step. Rerunning a passing or a
failing case costs nothing until an input changes.

The board outputs land in `bazel-bin/example_demo/axku3/build/`. That is
the bitstream, the routed checkpoint and the same reports that `make`
writes.

### How Bazel gets Vivado

The [rules_vivado](https://github.com/filmil/bazel_rules_vivado) toolchain
supplies Vivado. By default, `.bazelrc` selects its `hermetic` mode. In that
mode Bazel installs Vivado itself, once, from the AMD installer archive named
in `MODULE.bazel`. It installs the Kintex UltraScale+ device family and
nothing else, since that family includes the AXKU3's `xcku3p`. The
installation is kept in a shared cache, so later builds reuse it. The first
install needs about 300 GB free while it runs and takes a couple of hours.

AMD's download needs a login, so Bazel cannot fetch the archive. Download it
once and either put it at the path `MODULE.bazel` names, or name your own
path. The Micron DDR4 model comes from the installation's DDR4 IP, as
`setup_micron_model.sh` takes it. This repository does not redistribute it.

If Vivado is already installed, use it instead. Put these lines in
`user.bazelrc`, which is not committed:

```
build --@rules_vivado//:vivado_mode=host
build --@rules_vivado//internal:vivado_version=2025.2
build --@rules_vivado//internal:vivado_path=/tools/Xilinx/2025.2/Vivado
```

Use the path that `XILINX_VIVADO` would have. The
[rules_vivado toolchain guide](https://github.com/filmil/bazel_rules_vivado/blob/main/docs/vivado-toolchain.md)
covers the other modes, Docker among them.

## Not covered

`projects/axku3_linux/` builds a LiteX SoC with its own Python tools and
its own dependency list in `dependencies.json`. It is not built with Bazel
yet.
