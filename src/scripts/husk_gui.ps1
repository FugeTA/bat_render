param([string]$dropFile)

$baseDir = Split-Path -Parent $PSScriptRoot
$configDir = Join-Path $baseDir "config"
if (!(Test-Path $configDir)) { New-Item -ItemType Directory $configDir | Out-Null }
$script:iniPath = Join-Path $configDir "settings.ini"
$overridePath = Join-Path $configDir "usd_overrides.xml"

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
    } catch {}
    return $map
}

function Get-IniSettings {
    $c = @{ 
        USD_LIST=""; OUT_PATH=""; START_FRM="1"; END_FRM="1"; 
        REBOOT="False"; SHUTDOWN_ACTION="None"; SINGLE="False"; HOUDINI_BIN="C:\Program Files\Side Effects Software\Houdini 21.0.440\bin";
        BATCH_MODE="Auto"; OUT_TOGGLE="True"; OUT_NAME_MODE="USD"; OUT_NAME_BASE="render";
        EXT="exr"; PADDING="4"; RES_SCALE="100"; PIXEL_SAMPLES="0"; NOTIFY="None"; DISCORD_WEBHOOK=""; TIMEOUT_WARN="0"; TIMEOUT_KILL="0";
        ENGINE_TYPE="cpu"; DISABLE_MOTIONBLUR="False";
        LOCK_RENDER="False"; LOCK_TIMEOUT="False"
    }
    if (Test-Path $script:iniPath) {
        Get-Content $script:iniPath | ForEach-Object {
            if ($_ -match "^([^=]+)=(.*)$") { $c[$matches[1].Trim()] = $matches[2].Trim() }
        }
    }
    return $c
}

function Save-UsdOverrides {
    param($map, [string]$path)
    $map | Export-Clixml -Path $path -Depth 10
}

function Parse-RangeText {
    param([string]$text)
    $ranges = @()
    if ([string]::IsNullOrWhiteSpace($text)) { return $ranges }
    foreach ($chunk in $text.Split(",")) {
        $token = $chunk.Trim()
        if (-not $token) { continue }
        if ($token -match "^(-?\d+)-(-?\d+)$") {
            $start = [int]$matches[1]
            $end = [int]$matches[2]
            $ranges += @{ start = $start; end = $end }
        } elseif ($token -match "^(-?\d+)$") {
            $val = [int]$matches[1]
            $ranges += @{ start = $val; end = $val }
        } else {
            return $null
        }
    }
    return $ranges
}

# コンテキストメニューのヘルパー関数
function Add-SaveDefaultMenu {
    param(
        [System.Windows.Forms.Control]$control,
        [string]$iniKey,
        [string]$displayName = "",
        [string]$valueIfChecked = ""
    )
    
    if (-not $displayName) { $displayName = $iniKey }
    
    # iniPathを保存
    $localIniPath = $script:iniPath
    
    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    
    # デフォルトとして保存
    $menuSave = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuSave.Text = "この値をデフォルトとして保存"
    $menuSave.Add_Click({
        # コントロールの値を取得
        $value = if ($this.Tag.Control -is [System.Windows.Forms.NumericUpDown]) {
            $this.Tag.Control.Value
        } elseif ($this.Tag.Control -is [System.Windows.Forms.TrackBar]) {
            $this.Tag.Control.Value * 10
        } elseif ($this.Tag.Control -is [System.Windows.Forms.RadioButton]) {
            # ラジオボタンのグループ内でチェックされているものを探す
            $parent = $this.Tag.Control.Parent
            $checkedRadio = $parent.Controls | Where-Object {
                $_ -is [System.Windows.Forms.RadioButton] -and $_.Checked
            } | Select-Object -First 1
            
            if ($checkedRadio -and $checkedRadio.ContextMenuStrip) {
                $checkedRadio.ContextMenuStrip.Items[0].Tag.ValueIfChecked
            } else {
                "True"
            }
        } elseif ($this.Tag.Control -is [System.Windows.Forms.CheckBox]) {
            if ($this.Tag.ValueIfChecked) {
                if ($this.Tag.Control.Checked) { $this.Tag.ValueIfChecked } else { "Multi" }
            } else {
                $this.Tag.Control.Checked.ToString()
            }
        } else {
            $this.Tag.Control.Text
        }
        
        # INIファイルを読み込んで更新
        if (Test-Path $this.Tag.IniPath) {
            $lines = Get-Content $this.Tag.IniPath
        } else {
            $lines = @()
        }
        
        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^$($this.Tag.Key)=") {
                $lines[$i] = "$($this.Tag.Key)=$value"
                $found = $true
                break
            }
        }
        if (-not $found) {
            $lines += "$($this.Tag.Key)=$value"
        }
        
        $lines | Set-Content $this.Tag.IniPath -Encoding Default
        
        # メモリ上の設定キャッシュを最新の状態に更新
        $script:conf = Get-IniSettings

        # 全行の表示を更新（設定列の〇などを再計算）
        if ($gridUSD) {
            foreach ($row in $gridUSD.Rows) { if ($row.Tag) { Update-GridRow $row.Tag } }
        }
        if ($updatePreview) { & $updatePreview }

        [System.Windows.Forms.MessageBox]::Show(
            "デフォルト値を保存しました:`n$($this.Tag.DisplayName) = $value",
            "保存完了",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    })
    $menuSave.Tag = @{ Control = $control; Key = $iniKey; DisplayName = $displayName; IniPath = $localIniPath; ValueIfChecked = $valueIfChecked }
    
    # 値をクリップボードにコピー
    $menuCopy = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuCopy.Text = "値をコピー"
    $menuCopy.Add_Click({
        $value = if ($this.Tag.Control -is [System.Windows.Forms.NumericUpDown]) {
            $this.Tag.Control.Value
        } elseif ($this.Tag.Control -is [System.Windows.Forms.TrackBar]) {
            $this.Tag.Control.Value * 10
        } elseif ($this.Tag.Control -is [System.Windows.Forms.RadioButton]) {
            # ラジオボタンのグループ内でチェックされているものを探す
            $parent = $this.Tag.Control.Parent
            $checkedRadio = $parent.Controls | Where-Object {
                $_ -is [System.Windows.Forms.RadioButton] -and $_.Checked
            } | Select-Object -First 1
            
            if ($checkedRadio -and $checkedRadio.ContextMenuStrip) {
                $checkedRadio.ContextMenuStrip.Items[0].Tag.ValueIfChecked
            } else {
                "True"
            }
        } elseif ($this.Tag.Control -is [System.Windows.Forms.CheckBox]) {
            if ($this.Tag.ValueIfChecked) {
                if ($this.Tag.Control.Checked) { $this.Tag.ValueIfChecked } else { "Multi" }
            } else {
                $this.Tag.Control.Checked.ToString()
            }
        } else {
            $this.Tag.Control.Text
        }
        [System.Windows.Forms.Clipboard]::SetText($value.ToString())
        [System.Windows.Forms.MessageBox]::Show(
            "クリップボードにコピーしました: $value",
            "コピー完了",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    })
    $menuCopy.Tag = @{ Control = $control; ValueIfChecked = $valueIfChecked }
    
    $contextMenu.Items.AddRange(@($menuSave, $menuCopy))
    $control.ContextMenuStrip = $contextMenu
}

