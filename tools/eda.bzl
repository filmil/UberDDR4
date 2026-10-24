"""Bazel tests for the open-source stages of run_compile.sh.

Each macro declares one `sh_test` that runs tools/eda_test.sh in one of
its modes, with the tool taken from the pinned OSS CAD Suite archive.
"""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

_SUITE = "@oss_cad_suite//:all"
_STUBS = "//tools:xilinx_stubs"

def _eda_test(name, mode, tool, args, srcs, size = "small", **kwargs):
    """Declares an eda_test.sh test.

    Args:
      name: The test name.
      mode: The eda_test.sh mode.
      tool: Label of the tool in @oss_cad_suite, or None for none.
      args: Arguments after the tool.
      srcs: Files the test reads.
      size: The Bazel test size.
      **kwargs: Passed on to sh_test, for example tags.
    """
    tool_args = ["$(rootpath {})".format(tool)] if tool else []
    sh_test(
        name = name,
        size = size,
        srcs = ["//tools:eda_test.sh"],
        args = [mode] + tool_args + args,
        data = srcs + ([tool, _SUITE] if tool else []),
        **kwargs
    )

def verilator_lint_test(name, top, srcs, **kwargs):
    """Verilator lint of `srcs` with `top` as the top module.

    This is run_compile.sh's lint stage for one module: `verilator
    --lint-only -Wall`, with the Xilinx primitive stubs read first.

    Args:
      name: The test name.
      top: The top module.
      srcs: The Verilog sources, in the order they are read.
      **kwargs: Passed on to sh_test.
    """
    files = [_STUBS] + srcs
    _eda_test(
        name = name,
        mode = "lint",
        tool = "@oss_cad_suite//:verilator",
        args = [top] + ["$(rootpath {})".format(f) for f in files],
        srcs = files,
        **kwargs
    )

def iverilog_compile_test(name, srcs, **kwargs):
    """Icarus Verilog parse check of `srcs` (`iverilog -g2012 -Wall -t null`).

    Args:
      name: The test name.
      srcs: The Verilog sources, in the order they are read.
      **kwargs: Passed on to sh_test.
    """
    files = [_STUBS] + srcs
    _eda_test(
        name = name,
        mode = "iverilog",
        tool = "@oss_cad_suite//:iverilog",
        args = ["$(rootpath {})".format(f) for f in files],
        srcs = files,
        **kwargs
    )

def yosys_check_test(name, top, srcs, **kwargs):
    """Yosys synthesis check: hierarchy, proc, opt and check under `top`.

    Args:
      name: The test name.
      top: The top module.
      srcs: The Verilog sources, in the order they are read.
      **kwargs: Passed on to sh_test.
    """
    files = [_STUBS] + srcs
    _eda_test(
        name = name,
        mode = "yosys",
        tool = "@oss_cad_suite//:yosys",
        args = [top] + ["$(rootpath {})".format(f) for f in files],
        srcs = files,
        **kwargs
    )

def sby_tests(name, sby_file, tasks, srcs, bounded = [], **kwargs):
    """One SymbiYosys test per task of `sby_file`, and a suite of them all.

    A task is its own test so that the tasks run in parallel and each is
    cached and reported on its own; `sby -f <file>` with no task runs
    them one after another.

    Args:
      name: The test suite name; each test is `<name>_<task>`.
      sby_file: The .sby file.
      tasks: The task names in `sby_file`.
      srcs: The files its [files] section names.
      bounded: The tasks that prove to depth 28 rather than 8, which take
        longer (about 12 minutes each on one core) and get the largest
        test size.
      **kwargs: Passed on to each sh_test, for example tags.
    """
    tests = []
    for task in tasks:
        test = "{}_{}".format(name, task)
        tests.append(test)
        _eda_test(
            name = test,
            mode = "sby",
            tool = "@oss_cad_suite//:sby",
            args = ["$(rootpath {})".format(sby_file), task],
            srcs = [sby_file] + srcs,
            size = "enormous" if task in bounded else "medium",
            **kwargs
        )
    native.test_suite(
        name = name,
        tests = tests,
        tags = kwargs.get("tags", []),
    )

def ascii_test(name, srcs, **kwargs):
    """Fails when any of `srcs` holds a byte outside tab and printable ASCII.

    Args:
      name: The test name.
      srcs: The files to check.
      **kwargs: Passed on to sh_test.
    """
    _eda_test(
        name = name,
        mode = "ascii",
        tool = None,
        args = ["$(rootpaths {})".format(s) for s in srcs],
        srcs = srcs,
        **kwargs
    )
