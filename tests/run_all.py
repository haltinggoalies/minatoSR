"""Runs every tests/test_*.py against zig-out/bin/gameserver.exe (build first). Exits 1 if any fails."""
import glob
import os
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
failed = []
for path in sorted(glob.glob(os.path.join(here, "test_*.py"))):
    name = os.path.basename(path)
    print(f"=== {name}", flush=True)
    if subprocess.run([sys.executable, path]).returncode != 0:
        failed.append(name)
print("failed:", ", ".join(failed) if failed else "none")
sys.exit(1 if failed else 0)
