#!/usr/bin/env bash

cvmfs_set_repositories() {
    local repositories=${CVMFS_REPOSITORIES:-data.galaxyproject.org singularity.galaxyproject.org}
    repositories=${repositories//,/ }
    read -r -a CVMFS_REPOSITORY_LIST <<< "$repositories"
}

cvmfs_repository_available() {
    [[ -r "/cvmfs/$1/.cvmfspublished" ]]
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
