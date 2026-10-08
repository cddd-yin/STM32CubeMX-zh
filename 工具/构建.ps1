# 构建 STM32CubeMX 汉化 Agent：用 CubeMX 自带 JDK 编译源码，打包成 成品\stm32cubemx-zh-agent.jar
param(
    [string]$Jdk = 'C:\stm32mx软件\jre\bin'
)
$ErrorActionPreference = 'Stop'

$proj = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $proj '源码'
$out  = Join-Path $proj '成品'
$work = Join-Path $env:TEMP 'stm32cubemx-zh-build'

$javac = Join-Path $Jdk 'javac.exe'
$jar   = Join-Path $Jdk 'jar.exe'
if (-not (Test-Path $javac)) { Write-Error "找不到 javac：$javac （用 -Jdk 指定 CubeMX 自带 JDK 的 bin 目录）"; exit 1 }

# 用 ASCII 临时目录编译（避免中文路径带来的编码问题）
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$classes = Join-Path $work 'classes'
New-Item -ItemType Directory -Force -Path $classes | Out-Null
New-Item -ItemType Directory -Force -Path $out | Out-Null

Copy-Item (Join-Path $src '*.java') $work -Force
"Manifest-Version: 1.0`r`nPremain-Class: Stm32CubeMxZhAgent`r`nCan-Retransform-Classes: false`r`n`r`n" |
    Set-Content -Path (Join-Path $work 'MANIFEST.MF') -Encoding ASCII -NoNewline

& $javac -encoding UTF-8 -d $classes (Join-Path $work 'Stm32CubeMxZhAgent.java')
if ($LASTEXITCODE -ne 0) { Write-Error '编译失败'; exit 1 }

# 打包全部 class（含匿名内部类 $1/$2...）
$jarPath = Join-Path $out 'stm32cubemx-zh-agent.jar'
if (Test-Path $jarPath) { Remove-Item $jarPath -Force }
& $jar --create --file $jarPath --manifest (Join-Path $work 'MANIFEST.MF') -C $classes .
if ($LASTEXITCODE -ne 0) { Write-Error '打包失败'; exit 1 }

Remove-Item $work -Recurse -Force
Write-Output ("构建完成：" + $jarPath)
Write-Output ("大小：" + (Get-Item $jarPath).Length + " 字节")
Write-Output ("包含 " + ((& $jar --list --file $jarPath | Measure-Object).Count) + " 个条目")
