<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# VibingSpeech

VibingSpeech は、Apple Silicon Mac 向けのネイティブ macOS 音声入力ユーティリティです。メニューバー常駐アプリとして動作し、グローバルホットキーで録音を開始し、Qwen3-ASR を使用してローカルで音声を文字起こしし、必要に応じてテキストを整形したうえで、システムのペーストボードを通じて最前面のアプリに結果を貼り付けます。

## 目次

- [プレビュー](#preview)
- [機能](#features)
- [技術スタック](#tech-stack)
- [要件](#requirements)
- [ビルドと実行](#build-and-run)
- [使い方](#usage)
- [テスト](#testing)
- [アーカイブ](#archive)
- [プロジェクト構成](#project-structure)
- [権限とプライバシー](#permissions-and-privacy)
- [トラブルシューティング](#troubleshooting)
- [ライセンス](#license)

## プレビュー

<img src="githubreadme/ui-main.png" alt="VibingSpeech ホーム画面" width="480">

<img src="githubreadme/ui-hotwords.png" alt="VibingSpeech ホットワード画面" width="480">

<img src="githubreadme/ui-history.png" alt="VibingSpeech 履歴画面" width="480">

<img src="githubreadme/ui-other.png" alt="VibingSpeech その他の設定画面" width="480">

## 機能

- 短押しトグルモードと長押しホールドモードに対応したグローバル録音ホットキー。
- リアルタイムの音量フィードバックと文字起こし状態を表示するフローティング録音オーバーレイ。
- Qwen3-ASR 0.6B、1.7B 4ビット、1.7B 8ビットの MLX バリアントを対象としたローカル ASR モデルの選択。
- 誤字修正、箇条書き整形、またはカスタムプロンプトに対応したオプションのローカルテキスト処理（LLM）。
- 氏名、専門用語、固有名詞向けのローカルホットワードリスト。
- 保持設定、検索、コピー、削除、全消去、元の ASR テキストのコピー操作に対応したローカル文字起こし履歴。
- アプリ全体の外観モード、ログイン時起動、アイドル時のモデル自動アンロード設定。
- クリップボードを復元しながら、アクティブなアプリにテキストを安全に挿入するペーストボード対応の挿入機能。
- Dock アイコンなしのメニューバーライフサイクル。
- 起動時の Apple Silicon ガード。

## 技術スタック

- macOS アプリ、メニューバーアイテム、録音オーバーレイ向けの SwiftUI および AppKit。
- マイク入力と音声変換向けの AVFoundation。
- グローバルホットキーと擬似ペースト操作向けの Carbon および Core Graphics イベントタップ。
- Qwen3-ASR および音声サポート向けの `speech-swift` `0.0.15`。
- ローカル Qwen3 テキスト処理向けの `mlx-swift` `0.31.3` を含む `mlx-swift-lm` `3.31.3`。
- ローカルの履歴およびホットワードの永続化向けの Application Support 内 JSON ファイル。

## 要件

- Apple Silicon Mac。
- macOS 26.0 以降。
- Xcode 26.5 以降。
- Metalツールチェーン。Xcode Settings → Componentsタブ → Other Components → Metal Toolchain。
- マイクの権限。
- グローバルホットキーおよびアプリをまたいだ貼り付けのためのアクセシビリティ権限。

## ビルドと実行

リポジトリのルートからプロジェクトスクリプトを使用してください：

```sh
./script/build_and_run.sh --verify
```

このスクリプトは `VibingSpeech.xcodeproj` をビルドし、Debug アプリバンドルを起動して、`VibingSpeech` プロセスが実行中であることを確認します。

その他のサポートされているモード：

```sh
./script/build_and_run.sh
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

Xcode プロジェクトが主要なビルドパスです。このアプリでは SwiftPM のみによるリリースビルドは意図的に使用していません。

## 使い方

1. VibingSpeech を起動します。
2. macOS からプロンプトが表示されたら、マイクのアクセスを許可します。
3. システム設定 > プライバシーとセキュリティ > アクセシビリティ で VibingSpeech を有効にします。
4. ホーム画面から録音ホットキー、マイク、テキスト処理モード、言語モード、ASR モデルを選択します。
5. 任意のアプリで録音ホットキーを押します。離すか再度押すと録音が停止し、VibingSpeech が最終テキストを文字起こしして貼り付けます。

デフォルトのホットキーは右 Option キーです。Escape キーで録音中の操作をキャンセルできます。

ホットワードを使用して氏名やドメイン用語の認識精度を向上させ、履歴を使用して保存された音声入力を検索またはコピーし、その他の設定で外観、ログイン時起動、モデルの自動アンロードタイミングを設定してください。

## テスト

以下のコマンドでアプリの単体テストを実行します：

```sh
xcodebuild -project VibingSpeech.xcodeproj \
  -scheme VibingSpeech \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:VibingSpeechTests \
  test
```

現在のテストは、モデルメタデータ、言語の正規化、単語数カウント、テキストクリーンアップ、短い音声の ASR ガード、設定の永続化、履歴の保持、破損した履歴の復旧、ホットワードの検証、ペーストボードの復元をカバーしています。

## アーカイブ

アプリが `speech-swift` に依存している間は、Xcode GUI のアーカイブボタンを使用しないでください。リリースパッケージのビルドで `SpeechVAD` が x86_64 向けにコンパイルされ、`Float16` でビルドが失敗する可能性があります。

代わりにアーカイブスクリプトを使用してください：

```sh
./script/archive.sh
```

スクリプトは以下を出力します：

- `build/VibingSpeech.xcarchive`
- `build/VibingSpeech.app`

アーカイブのワークフローは `ARCHS=arm64` を渡し、Apple Silicon 専用のアプリを生成します。

## プロジェクト構成

```text
VibingSpeech/
├── VibingSpeech.xcodeproj
├── VibingSpeech/
│   ├── App/              # アプリのエントリーポイントとコーディネーター
│   ├── Core/             # 共有アプリの列挙型とヘルパー
│   ├── Models/           # ドメインモデル
│   ├── Persistence/      # 設定、履歴、ホットワードのストア
│   ├── Resources/        # Info.plist とアセットカタログ
│   ├── Services/         # ホットキー、音声、ASR、テキスト挿入、権限
│   ├── Support/          # 整形ヘルパー
│   └── Views/            # SwiftUI ビューとオーバーレイパネル
├── VibingSpeechTests/
├── VibingSpeechUITests/
├── docs/
└── script/
```

## 権限とプライバシー

VibingSpeech は録音のためにマイクへのアクセスが必要です。グローバルホットキーおよび最前面のアプリへのテキスト挿入にはアクセシビリティ権限が必要です。

音声はローカルで処理されます。ホットワード、設定、文字起こし履歴はデバイス上に保存されます。ASR またはテキスト処理モデルを初回使用時に Hugging Face からダウンロードする際は、ネットワークアクセスが発生します。

## トラブルシューティング

ホットキーが機能しない場合は、システム設定 > プライバシーとセキュリティ > アクセシビリティ で VibingSpeech を有効にし、アプリ内の「ホットキー設定を再試行」を使用してください。

録音が開始してすぐに停止する場合、VibingSpeech は ASR に対して短すぎる音声を `speech-swift` に送信せず破棄します。

Xcode の GUI からアーカイブが失敗する場合は、ターミナルから `./script/archive.sh` を使用して、arm64 専用のパッケージビルド設定が適用されるようにしてください。

## ライセンス

VibingSpeech は MIT ライセンスのもとでライセンスされています。[LICENSE](LICENSE) を参照してください。

使用ライブラリやLLMモデルは個々のライセンスを確認してください。
