# VibingSpeech

完全にデバイス内で動作するmacOS音声入力アプリ。録音完了後、AIが文脈の一括解析を行い、リアルタイム手法よりも高精度な文字起こしを実現します。文全体の意味を理解してからテキストに変換するため、同音異義語の誤変換が大幅に削減されます。グローバルホットキー → 録音 → 文字起こし（Qwen3-ASR） → オプションのLLMテキスト処理 → カーソル位置にテキスト貼り付け。Apple Silicon専用。

## 機能

- ✅ **グローバルホットキー:** 右Optionを長押しで録音、離すと転写（短押しでトグルモード）
- ✅ **オンデバイス転写:** Qwen3-ASRモデルを使用、クラウド呼び出しなしで完全にローカル実行
- ✅ **モデル選択:** 0.6B（8ビット、~1GB）と1.7B（4ビット、~2.1GB）のASRモデルから選択
- ✅ **LLMテキスト処理:** mlx-swift-lm経由でQwen3-4B-Instruct-2507-4bitを使用したオプションのオンデバイス後処理
- ✅ **処理プリセット:** エラー訂正用の「タイポ修正」、リスト形式用の「箇条書き」、ユーザー定義プロンプト用の「カスタム」
- ✅ **フローティングオーバーレイ:** 録音中のアニメーション付きマイクインジケーター
- ✅ **ホットワード辞書:** カスタム用語を追加して認識精度を向上
- ✅ **転写履歴:** 設定可能な保持期間で過去の転写を表示・管理
- ✅ **52言語:** 自動言語検出
- ✅ **メニューバー常駐:** バックグラウンド実行、Dockアイコンなし
- ✅ **アクセシビリティ対応:** テキスト入力を受け付けるあらゆるアプリケーションで動作

## 必要要件

