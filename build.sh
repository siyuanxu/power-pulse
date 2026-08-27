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

WIDGET_BUNDLE="$APP_DIR/Contents/PlugIns/PowerPulseWidget.appex"
WIDGET_PROCESS_PATTERN="$PROJECT_DIR/.*PowerPulseWidget.appex/Contents/MacOS/PowerPulseWidget"

# WidgetKit may keep executing the binary from the app bundle that was moved to
# .build/previous. Re-register the freshly built extension and stop that stale
# process so chronod creates a new timeline with the current binary.
if ! /usr/bin/pluginkit -a "$WIDGET_BUNDLE"; then
  echo "Warning: WidgetKit extension registration failed; relaunch the app or log in again."
fi
/usr/bin/pkill -f "$WIDGET_PROCESS_PATTERN" 2>/dev/null || true

echo "$APP_DIR"
