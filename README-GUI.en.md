# STAR-CCM+ Javadoc MCP — desktop setup for Codex

This Windows application finds your STAR-CCM+ Java API documentation, checks the local MCP server, and registers it with Codex. It extends [pacoEzq/starccm-javadoc-mcp](https://github.com/pacoEzq/starccm-javadoc-mcp), with the BSD-3-Clause license retained.

## Start and choose a language

Extract the **entire ZIP** into a writable folder you intend to keep. Open `STAR-CCM-Codex.exe`. Keep the executable, scripts, `gui`, `scripts`, and `lib` folders together.

Click **English** in the top-right corner to switch the interface to English. Click **中文** to return to Chinese. Buttons, hints, result labels and the current status update immediately; selected documents, paths and running operations remain intact. The choice applies to the current window. Technical output from Node, Codex and PowerShell retains its original language.

To start directly in English:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\gui.ps1 -Language en-US
```

## Connect your documentation

1. The application checks for Node.js and Codex. Use **Advanced options** if you need to supply their paths. Scanning works without either program.
2. Click **Scan documents**, or choose an installation folder, a Javadoc HTML folder, or a ZIP/JAR archive. A blank path searches common locations; a full-drive scan is available when needed.
3. Select documentation matching your installed STAR-CCM+ version. If several versions are found, choose one explicitly.
4. Click **Verify only** to install dependencies and test the actual MCP handshake, tool list, API search and document reading. This does not change Codex configuration.
5. Click **Verify and connect to Codex** to verify, back up the configuration, register the server and check the effective settings. Restart Codex and ask it to call `search_api` and `get_doc` to verify the actual session.

The server is a local Node.js process using MCP over standard input/output. Codex starts it from its saved configuration; you can close this setup application after registration. Do not move the application folder or the selected documentation. If you do, reconnect from the new location.

## Requirements and limits

- Windows with PowerShell 5.1 and .NET Framework WPF. The GUI does not require a browser.
- Node.js 20 or newer for verification and serving documentation; Codex CLI or a desktop installation providing the CLI for registration.
- Internet access for the initial dependency installation.
- Your own STAR-CCM+ Javadoc. Siemens documentation is not included or downloaded.

Indexed documentation supports class and member search. Legacy HTML without a member index supports class search and page reading only. Binary program JARs do not qualify as documentation. ZIP/JAR extraction is supported; encrypted archives, 7z, RAR and CHM are not supported.

The MCP tools query documentation. They do not operate STAR-CCM+, run macros or verify simulation physics. API checks still need to be followed by compilation and testing in your own STAR-CCM+ environment.

## Logs and configuration

Expand **Operation log** for diagnostic output. **Copy log** copies the currently displayed output. **Open report folder** opens the operation's folder under `%TEMP%\StarccmCodex\ui-runs`. Copy reports elsewhere if you need to retain them. Extracted documentation is kept under the application's `local-docs` folder.

Scanning and environment checks can be stopped. Verification and registration temporarily block closing to avoid interrupting installation or configuration changes. External errors are shown as failures, not successful registration.

Codex normally stores settings in `%USERPROFILE%\.codex\config.toml`; a configured `CODEX_HOME` takes precedence. Registration updates the selected MCP server name. Configuration is backed up before writing and restored if registration checks fail, unless a later external change must be preserved.

## Build and test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-gui.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\gui.ps1 -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\package-gui.ps1
```

GUI self-tests use synthetic documentation and an isolated `CODEX_HOME`. They require working Node.js and Codex executables. They do not register synthetic documentation in your everyday configuration. The package builder verifies each archived file against its source before replacing the previous release.

See `CHECKS.md` for test coverage and remaining real-installation validation limits.
