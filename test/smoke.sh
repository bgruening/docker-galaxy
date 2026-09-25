#!/usr/bin/env bash
set -Eeuo pipefail

GALAXY_SMOKE_IMAGE=${GALAXY_SMOKE_IMAGE:-quay.io/bgruening/galaxy:ci}
GALAXY_SMOKE_CONTAINER=${GALAXY_SMOKE_CONTAINER:-galaxy-smoke}
GALAXY_SMOKE_PORT=${GALAXY_SMOKE_PORT:-8080}
GALAXY_SMOKE_TIMEOUT=${GALAXY_SMOKE_TIMEOUT:-600}
GALAXY_SMOKE_EXPECTED_ARCH=${GALAXY_SMOKE_EXPECTED_ARCH:-}
GALAXY_SMOKE_RUNTIME=${GALAXY_SMOKE_RUNTIME:-privileged}
GALAXY_SMOKE_URL="http://127.0.0.1:${GALAXY_SMOKE_PORT}"
GALAXY_SMOKE_CVMFS_READY_FILE=/tmp/galaxy-cvmfs-ready

userspace_cache_dir=""

cleanup() {
    status=$?
    trap - EXIT

    if ((status != 0)); then
        echo "Galaxy smoke test failed; container logs follow."
        docker logs "$GALAXY_SMOKE_CONTAINER" 2>&1 || true
    fi

    docker rm -f "$GALAXY_SMOKE_CONTAINER" >/dev/null 2>&1 || true
    if [[ -n "$userspace_cache_dir" ]]; then
        rm -rf "$userspace_cache_dir" >/dev/null 2>&1 || true
    fi
    exit "$status"
}
trap cleanup EXIT

docker rm -f "$GALAXY_SMOKE_CONTAINER" >/dev/null 2>&1 || true
docker_args=(
    -d
    --name "$GALAXY_SMOKE_CONTAINER"
    -p "${GALAXY_SMOKE_PORT}:80"
)

case "$GALAXY_SMOKE_RUNTIME" in
    privileged)
        docker_args+=(--privileged)
        ;;
    userspace-cvmfs)
        if [[ ! -c /dev/fuse ]]; then
            echo "The host does not provide /dev/fuse; userspace CVMFS cannot be tested."
            exit 1
        fi
        userspace_cache_dir=$(mktemp -d)
        docker_args+=(
            --device /dev/fuse
            --security-opt seccomp=unconfined
            --security-opt systempaths=unconfined
            -e CVMFS_MODE=userspace
            -e "CVMFS_READY_FILE=$GALAXY_SMOKE_CVMFS_READY_FILE"
            -v "$userspace_cache_dir:/export/cvmfs-cache:delegated"
        )
        ;;
    *)
        echo "Unsupported GALAXY_SMOKE_RUNTIME '$GALAXY_SMOKE_RUNTIME'." >&2
        exit 1
        ;;
esac

docker run "${docker_args[@]}" "$GALAXY_SMOKE_IMAGE"

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

if [[ "$GALAXY_SMOKE_RUNTIME" == "userspace-cvmfs" ]]; then
    if ! docker exec "$GALAXY_SMOKE_CONTAINER" \
        grep -qx 'repositories=ready' "$GALAXY_SMOKE_CVMFS_READY_FILE"; then
        echo "Galaxy booted, but the requested CVMFS repositories were not ready."
        exit 1
    fi
    if ! docker exec "$GALAXY_SMOKE_CONTAINER" \
        grep -qx 'tool_data=ready' "$GALAXY_SMOKE_CVMFS_READY_FILE"; then
        echo "Galaxy booted, but CVMFS tool-data configuration was not ready."
        exit 1
    fi
    if [[ ! -d "$userspace_cache_dir/shared" ]]; then
        echo "Userspace CVMFS did not use the persisted cache directory."
        exit 1
    fi
fi

echo "Galaxy is ready at ${GALAXY_SMOKE_URL}."
