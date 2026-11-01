#!/bin/bash
# ビルドしてテストし、~/.local/bin に置いて、ログイン時に起動する LaunchAgent を
# 設定・再起動する。何度実行してもよい（既存の plist は書き換えない）。
#
# ad-hoc 署名のままだと macOS はバイナリのハッシュで許可を管理するため、
# ビルドのたびにアクセシビリティの許可が外れる。キーチェーンにコード署名用の
# 証明書（既定名 no-more-gobaku-dev）があればそれで署名し、「識別子＋証明書」で
# 管理させて、作り直しても許可が保たれるようにする。
set -euo pipefail

identity="${NMG_SIGN_IDENTITY:-no-more-gobaku-dev}"
dest="$HOME/.local/bin/no-more-gobaku"
label="local.no-more-gobaku"

cd "$(dirname "$0")/.."

swift build -c release
swift run -c release selftest

signed=false
security find-identity -p codesigning | grep -q "\"$identity\"" && signed=true

# 同じソースからは同じバイナリができる。ad-hoc 署名なら中身が同じかぎり許可は外れないので、入れ替えない
if ! $signed && cmp -s .build/release/no-more-gobaku "$dest"; then
    echo "install.sh: バイナリに変更がないため入れ替えません"
else
    # 動いているバイナリを上書きするとプロセスが強制終了されることがあるため、
    # install で別ファイルとして置き直す
    mkdir -p "$(dirname "$dest")"
    install -m 755 .build/release/no-more-gobaku "$dest"
    if $signed; then
        codesign --force --sign "$identity" --identifier "$label" "$dest"
    else
        echo "install.sh: 証明書「$identity」がないため ad-hoc 署名のまま入れました。" >&2
        echo "  アクセシビリティで no-more-gobaku を「−」で削除し、「＋」で $dest を追加し直してください。" >&2
    fi
fi

plist="$HOME/Library/LaunchAgents/$label.plist"
if [ ! -f "$plist" ]; then
    mkdir -p "$(dirname "$plist")" "$HOME/Library/Logs"
    # 許可がないときの正常終了で再起動を繰り返さないよう、クラッシュ時だけ再起動する
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>$dest</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>Crashed</key><true/></dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/no-more-gobaku.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/no-more-gobaku.log</string>
</dict>
</plist>
EOF
    echo "install.sh: $plist を作りました"
fi

if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/$label"
else
    launchctl bootstrap "gui/$(id -u)" "$plist"
fi

sleep 1
if pgrep -f "$dest run" >/dev/null; then
    echo "install.sh: 常駐版を起動しました"
else
    echo "install.sh: 常駐版が起動していません。アクセシビリティの許可が必要です。" >&2
    echo "  システム設定 > プライバシーとセキュリティ > アクセシビリティ で no-more-gobaku をオンにし" >&2
    echo "  （一覧になければ「＋」で $dest を追加）、次で起動してください。" >&2
    echo "  launchctl kickstart -k gui/\$(id -u)/$label" >&2
    exit 1
fi
