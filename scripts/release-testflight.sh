#!/bin/bash
# release-testflight.sh — Wishes を TestFlight に配信する（アーカイブ→アップロードまで一括）
#
# 使い方:
#   scripts/release-testflight.sh                  # ビルド番号を +1 して配信
#   scripts/release-testflight.sh --version 1.0.2  # マーケティングバージョンも変更
#   scripts/release-testflight.sh --build 7        # ビルド番号を明示指定
#
# 前提:
#   - Xcode に Apple ID でサインイン済み（Settings → Accounts）。署名・アップロード認証に使う。
#   - 成功後の pbxproj（バージョン番号）のコミットは手動（このスクリプトはコミットしない）。
#
# よくある失敗と対処:
#   - "bundle version must be higher than ... 'N'" → --build N+1 で再実行。
#   - "train version 'X' is closed"（そのバージョンはリリース済み） → --version を上げて再実行。
set -euo pipefail

cd "$(dirname "$0")/.."
PBX=BucketList.xcodeproj/project.pbxproj
ARCHIVE=/tmp/BucketList-archive/Wishes.xcarchive
EXPORT_DIR=/tmp/BucketList-archive/export

VERSION=""
BUILD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build)   BUILD="$2";   shift 2 ;;
    *) echo "不明な引数: $1（--version X.Y.Z / --build N）" >&2; exit 1 ;;
  esac
done

CURRENT_BUILD=$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBX" | grep -oE '[0-9]+')
CURRENT_VERSION=$(grep -m1 -oE 'MARKETING_VERSION = [0-9.]+' "$PBX" | grep -oE '[0-9][0-9.]*')
NEW_BUILD=${BUILD:-$((CURRENT_BUILD + 1))}
NEW_VERSION=${VERSION:-$CURRENT_VERSION}

echo "==> 配信: v${NEW_VERSION} (build ${NEW_BUILD})  ※現在 v${CURRENT_VERSION} (build ${CURRENT_BUILD})"

echo "==> 1/4 型チェック"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios17.0 $(find BucketList -name '*.swift')

echo "==> 2/4 バージョン反映 (${PBX})"
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBX"
if [[ "$NEW_VERSION" != "$CURRENT_VERSION" ]]; then
  sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBX"
fi

echo "==> 3/4 アーカイブ (Release)"
xcodebuild -project BucketList.xcodeproj -scheme BucketList \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates archive -quiet

echo "==> 4/4 App Store Connect へアップロード"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" -allowProvisioningUpdates

echo ""
echo "✅ v${NEW_VERSION} (build ${NEW_BUILD}) をアップロードしました。"
echo "   数分〜数十分の処理後、App Store Connect の TestFlight タブに表示されます。"
echo "   ⚠️ バージョン変更をコミットしてください:"
echo "   git add ${PBX} && git commit -m 'リリース: v${NEW_VERSION} (build ${NEW_BUILD}) — TestFlight配信'"
