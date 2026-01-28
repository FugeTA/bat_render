# Husk Render Launcher

Houdini Solaris (husk) でのバッチレンダリングを効率化する軽量ツール。

## 概要

GUIによる直感的な設定、詳細なログ収集、リアルタイム進捗監視、完了後の自動アクション実行機能を備えたPowerShellベースのレンダリングランチャー。

## フォルダ構造

```
src/
├── husk_gui_render.bat   # 起動用メインバッチ
├── scripts/
│   ├── husk_gui.ps1      # 設定用GUI (Windows Forms)
│   └── husk_logger.ps1   # ログ管理・実行エンジン
├── config/
│   └── settings.ini      # 自動生成される設定データ
└── log/
    └── render_YYYYMMDD_HHMM.log  # 詳細ログ (Verbose 3)
```

## 主な機能

### GUI機能
- **Houdini Bin パス設定**: husk.exe の場所を指定（自動検証付き）
- **USDリスト管理**: 複数ファイル対応、Drag&Drop、Del キーで削除
  - グリッドで選択したUSDを個別に設定可能（選択中のUSDの設定として表示）
  - 「〇」マークで個別設定の有無を表示
  - レンジと出力先のサマリーが各行に表示
- **USD個別設定（オーバーライド）**: 各USDファイルに対して個別の設定を保存
  - usd_overrides.xml に自動保存
  - グローバル設定（settings.ini）より優先
  - 「ini設定に戻す」ボタンで個別設定をリセット
- **出力設定**: パス、ファイル名（USD名/カスタム）、拡張子、パディング桁数
  - リアルタイム出力プレビュー表示
- **フレーム範囲**: 自動解析（USD Stage から取得）/ 手動設定 / 複数範囲設定
  - **Auto**: USD Stage の StartTimeCode/EndTimeCode を自動取得
  - **Manual**: 開始・終了フレームを手動指定
  - **Multi**: カンマ区切りで複数範囲を指定（例: 1001-1010,1050,1100-1150）
  - 「解析」ボタンで選択中のUSDのフレーム範囲を手動取得
- **単一フレームモード**: 開始と終了を自動同期

### Advanced Settings

#### 1. Render Setting
- **Resolution Scale**: 10%～200% (トラックバー)
- **Pixel Samples**: 0=デフォルト、>0 で `--pixel-samples` に渡す
- **Engine Override**: cpu / xpu の選択

#### 2. Timeout & Notification
- **Warn Timeout (Min)**: 指定分数経過で警告通知
- **Kill Timeout (Min)**: 0=無効、>0 で `--timelimit` に秒換算で渡す
- **Notification**: None / Windows Toast / Discord
- **Discord Webhook URL**: Discord通知用のWebhook URL

#### 3. 完了後のアクション
- なし / シャットダウン / 再起動 / ログオフ
- 設定時はメニューをスキップし、30秒のカウントダウン後に実行

### コンテキストメニュー機能

GUI内のほとんどの設定項目を**右クリック**することで、以下の操作が可能です：

- **この値をデフォルトとして保存**: 現在の値を settings.ini にデフォルト値として保存します
- **値をコピー**: 現在の値をクリップボードにコピーします

対応コントロール：
- すべての数値入力（Resolution Scale、Pixel Samples、フレーム範囲、パディング桁数など）
- ドロップダウン（Engine、Notification、完了後のアクションなど）
- テキスト入力（出力パス、ファイル名、拡張子、Discord Webhook URLなど）
- チェックボックス・ラジオボタン（出力カスタマイズ、ファイル名モードなど）

### 実行機能
- **レンダリングプラン事前表示**: 実行前に総レンダリング回数と各USDのフレーム範囲を表示
  - Autoモード時は各USDファイルを解析して進捗を表示（「解析中: filename.usd ✓」）
- **スマート進捗監視**: 1行更新でリアルタイム表示（進捗%、フレーム、経過時間、上限時間）
  - `Saved Image:` パスを監視して保存先フォルダを自動記録
- **詳細ログ記録**: `--verbose 3` で全出力を log/ に保存
  - ログファイル名: `PC名_YYYYMMDD_HHMM.log`
  - 実行コマンドも記録
- **エラー検出**: ExitCode 非0 時に赤字表示 + Discord通知（設定時）
  - Discord通知時は @everyone メンション付き、赤色表示
- **完了サマリー**: レンダリング完了したファイル一覧を表示
- **完了後メニュー**: O=保存先を開く、L=ログを開く、X=終了
  - 完了後のアクション設定時はメニューをスキップ

## 技術仕様

