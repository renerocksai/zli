#!/usr/bin/env python3
"""Run real process argument, help, error and legacy compatibility cases."""

import json
import os
import platform
from pathlib import Path
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: cli.py <zli-parser-fixture>")
    fixture = Path(sys.argv[1]).resolve(strict=True)
    cases = []

    def run(args, legacy=False):
        prefix = ["--legacy-iterator"] if legacy else []
        result = subprocess.run(
            [str(fixture), *prefix, *args],
            capture_output=True, text=True, encoding="utf-8", timeout=10,
        )
        assert result.returncode in (0, 1), (args, result.returncode, result.stderr)
        return result

    def success(name, args, expected):
        for legacy in (False, True):
            result = run(args, legacy)
            assert result.returncode == 0, (name, result.stderr)
            assert result.stderr == "", (name, result.stderr)
            actual = json.loads(result.stdout)
            for key, value in expected.items():
                assert actual[key] == value, (name, key, actual, expected)
        cases.append({"name": name, "status": "passed", "entry_points": 2})

    def error(name, args, diagnostic):
        for legacy in (False, True):
            result = run(args, legacy)
            assert result.returncode == 1, (name, result.returncode, result.stdout)
            assert result.stdout == "", (name, result.stdout)
            assert result.stderr.startswith("error: "), (name, result.stderr)
            assert diagnostic in result.stderr, (name, diagnostic, result.stderr)
        cases.append({"name": name, "status": "passed", "entry_points": 2})

    success("defaults", ["values"], {"port": 8080, "workers": None, "verbose": False})
    expected = {"port": 9000, "duration_ms": 25, "execution": "inline", "workers": 2}
    success("attached values", ["values", "--port=9000", "-d=25", "--execution=inline", "--workers=2"], expected)
    success("separate values", ["values", "-p", "9000", "--duration-ms", "25", "--execution", "inline", "--workers", "2"], expected)
    success("bare long boolean", ["values", "--verbose"], {"verbose": True})
    success("bare short boolean preserves positional", ["values", "-v", "false"], {"verbose": True, "positional": {"first": "false", "second": None}})
    success("explicit true", ["values", "--verbose=true"], {"verbose": True})
    success("explicit false", ["values", "-v=false"], {"verbose": False})
    success("negative named and positional numbers", ["values", "--count", "-12", "-4"], {"count": -12, "positional": {"first": "-4", "second": None}})
    success("empty attached and separate strings", ["values", "--text=", "--sentinel", "", "--optional=", "", ""], {"text": "", "sentinel": "", "optional": "", "positional": {"first": "", "second": ""}})
    value = 'Grüße 🦎 path with spaces \\ "quoted" = value'
    success("unicode quoted and sentinel lifetime", ["values", "--text", value, "--sentinel=" + value, "--optional", value, value, value], {"text": value, "sentinel": value, "optional": value, "positional": {"first": value, "second": value}})
    success("end of options disables help", ["values", "--", "--help", "help"], {"positional": {"first": "--help", "second": "help"}})
    success("end of options retains dash strings", ["values", "--", "-file", "--"], {"positional": {"first": "-file", "second": "--"}})
    success("lone dash is positional", ["values", "-"], {"positional": {"first": "-", "second": None}})
    success("help prefix stays positional", ["values", "h"], {"positional": {"first": "h", "second": None}})
    success("help token can be a named value", ["values", "--text", "--help"], {"text": "--help"})
    success("attached end marker can be a named value", ["values", "--text=--"], {"text": "--"})
    success("void subcommand", ["empty"], {})
    success("required value", ["required", "--number", "255"], {"number": 255})

    for token in ("--help", "-h", "help"):
        for scope, expected_help in (([], "GLOBAL HELP\n"), (["values"], "VALUES HELP\n")):
            for legacy in (False, True):
                result = run([*scope, token], legacy)
                assert (result.returncode, result.stdout, result.stderr) == (0, expected_help, ""), result
            cases.append({"name": "exact help " + " ".join([*scope, token]), "status": "passed", "entry_points": 2})

    error("missing subcommand", [], "subcommand required")
    error("unknown subcommand", ["missing"], "Invalid subcommand")
    error("empty subcommand", [""], "Invalid subcommand")
    error("empty argument without positionals", ["no-help", ""], "Unknown positional argument")
    error("unknown option", ["values", "--unknown"], "Unknown CLI argument")
    error("help option prefix is not help", ["values", "--hel"], "Unknown CLI argument")
    error("assigned help is not help", ["values", "--help=1"], "Unknown CLI argument")
    error("missing separate value", ["values", "--port"], "argument value required")
    error("missing value before end marker", ["values", "--text", "--"], "argument value required before --")
    error("empty integer", ["values", "--port="], "must not be empty")
    error("invalid integer", ["values", "--port=nope"], "expected an integer")
    error("integer overflow", ["values", "--port=65536"], "exceeds 16-bit")
    error("invalid enum", ["values", "--execution=other"], "expected one of")
    error("invalid boolean", ["values", "--verbose=maybe"], "expected true or false")
    error("empty boolean", ["values", "--verbose="], "expected true or false")
    error("duplicate alias", ["values", "--port=1", "-p", "2"], "duplicate argument")
    error("required argument missing", ["required"], "argument is required")
    error("extra positional", ["values", "one", "two", "three"], "Unknown positional argument")
    error("void subcommand rejects arguments", ["empty", "surplus"], "unexpected argument")

    print(json.dumps({
        "status": "passed", "platform": platform.platform(),
        "machine": platform.machine(), "python": platform.python_version(),
        "fixture": fixture.name, "case_groups": len(cases),
        "subprocesses": len(cases) * 2, "cases": cases,
    }, indent=2))


if __name__ == "__main__":
    main()
