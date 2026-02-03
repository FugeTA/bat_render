param([string]$dropFile)

<<<<<<< Updated upstream
# 共通ユーティリティモジュールをインポート
Import-Module (Join-Path $PSScriptRoot "husk_utils.psm1") -Force

=======
# モジュールをインポート
>>>>>>> Stashed changes
$baseDir = Split-Path -Parent $PSScriptRoot
$modulePath = $PSScriptRoot

# モジュールファイルのパスを構築
$commonModulePath = Join-Path $modulePath "HuskCommon.ps1"
$guiComponentsModulePath = Join-Path $modulePath "HuskGuiComponents.ps1"

# モジュールが存在するか確認
if (-not (Test-Path $commonModulePath)) {
    Write-Error "HuskCommon.ps1 が見つかりません: $commonModulePath"
    Read-Host "Enterキーを押して終了します..."; exit 1
}
if (-not (Test-Path $guiComponentsModulePath)) {
    Write-Error "HuskGuiComponents.ps1 が見つかりません: $guiComponentsModulePath"
    Read-Host "Enterキーを押して終了します..."; exit 1
}

# モジュールをドットソーシングで読み込み（スクリプトスコープに直接ロード）
try {
    . $commonModulePath
    . $guiComponentsModulePath
} catch {
    Write-Error "モジュールの読み込みに失敗しました: $_"
    Write-Error "エラー詳細: $($_.Exception.Message)"
    Write-Error "エラー位置: $($_.InvocationInfo.PositionMessage)"
    Read-Host "Enterキーを押して終了します..."; exit 1
}

$configDir = Join-Path $baseDir "config"
if (!(Test-Path $configDir)) { New-Item -ItemType Directory $configDir | Out-Null }
$iniPath = Join-Path $configDir "settings.ini"
$overridePath = Join-Path $configDir "usd_overrides.xml"

# 1. デフォルト設定の読み込み
<<<<<<< Updated upstream
$defaultConf = @{ 
    USD_LIST=""; OUT_PATH=""; START_FRM="1"; END_FRM="1"; 
    REBOOT="False"; SHUTDOWN_ACTION="None"; SINGLE="False"; HOUDINI_BIN="C:\Program Files\Side Effects Software\Houdini 21.0.440\bin";
    BATCH_MODE="Auto"; OUT_TOGGLE="True"; OUT_NAME_MODE="USD"; OUT_NAME_BASE="render";
    EXT="exr"; PADDING="4"; RES_SCALE="100"; PIXEL_SAMPLES="0"; NOTIFY="None"; DISCORD_WEBHOOK=""; TIMEOUT_WARN="0"; TIMEOUT_KILL="0";
    ENGINE_TYPE="cpu"
}
$conf = Import-ConfigIni $iniPath $defaultConf
$usdOverrides = Import-UsdOverrides $overridePath
=======
$script:conf = Get-IniSettings $script:iniPath
$script:usdOverrides = Load-UsdOverrides $overridePath
>>>>>>> Stashed changes

Add-Type -AssemblyName System.Windows.Forms
$f = New-Object Windows.Forms.Form
$f.Text = "Husk Batch Launcher"; $f.StartPosition = "CenterScreen"
$f.AutoSize = $true
$f.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink

# --- 解析関数とUIヘルパー関数 ---

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
    param($override)
    if (-not $override -or $override.Keys.Count -eq 0) { return "" }
    return "〇"
}

$script:currentEditingUSD = $null
$script:updatingFromSelection = $false

