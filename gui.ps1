#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SelfTest, [string]$ScreenshotPath, [ValidateSet('zh-CN','en-US')][string]$Language = 'zh-CN')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
$script:repoRoot = $PSScriptRoot
Add-Type -Path (Join-Path $PSScriptRoot 'gui/ProcessRunner.cs')
$xml = [xml][IO.File]::ReadAllText((Join-Path $PSScriptRoot 'gui/MainWindow.xaml'), [Text.Encoding]::UTF8)
$reader = New-Object Xml.XmlNodeReader($xml)
$script:window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Dispose()
$script:ui = @{}
$script:language = $Language
$script:translations = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'gui/strings.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$script:localizedBindings = @{}
$script:missingTranslations = New-Object 'System.Collections.Generic.HashSet[string]'
$ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
foreach ($element in $xml.SelectNodes('//*[@x:Name and not(ancestor::*[local-name()="ControlTemplate"])]', $ns)) {
    $name = $element.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $ui[$name] = $window.FindName($name)
    if (-not $ui[$name]) { throw "Missing named UI element: $name" }
}
$script:rows = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$ui.CandidatesGrid.ItemsSource = $rows
$script:active = $null
$script:lastResult = $null
$script:lastReport = $null
$script:testStage = 0
$script:testError = $null
$script:operationSucceeded = $false
$script:logWriteFailed = $false
$script:runRoot = Join-Path ([IO.Path]::GetTempPath()) 'StarccmCodex/ui-runs'
$script:powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'

function T([string]$Key, [object[]]$Values = @()) {
    $entry = $script:translations.PSObject.Properties[$Key]
    if (-not $entry -and $Key -match '[\u4e00-\u9fff]') { [void]$script:missingTranslations.Add($Key) }
    $text = if ($script:language -eq 'en-US' -and $entry) { [string]$entry.Value } else { $Key }
    if ($Values.Count -gt 0) { return [string]::Format($text, $Values) }
    return $text
}

function Set-UiText([string]$Name, [string]$Key, [object[]]$Values = @(), [string]$Property = 'Text') {
    $script:localizedBindings[$Name + '.' + $Property] = @{ Target = $ui[$Name]; Property = $Property; Key = $Key; Values = $Values }
    $ui[$Name].$Property = T $Key $Values
}

function Set-Language([string]$Value) {
    $script:language = $Value
    foreach ($binding in @($script:localizedBindings.Values)) {
        $binding.Target.($binding.Property) = T $binding.Key $binding.Values
    }
    foreach ($row in $rows) {
        $row.FormatLabel = T $(if ($row.Candidate.Format -eq 'indexed') { '完整搜索索引' } else { '旧版 HTML' })
        $row.SourceLabel = T $(if ($row.Candidate.Archive) { '压缩包' } else { '文件夹' })
    }
    $ui.CandidatesGrid.Items.Refresh()
    $ui.LanguageButton.Content = if ($Value -eq 'en-US') { '中文' } else { 'English' }
}

foreach ($element in $xml.SelectNodes('//*[@x:Name and not(ancestor::*[local-name()="ControlTemplate"])]', $ns)) {
    $name = $element.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    foreach ($property in @('Text','Content','Header','Title','ToolTip')) {
        $value = $element.GetAttribute($property)
        if ($value -match '[\u4e00-\u9fff]') { Set-UiText -Name $name -Key $value -Property $property }
    }
}

function Add-Log([string]$Text) {
    if (-not $Text) { return }
    $ui.LogBox.AppendText($Text)
    if ($ui.LogBox.Text.Length -gt 200000) { $ui.LogBox.Text = $ui.LogBox.Text.Substring($ui.LogBox.Text.Length - 150000) }
    $ui.LogBox.ScrollToEnd()
    if ($script:lastReport -and -not $script:logWriteFailed) {
        try { [IO.File]::AppendAllText((Join-Path $script:lastReport 'interface.log'), $Text, (New-Object Text.UTF8Encoding($false))) }
        catch {
            $script:logWriteFailed = $true
            $ui.LogBox.AppendText("`r`n" + (T '日志文件无法保存；可使用“复制日志”保留当前输出。') + "`r`n" + $_.Exception.Message + "`r`n")
        }
    }
}

