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
- Commit: `5d2f9154e2f252b6fdda8bc1674b7ad4dffa6559`
- CVMFS client: `2.14.1`

The Docker build pins and assembles cvmfsexec in a dedicated stage, then copies
the self-contained distribution into `/opt/cvmfsexec`. The local
`cvmfsexec-multi-user.patch` uses the image's subordinate UID/GID ranges and
keeps the launched command in that namespace so Galaxy can switch to its
service accounts. Update the version, commit, and patch deliberately and test
amd64 and arm64 images.

The patch also evaluates default configuration snippets in shell order when
selecting the configuration repository (quoted values and multiple assignments
are supported), and mounts with `allow_other` so Galaxy and PostgreSQL service
identities can read repositories mounted by namespace root.
