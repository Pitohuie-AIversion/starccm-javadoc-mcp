# STAR-CCM+ Javadoc MCP：Codex 自动部署版

基于 [pacoEzq/starccm-javadoc-mcp](https://github.com/pacoEzq/starccm-javadoc-mcp)，上游提交 `45812175dd1b266aa34426ca2a51763782105c51`。保留 BSD-3-Clause 许可证。本版增加 Windows 自动发现、ZIP/JAR 提取、Codex 注册和端到端验证，并修复成员搜索结果缺失 `#` 的问题。

## 图形界面（推荐）

将整个压缩包解压到长期保存、可写的目录，双击 `STAR-CCM-Codex.exe`。请保留同目录下的脚本和 `gui`、`scripts`、`lib` 文件夹，不能只复制 EXE。

右上角的 **English / 中文** 按钮可即时切换界面语言，包含按钮、提示、结果列表和当前运行状态。切换时保留所选文档、路径和后台任务，语言选择在当前窗口内有效。Node、Codex 和 PowerShell 的诊断日志保留原始语言，便于排错。英文界面的“User guide”会打开英文说明。

1. 界面自动检测 Node.js 和 Codex；缺少程序时可在“高级选项”中指定路径。扫描文档不需要这两个程序。
2. 点击“扫描文档”，或先选择安装目录、Javadoc 文件夹、ZIP/JAR。多个版本会分别列出，由你选择；常见位置找不到时可启用全盘扫描。
3. 选中文档后，“仅验证文档与连接”会执行真实 MCP 握手和工具调用，不写 Codex 配置。
4. 点击“验证并接入 Codex”，完成验证、配置备份、注册和核对。成功后重启 Codex，再实际调用 `search_api` 和 `get_doc`。

扫描和环境检测可停止。验证、依赖安装及注册期间暂不允许关闭窗口，以免中断文件写入。操作日志可展开、复制，报告保存在 `%TEMP%\StarccmCodex\ui-runs` 的独立子目录；需要长期保留时请自行复制。压缩包提取的文档保存在软件目录下的 `local-docs`，不放在临时报告目录。

界面使用 Windows 自带的 PowerShell 5.1 / .NET Framework WPF，无需浏览器。执行 MCP 验证仍需 Node.js 20+，接入需 Codex CLI；首次验证会联网安装 Node 依赖。部署后请勿移动软件或文档目录；移动后重新接入。

可直接通过脚本打开界面，也可重新编译启动器和打包：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\gui.ps1
# 直接以英文界面启动
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\gui.ps1 -Language en-US
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-gui.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\package-gui.ps1
```

开发者自检：`powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\gui.ps1 -SelfTest`。它会使用合成文档，在独立 `CODEX_HOME` 中测试真实 Codex 注册，不修改日常使用的配置；需已安装 Node 与 Codex。

## 一条命令部署

解压部署包到准备长期保存的目录，进入该目录，执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy-codex.ps1
```

要求 Windows PowerShell 5.1 或 PowerShell 7、Node.js 20+（建议受支持的 LTS）以及 Codex CLI 或带 CLI 的 Codex 桌面安装。首次安装依赖需要网络。脚本依次识别 PATH 中的 `codex.exe`、`codex.cmd`、`codex.ps1`，也支持 Codex 自带运行时；普通 Node 安装用 `npm ci`，本机 Codex 运行时用锁定的 pnpm 依赖。Node 的目录会加入部署进程的 PATH，让 npm 启动器能找到它，结束后恢复。`Bypass` 仅作用于本次 PowerShell 进程。

脚本依次执行：

1. 搜索 `STARCCM_DOC`、注册表中的 STAR-CCM+/Simcenter 安装位置、各固定磁盘的常见安装目录，以及桌面、下载和文档目录。
2. 区分两种文档：`indexed` 要求两个搜索索引和 `star/common/Simulation.html`；`html-fallback` 要求 `Simulation.html`、`Region.html` 位于 `star/common/`，并有根目录的 `index.html` 或 `overview-summary.html`。扫描报告会标明格式。文件名匹配只是候选发现，后续还会验证内容与 MCP 调用。
3. 检查候选 ZIP/JAR 压缩包中的相同结构。若选中了压缩包，只提取匹配的 Javadoc 子目录至 `local-docs/javadoc-<唯一标识>`。
4. 若有多个候选，列出编号并停止，让你明确选择仿真所用版本；不自动猜“最新版”。
5. 安装依赖，检查索引内容和 Simulation HTML，再实际执行 MCP 握手、工具枚举、完整类名搜索和读取搜索结果。有成员索引时，还测试 Simulation 成员搜索到文档读取的链路。损坏索引会中止部署，不会降级为“没有结果”。
6. 备份 Codex 配置，再通过 `codex mcp add` 注册 `starccm-javadoc`；用 `codex mcp get --json` 核对启用状态、传输方式、命令和参数与测试过的值一致。完成后重启 Codex，再进行会话内调用验收。

中文、空格和单引号路径已经过测试，无需手工复制成无空格目录。请保持部署文件夹和所选文档目录的位置不变；移动后重新执行部署脚本。

相对路径以 PowerShell 当前目录为准，切换目录后也可使用 `-ScanRoots '.\docs'`。npm 风格、直接转发参数的 `.cmd` 启动器已测试 `&`、百分号、`!`、`^`、括号等字符；自行编写且使用 `CALL` 或重新开启 delayed expansion 的包装脚本可能再次解释参数，建议改用原始 `codex.exe` 或 `codex.ps1`。

## 常用参数

```powershell
# 只扫描并生成 discovery-report.json，不安装、不解压、不修改 Codex
.\deploy-codex.ps1 -ListOnly

# 指定自定义安装目录；会递归查找，不必知道 html 在哪一层
.\deploy-codex.ps1 -ScanRoots 'D:\Siemens'

# 多个目录（在 PowerShell 窗口中调用）
.\deploy-codex.ps1 -ScanRoots @('D:\Apps', 'E:\Simulation Software')

# 常见目录找不到时，扫描所有就绪的固定磁盘，耗时可能较长
.\deploy-codex.ps1 -FullScan -ListOnly
.\deploy-codex.ps1 -FullScan -CandidateIndex 0

# 直接指定文档压缩包：识别 ZIP/JAR 内部嵌套的 Javadoc 根目录并提取
.\deploy-codex.ps1 -ScanRoots 'D:\Downloads\star-docs.zip'

# 已知 html 根目录时跳过扫描
.\deploy-codex.ps1 -JavadocRoot 'D:\Siemens\STAR-CCM+\doc\java\html'

# 多个版本时沿用同样的扫描参数并指定报告中的编号
.\deploy-codex.ps1 -ScanRoots 'D:\Siemens' -CandidateIndex 1

# 仅验证并生成 TOML 配置，不写入 Codex
.\deploy-codex.ps1 -JavadocRoot 'D:\ccmp\html' -SkipRegister

# 可指定运行程序、服务名称、解压位置和最大扫描深度
.\deploy-codex.ps1 -ScanRoots 'D:\Siemens' -NodePath 'C:\Program Files\nodejs\node.exe' -CodexPath 'C:\Tools\codex.exe' -ServerName 'starccm-javadoc' -ExtractTo 'D:\ccmp-docs' -MaxDepth 40
```

`-FullScan` 仍跳过 Windows 系统目录、依赖缓存、Git、虚拟环境和重解析点。默认最大深度 30；无权限目录跳过。网络盘、移动盘请用 `-ScanRoots` 明确指定。自动扫描仅检查名称含 doc/help/star/ccmp/client 或位于 Siemens/STAR-CCM+ 安装树的 ZIP/JAR；名字特殊的压缩包请直接传其路径。没有兼容文档时不会注册一个空服务。

## 自动提取的范围

这里的“提取”是识别已安装的 Javadoc，或者从 ZIP/JAR 提取已有 HTML 文档。不会从程序二进制或 class 文件重建官方文档，不会下载 Siemens 专有文档。纯程序 JAR 不会被识别为文档。7z、RAR、CHM、受密码保护的压缩包仍不支持，需要先解压或导出 HTML 文档。这不代表 Siemens 各版本都采用 ZIP/JAR 打包。

旧版或未生成搜索索引的 HTML 文档现在可用：按 `star/` 下的 HTML 文件查找类，并由 `get_doc` 读取。无成员索引时不提供方法名索引搜索，工具响应会明确提示，不会把“索引缺失”说成“API 不存在”。这属于功能降级支持，不能等同于完整方法搜索。程序不会从方法正文猜测 API，也不为所有历史版本的目录布局提供保证。

解压到唯一的新目录，不覆盖原文档；拒绝越界路径，默认最多提取 8 GiB。失败时可能保留部分解压目录供检查，确认不需要后可手动删除。读取文档也会检查真实路径，阻止符号链接绕过目录边界。

## Codex 使用

Codex 的配置是 `~/.codex/config.toml`（设置了 `CODEX_HOME` 时遵循该目录），不是通用客户端的 `mcpServers` JSON。本机注册结果也会保存在 `codex-mcp.generated.toml`。同名服务会更新，其他配置由 Codex CLI 保留；执行前有时间戳备份。

如果注册命令失败、读取配置失败、返回的 JSON 无法解析或配置值不匹配，部署会恢复注册前的配置文件状态。如果检测到注册后又有其他进程修改配置，则保留那些修改并报告备份位置，避免覆盖后续修改。

```powershell
codex mcp get starccm-javadoc
codex mcp list
# 取消注册
codex mcp remove starccm-javadoc
```

在重启后的 Codex 对话中可以说：

> 使用 starccm-javadoc 的 search_api 查找 RegionManager，然后用 get_doc 阅读结果。请根据这套本地版本的文档编写遍历 Region 名称的 Java 宏，并注明查证过的类和方法。

继承方法只按声明类索引；子类搜不到时继续阅读其 Javadoc 的继承成员。每次搜索都会提醒这一限制。支持 `star.common.Simulation` 和 `Simulation.getRegionManager` 这样的限定名，并优先显示完全匹配的类，避免常见类被前 25 条结果截掉。文档查证不能替代宏的编译、运行验证和物理模型检查。

注册成功表示配置已写入且与测试过的命令一致，不代表当前聊天已经加载了工具。重启后应当在 Codex 会话内实际执行 `search_api` 和 `get_doc`，检查返回内容来自你指定的版本。最终验收仍需要你的真实 Siemens 文档；本仓库的合成测试不能替代这一环节。

## 验证与本地文件

```powershell
# 综合回归：合成文档、发现、压缩包提取、越界拒绝、隔离配置中的 Codex 注册
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1

# 成员链接和 Windows junction 越界回归
node .\scripts\regression-test.mjs

# .cmd 特殊字符参数与注册回滚回归
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\arguments.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\registration.ps1

# 使用你的真实文档进行 MCP 端到端验证
node .\scripts\smoke-test.mjs 'D:\ccmp\html'
```

回归测试使用明确标记的合成数据，不是 Siemens 文档。注册测试只改临时 `CODEX_HOME`，并把报告写到临时目录，不污染真实 Codex 配置。覆盖 `codex.cmd` 启动器、无索引旧文档、嵌套 ZIP/JAR、程序 JAR 排除、损坏索引拒绝和失败时保留原配置。部署包不包含 Siemens 文档、用户配置、测试产物或 node_modules；搬到另一台电脑后运行部署命令即可重新发现本机路径。需要自定义报告位置时传 `-ReportDirectory <目录>`。

官方配置说明：[Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。

最近一次检查结果见 `CHECKS.md`。`get_doc` 读取成员链接时返回其所属类的整页文本；当前测试证明页面可读，不代表逐个方法的 HTML 锚点都已验证。
