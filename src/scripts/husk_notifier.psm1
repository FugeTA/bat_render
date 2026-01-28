# ================================================================
# husk_notifier.ps1
# 通知機能モジュール
# 
# Windows Toast通知とDiscord Webhook通知を提供
# ================================================================

<#
.SYNOPSIS
    Windows Toast通知を送信します
.PARAMETER title
    通知のタイトル
.PARAMETER message
    通知のメッセージ本文
.EXAMPLE
    Send-WindowsToast "レンダリング完了" "全てのフレームが正常に完了しました"
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
        Write-Host "[!] 通知の送信に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Discord Webhook経由で通知を送信します
.PARAMETER url
    Discord Webhook URL
.PARAMETER title
    埋め込みメッセージのタイトル
.PARAMETER message
    埋め込みメッセージの本文
.PARAMETER color
    埋め込みメッセージの色（10進数）。デフォルトは5814783（青緑色）
.EXAMPLE
    Send-DiscordNotification "https://discord.com/api/webhooks/..." "レンダリング完了" "処理が完了しました" 65280
#>
function Send-DiscordNotification {
    param(
        [string]$url, 
        [string]$title, 
        [string]$message, 
        [int]$color = 5814783
    )
    
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    
    $payload = @{
        embeds = @(@{
            title = $title
            description = "@everyone $message"
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

<#
.SYNOPSIS
    統一インターフェースで通知を送信します
.PARAMETER notifyType
    通知タイプ: "None", "Windows Toast", "Discord"
.PARAMETER title
    通知のタイトル
.PARAMETER message
    通知のメッセージ
.PARAMETER webhookUrl
    Discord Webhook URL（notifyType="Discord"の場合に使用）
.PARAMETER color
    Discord埋め込みメッセージの色（オプション）
.EXAMPLE
    Send-Notification "Windows Toast" "完了" "処理が完了しました"
.EXAMPLE
    Send-Notification "Discord" "エラー" "処理に失敗しました" "https://..." 16711680
#>
function Send-Notification {
    param(
        [string]$notifyType,
        [string]$title,
        [string]$message,
        [string]$webhookUrl = "",
        [int]$color = 5814783
    )
    
    switch ($notifyType) {
        "Windows Toast" {
            Send-WindowsToast $title $message
        }
        "Discord" {
            if (-not [string]::IsNullOrWhiteSpace($webhookUrl)) {
                Send-DiscordNotification $webhookUrl $title $message $color
            }
        }
        "None" {
            # 何もしない
        }
        default {
            # 不明な通知タイプは無視
        }
    }
}

# モジュールから公開する関数を明示的にエクスポート
Export-ModuleMember -Function @(
    'Send-WindowsToast',
    'Send-DiscordNotification',
    'Send-Notification'
)
