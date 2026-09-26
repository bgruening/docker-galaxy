#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export GALAXY_SMOKE_IMAGE=${GALAXY_IT_TEST_IMAGE:-quay.io/bgruening/galaxy:ci}
export GALAXY_SMOKE_CONTAINER=${GALAXY_IT_TEST_CONTAINER:-galaxy-it-smoke}
export GALAXY_SMOKE_PORT=${GALAXY_IT_TEST_PORT:-8082}
export GALAXY_SMOKE_RUNTIME=privileged
export GALAXY_SMOKE_IT_TEST=true
exec bash "$repo_root/test/smoke.sh"