function Load-UsdSettings {
    param([string]$usdPath)
    
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
    
    $norm = Resolve-UsdPath $usdPath
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
    $comboNoti.Text = $conf["NOTIFY"]
    
    # オーバーライドがあれば適用
    if ($override) {
        # 範囲設定モードを復元
        if ($override.batchMode -eq "Auto") {
            $rbAuto.Checked = $true
        } elseif ($override.batchMode -eq "Manual") {
            $rbManual.Checked = $true
            if ($override.startFrame) { $nFS.Value = [int]$override.startFrame }
            if ($override.endFrame) { $nFE.Value = [int]$override.endFrame }
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
        if ($override.outPath) { $tOUT.Text = $override.outPath }
        if ($override.nameMode -eq "Custom") { $rbNameCustom.Checked = $true; if($override.nameBase){ $tNameBase.Text = $override.nameBase } }
        elseif ($override.nameMode -eq "USD") { $rbNameUSD.Checked = $true }
        if ($override.ContainsKey('outToggle')) { $chkOutToggle.Checked = $override.outToggle }
        if ($override.ext) { $tExt.Text = $override.ext }
        if ($override.padding) { $nPad.Value = [int]$override.padding }
        if ($override.resScale) { $trackRes.Value = [int]($override.resScale / 10) }
        if ($override.pixelSamples) { $nPS.Value = [int]$override.pixelSamples }
        if ($override.engine) { $comboEngine.Text = $override.engine }
        if ($override.notify) { $comboNoti.Text = $override.notify }
    }
    
    $txtRanges.Enabled = $rbMulti.Checked
    $script:updatingFromSelection = $false
}

function Save-CurrentUsdSettings {
    if ($script:updatingFromSelection) { return }
    if ([string]::IsNullOrWhiteSpace($script:currentEditingUSD)) { return }
    
    $norm = Resolve-UsdPath $script:currentEditingUSD
    if (-not $norm) { return }
    
    $override = @{}
    
    # 範囲設定モードを保存
    if ($rbAuto.Checked) {
        $override.batchMode = "Auto"
    } elseif ($rbManual.Checked) {
        $override.batchMode = "Manual"
        $override.startFrame = [int]$nFS.Value
        $override.endFrame = [int]$nFE.Value
    } elseif ($rbMulti.Checked) {
        $override.batchMode = "Multi"
        $rangePairs = ConvertFrom-RangeText $txtRanges.Text
        if ($rangePairs -ne $null -and $rangePairs.Count -gt 0) { 
            $override.ranges = $rangePairs
        }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($tOUT.Text) -and $tOUT.Text -ne $conf["OUT_PATH"]) { $override.outPath = $tOUT.Text }
    if ($rbNameCustom.Checked -and -not [string]::IsNullOrWhiteSpace($tNameBase.Text)) {
        $override.nameMode = "Custom"; $override.nameBase = $tNameBase.Text
    } elseif ($rbNameUSD.Checked) { $override.nameMode = "USD" }
    if ($chkOutToggle.Checked -ne [System.Convert]::ToBoolean($conf["OUT_TOGGLE"])) { $override.outToggle = $chkOutToggle.Checked }
    if ($tExt.Text -ne $conf["EXT"]) { $override.ext = $tExt.Text }
    if ([int]$nPad.Value -ne [int]$conf["PADDING"]) { $override.padding = [int]$nPad.Value }
    if ($trackRes.Value * 10 -ne [int]$conf["RES_SCALE"]) { $override.resScale = [int]($trackRes.Value * 10) }
    if ($nPS.Value -ne [int]$conf["PIXEL_SAMPLES"]) { $override.pixelSamples = [int]$nPS.Value }
    if ($comboEngine.Text -ne $conf["ENGINE_TYPE"]) { $override.engine = $comboEngine.Text }
    if ($comboNoti.Text -ne $conf["NOTIFY"]) { $override.notify = $comboNoti.Text }
    
    if ($override.Keys.Count -gt 0) {
        $usdOverrides[$norm] = $override
    } else {
        $usdOverrides.Remove($norm) | Out-Null
    }
    
    # 変更を即座にXMLファイルに保存
    Export-UsdOverrides $usdOverrides $overridePath
    
    Update-GridRow $script:currentEditingUSD
}

# Save-CurrentUsdSettingsをスクリプトスコープに保存（モジュールから参照できるように）
$script:SaveCurrentUsdSettings = ${function:Save-CurrentUsdSettings}

function Update-GridRow {
    param([string]$usdPath)
    for($i=0; $i -lt $gridUSD.Rows.Count; $i++){
        if($gridUSD.Rows[$i].Tag -eq $usdPath){
            $norm = Resolve-UsdPath $usdPath
            $ov = if($norm){ $usdOverrides[$norm] }else{ $null }
            $gridUSD.Rows[$i].Cells[1].Value = Get-RangeSummary $ov $conf
            $gridUSD.Rows[$i].Cells[2].Value = Get-OutputSummary $ov $conf
            $gridUSD.Rows[$i].Cells[3].Value = Get-StatusText $ov
            break
        }
    }
}

<<<<<<< Updated upstream
=======
# Update-GridRowをスクリプトスコープに保存（モジュールから参照できるように）
$script:UpdateGridRow = ${function:Update-GridRow}

>>>>>>> Stashed changes
$leftX = 20; $y = 10
# 1. Houdini Bin
$l1 = New-Object Windows.Forms.Label; $l1.Text="1. Houdini Binフォルダ:"; $l1.Location="$leftX,$y"; $l1.AutoSize=$true; $f.Controls.Add($l1)
$tHOU = New-Object Windows.Forms.TextBox; $tHOU.Text=$conf["HOUDINI_BIN"]; $tHOU.Location="$leftX,$($y+20)"; $tHOU.Width=460; $f.Controls.Add($tHOU)
$lHouCheck = New-Object Windows.Forms.Label; $lHouCheck.Text=""; $lHouCheck.Location="350,$y"; $lHouCheck.AutoSize=$true; $f.Controls.Add($lHouCheck)


$y += 55
# 2. USDリスト
$lModeInfo = New-Object Windows.Forms.Label; $lModeInfo.Text="[モード判定]"; $lModeInfo.Location="320,$y"; $lModeInfo.Width=160; $lModeInfo.ForeColor="DarkBlue"; $f.Controls.Add($lModeInfo)
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

if ($conf["USD_LIST"]) {
    $conf["USD_LIST"].Split(",") | ForEach-Object {
        if($_){
            $path = $_.Trim()
            $norm = Resolve-UsdPath $path
            $ov = if($norm){ $usdOverrides[$norm] }else{ $null }
            $fname = [System.IO.Path]::GetFileName($path)
            [void]$gridUSD.Rows.Add($fname, (Get-RangeSummary $ov $conf), (Get-OutputSummary $ov $conf), (Get-StatusText $ov))
            $gridUSD.Rows[$gridUSD.Rows.Count-1].Tag = $path
        }
    }
}
if ($dropFile) {
    $norm = Resolve-UsdPath $dropFile
    $ov = if($norm){ $usdOverrides[$norm] }else{ $null }
    $fname = [System.IO.Path]::GetFileName($dropFile)
    [void]$gridUSD.Rows.Add($fname, (Get-RangeSummary $ov $conf), (Get-OutputSummary $ov $conf), (Get-StatusText $ov))
    $gridUSD.Rows[$gridUSD.Rows.Count-1].Tag = $dropFile
}

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

$y += 250
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
$groupAdv = New-Object Windows.Forms.GroupBox; $groupAdv.Text="Advanced Settings"; $groupAdv.Location="$advX,$advY"; $groupAdv.Size="280,530"; $f.Controls.Add($groupAdv)

# 1. Render Setting グループ
$groupRender = New-Object Windows.Forms.GroupBox; $groupRender.Text="1. Render Setting"; $groupRender.Location="10,20"; $groupRender.Size="260,180"; $groupAdv.Controls.Add($groupRender)
$lRes = New-Object Windows.Forms.Label; $lRes.Text="Resolution Scale: $($conf['RES_SCALE'])%"; $lRes.Location="10,20"; $lRes.Width=200; $groupRender.Controls.Add($lRes)
$trackRes = New-Object Windows.Forms.TrackBar; $trackRes.Location="10,40"; $trackRes.Width=230; $trackRes.Minimum=1; $trackRes.Maximum=20; $trackRes.Value=[math]::Max(1,[int]([float]$conf["RES_SCALE"]/10)); $groupRender.Controls.Add($trackRes)
$lPS = New-Object Windows.Forms.Label; $lPS.Text="Pixel Samples (0=Default):"; $lPS.Location="10,85"; $lPS.Width=200; $groupRender.Controls.Add($lPS)
$nPS = New-Object Windows.Forms.NumericUpDown; $nPS.Location="10,105"; $nPS.Width=80; $nPS.Minimum=0; $nPS.Maximum=9999; $nPS.Value=[int]$conf["PIXEL_SAMPLES"]; $groupRender.Controls.Add($nPS)
$lEngine = New-Object Windows.Forms.Label; $lEngine.Text="Engine:"; $lEngine.Location="10,140"; $lEngine.Width=80; $groupRender.Controls.Add($lEngine)
$comboEngine = New-Object Windows.Forms.ComboBox; $comboEngine.Location="90,138"; $comboEngine.Width=70; $comboEngine.DropDownStyle="DropDownList"
[void]$comboEngine.Items.AddRange(@("cpu", "xpu")); $comboEngine.Text=$conf["ENGINE_TYPE"]; $groupRender.Controls.Add($comboEngine)

# 2. Timeout & Notification グループ
$groupTimeout = New-Object Windows.Forms.GroupBox; $groupTimeout.Text="2. Timeout & Notification"; $groupTimeout.Location="10,210"; $groupTimeout.Size="260,245"; $groupAdv.Controls.Add($groupTimeout)
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
$lShutdown = New-Object Windows.Forms.Label; $lShutdown.Text="完了後のアクション:"; $lShutdown.Location="15,470"; $lShutdown.Width=200; $groupAdv.Controls.Add($lShutdown)
$comboShutdown = New-Object Windows.Forms.ComboBox; $comboShutdown.Location="15,490"; $comboShutdown.Width=220; $comboShutdown.DropDownStyle="DropDownList"
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
$btnRun = New-Object Windows.Forms.Button; $btnRun.Text="実行"; $btnRun.Location="$advX,600"; $btnRun.Size="280,50"; $f.Controls.Add($btnRun)

# --- ロジックとイベント ---
$updatePreview = {
    $first = if($gridUSD.Rows.Count -gt 0){ $gridUSD.Rows[0].Tag }else{ $null }
    $norm = Resolve-UsdPath $first
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

    $count = $gridUSD.Rows.Count
    
    if ($count -eq 0) { 
        $lModeInfo.Text="モード: 一括処理"; 
        $rbManual.Enabled=$true; $btnAnalyze.Enabled=$false
        $rbNameCustom.Enabled=$false; if($rbNameCustom.Checked){$rbNameUSD.Checked=$true}
        $nFS.Enabled=$rbManual.Checked; $nFE.Enabled=($rbManual.Checked -and -not $cS.Checked); $cS.Enabled=$rbManual.Checked
    } elseif ($count -eq 1) { 
        $lModeInfo.Text="モード: 単一詳細設定"; $rbManual.Enabled=$rbNameCustom.Enabled=$true
        $tNameBase.Enabled=($rbNameCustom.Checked -and $chkOutToggle.Checked); $btnAnalyze.Enabled=$false
        $nFS.Enabled=$rbManual.Checked; $nFE.Enabled=($rbManual.Checked -and -not $cS.Checked); $cS.Enabled=$rbManual.Checked
    } else {
        $lModeInfo.Text="モード: 単一詳細設定"; $rbManual.Enabled=$rbNameCustom.Enabled=$true
        $tNameBase.Enabled=($rbNameCustom.Checked -and $chkOutToggle.Checked); $btnAnalyze.Enabled=$true
        $nFS.Enabled=$rbManual.Checked; $nFE.Enabled=($rbManual.Checked -and -not $cS.Checked); $cS.Enabled=$rbManual.Checked
    }

    # カスタマイズトグルのグレーアウト連動
    $tOUT.Enabled = $rbNameUSD.Enabled = $rbNameCustom.Enabled = $tExt.Enabled = $nPad.Enabled = $chkOutToggle.Checked
    $lWeb.Visible = ($comboNoti.Text -eq "Discord")
    $tWeb.Visible = ($comboNoti.Text -eq "Discord")
    
    if ($cS.Checked) { $nFE.Value = $nFS.Value }
    & $updatePreview
}

# updateControlStateをスクリプトスコープに保存（モジュールから参照できるように）
$script:updateControlState = $updateControlState

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
    $usdOverrides.Remove((Resolve-UsdPath $path)) | Out-Null
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
        $normItems = $items | ForEach-Object { Resolve-UsdPath $_ }
        foreach ($key in @($usdOverrides.Keys)) { if (-not $normItems.Contains($key)) { $usdOverrides.Remove($key) | Out-Null } }

        $isReboot = ($comboShutdown.Text -eq "再起動")
        $res = @("HOUDINI_BIN=$($tHOU.Text)", "USD_LIST=$([string]::Join(',',$items))", "OUT_PATH=$($tOUT.Text)", "START_FRM=$($nFS.Value)", "END_FRM=$($nFE.Value)", "REBOOT=$isReboot", "SHUTDOWN_ACTION=$($comboShutdown.Text)", "SINGLE=$($cS.Checked)", "BATCH_MODE=$(if($rbAuto.Checked){'Auto'}else{'Manual'})", "OUT_TOGGLE=$($chkOutToggle.Checked)", "OUT_NAME_MODE=$(if($rbNameUSD.Checked){'USD'}else{'Custom'})", "OUT_NAME_BASE=$($tNameBase.Text)", "EXT=$($tExt.Text)", "PADDING=$($nPad.Value)", "RES_SCALE=$($trackRes.Value * 10)", "PIXEL_SAMPLES=$($nPS.Value)", "NOTIFY=$($comboNoti.Text)", "DISCORD_WEBHOOK=$($tWeb.Text)", "TIMEOUT_WARN=$($nTW.Value)", "TIMEOUT_KILL=$($nTK.Value)", "ENGINE_TYPE=$($comboEngine.Text)")
        $res | Set-Content $iniPath -Encoding Default
        Export-UsdOverrides $usdOverrides $overridePath
    }
})

