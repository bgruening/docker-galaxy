#!/usr/bin/env bash

cvmfs_set_repositories() {
    local repositories=${CVMFS_REPOSITORIES:-data.galaxyproject.org singularity.galaxyproject.org}
    repositories=${repositories//,/ }
    read -r -a CVMFS_REPOSITORY_LIST <<< "$repositories"
}

cvmfs_repository_available() {
    [[ -r "/cvmfs/$1/.cvmfspublished" ]]
}

cvmfs_repository_requested() {
    local requested_repository
    for requested_repository in "${CVMFS_REPOSITORY_LIST[@]}"; do
        [[ "$requested_repository" == "$1" ]] && return 0
    done
    return 1
}

cvmfs_repositories_available() {
    local repository
    for repository in "${CVMFS_REPOSITORY_LIST[@]}"; do
        cvmfs_repository_available "$repository" || return 1
    done
}

cvmfs_has_capability() {
    local mask=$1
    local effective
    effective=$(awk '/^CapEff:/ { print $2 }' /proc/self/status)
    (( (0x${effective:-0} & mask) != 0 ))
}

cvmfs_has_cap_sys_admin() {
    cvmfs_has_capability 0x200000
}

cvmfs_resolve_startup_mode() {
    if [[ -n "${CVMFS_RESOLVED_MODE:-}" ]]; then
        return
    fi

    if [[ "${CVMFS_USERSPACE_ACTIVE:-false}" == "true" ]]; then
        CVMFS_RESOLVED_MODE=userspace
    elif cvmfs_repositories_available; then
        CVMFS_RESOLVED_MODE=external
    elif [[ "${PRIVILEGED:-false}" == "true" ]]; then
        # Preserve the pre-entrypoint behavior for downstream images and
        # explicit --entrypoint invocations.
        CVMFS_RESOLVED_MODE=system
    else
        CVMFS_RESOLVED_MODE=disabled
    fi
    export CVMFS_RESOLVED_MODE
}

cvmfs_configure_autofs() {
    local supervisor_config=/etc/supervisor/conf.d/galaxy.conf
    local autostart=false
    [[ "$CVMFS_RESOLVED_MODE" == system ]] && autostart=true

    if [[ -f "$supervisor_config" ]]; then
        sed -i \
            "/^\[program:autofs\]/,/^\[/ s/^autostart[[:space:]]*=.*/autostart       = ${autostart}/" \
            "$supervisor_config"
    fi
}

cvmfs_mount_repositories() {
    local repository repo_dir
    chmod 666 /dev/fuse 2>/dev/null || true
    for repository in "${CVMFS_REPOSITORY_LIST[@]}"; do
        repo_dir="/cvmfs/$repository"
        mkdir -p "$repo_dir"
        if ! mountpoint -q "$repo_dir"; then
            echo "Mounting CVMFS repo $repository"
            mount -t cvmfs "$repository" "$repo_dir" || echo "Warning: failed to mount $repository"
        fi
    done
}

cvmfs_create_placeholders() {
    local repository repo_dir
    for repository in "${CVMFS_REPOSITORY_LIST[@]}"; do
        cvmfs_repository_available "$repository" && continue
        repo_dir="/cvmfs/$repository"
        mkdir -p "$repo_dir"
        chown "$GALAXY_USER:$GALAXY_USER" "$repo_dir"
        if [[ "$repository" == singularity.galaxyproject.org ]]; then
            mkdir -p "$repo_dir/all"
            chown "$GALAXY_USER:$GALAXY_USER" "$repo_dir/all"
        fi
    done
}

cvmfs_prepare_mounts() {
    local system_strategy=${1:-explicit}
    local autofs_configured=false

    cvmfs_resolve_startup_mode
    cvmfs_configure_autofs

    if [[ -f /etc/auto.cvmfs || -f /etc/auto.master.d/cvmfs.autofs ]]; then
        autofs_configured=true
    fi

    case "$CVMFS_RESOLVED_MODE" in
        userspace)
            echo "CVMFS repositories are mounted in the userspace namespace."
            ;;
        external)
            echo "Using externally mounted CVMFS repositories."
            ;;
        disabled)
            echo "CVMFS mounts are disabled."
            ;;
        system)
            if ! command -v mount.cvmfs >/dev/null 2>&1; then
                echo "Info: CVMFS client not available; install CVMFS or use the sidecar via docker-compose --profile cvmfs."
            elif [[ "$system_strategy" == autofs && "$autofs_configured" == true ]]; then
                echo "CVMFS autofs is configured; repositories will mount on first access."
            else
                cvmfs_mount_repositories
            fi
            ;;
        *)
            echo "Info: CVMFS mounts are unavailable in runtime mode '$CVMFS_RESOLVED_MODE'."
            ;;
    esac

    cvmfs_available=false
    cvmfs_tool_data_enabled=false
    if [[ "$CVMFS_RESOLVED_MODE" != disabled ]]; then
        cvmfs_repositories_available && cvmfs_available=true
        if cvmfs_repository_requested data.galaxyproject.org; then
            if [[ "$CVMFS_RESOLVED_MODE" == system ]]; then
                # In autofs mode the files become readable only after
                # supervisord starts automount. Preserve the historic system
                # mode contract and let Galaxy's first access trigger it.
                cvmfs_tool_data_enabled=true
            elif cvmfs_repository_available data.galaxyproject.org \
                && [[ -r /cvmfs/data.galaxyproject.org/byhand/location/tool_data_table_conf.xml ]] \
                && [[ -r /cvmfs/data.galaxyproject.org/managed/location/tool_data_table_conf.xml ]]; then
                cvmfs_tool_data_enabled=true
            fi
        fi
    fi

    $cvmfs_available || cvmfs_create_placeholders
}

cvmfs_enable_tool_data() {
    local byhand=/cvmfs/data.galaxyproject.org/byhand/location/tool_data_table_conf.xml
    local managed=/cvmfs/data.galaxyproject.org/managed/location/tool_data_table_conf.xml

    $cvmfs_tool_data_enabled || return 0
    case ",${GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH:-}," in
        *",${byhand},"*) ;;
        *) GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH="${GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH:+${GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH},}${byhand}" ;;
    esac
    case ",${GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH:-}," in
        *",${managed},"*) ;;
        *) GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH="${GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH:+${GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH},}${managed}" ;;
    esac
    export GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH
}
