param([string]$dropFile)

$baseDir = Split-Path -Parent $PSScriptRoot
$configDir = Join-Path $baseDir "config"
if (!(Test-Path $configDir)) { New-Item -ItemType Directory $configDir | Out-Null }
$iniPath = Join-Path $configDir "settings.ini"

# 1. デフォルト設定の読み込み
$conf = @{ 
    USD_LIST=""; OUT_PATH=""; START_FRM="1"; END_FRM="1"; 
    REBOOT="False"; SHUTDOWN_ACTION="None"; SINGLE="False"; HOUDINI_BIN="C:\Program Files\Side Effects Software\Houdini 21.0.440\bin";
    BATCH_MODE="Auto"; OUT_TOGGLE="True"; OUT_NAME_MODE="USD"; OUT_NAME_BASE="render";
    EXT="exr"; PADDING="4"; RES_SCALE="100"; PIXEL_SAMPLES="0"; NOTIFY="None"; DISCORD_WEBHOOK=""; TIMEOUT_WARN="0"; TIMEOUT_KILL="0";
    ENGINE_TYPE="cpu"
}
if (Test-Path $iniPath) {
    Get-Content $iniPath | ForEach-Object {
        if ($_ -match "^([^=]+)=(.*)$") { $conf[$matches[1].Trim()] = $matches[2].Trim() }
    }
}

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

$leftX = 20; $y = 10
# 1. Houdini Bin
$l1 = New-Object Windows.Forms.Label; $l1.Text="1. Houdini Binフォルダ:"; $l1.Location="$leftX,$y"; $l1.AutoSize=$true; $f.Controls.Add($l1)
$tHOU = New-Object Windows.Forms.TextBox; $tHOU.Text=$conf["HOUDINI_BIN"]; $tHOU.Location="$leftX,$($y+20)"; $tHOU.Width=460; $f.Controls.Add($tHOU)
$lHouCheck = New-Object Windows.Forms.Label; $lHouCheck.Text=""; $lHouCheck.Location="350,$y"; $lHouCheck.AutoSize=$true; $f.Controls.Add($lHouCheck)


$y += 55
# 2. USDリスト
$lModeInfo = New-Object Windows.Forms.Label; $lModeInfo.Text="[モード判定]"; $lModeInfo.Location="320,$y"; $lModeInfo.Width=160; $lModeInfo.ForeColor="DarkBlue"; $f.Controls.Add($lModeInfo)
$l2 = New-Object Windows.Forms.Label; $l2.Text="2. 対象USDリスト (Delで削除 / Drag&Drop対応):"; $l2.Location="$leftX,$y"; $l2.AutoSize=$true; $f.Controls.Add($l2)
$listUSD = New-Object Windows.Forms.ListBox; $listUSD.Location="$leftX,$($y+20)"; $listUSD.Size="460,100"; $f.Controls.Add($listUSD)
if ($conf["USD_LIST"]) { $conf["USD_LIST"].Split(",") | ForEach-Object { if($_){ [void]$listUSD.Items.Add($_) } } }
if ($dropFile) { [void]$listUSD.Items.Add($dropFile) }

$btnClear = New-Object Windows.Forms.Button; $btnClear.Text="リストをクリア"; $btnClear.Location="380,$($y+125)"; $btnClear.Size="100,25"; $f.Controls.Add($btnClear)

