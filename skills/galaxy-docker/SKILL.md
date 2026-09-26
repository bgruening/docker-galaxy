---
name: galaxy-docker
description: Maintain and upgrade the bgruening/docker-galaxy project: bump Galaxy/Ubuntu versions, update Ansible roles and scheduler support, adjust startup/CI/tests, and manage CVMFS.
---

# Galaxy Docker skill

Use this skill when working in the `bgruening/docker-galaxy` repo to upgrade Galaxy releases or refresh runtime, scheduler, CVMFS, and CI behavior.

## Quick start workflow

1. **Define targets**: Galaxy release, Ubuntu base, scheduler expectations (Slurm/HTCondor), and CI scope.
2. **Update build**: `galaxy/Dockerfile` (release ARGs, build stages, slurm-drmaa, uv usage, npm cleanup).
3. **Update Ansible**: `galaxy/ansible/requirements.yml` and playbooks (`rabbitmq.yml`, `condor.yml`, `slurm.yml`, `nginx.yml`, `proftpd.yml`).
4. **Update runtime**: `galaxy/startup2.sh` (default) and `galaxy/ansible/templates/export_user_files.py.j2`. The old `startup.sh` is a deprecated fallback until 27.0.
5. **CVMFS changes**: `galaxy/cvmfs-entrypoint.sh`, `galaxy/cvmfs-functions.sh`, and resolver config. Mount within the Galaxy container; no bundled sidecar is maintained.
6. **Tests/CI**: `test/` scripts and `.github/workflows/` (buildx caches, test orchestration).
7. **Run tests**: Use both `--privileged` and non-privileged runs where relevant.

## Repo map (files to touch)

- Build: `galaxy/Dockerfile`
- Startup: `galaxy/startup.sh`, `galaxy/startup2.sh`
- Galaxy config export: `galaxy/ansible/templates/export_user_files.py.j2`
- Ansible roles: `galaxy/ansible/requirements.yml`
- Services: `galaxy/ansible/rabbitmq.yml`, `galaxy/ansible/condor.yml`, `galaxy/ansible/slurm.yml`, `galaxy/ansible/nginx.yml`, `galaxy/ansible/proftpd.yml`
- Slurm config template: `galaxy/ansible/templates/configure_slurm.py.j2`
- Container resolvers: `galaxy/ansible/templates/container_resolvers_conf.yml.j2`
- CVMFS: `galaxy/cvmfs-entrypoint.sh`, `galaxy/cvmfs-functions.sh`, `galaxy/ansible/cvmfs_client.yml`
- Tests: `test/bioblend/`, `test/slurm/`, `test/gridengine/`, `test/cvmfs/`, `test/container_resolvers_conf.ci.yml`
- CI: `.github/workflows/*.yml` and `.github/workflows/single.sh`

## Guardrails and expectations

- Keep Python installs on `uv` (build and runtime). Avoid `pip install` directly.
- Prefer buildx cache mounts in Dockerfiles and `cache-to/cache-from` in GitHub Actions.
- Use `--rm` for test containers and clean up by name to avoid conflicts.
- If `/tmp` fills up on CI, use `TMPDIR=/var/tmp` for heavy Docker tests.
- `/usr/bin/startup` uses `startup2.sh`; `/usr/bin/startup2` aliases the same implementation. Retain `/usr/bin/startup-legacy` until its scheduled removal in 27.0.

## CVMFS

- Privileged runs use full CVMFS client + autofs.
- Userspace runs use the documented FUSE, namespace, and AppArmor configuration.
- The Compose wrapper starts a single Galaxy container without a CVMFS sidecar.
- Container resolver config should include cached mulled paths on both CVMFS and `/export`.
- See the README for current launch commands; `references/upgrade-25.1.md` describes historical decisions.

## Slurm

- Ensure Slurm works in containers without systemd/cgroup v2 requirements.
- `configure_slurm.py.j2` writes `cgroup.conf` with `CgroupPlugin=disabled`.
- Slurm-DRMAA is built from source when ABI mismatches exist (documented in references).

## Tests (typical order)

- `test/slurm/test.sh` (set `GALAXY_IMAGE=galaxy:test` if needed)
- `test/gridengine/test.sh` (uses ephemeris container for wait)
- `test/bioblend/test.sh`
- `test/cvmfs/test-userspace.sh` (mounting and reference data)
- `GALAXY_SMOKE_CVMFS_TOOL_TEST=true test/cvmfs/test-userspace.sh` (amd64 Slurm/Singularity job)
- `bash test/interactive/test-interactive.sh` (privileged Docker IT lifecycle)
- `test/smoke.sh` (default startup readiness)

## References

- `references/upgrade-25.1.md` for 25.1 upgrade decisions, pins, and pitfalls.
