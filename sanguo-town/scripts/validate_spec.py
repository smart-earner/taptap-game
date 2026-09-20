#!/usr/bin/env python3
"""Current static spec entrypoint; historical validators remain separately versioned."""
from pathlib import Path
import runpy

if __name__ == '__main__':
    runpy.run_path(str(Path(__file__).with_name('validate_identity_spec.py')), run_name='__main__')
