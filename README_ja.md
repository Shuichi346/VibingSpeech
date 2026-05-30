<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# VibingSpeech

VibingSpeech は、Apple Silicon Mac 向けのネイティブ macOS 音声入力ユーティリティです。メニューバー常駐アプリとして動作し、グローバルホットキーで録音を開始し、Qwen3-ASR によりローカルで音声をテキストに変換します。録音中にオプションのライブ文字起こし表示が可能で、必要に応じてローカルの Qwen3 LLM で最終テキストを整形し、システムのペーストボードを通じて最前面のアプリに結果を貼り付けます。

## 目次

- [プレビュー](#preview)
- [機能](#features)
- [技術スタック](#tech-stack)
- [動作環境](#requirements)
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

- グローバル録音ホットキー：短押しでトグルモード、長押しでホールドモード。
- フローティング録音オーバーレイ：リアルタイムの音量フィードバックと文字起こし状態の表示。
- オプションのライブ文字起こしモード：録音中に別のオーバーレイで ASR の中間テキストと確定テキストを表示しますが、貼り付けは録音停止後に一度だけ行います。
- Qwen3-ASR 0.6B、1.7B 4-bit、1.7B 8-bit MLX バリアントのローカル ASR モデル選択。
- `mlx-community/Qwen3-4B-Instruct-2507-4bit` を利用した、誤字修正・箇条書き整形・カスタムプロンプトによるオプションのローカルテキスト処理（LLM）。
- 録音エンジンに指定した入力デバイスを適用する Core Audio マイク選択（システムデフォルトに依存しない）。
- 人名・用語・固有名詞のローカルホットワードマネージャー。
- 保持期間設定・検索・コピー・削除・全削除・元の ASR テキストのコピーが可能なローカル文字起こし履歴。
- アプリ全体の外観モード、ログイン時に起動、アイドル時のモデル自動アンロード設定。
- クリップボード復元機能付きのペーストボード安全なテキスト挿入。
- Dock アイコンなしのメニューバーライフサイクル。
- 起動時の Apple Silicon チェック。

## 技術スタック

- macOS アプリ、メニューバーアイテム、録音オーバーレイに SwiftUI と AppKit を使用。
- マイク入力、デバイス選択、音声変換に AVFoundation と Core Audio を使用。
- グローバルホットキーと擬似ペーストに Carbon と Core Graphics イベントタップを使用。
- Qwen3-ASR、音声サポート、`SpeechVAD` ベースのライブ文字起こしに `speech-swift` `0.0.15` を使用。
- ローカル Qwen3 テキスト処理に `mlx-swift` `0.31.3`・`swift-huggingface` `0.9.0`・`swift-transformers` `1.3.0` を含む `mlx-swift-lm` `3.31.3` を使用。
- ログイン時起動に ServiceManagement を使用。
- ローカルの履歴とホットワードの永続化に Application Support の JSON ファイルを使用。

## 動作環境

- Apple Silicon Mac。
- macOS 26.0 以降。
- Xcode 26.5 以降。
- Metal Toolchain。Xcode の設定 → Components タブ → Other Components → Metal Toolchain。
- マイクのアクセス許可。
- グローバルホットキーとアプリ間ペーストのためのアクセシビリティ権限。

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

Xcode プロジェクトが主要なビルドパスです。このアプリでは SwiftPM のみのリリースビルドは意図的に使用しません。

## 使い方

1. VibingSpeech を起動します。
2. macOS からマイクアクセスを求められたら許可します。
3. システム設定 > プライバシーとセキュリティ > アクセシビリティ で VibingSpeech を有効にします。
4. ホーム画面から録音ホットキー、マイク、テキスト処理モード、言語モード、ASR モデルを選択します。
5. 任意のアプリで録音ホットキーを押します。離すか再度押すと録音が停止し、VibingSpeech が文字起こしを行って最終テキストを貼り付けます。

デフォルトのホットキーは右 Option キーです。Escape キーで録音中の操作をキャンセルできます。

ライブ文字起こしが有効な場合、録音中にコンパクトな録音オーバーレイの上に ASR の中間テキストと確定テキストが表示されます。ターゲットアプリへのリアルタイムの分割挿入は行われず、挿入は録音停止後、完全なトランスクリプトに対してオプションのテキスト処理が完了してから一度だけ行われます。

ホットワードで人名やドメイン用語のローカルリストを管理し、履歴で保存した音声入力の検索やコピーを行い、その他で外観・ログイン時起動・モデル自動アンロードのタイミングを設定できます。

## テスト

アプリのユニットテストを実行するには：

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

現在のテストは、モデルのメタデータ、プロンプト生成、言語の正規化、単語数カウント、ライブ文字起こしバッファリング、短い音声の ASR ガード、設定の永続化、モデルアンロードの遅延範囲、履歴の保持、破損した履歴の復元、ホットワードのバリデーション、ペーストボードの復元をカバーしています。

## アーカイブ

アプリが `speech-swift` に依存している間は、Xcode GUI のアーカイブボタンを使用しないでください。リリースパッケージのビルドで `SpeechVAD` が x86_64 用にコンパイルされ、`Float16` でエラーが発生する場合があります。

代わりにアーカイブスクリプトを使用してください：

```sh
./script/archive.sh
```

このスクリプトは以下を生成します：

- `build/VibingSpeech.xcarchive`
- `build/VibingSpeech.app`

アーカイブワークフローは `ARCHS=arm64` を渡し、アプリバンドルの前にネストされたコードに署名し、`VibingSpeech/Resources/VibingSpeech.entitlements` を保持し、Hardened Runtime を有効にし、ランタイムフラグの存在を確認して、Apple Silicon 専用アプリを生成します。

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

VibingSpeech は録音のためにマイクへのアクセスが必要です。グローバルホットキーと最前面アプリへのテキスト挿入のためにアクセシビリティ権限が必要です。

音声はローカルで処理されます。ホットワード、設定、文字起こし履歴はデバイス上に保存されます。ASR またはテキスト処理モデルを初回使用時に Hugging Face からダウンロードする際にネットワークアクセスが必要です。

## トラブルシューティング

ホットキーが機能しない場合は、システム設定 > プライバシーとセキュリティ > アクセシビリティ で VibingSpeech を有効にしてから、アプリ内の「ホットキー設定を再試行」を使用してください。

表示されているマイクを変更しても録音が別のデバイスを使用しているように見える場合は、アクティブな録音を停止して新しい録音を開始してください。VibingSpeech は録音セッション開始時に選択した Core Audio デバイスを適用し、そのデバイスが利用できないか起動できない場合はエラーを報告します。

録音がすぐに開始して停止する場合、VibingSpeech は ASR に対して短すぎる音声を `speech-swift` に送らずに破棄します。

Xcode の GUI からアーカイブが失敗する場合は、arm64 専用のパッケージビルド設定が適用されるよう Terminal から `./script/archive.sh` を使用してください。

## ライセンス

VibingSpeech は MIT ライセンスのもとで提供されています。[LICENSE](LICENSE) を参照してください。

使用しているライブラリおよび LLM モデルの個別ライセンスも必ずご確認ください。