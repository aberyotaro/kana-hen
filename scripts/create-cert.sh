#!/bin/bash
# install.sh がコード署名に使う自己署名証明書（既定名 kanahen-dev）を作り、ログインキーチェーンに入れる。
# この証明書で署名すると、macOS はアクセシビリティの許可を「識別子＋証明書」で管理するため、
# 作り直しても許可が外れない。証明書を信頼済みにする必要はない（システムの設定は変えない）。
# 既に同名の証明書があれば何もしない。
set -euo pipefail

identity="${KANAHEN_SIGN_IDENTITY:-kanahen-dev}"
keychain="${KANAHEN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$keychain" | grep -F -q -- "\"$identity\""; then
    echo "create-cert.sh: 証明書「${identity}」は既にあります"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# 鍵は一時ディレクトリで作ってキーチェーンに移し、ファイルには残さない
password="$(openssl rand -hex 16)"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=$identity" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null

# macOS の security は新しい暗号方式の PKCS#12 を読めないため、古い方式で書き出す
legacy=()
openssl pkcs12 -help 2>&1 | grep -q -- '-legacy' && legacy=(-legacy)
openssl pkcs12 -export "${legacy[@]}" -name "$identity" \
    -inkey "$work/key.pem" -in "$work/cert.pem" \
    -out "$work/identity.p12" -passout "pass:$password"

# codesign には確認なしで鍵を使わせる
security import "$work/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null

echo "create-cert.sh: 証明書「${identity}」を $keychain に作りました"
echo "  scripts/install.sh を実行し直し、最後にもう一度だけアクセシビリティで kanahen を登録し直してください。"
