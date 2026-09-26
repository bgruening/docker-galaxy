# 25.1 upgrade reference (docker-galaxy)

This reference captures the key decisions, pins, and fixes applied during the 25.1 upgrade.
Use it as a **lessons-learned checklist** and re-validate each item for the next release.

Historical note: the bundled CVMFS sidecar, its Compose profile, and its dedicated
test/workflow were removed during development for 26.2. The current image supports
userspace CVMFS and defaults to `startup2.sh`; consult the README for current commands.

## Base versions and build decisions

- **Ubuntu base**: `ubuntu:24.04` in `galaxy/Dockerfile` (`galaxy_cluster_base` stage).
- **Galaxy release**: set via `ARG GALAXY_RELEASE` in `galaxy/Dockerfile` (target `release_25.1`).
- **gx-it-proxy**: preinstalled via npm during build, then npm removed to save space.
- **Python installs**: migrate to `uv` for optional dependencies and tests.
- **jemalloc**: custom build kept for Grid Engine compatibility (see comment in Dockerfile).

## Slurm and slurm-drmaa (25.1-specific)

- **Slurm version**: for 25.1 on Ubuntu 24.04, Slurm 24.11 was required for ABI compatibility in this image. Re-check available packages and ABI compatibility each upgrade.
- **Slurm-DRMAA**: built from source in a dedicated build stage because the natefoo PPA binaries were built against Slurm 23.11 and broke at runtime with 24.11.
  - Build stage in `galaxy/Dockerfile` has a large comment that explains this as temporary and should be removed once 24.11-compatible packages are available.
- **Cgroups**: container-friendly configuration writes `/etc/slurm/cgroup.conf` with `CgroupPlugin=disabled` (via `configure_slurm.py.j2`).
- **Runtime config**: `configure_slurm.py.j2` merges `slurmd -C`, `lscpu -J`, and `/proc/meminfo` to avoid hardware mismatch errors; also forces `TaskPlugin=task/none`, `JobAcctGatherType=jobacct_gather/none`, `MpiDefault=none`, `ProctrackType=proctrack/pgid`.

## RabbitMQ

- Use Team RabbitMQ repositories (per rabbitmq.com install instructions).
- Pin `rabbitmq_version` in `galaxy/ansible/rabbitmq.yml`.
- Install Erlang packages explicitly and enable `rabbitmq_management`.

## HTCondor

- Prefer upstream roles and official repositories when they support the target OS and version.
- If upstream lags (e.g., no packages yet), document the temporary workaround and remove it once upstream catches up.

## CVMFS

- Main container supports CVMFS only in `--privileged` mode.
- Sidecar container added under `cvmfs/` with autofs and a minimal Ansible playbook.
- Compose profile `cvmfs` in `galaxy/docker-compose.yaml` uses rshared mount propagation so the Galaxy container sees CVMFS mounts.
- Container resolver config adds cached mulled paths:
  - `/cvmfs/singularity.galaxyproject.org/all`
  - `/export/container_cache/singularity/mulled`

## Startup scripts

- `startup2` adds colored logging, runtime summary, and a `GALAXY_*` env summary with masking.
- CVMFS messaging avoids early warnings by skipping manual mounts when autofs is configured.
- `startup2` and `startup.sh` call `/root/cgroupfs_mount.sh true` to avoid the "No command specified" warning.
- Optional dependency installs use `uv` when `LOAD_GALAXY_CONDITIONAL_DEPENDENCIES` is set.
- Creates `/tmp/slurm`, `/var/log/slurm`, and `/var/lib/slurm/slurmctld` to avoid missing state file errors.

## Job handlers

- `galaxy/ansible/galaxy_job_conf.yml` ensures `job_handler_assignment_method: db-skip-locked` when dynamic handlers are enabled.
- `galaxy/Dockerfile` runs `ansible-playbook /ansible/galaxy_job_conf.yml` after copying the `galaxy.yml.sample` so the setting persists in the built image.

## CI and tests

- Buildx caching enabled in workflows; `single.sh` uses buildx with cache-to/cache-from.
- `test/container_resolvers_conf.ci.yml` keeps resolver tests fast.
- `test/cvmfs/test.sh` validates mount propagation from sidecar to Galaxy.
- `test/gridengine/test.sh` uses ephemeris container to `galaxy-wait`.
- `test/bioblend` updated for Galaxy 25.1 and newer Bioblend.

## Known pitfalls and fixes

- **CVMFS warnings on startup**: resolved by checking autofs config before manual mounts.
- **Munge readiness**: add a wait loop and configurable `MUNGE_NUM_THREADS` (default 2).
- **Dynamic handler warning in Gravity**: fix by setting `job_handler_assignment_method` via Ansible.
- **No command specified**: avoid by running `/root/cgroupfs_mount.sh true` instead of no args.
- **/tmp full on CI**: run tests with `TMPDIR=/var/tmp`.

## Files touched during the 25.1 upgrade

High-signal files for reference:

- `galaxy/Dockerfile`
- `galaxy/startup.sh`, `galaxy/startup2.sh`
- `galaxy/ansible/requirements.yml`
- `galaxy/ansible/rabbitmq.yml`, `galaxy/ansible/condor.yml`, `galaxy/ansible/slurm.yml`
- `galaxy/ansible/templates/configure_slurm.py.j2`
- `galaxy/ansible/templates/container_resolvers_conf.yml.j2`
- `galaxy/ansible/templates/export_user_files.py.j2`
- `galaxy/docker-compose.yaml`
- `cvmfs/` (sidecar)
- `test/` (slurm, gridengine, bioblend, cvmfs)
- `.github/workflows/` (buildx caching, single-container tests, CVMFS workflow)
