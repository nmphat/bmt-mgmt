#!/usr/bin/env bash
set -euo pipefail
docker rm -f bmt-test >/dev/null 2>&1 || true
echo "test database removed"
