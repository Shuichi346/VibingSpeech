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
  <strong>完全オンデバイスのmacOS音声入力アプリ。</strong><br>
  録音完了後、AIが文脈を一括分析することで、リアルタイム方式よりも高精度な音声認識を実現。文章全体の意味を理解してからテキストに変換するため、同音異義語の誤変換が大幅に削減されます。グローバルホットキー → 録音 → 音声認識（Qwen3-ASR）→ オプションのLLMテキスト処理 → カーソル位置にペースト。
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
  <em>ホーム — ASRモデル、テキスト処理、ホットキーなどの設定。</em>
</p>

<p align="center">
  <img src="docs/README_PNG/UI_Hotwords.png" alt="ホットワード — カスタム語彙" width="500">
  <br>
  <em>固有名詞や専門用語のホットワード辞書。</em>
</p>

<p align="center">
  <img src="docs/README_PNG/UI_History.png" alt="履歴 — 音声認識ログ" width="500">
  <br>
  <em>検索可能な音声認識履歴。</em>
</p>

---

## 特徴

- ✅ **グローバルホットキー** — 右Optionキーを長押しで録音、離すと音声認識（短押しでトグルモード）
- ✅ **オンデバイス音声認識** — Qwen3-ASRモデル、クラウド通信不要、52言語自動検出
- ✅ **ASRモデル選択** — 0.6B（8-bit、約1GB）、1.7B（4-bit、約2.1GB）、1.7B（8-bit、約2.3GB）から選択
- ✅ **LLMテキスト処理** — オプションでQwen3-4B-Instruct-2507-4bitによるオンデバイス後処理
- ✅ **処理プリセット** — 「誤字修正」、「箇条書き」、または完全カスタムプロンプト
- ✅ **フローティングオーバーレイ** — 録音中のアニメーション波形インジケーター
- ✅ **ホットワード辞書** — カスタム用語を追加して認識精度を向上
- ✅ **音声認識履歴** — 過去の音声認識結果を表示、コピー、管理
- ✅ **メニューバー常駐** — Dockアイコンなしでバックグラウンド実行
- ✅ **プライバシー最優先** — すべての処理がMac内で完結、データは外部に送信されません

## システム要件

