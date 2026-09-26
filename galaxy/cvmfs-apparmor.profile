abi <abi/4.0>,
include <tunables/global>

# Broadly unconfined, like apparmor=unconfined, with explicit permission to
# retain capabilities inside user namespaces on Ubuntu 24.04 and newer.
profile galaxy-cvmfs-userspace flags=(unconfined) {
    userns,
}
