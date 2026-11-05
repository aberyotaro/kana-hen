# kana-hen

英数モードのまま打ったローマ字を、Enter で日本語に打ち直す macOS の常駐プログラム。

```
kyouhaiitenkidesune⏎   →  きょうはいいてんきですね
repositoryha⏎          →  repositoryは
korehatestwo⏎          →  これはtestを
repository ni push⏎    →  repository に push
git push origin main⏎  →  そのまま送信
```

変換するときは Enter を横取りするので、ローマ字のまま送信されない。かなは変換待ちで残るので、そのまま漢字にできる。

## インストール

macOS 13 以降と Command Line Tools（`xcode-select --install`）が要る。キー配列は US か JIS（Dvorak などでは打ち直しが正しく入らない）。

```bash
git clone https://github.com/aberyotaro/kana-hen.git
cd kana-hen
scripts/install.sh
```

`~/.local/bin/kanahen` を置き、ログイン時に起動する LaunchAgent `local.kanahen` を登録する。

初回は **システム設定 > プライバシーとセキュリティ > アクセシビリティ** で `~/.local/bin/kanahen` をオンにしてから、常駐を起動し直す。

```bash
launchctl kickstart -k gui/$(id -u)/local.kanahen
```

更新は `git pull && scripts/install.sh`。キーチェーンにコード署名用の自己署名証明書 `kanahen-dev` を作っておくと、更新しても許可が外れない。別名の証明書は `KANAHEN_SIGN_IDENTITY` で指定する。

## 変換しないもの

英文を壊さないことを優先している。

- 4 文字未満の語（英単語の直後の助詞は除く）
- 辞書にある英単語（`same`、`made`）と、英単語 2 つに分けられる語（`kanamono`）
- 英文にも出る `to`・`no`・`he`・`ya`。`GitHub`・`API`・`v2` のような技術用語の直後だけ変換する
- 英単語に挟まれた助詞をつなげた形（`repositorynipush`）
- 英単語に挟まれた `de`（`the de facto standard`、`Tour de France`）
- 貼り付けた文字、矢印キーやクリックのあとの文字、Shift+Enter

## 使い方

| コマンド | すること |
|---|---|
| `kanahen check <文字列>...` | 判定だけを試す |
| `kanahen run -v` | 常駐して、変換結果と変換しなかった理由を出す |
| `kanahen sources` | 入力ソースの一覧と、英数とみなすかを出す |
| `kanahen probe [秒]` | 前面の入力欄を読めるかを調べる |

誤って変換したら、変換待ちのうちに **F10** で英字に戻す。

## 設定

`~/.config/kanahen/config.json` に書いた項目だけが既定値を上書きする。

```json
{
  "minLetters": 4,
  "minJapaneseRatio": 0.5,
  "switchDelayMs": 60,
  "enabledApps": [],
  "disabledApps": ["com.apple.Terminal"],
  "japaneseInputSourceID": "com.google.inputmethod.Japanese.base"
}
```

| 項目 | 意味 |
|---|---|
| `minLetters` | 変換する最小の文字数 |
| `minJapaneseRatio` | 英単語でない語の文字数の割合の下限 |
| `switchDelayMs` | 入力モードを切り替えてから打つまでの待ち時間。打ち直しが英字のまま入るなら増やす |
| `enabledApps` | 動かすアプリの bundle ID。空ならすべて |
| `disabledApps` | 動かさないアプリの bundle ID。省略時は主なターミナル。書くと既定を置き換える |
| `japaneseInputSourceID` | このかな入力が有効なときだけ変換する |

bundle ID は `osascript -e 'id of app "Claude"'` で分かる。変換させたくない語は `~/.config/kanahen/words.txt` に 1 行 1 語で書く。

## プライバシー

打った文字はネットワークに送らない。Enter までメモリに最大 256 文字だけ持つ。

ログ `~/Library/Logs/kanahen.log` に打った文字が出るのは `-v` のときだけ。常に出すのは、キー監視の停止、セキュア入力の切り替わり、500 ms 以上かかった Enter、変換の中断の時刻だけ。

## アンインストール

```bash
scripts/uninstall.sh
```

アクセシビリティの一覧からも kanahen を削除する。

## ライセンス

MIT