function Set-Status([string]$Title, [string]$Detail, [bool]$Failed = $false) {
    Set-UiText 'StatusText' $Title
    Set-UiText 'StatusDetail' $Detail
    $ui.StatusText.Foreground = if ($Failed) { [Windows.Media.Brushes]::Firebrick } else { [Windows.Media.BrushConverter]::new().ConvertFromString('#172B3A') }
}

function Update-Controls {
    $busy = $null -ne $script:active
    foreach ($name in @('SourceBox','FolderButton','ArchiveButton','ScanButton','FullScanCheck','EnvironmentButton','NodeBox','CodexBox','ServerNameBox','NodeBrowseButton','CodexBrowseButton','CandidatesGrid')) { $ui[$name].IsEnabled = -not $busy }
    $selected = $null -ne $ui.CandidatesGrid.SelectedItem
    $ui.VerifyButton.IsEnabled = -not $busy -and $selected
    $ui.DeployButton.IsEnabled = -not $busy -and $selected
    $ui.CancelButton.Visibility = if ($busy -and $script:active.Action -in @('scan','environment')) { 'Visible' } else { 'Collapsed' }
    Set-UiText -Name 'CancelButton' -Property 'Content' -Key $(if ($busy -and $script:active.Action -eq 'environment') { '停止检查' } else { '停止扫描' })
    $ui.Progress.IsIndeterminate = $busy
    $ui.OpenReportButton.IsEnabled = $null -ne $script:lastReport
    $ui.EmptyPanel.Visibility = if ($rows.Count -eq 0) { 'Visible' } else { 'Collapsed' }
}

function Reset-Selection {
    if ($script:active) { return }
    $rows.Clear()
    $ui.CandidatesGrid.SelectedItem = $null
    Set-UiText 'CountLabel' '尚未扫描'
    Set-UiText 'EmptyTitle' '先扫描，再选择文档'
    Set-UiText 'EmptyHint' '搜索范围已更新，请重新扫描。'
    Set-UiText 'SelectionHint' '选择文档后，可先验证，再接入 Codex。'
    $script:lastResult = $null
    $script:operationSucceeded = $false
    Set-Status '准备扫描' '路径留空时搜索常见安装位置。'
    Update-Controls
}

function Update-SelectionHint {
    $row = $ui.CandidatesGrid.SelectedItem
    if (-not $script:active -and $script:lastResult.action -in @('verify','deploy')) {
        $script:lastResult = $null
        $script:operationSucceeded = $false
        Set-Status $(if ($row) { '已选择文档' } else { '请选择文档' }) '可先验证文档，或验证并接入 Codex。'
    }
    if ($row) {
        Set-UiText 'SelectionHint' $(if ($row.Candidate.Format -eq 'html-fallback') { '旧版文档：支持查类和读页面；没有成员索引时不能按方法名搜索。' } else { '已选择带搜索索引的文档。请确认版本与你的仿真一致。' })
    } else { Set-UiText 'SelectionHint' '选择文档后，可先验证，再接入 Codex。' }
    Update-Controls
}

function Choose-File([string]$Filter, [string]$Target) {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = T $Filter
    if ($dialog.ShowDialog($window)) { $ui[$Target].Text = $dialog.FileName }
}

