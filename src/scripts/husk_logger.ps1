$baseDir = Split-Path -Parent $PSScriptRoot
$iniPath = Join-Path $baseDir "config\settings.ini"
$overridePath = Join-Path $baseDir "config\usd_overrides.xml"
$logDir = Join-Path $baseDir "log"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory $logDir | Out-Null }

# --- ユーティリティ ---
function Normalize-UsdPath {
    param([string]$path)
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    try { return (Resolve-Path $path -ErrorAction Stop).ProviderPath } catch { return $path }
}

function Load-UsdOverrides {
    param([string]$path)
    $map = @{}
    if (!(Test-Path $path)) { return $map }
    try {
        $map = Import-Clixml -Path $path -ErrorAction Stop
        if (-not $map) { $map = @{} }
    } catch {
        Write-Host "[WARN] USD overrideファイルの読み込みに失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    return $map
}

function Convert-RangePairs {
    param($ranges)
    $result = @()
    if (-not $ranges) { return $result }
    foreach ($r in $ranges) {
        # ハッシュテーブル形式の場合
        if ($r -is [hashtable] -and $r.ContainsKey('start') -and $r.ContainsKey('end')) {
            $result += @{ start = [int]$r.start; end = [int]$r.end }
        }
        # 旧形式（配列）との互換性
        elseif ($r -is [System.Collections.IEnumerable] -and $r.Count -ge 1) {
            $s = [int]$r[0]
            $e = if ($r.Count -ge 2) { [int]$r[1] } else { [int]$r[0] }
            $result += @{ start = $s; end = $e }
        }
    }
    return $result
}

function Get-DefaultRanges {
    param([string]$usdPath, $conf)
    $ranges = @()
    $batchMode = $conf["BATCH_MODE"]
    if ($batchMode -eq "Auto") {
        $range = Get-USDFrameRange $usdPath $conf["HOUDINI_BIN"]
        if ($range) { $ranges += @{ start = [int]$range.start; end = [int]$range.end } }
    } elseif ($batchMode -eq "Manual") {
        $start = [int]$conf["START_FRM"]
        $end = [int]$conf["END_FRM"]
        if ($start -eq $end) {
            $ranges += @{ start = $start; end = $end }
        } else {
            $ranges += @{ start = $start; end = $end }
        }
    }
    return $ranges
}

function Build-RenderJobPlan {
    param([string]$usdPath, $conf, $override)
    $fullPath = Normalize-UsdPath $usdPath
    $usdName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)

    # オーバーライドから値を取得するヘルパー関数（存在すればオーバーライド、なければconf）
    $getValue = {
        param($key, $overrideKey = $null, [switch]$asInt)
        if (-not $overrideKey) { $overrideKey = $key }
        $val = if ($override -and $override.ContainsKey($overrideKey)) { $override[$overrideKey] } else { $conf[$key] }
        if ($asInt) { return [int]$val }
        return $val
    }

    $batchMode = if ($override -and $override.batchMode) { $override.batchMode } else { $conf["BATCH_MODE"] }
    $ranges = @()
    if ($override -and $override.ranges) { 
        $ranges = Convert-RangePairs $override.ranges 
    }
    elseif ($batchMode -eq "Auto") { 
        $ranges = Get-DefaultRanges $fullPath $conf 
    }
    elseif ($batchMode -eq "Manual") {
        $start = if ($override -and $override.startFrame) { [int]$override.startFrame } else { [int]$conf["START_FRM"] }
        $end = if ($override -and $override.endFrame) { [int]$override.endFrame } else { [int]$conf["END_FRM"] }
        $ranges = @(@{ start = $start; end = $end })
    }
    if ($ranges.Count -eq 0) { $ranges = @(@{ start = 1; end = 1 }) }

    $outToggle = & $getValue "OUT_TOGGLE" "outToggle"
    $useOutToggle = ($outToggle -eq "True") -or ($override -and $override.outPath)
    $renderOutDir = if ($override -and $override.outPath) { $override.outPath } elseif ($outToggle -eq "True" -and (& $getValue "OUT_PATH" "outPath")) { & $getValue "OUT_PATH" "outPath" } else { Split-Path -Parent $fullPath }
    $nameMode = if ($override -and $override.nameMode) { $override.nameMode } else { & $getValue "OUT_NAME_MODE" }
    $nameBase = if ($override -and $override.nameBase) { $override.nameBase } else { & $getValue "OUT_NAME_BASE" }
    $baseName = if ($nameMode -eq "USD") { $usdName } else { $nameBase }

    $padding = & $getValue "PADDING" -asInt
    $ext = & $getValue "EXT"
    $resScale = if ($override -and $override.resScale) { [int]$override.resScale } else { & $getValue "RES_SCALE" -asInt }
    $pixelSamples = if ($override -and $override.pixelSamples) { [int]$override.pixelSamples } else { & $getValue "PIXEL_SAMPLES" -asInt }
    $engine = if ($override -and $override.engine) { $override.engine } else { & $getValue "ENGINE_TYPE" }
    $notify = if ($override -and $override.notify) { $override.notify } else { & $getValue "NOTIFY" }
    $timeoutWarn = & $getValue "TIMEOUT_WARN" -asInt
    $timeoutKill = & $getValue "TIMEOUT_KILL" -asInt
    $discordWebhook = & $getValue "DISCORD_WEBHOOK"

    return [pscustomobject]@{
        Path = $fullPath
        Name = $usdName
        Ranges = $ranges
        UseOutput = $useOutToggle
        RenderOutDir = $renderOutDir
        BaseName = $baseName
        Padding = $padding
        Ext = $ext
        ResScale = $resScale
        PixelSamples = $pixelSamples
        Engine = $engine
        Notify = $notify
        TimeoutWarn = $timeoutWarn
        TimeoutKill = $timeoutKill
        DiscordWebhook = $discordWebhook
    }
}

