#Requires -Version 5.1
# 还原 STM32CubeMX 英文界面：从 .zhbak 恢复启动配置（或移除 -javaagent 行），并删除 agent 安装目录。
# 易用性：自动请求管理员权限；自动探测 STM32CubeMX 安装目录，失败可交互粘贴。
[CmdletBinding()]
param(
    [string]$Root       = '',
    [string]$InstallDir = 'C:\ProgramData\stm32zh',
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'

# ---------- 1. 自动请求管理员权限 ----------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host '[i] 还原启动配置需要管理员权限，正在弹出授权窗口……' -ForegroundColor Yellow
    $psExe   = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
                 '-InstallDir', "`"$InstallDir`"")
    if ($Root)    { $argList += @('-Root', "`"$Root`"") }
    if ($NoPause) { $argList += '-NoPause' }
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $proc.ExitCode
    }
    catch {
        Write-Host '[×] 未获得管理员权限（授权被取消）。' -ForegroundColor Red
        Write-Host '    可右键「一键还原英文.bat」→「以管理员身份运行」重试。' -ForegroundColor Yellow
        if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
        exit 1
    }
}

# ---------- 2. 探测 STM32CubeMX 安装目录（与安装脚本同一套逻辑） ----------
function Test-CubeMXRoot([string]$Path) {
    if (-not $Path) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'STM32CubeMX.exe') -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $Path 'STM32CubeMX.l4j.ini') -PathType Leaf)
}

function Resolve-CubeMXDir([string]$Hint) {
    if ($Hint) {
        $Hint = $Hint.Trim().Trim('"')
        if (Test-CubeMXRoot $Hint) { return (Resolve-Path -LiteralPath $Hint).Path }
        Write-Host "[×] 指定目录里找不到 STM32CubeMX：$Hint" -ForegroundColor Red
        return $null
    }

    $cands = New-Object System.Collections.Generic.List[string]
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
                                $d = "$($v.$p)".Trim('"')
                                if ($d -match '\.(exe|ini)$') { $d = Split-Path -Parent $d }
                                [void]$cands.Add($d.TrimEnd('\'))
                            }
                        }
                    }
                } catch { }
            }
        } catch { }
    }
    try {
        $p = Get-Process -Name 'STM32CubeMX' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p -and $p.Path) { [void]$cands.Add((Split-Path -Parent $p.Path)) }
    } catch { }
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($pf in @('Program Files', 'Program Files (x86)')) {
            $st = Join-Path $drive.Root (Join-Path $pf 'STMicroelectronics\STM32Cube')
            if (Test-Path -LiteralPath $st) {
                foreach ($sub in (Get-ChildItem -LiteralPath $st -Directory -ErrorAction SilentlyContinue)) {
                    [void]$cands.Add($sub.FullName)
                }
            }
        }
        foreach ($lg in @('C:\stm32mx软件', 'D:\stm32mx软件', (Join-Path $drive.Root 'STM32CubeMX'))) {
            [void]$cands.Add($lg)
        }
    }
    foreach ($c in $cands) {
        if (Test-CubeMXRoot $c) { return (Resolve-Path -LiteralPath $c).Path }
    }

    Write-Host ''
    Write-Host '[i] 未能自动找到 STM32CubeMX 安装目录。' -ForegroundColor Yellow
    Write-Host '    请粘贴 STM32CubeMX 安装目录（其中应有 STM32CubeMX.exe 和 STM32CubeMX.l4j.ini）。' -ForegroundColor Yellow
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
    Write-Host '[×] 未能定位 STM32CubeMX 安装目录，还原中止。' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 1
}
$ini = Join-Path $dir 'STM32CubeMX.l4j.ini'
$bak = "$ini.zhbak"

# ---------- 3. 运行中检查 ----------
$jw = Get-Process -Name 'javaw' -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowTitle -match 'STM32CubeMX' -or $_.Path -like "$dir*" }
if ($jw) {
    Write-Host '[×] STM32CubeMX 正在运行，请先完全关闭再还原。' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '按回车键关闭窗口' | Out-Null }
    exit 2
}

# ---------- 4. 还原 ----------
if (Test-Path $bak) {
    Copy-Item -LiteralPath $bak $ini -Force
    Write-Host "已从 $bak 恢复启动配置"
} else {
    $lines = [System.IO.File]::ReadAllLines($ini, [System.Text.Encoding]::ASCII) |
             Where-Object { $_ -notmatch '^-javaagent:' -and $_ -notmatch '^-Dstm32zh\.' }
    [System.IO.File]::WriteAllLines($ini, $lines, (New-Object System.Text.ASCIIEncoding))
    Write-Host '已从启动配置中移除 -javaagent 等汉化参数'
}

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
    Write-Host "已移除 agent 安装目录：$InstallDir"
}

Write-Host ''
Write-Host '[√] 还原完成，STM32CubeMX 将恢复英文界面。' -ForegroundColor Green

if (-not $NoPause) {
    Write-Host ''
    Read-Host '还原完成，按回车键关闭窗口' | Out-Null
}
