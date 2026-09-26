"""Exercise appliance routing without Docker or namespace privileges."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ContainerRoutingTest(unittest.TestCase):
    def configure(self, *, privileged=False, userspace=False, destination="", arguments="",
                  repositories="data.galaxyproject.org singularity.galaxyproject.org", docker=False):
        script = '''
source "$1/galaxy/cvmfs-functions.sh"
cvmfs_set_repositories
source "$1/galaxy/container-functions.sh"
singularity() { :; }
# Override detection so neither host binaries nor a host socket affect routing.
galaxy_docker_available() { [[ "$TEST_DOCKER_AVAILABLE" == true ]]; }
log_info() { routing_level=info; }
log_warn() { routing_level=warning; }
galaxy_configure_container_routing log_info log_warn
printf '%s\\n' "$routing_level" >&2
printf '%s\\n' "$GALAXY_DESTINATIONS_DEFAULT" "${GALAXY_SINGULARITY_RUN_EXTRA_ARGUMENTS:-}"
'''
        env = {"PATH": "/usr/bin:/bin", "PRIVILEGED": str(privileged).lower(),
               "CVMFS_USERSPACE_ACTIVE": str(userspace).lower(),
               "GALAXY_DESTINATIONS_DEFAULT": destination,
               "GALAXY_SINGULARITY_RUN_EXTRA_ARGUMENTS": arguments,
               "CVMFS_REPOSITORIES": repositories, "TEST_DOCKER_AVAILABLE": str(docker).lower()}
        result = subprocess.run(["bash", "-e", "-c", script, "bash", str(ROOT)],
                                env=env, text=True, capture_output=True, check=True)
        self.routing_level = result.stderr.strip()
        return result.stdout.splitlines()

    def test_userspace_selects_singularity_without_privileged(self):
        self.assertEqual(self.configure(userspace=True, destination="slurm_cluster"),
                         ["slurm_cluster_singularity", "--userns"])

    def test_privileged_routing_does_not_add_userns(self):
        self.assertEqual(self.configure(privileged=True), ["slurm_cluster_singularity", ""])

    def test_explicit_destination_is_preserved(self):
        self.assertEqual(self.configure(userspace=True, destination="local_no_container"),
                         ["local_no_container", "--userns"])

    def test_userspace_arguments_preserve_custom_options(self):
        self.assertEqual(self.configure(userspace=True, arguments="--writable-tmpfs"),
                         ["slurm_cluster_singularity", "--userns --writable-tmpfs"])

    def test_privileged_routing_preserves_custom_arguments(self):
        self.assertEqual(self.configure(privileged=True, arguments="--writable-tmpfs"),
                         ["slurm_cluster_singularity", "--writable-tmpfs"])

    def test_userspace_without_image_repository_uses_plain_slurm(self):
        self.assertEqual(self.configure(userspace=True, destination="slurm_cluster",
                                        repositories="data.galaxyproject.org"),
                         ["slurm_cluster", ""])

    def test_privileged_routing_is_independent_of_requested_repositories(self):
        self.assertEqual(self.configure(privileged=True, repositories="data.galaxyproject.org"),
                         ["slurm_cluster_singularity", ""])

    def test_userspace_without_image_repository_uses_available_docker(self):
        self.assertEqual(self.configure(userspace=True, repositories="data.galaxyproject.org", docker=True),
                         ["slurm_cluster_docker", ""])

    def test_unprivileged_without_userspace_uses_plain_slurm_and_warns(self):
        self.assertEqual(self.configure(), ["slurm_cluster", ""])
        self.assertEqual(self.routing_level, "warning")

    def test_unprivileged_without_userspace_uses_available_docker(self):
        self.assertEqual(self.configure(docker=True), ["slurm_cluster_docker", ""])
        self.assertEqual(self.routing_level, "info")


if __name__ == "__main__":
    unittest.main()