$y += 160
# 3. 出力設定
$groupOut = New-Object Windows.Forms.GroupBox; $groupOut.Text="3. 出力先・ファイル名設定"; $groupOut.Location="$leftX,$y"; $groupOut.Size="460,240"; $f.Controls.Add($groupOut)
$chkOutToggle = New-Object Windows.Forms.CheckBox; $chkOutToggle.Text="出力をカスタマイズする"; $chkOutToggle.Location="15,20"; $chkOutToggle.Width=200; $chkOutToggle.Checked = [System.Convert]::ToBoolean($conf["OUT_TOGGLE"]); $groupOut.Controls.Add($chkOutToggle)
$tOUT = New-Object Windows.Forms.TextBox; $tOUT.Text=$conf["OUT_PATH"]; $tOUT.Location="15,65"; $tOUT.Width=430; $groupOut.Controls.Add($tOUT)
$rbNameUSD = New-Object Windows.Forms.RadioButton; $rbNameUSD.Text="USD名"; $rbNameUSD.Location="15,95"; $rbNameUSD.Width=70; $rbNameUSD.Checked = ($conf["OUT_NAME_MODE"] -eq "USD"); $groupOut.Controls.Add($rbNameUSD)
$rbNameCustom = New-Object Windows.Forms.RadioButton; $rbNameCustom.Text="カスタム:"; $rbNameCustom.Location="90,95"; $rbNameCustom.Width=80; $rbNameCustom.Checked = ($conf["OUT_NAME_MODE"] -eq "Custom"); $groupOut.Controls.Add($rbNameCustom)
$tNameBase = New-Object Windows.Forms.TextBox; $tNameBase.Text=$conf["OUT_NAME_BASE"]; $tNameBase.Location="175,95"; $tNameBase.Width=260; $groupOut.Controls.Add($tNameBase)
$tExt = New-Object Windows.Forms.TextBox; $tExt.Text=$conf["EXT"]; $tExt.Location="70,122"; $tExt.Width=60; $groupOut.Controls.Add($tExt)
$nPad = New-Object Windows.Forms.NumericUpDown; $nPad.Location="230,122"; $nPad.Width=50; $nPad.Minimum=1; $nPad.Value=[int]$conf["PADDING"]; $groupOut.Controls.Add($nPad)
$lPreview = New-Object Windows.Forms.Label; $lPreview.Text="Preview: ---"; $lPreview.Location="15,165"; $lPreview.Size="430,55"; $lPreview.ForeColor="Blue"; $lPreview.Font = New-Object System.Drawing.Font("Consolas", 8); $groupOut.Controls.Add($lPreview)

$y += 270
# 4. レンダリング範囲設定
$groupMode = New-Object Windows.Forms.GroupBox; $groupMode.Text="4. レンダリング範囲設定"; $groupMode.Location="$leftX,$y"; $groupMode.Size="460,200"; $f.Controls.Add($groupMode)
$rbAuto = New-Object Windows.Forms.RadioButton; $rbAuto.Text="自動解析 (各USDのフレーム範囲を使用)"; $rbAuto.Location="15,25"; $rbAuto.Width=300; $rbAuto.Checked = ($conf["BATCH_MODE"] -eq "Auto"); $groupMode.Controls.Add($rbAuto)
$rbManual = New-Object Windows.Forms.RadioButton; $rbManual.Text="手動設定"; $rbManual.Location="15,55"; $rbManual.Width=100; $rbManual.Checked = ($conf["BATCH_MODE"] -eq "Manual"); $groupMode.Controls.Add($rbManual)
$nFS = New-Object Windows.Forms.NumericUpDown; $nFS.Location="120,53"; $nFS.Width=70; $nFS.Minimum=-999999; $nFS.Maximum=999999; $nFS.Value=[int]$conf["START_FRM"]; $groupMode.Controls.Add($nFS)
$lTo = New-Object Windows.Forms.Label; $lTo.Text="～"; $lTo.Location="195,57"; $lTo.Width=20; $groupMode.Controls.Add($lTo)
$nFE = New-Object Windows.Forms.NumericUpDown; $nFE.Location="220,53"; $nFE.Width=70; $nFE.Minimum=-999999; $nFE.Maximum=999999; $nFE.Value=[int]$conf["END_FRM"]; $groupMode.Controls.Add($nFE)
$btnAnalyze = New-Object Windows.Forms.Button; $btnAnalyze.Text="解析"; $btnAnalyze.Location="300,45"; $btnAnalyze.Size="140,40"; $groupMode.Controls.Add($btnAnalyze)
$lbRange = New-Object Windows.Forms.Label; $lbRange.Text="(USD Range: -- to --)"; $lbRange.Location="120,85"; $lbRange.Width=300; $lbRange.ForeColor="Gray"; $groupMode.Controls.Add($lbRange)
$cS = New-Object Windows.Forms.CheckBox; $cS.Text="単一フレームのみレンダリング"; $cS.Location="30,120"; $cS.Width=250; $cS.Checked = [System.Convert]::ToBoolean($conf["SINGLE"]); $groupMode.Controls.Add($cS)

