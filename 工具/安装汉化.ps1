#Requires -Version 5.1
# 安装 STM32CubeMX 汉化（Java Agent 运行时翻译方案）
# 特点：不修改任何程序文件（exe / jar 一律不动），只在启动参数里挂一个 agent；
#       桌面快捷方式直接生效；卸载只需还原一个 ini 备份。
# 易用性：自动请求管理员权限（UAC）；自动探测安装目录（参数 → 注册表 → 运行中进程 → 常见路径），
#         探测失败时可交互粘贴路径，无需命令行知识。
[CmdletBinding()]
param(
    [string]$Root       = '',                          # STM32CubeMX 安装目录（留空自动探测）
    [string]$InstallDir = 'C:\ProgramData\stm32zh',    # agent 安装目录（必须纯 ASCII 路径）
    [switch]$Discover,                                 # 带收集模式安装（记录未翻译文字）
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'

# ---------- 1. 自动请求管理员权限（写安装目录与 ProgramData 需要） ----------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host '[i] 写入 STM32CubeMX 安装目录需要管理员权限，正在弹出授权窗口……' -ForegroundColor Yellow
    $psExe   = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
                 '-InstallDir', "`"$InstallDir`"")
    if ($Root)     { $argList += @('-Root', "`"$Root`"") }
    if ($Discover) { $argList += '-Discover' }
    if ($NoPause)  { $argList += '-NoPause' }
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $proc.ExitCode
    }
    catch {
        Write-Host '[×] 未获得管理员权限（授权被取消）。' -ForegroundColor Red
        Write-Host '    可右键「一键安装汉化.bat」→「以管理员身份运行」重试。' -ForegroundColor Yellow
        if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
        exit 1
    }
}

# ---------- 2. 定位源文件 ----------
$proj = Split-Path -Parent $PSScriptRoot
$jar  = Join-Path $proj '成品\stm32cubemx-zh-agent.jar'
$dict = Join-Path $proj '词库\zh.tsv'

if (-not (Test-Path -LiteralPath $jar)) {
    Write-Host "[×] 找不到汉化 agent：$jar" -ForegroundColor Red
    Write-Host '    请确认已完整解压整个压缩包，且没有单独移动「成品」文件夹。' -ForegroundColor Yellow
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}

# ---------- 3. 探测 STM32CubeMX 安装目录 ----------
function Test-CubeMXRoot([string]$Path) {
    if (-not $Path) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'STM32CubeMX.exe') -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $Path 'STM32CubeMX.l4j.ini') -PathType Leaf)
}

function Resolve-CubeMXDir([string]$Hint) {
    if ($Hint) {
        $Hint = $Hint.Trim().Trim('"')
        if (Test-CubeMXRoot $Hint) { return (Resolve-Path -LiteralPath $Hint).Path }
        Write-Host "[×] 指定目录里找不到 STM32CubeMX（应同时包含 STM32CubeMX.exe 与 STM32CubeMX.l4j.ini）：$Hint" -ForegroundColor Red
        return $null
    }

    $cands = New-Object System.Collections.Generic.List[string]

    # (1) 注册表卸载信息（标准安装器会登记；32/64 位视图都查）
    foreach ($base in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path $base)) { continue }
        try {
            Get-ChildItem -Path $base -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $v = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                    if ($v.DisplayName -like '*STM32CubeMX*') {
                        foreach ($p in @('InstallLocation', 'UninstallString', 'DisplayIcon')) {
                            if ($v.$p) {
                                $dir = "$($v.$p)".Trim('"')
                                if ($dir -match '\.(exe|ini)$') { $dir = Split-Path -Parent $dir }
                                [void]$cands.Add($dir.TrimEnd('\'))
                            }
                        }
                    }
                } catch { }
            }
        } catch { }
    }

    # (2) 运行中的 STM32CubeMX / javaw 所在目录
    try {
        $p = Get-Process -Name 'STM32CubeMX' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p -and $p.Path) { [void]$cands.Add((Split-Path -Parent $p.Path)) }
        Get-Process -Name 'javaw' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.MainWindowTitle -match 'STM32CubeMX' -and $_.Path) {
                [void]$cands.Add((Split-Path -Parent $_.Path))
            }
        }
    } catch { }

    # (3) 各磁盘常见安装位置（含自定义目录名的兜底扫描）
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($pf in @('Program Files', 'Program Files (x86)')) {
            $st = Join-Path $drive.Root (Join-Path $pf 'STMicroelectronics\STM32Cube')
            if (Test-Path -LiteralPath $st) {
                foreach ($sub in (Get-ChildItem -LiteralPath $st -Directory -ErrorAction SilentlyContinue)) {
                    [void]$cands.Add($sub.FullName)
                }
            }
        }
        $legacy = @('C:\stm32mx软件', 'D:\stm32mx软件', (Join-Path $drive.Root 'STM32CubeMX'))
        foreach ($lg in $legacy) { [void]$cands.Add($lg) }
    }

    foreach ($c in $cands) {
        if (Test-CubeMXRoot $c) { return (Resolve-Path -LiteralPath $c).Path }
    }

    # (4) 仍然找不到：交互式让用户粘贴路径
    Write-Host ''
    Write-Host '[i] 未能自动找到 STM32CubeMX 安装目录。' -ForegroundColor Yellow
    Write-Host '    请粘贴 STM32CubeMX 安装目录（其中应有 STM32CubeMX.exe 和 STM32CubeMX.l4j.ini），例如：' -ForegroundColor Yellow
    Write-Host '    C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeMX' -ForegroundColor Gray
    Write-Host '    （不知道路径的话：右键桌面 STM32CubeMX 图标 → 打开文件所在位置，复制地址栏）' -ForegroundColor Gray
    for ($i = 0; $i -lt 3; $i++) {
        try { $in = Read-Host 'STM32CubeMX 安装目录（直接回车则退出）' } catch { break }
        if ([string]::IsNullOrWhiteSpace($in)) { break }
        $in = $in.Trim().Trim('"')
        if (Test-CubeMXRoot $in) { return (Resolve-Path -LiteralPath $in).Path }
        Write-Host '[×] 该目录下没有 STM32CubeMX.exe / STM32CubeMX.l4j.ini，请检查后重试。' -ForegroundColor Red
    }
    return $null
}

