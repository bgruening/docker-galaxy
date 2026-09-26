#!/usr/bin/env bash
set -Eeuo pipefail

GALAXY_SMOKE_IMAGE=${GALAXY_SMOKE_IMAGE:-quay.io/bgruening/galaxy:ci}
GALAXY_SMOKE_CONTAINER=${GALAXY_SMOKE_CONTAINER:-galaxy-smoke}
GALAXY_SMOKE_PORT=${GALAXY_SMOKE_PORT:-8080}
GALAXY_SMOKE_TIMEOUT=${GALAXY_SMOKE_TIMEOUT:-600}
GALAXY_SMOKE_EXPECTED_ARCH=${GALAXY_SMOKE_EXPECTED_ARCH:-}
GALAXY_SMOKE_RUNTIME=${GALAXY_SMOKE_RUNTIME:-privileged}
GALAXY_SMOKE_API_KEY=${GALAXY_SMOKE_API_KEY:-fakekey}
GALAXY_SMOKE_CVMFS_TOOL_TEST=${GALAXY_SMOKE_CVMFS_TOOL_TEST:-false}
GALAXY_SMOKE_URL="http://127.0.0.1:${GALAXY_SMOKE_PORT}"
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

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
        docker run --rm --entrypoint find \
            -v "$userspace_cache_dir:/cache" "$GALAXY_SMOKE_IMAGE" \
            /cache -mindepth 1 -delete >/dev/null 2>&1 || true
        rmdir "$userspace_cache_dir" >/dev/null 2>&1 || true
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
            --security-opt "apparmor=${GALAXY_SMOKE_APPARMOR_PROFILE:-unconfined}"
            --security-opt seccomp=unconfined
            --security-opt systempaths=unconfined
            -e CVMFS_MODE=userspace
            -v "$userspace_cache_dir:/export/cvmfs-cache:delegated"
        )
        ;;
    *)
        echo "Unsupported GALAXY_SMOKE_RUNTIME '$GALAXY_SMOKE_RUNTIME'." >&2
        exit 1
        ;;
esac

if [[ "$GALAXY_SMOKE_CVMFS_TOOL_TEST" == true ]]; then
    if [[ "$GALAXY_SMOKE_RUNTIME" != userspace-cvmfs ]]; then
        echo "CVMFS tool execution requires GALAXY_SMOKE_RUNTIME=userspace-cvmfs." >&2
        exit 1
    fi
    docker_args+=(
        -v "$repo_root/test/cvmfs/tools:/cvmfs-tool-test:ro"
        -e GALAXY_CVMFS_TOOL_TEST=true
        -e GALAXY_CONFIG_TOOL_CONFIG_FILE=/cvmfs-tool-test/tool_conf.xml
        -e GALAXY_CONFIG_CONTAINER_RESOLVERS_CONFIG_FILE=/cvmfs-tool-test/container_resolvers.yml
        -e GALAXY_CONFIG_CONDA_AUTO_INSTALL=False
    )
fi

container_command=()
if [[ "$GALAXY_SMOKE_RUNTIME" == userspace-cvmfs ]]; then
    # Run inside the entrypoint's namespaces. docker exec enters the original
    # container namespaces and cannot see the userspace CVMFS mounts.
    # shellcheck disable=SC2016
    container_command=(bash -ec '
        for identity in "$GALAXY_UID:$GALAXY_GID" "${GALAXY_POSTGRES_UID:-1550}:${GALAXY_POSTGRES_GID:-1550}"; do
            setpriv --reuid="${identity%:*}" --regid="${identity#*:}" --clear-groups \
                ls /cvmfs/data.galaxyproject.org/byhand/location/tool_data_table_conf.xml \
                   /cvmfs/singularity.galaxyproject.org/all >/dev/null
        done
        if [[ "${GALAXY_CVMFS_TOOL_TEST:-false}" == true ]]; then
            python3 /cvmfs-tool-test/prepare-job-config.py "$GALAXY_CONFIG_JOB_CONFIG_FILE" /tmp/cvmfs-job-conf.xml
            export GALAXY_CONFIG_JOB_CONFIG_FILE=/tmp/cvmfs-job-conf.xml
        fi
        exec /usr/bin/startup
    ')
fi
docker run "${docker_args[@]}" "$GALAXY_SMOKE_IMAGE" "${container_command[@]}"

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
    if ! curl --fail --silent --show-error \
        -H "x-api-key: ${GALAXY_SMOKE_API_KEY}" \
        "${GALAXY_SMOKE_URL}/api/tool_data/all_fasta" | python3 -c '
import json
import sys

table = json.load(sys.stdin)
assert table["name"] == "all_fasta"
assert table["fields"], "all_fasta has no entries"
assert any(
    isinstance(value, str) and value.startswith("/cvmfs/data.galaxyproject.org/")
    for row in table["fields"]
    for value in row
), "all_fasta has no CVMFS-backed entries"
'; then
        echo "Galaxy booted, but its all_fasta tool-data table was not loaded from CVMFS."
        exit 1
    fi
    if [[ ! -d "$userspace_cache_dir/shared" ]]; then
        echo "Userspace CVMFS did not use the persisted cache directory."
        exit 1
    fi
fi

if [[ "$GALAXY_SMOKE_CVMFS_TOOL_TEST" == true ]]; then
    GALAXY_CVMFS_TEST_URL="$GALAXY_SMOKE_URL" \
    GALAXY_CVMFS_TEST_API_KEY="$GALAXY_SMOKE_API_KEY" \
        bash "$repo_root/test/cvmfs/test-tool-execution.sh"
fi

echo "Galaxy is ready at ${GALAXY_SMOKE_URL}."
