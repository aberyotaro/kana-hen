#!/bin/bash
# LaunchAgent を止め、install.sh が置いたファイルを消す。何度実行してもよい。
# アクセシビリティと入力監視の許可は、システム設定から手で外す。
set -euo pipefail

dest="$HOME/.local/bin/kanahen"
label="local.kanahen"
plist="$HOME/Library/LaunchAgents/$label.plist"
config_dir="$HOME/.config/kanahen"
log="$HOME/Library/Logs/kanahen.log"
uid="$(id -u)"

if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
    launchctl bootout "gui/$uid/$label"
    echo "uninstall.sh: LaunchAgent $label を停止しました"
fi

if [ -f "$plist" ]; then
    rm -f "$plist"
    echo "uninstall.sh: $plist を削除しました"
fi
if [ -e "$dest" ]; then
    rm -f "$dest"
    echo "uninstall.sh: $dest を削除しました"
fi
# シンボリックリンクのときはリンクだけを外し、実体の中までは消さない
if [ -L "$config_dir" ] || [ -f "$config_dir" ]; then
    rm -f "$config_dir"
    echo "uninstall.sh: $config_dir を削除しました"
elif [ -d "$config_dir" ]; then
    rm -rf "$config_dir"
    echo "uninstall.sh: $config_dir を削除しました"
fi
if [ -e "$log" ]; then
    rm -f "$log"
    echo "uninstall.sh: $log を削除しました"
fi

echo "uninstall.sh: システム設定 > プライバシーとセキュリティ > アクセシビリティ から kanahen を「−」で削除してください。" >&2
echo "  入力監視に入っていれば、そこからも削除してください。" >&2
