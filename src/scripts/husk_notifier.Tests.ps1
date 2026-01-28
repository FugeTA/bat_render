# ================================================================
# husk_notifier.Tests.ps1
# husk_notifier.psm1 のテストスイート (Pester v3互換)
# ================================================================

# テスト対象モジュールをインポート
$modulePath = Join-Path $PSScriptRoot "husk_notifier.psm1"
Import-Module $modulePath -Force

Describe "husk_notifier Module Tests" {
    
    Context "Send-WindowsToast" {
        It "does not throw error when called with valid parameters" {
            # Windows Toast通知は実際に表示されるが、エラーが発生しないことを確認
            { Send-WindowsToast "Test Title" "Test Message" } | Should Not Throw
        }
        
        It "handles empty title gracefully" {
            { Send-WindowsToast "" "Test Message" } | Should Not Throw
        }
        
        It "handles empty message gracefully" {
            { Send-WindowsToast "Test Title" "" } | Should Not Throw
        }
    }
    
    Context "Send-DiscordNotification" {
        It "returns immediately for empty webhook URL" {
            # 空のURLでは何も送信されず、エラーも発生しない
            { Send-DiscordNotification "" "Title" "Message" } | Should Not Throw
        }
        
        It "returns immediately for null webhook URL" {
            { Send-DiscordNotification $null "Title" "Message" } | Should Not Throw
        }
        
        It "handles invalid webhook URL gracefully" {
            # 無効なURLでもエラーメッセージを出力して続行
            { Send-DiscordNotification "https://invalid.url" "Title" "Message" } | Should Not Throw
        }
        
        It "accepts custom color parameter" {
            { Send-DiscordNotification "" "Title" "Message" 16711680 } | Should Not Throw
        }
    }
    
    Context "Send-Notification (unified interface)" {
        It "handles 'None' notification type" {
            { Send-Notification "None" "Title" "Message" } | Should Not Throw
        }
        
        It "handles 'Windows Toast' notification type" {
            { Send-Notification "Windows Toast" "Title" "Message" } | Should Not Throw
        }
        
        It "handles 'Discord' notification type with empty webhook" {
            { Send-Notification "Discord" "Title" "Message" "" } | Should Not Throw
        }
        
        It "handles 'Discord' notification type with webhook URL" {
            # 無効なURLでもエラーハンドリングされる
            { Send-Notification "Discord" "Title" "Message" "https://invalid.url" } | Should Not Throw
        }
        
        It "handles unknown notification type gracefully" {
            { Send-Notification "UnknownType" "Title" "Message" } | Should Not Throw
        }
        
        It "accepts custom color parameter for Discord" {
            { Send-Notification "Discord" "Title" "Message" "" 65280 } | Should Not Throw
        }
        
        It "uses default parameters when optional ones are omitted" {
            { Send-Notification "None" "Title" "Message" } | Should Not Throw
        }
    }
    
    Context "Function exports" {
        It "exports Send-WindowsToast function" {
            Get-Command Send-WindowsToast -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
        
        It "exports Send-DiscordNotification function" {
            Get-Command Send-DiscordNotification -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
        
        It "exports Send-Notification function" {
            Get-Command Send-Notification -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }
}
