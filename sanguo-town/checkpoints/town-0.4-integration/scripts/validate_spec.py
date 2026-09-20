#!/usr/bin/env python3
"""Current specification entry point; no game simulation is executed."""
from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).with_name("validate_spec_v04.py")), run_name="__main__")
