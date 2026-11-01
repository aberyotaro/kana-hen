#!/bin/bash
# ビルドしてテストし、~/.local/bin に置いて常駐版を再起動する。
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

# 動いているバイナリを上書きするとプロセスが強制終了されることがあるため、
# install で別ファイルとして置き直す
mkdir -p "$(dirname "$dest")"
install -m 755 .build/release/no-more-gobaku "$dest"

if security find-identity -p codesigning | grep -q "\"$identity\""; then
    codesign --force --sign "$identity" --identifier "$label" "$dest"
else
    echo "install.sh: 証明書「$identity」がないため ad-hoc 署名のまま入れました。" >&2
    echo "  アクセシビリティで no-more-gobaku を「−」で削除し、「＋」で $dest を追加し直してください。" >&2
fi

if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/$label"
    sleep 1
    if pgrep -f "$dest run" >/dev/null; then
        echo "install.sh: 常駐版を再起動しました"
    else
        echo "install.sh: 常駐版が起動していません。~/Library/Logs/no-more-gobaku.log を確認してください" >&2
        exit 1
    fi
fi
