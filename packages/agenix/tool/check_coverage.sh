#!/usr/bin/env bash
set -euo pipefail
MIN=${1:-85}
flutter test --coverage
PCT=$(lcov --summary coverage/lcov.info 2>/dev/null \
      | grep -oE 'lines.*: [0-9.]+%' | grep -oE '[0-9.]+' | head -1)
echo "Line coverage: ${PCT}% (min ${MIN}%)"
awk -v p="$PCT" -v m="$MIN" 'BEGIN { exit (p+0 >= m+0) ? 0 : 1 }'
