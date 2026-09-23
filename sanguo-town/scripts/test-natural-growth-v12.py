#!/usr/bin/env python3
"""Check dinner last-mile recovery and lossless audit checkpoint resumption."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
subprocess.run(["swift", "build", "-c", "release", "--product", "SanguoLifeCLI"], cwd=ROOT, check=True)
BIN = pathlib.Path(subprocess.check_output(
    ["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True,
).strip()) / "SanguoLifeCLI"


def audit(days, checkpoint=None):
    command = [str(BIN), "--natural-growth-audit", "--days", str(days), "--seed", "7"]
    if checkpoint is not None:
        command += ["--audit-checkpoint-dir", checkpoint]
    return subprocess.check_output(command, cwd=ROOT, text=True)


whole = audit(7)
assert "MEAL_GAP" not in whole and "MEAL_WINDOW_GAP" not in whole, whole
for day in (3, 6):
    line = next(line for line in whole.splitlines() if line.startswith(f"DAY {day} "))
    assert "meal=100%" in line, line
print("PASS dinner meals reach newly occupied homes from conserved stock before the deadline")

with tempfile.TemporaryDirectory(prefix="sanguo-audit-") as checkpoint:
    first = audit(3, checkpoint)
    resumed = audit(7, checkpoint)
    assert "resumedDay=3" in resumed
    continuous_days = [line for line in whole.splitlines() if line.startswith("DAY ")]
    split_days = [line for line in (first + resumed).splitlines() if line.startswith("DAY ")]
    assert split_days == continuous_days, (split_days, continuous_days)
    assert "MEAL_GAP" not in resumed and "MEAL_WINDOW_GAP" not in resumed
    print("PASS atomic audit checkpoint resumes the same seven-day economy and meal ledger")

with tempfile.TemporaryDirectory(prefix="sanguo-daily-audit-") as checkpoint:
    command = [str(BIN), "--natural-growth-audit", "--days", "1", "--seed", "7",
               "--audit-linked-war-clock", "--audit-daily-draws", "10",
               "--audit-checkpoint-dir", checkpoint]
    first = subprocess.check_output(command, cwd=ROOT, text=True)
    assert "drawsPerRealDay=10" in first and "draws=2 " in first, first
    command[command.index("--days") + 1] = "2"
    resumed = subprocess.check_output(command, cwd=ROOT, text=True)
    assert "resumedDay=1" in resumed and "draws=2 " in resumed, resumed
    print("PASS daily-ten player policy persists the two opening draws and an isolated checkpoint")
