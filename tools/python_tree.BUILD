"""A source tree of Python packages, importable from its root."""

load("@rules_python//python:py_library.bzl", "py_library")

py_library(
    name = "lib",
    srcs = glob(
        ["**/*.py"],
        exclude = ["**/* *"],
    ),
    # LiteX and the pythondata packages read their C sources, templates
    # and RTL as files at run time.
    data = glob(
        ["**"],
        exclude = [
            "**/*.py",
            "**/* *",
            ".git*/**",
        ],
    ),
    imports = ["."],
    visibility = ["//visibility:public"],
)
