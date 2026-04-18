<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README.md">English</a></th>
      <th style="text-align:center"><a href="README_jp.md">日本語</a></th>
    </tr>
  </thead>
</table>

<h1 align="center">VibingSpeech</h1>

<p align="center">
  <strong>完全にオンデバイスで動作するmacOS音声入力アプリ</strong><br>
  録音完了後、AIが文脈を一括分析することで、リアルタイム方式よりも高精度な文字起こしを実現。文全体の意味を理解してからテキストに変換するため、同音異義語の誤変換が大幅に削減されます。グローバルホットキー → 録音 → 文字起こし（Qwen3-ASR） → オプションのLLMテキスト処理 → カーソル位置にペースト。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/chip-Apple%20Silicon-black" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/swift-6.2-orange" alt="Swift">
</p>

---

## スクリーンショット

<p align="center">
  <img src="docs/README_PNG/UI_main.png" alt="ホーム — 設定とステータス" width="500">
  <br>
  <em>ホーム — ASRモデル、テキスト処理、ホットキーなどの設定</em>
</p>

<p align="center">
  <img src="docs/README_PNG/UI_Hotwords.png" alt="ホットワード — カスタム語彙" width="500">
  <br>
  <em>固有名詞・専門用語用のホットワード辞書</em>
</p>

<p align="center">
  <img src="docs/README_PNG/UI_History.png" alt="履歴 — 文字起こしログ" width="500">
  <br>
  <em>検索可能な文字起こし履歴</em>
</p>

---

## 機能

- ✅ **グローバルホットキー** — 右Optionを押しながら録音、離すと文字起こし（短押しでトグルモード）
- ✅ **オンデバイス文字起こし** — Qwen3-ASRモデル、クラウド接続なし、52言語自動検出
- ✅ **ASRモデル選択** — 0.6B（8bit、~1 GB）、1.7B（4bit、~2.1 GB）、1.7B（8bit、~2.3 GB）から選択
- ✅ **LLMテキスト処理** — オプションのオンデバイス後処理（Qwen3.5-4B-MLX-4bit、思考無効）
- ✅ **処理プリセット** — 「誤字修正」、「箇条書き」、または完全カスタムプロンプト
- ✅ **フローティングオーバーレイ** — 録音中のアニメーション波形インジケーター
- ✅ **ホットワード辞書** — カスタム用語を追加して認識精度を向上
- ✅ **文字起こし履歴** — 過去の文字起こしの表示、コピー、管理
- ✅ **メニューバー常駐** — Dockアイコンなしでバックグラウンド実行
- ✅ **プライバシー優先** — すべての処理がMac内で完結、デバイス外に情報を送信しません

## システム要件

- macOS 26.0+（Tahoe）
- Apple Silicon（M1以降）
- **Xcode 26+**（App Storeからの完全インストール — Command Line Toolsのみでは不十分）
- インターネット接続（初回モデルダウンロード時、~1–4.8 GB）

> **注意：** このアプリはAppKit、SwiftUI、AVFoundation、CoreAudio、Metalフレームワークを使用しています。macOS SDKとMetal Toolchainサポートを提供するため、完全なXcodeインストールが必要です。

## セットアップガイド（ゼロから）

Macで開発環境を初めて設定する場合は、以下の手順を順番に実行してください。

### ステップ1：Xcodeのインストール

1. MacでApp Storeを開く
2. **Xcode**を検索してインストール（Apple ID必要、~30 GBダウンロード）
3. Xcodeを一度起動してライセンス同意
4. Xcodeが追加コンポーネントのインストールを完了するまで待機

確認方法：

```bash
# ターミナルを開く（アプリケーション → ユーティリティ → ターミナル）
xcode-select -p
# 期待値: /Applications/Xcode.app/Contents/Developer
```

パスが異なる場合は以下を実行：

```bash
sudo xcode-select -s /Applications/Xcode.app
```

> **なぜ完全なXcodeが必要？** このプロジェクトはmacOS SDKフレームワーク（AppKit、SwiftUI、AVFoundation、CoreAudio）とMetal Toolchainに依存しています。Command Line Toolsのみではmetal Toolchainが含まれず、必要なフレームワークを`swift build`が見つけられない場合があります。

### ステップ2：Metal Toolchainのインストール

Xcode 26以降、**Metal ToolchainはバンドルされなくなりSDK**、別途インストールが必要です。VibingSpeechはMLX Swiftに依存しており、ビルド時にMetalシェーダーをコンパイルします。