$dir = Resolve-CubeMXDir -Hint $Root
if (-not $dir) {
    Write-Host '[×] 未能定位 STM32CubeMX 安装目录，安装中止。' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}
$exe = Join-Path $dir 'STM32CubeMX.exe'
$ini = Join-Path $dir 'STM32CubeMX.l4j.ini'
$bak = "$ini.zhbak"

# ---------- 4. 运行中检查（CubeMX 由 javaw 承载） ----------
$running = @(Get-Process -Name 'STM32CubeMX' -ErrorAction SilentlyContinue)
$jw = Get-Process -Name 'javaw' -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowTitle -match 'STM32CubeMX' -or $_.Path -like "$dir*" }
if ($running.Count -gt 0 -or $jw) {
    Write-Host '[×] STM32CubeMX 正在运行，请先完全关闭再安装。' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 2
}

# ---------- 5. 备份启动配置（只备份一次，作为还原母本） ----------
if (-not (Test-Path $bak)) { Copy-Item -LiteralPath $ini $bak -Force; Write-Host "已备份启动配置：$bak" }
else { Write-Host "启动配置备份已存在：$bak" }

# ---------- 6. 释放 agent 与词库到 ASCII 安装目录 ----------
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -LiteralPath $jar  $InstallDir -Force
Copy-Item -LiteralPath $dict $InstallDir -Force
Write-Host "已释放 agent 与词库到：$InstallDir"

# ---------- 7. 以备份为母本重建 ini（幂等：先去掉旧的 -javaagent 行，再追加） ----------
$lines = [System.IO.File]::ReadAllLines($bak, [System.Text.Encoding]::ASCII) |
         Where-Object { $_ -notmatch '^-javaagent:' -and $_ -notmatch '^-Dstm32zh\.' }
$out = New-Object System.Collections.ArrayList
foreach ($l in $lines) { [void]$out.Add($l) }
[void]$out.Add("-javaagent:$InstallDir\stm32cubemx-zh-agent.jar")
if ($Discover) { [void]$out.Add('-Dstm32zh.discover=true') }
[System.IO.File]::WriteAllLines($ini, $out, (New-Object System.Text.ASCIIEncoding))
$mode = if ($Discover) { '（含收集模式）' } else { '' }
Write-Host ("已写入启动参数：-javaagent $mode")

Write-Host ''
Write-Host "STM32CubeMX 目录：$dir"
if ($Discover) {
    Write-Host "收集模式：正常使用 CubeMX，未翻译的界面文字会追加到 $InstallDir\发现-未翻译.tsv"
    Write-Host '收集完成后重新运行本脚本（不加 -Discover）即可恢复普通汉化模式。'
} else {
    Write-Host '[√] 汉化已安装。直接从桌面快捷方式启动 STM32CubeMX 即为中文界面。' -ForegroundColor Green
    Write-Host '如需还原英文，双击仓库根目录的「一键还原英文.bat」。'
}

if (-not $NoPause) {
    Write-Host ''
    Read-Host '安装完成，按回车键关闭窗口' | Out-Null
}
