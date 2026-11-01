# no-more-gobaku

英数モードのまま日本語をローマ字で打ってしまったとき、Enter を押した時点でそれを検出し、
かな入力に切り替えて打ち直す macOS 用の常駐プログラムです。

```
英数モードで "kyouhaiitenkidesune" と打って Enter
  → Enter は送信されず、文字が消えて日本語入力に切り替わり、
    「きょうはいいてんきですね」が変換待ちの状態になる
```

チャット欄で英数モードのまま Enter を押してしまい、誤送信する問題の対策も兼ねています。
`repositoryha` のような「英単語＋助詞」は、助詞の部分だけを打ち直して「repositoryは」にします。

## インストール

macOS 13 以降と、Swift をビルドできる環境（Command Line Tools）が必要です。
入っていなければ次で入れます。

```bash
xcode-select --install
```

clone して `install.sh` を実行します。ビルド、テスト、`~/.local/bin` への配置、
ログイン時に起動する LaunchAgent の設定までを行います。

```bash
git clone https://github.com/aberyotaro/no-more-gobaku.git
```

```bash
cd no-more-gobaku && scripts/install.sh
```

初回は、アクセシビリティの許可がないため起動できずに終わります。
システム設定 > プライバシーとセキュリティ > アクセシビリティ で no-more-gobaku をオンにしてください。
一覧になければ「＋」を押し、⌘+Shift+G で `~/.local/bin/no-more-gobaku` を指定して追加します。
許可したら次で起動します。

```bash
launchctl kickstart -k gui/$(id -u)/local.no-more-gobaku
```

### 更新

```bash
git pull && scripts/install.sh
```

更新でバイナリが変わると、macOS は別のプログラムとみなし、アクセシビリティの許可が外れます
（`install.sh` がその旨を表示します。変わらなければ入れ替えないので、許可は外れません）。
そのときは、アクセシビリティで no-more-gobaku を「−」で削除し、「＋」で追加し直してから、上の `launchctl kickstart` を実行してください。

キーチェーンにコード署名用の証明書 `no-more-gobaku-dev` を作っておくと、`install.sh` がそれで署名するので、
更新しても許可が外れなくなります。キーチェーンアクセス > 証明書アシスタント > 証明書を作成 で、
固有名の種類を「自己署名ルート」、証明書のタイプを「コード署名」にして作ります。

### アンインストール

```bash
launchctl bootout gui/$(id -u)/local.no-more-gobaku
```

```bash
rm ~/.local/bin/no-more-gobaku ~/Library/LaunchAgents/local.no-more-gobaku.plist ~/Library/Logs/no-more-gobaku.log
```

アクセシビリティの一覧からも「−」で削除してください。

## プライバシー

キー入力を監視するプログラムなので、扱うデータを明記します。

- 打った文字は、Enter で判定するまでのあいだ、メモリ上に最大 256 文字だけ保持します。
  クリック、矢印キー、アプリの切り替え、30 秒の無入力で捨てます。
- 打った文字をファイルに保存したり、ネットワークへ送ったりはしません。
- ターミナルなど対象外のアプリと、パスワード欄（Secure Input）では文字を保持しません。
- `-v` を付けて起動したときだけ、変換した文字列をログに出力します。

## 仕組み

1. CGEventTap でキー入力を監視し、英数モード（ABC などの配列と、日本語入力の英数モード）で打った文字を溜める
2. Enter（Shift なし）を押したら、末尾の文字列を判定する
   - 全体をローマ字として解釈できる（スペース区切りの複数語も可）
   - 英単語ではない（`/usr/share/dict/words` と組み込みの語、複合語、`-tion`/`-sion`）
   - 4 文字以上
3. アクセシビリティ API で入力欄を読み、消す予定の文字列がカーソルの直前にあって選択範囲がないことを確かめる。
   一致しなければ何もしない。入力欄を読めないアプリでは確認せずに進む
4. Enter を握りつぶし、Backspace で消して、かなキーで日本語入力に切り替えてから同じキーを打ち直す。
   打ち直しが終わるまでに押されたキーは溜めておき、打ち直しのあとに同じ順で送る

### 誤って変換されたとき

変換待ちの状態で **F10** を押すと半角英数に戻せます（ことえり・Google 日本語入力とも）。
そのあと Enter で確定してください。

ローマ字のまま送りたいときは、Enter の前に ← → でカーソルを動かします。溜めた文字が捨てられ、判定されません。

## コマンド

```bash
no-more-gobaku check kyouhaiitenkidesune "go home" database
```

判定だけを試します。引数がなければ標準入力を 1 行ずつ判定します。

```bash
no-more-gobaku sources
```

有効な入力ソースと、今の入力ソースを英数とみなすかを表示します。

```bash
no-more-gobaku probe 5
```

5 秒後に前面にある入力欄を読めるかを調べます（文字数とカーソル位置だけを表示します）。
許可を持つのは no-more-gobaku 本体なので、ターミナルから実行すると読めないことがあります。

```bash
no-more-gobaku run -v
```

常駐します。`-v` を付けると、変換した文字列と、変換しなかった理由を表示します。

## 設定

`~/.config/no-more-gobaku/config.json`（任意。書いた項目だけが上書きされます）

```json
{
  "minLetters": 4,
  "minJapaneseRatio": 0.5,
  "switchDelayMs": 60,
  "enabledApps": ["com.anthropic.claudefordesktop"],
  "disabledApps": ["com.apple.Terminal"],
  "japaneseInputSourceID": "com.google.inputmethod.Japanese.base"
}
```

| 項目 | 意味 |
|---|---|
| `minLetters` | 変換の対象とする最小の文字数 |
| `minJapaneseRatio` | 英単語でない語が占める文字数の割合の下限 |
| `switchDelayMs` | 日本語入力に切り替えてから打ち直すまでの待ち時間。打ち直しが英字のまま入るなら増やす |
| `enabledApps` | 指定するとそのアプリだけで動く（bundle ID）。空ならすべて |
| `disabledApps` | 動かさないアプリ。省略時は主要なターミナルが入っている |
| `japaneseInputSourceID` | この入力ソースが有効なときだけ変換する。省略時は何らかのかな入力があればよい。切り替え先はかなキーで決まる |

アプリの bundle ID は `osascript -e 'id of app "Claude"'` で調べられます。

変換してほしくない語は `~/.config/no-more-gobaku/words.txt` に 1 行 1 語で書きます（`#` はコメント）。

## 開発

```bash
swift build -c release
```

```bash
swift run -c release selftest
```

Command Line Tools だけでは XCTest と swift-testing が使えないため、テストは実行形式（`selftest`）にしています。

## 既知の制限

- 英単語 2 つに分けられる日本語は英語とみなされる（例: `kanamono` = kana + mono）
- 辞書に載っている語と同じ綴りの日本語は変換されない（例: `same`, `made`, `sake`）
- 文字を溜め始める前（クリックした位置より前）の文字は対象にならない
- l/x による小書き文字、v 行、`th`/`dh` などの綴りは、英文の誤検出を避けるため受け付けない
- 打ち直しは US 配列のキーコードで行うため、Dvorak などの配列では正しく打ち直せない
- 大文字を含むローマ字（Caps Lock 中を含む）は、略語や人名との区別がつかないため変換しない

## ライセンス

MIT