$btnRun.Add_Click({ $f.DialogResult = [Windows.Forms.DialogResult]::OK; $f.Close() })

$btnResetToIni.Add_Click({
    if ($gridUSD.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("USDファイルが選択されていません。", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
<<<<<<< Updated upstream
=======
    # 最新のini設定をファイルから再読み込み
    $script:conf = Get-IniSettings $script:iniPath

>>>>>>> Stashed changes
    $idx = $gridUSD.SelectedRows[0].Index
    $path = $gridUSD.Rows[$idx].Tag
    $norm = Resolve-UsdPath $path
    if ($usdOverrides.ContainsKey($norm)) {
        $usdOverrides.Remove($norm)
        $gridUSD.Rows[$idx].Cells[1].Value = Get-RangeSummary $null $conf
        $gridUSD.Rows[$idx].Cells[2].Value = Get-OutputSummary $null $conf
        $gridUSD.Rows[$idx].Cells[3].Value = Get-StatusText $null
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
    foreach ($file in $files) {
        if ($file -match "\.usd[azc]?$") {
            $norm = Resolve-UsdPath $file
            $ov = if($norm){ $usdOverrides[$norm] }else{ $null }
            $fname = [System.IO.Path]::GetFileName($file)
            [void]$gridUSD.Rows.Add($fname, (Get-RangeSummary $ov $conf), (Get-OutputSummary $ov $conf), (Get-StatusText $ov))
            $gridUSD.Rows[$gridUSD.Rows.Count-1].Tag = $file
        }
    }
    & $updateControlState
})

# --- 起動時の初期反映 ---
& $updateControlState

# ウィンドウ表示と終了判定
$result = $f.ShowDialog()
if ($result -ne [Windows.Forms.DialogResult]::OK) { exit 2 }
exit 0