**Xcode UIでインストール：**

1. Xcode → Settings → Components
2. "Other Components"の**Metal Toolchain**を探す
3. **Get**をクリック

**コマンドラインでインストール：**

```bash
xcodebuild -downloadComponent metalToolchain
```

確認方法：

```bash
xcrun metal --version
# 期待値: metal version 32.x.x
```

> **注意：** ダウンロード後にツールチェインが認識されない場合は以下を試してください：
> ```bash
> xcodebuild -downloadComponent metalToolchain -exportPath /tmp/MetalExport/
> xcodebuild -importComponent metalToolchain -importPath /tmp/MetalExport/*.exportedBundle
> ```

### ステップ3：ツールの確認

Xcodeをインストール後、`git`、`swift`、`make`がすべて利用可能になります。確認方法：

```bash
git --version
# 期待値: git version 2.x.x

swift --version
# 期待値: Apple Swift version 6.2.x

make --version
# 期待値: GNU Make 3.x.x または 4.x.x
```

## ビルドと実行

```bash
git clone https://github.com/Shuichi346/VibingSpeech.git
cd VibingSpeech
make build
make run
```

`make build`はSwiftパッケージをコンパイルし、MLX Metalシェーダーライブラリ（`mlx.metallib`）をビルドします。シェーダービルドはキャッシュされ、ソースが変更された時のみ再コンパイルされます。

スタンドアロンの`.app`バンドルを作成するには：

```bash
make app
open VibingSpeech.app

# または/Applicationsにインストール
cp -r VibingSpeech.app /Applications/
```

### 初回起動

初回起動時、VibingSpeechは必要なAIモデルを自動的にダウンロードします。**インターネット接続が必要です。**

- **ASRモデル**（デフォルト0.6B）：~1 GBダウンロード
- **テキスト処理モデル**（有効な場合）：~2.9 GBダウンロード

ダウンロード進行状況はアプリウィンドウに表示されます。これは一回限りのダウンロードで、モデルは今後の使用のためローカルにキャッシュされます。

## モデルキャッシュの場所

VibingSpeechは初回起動時に2種類のモデルをダウンロードします。それぞれMac上の異なる場所にキャッシュされます。

### ASRモデル（Qwen3-ASR）

