#!/bin/sh
# Runs the headless suite. Extra args go to the test runner, e.g. tools/test.sh --only=cambrian
cd "$(dirname "$0")/.."
godot --headless --path . -s tests/run_all.gd -- "$@"
