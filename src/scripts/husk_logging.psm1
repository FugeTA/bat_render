# ================================================================
# husk_logging.ps1
# ログ機能モジュール
# ================================================================

<#
.SYNOPSIS
    レンダリングログファイルを初期化します
.PARAMETER logDir
    ログディレクトリのパス
.PARAMETER computerName
    コンピューター名（省略時は環境変数から取得）
.OUTPUTS
    ログファイルのフルパス
#>
function Initialize-RenderLog {
    param(
        [string]$logDir,
        [string]$computerName = $env:COMPUTERNAME
    )
    
    # ログディレクトリが存在しない場合は作成
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory $logDir | Out-Null
    }
    
    # ログファイル名を生成（例: PC01_20260128_1430.log）
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmm'
    $logFileName = "$computerName`_$timestamp.log"
    $logPath = Join-Path $logDir $logFileName
    
    return $logPath
}

<#
.SYNOPSIS
    コンソールとログファイルの両方に出力します
.PARAMETER message
    出力するメッセージ
.PARAMETER logFile
    ログファイルのパス
.PARAMETER color
    コンソール出力の色（省略可）
.PARAMETER noNewline
    改行を抑制するかどうか
#>
function Write-RenderLog {
    param(
        [string]$message,
        [string]$logFile,
        [string]$color = "",
        [switch]$noNewline
    )
    
    # コンソールに出力
    if ($color) {
        if ($noNewline) {
            Write-Host $message -ForegroundColor $color -NoNewline
        } else {
            Write-Host $message -ForegroundColor $color
        }
    } else {
        if ($noNewline) {
            Write-Host $message -NoNewline
        } else {
            Write-Host $message
        }
    }
    
    # ログファイルに出力（改行制御付き）
    if (!$noNewline) {
        $message | Out-File $logFile -Append -Encoding utf8
    }
}

<#
.SYNOPSIS
    ログファイルのみに出力します（コンソールには出力しません）
.PARAMETER message
    出力するメッセージ
.PARAMETER logFile
    ログファイルのパス
#>
function Write-LogOnly {
    param(
        [string]$message,
        [string]$logFile
    )
    
    $message | Out-File $logFile -Append -Encoding utf8
}

<#
.SYNOPSIS
    ログファイルに複数行を一度に書き込みます
.PARAMETER messages
    出力するメッセージの配列
.PARAMETER logFile
    ログファイルのパス
#>
function Write-LogBatch {
    param(
        [string[]]$messages,
        [string]$logFile
    )
    
    $messages | Out-File $logFile -Append -Encoding utf8
}

# モジュールから公開する関数を明示的にエクスポート
Export-ModuleMember -Function @(
    'Initialize-RenderLog',
    'Write-RenderLog',
    'Write-LogOnly',
    'Write-LogBatch'
)