[speech-swift](https://github.com/soniqo/speech-swift)経由でダウンロードされ、以下に保存されます：

```
~/Library/Caches/qwen3-speech/
```

このディレクトリには選択されたASRモデルの重み（0.6B、1.7Bなど）が含まれます。`QWEN3_CACHE_DIR`環境変数を設定することでこの場所を変更できます。

### テキスト処理モデル（Qwen3.5-4B）

[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)でHugging Face Hubクライアントを使用してダウンロードされ、以下に保存されます：

```
~/.cache/huggingface/hub/
```

モデルファイルは`models--mlx-community--Qwen3.5-4B-MLX-4bit`という名前のサブディレクトリ内にあります。`HF_HOME`または`HF_HUB_CACHE`環境変数を設定することでこの場所を変更できます。

### ディスク容量の解放

ディスク容量を回収したい場合は、上記のディレクトリを削除してください。VibingSpeechは次回起動時に必要なモデルを自動的に再ダウンロードします。選択したASRバリアントとテキスト処理の有効状況により、モデルは合計で約**1–4.8 GB**を占有する可能性があります。

> **ヒント：** `~/Library`と`~/.cache`フォルダはFinderでデフォルトで非表示になっています。Finderで`Cmd + Shift + .`を押して隠しファイルを表示するか、Finder → 移動 → フォルダへ移動（`Cmd + Shift + G`）を使用して直接ナビゲートしてください。

## 権限

VibingSpeechは2つの権限が必要です：

1. **アクセシビリティ** — グローバルホットキー検出とテキスト挿入のため
2. **マイク** — 音声録音のため

初回起動時にプロンプトが表示されます。後で有効にするには：システム設定 → プライバシーとセキュリティ

## 使用方法

1. アプリを起動 — メニューバーにマイクアイコンが表示されます
2. **ホールドモード：** 話している間右Optionを押し続け、完了時に離す
3. **トグルモード：** 右Optionを短押しして開始、再度押して停止
4. **キャンセル：** 録音中いつでもEscを押す
5. メニューバーアイコンをクリック → "ウィンドウを表示"で設定、ホットワード、履歴にアクセス

## ASRモデル選択

| モデル | ダウンロード | メモリ | 最適な用途 |
|---|---|---|---|
| Qwen3-ASR 0.6B（8bit） | ~1.0 GB | ~1.5 GB | 一般用途、高速起動 |
| Qwen3-ASR 1.7B（4bit） | ~2.1 GB | ~3.5 GB | 複雑な音声、高精度 |
| Qwen3-ASR 1.7B（8bit） | ~2.3 GB | ~4.0 GB | 最高精度、特に日本語 |

## テキスト処理（LLM）

有効な場合、文字起こしされたテキストはペースト前にオンデバイスLLMで後処理されます。**無効な場合、LLMはロードされません** — 追加メモリなし、追加レイテンシーなし。

**モデル：** [Qwen3.5-4B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit)（~2.9 GBダウンロード、~3.5 GBメモリ）

高速で直接的な応答のため、思考（推論）モードは**無効**になっています。モデルは最適化された非思考パラメータを使用：temperature=0.7、top_p=0.8、top_k=20、presence_penalty=1.5

| プリセット | 機能 |
|---|---|
| **誤字修正** | 意味を保持しながらスペル、誤字、文法を修正 |
| **箇条書き** | テキストを構造化された箇条書きリストに再フォーマット |
| **カスタム** | 任意の処理タスク用のユーザー定義システムプロンプトを適用 |

**処理フロー：** 録音 → 文字起こし（ASR） → 言語検出 → 処理（LLM） → ペースト

## トラブルシューティング

### `swift build`が"no such module"エラーで失敗する

完全なXcode（Command Line Toolsだけでなく）がインストールされ、選択されていることを確認してください：

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### Metalシェーダービルドが失敗する

```bash
xcodebuild -downloadComponent metalToolchain
```

インストール後も`xcrun metal`が失敗する場合は、ターミナルを再起動するか正しいXcodeを選択してください：

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### 実行時に`Failed to load the default metallib`

```bash
make metallib
```

### グローバルホットキーが動作しない

システム設定 → プライバシーとセキュリティ → アクセシビリティでアクセシビリティを有効にしてください。

### 開発者を確認できないためアプリを開けない

```bash
xattr -cr VibingSpeech.app
```

### モデルダウンロードが失敗するか非常に遅い

安定したインターネット接続があることを確認してください。モデルはHugging Faceからダウンロードされます。プロキシ環境下の場合は、`HTTP_PROXY`/`HTTPS_PROXY`環境変数を設定してください。

## アーキテクチャ

```
Sources/VibingSpeech/
├── App/              # @main、AppDelegate、AppState（中央状態）
├── Audio/            # AudioCaptureManager、TranscriptionEngine（Qwen3-ASR）
├── HotkeyManager/    # GlobalHotkeyManager（CGEventTap）
├── TextInsertion/    # クリップボード + Cmd+Vシミュレーション
├── TextProcessing/   # LLMテキスト処理（mlx-swift-lm経由のQwen3.5-4B）
├── Persistence/      # UserDefaults設定、JSON履歴/ホットワード
├── Views/            # メインウィンドウタブ、フローティングオーバーレイ
├── Models/           # データモデル、プリセット
└── Utilities/        # 権限、音声フィードバック、アーキテクチャチェック
```

## 依存関係

| パッケージ | バージョン | 目的 |
|---|---|---|
| [speech-swift](https://github.com/soniqo/speech-swift) | ≥ 0.0.9 | Qwen3-ASR音声認識 |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 3.31.3 | テキスト処理用LLM推論 |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.x | MLX配列フレームワーク（共有） |
| [swift-huggingface](https://github.com/huggingface/swift-huggingface) | ≥ 0.9.0 | HuggingFaceモデルダウンローダー（mlx-swift-lm v3） |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | ≥ 1.3.0 | トークナイザー実装（mlx-swift-lm v3） |

## クレジット

- **[speech-swift](https://github.com/soniqo/speech-swift)**（Apache 2.0） — Qwen3-ASR Swiftラッパー
- **[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)**（MIT） — LLM推論フレームワーク
- **[Qwen3-ASR](https://huggingface.co/collections/aufklarer/qwen3-asr-mlx)** — Alibaba Cloud
- **[Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B)** — Alibaba Cloud
- **[MLX Swift](https://github.com/ml-explore/mlx-swift)** — Apple Machine Learning Explore

## ライセンス

[MIT](LICENSE)

このツールで使用される外部モデルやライブラリには、それぞれ独自のライセンスが適用されます。