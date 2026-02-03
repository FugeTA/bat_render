# HuskGuiComponents.psm1
# GUIコンポーネントの部品化

# ============================================================================
# GUIコンポーネント (GUI Components)
# ============================================================================

<#
.SYNOPSIS
コントロールに「デフォルトとして保存」のコンテキストメニューを追加します。

.DESCRIPTION
右クリックメニューから設定値をINIファイルに保存できるようにします。

.PARAMETER control
対象のコントロール

.PARAMETER iniKey
INIファイルのキー名

.PARAMETER displayName
表示名（オプション）

.PARAMETER valueIfChecked
チェックボックス/ラジオボタンがチェックされた際の値（オプション）

.EXAMPLE
Add-SaveDefaultMenu $textBox "OUTPUT_PATH" "出力パス"
#>
function Add-SaveDefaultMenu {
    param(
        [System.Windows.Forms.Control]$control,
        [string]$iniKey,
        [string]$displayName = "",
        [string]$valueIfChecked = ""
    )
    
    if (-not $displayName) { $displayName = $iniKey }
    
    # iniPathを保存（スクリプトスコープから取得）
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
        $script:conf = Get-IniSettings $this.Tag.IniPath

        # 全行の表示を更新（設定列の〇などを再計算）
        if ($gridUSD) {
            foreach ($row in $gridUSD.Rows) { 
                if ($row.Tag) { 
                    if ($script:UpdateGridRow) {
                        & $script:UpdateGridRow $row.Tag
                    }
                } 
            }
        }
        if ($updatePreview) { & $updatePreview }

        [System.Windows.Forms.MessageBox]::Show(
            "デフォルト値を保存しました:`n$($this.Tag.DisplayName) = $value",
            "保存完了",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    })
    $menuSave.Tag = @{ 
        Control = $control
        Key = $iniKey
        DisplayName = $displayName
        IniPath = $localIniPath
        ValueIfChecked = $valueIfChecked 
    }
    
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

<#
.SYNOPSIS
グループボックスに設定ロックボタン（南京錠）を追加します。

.DESCRIPTION
設定をロックする南京錠ボタン（🔓/🔒）を生成し、グループボックスの右上に配置します。

.PARAMETER group
対象のグループボックス

.EXAMPLE
$lockButton = Add-LockButton $groupBox
#>
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
    
    $lockBtn.Add_CheckedChanged({
        $locked = $this.Checked
        $this.Text = if ($locked) { "🔒" } else { "🔓" }
        
        # updateControlStateが定義されていれば呼び出す
        if ($script:updateControlState) { 
            & $script:updateControlState 
        }
        
        # Save-CurrentUsdSettingsが定義されていれば呼び出す
        if ($script:SaveCurrentUsdSettings) {
            & $script:SaveCurrentUsdSettings
        }
    })
    
    $group.Controls.Add($lockBtn)
    $lockBtn.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 12)
    $lockBtn.BringToFront()
    
    return $lockBtn
}

# ============================================================================
# モジュールのエクスポート（ドットソーシング使用時は不要）
# ============================================================================

# Export-ModuleMember -Function @(
#     'Add-SaveDefaultMenu',
#     'Add-LockButton'
# )
