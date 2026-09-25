#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

GALAXY_SMOKE_IMAGE=${GALAXY_CVMFS_TEST_IMAGE:-galaxy:test} \
GALAXY_SMOKE_CONTAINER=${GALAXY_CVMFS_TEST_CONTAINER:-galaxy-cvmfs-userspace-test} \
GALAXY_SMOKE_PORT=${GALAXY_CVMFS_TEST_PORT:-8081} \
GALAXY_SMOKE_TIMEOUT=${GALAXY_CVMFS_TEST_TIMEOUT:-600} \
GALAXY_SMOKE_EXPECTED_ARCH=${GALAXY_CVMFS_TEST_EXPECTED_ARCH:-} \
GALAXY_SMOKE_RUNTIME=userspace-cvmfs \
    "$repo_root/test/smoke.sh"