# 1. デフォルト設定の読み込み
$script:conf = Get-IniSettings
$script:usdOverrides = Load-UsdOverrides $overridePath

Add-Type -AssemblyName System.Windows.Forms
$f = New-Object Windows.Forms.Form
$f.Text = "Husk Batch Launcher"; $f.StartPosition = "CenterScreen"
$f.AutoSize = $true
$f.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink

# --- 解析関数 ---
function Get-USDFrameRange {
    param($usdPath, $houBin)
    if ([string]::IsNullOrWhiteSpace($usdPath) -or !(Test-Path $usdPath)) { return $null }
    $hythonExe = Join-Path $houBin "hython.exe"
    if (!(Test-Path $hythonExe)) { return $null }
    $pyCode = "from pxr import Usd; stage = Usd.Stage.Open('$($usdPath.Replace('\','/'))'); print(f'START:{stage.GetStartTimeCode()} END:{stage.GetEndTimeCode()}')"
    $si = New-Object System.Diagnostics.ProcessStartInfo -Property @{
        FileName = $hythonExe; Arguments = "-c `"$pyCode`""; RedirectStandardOutput = $true;
        UseShellExecute = $false; CreateNoWindow = $true
    }
    $proc = [System.Diagnostics.Process]::Start($si); $out = $proc.StandardOutput.ReadToEnd(); $proc.WaitForExit()
    if ($out -match "START:([-?\d\.]+) END:([-?\d\.]+)") {
        return @{ start = [math]::Floor([double]$matches[1]); end = [math]::Floor([double]$matches[2]) }
    }
    return $null
}

function Get-RangeSummary {
    param($override, $conf)
    if ($override -and $override.batchMode) {
        if ($override.batchMode -eq "Auto") { return "(自動解析)" }
        elseif ($override.batchMode -eq "Manual") {
            $s = if($override.startFrame){ $override.startFrame }else{ $conf["START_FRM"] }
            $e = if($override.endFrame){ $override.endFrame }else{ $conf["END_FRM"] }
            return "$s-$e"
        }
        elseif ($override.batchMode -eq "Multi" -and $override.ranges) {
            $parts = $override.ranges | ForEach-Object {
                if ($_.start -eq $_.end) { "{0}" -f $_.start }
                else { "{0}-{1}" -f $_.start, $_.end }
            }
            return ($parts -join ", ")
        }
    }
    if ($override -and $override.ranges) {
        $parts = $override.ranges | ForEach-Object {
            if ($_.start -eq $_.end) { "{0}" -f $_.start }
            else { "{0}-{1}" -f $_.start, $_.end }
        }
        return ($parts -join ", ")
    }
    # デフォルト値を表示
    $batchMode = $conf["BATCH_MODE"]
    if ($batchMode -eq "Auto") { return "(自動解析)" }
    else { return "$($conf['START_FRM'])-$($conf['END_FRM'])" }
}

function Get-OutputSummary {
    param($override, $conf)
    # outToggleの状態を確認
    $outToggle = if ($override -and $override.ContainsKey('outToggle')) { 
        $override.outToggle 
    } else { 
        [System.Convert]::ToBoolean($conf["OUT_TOGGLE"]) 
    }
    
    # outToggleがオフの場合は「(デフォルト)」を表示
    if (-not $outToggle) { return "(デフォルト)" }
    
    if ($override -and $override.outPath) {
        $short = [System.IO.Path]::GetFileName($override.outPath)
        if($short){ return $short }else{ return $override.outPath }
    }
    # デフォルト値を表示
    if ([string]::IsNullOrWhiteSpace($conf["OUT_PATH"])) { return "(USD同階層)" }
    $short = [System.IO.Path]::GetFileName($conf["OUT_PATH"])
    if($short){ return $short }else{ return $conf["OUT_PATH"] }
}

function Get-StatusText {
    param($override, $conf)
    if (-not $override -or $override.Keys.Count -eq 0) { return "" }
    
    foreach ($key in $override.Keys) {
        $confKey = switch ($key) {
            "batchMode"    { "BATCH_MODE" }
            "startFrame"   { "START_FRM" }
            "endFrame"     { "END_FRM" }
            "outPath"      { "OUT_PATH" }
            "outToggle"    { "OUT_TOGGLE" }
            "nameMode"     { "OUT_NAME_MODE" }
            "nameBase"     { "OUT_NAME_BASE" }
            "ext"          { "EXT" }
            "padding"      { "PADDING" }
            "resScale"     { "RES_SCALE" }
            "pixelSamples" { "PIXEL_SAMPLES" }
            "engine"       { "ENGINE_TYPE" }
            "notify"       { "NOTIFY" }
            "disableMotionBlur" { "DISABLE_MOTIONBLUR" }
            "ranges"       { return "〇" } # 複数範囲設定は常にオーバーライド扱い
            default        { $null }
        }
        if ($null -eq $confKey) { continue }
        $val = $override[$key]; $cVal = $conf[$confKey]
        if ($val -is [bool] -or $cVal -eq "True" -or $cVal -eq "False") {
            if ([System.Convert]::ToBoolean($val) -ne [System.Convert]::ToBoolean($cVal)) { return "〇" }
        } elseif ($val -is [int] -or $val -is [long] -or $cVal -match '^-?\d+$') {
            if ([int]$val -ne [int]$cVal) { return "〇" }
        } elseif ($val.ToString() -ne $cVal.ToString()) { return "〇" }
    }
    return ""
}

$script:currentEditingUSD = $null
$script:updatingFromSelection = $false

function Load-UsdSettings {
    param([string]$usdPath)
    
    # XMLファイルを再読み込みしてキャッシュを更新（外部編集の反映）
    $script:usdOverrides = Load-UsdOverrides $overridePath

    $script:updatingFromSelection = $true
    $script:currentEditingUSD = $usdPath
    
    if ([string]::IsNullOrWhiteSpace($usdPath)) {
        # グローバル設定を表示
        $lEditingUSD.Text = "[グローバル設定]"
        $lEditingUSD.ForeColor = "Gray"
        $txtRanges.Text = ""
        $txtRanges.Enabled = $false
        $script:updatingFromSelection = $false
        return
    }
    
    $norm = Normalize-UsdPath $usdPath
    $override = if($norm){ $usdOverrides[$norm] }else{ $null }
    
    $fname = [System.IO.Path]::GetFileName($usdPath)
    $lEditingUSD.Text = "編集中: $fname"
    $lEditingUSD.ForeColor = "DarkBlue"
    
    # すべてのコントロールをデフォルト値にリセット
    $batchMode = $conf["BATCH_MODE"]
    if ($batchMode -eq "Auto") { $rbAuto.Checked = $true }
    elseif ($batchMode -eq "Manual") { $rbManual.Checked = $true }
    else { $rbAuto.Checked = $true }
    $rbMulti.Checked = $false
    $txtRanges.Text = ""
    $nFS.Value = [int]$conf["START_FRM"]
    $nFE.Value = [int]$conf["END_FRM"]
    $script:lockRenderBtn.Checked = [System.Convert]::ToBoolean($conf["LOCK_RENDER"])
    $script:lockTimeoutBtn.Checked = [System.Convert]::ToBoolean($conf["LOCK_TIMEOUT"])
    $tOUT.Text = $conf["OUT_PATH"]
    $rbNameUSD.Checked = ($conf["OUT_NAME_MODE"] -eq "USD")
    $rbNameCustom.Checked = ($conf["OUT_NAME_MODE"] -eq "Custom")
    $tNameBase.Text = $conf["OUT_NAME_BASE"]
    $chkOutToggle.Checked = [System.Convert]::ToBoolean($conf["OUT_TOGGLE"])
    $tExt.Text = $conf["EXT"]
    $nPad.Value = [int]$conf["PADDING"]
    $trackRes.Value = [int]([float]$conf["RES_SCALE"]/10)
    $nPS.Value = [int]$conf["PIXEL_SAMPLES"]
    $comboEngine.Text = $conf["ENGINE_TYPE"]
    $chkDisableMB.Checked = [System.Convert]::ToBoolean($conf["DISABLE_MOTIONBLUR"])
    $comboNoti.Text = $conf["NOTIFY"]
    
    # オーバーライドがあれば適用
    if ($override) {
        # 範囲設定モードを復元
        if ($override.batchMode -eq "Auto") {
            $rbAuto.Checked = $true
        } elseif ($override.batchMode -eq "Manual") {
            $rbManual.Checked = $true
            if ($null -ne $override.startFrame) { $nFS.Value = [int]$override.startFrame }
            if ($null -ne $override.endFrame) { $nFE.Value = [int]$override.endFrame }
        } elseif ($override.batchMode -eq "Multi") {
            $rbMulti.Checked = $true
            if ($override.ranges) {
                $txtRanges.Text = ($override.ranges | ForEach-Object { 
                    if ($_.start -eq $_.end) { "{0}" -f $_.start }
                    else { "{0}-{1}" -f $_.start, $_.end }
                } ) -join ","
            }
        } elseif ($override.ranges) {
            # 旧形式の互換性のため
            $rbMulti.Checked = $true
            $txtRanges.Text = ($override.ranges | ForEach-Object { 
                if ($_.start -eq $_.end) { "{0}" -f $_.start }
                else { "{0}-{1}" -f $_.start, $_.end }
            } ) -join ","
        }
        if ($override.ContainsKey('lockRender')) { $script:lockRenderBtn.Checked = $override.lockRender }
        if ($override.ContainsKey('lockTimeout')) { $script:lockTimeoutBtn.Checked = $override.lockTimeout }
        if ($override.outPath) { $tOUT.Text = $override.outPath }
        if ($override.nameMode -eq "Custom") { $rbNameCustom.Checked = $true; if($override.nameBase){ $tNameBase.Text = $override.nameBase } }
        elseif ($override.nameMode -eq "USD") { $rbNameUSD.Checked = $true }
        if ($override.ContainsKey('outToggle')) { $chkOutToggle.Checked = $override.outToggle }
        if ($override.ext) { $tExt.Text = $override.ext }
        if ($null -ne $override.padding) { $nPad.Value = [int]$override.padding }
        if ($null -ne $override.resScale) { $trackRes.Value = [int]($override.resScale / 10) }
        if ($null -ne $override.pixelSamples) { $nPS.Value = [int]$override.pixelSamples }
        if ($override.engine) { $comboEngine.Text = $override.engine }
        if ($override.ContainsKey('disableMotionBlur')) { $chkDisableMB.Checked = $override.disableMotionBlur }
        if ($override.notify) { $comboNoti.Text = $override.notify }
    }
    
    $script:updatingFromSelection = $false
    # グリッドの表示を更新（外部編集による「〇」の有無などを反映）
    if ($usdPath) { Update-GridRow $usdPath }
}

function Save-CurrentUsdSettings {
    if ($script:updatingFromSelection) { return }
    if ([string]::IsNullOrWhiteSpace($script:currentEditingUSD)) { return }
    
    $norm = Normalize-UsdPath $script:currentEditingUSD
    if (-not $norm) { return }
    
    $override = @{}
    
    # 範囲設定モードを保存
    $currentBatchMode = if($rbAuto.Checked){"Auto"} elseif($rbManual.Checked){"Manual"} elseif($rbMulti.Checked){"Multi"}
    if ($currentBatchMode -ne $conf["BATCH_MODE"]) {
        $override.batchMode = $currentBatchMode
    }

    if ($rbManual.Checked) {
        if ([int]$nFS.Value -ne [int]$conf["START_FRM"]) { $override.startFrame = [int]$nFS.Value }
        if ([int]$nFE.Value -ne [int]$conf["END_FRM"]) { $override.endFrame = [int]$nFE.Value }
    } elseif ($rbMulti.Checked) {
        $rangePairs = Parse-RangeText $txtRanges.Text
        if ($rangePairs -ne $null -and $rangePairs.Count -gt 0) { 
            $override.ranges = $rangePairs
        }
    }
    
    if ($script:lockRenderBtn.Checked -ne [System.Convert]::ToBoolean($conf["LOCK_RENDER"])) { $override.lockRender = $script:lockRenderBtn.Checked }
    if ($script:lockTimeoutBtn.Checked -ne [System.Convert]::ToBoolean($conf["LOCK_TIMEOUT"])) { $override.lockTimeout = $script:lockTimeoutBtn.Checked }

    if ($chkOutToggle.Checked -ne [System.Convert]::ToBoolean($conf["OUT_TOGGLE"])) { $override.outToggle = $chkOutToggle.Checked }
    if (-not [string]::IsNullOrWhiteSpace($tOUT.Text) -and $tOUT.Text -ne $conf["OUT_PATH"]) { $override.outPath = $tOUT.Text }
    
    $currentNameMode = if($rbNameUSD.Checked){"USD"} else {"Custom"}
    if ($currentNameMode -ne $conf["OUT_NAME_MODE"]) { $override.nameMode = $currentNameMode }
    
    if ($rbNameCustom.Checked -and $tNameBase.Text -ne $conf["OUT_NAME_BASE"]) {
        $override.nameBase = $tNameBase.Text
    }

    if ($tExt.Text -ne $conf["EXT"]) { $override.ext = $tExt.Text }
    if ([int]$nPad.Value -ne [int]$conf["PADDING"]) { $override.padding = [int]$nPad.Value }
    if ($trackRes.Value * 10 -ne [int]$conf["RES_SCALE"]) { $override.resScale = [int]($trackRes.Value * 10) }
    if ($nPS.Value -ne [int]$conf["PIXEL_SAMPLES"]) { $override.pixelSamples = [int]$nPS.Value }
    if ($comboEngine.Text -ne $conf["ENGINE_TYPE"]) { $override.engine = $comboEngine.Text }
    if ($chkDisableMB.Checked -ne [System.Convert]::ToBoolean($conf["DISABLE_MOTIONBLUR"])) { $override.disableMotionBlur = $chkDisableMB.Checked }
    if ($comboNoti.Text -ne $conf["NOTIFY"]) { $override.notify = $comboNoti.Text }
    
    if ($override.Keys.Count -gt 0) {
        $usdOverrides[$norm] = $override
    } else {
        $usdOverrides.Remove($norm) | Out-Null
    }
    
    # 変更を即座にXMLファイルに保存
    Save-UsdOverrides $usdOverrides $overridePath
    
    Update-GridRow $script:currentEditingUSD
}

function Update-GridRow {
    param([string]$usdPath)
    for($i=0; $i -lt $gridUSD.Rows.Count; $i++){
        if($gridUSD.Rows[$i].Tag -eq $usdPath){
            $norm = Normalize-UsdPath $usdPath
            $ov = if($norm){ $usdOverrides[$norm] }else{ $null }
            $gridUSD.Rows[$i].Cells[1].Value = Get-RangeSummary $ov $conf
            $gridUSD.Rows[$i].Cells[2].Value = Get-OutputSummary $ov $conf
            $gridUSD.Rows[$i].Cells[3].Value = Get-StatusText $ov $conf
            break
        }
    }
}

function Add-LockButton {
    param([System.Windows.Forms.GroupBox]$group)
    $lockBtn = New-Object Windows.Forms.CheckBox
    $lockBtn.Text = "🔓"
    $lockBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lockBtn.ImageAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lockBtn.Appearance = "Button"
    $lockBtn.Size = "28,38"
    $lockBtn.Location = New-Object System.Drawing.Point(($group.Width - 30), -10)
    $lockBtn.FlatStyle = "Flat"
    $lockBtn.FlatAppearance.BorderSize = 0
    #$lockBtn.BackColor = [System.Drawing.Color]::Transparent
    $lockBtn.Add_CheckedChanged({
        $locked = $this.Checked
        $this.Text = if ($locked) { "🔒"} else { "🔓" }
        if ($updateControlState) { & $updateControlState }
        Save-CurrentUsdSettings
    })
    $group.Controls.Add($lockBtn)
    $lockBtn.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 12)
    $lockBtn.BringToFront()
    return $lockBtn
}

$leftX = 20; $y = 10
# 1. Houdini Bin
$l1 = New-Object Windows.Forms.Label; $l1.Text="1. Houdini Binフォルダ:"; $l1.Location="$leftX,$y"; $l1.AutoSize=$true; $f.Controls.Add($l1)
$tHOU = New-Object Windows.Forms.TextBox; $tHOU.Text=$conf["HOUDINI_BIN"]; $tHOU.Location="$leftX,$($y+20)"; $tHOU.Width=460; $f.Controls.Add($tHOU)
$lHouCheck = New-Object Windows.Forms.Label; $lHouCheck.Text=""; $lHouCheck.Location="350,$y"; $lHouCheck.AutoSize=$true; $f.Controls.Add($lHouCheck)


$y += 55
# 2. USDリスト
$l2 = New-Object Windows.Forms.Label; $l2.Text="2. 対象USDリスト (選択して編集 / Delで削除 / Drag&Drop対応):"; $l2.Location="$leftX,$y"; $l2.AutoSize=$true; $f.Controls.Add($l2)
$gridUSD = New-Object Windows.Forms.DataGridView
$gridUSD.Location="$leftX,$($y+20)"; $gridUSD.Size="460,100"
$gridUSD.AllowUserToAddRows=$false; $gridUSD.AllowUserToResizeRows=$false; $gridUSD.AllowUserToDeleteRows=$false
$gridUSD.RowHeadersVisible=$false; $gridUSD.SelectionMode="FullRowSelect"; $gridUSD.MultiSelect=$false
$gridUSD.AutoSizeColumnsMode="Fill"; $gridUSD.ReadOnly=$true
[void]$gridUSD.Columns.Add((New-Object Windows.Forms.DataGridViewTextBoxColumn -Property @{Name="USD"; HeaderText="USDファイル"; FillWeight=100}))
[void]$gridUSD.Columns.Add((New-Object Windows.Forms.DataGridViewTextBoxColumn -Property @{Name="Range"; HeaderText="レンジ"; FillWeight=50}))
[void]$gridUSD.Columns.Add((New-Object Windows.Forms.DataGridViewTextBoxColumn -Property @{Name="Output"; HeaderText="出力"; FillWeight=50}))
[void]$gridUSD.Columns.Add((New-Object Windows.Forms.DataGridViewTextBoxColumn -Property @{Name="Status"; HeaderText="設定"; FillWeight=20}))
$f.Controls.Add($gridUSD)

$lEditingUSD = New-Object Windows.Forms.Label; $lEditingUSD.Text="[グローバル設定]"; $lEditingUSD.Location="$leftX,$($y+125)"; $lEditingUSD.AutoSize=$true; $lEditingUSD.ForeColor="Gray"; $f.Controls.Add($lEditingUSD)
$btnClear = New-Object Windows.Forms.Button; $btnClear.Text="リストをクリア"; $btnClear.Location="380,$($y+125)"; $btnClear.Size="100,25"; $f.Controls.Add($btnClear)

$y += 160
# 3. 出力設定
$groupOut = New-Object Windows.Forms.GroupBox; $groupOut.Text="3. 出力先・ファイル名設定 (選択中のUSD)"; $groupOut.Location="$leftX,$y"; $groupOut.Size="460,240"; $f.Controls.Add($groupOut)
$chkOutToggle = New-Object Windows.Forms.CheckBox; $chkOutToggle.Text="出力をカスタマイズする"; $chkOutToggle.Location="15,20"; $chkOutToggle.Width=200; $chkOutToggle.Checked = [System.Convert]::ToBoolean($conf["OUT_TOGGLE"]); $groupOut.Controls.Add($chkOutToggle)
$tOUT = New-Object Windows.Forms.TextBox; $tOUT.Text=$conf["OUT_PATH"]; $tOUT.Location="15,65"; $tOUT.Width=430; $groupOut.Controls.Add($tOUT)
$rbNameUSD = New-Object Windows.Forms.RadioButton; $rbNameUSD.Text="USD名"; $rbNameUSD.Location="15,95"; $rbNameUSD.Width=70; $rbNameUSD.Checked = ($conf["OUT_NAME_MODE"] -eq "USD"); $groupOut.Controls.Add($rbNameUSD)
$rbNameCustom = New-Object Windows.Forms.RadioButton; $rbNameCustom.Text="カスタム:"; $rbNameCustom.Location="90,95"; $rbNameCustom.Width=80; $rbNameCustom.Checked = ($conf["OUT_NAME_MODE"] -eq "Custom"); $groupOut.Controls.Add($rbNameCustom)
$tNameBase = New-Object Windows.Forms.TextBox; $tNameBase.Text=$conf["OUT_NAME_BASE"]; $tNameBase.Location="175,95"; $tNameBase.Width=260; $groupOut.Controls.Add($tNameBase)
$tExt = New-Object Windows.Forms.TextBox; $tExt.Text=$conf["EXT"]; $tExt.Location="70,122"; $tExt.Width=60; $groupOut.Controls.Add($tExt)
$nPad = New-Object Windows.Forms.NumericUpDown; $nPad.Location="230,122"; $nPad.Width=50; $nPad.Minimum=1; $nPad.Value=[int]$conf["PADDING"]; $groupOut.Controls.Add($nPad)
$lPreview = New-Object Windows.Forms.Label; $lPreview.Text="Preview: ---"; $lPreview.Location="15,165"; $lPreview.Size="430,55"; $lPreview.ForeColor="Blue"; $lPreview.Font = New-Object System.Drawing.Font("Consolas", 8); $groupOut.Controls.Add($lPreview)

$y += 265
# 4. レンダリング範囲設定
$groupMode = New-Object Windows.Forms.GroupBox; $groupMode.Text="4. レンダリング範囲設定 (選択中のUSD)"; $groupMode.Location="$leftX,$y"; $groupMode.Size="460,180"; $f.Controls.Add($groupMode)
$rbAuto = New-Object Windows.Forms.RadioButton; $rbAuto.Text="自動解析 (各USDのフレーム範囲を使用)"; $rbAuto.Location="15,20"; $rbAuto.Width=300; $rbAuto.Checked = ($conf["BATCH_MODE"] -eq "Auto"); $groupMode.Controls.Add($rbAuto)
$rbManual = New-Object Windows.Forms.RadioButton; $rbManual.Text="範囲設定"; $rbManual.Location="15,45"; $rbManual.Width=100; $rbManual.Checked = ($conf["BATCH_MODE"] -eq "Manual"); $groupMode.Controls.Add($rbManual)
$nFS = New-Object Windows.Forms.NumericUpDown; $nFS.Location="120,48"; $nFS.Width=70; $nFS.Minimum=-999999; $nFS.Maximum=999999; $nFS.Value=[int]$conf["START_FRM"]; $groupMode.Controls.Add($nFS)
$lTo = New-Object Windows.Forms.Label; $lTo.Text="～"; $lTo.Location="195,51"; $lTo.Width=20; $groupMode.Controls.Add($lTo)
$nFE = New-Object Windows.Forms.NumericUpDown; $nFE.Location="220,48"; $nFE.Width=70; $nFE.Minimum=-999999; $nFE.Maximum=999999; $nFE.Value=[int]$conf["END_FRM"]; $groupMode.Controls.Add($nFE)
$rbMulti = New-Object Windows.Forms.RadioButton; $rbMulti.Text="複数設定 (例: 1001-1010,1050)"; $rbMulti.Location="15,70"; $rbMulti.Width=300; $rbMulti.Checked=$false; $groupMode.Controls.Add($rbMulti)
$txtRanges = New-Object Windows.Forms.TextBox; $txtRanges.Location="15,95"; $txtRanges.Width=430; $txtRanges.Enabled=$false; $groupMode.Controls.Add($txtRanges)
$btnAnalyze = New-Object Windows.Forms.Button; $btnAnalyze.Text="解析"; $btnAnalyze.Location="300,125"; $btnAnalyze.Size="140,40"; $groupMode.Controls.Add($btnAnalyze)
$cS = New-Object Windows.Forms.CheckBox; $cS.Text="単一フレーム"; $cS.Location="300,46"; $cS.Width=100; $cS.Checked = [System.Convert]::ToBoolean($conf["SINGLE"]); $groupMode.Controls.Add($cS)

# --- ini設定に戻すボタン ---
$advX = 500; $advY = 10
$btnResetToIni = New-Object Windows.Forms.Button; $btnResetToIni.Text="ini設定に戻す"; $btnResetToIni.Location="$advX,$advY"; $btnResetToIni.Size="280,40"; $f.Controls.Add($btnResetToIni)

# --- Advanced Settings (右側) ---
$advY = 60
$groupAdv = New-Object Windows.Forms.GroupBox; $groupAdv.Text="Advanced Settings"; $groupAdv.Location="$advX,$advY"; $groupAdv.Size="280,550"; $f.Controls.Add($groupAdv)

# 1. Render Setting グループ
$groupRender = New-Object Windows.Forms.GroupBox; $groupRender.Text="1. Render Setting"; $groupRender.Location="10,20"; $groupRender.Size="260,210"; $groupAdv.Controls.Add($groupRender)
$script:lockRenderBtn = Add-LockButton $groupRender
$lRes = New-Object Windows.Forms.Label; $lRes.Text="Resolution Scale: $($conf['RES_SCALE'])%"; $lRes.Location="10,20"; $lRes.Width=200; $groupRender.Controls.Add($lRes)
$trackRes = New-Object Windows.Forms.TrackBar; $trackRes.Location="10,40"; $trackRes.Width=230; $trackRes.Minimum=1; $trackRes.Maximum=20; $trackRes.Value=[math]::Max(1,[int]([float]$conf["RES_SCALE"]/10)); $groupRender.Controls.Add($trackRes)
$lPS = New-Object Windows.Forms.Label; $lPS.Text="Pixel Samples (0=Default):"; $lPS.Location="10,85"; $lPS.Width=200; $groupRender.Controls.Add($lPS)
$nPS = New-Object Windows.Forms.NumericUpDown; $nPS.Location="10,105"; $nPS.Width=80; $nPS.Minimum=0; $nPS.Maximum=9999; $nPS.Value=[int]$conf["PIXEL_SAMPLES"]; $groupRender.Controls.Add($nPS)
$lEngine = New-Object Windows.Forms.Label; $lEngine.Text="Engine:"; $lEngine.Location="10,140"; $lEngine.Width=80; $groupRender.Controls.Add($lEngine)
$comboEngine = New-Object Windows.Forms.ComboBox; $comboEngine.Location="90,138"; $comboEngine.Width=70; $comboEngine.DropDownStyle="DropDownList"
[void]$comboEngine.Items.AddRange(@("cpu", "xpu")); $comboEngine.Text=$conf["ENGINE_TYPE"]; $groupRender.Controls.Add($comboEngine)
$chkDisableMB = New-Object Windows.Forms.CheckBox; $chkDisableMB.Text="Disable Motion Blur"; $chkDisableMB.Location="10,175"; $chkDisableMB.Width=200; $chkDisableMB.Checked = [System.Convert]::ToBoolean($conf["DISABLE_MOTIONBLUR"]); $groupRender.Controls.Add($chkDisableMB)

# 2. Timeout & Notification グループ
$groupTimeout = New-Object Windows.Forms.GroupBox; $groupTimeout.Text="2. Timeout & Notification"; $groupTimeout.Location="10,240"; $groupTimeout.Size="260,245"; $groupAdv.Controls.Add($groupTimeout)
$script:lockTimeoutBtn = Add-LockButton $groupTimeout
$lTW = New-Object Windows.Forms.Label; $lTW.Text="Warn Timeout (Min, 0=Off):"; $lTW.Location="10,20"; $lTW.Width=200; $groupTimeout.Controls.Add($lTW)
$nTW = New-Object Windows.Forms.NumericUpDown; $nTW.Location="10,40"; $nTW.Width=80; $nTW.Maximum=9999; $nTW.Value=[int]$conf["TIMEOUT_WARN"]; $groupTimeout.Controls.Add($nTW)
$lTK = New-Object Windows.Forms.Label; $lTK.Text="Kill Timeout (Min, 0=Off):"; $lTK.Location="10,75"; $lTK.Width=200; $groupTimeout.Controls.Add($lTK)
$nTK = New-Object Windows.Forms.NumericUpDown; $nTK.Location="10,95"; $nTK.Width=80; $nTK.Maximum=9999; $nTK.Value=[int]$conf["TIMEOUT_KILL"]; $groupTimeout.Controls.Add($nTK)
$lNo = New-Object Windows.Forms.Label; $lNo.Text="Notification:"; $lNo.Location="10,130"; $lNo.Width=200; $groupTimeout.Controls.Add($lNo)
$comboNoti = New-Object Windows.Forms.ComboBox; $comboNoti.Location="10,150"; $comboNoti.Width=220; $comboNoti.DropDownStyle="DropDownList"
[void]$comboNoti.Items.AddRange(@("None", "Windows Toast", "Discord")); $comboNoti.Text=$conf["NOTIFY"]; $groupTimeout.Controls.Add($comboNoti)
$lWeb = New-Object Windows.Forms.Label; $lWeb.Text="Discord Webhook URL:"; $lWeb.Location="10,180"; $lWeb.Width=200; $groupTimeout.Controls.Add($lWeb)
$tWeb = New-Object Windows.Forms.TextBox; $tWeb.Text=$conf["DISCORD_WEBHOOK"]; $tWeb.Location="10,200"; $tWeb.Width=220; $groupTimeout.Controls.Add($tWeb)

# 完了後のアクション
$lShutdown = New-Object Windows.Forms.Label; $lShutdown.Text="完了後のアクション:"; $lShutdown.Location="15,500"; $lShutdown.Width=200; $groupAdv.Controls.Add($lShutdown)
$comboShutdown = New-Object Windows.Forms.ComboBox; $comboShutdown.Location="15,520"; $comboShutdown.Width=220; $comboShutdown.DropDownStyle="DropDownList"
[void]$comboShutdown.Items.AddRange(@("なし", "シャットダウン", "再起動", "ログオフ"))
# 旧設定との互換性のため、REBOOTがTrueの場合は再起動を選択
if ([System.Convert]::ToBoolean($conf["REBOOT"])) {
    $comboShutdown.Text = "再起動"
} elseif ($conf.ContainsKey("SHUTDOWN_ACTION")) {
    $comboShutdown.Text = $conf["SHUTDOWN_ACTION"]
} else {
    $comboShutdown.Text = "なし"
}
$groupAdv.Controls.Add($comboShutdown)

# --- 実行ボタン (Advanced Settingsの下) ---
$btnRun = New-Object Windows.Forms.Button; $btnRun.Text="実行"; $btnRun.Location="$advX,620"; $btnRun.Size="280,50"; $f.Controls.Add($btnRun)

# --- ロジックとイベント ---
$updatePreview = {
    $first = if($gridUSD.Rows.Count -gt 0){ $gridUSD.Rows[0].Tag }else{ $null }
    $norm = Normalize-UsdPath $first
    $ov = if($norm){ $usdOverrides[$norm] }else{ $null }

    $dir = if($ov -and $ov.outPath){ $ov.outPath.Replace("\","/") } elseif([string]::IsNullOrWhiteSpace($tOUT.Text)){ if($first){ $p = Split-Path -Parent $first; if($p){ $p.Replace("\","/") }else{"."} } else {"C:/render"} } else { $tOUT.Text.Replace("\","/") }

    $base = "filename"
    if ($ov -and $ov.nameMode -eq "Custom" -and $ov.nameBase) {
        $base = $ov.nameBase
    } elseif ($ov -and $ov.nameMode -eq "USD") {
        $base = if($first){ [System.IO.Path]::GetFileNameWithoutExtension($first) }else{"filename"}
    } elseif ($rbNameUSD.Checked) {
        $base = if($first){ [System.IO.Path]::GetFileNameWithoutExtension($first) }else{"filename"}
    } else {
        $base = $tNameBase.Text
    }

    $scale = if($ov -and $ov.resScale){ $ov.resScale }else{ $trackRes.Value * 10 }
    $lPreview.Text = "Preview:`n$dir/$base.$('0'*($nPad.Value-1))1.$($tExt.Text.TrimStart('.'))`n(Scale: $scale%)"
    $lPreview.ForeColor = if(($chkOutToggle.Checked) -or ($ov -and $ov.outPath)){[System.Drawing.Color]::Blue}else{[System.Drawing.Color]::Gray}
}

$updateControlState = {
    # Houdini Bin チェック
    if (![string]::IsNullOrWhiteSpace($tHOU.Text) -and (Test-Path (Join-Path $tHOU.Text "husk.exe"))) {
        $lHouCheck.Text = "〇 OK"; $lHouCheck.ForeColor = "DarkGreen"
    } else {
        $lHouCheck.Text = "× husk.exe not found"; $lHouCheck.ForeColor = "Red"
    }

    # --- ロック状態の取得 ---
    $renderLocked  = $script:lockRenderBtn.Checked
    $timeoutLocked = $script:lockTimeoutBtn.Checked

    # --- 3. 出力設定の制御 ---
    $chkOutToggle.Enabled = $true
    $outActive = $chkOutToggle.Checked
    $tOUT.Enabled = $rbNameUSD.Enabled = $rbNameCustom.Enabled = $tExt.Enabled = $nPad.Enabled = $outActive
    $tNameBase.Enabled = ($outActive -and $rbNameCustom.Checked)

    # --- 4. レンダリング範囲設定の制御 ---
    $rbAuto.Enabled = $rbManual.Enabled = $rbMulti.Enabled = $cS.Enabled = $true
    $nFS.Enabled = $rbManual.Checked
    $nFE.Enabled = ($rbManual.Checked -and -not $cS.Checked)
    $txtRanges.Enabled = $rbMulti.Checked
    $btnAnalyze.Enabled = $rbMulti.Checked

    # --- Advanced Settings の制御 ---
    $trackRes.Enabled = $nPS.Enabled = $comboEngine.Enabled = $chkDisableMB.Enabled = -not $renderLocked

    $nTW.Enabled = $nTK.Enabled = $comboNoti.Enabled = -not $timeoutLocked
    $tWeb.Enabled = (-not $timeoutLocked -and $comboNoti.Text -eq "Discord")

    $comboShutdown.Enabled = $true

    $lWeb.Visible = ($comboNoti.Text -eq "Discord")
    $tWeb.Visible = ($comboNoti.Text -eq "Discord")

    if ($cS.Checked) { $nFE.Value = $nFS.Value }
    & $updatePreview
}

# イベント登録
$nFS.Add_ValueChanged({ if ($cS.Checked) { $nFE.Value = $nFS.Value }; & $updatePreview })
$tHOU.Add_TextChanged({ & $updateControlState })
$tOUT.Add_TextChanged({ & $updateControlState })
$tNameBase.Add_TextChanged({ & $updatePreview })
$tExt.Add_TextChanged({ & $updatePreview })
$nPad.Add_ValueChanged({ & $updatePreview })
$btnClear.Add_Click({ $gridUSD.Rows.Clear(); $usdOverrides.Clear(); Load-UsdSettings $null; & $updateControlState })
$trackRes.Add_ValueChanged({ $lRes.Text = "Resolution Scale: $($trackRes.Value * 10)%"; Save-CurrentUsdSettings; & $updatePreview })
$gridUSD.Add_SelectionChanged({
    Save-CurrentUsdSettings
    if ($gridUSD.SelectedRows.Count -gt 0) {
        Load-UsdSettings $gridUSD.Rows[$gridUSD.SelectedRows[0].Index].Tag
    } else {
        Load-UsdSettings $null
    }
    & $updateControlState
})
$gridUSD.Add_KeyUp({
    # KeyUpで処理することでDeleteキーリピート時の連続削除を防止
    if ($_.KeyCode -ne [Windows.Forms.Keys]::Delete) { return }
    if ($gridUSD.SelectedRows.Count -eq 0) { return }

    $idx = $gridUSD.SelectedRows[0].Index
    $path = $gridUSD.Rows[$idx].Tag
    $usdOverrides.Remove((Normalize-UsdPath $path)) | Out-Null
    $gridUSD.Rows.RemoveAt($idx)
    Load-UsdSettings $null
    & $updateControlState
    $_.SuppressKeyPress = $true
    $_.Handled = $true
})
$rbMulti.Add_CheckedChanged({ $txtRanges.Enabled = $rbMulti.Checked; Save-CurrentUsdSettings; & $updateControlState })
$rbAuto.Add_CheckedChanged({ Save-CurrentUsdSettings; & $updateControlState })
$rbManual.Add_CheckedChanged({ Save-CurrentUsdSettings; & $updateControlState })
$nFS.Add_ValueChanged({ Save-CurrentUsdSettings; if ($cS.Checked) { $nFE.Value = $nFS.Value }; & $updatePreview })
$nFE.Add_ValueChanged({ Save-CurrentUsdSettings; & $updatePreview })
$txtRanges.Add_TextChanged({ Save-CurrentUsdSettings })
$tOUT.Add_TextChanged({ Save-CurrentUsdSettings; & $updateControlState })
$rbNameUSD.Add_CheckedChanged({ Save-CurrentUsdSettings; & $updateControlState })
$rbNameCustom.Add_CheckedChanged({ Save-CurrentUsdSettings; & $updateControlState })
$tNameBase.Add_TextChanged({ Save-CurrentUsdSettings; & $updatePreview })
$chkOutToggle.Add_CheckedChanged({ Save-CurrentUsdSettings; & $updateControlState })
$tExt.Add_TextChanged({ Save-CurrentUsdSettings; & $updatePreview })
$nPad.Add_ValueChanged({ Save-CurrentUsdSettings; & $updatePreview })
$nPS.Add_ValueChanged({ Save-CurrentUsdSettings })
$chkDisableMB.Add_CheckedChanged({ Save-CurrentUsdSettings })
$comboEngine.Add_SelectedIndexChanged({ Save-CurrentUsdSettings })
$comboNoti.Add_SelectedIndexChanged({ Save-CurrentUsdSettings; & $updateControlState })
$btnAnalyze.Add_Click({
    if ($gridUSD.SelectedRows.Count -eq 0) { return }
    $btnAnalyze.Text = "..."; $f.Refresh()
    $path = $gridUSD.Rows[$gridUSD.SelectedRows[0].Index].Tag
    $res = Get-USDFrameRange $path $tHOU.Text
    if ($res) {
        $rangeText = "$($res.start)-$($res.end)"
        $txtRanges.Text = $rangeText
        $rbMulti.Checked = $true
        Save-CurrentUsdSettings
    }
    $btnAnalyze.Text = "解析"
})
$nFS.Add_ValueChanged({ if ($cS.Checked) { $nFE.Value = $nFS.Value }; & $updatePreview })
$tHOU.Add_TextChanged({ & $updateControlState })
$tExt.Add_TextChanged({ & $updatePreview })
$nPad.Add_ValueChanged({ & $updatePreview })
$chkOutToggle.Add_CheckedChanged({ & $updateControlState })
$rbAuto.Add_CheckedChanged({ & $updateControlState })
$rbManual.Add_CheckedChanged({ & $updateControlState })
$cS.Add_CheckedChanged({ & $updateControlState })

# --- 保存処理をClosingイベントに集約 ---
$f.Add_FormClosing({
    Save-CurrentUsdSettings
    if ($f.DialogResult -eq [Windows.Forms.DialogResult]::OK) {
        $items = @(); foreach($row in $gridUSD.Rows){ if($row.Tag){ $items += $row.Tag } }
        $normItems = $items | ForEach-Object { Normalize-UsdPath $_ }
        foreach ($key in @($usdOverrides.Keys)) { if (-not $normItems.Contains($key)) { $usdOverrides.Remove($key) | Out-Null } }

        $isReboot = ($comboShutdown.Text -eq "再起動")
        $res = @("HOUDINI_BIN=$($tHOU.Text)", "USD_LIST=$([string]::Join(',',$items))", "OUT_PATH=$($tOUT.Text)", "START_FRM=$($nFS.Value)", "END_FRM=$($nFE.Value)", "REBOOT=$isReboot", "SHUTDOWN_ACTION=$($comboShutdown.Text)", "SINGLE=$($cS.Checked)", "BATCH_MODE=$(if($rbAuto.Checked){'Auto'}else{'Manual'})", "OUT_TOGGLE=$($chkOutToggle.Checked)", "OUT_NAME_MODE=$(if($rbNameUSD.Checked){'USD'}else{'Custom'})", "OUT_NAME_BASE=$($tNameBase.Text)", "EXT=$($tExt.Text)", "PADDING=$($nPad.Value)", "RES_SCALE=$($trackRes.Value * 10)", "PIXEL_SAMPLES=$($nPS.Value)", "NOTIFY=$($comboNoti.Text)", "DISCORD_WEBHOOK=$($tWeb.Text)", "TIMEOUT_WARN=$($nTW.Value)", "TIMEOUT_KILL=$($nTK.Value)", "ENGINE_TYPE=$($comboEngine.Text)", "DISABLE_MOTIONBLUR=$($chkDisableMB.Checked)", "LOCK_RENDER=$($script:lockRenderBtn.Checked)", "LOCK_TIMEOUT=$($script:lockTimeoutBtn.Checked)") 
        $res | Set-Content $script:iniPath -Encoding Default
        Save-UsdOverrides $usdOverrides $overridePath
    }
})

$btnRun.Add_Click({ $f.DialogResult = [Windows.Forms.DialogResult]::OK; $f.Close() })

$btnResetToIni.Add_Click({
    if ($gridUSD.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("USDファイルが選択されていません。", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    # 最新のini設定をファイルから再読み込み
    $script:conf = Get-IniSettings

    $idx = $gridUSD.SelectedRows[0].Index
    $path = $gridUSD.Rows[$idx].Tag
    $norm = Normalize-UsdPath $path
    if ($usdOverrides.ContainsKey($norm)) {
        $usdOverrides.Remove($norm)
        Save-UsdOverrides $usdOverrides $overridePath
        $gridUSD.Rows[$idx].Cells[1].Value = Get-RangeSummary $null $conf
        $gridUSD.Rows[$idx].Cells[2].Value = Get-OutputSummary $null $conf
        $gridUSD.Rows[$idx].Cells[3].Value = Get-StatusText $null $conf
        Load-UsdSettings $path
        & $updateControlState
        [System.Windows.Forms.MessageBox]::Show("選択中のUSDの設定を削除し、ini設定に戻しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        [System.Windows.Forms.MessageBox]::Show("選択中のUSDには個別設定がありません。", "情報", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

$tHOU.AllowDrop = $true
$tHOU.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = "Copy" } })
$tHOU.Add_DragDrop({
    $files = $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    if ($files.Count -gt 0) {
        $path = $files[0]
        if (Test-Path $path -PathType Container) {
            $tHOU.Text = $path
        } else {
            $tHOU.Text = Split-Path -Parent $path
        }
    }
})

$tOUT.AllowDrop = $true
$tOUT.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = "Copy" } })
$tOUT.Add_DragDrop({
    $files = $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    if ($files.Count -gt 0) {
        $path = $files[0]
        if (Test-Path $path -PathType Container) {
            $tOUT.Text = $path
        } else {
            $tOUT.Text = Split-Path -Parent $path
        }
    }
})

$gridUSD.AllowDrop = $true
$gridUSD.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = "Copy" } })
$gridUSD.Add_DragDrop({
    $files = $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    $wasEmpty = ($gridUSD.Rows.Count -eq 0)
    foreach ($file in $files) {
        if ($file -match "\.usd[azc]?$") {
            $norm = Normalize-UsdPath $file
            $ov = if($norm){ $usdOverrides[$norm] }else{ $null }
            $fname = [System.IO.Path]::GetFileName($file)
            [void]$gridUSD.Rows.Add($fname, (Get-RangeSummary $ov $conf), (Get-OutputSummary $ov $conf), (Get-StatusText $ov $conf))
            $newRow = $gridUSD.Rows[$gridUSD.Rows.Count-1]
            $newRow.Tag = $file
            $gridUSD.ClearSelection()
            $newRow.Selected = $true
        }
    }
    if ($wasEmpty -and $gridUSD.Rows.Count -gt 0) { Load-UsdSettings $gridUSD.Rows[0].Tag }
    & $updateControlState
})

# --- 起動時の初期反映 ---
if ($conf["USD_LIST"]) {
    $conf["USD_LIST"].Split(",") | ForEach-Object {
        if($_){
            $path = $_.Trim()
            $norm = Normalize-UsdPath $path
            $ov = if($norm){ $usdOverrides[$norm] }else{ $null }
            $fname = [System.IO.Path]::GetFileName($path)
            [void]$gridUSD.Rows.Add($fname, (Get-RangeSummary $ov $conf), (Get-OutputSummary $ov $conf), (Get-StatusText $ov $conf))
            $gridUSD.Rows[$gridUSD.Rows.Count-1].Tag = $path
        }
    }
    if ($gridUSD.Rows.Count -gt 0) { 
        $gridUSD.Rows[0].Selected = $true
        Load-UsdSettings $gridUSD.Rows[0].Tag 
    }
}
if ($dropFile) {
    $norm = Normalize-UsdPath $dropFile
    $ov = if($norm){ $usdOverrides[$norm] }else{ $null }
    $fname = [System.IO.Path]::GetFileName($dropFile)
    [void]$gridUSD.Rows.Add($fname, (Get-RangeSummary $ov $conf), (Get-OutputSummary $ov $conf), (Get-StatusText $ov $conf))
    $lastRow = $gridUSD.Rows[$gridUSD.Rows.Count-1]
    $lastRow.Tag = $dropFile
    $gridUSD.ClearSelection()
    $lastRow.Selected = $true
    Load-UsdSettings $dropFile
}
& $updateControlState

# --- コンテキストメニューの追加 ---
# Render Settings
Add-SaveDefaultMenu $trackRes "RES_SCALE" "解像度スケール"
Add-SaveDefaultMenu $nPS "PIXEL_SAMPLES" "ピクセルサンプル数"
Add-SaveDefaultMenu $comboEngine "ENGINE_TYPE" "レンダリングエンジン"
Add-SaveDefaultMenu $chkDisableMB "DISABLE_MOTIONBLUR" "モーションブラー無効"

# Timeout & Notification
Add-SaveDefaultMenu $nTW "TIMEOUT_WARN" "警告タイムアウト"
Add-SaveDefaultMenu $nTK "TIMEOUT_KILL" "強制終了タイムアウト"
Add-SaveDefaultMenu $comboNoti "NOTIFY" "通知方法"
Add-SaveDefaultMenu $tWeb "DISCORD_WEBHOOK" "Discord Webhook URL"

# Output Settings
Add-SaveDefaultMenu $chkOutToggle "OUT_TOGGLE" "出力カスタマイズ"
Add-SaveDefaultMenu $tOUT "OUT_PATH" "出力パス"
Add-SaveDefaultMenu $rbNameUSD "OUT_NAME_MODE" "ファイル名モード(USD名)" "USD"
Add-SaveDefaultMenu $rbNameCustom "OUT_NAME_MODE" "ファイル名モード(カスタム)" "Custom"
Add-SaveDefaultMenu $tNameBase "OUT_NAME_BASE" "出力ファイル名ベース"
Add-SaveDefaultMenu $nPad "PADDING" "パディング桁数"
Add-SaveDefaultMenu $tExt "EXT" "ファイル拡張子"

# Frame Range Settings
Add-SaveDefaultMenu $rbAuto "BATCH_MODE" "レンダリングモード(自動)" "Auto"
Add-SaveDefaultMenu $rbManual "BATCH_MODE" "レンダリングモード(手動)" "Manual"
Add-SaveDefaultMenu $rbMulti "BATCH_MODE" "レンダリングモード(複数設定)" "Multi"
Add-SaveDefaultMenu $nFS "START_FRM" "開始フレーム"
Add-SaveDefaultMenu $nFE "END_FRM" "終了フレーム"
Add-SaveDefaultMenu $cS "SINGLE" "単一フレーム" "Single"

# Completion Action
Add-SaveDefaultMenu $comboShutdown "SHUTDOWN_ACTION" "完了後のアクション"

# Houdini Path
Add-SaveDefaultMenu $tHOU "HOUDINI_BIN" "Houdini Binパス"

# ウィンドウ表示と終了判定
$result = $f.ShowDialog()
if ($result -ne [Windows.Forms.DialogResult]::OK) { exit 2 }
exit 0
