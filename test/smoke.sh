#!/usr/bin/env bash
set -Eeuo pipefail

GALAXY_SMOKE_IMAGE=${GALAXY_SMOKE_IMAGE:-quay.io/bgruening/galaxy:ci}
GALAXY_SMOKE_CONTAINER=${GALAXY_SMOKE_CONTAINER:-galaxy-smoke}
GALAXY_SMOKE_PORT=${GALAXY_SMOKE_PORT:-8080}
GALAXY_SMOKE_TIMEOUT=${GALAXY_SMOKE_TIMEOUT:-600}
GALAXY_SMOKE_EXPECTED_ARCH=${GALAXY_SMOKE_EXPECTED_ARCH:-}
GALAXY_SMOKE_URL="http://127.0.0.1:${GALAXY_SMOKE_PORT}"

cleanup() {
    status=$?
    trap - EXIT

    if ((status != 0)); then
        echo "Galaxy smoke test failed; container logs follow."
        docker logs "$GALAXY_SMOKE_CONTAINER" 2>&1 || true
    fi

    docker rm -f "$GALAXY_SMOKE_CONTAINER" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT

docker rm -f "$GALAXY_SMOKE_CONTAINER" >/dev/null 2>&1 || true
docker run -d \
    --name "$GALAXY_SMOKE_CONTAINER" \
    --privileged \
    -p "${GALAXY_SMOKE_PORT}:80" \
    "$GALAXY_SMOKE_IMAGE"

if ! docker exec "$GALAXY_SMOKE_CONTAINER" \
    /tool_deps/_conda/bin/galaxy-wait \
    -g http://127.0.0.1 \
    -v \
    --timeout "$GALAXY_SMOKE_TIMEOUT"; then
    echo "Galaxy did not become ready within ${GALAXY_SMOKE_TIMEOUT} seconds."
    exit 1
fi

if [[ -n "$GALAXY_SMOKE_EXPECTED_ARCH" ]]; then
    actual_arch=$(docker exec "$GALAXY_SMOKE_CONTAINER" uname -m)
    if [[ "$actual_arch" != "$GALAXY_SMOKE_EXPECTED_ARCH" ]]; then
        echo "Expected architecture ${GALAXY_SMOKE_EXPECTED_ARCH}, got ${actual_arch}."
        exit 1
    fi
fi

echo "Galaxy is ready at ${GALAXY_SMOKE_URL}."
