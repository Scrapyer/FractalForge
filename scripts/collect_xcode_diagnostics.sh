#!/bin/bash
set -euo pipefail
OUT="${1:-$HOME/Documents/FractalForge/xcode-diagnostics.txt}"
{
  echo "=== $(date) ==="
  echo "## Project"
  ls -la "$HOME/Documents/FractalForge" 2>&1 || true
  echo "## Build"
  cd "$HOME/Documents/FractalForge" && xcodebuild -scheme FractalForge -configuration Debug build 2>&1 | tail -80
  echo "## Crash reports (FractalForge)"
  ls -lt "$HOME/Library/Logs/DiagnosticReports/"*Fractal* 2>&1 | head -5 || true
  LATEST=$(ls -t "$HOME/Library/Logs/DiagnosticReports/"*Fractal* 2>/dev/null | head -1 || true)
  if [[ -n "${LATEST:-}" ]]; then
    echo "## Latest crash: $LATEST"
    head -200 "$LATEST"
  fi
} >"$OUT" 2>&1
echo "Wrote $OUT"
