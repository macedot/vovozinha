#!/usr/bin/env bash
# Build, install, and launch Vovozinha on the connected physical iPhone.
# Never falls back to the simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app}"
IPHONE_UDID="${IPHONE_UDID:-00008130-001C78EC18EB8D3A}"
DESTINATION="${DESTINATION:-platform=iOS,id=$IPHONE_UDID}"
BUNDLE_ID="${BUNDLE_ID:-app.vovozinha.Vovozinha}"
SCHEME="${SCHEME:-Vovozinha}"
DERIVED="${DERIVED:-$ROOT/build/DerivedData}"

if ! xcrun devicectl device info details --device "$IPHONE_UDID" >/dev/null 2>&1; then
  echo "deploy.sh: physical iPhone $IPHONE_UDID is not connected" >&2
  exit 1
fi

if [[ ! -f "$ROOT/Vovozinha.xcodeproj/project.pbxproj" ]]; then
  echo "deploy.sh: generating Xcode project"
  (cd "$ROOT" && xcodegen generate)
fi

echo "xcodebuild build destination: $DESTINATION"
xcodebuild \
  -project "$ROOT/Vovozinha.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=FTS4YLJNG3 \
  build

APP=$(find "$DERIVED/Build/Products" -name 'Vovozinha.app' -path '*/Debug-iphoneos/*' | head -n 1)
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "deploy.sh: Vovozinha.app not found under $DERIVED/Build/Products" >&2
  exit 1
fi

echo "installing $APP"
xcrun devicectl device install app --device "$IPHONE_UDID" "$APP"

echo "launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$IPHONE_UDID" "$BUNDLE_ID"

echo "deploy.sh: launched $BUNDLE_ID on $IPHONE_UDID"
