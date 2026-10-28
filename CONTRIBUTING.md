# Contributing to starccm-javadoc-mcp

Thank you for your interest in contributing to **starccm-javadoc-mcp**! This document explains the codebase layout, local testing workflows, and PR guidelines.

---

## 1. Project Architecture

The repository consists of four interoperable layers:

1. **Core MCP Server (`server.mjs`, `lib/`)**:
   - Written in modern JavaScript (ESM) using `@modelcontextprotocol/sdk`.
   - Exposes `search_api` and `get_doc` tools over standard I/O (stdio).
   - Designed to run under Node.js 20+.

2. **Windows Desktop & Automation (`gui/`, `deploy-codex.ps1`, `gui.ps1`)**:
   - `STAR-CCM-Codex.exe`: Lightweight launcher compiled with Windows built-in `csc.exe` (`build-gui.ps1`), requiring zero browser engines.
   - `MainWindow.xaml`: Bilingual (English / Chinese) WPF interface.
   - `deploy-codex.ps1`: Automated Javadoc scanning (fixed disks, registry, ZIP/JAR archives), validation, and atomic registration into Codex CLI.

3. **Python & uv Runner (`pyproject.toml`, `src/starccm_javadoc_mcp/`)**:
   - Provides a Python entrypoint so users can run the MCP server seamlessly with `uvx starccm-javadoc-mcp` or `uv run starccm-javadoc-mcp`.

4. **CI/CD & Packaging (`.github/workflows/`, `package-gui.ps1`)**:
   - Automated testing on Linux & Windows across Node 20/22, PowerShell 5.1/7, and Python/uv.
   - Automated release packaging into portable ZIP bundles with SHA-256 checksums.

---

## 2. Local Development & Testing

### Prerequisites
- **Node.js**: 20.0 or higher
- **PowerShell**: Windows PowerShell 5.1 or PowerShell 7 (on Windows)
- **uv / Python**: Optional, for running via `uvx` / `uv run`

### Running Tests

#### Node.js Regression Tests:
```bash
npm test
# or:
node scripts/regression-test.mjs
```

#### Windows PowerShell & GUI Tests:
```powershell
# Argument passing test across launcher variants:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\arguments.ps1

# Configuration registration & rollback test:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\registration.ps1

# Full packaging & integrity test:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\package-gui.ps1
```

#### Python & uv Tests:
```bash
# Verify uv build & CLI:
uv build
uv run starccm-javadoc-mcp --help
uv run starccm-javadoc-mcp --version
```

---

## 3. Pull Request Guidelines

1. **Branches**: Create a descriptive feature branch (e.g. `feat/xyz` or `fix/abc`) from `main`.
2. **Clean Scope**: Avoid committing generated log files (`*.log`), local test documentation, or temporary IDE files.
3. **Tests**: Ensure existing tests pass before submitting.
4. **Documentation**: If adding new options or changing behaviors, update the corresponding documentation:
   - `README.md`
   - `README-Codex.zh-CN.md` (Chinese guide)
   - `README-GUI.en.md` (English guide)
