#!/usr/bin/env bash
set -euo pipefail

if ! docker build -t galaxy-cvmfs:test ./cvmfs; then
    echo "CVMFS sidecar image build failed."
    exit 1
fi

cvmfs_mount_dir="$(mktemp -d)"
cvmfs_cache_dir="$(mktemp -d)"

cleanup() {
    status=$?
    if ((status != 0)); then
        docker inspect galaxy-cvmfs-test --format '{{json .State}}' >&2 || true
        docker logs galaxy-cvmfs-test >&2 || true
    fi
    docker exec galaxy-cvmfs-test sh -c "umount -l /cvmfs/data.galaxyproject.org /cvmfs/singularity.galaxyproject.org >/dev/null 2>&1 || true" || true
    docker exec galaxy-cvmfs-test sh -c "service autofs stop >/dev/null 2>&1 || true" || true
    docker stop galaxy-cvmfs-test >/dev/null 2>&1 || true
    docker rm -f galaxy-cvmfs-test >/dev/null 2>&1 || true
    rm -rf "$cvmfs_mount_dir" "$cvmfs_cache_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! docker run -d --name galaxy-cvmfs-test --privileged \
    -e CVMFS_REPOSITORIES=data.galaxyproject.org,singularity.galaxyproject.org \
    -v "$cvmfs_mount_dir:/cvmfs:rshared" \
    -v "$cvmfs_cache_dir:/var/lib/cvmfs:delegated" \
    galaxy-cvmfs:test >/dev/null; then
    echo "CVMFS sidecar container failed to start."
    exit 1
fi

mounted=false
for _ in $(seq 1 90); do
    if [[ $(docker inspect galaxy-cvmfs-test --format '{{.State.Running}}') != true ]]; then
        echo "CVMFS sidecar exited before its repositories became ready." >&2
        exit 1
    fi
    if docker exec galaxy-cvmfs-test ls /cvmfs/data.galaxyproject.org/byhand >/dev/null 2>&1; then
        mounted=true
        break
    fi
    sleep 2
done

if ! $mounted; then
    echo "CVMFS mount test failed in the sidecar."
    exit 1
fi

if ! docker run --rm \
    -v "$cvmfs_mount_dir:/cvmfs:rshared" \
    ubuntu:24.04 /bin/sh -c "ls /cvmfs/data.galaxyproject.org/byhand >/dev/null"; then
    echo "CVMFS mount not visible in a consumer container."
    exit 1
fi
