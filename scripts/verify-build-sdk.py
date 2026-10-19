"""Reject binaries whose linked SDK differs from the selected compile SDK."""
import re
import subprocess
import sys


def version(value):
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", value):
        raise ValueError("Invalid SDK version: " + value)
    return tuple(int(part) for part in (value.split(".") + ["0"] * 3)[:3])


def verify(output, expected_sdk):
    if output.count("cmd LC_BUILD_VERSION") != 1:
        raise ValueError("Expected one LC_BUILD_VERSION")
    fields = {}
    for key in ("platform", "minos", "sdk"):
        values = re.findall(r"^\s*" + key + r"\s+(\S+)\s*$", output, re.MULTILINE)
        if len(values) != 1:
            raise ValueError("Missing or ambiguous build field: " + key)
        fields[key] = values[0]
    if fields["platform"] != "MACOS" or version(fields["minos"]) != version("14.0"):
        raise ValueError("Expected macOS deployment target 14.0: " + str(fields))
    if version(fields["sdk"]) != version(expected_sdk):
        raise ValueError("Linked SDK differs from selected SDK: " + str(fields))
    return fields


if __name__ == "__main__":
    expected_sdk, *binaries = sys.argv[1:]
    if not binaries:
        raise SystemExit("Usage: verify-build-sdk.py SDK BINARY [BINARY ...]")
    for binary in binaries:
        output = subprocess.check_output(["/usr/bin/vtool", "-show-build", binary], text=True)
        print(binary, verify(output, expected_sdk))
