#!/usr/bin/env python3
"""Keep the published v0.12 save identity tied to its five content inputs."""
import hashlib
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = (
    "Sources/SanguoLife/Resources/hero-town-v0.9.json",
    "spec/hero-town-v0.10-growth-delta.json",
    "spec/hero-town-v0.11-war-delta.json",
    "Sources/SanguoLife/Resources/hero-town-v0.12-economy-delta.json",
    "Sources/SanguoLife/Resources/hero-town-v0.12-roster.json",
)
data = b"".join(b"".join(line + b"\n" for line in (ROOT / name).read_bytes().splitlines())
                for name in CONTENT)
actual = hashlib.sha256(data).hexdigest()
source = (ROOT / "Sources/SanguoLife/LifeHeroTown.swift").read_text()
contract = re.search(r"public enum LifeV12Contract\s*\{.*?contentHash\s*=\s*\"([0-9a-f]{64})\"", source, re.S)
assert contract is not None, "v0.12 rules identity is missing"
assert contract.group(1) == actual, f"v0.12 content hash differs: expected {actual}"
print(f"PASS v0.12 content identity covers {len(CONTENT)} inputs: {actual}")
