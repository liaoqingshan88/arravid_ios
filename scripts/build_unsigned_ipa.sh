#!/usr/bin/env bash
# =====================================================================
# 本地（Mac）构建未签名 ipa 的脚本
#
# 用法：在 Mac 上，进入本目录后执行：
#   bash scripts/build_unsigned_ipa.sh
#
# 产物：build/ArrAvid-unsigned.ipa（可直接用 Sideloadly / AltStore 安装）
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 构建 Release（不签名）"
xcodebuild \
  -project ArrAvid.xcodeproj \
  -scheme ArrAvid \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

echo "==> 打包 ipa"
APP="build/Build/Products/Release-iphoneos/ArrAvid.app"
test -d "$APP" || { echo "找不到产物：$APP"; exit 1; }
rm -rf build/Payload build/ArrAvid-unsigned.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry ArrAvid-unsigned.ipa Payload)
rm -rf build/Payload
echo "==> 完成：build/ArrAvid-unsigned.ipa"
ls -lh build/ArrAvid-unsigned.ipa