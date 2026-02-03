# HuskRenderLogic.psm1
# レンダリングプラン構築とhusk実行監視ロジック

# ============================================================================
# レンダリングプラン構築 (Render Job Logic)
# ============================================================================

<#
.SYNOPSIS
デフォルトのフレーム範囲を取得します。

.PARAMETER usdPath
USDファイルのパス

.PARAMETER conf
設定情報のハッシュテーブル

.EXAMPLE
Get-DefaultRanges "C:\path\to\file.usd" $conf
#>
function Get-DefaultRanges {
    param(
        [string]$usdPath, 
        $conf
    )
    
    $ranges = @()
    $batchMode = $conf["BATCH_MODE"]
    
    if ($batchMode -eq "Auto") {
        $range = Get-USDFrameRange $usdPath $conf["HOUDINI_BIN"]
        if ($range) { 
            $ranges += @{ start = [int]$range.start; end = [int]$range.end } 
        }
    } 
    elseif ($batchMode -eq "Manual") {
        $start = [int]$conf["START_FRM"]
        $end = [int]$conf["END_FRM"]
        $ranges += @{ start = $start; end = $end }
    }
    
    return ,$ranges
}

<#
.SYNOPSIS
レンダリングジョブの実行プランを構築します。

.DESCRIPTION
ユーザーがGUIで設定した内容やデフォルト値を統合して、最終的な「実行指示書」を作成します。
個別設定、グローバル設定、自動解析結果を統合して、レンダリングに必要な全パラメータを確定させます。

.PARAMETER usdPath
USDファイルのパス

.PARAMETER conf
グローバル設定情報

.PARAMETER override
個別設定（オーバーライド）情報

.EXAMPLE
Build-RenderJobPlan "C:\path\to\file.usd" $conf $override
#>
function Build-RenderJobPlan {
    param(
        [string]$usdPath, 
        $conf, 
        $override
    )
    
    $fullPath = Normalize-UsdPath $usdPath
    $usdName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)

    # オーバーライドから値を取得するヘルパー関数（存在すればオーバーライド、なければconf）
    $getValue = {
        param($key, $overrideKey = $null, [switch]$asInt)
        if (-not $overrideKey) { $overrideKey = $key }
        $val = if ($override -and $override.ContainsKey($overrideKey)) { 
            $override[$overrideKey] 
        } else { 
            $conf[$key] 
        }
        if ($asInt) { return [int]$val }
        return $val
    }

    # バッチモードと範囲の決定
    $batchMode = if ($override -and $override.batchMode) { 
        $override.batchMode 
    } else { 
        $conf["BATCH_MODE"] 
    }
    
    $ranges = @()
    if ($override -and $override.ranges) { 
        $ranges = Convert-RangePairs $override.ranges 
    }
    elseif ($batchMode -eq "Auto") { 
        $ranges = Get-DefaultRanges $fullPath $conf 
    }
    elseif ($batchMode -eq "Manual") {
        $start = if ($override -and $override.startFrame) { 
            [int]$override.startFrame 
        } else { 
            [int]$conf["START_FRM"] 
        }
        $end = if ($override -and $override.endFrame) { 
            [int]$override.endFrame 
        } else { 
            [int]$conf["END_FRM"] 
        }
        $ranges = @(@{ start = $start; end = $end })
    }
    
    if ($ranges.Count -eq 0) { 
        $ranges = @(@{ start = 1; end = 1 }) 
    }

    # 出力設定の決定
    $outToggle = & $getValue "OUT_TOGGLE" "outToggle"
    $useOutToggle = ($outToggle -eq "True") -or ($override -and $override.outPath)
    
    $renderOutDir = if ($override -and $override.outPath) { 
        $override.outPath 
    } elseif ($outToggle -eq "True" -and (& $getValue "OUT_PATH" "outPath")) { 
        & $getValue "OUT_PATH" "outPath" 
    } else { 
        Split-Path -Parent $fullPath 
    }
    
    # ファイル名設定の決定
    $nameMode = if ($override -and $override.nameMode) { 
        $override.nameMode 
    } else { 
        & $getValue "OUT_NAME_MODE" 
    }
    $nameBase = if ($override -and $override.nameBase) { 
        $override.nameBase 
    } else { 
        & $getValue "OUT_NAME_BASE" 
    }
    $baseName = if ($nameMode -eq "USD") { $usdName } else { $nameBase }

    # その他のレンダリング設定
    $padding = & $getValue "PADDING" -asInt
    $ext = & $getValue "EXT"
    $resScale = if ($override -and $override.resScale) { 
        [int]$override.resScale 
    } else { 
        & $getValue "RES_SCALE" -asInt 
    }
    $pixelSamples = if ($override -and $override.pixelSamples) { 
        [int]$override.pixelSamples 
    } else { 
        & $getValue "PIXEL_SAMPLES" -asInt 
    }
    $engine = if ($override -and $override.engine) { 
        $override.engine 
    } else { 
        & $getValue "ENGINE_TYPE" 
    }
    $disableMB = & $getValue "DISABLE_MOTIONBLUR" "disableMotionBlur"
    $notify = if ($override -and $override.notify) { 
        $override.notify 
    } else { 
        & $getValue "NOTIFY" 
    }
    $timeoutWarn = & $getValue "TIMEOUT_WARN" -asInt
    $timeoutKill = & $getValue "TIMEOUT_KILL" -asInt
    $discordWebhook = & $getValue "DISCORD_WEBHOOK"

    # レンダリングプランオブジェクトを返す
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
        DisableMotionBlur = ($disableMB -eq "True")
        Notify = $notify
        TimeoutWarn = $timeoutWarn
        TimeoutKill = $timeoutKill
        DiscordWebhook = $discordWebhook
    }
}

# ============================================================================
# モジュールのエクスポート（ドットソーシング使用時は不要）
# ============================================================================

# Export-ModuleMember -Function @(
#     'Get-DefaultRanges',
#     'Build-RenderJobPlan'
# )
