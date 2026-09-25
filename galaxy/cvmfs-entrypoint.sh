#!/usr/bin/env bash
set -euo pipefail

CVMFS_MODE=${CVMFS_MODE:-auto}
CVMFS_USERSPACE_ROOT=${CVMFS_USERSPACE_ROOT:-/opt/cvmfsexec}
CVMFS_CACHE_BASE=${CVMFS_CACHE_BASE:-/export/cvmfs-cache}
CVMFS_QUOTA_LIMIT=${CVMFS_QUOTA_LIMIT:-4000}
CVMFS_EXTERNAL_WAIT=${CVMFS_EXTERNAL_WAIT:-60}

# shellcheck source-path=SCRIPTDIR
# shellcheck source=cvmfs-functions.sh
source /usr/lib/docker-galaxy/cvmfs-functions.sh
cvmfs_set_repositories

wait_for_external_repositories() {
    local deadline=$((SECONDS + CVMFS_EXTERNAL_WAIT))
    while ((SECONDS < deadline)); do
        if cvmfs_repositories_available; then
            return 0
        fi
        sleep 2
    done
    return 1
}

userspace_prerequisites_available() {
    local uid_start uid_count gid_start gid_count
    [[ -c /dev/fuse ]] || return 1
    [[ -x "$CVMFS_USERSPACE_ROOT/cvmfsexec" ]] || return 1
    command -v newuidmap >/dev/null || return 1
    command -v newgidmap >/dev/null || return 1
    IFS=: read -r uid_start uid_count < <(awk -F: '$1 == "root" { print $2 ":" $3; exit }' /etc/subuid)
    IFS=: read -r gid_start gid_count < <(awk -F: '$1 == "root" { print $2 ":" $3; exit }' /etc/subgid)
    [[ "$uid_start" == 1 && "$gid_start" == 1 && -n "$uid_count" && -n "$gid_count" ]] || return 1
    # The service IDs are passed as positional parameters to the namespace shell.
    # shellcheck disable=SC2016
    unshare --user --map-user 0 --map-group 0 \
        --map-users="1:${uid_start}:${uid_count}" --map-groups="1:${gid_start}:${gid_count}" \
        bash -c 'setpriv --reuid="$1" --regid="$2" --clear-groups true && setpriv --reuid="$3" --regid="$4" --clear-groups true' \
        bash "${GALAXY_UID:-1450}" "${GALAXY_GID:-1450}" \
        "${GALAXY_POSTGRES_UID:-1550}" "${GALAXY_POSTGRES_GID:-1550}" \
        >/dev/null 2>&1
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
        if cvmfs_repositories_available; then
            CVMFS_RESOLVED_MODE=external
        elif cvmfs_has_cap_sys_admin; then
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
            echo "CVMFS userspace mode requires /dev/fuse, newuidmap/newgidmap, and subordinate ID mappings that cover the Galaxy service accounts." >&2
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
    system)
        if ! cvmfs_has_cap_sys_admin; then
            echo "CVMFS system mode requires CAP_SYS_ADMIN." >&2
            exit 1
        fi
        CVMFS_RESOLVED_MODE=system
        ;;
    disabled)
        CVMFS_RESOLVED_MODE=disabled
        ;;
    *)
        echo "Unsupported CVMFS_MODE '${CVMFS_MODE}'. Expected auto, userspace, system, external, or disabled." >&2
        exit 1
        ;;
esac

export CVMFS_RESOLVED_MODE
echo "CVMFS mode: ${CVMFS_RESOLVED_MODE}" >&2

if [[ "$CVMFS_RESOLVED_MODE" == userspace ]]; then
    configure_userspace_cache
    export CVMFS_USERSPACE_ACTIVE=true
    exec "$CVMFS_USERSPACE_ROOT/cvmfsexec" "${CVMFS_REPOSITORY_LIST[@]}" -- "$@"
fi

exec "$@"
