# HuskCommon.psm1
# 共通ユーティリティ、設定管理、通知サービスモジュール

# ============================================================================
# 1. 共通ユーティリティ (Common Utilities)
# ============================================================================

<#
.SYNOPSIS
USDファイルのパスを正規化します。

.DESCRIPTION
相対パスを絶対パスに変換し、パスを標準化します。

.PARAMETER path
正規化するパス

.EXAMPLE
Normalize-UsdPath ".\test.usd"
#>
function Normalize-UsdPath {
    param([string]$path)
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    try { 
        return (Resolve-Path $path -ErrorAction Stop).ProviderPath 
    } catch { 
        return $path 
    }
}

<#
.SYNOPSIS
USDファイルからフレーム範囲を取得します。

.DESCRIPTION
hython.exeを使用してUSDファイルのStageを開き、StartTimeCodeとEndTimeCodeを取得します。

.PARAMETER usdPath
USDファイルのパス

.PARAMETER houBin
Houdiniのbinフォルダパス

.EXAMPLE
Get-USDFrameRange "C:\path\to\file.usd" "C:\Program Files\Side Effects Software\Houdini 21.0.440\bin"
#>
function Get-USDFrameRange {
    param($usdPath, $houBin)
    
    if ([string]::IsNullOrWhiteSpace($usdPath) -or !(Test-Path $usdPath)) { 
        return $null 
    }
    
    $hythonExe = Join-Path $houBin "hython.exe"
    if (!(Test-Path $hythonExe)) { 
        return $null 
    }
    
    # USDのStageを開いてStartTimeとEndTimeを取得するPythonコード
    $pyCode = "from pxr import Usd; stage = Usd.Stage.Open('$($usdPath.Replace('\','/'))'); print(f'START:{stage.GetStartTimeCode()} END:{stage.GetEndTimeCode()}')"
    
    try {
        $si = New-Object System.Diagnostics.ProcessStartInfo -Property @{
            FileName = $hythonExe
            Arguments = "-c `"$pyCode`""
            RedirectStandardOutput = $true
            UseShellExecute = $false
            CreateNoWindow = $true
        }
        $proc = [System.Diagnostics.Process]::Start($si)
        $out = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        
        if ($out -match "START:([-?\d\.]+) END:([-?\d\.]+)") {
            return @{ 
                start = [math]::Floor([double]$matches[1])
                end = [math]::Floor([double]$matches[2])
            }
        }
    } catch {
        Write-Verbose "USDフレーム範囲の取得に失敗: $_"
    }
    
    return $null
}

<#
.SYNOPSIS
範囲テキスト（例: "1001-1010,1050"）をオブジェクト形式に変換します。

.PARAMETER text
範囲を表すテキスト

.EXAMPLE
Parse-RangeText "1001-1010,1050"
#>
function Parse-RangeText {
    param([string]$text)
    
    $ranges = @()
    if ([string]::IsNullOrWhiteSpace($text)) { 
        return $ranges 
    }
    
    foreach ($chunk in $text.Split(",")) {
        $token = $chunk.Trim()
        if (-not $token) { continue }
        
        if ($token -match "^(-?\d+)-(-?\d+)$") {
            $start = [int]$matches[1]
            $end = [int]$matches[2]
            $ranges += @{ start = $start; end = $end }
        } 
        elseif ($token -match "^(-?\d+)$") {
            $val = [int]$matches[1]
            $ranges += @{ start = $val; end = $val }
        } 
        else {
            return $null
        }
    }
    
    return $ranges
}

<#
.SYNOPSIS
範囲オブジェクトを標準化されたハッシュテーブル形式に変換します。

.PARAMETER ranges
変換する範囲オブジェクト

.EXAMPLE
Convert-RangePairs $rangeArray
#>
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

# ============================================================================
# 2. 設定・データ管理 (Configuration & Data Access)
# ============================================================================

<#
.SYNOPSIS
デフォルト設定を取得します。

.DESCRIPTION
デフォルト値を定義し、設定ファイル（.ini）から値を読み込んで上書きします。

.PARAMETER iniPath
INIファイルのパス（省略可）

.EXAMPLE
Get-IniSettings "C:\path\to\settings.ini"
#>
function Get-IniSettings {
    param([string]$iniPath)
    
    $c = @{ 
        USD_LIST = ""
        OUT_PATH = ""
        START_FRM = "1"
        END_FRM = "1"
        REBOOT = "False"
        SHUTDOWN_ACTION = "None"
        SINGLE = "False"
        HOUDINI_BIN = "C:\Program Files\Side Effects Software\Houdini 21.0.440\bin"
        BATCH_MODE = "Auto"
        OUT_TOGGLE = "True"
        OUT_NAME_MODE = "USD"
        OUT_NAME_BASE = "render"
        EXT = "exr"
        PADDING = "4"
        RES_SCALE = "100"
        PIXEL_SAMPLES = "0"
        NOTIFY = "None"
        DISCORD_WEBHOOK = ""
        TIMEOUT_WARN = "0"
        TIMEOUT_KILL = "0"
        ENGINE_TYPE = "cpu"
        DISABLE_MOTIONBLUR = "False"
        LOCK_RENDER = "False"
        LOCK_TIMEOUT = "False"
    }
    
    if ($iniPath -and (Test-Path $iniPath)) {
        Get-Content $iniPath | ForEach-Object {
            if ($_ -match "^([^=]+)=(.*)$") { 
                $c[$matches[1].Trim()] = $matches[2].Trim() 
            }
        }
    }
    
    return $c
}

<#
.SYNOPSIS
USDごとの個別設定（オーバーライド）を読み込みます。

.PARAMETER path
XMLファイルのパス

.EXAMPLE
Load-UsdOverrides "C:\path\to\usd_overrides.xml"
#>
function Load-UsdOverrides {
    param([string]$path)
    
    $map = @{}
    if (!(Test-Path $path)) { 
        return $map 
    }
    
    try {
        $map = Import-Clixml -Path $path -ErrorAction Stop
        if (-not $map) { 
            $map = @{} 
        }
    } catch {
        Write-Verbose "USD overrideファイルの読み込みに失敗: $_"
    }
    
    return $map
}

<#
.SYNOPSIS
USDごとの個別設定（オーバーライド）を保存します。

.PARAMETER map
保存する設定マップ

.PARAMETER path
XMLファイルのパス

.EXAMPLE
Save-UsdOverrides $overrideMap "C:\path\to\usd_overrides.xml"
#>
function Save-UsdOverrides {
    param($map, [string]$path)
    
    try {
        $map | Export-Clixml -Path $path -Depth 10
    } catch {
        Write-Warning "USD overrideファイルの保存に失敗: $_"
    }
}

# ============================================================================
# 3. 通知サービス (Notification Service)
# ============================================================================

<#
.SYNOPSIS
Windows通知を送信します。

.PARAMETER title
通知のタイトル

.PARAMETER message
通知のメッセージ

.EXAMPLE
Send-WindowsToast "レンダリング完了" "すべてのジョブが完了しました"
#>
function Send-WindowsToast {
    param(
        [string]$title, 
        [string]$message
    )
    
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
        Write-Warning "通知の送信に失敗しました: $_"
    }
}

<#
.SYNOPSIS
Discord Webhookに通知を送信します。

.PARAMETER url
Discord WebhookのURL

.PARAMETER title
通知のタイトル

.PARAMETER message
通知のメッセージ

.PARAMETER color
埋め込みの色（デフォルト: 5814783 = 青系）

.EXAMPLE
Send-DiscordNotification "https://discord.com/api/webhooks/..." "レンダリング完了" "すべてのジョブが完了しました"
#>
function Send-DiscordNotification {
    param(
        [string]$url, 
        [string]$title, 
        [string]$message, 
        [int]$color = 5814783
    )
    
    if ([string]::IsNullOrWhiteSpace($url)) { 
        return 
    }
    
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
        Write-Warning "Discord通知の送信に失敗しました: $_"
    }
}

# ============================================================================
# モジュールのエクスポート（ドットソーシング使用時は不要）
# ============================================================================

# Export-ModuleMember -Function @(
#     'Normalize-UsdPath',
#     'Get-USDFrameRange',
#     'Parse-RangeText',
#     'Convert-RangePairs',
#     'Get-IniSettings',
#     'Load-UsdOverrides',
#     'Save-UsdOverrides',
#     'Send-WindowsToast',
#     'Send-DiscordNotification'
# )
