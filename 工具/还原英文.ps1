# 还原 STM32CubeMX 英文界面：从 .zhbak 恢复启动配置（或移除 -javaagent 行）。
param(
    [string]$Root       = 'C:\stm32mx软件',
    [string]$InstallDir = 'C:\ProgramData\stm32zh'
)
$ErrorActionPreference = 'Stop'

$ini = Join-Path $Root 'STM32CubeMX.l4j.ini'
$bak = "$ini.zhbak"

$jw = Get-Process -Name 'javaw' -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowTitle -match 'STM32CubeMX' -or $_.Path -like "$Root*" }
if ($jw) { Write-Warning 'STM32CubeMX 正在运行，请先关闭再还原。'; exit 2 }

if (Test-Path $bak) {
    Copy-Item $bak $ini -Force
    Write-Output "已从 $bak 恢复启动配置"
} else {
    $lines = [System.IO.File]::ReadAllLines($ini, [System.Text.Encoding]::ASCII) |
             Where-Object { $_ -notmatch '^-javaagent:' -and $_ -notmatch '^-Dstm32zh\.' }
    [System.IO.File]::WriteAllLines($ini, $lines, (New-Object System.Text.ASCIIEncoding))
    Write-Output '已从启动配置中移除 -javaagent 等汉化参数'
}

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
    Write-Output "已移除 agent 安装目录：$InstallDir"
}

Write-Output ''
Write-Output '还原完成，STM32CubeMX 将恢复英文界面。'
