"""The Vivado stages of UberDDR4: XSim simulation and the AXKU3 bitstream.

These run the repository's own scripts, testbench/run_xsim.sh and
example_demo/axku3/build.tcl, unchanged, with Vivado from the
rules_vivado toolchain. Every target here is tagged `manual`, because
they need a Vivado installation that `bazel test //...` cannot assume.
"""

load(
    "@rules_vivado//internal:defines.bzl",
    "VIVADO_TOOLCHAIN_TYPE",
    _script_cmd = "script_cmd",
    _vivado_config = "vivado_config",
)
load("@rules_vivado//internal:providers.bzl", "VivadoBitstreamProvider")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# The Micron DDR4 model files that testbench/setup_micron_model.sh links
# into testbench/micron/, from the DDR4 IP of the Vivado installation.
MICRON_MODEL_DIR = "data/ip/xilinx/ddr4_v2_2/data/dlib/ultrascale/ddr4_sdram/tb/ddr4_model"
MICRON_MODEL_FILES = [
    "arch_defines.v",
    "arch_package.sv",
    "proj_package.sv",
    "interface.sv",
    "StateTable.sv",
    "StateTableCore.sv",
    "MemoryArray.sv",
    "ddr4_model.sv",
    "timing_tasks.sv",
]

def _vivado_command(ctx, first_output, cache_dir):
    """The command prefix that runs what follows it with Vivado available.

    Args:
      ctx: The rule context; the rule must use the Vivado toolchain.
      first_output: An output file of the action, which docker mode uses to
        find the directory it mounts.
      cache_dir: A declared directory for the runner's scratch space.

    Returns:
      A struct with `prefix`, the command line to put first, and `config`,
      the resolved Vivado configuration.
    """
    config = _vivado_config(ctx)
    prefix = _script_cmd(
        config.runner.executable.path,
        first_output.path,
        cache_dir.path,
        freeargs = ["--net=host"],
        container = config.container,
    )
    return struct(prefix = prefix, config = config)

def _xsim_run_impl(ctx):
    log = ctx.actions.declare_file(ctx.label.name + ".log")
    status = ctx.actions.declare_file(ctx.label.name + ".status")
    cache_dir = ctx.actions.declare_directory("_xsim.cache." + ctx.label.name)
    vivado = _vivado_command(ctx, log, cache_dir)

    # Each input goes where a checkout has it: sources at their own
    # paths, the Micron model in testbench/micron/, and the case's header
    # where regression_test.sh writes it.
    placed = []
    inputs = []
    for target in ctx.attr.srcs:
        for f in target.files.to_list():
            placed.append("{}={}".format(f.short_path, f.path))
            inputs.append(f)
    for f in ctx.files.micron_model:
        placed.append("testbench/micron/{}={}".format(f.basename, f.path))
        inputs.append(f)
    placed.append("testbench/regression_logs/regression_config.vh={}".format(ctx.file.config.path))
    inputs += [ctx.file.config, ctx.file.env]

    ctx.actions.run_shell(
        progress_message = "XSim %{label}",
        mnemonic = "XSim",
        inputs = inputs,
        outputs = [log, status, cache_dir],
        tools = [vivado.config.runner, ctx.executable._run],
        command = "{prefix} bash {run} {vivado} {log} {status} {timeout} {phy} {env} {placed}".format(
            prefix = vivado.prefix,
            run = ctx.executable._run.path,
            vivado = vivado.config.vivado_path,
            log = log.path,
            status = status.path,
            timeout = ctx.attr.timeout_minutes,
            phy = ctx.attr.phy_impl,
            env = ctx.file.env.path,
            placed = " ".join(placed),
        ),
    )
    return [DefaultInfo(files = depset([log, status]))]

xsim_run = rule(
    implementation = _xsim_run_impl,
    doc = "Runs testbench/run_xsim.sh for one regression case.",
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Repository files the simulation reads, placed at their own paths.",
        ),
        "micron_model": attr.label_list(
            allow_files = True,
            doc = "The Micron model files, placed in testbench/micron/.",
        ),
        "config": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The case's regression_config.vh, from regression_row.sh.",
        ),
        "env": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The case's MICRON_DENSITY and MICRON_SPEED, from regression_row.sh.",
        ),
        "phy_impl": attr.string(
            default = "component",
            values = ["component", "native"],
            doc = "run_xsim.sh's PHY_IMPL.",
        ),
        "timeout_minutes": attr.int(
            default = 60,
            doc = "Wall-clock limit, as regression_test.sh's SIM_TIMEOUT_MINUTES.",
        ),
        "_run": attr.label(
            default = "//tools:xsim_run",
            executable = True,
            cfg = "exec",
        ),
    },
)

