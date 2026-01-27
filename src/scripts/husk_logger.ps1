$baseDir = Split-Path -Parent $PSScriptRoot
$iniPath = Join-Path $baseDir "config\settings.ini"
$logDir = Join-Path $baseDir "log"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory $logDir | Out-Null }

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
Write-Host "[START] Husk Batch Rendering" -ForegroundColor Cyan

foreach ($usdPath in $usdList) {
    if (!(Test-Path $usdPath)) { continue }
    $usdName = [System.IO.Path]::GetFileNameWithoutExtension($usdPath)
    Write-Host ("`n" + "="*80) -ForegroundColor Cyan
    Write-Host " Processing: $usdName" -ForegroundColor Cyan
    
    # --- 引数構築 ---
    $argList = @("--verbose", "3", "--skip-licenses", "apprentice", "--make-output-path", "--timelimit-image", "--timelimit-nosave-partial")
    $renderOutDir = if($conf["OUT_TOGGLE"] -eq "True" -and $conf["OUT_PATH"]){ $conf["OUT_PATH"] } else { Split-Path -Parent $usdPath }
    
    $frameStart = 1
    $frameEnd = 1
    if ($conf["BATCH_MODE"] -eq "Auto") {
        # 各ファイルごとにhythonで解析
        $range = Get-USDFrameRange $usdPath $conf["HOUDINI_BIN"]
        if ($range) {
            $frameStart = [int]$range.start
            $frameEnd = [int]$range.end
            $count = $frameEnd - $frameStart + 1
            $argList += @("-f", $frameStart, "-n", ([math]::Max(1, $count)))
        }
    } elseif ($conf["BATCH_MODE"] -eq "Manual") {
        $frameStart = [int]$conf["START_FRM"]
        $frameEnd = [int]$conf["END_FRM"]
        $count = $frameEnd - $frameStart + 1
        $argList += @("-f", $frameStart, "-n", ([math]::Max(1, $count)))
    }
    
    # フレームレンジを表示
    Write-Host "  Frame Range: $frameStart - $frameEnd ($($frameEnd - $frameStart + 1) frames)" -ForegroundColor Gray
    
    if ($conf["OUT_TOGGLE"] -eq "True") {
        $baseName = if($conf["OUT_NAME_MODE"] -eq "USD"){ $usdName } else { $conf["OUT_NAME_BASE"] }
        $fullOutPath = Join-Path $renderOutDir "$baseName.`$F$($conf['PADDING']).$($conf['EXT'].TrimStart('.'))"
        $argList += @("--output", $fullOutPath)
    }
    if ($conf.ContainsKey("ENGINE_TYPE")) { $argList += @("--engine", $conf["ENGINE_TYPE"]) }
    if ($conf["RES_SCALE"] -and $conf["RES_SCALE"] -ne "100") { $argList += @("--res-scale", $conf["RES_SCALE"]) }
    if ($conf.ContainsKey("PIXEL_SAMPLES") -and [int]$conf["PIXEL_SAMPLES"] -gt 0) { $argList += @("--pixel-samples", $conf["PIXEL_SAMPLES"]) }
    $limitWarnMin = [int]$conf["TIMEOUT_WARN"]
    $limitKillMin = [int]$conf["TIMEOUT_KILL"]
    $timeLimitSec = if ($limitKillMin -gt 0) { [int]([double]$limitKillMin * 60) } else { -1 }
    $argList += @("--timelimit", $timeLimitSec)
    $argList += $usdPath

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

        # タイムアウト判定
        if ($limitWarn -gt 0 -and $elapsed.TotalMinutes -ge $limitWarn -and -not $warnSent) {
            $msg = "USD: $usdName が制限時間 ($limitWarn 分) を超過しました。"
            Write-Host "`n[WARN] $msg" -ForegroundColor Yellow
            if ($conf["NOTIFY"] -eq "Windows Toast") { Send-WindowsToast -title "Husk Render Warning" -message $msg }
            elseif ($conf["NOTIFY"] -eq "Discord") { Send-DiscordNotification -url $conf["DISCORD_WEBHOOK"] -title "Husk Render Warning" -message $msg }
            $warnSent = $true
        }

    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[COMPLETE] $usdName (Total: $timeStr)" -ForegroundColor Green
        $successCount++
        $renderedFiles += "$usdName ($frameStart-$frameEnd)"
        if (!$lastSavedDir) { $lastSavedDir = $renderOutDir }
    } else {
        $errMsg = "USD: $usdName のレンダリング中にエラーが発生しました (ExitCode: $LASTEXITCODE)"
        Write-Host "`n[ERROR] $errMsg" -ForegroundColor Red
        if ($conf["NOTIFY"] -eq "Discord") { Send-DiscordNotification -url $conf["DISCORD_WEBHOOK"] -title "Husk Render Error" -message "@everyone $errMsg" -color 15158332 }
        $failCount++
    }
}

# --- 終了後の処理 ---
$summary = "完了: $successCount 件 / 失敗: $failCount 件"
$detailMsg = "PC: $pcName`n完了: $successCount 件 / 失敗: $failCount 件"
if ($renderedFiles.Count -gt 0) {
    $detailMsg += "`n`nレンダリング完了:" + ($renderedFiles -join "`n")
}

Write-Host ("`n" + ("=" * 80)) -ForegroundColor Green
Write-Host "  ALL JOBS FINISHED ($summary)" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green

if ($conf["NOTIFY"] -eq "Windows Toast") {
    Send-WindowsToast -title "Husk Render Finished" -message $detailMsg
}
elseif ($conf["NOTIFY"] -eq "Discord") {
    Send-DiscordNotification -url $conf["DISCORD_WEBHOOK"] -title "Husk Render Finished" -message "@everyone $detailMsg"
}

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
                "シャットダウン" { shutdown /s /t 5 }
                "再起動" { shutdown /r /t 5 }
                "ログオフ" { shutdown /l }
            }
            Start-Sleep -Seconds 2
            exit
        }
    }
}

# --- メニュー処理 ---
$skipMenu = $false
if ($conf.ContainsKey("SHUTDOWN_ACTION")) {
    $action = $conf["SHUTDOWN_ACTION"]
    if ($action -eq "シャットダウン" -or $action -eq "再起動" -or $action -eq "ログオフ") {
        $skipMenu = $true
    }
}
if ($conf["REBOOT"] -eq "True") {
    $skipMenu = $true
}

if (-not $skipMenu) {
    # 入力バッファをクリア
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    
    Write-Host ("`n" + ("=" * 80)) -ForegroundColor Green
    Write-Host "  ALL JOBS FINISHED - Menu Mode" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host " [O]保存先を開く  [L]ログを開く  [X]閉じる" -ForegroundColor Gray

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