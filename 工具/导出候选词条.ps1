# 从 STM32CubeMX 插件 jar 的 class 常量池里抽取「像界面文案」的英文串，供翻译入词库。
# 输出：词库\候选词条.tsv（英文<TAB>出现次数），按出现次数降序。
param(
    [string]$Root = 'C:\stm32mx软件',
    [string]$Out  = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$proj = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = Join-Path $proj '词库\候选词条.tsv' }

# 明显不属于界面文案的串（代码/路径/格式/标识符）直接排除
$blacklist = '(^[a-z0-9_\.\-]+$)|(^[A-Z_]+$)|(\.class$)|(\.jar$)|(\.properties$)|(\.xml$)|(\.htm)|(\.png$)|(\.jpg$)|(\.gif$)|(^com\.)|(^org\.)|(^java)|(^javax)|(^sun\.)|(^http)|(^www\.)|(^[A-Za-z]:)|(\\|/)|(^\W)|(\W$)|(^[A-Za-z]+_[A-Za-z_]+$)|(RGB|ARGB|\$)|(^\d)|(\d{3,})|(=)|(;)|(\{|\})|(\[|\])|(\()|(\))|(%s|%d|%1)|(^%[a-z])'
# 需要保留的短标签（按钮/菜单常用词）
$shortAllow = @('OK','Cancel','Apply','Close','Yes','No','Add','Remove','Delete','Edit','New','Open','Save','Help','About','Back','Next','Finish','Browse','Copy','Cut','Paste','Undo','Redo','Reset','Clear','Search','Print','Import','Export','Rename','Select','Deselect','Enable','Disable','Start','Stop','Run','Debug','Build','View','File','Edit','Tools','Window','Project','Settings','Options','Properties','General','Advanced','Default','Custom','True','False','Enabled','Disabled','Warning','Error','Info','Name','Value','Type','Size','Unit','Mode')
# 丢弃的噪声词（库/框架内部文案）
$noise = @('null','true','false','yes','no','ok','cancel','N/A','TODO','FIXME')

$counts = @{}
foreach ($jar in (Get-ChildItem (Join-Path $Root 'plugins') -Filter '*.jar' -File)) {
    $zip = $null
    try { $zip = [System.IO.Compression.ZipFile]::OpenRead($jar.FullName) } catch { continue }
    foreach ($e in ($zip.Entries | Where-Object { $_.FullName -match '\.class$' })) {
        $ms = New-Object System.IO.MemoryStream
        try { $s = $e.Open(); $s.CopyTo($ms); $s.Close() } catch { continue }
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString($ms.ToArray())
        $ms.Dispose()
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $text.ToCharArray()) {
            $code = [int][char]$ch
            if ($code -ge 32 -and $code -lt 127) { [void]$sb.Append($ch) }
            else {
                if ($sb.Length -ge 2) {
                    $str = $sb.ToString()
                    if ($str.Length -ge 2 -and $str.Length -le 80) {
                        $isShortAllowed = $shortAllow -contains $str
                        $looksSentence = ($str -match '^[A-Z][A-Za-z0-9]') -and ($str -match '[a-z]') -and ($str -match '\s')
                        if (($isShortAllowed -or $looksSentence) -and ($str -notmatch $blacklist) -and ($noise -notcontains $str)) {
                            if ($counts.ContainsKey($str)) { $counts[$str]++ } else { $counts[$str] = 1 }
                        }
                    }
                }
                [void]$sb.Clear()
            }
        }
    }
    $zip.Dispose()
}

$rows = $counts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "$($_.Key)`t$($_.Value)" }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null
$enc = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($Out, ("en`tcount`tzh`r`n" + ($rows -join "`r`n") + "`r`n"), $enc)
Write-Output ("候选词条：" + $rows.Count + " 条 -> " + $Out)
