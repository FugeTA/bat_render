# Husk Batch Render - モジュール構成

このプロジェクトは、メンテナンス性を向上させるためにモジュール化されています。

## ファイル構成

```
src/
├── scripts/
│   ├── HuskCommon.psm1           # 共通ユーティリティモジュール
│   ├── HuskRenderLogic.psm1      # レンダリングロジックモジュール
│   ├── HuskGuiComponents.psm1    # GUIコンポーネントモジュール
│   ├── husk_gui.ps1               # GUIメインスクリプト
│   └── husk_logger.ps1            # レンダリング実行スクリプト
├── config/
│   ├── settings.ini               # グローバル設定
│   └── usd_overrides.xml          # USD個別設定
└── ...
```

## モジュール詳細

### 1. HuskCommon.psm1 (共通ユーティリティ)

**目的**: GUIとレンダリング実行スクリプトの両方で使用される基本的な補助関数を提供

**主な機能**:
- `Normalize-UsdPath`: パスの正規化処理
- `Get-USDFrameRange`: hython.exeを使用してUSDファイルからフレーム範囲を取得
- `Parse-RangeText`: 文字列（例: "1001-1010,1050"）をオブジェクト形式に変換
- `Convert-RangePairs`: 範囲オブジェクトを標準化されたハッシュテーブル形式に変換
- `Get-IniSettings`: デフォルト設定の定義と設定ファイルの読み込み
- `Load-UsdOverrides`: 個別設定（XML）の読み込み
- `Save-UsdOverrides`: 個別設定（XML）の保存
- `Send-WindowsToast`: Windows通知の送信
- `Send-DiscordNotification`: Discord Webhookへの通知送信

**利点**:
- データの保存形式を将来的にJSONなどに変更する場合も、一箇所の修正で済む
- 通知機能が独立しているため、他の通知サービス（Slack等）の追加が容易

### 2. HuskRenderLogic.psm1 (レンダリングロジック)

**目的**: レンダリングプラン構築とジョブ管理のロジックを提供

**主な機能**:
- `Get-DefaultRanges`: デフォルトのフレーム範囲を取得
- `Build-RenderJobPlan`: 個別設定、グローバル設定、自動解析結果を統合して、レンダリングに必要な全パラメータを確定

**利点**:
- GUIを通さずにコマンドラインから直接ジョブを生成することが可能
- レンダリング設定のロジックが独立しているため、テストやデバッグが容易

**依存関係**:
- HuskCommon.psm1をインポート

### 3. HuskGuiComponents.psm1 (GUIコンポーネント)

**目的**: GUI特有の定型的なコントロール作成機能を提供

**主な機能**:
- `Add-SaveDefaultMenu`: コンテキストメニュー（右クリックメニュー）の生成と保存ロジック
- `Add-LockButton`: 設定をロックする南京錠ボタンの生成

**利点**:
- GUIコードの重複を削減
- 一貫したUI動作を保証
- GUI部品の再利用が容易

**依存関係**:
- HuskCommon.psm1をインポート

### 4. husk_gui.ps1 (GUIメインスクリプト)

**目的**: フォームのレイアウトとイベント処理を管理

**特徴**:
- 上記3つのモジュールをインポートして使用
- フォームの構築とユーザーインタラクションに集中
- ビジネスロジックはモジュールに委譲

**依存関係**:
- HuskCommon.psm1
- HuskGuiComponents.psm1

### 5. husk_logger.ps1 (レンダリング実行スクリプト)

**目的**: 実際のレンダリング処理を実行

**特徴**:
- モジュールから提供される関数を使用してジョブプランを構築
- husk.exeの実行と監視
- 通知の送信

**依存関係**:
- HuskCommon.psm1
- HuskRenderLogic.psm1

## モジュール化の利点

### メンテナンス性の向上
- 機能ごとに分離されているため、修正箇所が明確
- 重複コードが削減され、バグ修正が一箇所で済む
- コードの役割が明確になり、理解しやすい

### 拡張性の向上
- 新しい通知サービスの追加が容易（HuskCommon.psm1に関数を追加するだけ）
- 設定ファイル形式の変更が容易（HuskCommon.psm1の関数を修正するだけ）
- 新しいレンダリングパラメータの追加が容易

### テスト容易性の向上
- 各モジュールを個別にテスト可能
- モックやスタブを使用した単体テストが容易

### 再利用性の向上
- 他のプロジェクトでモジュールを再利用可能
- コマンドラインツールやバッチスクリプトから直接モジュールを使用可能

## 使用方法

### GUIの起動
```powershell
powershell -ExecutionPolicy Bypass -File .\src\scripts\husk_gui.ps1
```

### コマンドラインからの実行
```powershell
powershell -ExecutionPolicy Bypass -File .\src\scripts\husk_logger.ps1
```

### モジュールの直接利用（例）
```powershell
Import-Module .\src\scripts\HuskCommon.psm1
$settings = Get-IniSettings ".\src\config\settings.ini"
```

## 今後の拡張予定

- レンダリングキューの管理機能
- 複数マシンでの分散レンダリングサポート
- レンダリング履歴とログの可視化
- プリセット設定の保存・読み込み機能

## トラブルシューティング

### モジュールが読み込めない場合
- PowerShellの実行ポリシーを確認: `Get-ExecutionPolicy`
- 必要に応じて: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

### "unapproved verb"の警告について
- これはPowerShellの推奨動詞リストに含まれていない関数名に対する警告です
- 動作には影響しませんが、気になる場合は`-DisableNameChecking`オプションを使用してインポート可能

## ライセンス

このプロジェクトのライセンスについては、プロジェクトルートのライセンスファイルを参照してください。
