"""Exercise appliance routing without Docker or namespace privileges."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ContainerRoutingTest(unittest.TestCase):
    def configure(self, *, privileged=False, userspace=False, destination="", arguments=""):
        script = '''
source "$1/galaxy/container-functions.sh"
singularity() { :; }
galaxy_configure_container_routing >/dev/null
printf '%s\\n' "$GALAXY_DESTINATIONS_DEFAULT" "${GALAXY_SINGULARITY_RUN_EXTRA_ARGUMENTS:-}"
'''
        env = {"PATH": "/usr/bin:/bin", "PRIVILEGED": str(privileged).lower(),
               "CVMFS_USERSPACE_ACTIVE": str(userspace).lower(),
               "GALAXY_DESTINATIONS_DEFAULT": destination,
               "GALAXY_SINGULARITY_RUN_EXTRA_ARGUMENTS": arguments}
        result = subprocess.run(["bash", "-e", "-c", script, "bash", str(ROOT)],
                                env=env, text=True, capture_output=True, check=True)
        return result.stdout.splitlines()

    def test_userspace_selects_singularity_without_privileged(self):
        self.assertEqual(self.configure(userspace=True, destination="slurm_cluster"),
                         ["slurm_cluster_singularity", "--userns"])

    def test_privileged_routing_keeps_existing_arguments(self):
        self.assertEqual(self.configure(privileged=True), ["slurm_cluster_singularity", ""])

    def test_explicit_destination_is_preserved(self):
        self.assertEqual(self.configure(userspace=True, destination="local_no_container"),
                         ["local_no_container", "--userns"])

    def test_userspace_arguments_preserve_custom_options(self):
        self.assertEqual(self.configure(userspace=True, arguments="--writable-tmpfs"),
                         ["slurm_cluster_singularity", "--userns --writable-tmpfs"])


if __name__ == "__main__":
    unittest.main()
