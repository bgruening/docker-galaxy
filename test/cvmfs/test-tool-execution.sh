#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
results_dir=${GALAXY_CVMFS_TEST_RESULTS_DIR:-$repo_root/test-results/cvmfs-tools}
planemo_cmd=${GALAXY_CVMFS_TEST_PLANEMO:-planemo}
mkdir -p "$results_dir"

"$planemo_cmd" test \
    --engine external_galaxy \
    --galaxy_url "${GALAXY_CVMFS_TEST_URL:-http://127.0.0.1:8081}" \
    --galaxy_admin_key "${GALAXY_CVMFS_TEST_API_KEY:-fakekey}" \
    --galaxy_user_key "${GALAXY_CVMFS_TEST_API_KEY:-fakekey}" \
    --no_shed_install \
    --no_paste_test_data_paths \
    --test_timeout "${GALAXY_CVMFS_TEST_JOB_TIMEOUT:-300}" \
    --test_output "$results_dir/tool_test_output.html" \
    --test_output_json "$results_dir/tool_test_output.json" \
    --test_output_xunit "$results_dir/tool_test_output.xml" \
    gxid://tools/cvmfs_seqtk_smoke

# Guard against an empty test discovery being reported as a successful run.
python3 - "$results_dir/tool_test_output.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)
tests = report["tests"]
assert len(tests) == 1, f"Expected one seqtk test, found {len(tests)}"
assert tests[0]["data"]["status"] == "success", tests[0]
print("Planemo verified seqtk output from a CVMFS-backed Singularity job.")
PY
