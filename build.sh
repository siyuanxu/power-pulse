#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
DERIVED_DIR="$PROJECT_DIR/.build/xcode"
APP_DIR="$PROJECT_DIR/dist/Power Pulse.app"
PREVIOUS_DIR="$PROJECT_DIR/.build/previous"

cd "$PROJECT_DIR"
/opt/homebrew/bin/xcodegen generate --spec "$PROJECT_DIR/project.yml"
/usr/bin/xcodebuild \
  -project "$PROJECT_DIR/PowerPulse.xcodeproj" \
  -scheme PowerPulse \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

if [[ -d "$APP_DIR" ]]; then
  /bin/mkdir -p "$PREVIOUS_DIR"
  /bin/mv "$APP_DIR" "$PREVIOUS_DIR/Power Pulse-$(/bin/date +%Y%m%d-%H%M%S).app"
fi
/usr/bin/ditto "$DERIVED_DIR/Build/Products/Release/Power Pulse.app" "$APP_DIR"

echo "$APP_DIR"
