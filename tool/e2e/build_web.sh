#!/bin/bash
# Build a throwaway web copy of the app for browser-based E2E checks.
#
# The repo itself stays Android-only: this copies lib/, pubspec.yaml and
# assets/ into WORK_DIR, adds a web platform there, turns on semantics (so
# Playwright can find widgets by label) and builds it.
#
# Usage: tool/e2e/build_web.sh [--debug]     (WORK_DIR defaults to /tmp/robotics_tool_web)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="${WORK_DIR:-/tmp/robotics_tool_web}"
MODE="--release"
[[ "${1:-}" == "--debug" ]] && MODE="--debug"

mkdir -p "$WORK_DIR"
rm -rf "$WORK_DIR/lib" "$WORK_DIR/assets"
cp -r "$REPO/lib" "$REPO/assets" "$REPO/pubspec.yaml" "$REPO/analysis_options.yaml" "$WORK_DIR/"

cd "$WORK_DIR"
[[ -d web ]] || flutter create --platforms=web --project-name robotics_tool . >/dev/null

python3 - lib/main.dart <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("import 'package:flutter/services.dart';",
              "import 'package:flutter/semantics.dart';\nimport 'package:flutter/services.dart';", 1)
s = s.replace("WidgetsFlutterBinding.ensureInitialized();",
              "WidgetsFlutterBinding.ensureInitialized();\n  SemanticsBinding.instance.ensureSemantics();", 1)
open(p, "w").write(s)
PY

flutter pub get >/dev/null
flutter build web $MODE --no-web-resources-cdn --no-wasm-dry-run 2>&1 | grep -E "Built|Error|error:" || true
echo "web build: $WORK_DIR/build/web"
