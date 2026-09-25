#!/usr/bin/env bash
set -euo pipefail

CVMFS_MODE=${CVMFS_MODE:-auto}
CVMFS_USERSPACE_ROOT=${CVMFS_USERSPACE_ROOT:-/opt/cvmfsexec}
CVMFS_CACHE_BASE=${CVMFS_CACHE_BASE:-/export/cvmfs-cache}
CVMFS_QUOTA_LIMIT=${CVMFS_QUOTA_LIMIT:-4000}
CVMFS_EXTERNAL_WAIT=${CVMFS_EXTERNAL_WAIT:-60}

repos=${CVMFS_REPOSITORIES:-data.galaxyproject.org singularity.galaxyproject.org}
repos=${repos//,/ }
read -r -a repository_list <<< "$repos"

repositories_available() {
    local repository
    for repository in "${repository_list[@]}"; do
        if [[ ! -r "/cvmfs/${repository}/.cvmfspublished" ]]; then
            return 1
        fi
    done
}

wait_for_external_repositories() {
    local deadline=$((SECONDS + CVMFS_EXTERNAL_WAIT))
    while ((SECONDS < deadline)); do
        if repositories_available; then
            return 0
        fi
        sleep 2
    done
    return 1
}

has_cap_sys_admin() {
    local effective
    effective=$(awk '/^CapEff:/ { print $2 }' /proc/self/status)
    (( (0x${effective:-0} & 0x200000) != 0 ))
}

userspace_prerequisites_available() {
    [[ -c /dev/fuse ]] || return 1
    [[ -x "$CVMFS_USERSPACE_ROOT/cvmfsexec" ]] || return 1
    unshare -Ur true >/dev/null 2>&1
}

configure_userspace_cache() {
    local config_file="$CVMFS_USERSPACE_ROOT/dist/etc/cvmfs/default.local"
    mkdir -p "$CVMFS_CACHE_BASE"
    touch "$config_file"
    sed -i '/^CVMFS_CACHE_BASE=/d; /^CVMFS_QUOTA_LIMIT=/d' "$config_file"
    printf 'CVMFS_CACHE_BASE="%s"\n' "$CVMFS_CACHE_BASE" >> "$config_file"
    printf 'CVMFS_QUOTA_LIMIT="%s"\n' "$CVMFS_QUOTA_LIMIT" >> "$config_file"
}

case "$CVMFS_MODE" in
    auto)
        if repositories_available; then
            CVMFS_RESOLVED_MODE=external
        elif has_cap_sys_admin; then
            # Preserve the existing privileged/autofs path when it is available.
            CVMFS_RESOLVED_MODE=system
        elif userspace_prerequisites_available; then
            CVMFS_RESOLVED_MODE=userspace
        else
            CVMFS_RESOLVED_MODE=disabled
        fi
        ;;
    userspace)
        if ! userspace_prerequisites_available; then
            echo "CVMFS userspace mode requires /dev/fuse and unprivileged user namespaces." >&2
            echo "See the CVMFS section in README.md for the required Docker options." >&2
            exit 1
        fi
        CVMFS_RESOLVED_MODE=userspace
        ;;
    external)
        if ! wait_for_external_repositories; then
            echo "CVMFS external mode could not read all requested repositories within ${CVMFS_EXTERNAL_WAIT}s." >&2
            exit 1
        fi
        CVMFS_RESOLVED_MODE=external
        ;;
    system|disabled)
        CVMFS_RESOLVED_MODE=$CVMFS_MODE
        ;;
    *)
        echo "Unsupported CVMFS_MODE '${CVMFS_MODE}'. Expected auto, userspace, system, external, or disabled." >&2
        exit 1
        ;;
esac

export CVMFS_RESOLVED_MODE
echo "CVMFS mode: ${CVMFS_RESOLVED_MODE}"

if [[ "$CVMFS_RESOLVED_MODE" == userspace ]]; then
    configure_userspace_cache
    export CVMFS_USERSPACE_ACTIVE=true
    exec "$CVMFS_USERSPACE_ROOT/cvmfsexec" "${repository_list[@]}" -- "$@"
fi

exec "$@"
