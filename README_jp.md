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
  録音完了後、AIがコンテキストをバッチ解析し、リアルタイム方式よりも高精度な音声認識を実現。文全体の意味を理解してからテキスト変換するため、同音異義語の誤変換が大幅に減少。グローバルホットキー → 録音 → 音声認識（Qwen3-ASR）→ オプショナルLLMテキスト処理 → カーソル位置に貼り付け。
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
  <em>ホーム — ASRモデル、テキスト処理、ホットキーなどを設定。</em>
</p>

<p align="center">
  <img src="docs/README_PNG/UI_Hotwords.png" alt="ホットワード — カスタム語彙" width="500">
  <br>
  <em>固有名詞と専門用語のホットワード辞書。</em>
</p>

<p align="center">
  <img src="docs/README_PNG/UI_History.png" alt="履歴 — 音声認識ログ" width="500">
  <br>
  <em>検索可能な音声認識履歴。</em>
</p>

---

## 機能

- ✅ **グローバルホットキー** — 右Option長押しで録音、離すと音声認識（短押しでトグルモード）
- ✅ **オンデバイス音声認識** — Qwen3-ASRモデル、クラウド通信ゼロ、52言語自動検出
- ✅ **ASRモデル選択** — 0.6B（8bit、約1GB）、1.7B（4bit、約2.1GB）、1.7B（8bit、約2.3GB）を切り替え
- ✅ **LLMテキスト処理** — Qwen3-4B-Instruct-2507-4bitによるオプショナルなオンデバイス後処理
- ✅ **処理プリセット** — 「誤字修正」、「箇条書き」、または完全カスタムプロンプト
- ✅ **フローティングオーバーレイ** — 録音中のアニメーション波形インジケーター
- ✅ **ホットワード辞書** — カスタム用語を追加して認識精度を向上
- ✅ **音声認識履歴** — 過去の音声認識結果の表示、コピー、管理
- ✅ **メニューバー常駐** — Dockアイコンなしでバックグラウンド実行
- ✅ **プライバシー重視** — すべての処理がMac内で完結、デバイス外への送信なし

## 要件

- macOS 26.0+（Tahoe）
- Apple Silicon（M1以降）
- Xcode 26+ / Command Line Tools（Swift 6.2）
- **Metal Toolchain**（[Metal Toolchainセットアップ](#metal-toolchainセットアップ)を参照）

## Metal Toolchainセットアップ

Xcode 26以降、**Metal Toolchainはバンドルされなくなり**、別途インストールが必要です。VibingSpeechはMLX Swiftに依存しており、ビルド時にMetalシェーダーをコンパイルします。

**Xcode UIからのインストール:**

1. Xcode → 設定 → コンポーネントを開く
2. 「その他のコンポーネント」の下で**Metal Toolchain**を見つける
3. **取得**をクリック

**コマンドラインからのインストール:**

```bash
xcodebuild -downloadComponent metalToolchain
```

確認:

```bash
xcrun metal --version
# 期待値: metal version 32.x.x
```

> **注意:** ダウンロード後にツールチェーンが登録されない場合、以下を試してください:
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

スタンドアロンの`.app`バンドルを作成するには:

```bash
make app
open VibingSpeech.app

# または/Applicationsにインストール
cp -r VibingSpeech.app /Applications/
```

初回起動時、選択されたASRモデル（デフォルト0.6Bで約1GB）が自動ダウンロードされます。テキスト処理が有効の場合、Qwen3-4B-Instructモデル（約2.5GB）もダウンロードされます。

## 権限

VibingSpeechは2つの権限が必要です:

1. **アクセシビリティ** — グローバルホットキー検出とテキスト挿入のため
2. **マイク** — 音声録音のため

初回起動時にプロンプトが表示されます。後で有効にする場合: システム設定 → プライバシーとセキュリティ。

## 使用方法

1. アプリを起動 — メニューバーにマイクアイコンが表示されます
2. **長押しモード:** 話している間右Optionを押し続け、終了時に離す
3. **トグルモード:** 右Optionを短押しして開始、再度押して停止
4. **キャンセル:** 録音中いつでもEscを押す
5. メニューバーアイコンをクリック → 「ウィンドウを表示」で設定、ホットワード、履歴にアクセス

## ASRモデル選択

| モデル | ダウンロード | メモリ | 最適用途 |
|---|---|---|---|
| Qwen3-ASR 0.6B (8bit) | 約1.0GB | 約1.5GB | 一般用途、高速起動 |
| Qwen3-ASR 1.7B (4bit) | 約2.1GB | 約3.5GB | 複雑な音声、高精度 |
| Qwen3-ASR 1.7B (8bit) | 約2.3GB | 約4.0GB | 最高精度、特に日本語 |


## テキスト処理（LLM）

有効時、音声認識されたテキストは貼り付け前にオンデバイスLLMで後処理されます。**無効時はLLMは読み込まれません** — 追加メモリなし、追加遅延なし。

**モデル:** [Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) (約2.5GBダウンロード、約3.5GBメモリ)

| プリセット | 機能 |
|---|---|
| **誤字修正** | 意味を保持しながらスペル、誤字、文法を修正 |
| **箇条書き** | テキストを構造化された箇条書きリストに再フォーマット |
| **カスタム** | 任意の処理タスクにユーザー定義システムプロンプトを適用 |

**処理フロー:** 録音 → 音声認識（ASR）→ 言語検出 → 処理（LLM）→ 貼り付け

## トラブルシューティング

### Metalシェーダービルドが失敗する

```bash
xcodebuild -downloadComponent metalToolchain
```

インストール後も`xcrun metal`が失敗する場合、ターミナルを再起動するか正しいXcodeを選択してください:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### 実行時に`Failed to load the default metallib`エラー

```bash
make metallib
```

### グローバルホットキーが動作しない

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
├── TextProcessing/   # LLMテキスト処理（mlx-swift-lm経由でQwen3-4B）
├── Persistence/      # UserDefaults設定、JSON履歴/ホットワード
├── Views/            # メインウィンドウタブ、フローティングオーバーレイ
├── Models/           # データモデル、プリセット
└── Utilities/        # 権限、音声フィードバック、アーキテクチャチェック
```

## 依存関係

| パッケージ | バージョン | 用途 |
|---|---|---|
| [speech-swift](https://github.com/soniqo/speech-swift) | ≥ 0.0.9 | Qwen3-ASR音声認識 |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 2.31.3 | テキスト処理用LLM推論 |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.x | MLX配列フレームワーク（共有） |

## クレジット

- **[speech-swift](https://github.com/soniqo/speech-swift)** (Apache 2.0) — Qwen3-ASR Swiftラッパー
- **[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)** (MIT) — LLM推論フレームワーク
- **[Qwen3-ASR](https://huggingface.co/collections/aufklarer/qwen3-asr-mlx)** — Alibaba Cloud
- **[Qwen3-4B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507)** — Alibaba Cloud
- **[MLX Swift](https://github.com/ml-explore/mlx-swift)** — Apple Machine Learning Explore

## ライセンス

[MIT](LICENSE)

このプロジェクトは、それぞれ独自のライセンスの下で配布されているサードパーティライブラリに依存しています。このアプリケーションをビルドおよび配布する際は、すべての依存関係のそれぞれのライセンス（例：speech-swiftのApache 2.0）に準拠してください。詳細については、各ライブラリのリポジトリを参照してください。