- macOS 26.0+（Tahoe）
- Apple Silicon（M1以降）
- Xcode 26+ / Command Line Tools（Swift 6.2付き）
- **Metal Toolchain**（下記の[Metal Toolchain セットアップ](#metal-toolchain-セットアップ)を参照）

## Metal Toolchain セットアップ

Xcode 26以降、**Metal ToolchainはXcodeにバンドルされなくなり**、別途インストールが必要です。VibingSpeechはMLX Swiftに依存しており、ビルド時にMetalシェーダーのコンパイルが必要です。Metal Toolchainがないとビルドに失敗します。

**Xcode UIでインストール:**

1. Xcode → 設定 → コンポーネントを開く
2. 「その他のコンポーネント」で**Metal Toolchain**を見つける
3. **取得**をクリックしてダウンロード・インストール

**コマンドラインでインストール:**

```bash
xcodebuild -downloadComponent metalToolchain
```

インストールの確認:

```bash
xcrun metal --version
```

バージョン番号（例：`metal version 32.x.x`）が表示されれば、ツールチェーンの準備完了です。

> **注意:** 一部のXcode 26バージョンでは、ダウンロード後にツールチェーンが正しく登録されない場合があります。インストール後もエラーが出る場合は以下を試してください:
> ```bash
> xcodebuild -downloadComponent metalToolchain -exportPath /tmp/MetalExport/
> xcodebuild -importComponent metalToolchain -importPath /tmp/MetalExport/*.exportedBundle
> ```

## ビルド & 実行

```bash
git clone https://github.com/Shuichi346/VibingSpeech.git
cd VibingSpeech
make build
make run
```

`make build`はSwiftパッケージをコンパイルし、MLX Metalシェーダーライブラリ（`mlx.metallib`）をビルドします。シェーダービルドはキャッシュされ、ソースファイルが変更された時のみ再コンパイルされます。

スタンドアロンの`.app`バンドルを作成:

```bash
make app
open VibingSpeech.app

# または/Applicationsにインストール
cp -r VibingSpeech.app /Applications/
```

初回起動時に選択されたASRモデル（デフォルトの0.6Bモデルで約1GB）が自動的にダウンロードされます。テキスト処理が有効な場合、Qwen3-4B-Instructモデル（約2.5GB）もダウンロードされます。

## 権限

VibingSpeechには2つの権限が必要です:

1. **アクセシビリティ権限:** グローバルホットキー検出とテキスト挿入に必要
2. **マイク権限:** 音声録音に必要

初回起動時に権限を許可するようプロンプトが表示されます。プロンプトを見逃した場合は、後でシステム設定 → プライバシーとセキュリティで有効にできます。

## 使用方法

1. アプリを起動 — メニューバーにマイクアイコンが表示されます
2. **長押しモード:** 話している間は右Optionキーを押し続け、終わったら離す
3. **トグルモード:** 右Optionを短押しで録音開始、もう一度押して停止
4. **録音キャンセル:** 録音中はいつでもEscキーでキャンセル
5. メニューバーアイコンをクリック → 「ウィンドウを表示」で設定、ホットワード、履歴にアクセス

## ASRモデル選択

| モデル | サイズ | メモリ | 精度 |
|---|---|---|---|
| Qwen3-ASR 0.6B (8ビット) | ~1.0 GB | ~1.5 GB | 一般用途に適している |
| Qwen3-ASR 1.7B (4ビット) | ~2.1 GB | ~3.5 GB | 複雑な音声でより高い精度 |

## テキスト処理（LLM）

有効にすると、転写されたテキストは貼り付け前にオンデバイスLLMで後処理されます。これは完全にオプションです — 無効時はLLMモデルは読み込まれず、転写は追加のメモリ使用量や遅延なしで以前と同様に動作します。

**モデル:** [Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) （約2.5GBダウンロード、約3.5GBメモリ）

**プリセット:**

| プリセット | 説明 |
|---|---|
| タイポ修正 | 意味を保持しながらスペルエラー、タイポ、文法を修正 |
| 箇条書き | テキストを構造化された箇条書きリストに再フォーマット |
| カスタム | あらゆる処理タスクにユーザー定義システムプロンプトを使用 |

**フロー:** 録音 → 転写（ASR） → 言語検出 → テキスト処理（LLM） → 貼り付け

テキスト処理モデルは機能がオンに切り替えられた時のみ読み込まれ、オフにすると解放されるため、使用しない時のメモリ使用量を最小限に抑えます。

## トラブルシューティング

### Metalシェーダービルドが失敗する

Metal Toolchainがインストールされていることを確認してください（[Metal Toolchain セットアップ](#metal-toolchain-セットアップ)を参照）:

```bash
xcodebuild -downloadComponent metalToolchain
```

ツールチェーンがインストールされているが`xcrun metal`が失敗する場合は、ターミナルを再起動するか正しいXcodeを選択してください:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### 実行時に`Failed to load the default metallib`

Metalシェーダーライブラリがビルドされていません。以下を実行:

```bash
make metallib
```

これはMLX Swift依存関係から`.metal`シェーダーソースをコンパイルし、バイナリの隣に`mlx.metallib`を配置します。

### グローバルホットキーが動作しない

システム設定 → プライバシーとセキュリティ → アクセシビリティでアクセシビリティ権限が有効になっていることを確認してください。

### 開発者を確認できないためアプリを開けない

```bash
xattr -cr VibingSpeech.app
```

## アーキテクチャ

```
Sources/VibingSpeech/
├── App/              # @main, AppDelegate, AppState（中央状態）
├── Audio/            # AudioCaptureManager, TranscriptionEngine（Qwen3-ASR）
├── HotkeyManager/    # GlobalHotkeyManager（CGEventTap）
├── TextInsertion/    # クリップボード + Cmd+Vシミュレーション
├── TextProcessing/   # mlx-swift-lm経由のLLMベーステキスト処理（Qwen3-4B-Instruct）
├── Persistence/      # UserDefaults設定、JSON履歴/ホットワード
├── Views/            # メインウィンドウタブ、フローティングオーバーレイ
├── Models/           # データモデル、プリセット
└── Utilities/        # 権限、サウンドフィードバック、アーキテクチャチェック
```

## 依存関係

| パッケージ | バージョン | 用途 |
|---|---|---|
| [speech-swift](https://github.com/soniqo/speech-swift) | ≥ 0.0.9 | Qwen3-ASR音声認識エンジン |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 2.31.3 | テキスト処理のLLM推論 |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.x | MLX配列フレームワーク（共有依存関係） |

## クレジット

- **speech-swift** (Apache 2.0) — https://github.com/soniqo/speech-swift
- **mlx-swift-lm** (MIT) — https://github.com/ml-explore/mlx-swift-lm
- **Qwen3-ASR** — Alibaba Cloud
- **Qwen3-4B-Instruct-2507** — Alibaba Cloud
- **MLX Swift** — Apple Machine Learning Explore

## ライセンス

MIT