function Start-Operation([string]$Action) {
    if ($script:active) { return }
    if ($Action -in @('verify','deploy') -and -not $ui.CandidatesGrid.SelectedItem) { return }
    try {
        if ($Action -in @('verify','deploy') -and $ui.ServerNameBox.Text -notmatch '^[A-Za-z0-9_-]+$') { throw '服务名称只能包含英文字母、数字、下划线和连字符。' }
        $id = [guid]::NewGuid().ToString('N')
        $directory = Join-Path $script:runRoot $id
        [void][IO.Directory]::CreateDirectory($directory)
        $requestPath = Join-Path $directory 'request.json'
        $resultPath = Join-Path $directory 'result.json'
        $selected = if ($ui.CandidatesGrid.SelectedItem) { $ui.CandidatesGrid.SelectedItem.Candidate } else { $null }
        $request = @{
            action = $Action; scanRoot = $ui.SourceBox.Text.Trim(); fullScan = [bool]$ui.FullScanCheck.IsChecked;
            selected = $selected; nodePath = $ui.NodeBox.Text.Trim(); codexPath = $ui.CodexBox.Text.Trim();
            serverName = $ui.ServerNameBox.Text.Trim(); reportDirectory = $directory
        }
        [IO.File]::WriteAllText($requestPath, (ConvertTo-Json $request -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $script:lastReport = $directory
        $script:lastResult = $null
        $script:operationSucceeded = $false
        $script:logWriteFailed = $false
        $ui.LogBox.Clear()
        if ($Action -eq 'scan') { $rows.Clear(); Set-UiText 'CountLabel' '正在搜索'; Set-UiText 'EmptyTitle' '正在查找文档…'; Set-UiText 'EmptyHint' '请稍候，可以随时停止扫描。' }
        $label = switch ($Action) { 'environment' {'检查运行环境'} 'scan' {'扫描本地文档'} 'verify' {'验证文档与 MCP 连接'} 'deploy' {'验证并接入 Codex'} }
        Set-Status $label $(if ($Action -in @('verify','deploy')) { '正在执行后台任务，请勿关闭窗口。详细输出见下方日志。' } else { '后台运行中，窗口会持续更新。' })
        Add-Log ((Get-Date -Format 'HH:mm:ss') + '  ' + (T $label) + "`r`n")
        $process = New-Object StarGuiProcess($script:powershell, $script:repoRoot, (Join-Path $script:repoRoot 'scripts/gui-worker.ps1'), $requestPath, $resultPath)
        $script:active = [pscustomobject]@{ Id = $id; Action = $Action; Process = $process; ResultPath = $resultPath }
        Update-Controls
    } catch {
        $script:active = $null
        $script:lastResult = $null
        $script:operationSucceeded = $false
        Set-Status '无法启动操作' $_.Exception.Message $true
        Add-Log ($_.Exception.Message + "`r`n")
        Update-Controls
    }
}

function Apply-Result($Operation, $Result, [int]$ExitCode) {
    $script:operationSucceeded = $false
    if ($ExitCode -ne 0 -or $Result.ok -isnot [bool] -or -not $Result.ok -or $Result.action -ne $Operation.Action) {
        $message = if ($Result.error) { [string]$Result.error } else { T '后台任务未成功完成（退出码 {0}）。请查看日志。' @($ExitCode) }
        Set-Status '操作未完成' $message $true
        if (-not $Result.error) { Set-UiText 'StatusDetail' '后台任务未成功完成（退出码 {0}）。请查看日志。' @($ExitCode) }
        Add-Log ($message + "`r`n")
        return
    }
    $script:operationSucceeded = $true
    $script:lastResult = $Result
    switch ($Operation.Action) {
        'environment' {
            if ($Result.nodeReady) { Set-UiText 'NodeStatus' '已就绪 · {0}' @($Result.nodeVersion) } else { Set-UiText 'NodeStatus' '未找到可用 Node.js' }
            if ($Result.codexReady) { Set-UiText 'CodexStatus' '已找到 · {0}' @([IO.Path]::GetFileName($Result.codexPath)) } else { Set-UiText 'CodexStatus' '未找到 Codex' }
            $ui.NodeStatus.ToolTip = $Result.nodePath
            $ui.CodexStatus.ToolTip = $Result.codexPath
            Set-Status '环境检查完成' $(if ($Result.nodeReady -and $Result.codexReady) { '可以开始扫描文档。' } else { '仍可扫描文档；在高级选项中指定缺少的程序路径，再刷新环境。' })
            if ($Result.errors) { Add-Log (($Result.errors -join "`r`n") + "`r`n") }
        }
        'scan' {
            foreach ($candidate in @($Result.candidates)) {
                if (-not $candidate) { continue }
                $location = if ($candidate.Archive) { $candidate.Archive + '  /  ' + $candidate.Prefix } else { $candidate.Root }
                $rows.Add([pscustomobject]@{ Candidate = $candidate; FormatLabel = (T $(if ($candidate.Format -eq 'indexed') {'完整搜索索引'} else {'旧版 HTML'})); SourceLabel = (T $(if ($candidate.Archive) {'压缩包'} else {'文件夹'})); Location = $location })
            }
            Set-UiText 'CountLabel' '发现 {0} 处文档' @($rows.Count)
            if ($rows.Count -eq 0) {
                Set-UiText 'EmptyTitle' '没有找到兼容文档'
                Set-UiText 'EmptyHint' '尝试选择安装目录、文档压缩包，或启用全盘扫描。'
                Set-Status '扫描完成，未发现文档' '请确认已安装 Java API 文档；程序 JAR 不等于 Javadoc。'
            } else {
                if ($rows.Count -eq 1) { $ui.CandidatesGrid.SelectedIndex = 0 }
                Set-Status '扫描完成' '选择与你的仿真版本对应的文档，再进行验证或接入。'
            }
        }
        'verify' { Set-Status '文档与 MCP 测试通过' '验证未写入 Codex 配置。现在可以点击“验证并接入 Codex”。' }
        'deploy' { Set-Status 'Codex 配置已写入并核对' '请重启 Codex，再让它调用 search_api 和 get_doc 完成会话验收。' }
    }
}

function Stop-Operation {
    if (-not $script:active -or $script:active.Action -notin @('scan','environment')) { return }
    $operation = $script:active
    $script:active = $null
    $operation.Process.Stop()
    Add-Log ($operation.Process.Drain())
    $operation.Process.Dispose()
    if ($operation.Action -eq 'scan') {
        Set-Status '操作已停止' '可以调整范围后重新扫描。'
        Set-UiText 'CountLabel' '扫描已停止'
        Set-UiText 'EmptyTitle' '扫描已停止'
        Set-UiText 'EmptyHint' '调整目录可缩小扫描范围。'
    } else {
        Set-UiText 'NodeStatus' '检查已停止'
        Set-UiText 'CodexStatus' '检查已停止'
        Set-Status '环境检查已停止' '仍可扫描文档，或点击“刷新环境”重新检查。'
    }
    Update-Controls
}

function Save-Preview([string]$Path) {
    $size = New-Object Windows.Size($window.Width, $window.Height)
    $window.Content.Measure($size)
    $window.Content.Arrange((New-Object Windows.Rect(0, 0, $size.Width, $size.Height)))
    $window.Content.UpdateLayout()
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$size.Width, [int]$size.Height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $background = New-Object Windows.Media.DrawingVisual
    $drawing = $background.RenderOpen()
    $drawing.DrawRectangle($window.Background, $null, (New-Object Windows.Rect(0, 0, $size.Width, $size.Height)))
    $drawing.Close()
    $bitmap.Render($background)
    $bitmap.Render($window.Content)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($Path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

$ui.LanguageButton.Add_Click({ Set-Language $(if ($script:language -eq 'zh-CN') { 'en-US' } else { 'zh-CN' }) })
$ui.FolderButton.Add_Click({ $dialog = New-Object Windows.Forms.FolderBrowserDialog; $dialog.Description = T '选择 STAR-CCM+ 安装目录或 Javadoc 文件夹'; try { if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $ui.SourceBox.Text = $dialog.SelectedPath } } finally { $dialog.Dispose() } })
$ui.ArchiveButton.Add_Click({ Choose-File 'Javadoc 压缩包 (*.zip;*.jar)|*.zip;*.jar' 'SourceBox' })
$ui.NodeBrowseButton.Add_Click({ Choose-File 'Node.js (node.exe)|node.exe|程序 (*.exe)|*.exe' 'NodeBox' })
$ui.CodexBrowseButton.Add_Click({ Choose-File 'Codex 启动器 (*.exe;*.cmd;*.ps1)|*.exe;*.cmd;*.ps1' 'CodexBox' })
$ui.SourceBox.Add_TextChanged({ Reset-Selection })
$ui.FullScanCheck.Add_Checked({ Reset-Selection }); $ui.FullScanCheck.Add_Unchecked({ Reset-Selection })
foreach ($box in @($ui.NodeBox, $ui.CodexBox, $ui.ServerNameBox)) { $box.Add_TextChanged({ if (-not $script:active) { $script:lastResult = $null; $script:operationSucceeded = $false; Set-Status '设置已更新' '请刷新环境，或重新验证所选文档。' } }) }
$ui.CandidatesGrid.Add_SelectionChanged({ Update-SelectionHint })
$ui.ScanButton.Add_Click({ Start-Operation 'scan' })
$ui.EnvironmentButton.Add_Click({ Start-Operation 'environment' })
$ui.VerifyButton.Add_Click({ Start-Operation 'verify' })
$ui.DeployButton.Add_Click({ Start-Operation 'deploy' })
$ui.CancelButton.Add_Click({ Stop-Operation })
$ui.CopyLogButton.Add_Click({ try { [Windows.Clipboard]::SetText($ui.LogBox.Text) } catch { Set-Status '无法复制日志' '剪贴板暂时被占用，请稍后重试。' $true } })
$ui.OpenReportButton.Add_Click({
    if ($script:lastReport) {
        try {
            if (-not (Test-Path -LiteralPath $script:lastReport -PathType Container)) { Set-Status '无法打开报告目录' '报告目录已不存在；可复制界面中保留的日志。' $true; return }
            $info = New-Object Diagnostics.ProcessStartInfo($script:lastReport)
            $info.UseShellExecute = $true
            [void][Diagnostics.Process]::Start($info)
        } catch { Set-Status '无法打开报告目录' $_.Exception.Message $true }
    }
})
$ui.HelpButton.Add_Click({
    $helpFile = Join-Path $script:repoRoot $(if ($script:language -eq 'en-US') { 'README-GUI.en.md' } else { 'README-Codex.zh-CN.md' })
    $info = New-Object Diagnostics.ProcessStartInfo($helpFile)
    $info.UseShellExecute = $true
    try { [void][Diagnostics.Process]::Start($info) } catch { Set-Status '说明文件' $helpFile }
})
$window.Add_Closing({ param($sender, $eventArgs) if ($script:active -and $script:active.Action -in @('verify','deploy')) { $eventArgs.Cancel = $true; Set-UiText 'StatusDetail' '验证或配置写入尚未结束，请稍候再关闭窗口。'; return }; Stop-Operation })
$script:timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(180)
$timer.Add_Tick({
    try {
        if ($script:active) {
            $operation = $script:active
            Add-Log ($operation.Process.Drain())
            if ($operation.Process.HasExited) {
                $code = $operation.Process.ExitCode
                Add-Log ($operation.Process.Drain())
                $operation.Process.Dispose()
                $script:active = $null
                try {
                    if (-not (Test-Path -LiteralPath $operation.ResultPath)) { throw '后台任务没有返回结果，请检查日志。' }
                    $result = [IO.File]::ReadAllText($operation.ResultPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
                    Apply-Result $operation $result $code
                } catch { Set-Status '操作未完成' $_.Exception.Message $true; Add-Log ($_.Exception.Message + "`r`n") }
                Update-Controls
            }
        }
        if ($SelfTest -and -not $script:active) { Invoke-SelfTestStep }
    } catch {
        if ($SelfTest) { $script:testError = $_; $script:testFrame.Continue = $false }
        else { Set-Status '界面遇到错误' $_.Exception.Message $true }
    }
})

function Invoke-SelfTestStep {
    switch ($script:testStage) {
        0 {
            if ($ScreenshotPath) { Save-Preview $ScreenshotPath }
            if (-not $script:operationSucceeded) { throw ('GUI environment workflow failed: ' + $ui.LogBox.Text) }
            Set-Language 'en-US'
            if ($ui.ScanButton.Content -ne 'Scan documents' -or $ui.StatusText.Text -ne 'Environment check complete') { throw 'English static/status translation failed.' }
            if ($ScreenshotPath) { Save-Preview ([IO.Path]::Combine([IO.Path]::GetDirectoryName($ScreenshotPath), [IO.Path]::GetFileNameWithoutExtension($ScreenshotPath) + '-en.png')) }
            Set-Language 'zh-CN'
            $script:fixture = Join-Path $env:TEMP ('starccm-gui-smoke-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory((Join-Path $script:fixture 'star/common'))
            [IO.File]::WriteAllText((Join-Path $script:fixture 'type-search-index.js'), 'typeSearchIndex=[{"p":"star.common","l":"Simulation"}];')
            [IO.File]::WriteAllText((Join-Path $script:fixture 'member-search-index.js'), 'memberSearchIndex=[{"p":"star.common","c":"Simulation","l":"getRegionManager()"}];')
            [IO.File]::WriteAllText((Join-Path $script:fixture 'star/common/Simulation.html'), '<html>Simulation getRegionManager()</html>')
            $script:testConfigHome = Join-Path $script:fixture 'isolated-codex'
            [void][IO.Directory]::CreateDirectory($script:testConfigHome)
            $script:savedConfigHome = $env:CODEX_HOME
            $env:CODEX_HOME = $script:testConfigHome
            $ui.SourceBox.Text = $script:fixture
            if ($ui.DeployButton.IsEnabled) { throw 'Deploy must be disabled until a document is selected.' }
            $script:testStage = 1
            $ui.ScanButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        }
        1 {
            if (-not $script:operationSucceeded -or $rows.Count -ne 1 -or -not $ui.VerifyButton.IsEnabled) { throw 'GUI scan/selection workflow failed.' }
            $previousSelection = $ui.CandidatesGrid.SelectedItem
            $previousLog = $ui.LogBox.Text
            $ui.LanguageButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            if ($rows[0].FormatLabel -ne 'Full search index' -or $ui.CountLabel.Text -ne 'Found 1 documentation location(s)' -or $ui.CandidatesGrid.SelectedItem -ne $previousSelection -or $ui.LogBox.Text -ne $previousLog) { throw 'Language switch changed selection/logs or did not translate results.' }
            $script:testStage = 2
            $ui.VerifyButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            if ($ui.CancelButton.Visibility -ne 'Collapsed') { throw 'Verify must not be force-cancellable.' }
            $previousId = $script:active.Id
            $ui.LanguageButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            if ($script:active.Id -ne $previousId -or $ui.VerifyButton.IsEnabled -or $ui.StatusText.Text -ne '验证文档与 MCP 连接') { throw 'Language switching interrupted or unlocked an active operation.' }
            $window.Close()
            if (-not $window.IsVisible) { throw 'Closing must be blocked while verification is running.' }
        }
        2 {
            if (-not $script:operationSucceeded -or -not $script:lastResult.verified -or $script:lastResult.registered) { throw 'GUI verification did not complete without registration.' }
            Set-Language 'en-US'
            if (-not $script:operationSucceeded -or -not $script:lastResult.verified -or $ui.StatusText.Text -ne 'Documentation and MCP checks passed') { throw 'Language switch invalidated verified state.' }
            if (Test-Path -LiteralPath (Join-Path $script:testConfigHome 'config.toml')) { throw 'Verify wrote Codex config.' }
            $script:testStage = 3
            $ui.DeployButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        }
        3 {
            if (-not $script:operationSucceeded -or -not $script:lastResult.registered) { throw ('GUI isolated deployment failed: ' + $ui.LogBox.Text) }
            if (-not (Test-Path -LiteralPath (Join-Path $script:testConfigHome 'config.toml'))) { throw 'Deployment did not produce isolated configuration.' }
            $ui.CandidatesGrid.SelectedIndex = -1
            if ($script:lastResult -or $script:operationSucceeded) { throw 'Changing selection retained a stale success.' }
            if ($ui.StatusText.Text -ne 'Select documentation') { throw 'Deselection retained a misleading success status.' }
            $empty = Join-Path $script:fixture 'empty'
            [void][IO.Directory]::CreateDirectory($empty)
            $ui.SourceBox.Text = $empty
            if ($rows.Count -ne 0 -or $ui.DeployButton.IsEnabled) { throw 'Changing input did not invalidate the previous selection.' }
            $script:testStage = 4
            Start-Operation 'scan'
        }
        4 {
            if (-not $script:operationSucceeded -or $rows.Count -ne 0 -or $ui.DeployButton.IsEnabled) { throw 'Empty-result workflow failed.' }
            $script:testStage = 5
            Start-Operation 'scan'
            Stop-Operation
            if ($script:active) { throw 'Cancellation left an active operation.' }
            Apply-Result ([pscustomobject]@{Action='scan'}) ([pscustomobject]@{ok=$false;error='Expected test error';action='scan'}) 1
            if ($ui.StatusText.Text -ne (T '操作未完成')) { throw 'Error results were treated as success.' }
            Set-Language 'en-US'
            if ($ui.StatusText.Text -ne 'Operation failed') { throw 'Failure status did not translate.' }
            $savedReport = $script:lastReport
            $script:lastReport = Join-Path $script:fixture 'unavailable-report'
            $script:logWriteFailed = $false
            Add-Log "Expected logging failure; UI must stay responsive.`r`n"
            if (-not $script:logWriteFailed) { throw 'Log failure regression did not execute.' }
            $ui.OpenReportButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            if ($ui.StatusText.Text -ne 'Cannot open report folder') { throw 'Missing report folder did not produce a usable error.' }
            $script:lastReport = $savedReport
            $script:logWriteFailed = $false
            $window.Width = $window.MinWidth
            $window.Height = $window.MinHeight
            $window.FindName('AdvancedExpander').IsExpanded = $true
            $window.FindName('LogExpander').IsExpanded = $true
            $window.UpdateLayout()
            $body = $window.FindName('BodyScroll')
            $bodyBottom = $body.TranslatePoint((New-Object Windows.Point(0, $body.ActualHeight)), $window.Content).Y
            $footerTop = $ui.StatusText.TranslatePoint((New-Object Windows.Point(0, 0)), $window.Content).Y
            if ($bodyBottom -gt $footerTop -or $body.ScrollableHeight -le 0) { throw 'Expanded settings overlap the footer or cannot be scrolled.' }
            $body.ScrollToBottom()
            $window.UpdateLayout()
            if ($ScreenshotPath) { Save-Preview ([IO.Path]::Combine([IO.Path]::GetDirectoryName($ScreenshotPath), [IO.Path]::GetFileNameWithoutExtension($ScreenshotPath) + '-en-compact.png')) }
            if ($script:missingTranslations.Count -gt 0) { throw ('Missing UI translations: ' + ($script:missingTranslations -join '; ')) }
            $script:testFrame.Continue = $false
        }
    }
}

Set-Language $Language
Update-Controls
$timer.Start()
try {
    if ($SelfTest) {
        $window.WindowStartupLocation = 'Manual'
        $window.Left = -20000
        $window.Top = 0
        $window.ShowInTaskbar = $false
        $window.ShowActivated = $false
        $window.Show()
        $script:testFrame = New-Object Windows.Threading.DispatcherFrame
        Start-Operation 'environment'
        [Windows.Threading.Dispatcher]::PushFrame($script:testFrame)
        if ($script:testError) { throw $script:testError }
        Write-Output 'PASS: bilingual WPF UI, language switching while busy, selection/log preservation, scan, MCP verification, isolated Codex deployment, close protection, stale-selection reset, empty results, cancellation, failure display, unavailable logs/reports and minimum-window scrolling.'
    } else {
        $window.Height = [Math]::Min($window.Height, [Math]::Max($window.MinHeight, [Windows.SystemParameters]::WorkArea.Height - 24))
        $window.Width = [Math]::Min($window.Width, [Math]::Max($window.MinWidth, [Windows.SystemParameters]::WorkArea.Width - 24))
        $window.Add_ContentRendered({ Start-Operation 'environment' })
        [void]$window.ShowDialog()
    }
} finally {
    $timer.Stop()
    if ($script:active -and $script:active.Action -in @('scan','environment')) { Stop-Operation }
    if ($SelfTest) {
        $window.Close()
        if ($script:testConfigHome) { $env:CODEX_HOME = $script:savedConfigHome }
    }
}