def xsim_test(name, case, phy_impl = "component", tags = []):
    """One case of testbench/regression_test.sh, as a test.

    Declares `<name>_config` (the case's header, read from the script's
    table), `<name>_run` (the simulation, a cached build action) and
    `<name>` (the verdict).

    Args:
      name: The test name.
      case: The test's name in regression_test.sh's ALL_TESTS.
      phy_impl: "component" or "native", as PHY_IMPL.
      tags: Extra tags; `manual` and `vivado` are always added.
    """
    all_tags = ["manual", "vivado"] + tags
    native.genrule(
        name = name + "_config",
        srcs = ["//testbench:regression_test.sh"],
        outs = [
            name + "/regression_config.vh",
            name + "/env.sh",
        ],
        cmd = "$(execpath //tools:regression_row) $< {case} $(OUTS)".format(case = case),
        tools = ["//tools:regression_row"],
        tags = all_tags,
    )
    xsim_run(
        name = name + "_run",
        srcs = ["//testbench:sim_srcs"],
        micron_model = ["//testbench:micron_model"],
        config = name + "/regression_config.vh",
        env = name + "/env.sh",
        phy_impl = phy_impl,
        # regression_test.sh's default limits.
        timeout_minutes = 240 if phy_impl == "native" else 60,
        tags = all_tags,
    )
    sh_test(
        name = name,
        size = "enormous",
        srcs = ["//tools:xsim_check.sh"],
        # The run's outputs, in order: the log, then the status.
        args = ["$(rootpaths :{}_run)".format(name)],
        data = [":{}_run".format(name)],
        tags = all_tags,
    )

def _vivado_tcl_impl(ctx):
    cache_dir = ctx.actions.declare_directory("_vivado.cache." + ctx.label.name)
    outs = [ctx.actions.declare_file(o) for o in ctx.attr.outs]
    log = ctx.actions.declare_file(ctx.label.name + ".vivado.log")
    vivado = _vivado_command(ctx, log, cache_dir)

    placed = []
    for f in ctx.files.srcs:
        placed.append("{}={}".format(f.short_path, f.path))
    taken = ["{}={}".format(o, f.path) for o, f in zip(ctx.attr.outs, outs)]

    ctx.actions.run_shell(
        progress_message = "Vivado %{label}",
        mnemonic = "VivadoTcl",
        inputs = ctx.files.srcs,
        outputs = outs + [log, cache_dir],
        tools = [vivado.config.runner, ctx.executable._run],
        command = "{prefix} bash {run} {vivado} {log} {dir} {script} '{tclargs}' {placed} -- {taken}".format(
            prefix = vivado.prefix,
            run = ctx.executable._run.path,
            vivado = vivado.config.vivado_path,
            log = log.path,
            dir = ctx.attr.dir,
            script = ctx.attr.script,
            tclargs = " ".join(ctx.attr.tclargs),
            placed = " ".join(placed),
            taken = " ".join(taken),
        ),
    )
    providers = [DefaultInfo(files = depset(outs + [log]))]
    if ctx.attr.bitstream:
        if ctx.attr.bitstream not in ctx.attr.outs:
            fail("bitstream must be one of outs: " + ctx.attr.bitstream)
        bit = outs[ctx.attr.outs.index(ctx.attr.bitstream)]
        providers.append(VivadoBitstreamProvider(bitstream = bit, probes = None))
    return providers

vivado_tcl = rule(
    implementation = _vivado_tcl_impl,
    doc = """Runs a Vivado batch Tcl script of the repository in a checkout layout.

    The sources are placed at their own paths in a fresh directory, Vivado
    is started in `dir` with `-mode batch -source <script>`, as the
    directory's Makefile starts it, and `outs`, paths relative to `dir`,
    are taken back as outputs.
    """,
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Repository files the script reads, placed at their own paths.",
        ),
        "dir": attr.string(
            mandatory = True,
            doc = "The directory, relative to the repository root, to start Vivado in.",
        ),
        "script": attr.string(
            mandatory = True,
            doc = "The Tcl script, relative to `dir`.",
        ),
        "tclargs": attr.string_list(
            doc = "Arguments passed after -tclargs.",
        ),
        "outs": attr.string_list(
            mandatory = True,
            doc = "Files the script writes, relative to `dir`, to keep as outputs.",
        ),
        "bitstream": attr.string(
            doc = "The one of `outs` that is a bitstream, if any. It is " +
                  "then provided the way rules_vivado's place and route " +
                  "provides one, so vivado_program_device can program it.",
        ),
        "_run": attr.label(
            default = "//tools:vivado_tcl_run",
            executable = True,
            cfg = "exec",
        ),
    },
)
