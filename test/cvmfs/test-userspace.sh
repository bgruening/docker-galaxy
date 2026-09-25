#!/usr/bin/env bash
set -euo pipefail

GALAXY_CVMFS_TEST_IMAGE=${GALAXY_CVMFS_TEST_IMAGE:-galaxy:test}
GALAXY_CVMFS_TEST_CONTAINER=${GALAXY_CVMFS_TEST_CONTAINER:-galaxy-cvmfs-userspace-test}
GALAXY_CVMFS_TEST_TIMEOUT=${GALAXY_CVMFS_TEST_TIMEOUT:-180}

userspace_cache_dir="$(mktemp -d)"

cleanup() {
    status=$?
    trap - EXIT
    if ((status != 0)); then
        docker logs "$GALAXY_CVMFS_TEST_CONTAINER" 2>&1 || true
        docker inspect "$GALAXY_CVMFS_TEST_CONTAINER" 2>&1 || true
    fi
    docker stop "$GALAXY_CVMFS_TEST_CONTAINER" >/dev/null 2>&1 || true
    docker rm -f "$GALAXY_CVMFS_TEST_CONTAINER" >/dev/null 2>&1 || true
    rm -rf "$userspace_cache_dir" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT

# The marker is created only after the command below cvmfsexec can read both
# repositories. docker exec does not need to enter cvmfsexec's mount namespace.
if [[ ! -c /dev/fuse ]]; then
    echo "The host does not provide /dev/fuse; userspace CVMFS cannot be tested."
    exit 1
fi

docker rm -f "$GALAXY_CVMFS_TEST_CONTAINER" >/dev/null 2>&1 || true
docker run -d --rm --name "$GALAXY_CVMFS_TEST_CONTAINER" \
    --device /dev/fuse \
    --security-opt seccomp=unconfined \
    --security-opt systempaths=unconfined \
    -e CVMFS_MODE=userspace \
    -e CVMFS_REPOSITORIES=data.galaxyproject.org,singularity.galaxyproject.org \
    -v "$userspace_cache_dir:/export/cvmfs-cache:delegated" \
    "$GALAXY_CVMFS_TEST_IMAGE" \
    bash -c 'set -e
        test -r /cvmfs/data.galaxyproject.org/.cvmfspublished
        test -d /cvmfs/data.galaxyproject.org/byhand
        test -r /cvmfs/singularity.galaxyproject.org/.cvmfspublished
        test -d /cvmfs/singularity.galaxyproject.org/all
        touch /tmp/cvmfs-userspace-ready
        exec sleep infinity' >/dev/null

deadline=$((SECONDS + GALAXY_CVMFS_TEST_TIMEOUT))
while ((SECONDS < deadline)); do
    if docker exec "$GALAXY_CVMFS_TEST_CONTAINER" test -f /tmp/cvmfs-userspace-ready >/dev/null 2>&1; then
        break
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$GALAXY_CVMFS_TEST_CONTAINER")" != true ]]; then
        echo "Userspace CVMFS container exited before becoming ready."
        exit 1
    fi
    sleep 2
done

if ! docker exec "$GALAXY_CVMFS_TEST_CONTAINER" test -f /tmp/cvmfs-userspace-ready >/dev/null 2>&1; then
    echo "Userspace CVMFS repositories did not become ready within ${GALAXY_CVMFS_TEST_TIMEOUT}s."
    exit 1
fi

if [[ ! -d "$userspace_cache_dir/shared" ]]; then
    echo "Userspace CVMFS did not use the persisted cache directory."
    exit 1
fi

echo "Userspace CVMFS is serving data and container-image repositories."
