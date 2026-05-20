<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# VibingSpeech

VibingSpeech は、Apple Silicon Mac 向けのネイティブ macOS 音声入力ユーティリティです。メニューバー常駐アプリとして動作し、グローバルホットキーで録音を開始し、Qwen3-ASR によってローカルで音声をテキストに変換します。オプションでテキストを整形し、システムペーストボードを介して最前面のアプリに結果を貼り付けます。

## 目次

- [プレビュー](#プレビュー)
- [機能](#機能)
- [技術スタック](#技術スタック)
- [動作環境](#動作環境)
- [ビルドと実行](#ビルドと実行)
- [使い方](#使い方)
- [テスト](#テスト)
- [アーカイブ](#アーカイブ)
- [プロジェクト構成](#プロジェクト構成)
- [権限とプライバシー](#権限とプライバシー)
- [トラブルシューティング](#トラブルシューティング)
- [ライセンス](#ライセンス)

## プレビュー

<img src="githubreadme/ui-main.png" alt="VibingSpeech ホーム画面" width="480">

<img src="githubreadme/ui-hotwords.png" alt="VibingSpeech ホットワード画面" width="480">

<img src="githubreadme/ui-history.png" alt="VibingSpeech 履歴画面" width="480">

## 機能

- 短押しトグルモードと長押しホールドモードに対応したグローバル録音ホットキー。
- リアルタイムの音声レベルフィードバックと文字起こし状態を表示するフローティング録音オーバーレイ。
- Qwen3-ASR 0.6B および 1.7B MLX バリアントに対応したローカル ASR モデル選択。
- タイポ修正、箇条書き、またはカスタムプロンプトに対応したオプションのローカルテキスト整形プリセット。
- 名前、専門用語、固有名詞向けのローカルホットワードリスト。
- 保持期間設定、検索、コピー、削除、全消去アクションを備えたローカル文字起こし履歴。
- クリップボード復元機能付きで、アクティブなアプリへ安全にテキストを挿入するペーストボード対応機能。
- Dock アイコンなしのメニューバーライフサイクル。
- 起動時の Apple Silicon チェック機能。

## 技術スタック

- macOS アプリ、メニューバーアイテム、録音オーバーレイに SwiftUI および AppKit を使用。
- マイク入力と音声変換に AVFoundation を使用。
- グローバルホットキーおよびペースト操作のシミュレーションに Carbon と Core Graphics イベントタップを使用。
- Qwen3-ASR と音声サポートに `speech-swift` `0.0.15` を使用。
- `mlx-swift` `0.31.3` および Xcode で解決される Swift パッケージ依存関係。
- ローカルの履歴およびホットワード永続化に Application Support 内の JSON ファイルを使用。

## 動作環境

- Apple Silicon Mac。
- macOS 26.0 以降。
- Xcode 26.5 以降。
- マイクの権限。
- グローバルホットキーおよびアプリ間ペースト操作のためのアクセシビリティ権限。

## ビルドと実行

リポジトリルートからプロジェクトスクリプトを使用します：

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

Xcode プロジェクトが主要なビルドパスです。このアプリでは SwiftPM のみを使用したリリースビルドは意図的に使用していません。

## 使い方

1. VibingSpeech を起動します。
2. macOS がプロンプトを表示したら、マイクへのアクセスを許可します。
3. システム設定 > プライバシーとセキュリティ > アクセシビリティ で VibingSpeech を有効にします。
4. ホーム画面から録音ホットキー、言語モード、ASR モデル、マイク、履歴保持期間を選択します。
5. 任意のアプリで録音ホットキーを押します。キーを離すか再度押すと停止し、VibingSpeech が文字起こしを行い最終テキストを貼り付けます。

デフォルトのホットキーは右 Option キーです。Escape キーでアクティブな録音をキャンセルできます。

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

現在のテストは、モデルメタデータ、言語正規化、単語数カウント、テキスト整形、短い音声の ASR ガード処理、設定の永続化、履歴保持、破損した履歴の復元、ホットワードの検証、ペーストボードの復元をカバーしています。

## アーカイブ

アプリが `speech-swift` に依存している間は、Xcode GUI の「アーカイブ」ボタンを使用しないでください。リリースパッケージのビルドで `SpeechVAD` が x86_64 向けにコンパイルされ、`Float16` でエラーが発生する場合があります。

代わりにアーカイブスクリプトを使用してください：

```sh
./script/archive.sh
```

スクリプトは以下を生成します：

- `build/VibingSpeech.xcarchive`
- `build/VibingSpeech.app`

アーカイブのワークフローでは `ARCHS=arm64` を指定し、Apple Silicon 専用のアプリを生成します。

## プロジェクト構成

```text
VibingSpeech/
├── VibingSpeech.xcodeproj
├── VibingSpeech/
│   ├── App/              # アプリのエントリポイントとコーディネーター
│   ├── Core/             # 共有アプリの列挙型とヘルパー
│   ├── Models/           # ドメインモデル
│   ├── Persistence/      # 設定、履歴、ホットワードストア
│   ├── Resources/        # Info.plist とアセットカタログ
│   ├── Services/         # ホットキー、音声、ASR、テキスト挿入、権限
│   ├── Support/          # フォーマットヘルパー
│   └── Views/            # SwiftUI ビューとオーバーレイパネル
├── VibingSpeechTests/
├── VibingSpeechUITests/
├── docs/
└── script/
```

## 権限とプライバシー

VibingSpeech は録音のためにマイクへのアクセスが必要です。グローバルホットキーおよび最前面のアプリへのテキスト挿入には、アクセシビリティ権限が必要です。

音声サンプル、ホットワード、設定、および文字起こし履歴はローカルに保存されます。初回使用時に ASR モデルを Hugging Face からダウンロードする際には、ネットワークアクセスが発生します。

## トラブルシューティング

ホットキーが機能しない場合は、システム設定 > プライバシーとセキュリティ > アクセシビリティ で VibingSpeech を有効にし、アプリ内の「ホットキー設定を再試行」を使用してください。

録音が開始してすぐに停止する場合、VibingSpeech は ASR に対して短すぎる音声を `speech-swift` に送信せずに破棄します。

Xcode の GUI からアーカイブが失敗する場合は、arm64 専用のパッケージビルド設定が適用されるよう、Terminal から `./script/archive.sh` を使用してください。

## ライセンス

VibingSpeech は MIT ライセンスの下で提供されています。[LICENSE](LICENSE) を参照してください。