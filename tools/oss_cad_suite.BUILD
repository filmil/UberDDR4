"""The parts of an OSS CAD Suite release that the UberDDR4 checks run."""

package(default_visibility = ["//visibility:public"])

# The whole tree: each wrapper in bin/ runs the real binary from lib/ and
# libexec/ with a library path and a Python of its own, all relative to
# itself, so a tool needs every file next to it.
filegroup(
    name = "all",
    srcs = glob(
        ["**"],
        exclude = [
            "**/* *",
            "share/doc/**",
            "share/man/**",
        ],
    ),
)

[
    alias(
        name = tool,
        actual = "bin/" + tool,
    )
    for tool in [
        "iverilog",
        "sby",
        "verilator",
        "yosys",
        "yosys-smtbmc",
    ]
]