### レンダリングエンジン
- **Engine**: Karma XPU / CPU (husk)
- **License Mode**: `--skip-licenses apprentice` で Apprentice ライセンス回避
- **Output**: `$F4` シーケンス形式をサポート
- **Logging**: PowerShell の標準出力・標準エラー出力をリアルタイムストリーム処理

### husk コマンドライン引数

自動生成される引数:
```powershell
--verbose 3
--skip-licenses apprentice
--make-output-path
--timelimit-image
--timelimit-nosave-partial
-f <start_frame>
-n <frame_count>
--output <path>
--engine <cpu|xpu>          # ENGINE_OVERRIDE=True 時
--res-scale <percentage>     # RES_SCALE≠100 時
--pixel-samples <value>      # PIXEL_SAMPLES>0 時
--timelimit <seconds>        # TIMEOUT_KILL>0 時（分→秒換算）
<usd_path>
```

### 設定ファイル (settings.ini)

```ini
HOUDINI_BIN=C:\Program Files\Side Effects Software\Houdini 21.0.440\bin
USD_LIST=path1.usd,path2.usd
OUT_PATH=C:/render
START_FRM=1
END_FRM=100
REBOOT=False
SHUTDOWN_ACTION=なし
SINGLE=False
BATCH_MODE=Auto
OUT_TOGGLE=True
OUT_NAME_MODE=USD
OUT_NAME_BASE=render
EXT=exr
PADDING=4
RES_SCALE=100
PIXEL_SAMPLES=0
NOTIFY=None
DISCORD_WEBHOOK=
TIMEOUT_WARN=0
TIMEOUT_KILL=0
ENGINE_OVERRIDE=False
ENGINE_TYPE=cpu
```

### バッチ終了コード

**husk_gui.ps1**:
- `0`: 正常完了（設定保存してレンダリング開始）
- `2`: ユーザーキャンセル（ダイアログクローズ）
- `その他`: GUI実行エラー

**husk_gui_render.bat**:
```batch
if %GUI_EXIT% equ 0 (
    :: ロガー実行
) else if %GUI_EXIT% equ 2 (
    :: キャンセルメッセージ
) else (
    :: エラーメッセージ
)
```

## 実装の詳細

### フレーム範囲の自動解析

```powershell
function Get-USDFrameRange {
    param($usdPath, $houBin)
    $hythonExe = Join-Path $houBin "hython.exe"
    $pyCode = "from pxr import Usd; stage = Usd.Stage.Open('...');
               print(f'START:{stage.GetStartTimeCode()} END:{stage.GetEndTimeCode()}')"
    # ProcessStartInfo で hython 実行 → 正規表現で抽出
}
```

### タイムアウト制御

- **TIMEOUT_WARN**: PowerShell 側で経過時間を監視し、指定分数超過で通知
- **TIMEOUT_KILL**: `--timelimit` に秒数を渡し、husk 側でタイムアウト処理
  - 0 の場合は `-1`（無制限）を渡す
  - >0 の場合は `分 × 60` で秒換算

### 通知機能

#### Windows Toast
```powershell
[Windows.UI.Notifications.ToastNotificationManager]
```
を使用した WinRT トースト通知。

#### Discord
```powershell
Invoke-RestMethod -Uri $webhook -Method Post -Body $json
```
埋め込みメッセージで通知（エラー時は赤色）。

### 完了後アクション

```powershell
switch ($conf["SHUTDOWN_ACTION"]) {
    "シャットダウン" { shutdown /s /t 5; exit }
    "再起動" { shutdown /r /t 5; exit }
    "ログオフ" { shutdown /l; exit }
}
```

30秒のカウントダウン中にキー入力で中止可能。

## ドラッグ＆ドロップ対応

- **render.bat にドロップ**: `%~1` でパスを受け取り、`-dropFile` パラメータで GUI に渡す
- **GUI内のテキストボックス**: `AllowDrop=true` + `DragEnter`/`DragDrop` イベント
- **USDリスト**: `.usd`, `.usda`, `.usdc`, `.usdz` の拡張子をフィルタ

## 互換性とフォールバック

- **旧設定との互換性**: `REBOOT=True` の場合は `SHUTDOWN_ACTION=再起動` として扱う
- **TIMEOUT_KILL_ENABLE の廃止**: 0 チェックで判定（シンプル化）
- **エンコーディング**: UTF-8 で保存（文字化け防止）

## Houdiniライセンス

本ツールは Houdini Apprentice以外のライセンス環境での使用を想定しています。
`--skip-licenses apprentice` により、Apprenticeライセンスチェックをスキップします。