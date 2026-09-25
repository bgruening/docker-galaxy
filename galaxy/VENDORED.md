# Vendored files

## `galaxy-dir-sync.py`

- Source: <https://git.embl.de/grp-gbcs/galaxy-dir-sync/raw/master/src/galaxy-dir-sync.py>
- Vendored: 2026-09-21
- Upstream SHA-256: `4c060f1aeec1170bff4e6c72f4fc0d7338ce924eac5b3920546a5a384bc4891e`

The file is stored in this repository because the upstream GitLab instance
rejects or times out requests from GitHub Actions runners. Update the vendored
copy deliberately and record its new checksum here.

## `cvmfsexec`

- Source: <https://github.com/cvmfs/cvmfsexec>
- Version: `v4.54`
- CVMFS client: `2.14.1`

The Docker build pins and assembles cvmfsexec in a dedicated stage, then copies
the self-contained distribution into `/opt/cvmfsexec`. Update both version
arguments in `galaxy/Dockerfile` deliberately and test amd64 and arm64 images.
