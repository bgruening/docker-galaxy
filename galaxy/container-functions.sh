#!/usr/bin/env bash

galaxy_docker_available() {
    [ -S /var/run/docker.sock ] || command -v docker >/dev/null 2>&1
}

# Shared by both startup implementations; initialize CVMFS repositories first.
galaxy_configure_container_routing() {
    local routing_log=${1:-echo}
    local routing_warn=${2:-$routing_log}
    local docker_ok singularity_cmd singularity_ok dest_default dest_docker
    docker_ok=false
    if galaxy_docker_available; then
        docker_ok=true
    fi

    singularity_cmd=""
    if command -v singularity >/dev/null 2>&1; then
        singularity_cmd="singularity"
    elif command -v apptainer >/dev/null 2>&1; then
        singularity_cmd="apptainer"
    fi

    singularity_ok=false
    if {
        ${PRIVILEGED:-false} || {
            [[ "${CVMFS_USERSPACE_ACTIVE:-false}" == true ]] &&
                cvmfs_repository_requested singularity.galaxyproject.org
        }
    } && [ -n "$singularity_cmd" ]; then
        singularity_ok=true
        if [[ "${CVMFS_USERSPACE_ACTIVE:-false}" == true ]]; then
            # Avoid Singularity's setuid path inside cvmfsexec's user namespace.
            case " ${GALAXY_SINGULARITY_RUN_EXTRA_ARGUMENTS:-} " in
                *" --userns "*) ;;
                *) export GALAXY_SINGULARITY_RUN_EXTRA_ARGUMENTS="--userns${GALAXY_SINGULARITY_RUN_EXTRA_ARGUMENTS:+ $GALAXY_SINGULARITY_RUN_EXTRA_ARGUMENTS}" ;;
            esac
        fi
    fi

    dest_default="${GALAXY_DESTINATIONS_DEFAULT:-}"
    dest_docker="${GALAXY_DESTINATIONS_DOCKER_DEFAULT:-}"

    if [ -z "$dest_default" ] || { $singularity_ok && [ "$dest_default" = "slurm_cluster" ]; }; then
        if $singularity_ok; then
            dest_default="slurm_cluster_singularity"
        elif $docker_ok; then
            dest_default="slurm_cluster_docker"
        else
            dest_default="slurm_cluster"
        fi
        export GALAXY_DESTINATIONS_DEFAULT="$dest_default"
    fi

    if [ -z "$dest_docker" ]; then
        if $docker_ok; then
            dest_docker="slurm_cluster_docker"
        else
            dest_docker="$dest_default"
        fi
        export GALAXY_DESTINATIONS_DOCKER_DEFAULT="$dest_docker"
    else
        dest_docker="$GALAXY_DESTINATIONS_DOCKER_DEFAULT"
    fi

    if $singularity_ok; then
        export SINGULARITY_CACHEDIR="${SINGULARITY_CACHEDIR:-/export/container_cache/singularity/mulled}"
        export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-$SINGULARITY_CACHEDIR}"
        "$routing_log" "Container routing: default -> ${dest_default} (Singularity via ${singularity_cmd}); Docker -> ${dest_docker}"
    elif $docker_ok; then
        "$routing_log" "Container routing: default -> ${dest_default} (Docker socket detected); Docker -> ${dest_docker}"
    else
        "$routing_warn" "Container routing: no Docker/Singularity detected; using ${dest_default}"
    fi
}