# --- Advanced Settings (右側) ---
$advX = 500; $advY = 10
$groupAdv = New-Object Windows.Forms.GroupBox; $groupAdv.Text="Advanced Settings"; $groupAdv.Location="$advX,$advY"; $groupAdv.Size="280,625"; $f.Controls.Add($groupAdv)

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



# --- ロジックとイベント ---
$updatePreview = {
    $dir = if([string]::IsNullOrWhiteSpace($tOUT.Text)){"C:/render"}else{$tOUT.Text.Replace("\","/")}
    $dir = if([string]::IsNullOrWhiteSpace($tOUT.Text)){
        if($listUSD.Items.Count -gt 0){ 
            $p = Split-Path -Parent $listUSD.Items[0]; if($p){ $p.Replace("\","/") }else{ "." }
        }else{"C:/render"}
    }else{
        $tOUT.Text.Replace("\","/")
    }
    $base = if($rbNameUSD.Checked){ 
        if($listUSD.Items.Count -gt 0){ [System.IO.Path]::GetFileNameWithoutExtension($listUSD.Items[0]) }else{"filename"}
    }else{$tNameBase.Text}
    $lPreview.Text = "Preview:`n$dir/$base.$('0'*($nPad.Value-1))1.$($tExt.Text.TrimStart('.'))`n(Scale: $($trackRes.Value * 10)%)"
    $lPreview.ForeColor = if($chkOutToggle.Checked){[System.Drawing.Color]::Blue}else{[System.Drawing.Color]::Gray}
}

$updateControlState = {
    # Houdini Bin チェック
    if (![string]::IsNullOrWhiteSpace($tHOU.Text) -and (Test-Path (Join-Path $tHOU.Text "husk.exe"))) {
        $lHouCheck.Text = "〇 OK"; $lHouCheck.ForeColor = "DarkGreen"
    } else {
        $lHouCheck.Text = "× husk.exe not found"; $lHouCheck.ForeColor = "Red"
    }

    $count = $listUSD.Items.Count
    if ($count -gt 1) { 
        $lModeInfo.Text="モード: 一括処理"; 
        $rbManual.Enabled=$true; $btnAnalyze.Enabled=$false
        $rbNameCustom.Enabled=$false; if($rbNameCustom.Checked){$rbNameUSD.Checked=$true}
        $nFS.Enabled=$rbManual.Checked; $nFE.Enabled=($rbManual.Checked -and -not $cS.Checked); $cS.Enabled=$rbManual.Checked
    } else { 
        $lModeInfo.Text="モード: 単一詳細設定"; $rbManual.Enabled=$rbNameCustom.Enabled=$true
        $tNameBase.Enabled=($rbNameCustom.Checked -and $chkOutToggle.Checked); $btnAnalyze.Enabled=$nFS.Enabled=$rbManual.Checked
        $nFE.Enabled=($rbManual.Checked -and -not $cS.Checked); $cS.Enabled=$rbManual.Checked
    }
    # カスタマイズトグルのグレーアウト連動
    $tOUT.Enabled = $rbNameUSD.Enabled = $rbNameCustom.Enabled = $tExt.Enabled = $nPad.Enabled = $chkOutToggle.Checked
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
$btnClear.Add_Click({ $listUSD.Items.Clear(); & $updateControlState })
$trackRes.Add_ValueChanged({ $lRes.Text = "Resolution Scale: $($trackRes.Value * 10)%"; & $updatePreview })
$listUSD.Add_KeyDown({ if ($_.KeyCode -eq [Windows.Forms.Keys]::Delete -and $this.SelectedIndex -ge 0) { $this.Items.RemoveAt($this.SelectedIndex); & $updateControlState } })
$btnAnalyze.Add_Click({
    if ($listUSD.SelectedIndex -lt 0) { return }
    $btnAnalyze.Text = "..."; $f.Refresh()
    $res = Get-USDFrameRange $listUSD.SelectedItem $tHOU.Text
    if ($res) { $nFS.Value = $res.start; $nFE.Value = $res.end; $lbRange.Text = "(USD Range: $($res.start) to $($res.end))"; $lbRange.ForeColor = "DarkGreen" }
    $btnAnalyze.Text = "解析"
})
$chkOutToggle.Add_CheckedChanged({ & $updateControlState })
$rbNameUSD.Add_CheckedChanged({ & $updateControlState })
$rbNameCustom.Add_CheckedChanged({ & $updateControlState })
$rbAuto.Add_CheckedChanged({ & $updateControlState })
$rbManual.Add_CheckedChanged({ & $updateControlState })
$cS.Add_CheckedChanged({ & $updateControlState })
$comboNoti.Add_SelectedIndexChanged({ & $updateControlState })

# --- 保存処理をClosingイベントに集約 ---
$f.Add_FormClosing({
    if ($f.DialogResult -eq [Windows.Forms.DialogResult]::OK) {
        $items = if($listUSD.Items){ $listUSD.Items | ForEach-Object { $_.ToString() } } else { @() }
        $isReboot = ($comboShutdown.Text -eq "再起動")
        $res = @("HOUDINI_BIN=$($tHOU.Text)", "USD_LIST=$([string]::Join(',',$items))", "OUT_PATH=$($tOUT.Text)", "START_FRM=$($nFS.Value)", "END_FRM=$($nFE.Value)", "REBOOT=$isReboot", "SHUTDOWN_ACTION=$($comboShutdown.Text)", "SINGLE=$($cS.Checked)", "BATCH_MODE=$(if($rbAuto.Checked){'Auto'}else{'Manual'})", "OUT_TOGGLE=$($chkOutToggle.Checked)", "OUT_NAME_MODE=$(if($rbNameUSD.Checked){'USD'}else{'Custom'})", "OUT_NAME_BASE=$($tNameBase.Text)", "EXT=$($tExt.Text)", "PADDING=$($nPad.Value)", "RES_SCALE=$($trackRes.Value * 10)", "PIXEL_SAMPLES=$($nPS.Value)", "NOTIFY=$($comboNoti.Text)", "DISCORD_WEBHOOK=$($tWeb.Text)", "TIMEOUT_WARN=$($nTW.Value)", "TIMEOUT_KILL=$($nTK.Value)", "ENGINE_TYPE=$($comboEngine.Text)")
        $res | Set-Content $iniPath -Encoding Default
    }
})

$btnRun = New-Object Windows.Forms.Button; $btnRun.Text="保存して開始"; $btnRun.Location="250,$($y + 210)"; $btnRun.Size="300,50"; $f.Controls.Add($btnRun)
$btnRun.Add_Click({ $f.DialogResult = [Windows.Forms.DialogResult]::OK; $f.Close() })

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

$listUSD.AllowDrop = $true
$listUSD.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = "Copy" } })
$listUSD.Add_DragDrop({ $files = $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop); foreach ($file in $files) { if ($file -match "\.usd[azc]?$") { [void]$listUSD.Items.Add($file) } }; & $updateControlState })

# --- 起動時の初期反映 ---
& $updateControlState

# ウィンドウ表示と終了判定
$result = $f.ShowDialog()
if ($result -ne [Windows.Forms.DialogResult]::OK) { exit 2 }
exit 0

