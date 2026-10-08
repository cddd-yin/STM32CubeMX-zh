# 安装 STM32CubeMX 汉化（Java Agent 运行时翻译方案）
# 特点：不修改任何程序文件（exe / jar 一律不动），只在启动参数里挂一个 agent；
#       桌面快捷方式直接生效；卸载只需还原一个 ini 备份。
param(
    [string]$Root       = 'C:\stm32mx软件',            # STM32CubeMX 安装目录
    [string]$InstallDir = 'C:\ProgramData\stm32zh',    # agent 安装目录（必须纯 ASCII 路径）
    [switch]$Discover                                   # 带收集模式安装（记录未翻译文字）
)
$ErrorActionPreference = 'Stop'

$proj = Split-Path -Parent $PSScriptRoot
$jar  = Join-Path $proj '成品\stm32cubemx-zh-agent.jar'
$dict = Join-Path $proj '词库\zh.tsv'
$exe  = Join-Path $Root 'STM32CubeMX.exe'
$ini  = Join-Path $Root 'STM32CubeMX.l4j.ini'
$bak  = "$ini.zhbak"

if (-not (Test-Path $exe)) { Write-Error "未找到 STM32CubeMX：$exe"; exit 1 }
if (-not (Test-Path $ini)) { Write-Error "未找到启动配置：$ini"; exit 1 }
if (-not (Test-Path $jar)) { Write-Error "缺少 agent，请先运行 工具\构建.ps1：$jar"; exit 1 }

# 0. 运行中检查（CubeMX 由 javaw 承载）
$running = @(Get-Process -Name 'STM32CubeMX' -ErrorAction SilentlyContinue)
$jw = Get-Process -Name 'javaw' -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowTitle -match 'STM32CubeMX' -or $_.Path -like "$Root*" }
if ($running.Count -gt 0 -or $jw) { Write-Warning 'STM32CubeMX 正在运行，请先关闭再安装。'; exit 2 }

# 1. 备份启动配置（只备份一次，作为还原母本）
if (-not (Test-Path $bak)) { Copy-Item $ini $bak -Force; Write-Output "已备份启动配置：$bak" }
else { Write-Output "启动配置备份已存在：$bak" }

# 2. 释放 agent 与词库到 ASCII 安装目录
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item $jar  $InstallDir -Force
Copy-Item $dict $InstallDir -Force
Write-Output "已释放 agent 与词库到：$InstallDir"

# 3. 以备份为母本重建 ini（幂等：先去掉旧的 -javaagent 行，再追加）
$lines = [System.IO.File]::ReadAllLines($bak, [System.Text.Encoding]::ASCII) |
         Where-Object { $_ -notmatch '^-javaagent:' -and $_ -notmatch '^-Dstm32zh\.' }
$out = New-Object System.Collections.ArrayList
foreach ($l in $lines) { [void]$out.Add($l) }
[void]$out.Add("-javaagent:$InstallDir\stm32cubemx-zh-agent.jar")
if ($Discover) { [void]$out.Add('-Dstm32zh.discover=true') }
[System.IO.File]::WriteAllLines($ini, $out, (New-Object System.Text.ASCIIEncoding))
$mode = if ($Discover) { '（含收集模式）' } else { '' }
Write-Output ("已写入启动参数：-javaagent $mode")

if ($Discover) {
    Write-Output ''
    Write-Output "收集模式：正常使用 CubeMX，未翻译的界面文字会追加到 $InstallDir\发现-未翻译.tsv"
    Write-Output '收集完成后重新运行本脚本（不加 -Discover）即可恢复普通汉化模式。'
} else {
    Write-Output ''
    Write-Output '安装完成。直接从桌面快捷方式启动 STM32CubeMX 即为中文界面。'
    Write-Output '如需还原英文，运行 工具\还原英文.cmd。'
}
