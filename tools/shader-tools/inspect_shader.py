#!/usr/bin/env python3
"""
Shader Inspection & Disassembly Helper for PSPC5 Plus.
Interfaces with rdna2-disasm and shader-dump binaries to inspect
RDNA2 shader binaries, examine CFG structure, and inspect emitted SPIR-V.
"""

import sys
import subprocess
import os
import shutil

def find_binary(name: str) -> str:
    # Check zig-out/bin first
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    local_path = os.path.join(repo_root, "zig-out", "bin", f"{name}.exe" if sys.platform == "win32" else name)
    if os.path.exists(local_path):
        return local_path
    path = shutil.which(name)
    if path:
        return path
    return local_path

def main():
    if len(sys.argv) < 2:
        print("Usage: inspect_shader.py <shader.bin> [--cfg] [--check-fragment] [--write-spv out.spv]")
        sys.exit(1)

    shader_path = sys.argv[1]
    if not os.path.exists(shader_path):
        print(f"Error: shader file '{shader_path}' not found.", file=sys.stderr)
        sys.exit(1)

    disasm_exe = find_binary("rdna2-disasm")
    if not os.path.exists(disasm_exe):
        print(f"rdna2-disasm not found at {disasm_exe}. Please build it first: `zig build`", file=sys.stderr)
        sys.exit(1)

    cmd = [disasm_exe] + sys.argv[2:] + [shader_path]
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd)
    sys.exit(result.returncode)

if __name__ == "__main__":
    main()
