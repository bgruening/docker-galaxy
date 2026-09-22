#!/usr/bin/env bash
set -Eeuo pipefail

GALAXY_SMOKE_IMAGE=${GALAXY_SMOKE_IMAGE:-quay.io/bgruening/galaxy:ci}
GALAXY_SMOKE_CONTAINER=${GALAXY_SMOKE_CONTAINER:-galaxy-smoke}
GALAXY_SMOKE_PORT=${GALAXY_SMOKE_PORT:-8080}
GALAXY_SMOKE_TIMEOUT=${GALAXY_SMOKE_TIMEOUT:-600}
GALAXY_SMOKE_INTERVAL=${GALAXY_SMOKE_INTERVAL:-15}
GALAXY_SMOKE_EXPECTED_ARCH=${GALAXY_SMOKE_EXPECTED_ARCH:-}
GALAXY_SMOKE_URL="http://127.0.0.1:${GALAXY_SMOKE_PORT}/api/version"

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

deadline=$((SECONDS + GALAXY_SMOKE_TIMEOUT))
while ! curl --fail --silent --show-error "$GALAXY_SMOKE_URL"; do
    if [[ "$(docker inspect --format '{{.State.Running}}' "$GALAXY_SMOKE_CONTAINER")" != "true" ]]; then
        echo "Galaxy container stopped before becoming ready."
        exit 1
    fi
    if ((SECONDS >= deadline)); then
        echo "Galaxy did not become ready within ${GALAXY_SMOKE_TIMEOUT} seconds."
        exit 1
    fi
    sleep "$GALAXY_SMOKE_INTERVAL"
done
echo

if [[ -n "$GALAXY_SMOKE_EXPECTED_ARCH" ]]; then
    actual_arch=$(docker exec "$GALAXY_SMOKE_CONTAINER" uname -m)
    if [[ "$actual_arch" != "$GALAXY_SMOKE_EXPECTED_ARCH" ]]; then
        echo "Expected architecture ${GALAXY_SMOKE_EXPECTED_ARCH}, got ${actual_arch}."
        exit 1
    fi
fi

echo "Galaxy is ready at ${GALAXY_SMOKE_URL}."
