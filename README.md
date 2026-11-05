# kana-hen

英数モードで打ったローマ字を、Enter でかな入力に打ち直す macOS の常駐プログラムです。変換するとき、その Enter はアプリに届きません。

`kyouhaiitenkidesune` は変換待ちの「きょうはいいてんきですね」になります。英単語の直後の助詞は助詞以降だけを打ち直します。`repositoryha` は「repositoryは」、`repository ha` は「repository は」、`repository ha ugokanai` は「repository はうごかない」です。`to`・`no`・`he`・`ya` は英単語でもあるので、行がその語で終わるときは `GitHub`・`API`・`v2` のような技術用語の直後だけ変換します。`repository to` や `introduction to` は変換しません。`made` は辞書にあるので、`repository made` も `repositorymade` も変換しません。

ローマ字と英単語と助詞がつながった 1 語は、英単語だけをそのまま挟んで打ち直します。`korehatestwo` は「これは」「test」「を」で、「これはtestを」になります。英単語が 4 文字以上で、前半がローマ字として読めるときだけです。`korehatest` のように助詞がなければ変換しません。スペースで区切った `repository ni push` は、助詞 `ha`・`ga`・`wo`・`ni`・`de`・`mo` だけを打ち直し、「repository に push」になります。助詞の後ろがすべて英単語のときだけで、`repository to push` や `git push origin main` は変換しません。`repositorynipush` のようにつなげた形も変換しません。

打った文字はネットワークへ送りません。Enter で判定するまでメモリ上に最大 256 文字だけ持ち、`-v` で起動したときだけ変換結果をログに出します。

## 必要なもの

macOS 13 以降と、Swift をビルドできる環境（Command Line Tools）です。無ければ次で入れます。

```bash
xcode-select --install
```

## インストール

```bash
git clone https://github.com/aberyotaro/kana-hen.git
cd kana-hen
```

更新でバイナリが変わってもアクセシビリティの許可を残したいときは、先にコード署名用の証明書 `kanahen-dev` を作ります。キーチェーンアクセス > 証明書アシスタント > 証明書を作成 で、固有名の種類を「自己署名ルート」、証明書のタイプを「コード署名」にします。別の名前にするときは `KANAHEN_SIGN_IDENTITY` にその名前を入れます。

```bash
scripts/install.sh
```

ビルドとテストのあと、`~/.local/bin/kanahen` に置き、ログイン時に起動する LaunchAgent `local.kanahen` を登録して起動します。ログは `~/Library/Logs/kanahen.log` です。

初回は許可がないため起動できません。システム設定 > プライバシーとセキュリティ > アクセシビリティ で `~/.local/bin/kanahen` をオンにします。一覧になければ「＋」を押し、⌘+Shift+G でそのパスを指定します。入力監視を求められたら、同じバイナリをそこでも許可します。

許可したら次で起動します。

```bash
launchctl kickstart -k gui/$(id -u)/local.kanahen
```

更新は次です。

```bash
git pull && scripts/install.sh
```

証明書が無く ad-hoc 署名のままバイナリが変わると、許可が外れます。アクセシビリティの一覧から kanahen を「−」で削除し、「＋」で `~/.local/bin/kanahen` を追加し直してから、上の `launchctl kickstart` を実行します。

## アンインストール

```bash
scripts/uninstall.sh
```

読み込まれていれば `launchctl bootout gui/$(id -u)/local.kanahen` で止め、次を削除します。無いものは飛ばすので、何度実行してもよいです。

- `~/Library/LaunchAgents/local.kanahen.plist`
- `~/.local/bin/kanahen`
- `~/.config/kanahen`
- `~/Library/Logs/kanahen.log`

システム設定 > プライバシーとセキュリティ > アクセシビリティ から kanahen を「−」で削除します。入力監視に入っていれば、そこからも削除します。

## 使い方

インストール後はログインのたびに起動します。判定や調査は `~/.local/bin/kanahen` を直接実行します。

```bash
~/.local/bin/kanahen check kyouhaiitenkidesune "go home" database
```

引数がなければ標準入力を 1 行ずつ判定します。

```bash
~/.local/bin/kanahen sources
```

有効な入力ソースと、今の入力ソースを英数とみなすかを表示します。

```bash
~/.local/bin/kanahen probe 5
```

5 秒後に前面の入力欄が読めるかを調べます（文字数とカーソル位置だけ）。許可を持つのは常駐している kanahen なので、ターミナルからだと読めないことがあります。

```bash
~/.local/bin/kanahen run -v
```

常駐します。`-v` を付けると、変換した文字列と、変換しなかった理由を出します。

## 設定

`~/.config/kanahen/config.json` に書いた項目だけが既定値を上書きします。

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
| `minLetters` | 変換する最小文字数。既定は 4 |
| `minJapaneseRatio` | 英単語でない語が占める文字数の割合の下限。既定は 0.5 |
| `switchDelayMs` | かな入力に切り替えてから打ち直すまでの待ち時間（ミリ秒）。打ち直しが英字のまま入るなら増やす |
| `enabledApps` | この bundle ID だけで動く。空ならすべてのアプリ |
| `disabledApps` | 動かさない bundle ID。省略時は Terminal、iTerm2、Ghostty、Warp、kitty、WezTerm、Alacritty。書いた配列がそのまま使われ、既定の一覧には足されない |
| `japaneseInputSourceID` | この入力ソースが有効なときだけ変換する。省略時はかな入力がどれかあればよい。切り替え先はかなキーで決まる |

bundle ID は `osascript -e 'id of app "Claude"'` で分かります。

変換しない語は `~/.config/kanahen/words.txt` に 1 行 1 語で書きます。`#` で始まる行は読みません。

## うまくいかないとき

- 起動しない、変換されない: アクセシビリティで `~/.local/bin/kanahen` がオンかを確認する。許可したあと `launchctl kickstart -k gui/$(id -u)/local.kanahen`
- 更新のたびに許可が外れる: 証明書 `kanahen-dev` が無い。作ってから `scripts/install.sh` をやり直す。外れた項目は「−」で削除し、「＋」で追加し直す
- 誤って変換した: 変換待ちのまま **F10** で半角英数に戻し、Enter で確定する（ことえり、Google 日本語入力）
- ローマ字のまま送りたい: Enter の前に ← か → を押す。溜めた文字は捨てられ、判定しない。クリック、アプリの切り替え、30 秒の無入力でも捨てる。Shift+Enter は変換しない
- セキュア入力中は文字を溜めない。パスワード欄だと分かった Enter は変換しない
- 打ち直しが英字のまま: `switchDelayMs` を増やす
- ターミナルで動かない: 既定の `disabledApps` に入っている
- 変換されない日本語: 4 文字未満（英単語の直後の助詞は除く）、大文字を含む、辞書にある綴り（`same`、`made`、`sake`）、英単語 2 つに分けられるもの（`kanamono` = kana + mono、`repositorymade`）、l/x の小書き、v 行、`th` / `dh`。クリックより前の文字は対象にしない。`shita` のような 4 文字以上の語尾は辞書にあっても後ろで切る。`mergeshita` は「した」
- 助詞より前にローマ字でない語があると、そこから先は残る。`PR wo merge shita` は「した」だけ、`Kubernetes no pod ga ochiru` は「がおちる」だけになる
- US 配列以外（Dvorak など）: 打ち直しのキーコードが US 配列のため、正しく入らない

## ライセンス

MIT
