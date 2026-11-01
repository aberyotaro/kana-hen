# no-more-gobaku

英数モードのまま日本語をローマ字で打ってしまったとき、Enter を押した時点でそれを検出し、
かな入力に切り替えて打ち直す macOS 用の常駐プログラムです。

```
英数モードで "kyouhaiitenkidesune" と打って Enter
  → Enter は送信されず、文字が消えて日本語入力に切り替わり、
    「きょうはいいてんきですね」が変換待ちの状態になる
```

チャット欄で英数モードのまま Enter を押してしまい、誤送信する問題の対策も兼ねています。

## 仕組み

1. CGEventTap でキー入力を監視し、英数モードで打った文字を溜める
   （クリック、矢印キー、⌘/⌃/⌥ の組み合わせ、アプリの切り替えで破棄する）
2. Enter（Shift なし）を押したら、末尾の文字列を判定する
   - 全体をローマ字として解釈できる（スペース区切りの複数語も可）
   - 英単語ではない（`/usr/share/dict/words` と組み込みの語、複合語、`-tion`/`-sion`）
   - 4 文字以上
3. 日本語と判定したら Enter を握りつぶし、Backspace で消して、日本語入力に切り替えてから同じキーを打ち直す

パスワード欄（Secure Input が有効なとき）では動きません。

## ビルド

```bash
swift build -c release
```

```bash
swift run -c release selftest
```

## 使い方

まず判定だけを試せます。

```bash
.build/release/no-more-gobaku check kyouhaiitenkidesune "go home" database
```

常駐させるには次を実行します。初回はアクセシビリティの許可を求められるので、
システム設定 > プライバシーとセキュリティ > アクセシビリティ で、
実行しているアプリ（ターミナルなど）を許可してから再実行してください。

```bash
.build/release/no-more-gobaku run -v
```

`-v` を付けると、変換したときに内容を表示します（打ったキーそのものは記録しません）。

### 誤って変換されたとき

変換待ちの状態で **F10** を押すと半角英数に戻せます（ことえり・Google 日本語入力とも）。
そのあと Enter で確定してください。

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
| `switchDelayMs` | 入力ソースを切り替えてから打ち直すまでの待ち時間。打ち直しが英字のまま入るなら増やす |
| `enabledApps` | 指定するとそのアプリだけで動く（bundle ID）。空ならすべて |
| `disabledApps` | 動かさないアプリ。省略時は主要なターミナルが入っている |
| `japaneseInputSourceID` | 切り替え先。省略時は `no-more-gobaku sources` の `*` の先頭 |

アプリの bundle ID は `osascript -e 'id of app "Claude"'` で調べられます。

変換してほしくない語は `~/.config/no-more-gobaku/words.txt` に 1 行 1 語で書きます（`#` はコメント）。

## ログイン時に自動起動する

バイナリを `~/.local/bin` に置き、`~/Library/LaunchAgents/local.no-more-gobaku.plist` を作ります
（`/Users/you` は自分のホームディレクトリに置き換える）。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.no-more-gobaku</string>
  <key>ProgramArguments</key>
  <array><string>/Users/you/.local/bin/no-more-gobaku</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <!-- 許可がないときの正常終了で再起動を繰り返さないよう、クラッシュ時だけ再起動する -->
  <key>KeepAlive</key><dict><key>Crashed</key><true/></dict>
  <key>StandardOutPath</key><string>/Users/you/Library/Logs/no-more-gobaku.log</string>
  <key>StandardErrorPath</key><string>/Users/you/Library/Logs/no-more-gobaku.log</string>
</dict>
</plist>
```

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.no-more-gobaku.plist
```

アクセシビリティでは、ターミナルではなく `~/.local/bin/no-more-gobaku` そのものを許可してください。
バイナリを入れ替えたら、許可をやり直してから次で再起動します。

```bash
launchctl kickstart -k gui/$(id -u)/local.no-more-gobaku
```

## 既知の制限

- 英単語 2 つに分けられる日本語は英語とみなされる（例: `kanamono` = kana + mono）
- 辞書に載っている語と同じ綴りの日本語は変換されない（例: `same`, `made`, `sake`）
- 文字を溜め始める前（クリックした位置より前）の文字は対象にならない
- l/x による小書き文字、v 行、`th`/`dh` などの綴りは、英文の誤検出を避けるため受け付けない