# --- 通知用関数の定義 ---
function Send-WindowsToast {
    param([string]$title, [string]$message)
    
    try {
        # WinRTのアセンブリをより確実にロードする
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    } catch {
        # 上記で失敗する場合のフォールバック（型を直接指定してロードを試みる）
        Add-Type -AssemblyName "System.Runtime.WindowsRuntime"
    }

    # 通知のXMLテンプレート作成
    $xml = "<toast><visual><binding template='ToastGeneric'><text>$title</text><text>$message</text></binding></visual></toast>"
    $toastXml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $toastXml.LoadXml($xml)

    # OS標準のAppIDを使用して送信
    $toast = New-Object Windows.UI.Notifications.ToastNotification $toastXml
    $appId = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
    
    try {
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch {
        Write-Host "[!] 通知の送信に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Send-DiscordNotification {
    param([string]$url, [string]$title, [string]$message, [int]$color = 5814783)
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    
    $payload = @{
        embeds = @(@{
            title = $title
            description = $message
            color = $color
        })
    }
    
    try {
        $jsonBody = $payload | ConvertTo-Json -Depth 10 -Compress
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $bodyBytes = $utf8.GetBytes($jsonBody)
        
        Invoke-RestMethod -Uri $url -Method Post -Body $bodyBytes -ContentType "application/json; charset=utf-8"
    } catch {
        Write-Host "[!] Discord通知の送信に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Get-USDFrameRange {
    param($usdPath, $houBin)
    $hythonExe = Join-Path $houBin "hython.exe"
    if (!(Test-Path $hythonExe)) { return $null }
    # USDのStageを開いてStartTimeとEndTimeを取得するPythonコード
    $pyCode = "from pxr import Usd; stage = Usd.Stage.Open('$($usdPath.Replace('\','/'))'); print(f'START:{stage.GetStartTimeCode()} END:{stage.GetEndTimeCode()}')"
    try {
        $out = & "$hythonExe" -c "$pyCode" 2>$null
        if ($out -match "START:([-?\d\.]+) END:([-?\d\.]+)") {
            return @{ start = [math]::Floor([double]$matches[1]); end = [math]::Floor([double]$matches[2]) }
        }
    } catch {}
    return $null
}

# 1. 設定の読み込み
$conf = @{}
if (Test-Path $iniPath) {
    Get-Content $iniPath | ForEach-Object { if($_ -match "^([^=]+)=(.*)$") { $conf[$matches[1].Trim()]=$matches[2].Trim() } }
}
$usdOverrides = Load-UsdOverrides $overridePath

# Houdiniのパスを通す
$huskExe = Join-Path $conf["HOUDINI_BIN"] "husk.exe"
if (!(Test-Path $huskExe)) {
    Write-Host "[ERROR] husk.exe が見つかりません。パスを確認してください: $huskExe" -ForegroundColor Red
    Read-Host "Enterキーを押して終了します..."; exit 1
}
$env:Path = $conf["HOUDINI_BIN"] + ";" + $env:Path

# リストのクリーンアップ（空の要素を除去）
$usdList = if($conf["USD_LIST"]){ $conf["USD_LIST"].Split(",") | Where-Object { $_ -ne "" } } else { @() }
if ($usdList.Count -eq 0) { Write-Host "[ERROR] 対象USDがありません。" -ForegroundColor Red; Read-Host "Enterキーを押して終了します..."; exit 1 }

$pcName = $env:COMPUTERNAME
$logFile = Join-Path $logDir ("$pcName`_" + (Get-Date -Format 'yyyyMMdd_HHmm') + ".log")
$lastSavedDir = "" # フォルダオープン用に初期化
$successCount = 0
$failCount = 0
$renderedFiles = @() # レンダリングしたファイル情報を保存

# 総レンダリング回数を計算とレンダリングプランの事前表示
$totalRenderCount = 0
$renderPlans = @()
$isAutoMode = $conf["BATCH_MODE"] -eq "Auto"
if ($isAutoMode) {
    Write-Host "USDファイルを解析中..." -ForegroundColor Gray
}
foreach ($usdPath in $usdList) {
    if (!(Test-Path $usdPath)) { continue }
    $usdFileName = [System.IO.Path]::GetFileName($usdPath)
    if ($isAutoMode) {
        Write-Host "  解析中: $usdFileName" -ForegroundColor DarkGray -NoNewline
    }
    
    $normalized = Normalize-UsdPath $usdPath
    $override = $usdOverrides[$normalized]
    $plan = Build-RenderJobPlan $usdPath $conf $override
    $totalRenderCount += $plan.Ranges.Count
    $renderPlans += $plan
    
    if ($isAutoMode) {
        Write-Host " ✓" -ForegroundColor Green
    }
}
if ($isAutoMode) {
    Write-Host "解析完了`n" -ForegroundColor Green
}

Write-Host "[START] Husk Batch Rendering" -ForegroundColor Cyan
Write-Host "総レンダリング回数: $totalRenderCount" -ForegroundColor Cyan
Write-Host ("="*80) -ForegroundColor Cyan
Write-Host "レンダリング対象:" -ForegroundColor Yellow

"[START] Husk Batch Rendering" | Out-File $logFile -Append -Encoding utf8
"総レンダリング回数: $totalRenderCount" | Out-File $logFile -Append -Encoding utf8
("="*80) | Out-File $logFile -Append -Encoding utf8
"レンダリング対象:" | Out-File $logFile -Append -Encoding utf8

foreach ($plan in $renderPlans) {
    $rangeTexts = $plan.Ranges | ForEach-Object {
        if ($_.start -eq $_.end) { "($($_.start))" } else { "($($_.start)-$($_.end))" }
    }
    $rangeStr = $rangeTexts -join ","
    Write-Host "  $($plan.Name).usd $rangeStr" -ForegroundColor Gray
    "  $($plan.Name).usd $rangeStr" | Out-File $logFile -Append -Encoding utf8
}
("="*80) | Out-File $logFile -Append -Encoding utf8


$currentRenderIndex = 0
foreach ($usdPath in $usdList) {
    if (!(Test-Path $usdPath)) { Write-Host "[WARN] USDが見つかりません: $usdPath" -ForegroundColor Yellow; continue }

    $normalized = Normalize-UsdPath $usdPath
    $override = $usdOverrides[$normalized]
    $plan = Build-RenderJobPlan $usdPath $conf $override
    $usdName = $plan.Name

    Write-Host ("="*80) -ForegroundColor Cyan
    Write-Host " Processing: $usdName" -ForegroundColor Cyan
    
    "" | Out-File $logFile -Append -Encoding utf8
    ("="*80) | Out-File $logFile -Append -Encoding utf8
    " Processing: $usdName" | Out-File $logFile -Append -Encoding utf8
    ("="*80) | Out-File $logFile -Append -Encoding utf8

    foreach ($range in $plan.Ranges) {
        $currentRenderIndex++
        $frameStart = [int]$range.start
        $frameEnd = [int]$range.end
        $frameCount = [math]::Max(1, ($frameEnd - $frameStart + 1))

        Write-Host ""
        Write-Host ("  " + "-"*76) -ForegroundColor DarkCyan
        Write-Host "  [$currentRenderIndex/$totalRenderCount] Frame Range: $frameStart - $frameEnd ($frameCount frames)" -ForegroundColor White
        Write-Host ("  " + "-"*76) -ForegroundColor DarkCyan
        
        "" | Out-File $logFile -Append -Encoding utf8
        ("  " + "-"*76) | Out-File $logFile -Append -Encoding utf8
        "  [$currentRenderIndex/$totalRenderCount] Frame Range: $frameStart - $frameEnd ($frameCount frames)" | Out-File $logFile -Append -Encoding utf8
        ("  " + "-"*76) | Out-File $logFile -Append -Encoding utf8
        
        # レンダリング開始通知
        $startMsg = "レンダリング開始 [$currentRenderIndex/$totalRenderCount]: $pcName, $usdName ($frameStart-$frameEnd)"
        Write-Host "  [START] $startMsg" -ForegroundColor Yellow
        "  [START] $startMsg" | Out-File $logFile -Append -Encoding utf8
        if ($plan.Notify -eq "Windows Toast") { Send-WindowsToast -title "Husk Render Started" -message $startMsg }
        elseif ($plan.Notify -eq "Discord") { Send-DiscordNotification -url $plan.DiscordWebhook -title "Husk Render Started" -message $startMsg -color 3447003 }

        # --- 引数構築 ---
        $argList = @("--verbose", "3", "--skip-licenses", "apprentice", "--make-output-path", "--timelimit-image", "--timelimit-nosave-partial")
        if ($plan.UseOutput) {
            # 出力ディレクトリを明示的に作成
            if (!(Test-Path $plan.RenderOutDir)) {
                try {
                    New-Item -ItemType Directory -Path $plan.RenderOutDir -Force | Out-Null
                    Write-Host "  [INFO] 出力ディレクトリを作成: $($plan.RenderOutDir)" -ForegroundColor Gray
                } catch {
                    Write-Host "  [WARN] 出力ディレクトリ作成エラー: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            $fullOutPath = Join-Path $plan.RenderOutDir "$($plan.BaseName).`$F$($plan.Padding).$($plan.Ext.TrimStart('.'))"
            Write-Host "  [INFO] 出力パス: $fullOutPath" -ForegroundColor Gray
            $argList += @("--output", $fullOutPath)
        }
        if ($plan.Engine) { $argList += @("--engine", $plan.Engine) }
        if ($plan.ResScale -and $plan.ResScale -ne 100) { $argList += @("--res-scale", $plan.ResScale) }
        if ($plan.PixelSamples -gt 0) { $argList += @("--pixel-samples", $plan.PixelSamples) }
        $limitWarnMin = $plan.TimeoutWarn
        $limitKillMin = $plan.TimeoutKill
        $timeLimitSec = if ($limitKillMin -gt 0) { [int]([double]$limitKillMin * 60) } else { -1 }
        $argList += @("--timelimit", $timeLimitSec)
        $argList += @("-f", $frameStart, "-n", $frameCount)
        $argList += $plan.Path

        $startTime = Get-Date
        $warnSent = $false
        $limitWarn = $limitWarnMin
        $limitKill = $limitKillMin
        $progress = "0.0%"
        $currentFrame = "---"

        # --- husk実行と監視 ---
        $fullCmd = "`"$huskExe`" " + (($argList | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } }) -join " ")
        "[COMMAND] $fullCmd" | Out-File $logFile -Append -Encoding utf8

        & "$huskExe" @argList 2>&1 | ForEach-Object {
            $line = $_.ToString()
            $line | Out-File $logFile -Append -Encoding utf8

            $elapsed = (Get-Date) - $startTime
            $timeStr = "{0:D2}:{1:D2}:{2:D2}" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds
            if ($line -match '(\d+\.\d+%)') { $progress = $matches[1] }
            if ($line -match '(\d+/\d+)') { $currentFrame = $matches[1] }
            elseif ($line -match 'Rendering frame (\d+)') { $currentFrame = $matches[1] }
            if ($line -match 'Saved Image:\s*(.+)') { $lastSavedDir = Split-Path -Parent $matches[1].Trim() }

            $statusLine = "`r[PROGRESS] $progress | Frame: $currentFrame | Elapsed: $timeStr"
            if ($limitKill -gt 0) { $statusLine += " / Limit: $limitKill min" }
            Write-Host -NoNewline ($statusLine.PadRight(100))

            if ($limitWarn -gt 0 -and $elapsed.TotalMinutes -ge $limitWarn -and -not $warnSent) {
                $msg = "USD: $usdName ($frameStart-$frameEnd) が制限時間 ($limitWarn 分) を超過しました。"
                Write-Host "`n[WARN] $msg" -ForegroundColor Yellow
                if ($plan.Notify -eq "Windows Toast") { Send-WindowsToast -title "Husk Render Warning" -message $msg }
                elseif ($plan.Notify -eq "Discord") { Send-DiscordNotification -url $plan.DiscordWebhook -title "Husk Render Warning" -message $msg }
                $warnSent = $true
            }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n[COMPLETE] $usdName ($frameStart-$frameEnd) (Total: $timeStr)" -ForegroundColor Green
            $successCount++
            $renderedFiles += "$usdName ($frameStart-$frameEnd)"
            if (!$lastSavedDir) { $lastSavedDir = $plan.RenderOutDir }
        } else {
            $errMsg = "USD: $usdName ($frameStart-$frameEnd) のレンダリング中にエラーが発生しました (ExitCode: $LASTEXITCODE)"
            Write-Host "`n[ERROR] $errMsg" -ForegroundColor Red
            if ($plan.Notify -eq "Discord") { Send-DiscordNotification -url $plan.DiscordWebhook -title "Husk Render Error" -message "@everyone $errMsg" -color 15158332 }
            $failCount++
        }
    }
}

# --- 終了後の処理 ---
$summary = "完了: $successCount 件 / 失敗: $failCount 件"
$detailMsg = "PC: $pcName`n完了: $successCount 件 / 失敗: $failCount 件"
if ($renderedFiles.Count -gt 0) {
    $detailMsg += "`n`nレンダリング完了:" + ($renderedFiles -join ",")
}

Write-Host ("`n" + ("=" * 80)) -ForegroundColor Yellow
Write-Host "  ALL JOBS FINISHED ($summary)" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Yellow
"" | Out-File $logFile -Append -Encoding utf8
("=" * 80) | Out-File $logFile -Append -Encoding utf8
"  ALL JOBS FINISHED ($summary)" | Out-File $logFile -Append -Encoding utf8
("=" * 80) | Out-File $logFile -Append -Encoding utf8
if ($conf["NOTIFY"] -eq "Windows Toast") {
    Send-WindowsToast -title "Husk Render Finished" -message $detailMsg
}
elseif ($conf["NOTIFY"] -eq "Discord") {
    Send-DiscordNotification -url $conf["DISCORD_WEBHOOK"] -title "Husk Render Finished" -message "@everyone $detailMsg"
}

# 完了後のアクション処理
$actionToPerform = $null
if ($conf.ContainsKey("SHUTDOWN_ACTION")) {
    $actionToPerform = $conf["SHUTDOWN_ACTION"]
} elseif ($conf["REBOOT"] -eq "True") {
    $actionToPerform = "再起動"
}

if ($actionToPerform -and $actionToPerform -ne "なし" -and $actionToPerform -ne "None") {
    $actionName = switch ($actionToPerform) {
        "シャットダウン" { "シャットダウン"; break }
        "再起動" { "再起動"; break }
        "ログオフ" { "ログオフ"; break }
        default { $null }
    }
    
    if ($actionName) {
        Write-Host "`n[SYSTEM] 30秒後に$actionName`します。中止するにはキーを押してください..." -ForegroundColor Red
        $cancelled = $false
        for ($i = 30; $i -gt 0; $i--) {
            Write-Host -NoNewline "`rCountdown: $i  "
            if ($Host.UI.RawUI.KeyAvailable) {
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                Write-Host "`n[CANCEL] $actionName`は中止されました。" -ForegroundColor Cyan
                $cancelled = $true
                break
            }
            Start-Sleep -Seconds 1
        }
        
        if (-not $cancelled) {
            Write-Host "`n[$actionName] 実行します..." -ForegroundColor Yellow
            switch ($actionToPerform) {
                "シャットダウン" { shutdown /s /t 5 /f }
                "再起動" { shutdown /r /t 5 /f }
                "ログオフ" { shutdown /l /f }
            }
            Start-Sleep -Seconds 2
            exit
        }
    }
} else {
    # アクションが「なし」またはアクションがキャンセルされた場合はメニューを表示
    # 入力バッファをクリア
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    
    Write-Host ("`n" + ("=" * 80)) -ForegroundColor Cyan
    Write-Host "  ALL JOBS FINISHED - Menu Mode" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host " [O]保存先を開く  [L]ログを開く  [X]閉じる" -ForegroundColor White

    $menuActive = $true
    $lastStatus = "待機中..."

    while ($menuActive) {
        # 行の先頭に戻り、前回のメッセージを十分な空白で消してから新しい状態を表示
        # `r で先頭に戻り、80文字分クリアしてから再度先頭へ
        $menuLine = "`r" + (" " * 80) + "`r[MENU] $($lastStatus.PadRight(40)) >> "
        Write-Host -NoNewline $menuLine -ForegroundColor Cyan
        
        $keyInput = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $key = $keyInput.Character.ToString().ToLower()
        
        switch ($key) {
            'o' {
                if ($lastSavedDir -and (Test-Path $lastSavedDir)) {
                    Start-Process explorer.exe $lastSavedDir
                    $lastStatus = "保存先フォルダを開きました"
                } elseif ($conf["OUT_PATH"] -and (Test-Path $conf["OUT_PATH"])) {
                    Start-Process explorer.exe $conf["OUT_PATH"]
                    $lastStatus = "設定の出力先を開きました"
                } else {
                    $lastStatus = "エラー: 保存先が見つかりません"
                }
            }
            'l' { 
                if (Test-Path $logFile) { 
                    Start-Process notepad.exe $logFile 
                    $lastStatus = "ログファイルを開きました"
                } else {
                    $lastStatus = "エラー: ログが見つかりません"
                }
            }
            'x' { 
                $menuActive = $false 
                Write-Host "`n[EXIT] 終了します..." -ForegroundColor Gray
            }
            "`r" { $menuActive = $false } # Enterで終了
        }
    }
}