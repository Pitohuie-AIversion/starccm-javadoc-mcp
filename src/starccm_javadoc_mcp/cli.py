"""Command-line interface for starccm-javadoc-mcp."""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

__version__ = "1.0.0"


def find_node() -> str | None:
    """Find a usable node binary."""
    node_path = shutil.which("node")
    if node_path:
        return node_path

    if platform.system() == "Windows":
        candidates = [
            Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "nodejs" / "node.exe",
            Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "node" / "node.exe",
            Path.home() / ".cache" / "codex-runtimes" / "codex-primary-runtime" / "dependencies" / "node" / "bin" / "node.exe",
        ]
        for candidate in candidates:
            if candidate.is_file():
                return str(candidate)

    return None


def find_server_mjs() -> Path | None:
    """Locate the server.mjs entrypoint."""
    # 1. Package directory or repo root (parents[2] from src/starccm_javadoc_mcp/cli.py)
    here = Path(__file__).resolve()
    repo_root = here.parents[2]
    if (repo_root / "server.mjs").is_file():
        return repo_root / "server.mjs"

    # 2. Same directory as package
    pkg_dir = here.parent
    if (pkg_dir / "server.mjs").is_file():
        return pkg_dir / "server.mjs"

    # 3. sys.prefix share directory (when installed via wheel)
    shared = Path(sys.prefix) / "share" / "starccm-javadoc-mcp" / "server.mjs"
    if shared.is_file():
        return shared

    # 4. Current working directory
    cwd_server = Path.cwd() / "server.mjs"
    if cwd_server.is_file():
        return cwd_server

    return None


def run_gui(server_dir: Path) -> int:
    """Launch the Windows GUI."""
    if platform.system() != "Windows":
        sys.stderr.write("Error: The graphical setup launcher is only available on Windows.\n")
        return 1

    exe_path = server_dir / "STAR-CCM-Codex.exe"
    if exe_path.is_file():
        return subprocess.call([str(exe_path)])

    gui_script = server_dir / "gui.ps1"
    if gui_script.is_file():
        return subprocess.call([
            "powershell.exe",
            "-NoProfile",
            "-STA",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(gui_script),
        ])

    sys.stderr.write("Error: GUI launcher files (STAR-CCM-Codex.exe or gui.ps1) not found.\n")
    return 1


def run_deploy(server_dir: Path, extra_args: list[str]) -> int:
    """Run deploy-codex.ps1 on Windows."""
    if platform.system() != "Windows":
        sys.stderr.write("Error: deploy-codex.ps1 is only available on Windows.\n")
        return 1

    deploy_script = server_dir / "deploy-codex.ps1"
    if not deploy_script.is_file():
        sys.stderr.write("Error: deploy-codex.ps1 was not found.\n")
        return 1

    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(deploy_script),
        *extra_args,
    ]
    return subprocess.call(cmd)


def main(argv: list[str] | None = None) -> int:
    """Main CLI entrypoint for running the MCP server or deployment."""
    if argv is None:
        argv = sys.argv[1:]

    parser = argparse.ArgumentParser(
        prog="starccm-javadoc-mcp",
        description="STAR-CCM+ Java API Documentation MCP Server",
        add_help=False,
    )
    parser.add_argument(
        "-h", "--help", action="store_true", help="Show this help message and exit."
    )
    parser.add_argument(
        "-v", "--version", action="store_true", help="Show program's version number and exit."
    )
    parser.add_argument(
        "--gui", action="store_true", help="Launch the Windows GUI configuration tool."
    )
    parser.add_argument(
        "--deploy", action="store_true", help="Run the automated Codex deployment script on Windows."
    )

    args, unknown = parser.parse_known_args(argv)

    if args.version:
        print(f"starccm-javadoc-mcp {__version__}")
        return 0

    if args.help:
        parser.print_help()
        print("\nEnvironment Variables:")
        print("  STARCCM_DOC    Path to the STAR-CCM+ Javadoc root directory.")
        print("\nMCP Usage:")
        print("  Run directly (stdio MCP server):")
        print("    uvx starccm-javadoc-mcp")
        print("    python -m starccm_javadoc_mcp")
        return 0

    server_file = find_server_mjs()
    if not server_file:
        sys.stderr.write(
            "Error: server.mjs could not be located. "
            "Please ensure you have cloned the repository or installed the complete package.\n"
        )
        return 1

    server_dir = server_file.parent

    if args.gui:
        return run_gui(server_dir)

    if args.deploy:
        return run_deploy(server_dir, unknown)

    node = find_node()
    if not node:
        sys.stderr.write(
            "Error: Node.js (>= 20) is required to run the starccm-javadoc-mcp server.\n"
            "Please install Node.js from https://nodejs.org or ensure 'node' is in PATH.\n"
            "错误：运行 starccm-javadoc-mcp 服务需要 Node.js (>= 20)，请先安装 Node.js。\n"
        )
        return 1

    # Default: launch node server.mjs as an stdio MCP server
    cmd = [node, str(server_file), *unknown]
    try:
        # In stdio MCP servers, stdin/stdout/stderr must be inherited directly
        proc = subprocess.run(cmd)
        return proc.returncode
    except KeyboardInterrupt:
        return 130