- macOS 26.0+（Tahoe）
- Apple Silicon（M1以降）
- Xcode 26+ / Command Line Tools（Swift 6.2）
- **Metal Toolchain**（[Metal Toolchainセットアップ](#metal-toolchainセットアップ)を参照）

## Metal Toolchainセットアップ

Xcode 26以降では、**Metal Toolchainが同梱されなくなり**、別途インストールが必要です。VibingSpeechはMLX Swiftに依存しており、ビルド時にMetalシェーダーをコンパイルします。

**Xcode UIからインストール：**

1. Xcode → 設定 → コンポーネント を開く
2. 「その他のコンポーネント」の下にある**Metal Toolchain**を見つける
3. **取得**をクリック

**コマンドラインからインストール：**

```bash
xcodebuild -downloadComponent metalToolchain
```

確認：

```bash
xcrun metal --version
# 期待値: metal version 32.x.x
```

> **注意：** ダウンロード後にツールチェーンが認識されない場合は、以下を試してください：
> ```bash
> xcodebuild -downloadComponent metalToolchain -exportPath /tmp/MetalExport/
> xcodebuild -importComponent metalToolchain -importPath /tmp/MetalExport/*.exportedBundle
> ```

## ビルドと実行

```bash
git clone https://github.com/Shuichi346/VibingSpeech.git
cd VibingSpeech
make build
make run
```

`make build`はSwiftパッケージをコンパイルし、MLX Metalシェーダーライブラリ（`mlx.metallib`）をビルドします。シェーダービルドはキャッシュされ、ソースが変更された場合のみ再コンパイルされます。

スタンドアロンの`.app`バンドルを作成するには：

```bash
make app
open VibingSpeech.app

# または /Applications にインストール
cp -r VibingSpeech.app /Applications/
```

初回起動時、選択されたASRモデル（デフォルトの0.6Bで約1GB）が自動的にダウンロードされます。テキスト処理が有効な場合、Qwen3-4B-Instructモデル（約2.5GB）もダウンロードされます。

## モデルキャッシュの場所

VibingSpeechは初回起動時に2種類のモデルをダウンロードします。それぞれMac上の異なる場所にキャッシュされます。

### ASRモデル（Qwen3-ASR）

[speech-swift](https://github.com/soniqo/speech-swift)経由でダウンロードされ、以下の場所に保存されます：

```
~/Library/Caches/qwen3-speech/
```

このディレクトリには選択されたASRモデルの重み（0.6B、1.7Bなど）が含まれます。`QWEN3_CACHE_DIR`環境変数を設定することでこの場所をオーバーライドできます。

### テキスト処理モデル（Qwen3-4B-Instruct）

[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)経由でHugging Face Hubクライアントを使用してダウンロードされ、以下の場所に保存されます：

```
~/.cache/huggingface/hub/
```

モデルファイルは`models--mlx-community--Qwen3-4B-Instruct-2507-4bit`という名前のサブディレクトリ内にあります。`HF_HOME`または`HF_HUB_CACHE`環境変数を設定することでこの場所をオーバーライドできます。

### ディスク容量の解放

ディスク容量を回収したい場合は、上記のディレクトリを削除するだけです。VibingSpeechは次回起動時に必要なモデルを自動的に再ダウンロードします。選択されたASRバリアントとテキスト処理の有効/無効に応じて、モデルは合計で約**1〜4.8GB**の容量を占めます。

> **ヒント：** `~/Library`と`~/.cache`フォルダはFinderでデフォルトで非表示になっています。Finderで`Cmd + Shift + .`を押して隠しファイルを表示するか、Finder → 移動 → フォルダへ移動（`Cmd + Shift + G`）を使用して直接ナビゲートしてください。

## 権限

VibingSpeechには以下の2つの権限が必要です：

1. **アクセシビリティ** — グローバルホットキー検出とテキスト挿入のため
2. **マイク** — 音声録音のため

初回起動時にプロンプトが表示されます。後で有効にするには：システム設定 → プライバシーとセキュリティ。

## 使用方法

1. アプリを起動 — メニューバーにマイクアイコンが表示されます
2. **長押しモード：** 話している間、右Optionキーを押し続け、終わったら離します
3. **トグルモード：** 右Optionキーを短押しして開始、もう一度押して停止
4. **キャンセル：** 録音中いつでもEscキーでキャンセル
5. メニューバーアイコンをクリック → 「ウィンドウを表示」で設定、ホットワード、履歴にアクセス

## ASRモデル選択

| モデル | ダウンロード | メモリ | 最適用途 |
|---|---|---|---|
| Qwen3-ASR 0.6B（8-bit） | 約1.0GB | 約1.5GB | 一般用途、高速起動 |
| Qwen3-ASR 1.7B（4-bit） | 約2.1GB | 約3.5GB | 複雑な音声、高精度 |
| Qwen3-ASR 1.7B（8-bit） | 約2.3GB | 約4.0GB | 最高精度、特に日本語 |

## テキスト処理（LLM）

有効にすると、音声認識されたテキストはペースト前にオンデバイスLLMで後処理されます。**無効の場合、LLMは読み込まれません** — 追加メモリなし、追加レイテンシーなし。

**モデル：** [Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit)（約2.5GBダウンロード、約3.5GBメモリ）

| プリセット | 機能 |
|---|---|
| **誤字修正** | 意味を保持しながらスペル、誤字、文法を修正 |
| **箇条書き** | テキストを構造化された箇条書きリストに再フォーマット |
| **カスタム** | あらゆる処理タスクにユーザー定義のシステムプロンプトを適用 |

**処理フロー：** 録音 → 音声認識（ASR） → 言語検出 → 処理（LLM） → ペースト

## トラブルシューティング

### Metalシェーダービルドが失敗する

```bash
xcodebuild -downloadComponent metalToolchain
```

インストール後も`xcrun metal`が失敗する場合は、ターミナルを再起動するか、正しいXcodeを選択してください：

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### 実行時に`Failed to load the default metallib`エラー

```bash
make metallib
```

### グローバルホットキーが機能しない

システム設定 → プライバシーとセキュリティ → アクセシビリティでアクセシビリティを有効にしてください。

### 開発者を確認できないためアプリを開けない

```bash
xattr -cr VibingSpeech.app
```

## アーキテクチャ

```
Sources/VibingSpeech/
├── App/              # @main、AppDelegate、AppState（中央状態管理）
├── Audio/            # AudioCaptureManager、TranscriptionEngine（Qwen3-ASR）
├── HotkeyManager/    # GlobalHotkeyManager（CGEventTap）
├── TextInsertion/    # クリップボード + Cmd+Vシミュレーション
├── TextProcessing/   # LLMテキスト処理（mlx-swift-lm経由のQwen3-4B）
├── Persistence/      # UserDefaults設定、JSON履歴/ホットワード
├── Views/            # メインウィンドウタブ、フローティングオーバーレイ
├── Models/           # データモデル、プリセット
└── Utilities/        # 権限、サウンドフィードバック、アーキテクチャチェック
```

## 依存関係

| パッケージ | バージョン | 目的 |
|---|---|---|
| [speech-swift](https://github.com/soniqo/speech-swift) | ≥ 0.0.9 | Qwen3-ASR音声認識 |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 2.31.3 | テキスト処理用LLM推論 |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.x | MLX配列フレームワーク（共有） |

## クレジット

- **[speech-swift](https://github.com/soniqo/speech-swift)**（Apache 2.0） — Qwen3-ASR Swiftラッパー
- **[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)**（MIT） — LLM推論フレームワーク
- **[Qwen3-ASR](https://huggingface.co/collections/aufklarer/qwen3-asr-mlx)** — Alibaba Cloud
- **[Qwen3-4B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507)** — Alibaba Cloud
- **[MLX Swift](https://github.com/ml-explore/mlx-swift)** — Apple Machine Learning Explore

## ライセンス

[MIT](LICENSE)
