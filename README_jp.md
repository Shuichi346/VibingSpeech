# VibingSpeech

完全にオンデバイスのmacOS音声入力アプリ。グローバルホットキー → 録音 → 転写（Qwen3-ASR） → カーソル位置にテキスト貼り付け。Apple Silicon専用。

## 機能

- ✅ **グローバルホットキー:** 右Optionキーを押しながら録音、離すと転写（短押しでトグルモード）
- ✅ **オンデバイス転写:** Qwen3-ASRモデルを使用、クラウド呼び出しなしで完全にローカルで実行
- ✅ **モデル選択:** 0.6B（8ビット、約1GB）と1.7B（4ビット、約2.1GB）モデルから選択
- ✅ **フローティングオーバーレイ:** 録音中のアニメーション付きマイクインジケーター
- ✅ **ホットワード辞書:** カスタム用語を追加して認識精度を向上
- ✅ **転写履歴:** 設定可能な保持期間で過去の転写を表示・管理
- ✅ **52言語対応:** 自動言語検出
- ✅ **テキスト修正:** よりクリーンな出力のための軽量後処理
- ✅ **メニューバー常駐:** バックグラウンドで動作、Dockアイコンなし
- ✅ **アクセシビリティ対応:** テキスト入力を受け付けるあらゆるアプリケーションで動作

## 要件

- macOS 26.0+（Tahoe）
- Apple Silicon（M1以降）
- Xcode 26+ / Command Line Tools（Swift 6.2付き）
- **Metal Toolchain**（下記の[Metal Toolchain セットアップ](#metal-toolchain-セットアップ)を参照）

## Metal Toolchain セットアップ

Xcode 26以降、**Metal ToolchainはXcodeにバンドルされなくなり**、別途インストールする必要があります。VibingSpeechはMLX Swiftに依存しており、ビルド時にMetalシェーダーをコンパイルする必要があります。Metal Toolchainなしでは、ビルドが失敗します。

**Xcode UIからインストール:**

1. Xcode → 設定 → コンポーネントを開く
2. 「その他のコンポーネント」で**Metal Toolchain**を見つける
3. **取得**をクリックしてダウンロード・インストール

**コマンドラインからインストール:**

```bash
xcodebuild -downloadComponent metalToolchain
```

インストールの確認:

```bash
xcrun metal --version
```

バージョン番号（例：`metal version 32.x.x`）が表示されれば、ツールチェーンの準備完了です。

> **注意:** 一部のXcode 26バージョンでは、ダウンロード後にツールチェーンが正しく登録されない場合があります。インストール後もエラーが出る場合は、以下を試してください:
> ```bash
> xcodebuild -downloadComponent metalToolchain -exportPath /tmp/MetalExport/
> xcodebuild -importComponent metalToolchain -importPath /tmp/MetalExport/*.exportedBundle
> ```

## ビルド＆実行

```bash
git clone https://github.com/Shuichi346/VibingSpeech.git
cd VibingSpeech
make build
make run
```

`make build`はSwiftパッケージをコンパイルし、その後MLX Metalシェーダーライブラリ（`mlx.metallib`）をビルドします。シェーダービルドはキャッシュされ、ソースファイルが変更された場合のみ再コンパイルされます。

スタンドアロンの`.app`バンドルを作成するには:

```bash
make app
open VibingSpeech.app

# または/Applicationsにインストール
cp -r VibingSpeech.app /Applications/
```

初回起動時に、選択したASRモデル（デフォルトの0.6Bモデルで約1GB）が自動的にダウンロードされます。

## 権限

VibingSpeechには2つの権限が必要です:

1. **アクセシビリティ権限:** グローバルホットキー検出とテキスト挿入に必要
2. **マイク権限:** オーディオ録音に必要

初回起動時にこれらの権限を付与するよう促されます。プロンプトを見逃した場合は、後でシステム設定 → プライバシーとセキュリティで有効にできます。

## 使用方法

1. アプリを起動 — メニューバーにマイクアイコンが表示されます
2. **ホールドモード:** 話しながら右Optionキーを押し続け、終了時に離す
3. **トグルモード:** 右Optionキーを短押しして録音開始、再度押して停止
4. **録音キャンセル:** 録音中はいつでもEscキーを押す
5. メニューバーアイコンをクリック → 「ウィンドウを表示」で設定、ホットワード、履歴にアクセス

## モデル選択

| モデル | サイズ | メモリ | 精度 |
|---|---|---|---|
| Qwen3-ASR 0.6B（8ビット） | 約1.0 GB | 約1.5 GB | 一般用途に適している |
| Qwen3-ASR 1.7B（4ビット） | 約2.1 GB | 約3.5 GB | 複雑な音声でより高い精度 |

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

これによりMLX Swift依存関係の`.metal`シェーダーソースがコンパイルされ、バイナリの隣に`mlx.metallib`が配置されます。

### グローバルホットキーが動作しない

システム設定 → プライバシーとセキュリティ → アクセシビリティでアクセシビリティ権限が有効になっていることを確認してください。

### 開発者が確認できないためアプリを開けない

```bash
xattr -cr VibingSpeech.app
```

## アーキテクチャ

```
Sources/VibingSpeech/
├── App/             # @main, AppDelegate, AppState（中央状態）
├── Audio/           # AudioCaptureManager, TranscriptionEngine
├── HotkeyManager/   # GlobalHotkeyManager（CGEventTap）
├── TextInsertion/   # クリップボード + Cmd+Vシミュレーション
├── Persistence/     # UserDefaults設定、JSON履歴/ホットワード
├── Views/           # メインウィンドウタブ、フローティングオーバーレイ
├── Models/          # データモデル
└── Utilities/       # 権限、音声フィードバック、アーキテクチャチェック
```

## クレジット

- **speech-swift**（Apache 2.0） — https://github.com/soniqo/speech-swift
- **Qwen3-ASR** — Alibaba Cloud
- **MLX Swift** — Apple Machine Learning Explore

## ライセンス

MIT
