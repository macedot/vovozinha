#!/usr/bin/env bash
# Physical iPhone only. Never fall back to a simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app}"
IPHONE_UDID="${IPHONE_UDID:-00008130-001C78EC18EB8D3A}"
DESTINATION="${DESTINATION:-platform=iOS,id=$IPHONE_UDID}"
DERIVED="${DERIVED:-$ROOT/build/DerivedData}"

if ! xcrun devicectl device info details --device "$IPHONE_UDID" >/dev/null 2>&1; then
  echo "test.sh: physical iPhone $IPHONE_UDID is not connected" >&2
  exit 1
fi

if [[ ! -f "$ROOT/Vovozinha.xcodeproj/project.pbxproj" ]]; then
  echo "test.sh: generating Xcode project"
  (cd "$ROOT" && xcodegen generate)
fi

echo "xcodebuild test destination: $DESTINATION"
xcodebuild \
  -project "$ROOT/Vovozinha.xcodeproj" \
  -scheme Vovozinha \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=FTS4YLJNG3 \
  test
