"""Runs a Python test script with a pseudo-terminal as its standard input.

Usage: with_pty.py <script> [<arg>...]

Some tests of projects/axku3_linux build LiteX's serial terminal, which
reads the terminal settings of standard input when it is created. A Bazel
test has no terminal there, so this opens a pseudo-terminal, puts it on
standard input, and runs <script> as __main__ in this same interpreter,
with this test's import path. That is the situation of running the tests
by hand from a shell. The exit status is the script's.
"""

import os
import runpy
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: with_pty.py <script> [<arg>...]")
    script = sys.argv[1]
    _, terminal = os.openpty()
    os.dup2(terminal, 0)
    sys.argv = sys.argv[1:]
    sys.path.insert(0, os.path.dirname(os.path.abspath(script)))
    runpy.run_path(script, run_name="__main__")


if __name__ == "__main__":
    main()
