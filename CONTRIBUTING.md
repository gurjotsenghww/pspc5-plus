# Contributing to PSPC5 Plus

Thank you for your interest in contributing to **PSPC5 Plus**!

PSPC5 Plus is an open-source PlayStation 5 emulation and compatibility research project written in Zig, licensed under the [GNU General Public License v3.0 or later](LICENSE), and derived from [PS5PCEM](https://github.com/iStark/PS5PCEM).

---

## Code of Conduct & Legal Boundaries

PSPC5 Plus is strictly an interoperability and systems research project.

To protect the project, its maintainers, and contributors:
- **DO NOT** contribute copyrighted game binaries, decrypted package dumps, or commercial game assets.
- **DO NOT** contribute leaked Sony proprietary firmware, SDK headers, or console cryptographic keys.
- **DO NOT** contribute DRM bypass mechanisms designed to facilitate software piracy.
- All code contributed must be your own original work or compatible with the GNU General Public License v3.0 or later.
- Preserve all existing copyright notices and upstream attributions.

---

## Development Environment

### Requirements

- **Zig 0.16.0**: Required compiler toolchain. Verify with `zig version`.
- **Vulkan 1.2+**: Graphics driver supporting Vulkan 1.2 or higher (Vulkan 1.3/1.4 recommended).
- **Target OS**: Windows 10/11 x86-64-v3 (AVX2, BMI2, FMA).

### Building and Testing

Always ensure the codebase compiles cleanly and passes all tests before submitting changes:

```sh
# Compile every module without running tests
zig build check

# Run the complete test suite
zig build test

# Run a specific filtered test
zig test src/rdna2/root.zig --test-filter "your_test_name"
```

---

## Git Workflow & Branching

- **`main`**: Stable default branch.
- **`development`**: Active integration and development branch.
- Feature branches should branch from `development`.

### Commit Guidelines

- Write clear, concise commit messages explaining *what* was changed and *why*.
- Include genuine author attribution.
- If Antigravity or pair-programming tools assist in creating code, ensure appropriate co-authorship attribution without inventing fictitious email addresses.

---

## Submitting Pull Requests

1. Fork the repository on GitHub: `https://github.com/gurjotsenghww/pspc5-plus`.
2. Create a topic branch from `development`.
3. Add unit tests for any new functionality, instruction lowerings, or bug fixes.
4. Verify all tests pass locally.
5. Submit a Pull Request targeting `development`.

---

## Core Team & Contributors

- **Gurjotpal Singh** ([@gurjotsenghww](https://github.com/gurjotsenghww)) — Project Lead, Architecture & Development
- **Antigravity** (Google DeepMind) — Core System Engineering, Diagnostics & Verification Contributor
- **Artur Strazewicz** ([@iStark](https://github.com/iStark)) — Upstream Creator (PS5PCEM)

