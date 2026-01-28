# ================================================================
# husk_utils.ps1
# 共通ユーティリティ関数モジュール
# 
# husk_gui.ps1 と husk_logger.ps1 で共有される関数を定義
# ================================================================

# ===== 基本ユーティリティ =====

<#
.SYNOPSIS
    USDファイルパスを正規化します
.PARAMETER path
    正規化するパス
.OUTPUTS
    正規化されたパス、または失敗時は元のパス
#>
function Resolve-UsdPath {
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
    USD個別設定（オーバーライド）をXMLファイルから読み込みます
.PARAMETER path
    XMLファイルのパス
.OUTPUTS
    オーバーライド設定のハッシュテーブル
#>
function Import-UsdOverrides {
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

<#
.SYNOPSIS
    USD個別設定（オーバーライド）をXMLファイルに保存します
.PARAMETER map
    保存するハッシュテーブル
.PARAMETER path
    保存先XMLファイルのパス
#>
function Export-UsdOverrides {
    param($map, [string]$path)
    $map | Export-Clixml -Path $path -Depth 10
}

<#
.SYNOPSIS
    INI形式の設定ファイルを読み込みます
.PARAMETER iniPath
    INIファイルのパス
.PARAMETER defaultConfig
    デフォルト値のハッシュテーブル（オプション）
.OUTPUTS
    設定のハッシュテーブル
#>
function Import-ConfigIni {
    param(
        [string]$iniPath, 
        [hashtable]$defaultConfig = @{}
    )
    
    $conf = if ($defaultConfig) { $defaultConfig.Clone() } else { @{} }
    
    if (Test-Path $iniPath) {
        Get-Content $iniPath | ForEach-Object {
            if ($_ -match "^([^=]+)=(.*)$") {
                $conf[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }
    
    return $conf
}

# ===== USD解析 =====

<#
.SYNOPSIS
    USDファイルのフレーム範囲を解析します（Houdini hython使用）
.PARAMETER usdPath
    解析するUSDファイルのパス
.PARAMETER houBin
    Houdini binフォルダのパス
.OUTPUTS
    フレーム範囲のハッシュテーブル @{ start = <int>; end = <int> }
#>
function Get-USDFrameRange {
    param($usdPath, $houBin)
    
    $hythonExe = Join-Path $houBin "hython.exe"
    if (!(Test-Path $hythonExe)) { return $null }
    
    # USDのStageを開いてStartTimeとEndTimeを取得するPythonコード
    $pyCode = "from pxr import Usd; stage = Usd.Stage.Open('$($usdPath.Replace('\','/'))'); print(f'START:{stage.GetStartTimeCode()} END:{stage.GetEndTimeCode()}')"
    
    try {
        $out = & "$hythonExe" -c "$pyCode" 2>$null
        if ($out -match "START:([-?\d\.]+) END:([-?\d\.]+)") {
            return @{ 
                start = [math]::Floor([double]$matches[1])
                end = [math]::Floor([double]$matches[2])
            }
        }
    } catch {}
    
    return $null
}

# ===== データ変換 =====

<#
.SYNOPSIS
    範囲データを正規化されたハッシュテーブル配列に変換します
.PARAMETER ranges
    変換する範囲データ（ハッシュテーブルまたは配列）
.OUTPUTS
    @{ start = <int>; end = <int> } 形式の配列
#>
function Convert-RangePairs {
    param($ranges)
    
    $result = @()
    if (-not $ranges) { return $result }
    
    foreach ($r in $ranges) {
        # ハッシュテーブル形式の場合
        if ($r -is [hashtable] -and $r.ContainsKey('start') -and $r.ContainsKey('end')) {
            $result += ,@{ start = [int]$r.start; end = [int]$r.end }
        }
        # 旧形式（配列）との互換性
        elseif ($r -is [array] -and $r.Count -ge 1) {
            $s = [int]$r[0]
            $e = if ($r.Count -ge 2) { [int]$r[1] } else { [int]$r[0] }
            $result += ,@{ start = $s; end = $e }
        }
        # 単一の数値の場合
        elseif ($r -is [int] -or $r -is [long]) {
            $result += ,@{ start = [int]$r; end = [int]$r }
        }
    }
    
    return ,$result
}

<#
.SYNOPSIS
    カンマ区切りの範囲文字列をハッシュテーブル配列に変換します
.PARAMETER text
    範囲文字列（例: "1-10,20,30-40"）
.OUTPUTS
    @{ start = <int>; end = <int> } 形式の配列、または解析失敗時は $null
.EXAMPLE
    ConvertFrom-RangeText "1-10,20,30-40"
    # 出力: @(@{start=1;end=10}, @{start=20;end=20}, @{start=30;end=40})
#>
function ConvertFrom-RangeText {
    param([string]$text)
    
    $ranges = @()
    if ([string]::IsNullOrWhiteSpace($text)) { return $ranges }
    
    # 空白を除去して処理を簡素化
    $cleaned = $text -replace '\s+', ''
    
    foreach ($chunk in $cleaned.Split(",")) {
        if (-not $chunk) { continue }
        
        if ($chunk -match "^(-?\d+)-(-?\d+)$") {
            # 範囲形式: "1-10"
            $start = [int]$matches[1]
            $end = [int]$matches[2]
            $ranges += ,@{ start = $start; end = $end }
        } elseif ($chunk -match "^(-?\d+)$") {
            # 単一フレーム: "20"
            $val = [int]$matches[1]
            $ranges += ,@{ start = $val; end = $val }
        } else {
            # 解析エラー
            return $null
        }
    }
    
    return ,$ranges
}

# モジュールから公開する関数を明示的にエクスポート
Export-ModuleMember -Function @(
    'Resolve-UsdPath',
    'Import-UsdOverrides',
    'Export-UsdOverrides',
    'Import-ConfigIni',
    'Get-USDFrameRange',
    'Convert-RangePairs',
    'ConvertFrom-RangeText'
)
