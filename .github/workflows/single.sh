#!/bin/bash
set -ex

failure_diagnostics() {
    exit_code=$?
    trap - EXIT

    if [[ $exit_code -eq 0 ]]; then
        exit 0
    fi

    set +e
    set +x
    echo "Single-container test failed with exit code ${exit_code}."

    echo "::group::Host and Docker resources"
    df -h
    docker system df
    docker ps -a
    echo "::endgroup::"

    if docker inspect galaxy >/dev/null 2>&1; then
        echo "::group::Galaxy container state"
        docker inspect --format '{{json .State}}' galaxy
        docker stats --no-stream galaxy
        echo "::endgroup::"

        echo "::group::Galaxy container logs"
        docker logs --tail 1000 galaxy
        echo "::endgroup::"

        echo "::group::Galaxy service status"
        docker exec galaxy supervisorctl status
        echo "::endgroup::"

        echo "::group::Galaxy service logs"
        docker exec galaxy bash -c '
            for log_file in \
                /home/galaxy/logs/*.log \
                /var/log/nginx/*.log \
                /var/log/supervisor/*.log; do
                if [[ -f "$log_file" ]]; then
                    echo "===== $log_file ====="
                    tail -n 200 "$log_file"
                fi
            done
        '
        echo "::endgroup::"
    fi

    exit "$exit_code"
}

trap failure_diagnostics EXIT

docker --version
docker info

export GALAXY_HOME=/home/galaxy
export GALAXY_USER=admin@example.org
export GALAXY_USER_EMAIL=admin@example.org
export GALAXY_USER_PASSWD=password
export BIOBLEND_GALAXY_API_KEY=fakekey
export BIOBLEND_GALAXY_URL=http://localhost:8080
export EPHEMERIS_IMAGE=${EPHEMERIS_IMAGE:-quay.io/biocontainers/ephemeris:0.10.11--pyhdfd78af_0}
export GALAXY_WAIT_TIMEOUT=${GALAXY_WAIT_TIMEOUT:-600}

SKIP_SFTP=false
SKIP_DIVE=false

if [[ "${CI:-}" == "true" ]]; then
    sudo apt-get update -qq
    #sudo apt-get install docker-ce --no-install-recommends -y -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew"
    sudo apt-get install sshpass --no-install-recommends -y
else
    if ! command -v sshpass >/dev/null 2>&1; then
        echo "sshpass not found; skipping SFTP test."
        SKIP_SFTP=true
    fi
fi

if [[ "${CI:-}" == "true" ]]; then
    DIVE_VERSION=$(curl -sL "https://api.github.com/repos/wagoodman/dive/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -OL https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb
    sudo apt install ./dive_${DIVE_VERSION}_linux_amd64.deb
    rm ./dive_${DIVE_VERSION}_linux_amd64.deb
else
    if ! command -v dive >/dev/null 2>&1; then
        echo "dive not found; skipping image analysis."
        SKIP_DIVE=true
    fi
fi

galaxy_wait() {
    docker run --rm --link galaxy:galaxy \
        "${EPHEMERIS_IMAGE}" galaxy-wait -g http://galaxy --timeout "${1:-$GALAXY_WAIT_TIMEOUT}"
}

# start building this repo
if [[ "${CI:-}" == "true" ]]; then
    sudo chown 1450 /tmp && sudo chmod a=rwx /tmp
fi

## define a container size check function, first parameter is the container name, second the max allowed size in MB
container_size_check () {

    # check that the image size is not growing too much between releases
    # the 19.05 monolithic image was around 1.500 MB
    size="${docker image inspect $1 --format='{{.Size}}'}"
    size_in_mb=$(($size/(1024*1024)))
    if [[ $size_in_mb -ge $2 ]]
    then
        echo "The new compiled image ($1) is larger than allowed. $size_in_mb vs. $2"
        sleep 2
        #exit
    fi
}

export WORKING_DIR=${GITHUB_WORKSPACE:-$PWD}

export DOCKER_RUN_CONTAINER="quay.io/bgruening/galaxy"
SAMPLE_TOOLS=$GALAXY_HOME/ephemeris/sample_tool_list.yaml
GALAXY_EXTRA_MOUNTS=()
if [ -f "$WORKING_DIR/test/container_resolvers_conf.ci.yml" ]; then
    GALAXY_EXTRA_MOUNTS+=(-v "$WORKING_DIR/test/container_resolvers_conf.ci.yml:/etc/galaxy/container_resolvers_conf.yml:ro")
fi
cd "$WORKING_DIR"
docker buildx build \
    --load \
    --cache-from type=gha \
    --cache-to type=gha,mode=max \
    -t quay.io/bgruening/galaxy \
    galaxy/
#container_size_check   quay.io/bgruening/galaxy  1500

# Check userspace mounting before the lengthy Bioblend suite.
if [[ "${CI:-}" == "true" ]]; then
    sudo apparmor_parser -r galaxy/cvmfs-apparmor.profile
    GALAXY_SMOKE_APPARMOR_PROFILE=galaxy-cvmfs-userspace \
    GALAXY_SMOKE_CVMFS_TOOL_TEST=true \
    GALAXY_CVMFS_TEST_IMAGE="$DOCKER_RUN_CONTAINER" \
        bash test/cvmfs/test-userspace.sh
fi

docker rm -f galaxy httpstest || true
mkdir -p local_folder
docker run -d -p 8080:80 -p 8021:21 -p 8022:22 \
    --name galaxy \
    --privileged=true \
    -v "$(pwd)/local_folder:/export/" \
    "${GALAXY_EXTRA_MOUNTS[@]}" \
    -e GALAXY_CONFIG_ALLOW_USER_DATASET_PURGE=True \
    -e GALAXY_CONFIG_ALLOW_PATH_PASTE=True \
    -e GALAXY_CONFIG_ALLOW_USER_DELETION=True \
    -e GALAXY_CONFIG_ENABLE_BETA_WORKFLOW_MODULES=True \
    -v /tmp/:/tmp/ \
    quay.io/bgruening/galaxy

sleep 30
docker logs galaxy
# Define start functions
docker_exec() {
      cd "$WORKING_DIR"
      docker exec galaxy "$@"
}
docker_exec_run() {
   cd "$WORKING_DIR"
   docker run quay.io/bgruening/galaxy "$@"
}
docker_run() {
   cd "$WORKING_DIR"
   docker run "$@"
}

docker ps

# Test submitting jobs to an external slurm cluster
cd "${WORKING_DIR}/test/slurm/" && bash test.sh && cd "$WORKING_DIR"

# Test submitting jobs to an external gridengine cluster
cd $WORKING_DIR/test/gridengine/ && bash test.sh || exit 1 && cd $WORKING_DIR

echo "SLURM and SGE tests have finished."

docker ps
echo 'Waiting for Galaxy to come up.'
galaxy_wait_timeout=$GALAXY_WAIT_TIMEOUT
galaxy_wait_interval=30
galaxy_wait_end=$((SECONDS + galaxy_wait_timeout))
while [ $SECONDS -lt $galaxy_wait_end ]; do
    if galaxy_wait 30; then
        break
    fi
    echo "Galaxy still starting, tailing logs..."
    docker logs --tail 200 galaxy || true
    sleep $galaxy_wait_interval
done
if [ $SECONDS -ge $galaxy_wait_end ]; then
    echo "Galaxy did not become ready within ${galaxy_wait_timeout}s."
    docker logs --tail 400 galaxy || true
    exit 1
fi

curl -v --fail $BIOBLEND_GALAXY_URL/api/version

# Test self-signed HTTPS
docker_run -d --name httpstest -p 443:443 -e "USE_HTTPS=True" $DOCKER_RUN_CONTAINER
sleep 30
docker logs httpstest

sleep 180s && curl -v -k --fail https://127.0.0.1:443/api/version
echo | openssl s_client -connect 127.0.0.1:443 2>/dev/null | openssl x509 -issuer -noout| grep localhost

docker rm -f httpstest || true

# Test FTP Server upload
date > time.txt
# FIXME passive mode does not work, it would require the container to run with --net=host
#curl -v --fail -T time.txt ftp://localhost:8021 --user $GALAXY_USER:$GALAXY_USER_PASSWD || true
# Test FTP Server get
#curl -v --fail ftp://localhost:8021 --user $GALAXY_USER:$GALAXY_USER_PASSWD

# Test SFTP Server
if [[ "$SKIP_SFTP" != "true" ]]; then
    sshpass -p $GALAXY_USER_PASSWD sftp -v -P 8022 -o User=$GALAXY_USER -o "StrictHostKeyChecking no" localhost <<< $'put time.txt'
fi

# Test FTP Server from within the container (avoids host NAT/passive issues)
docker_exec python - <<'PY'
import ftplib

ftp = ftplib.FTP()
ftp.connect("localhost", 21, timeout=30)
ftp.login("admin@example.org", "password")
ftp.retrlines("LIST")
ftp.quit()
PY

# Test CVMFS
docker_exec bash -c "service autofs start"
docker_exec bash -c "cvmfs_config chksetup"
docker_exec bash -c "ls /cvmfs/data.galaxyproject.org/byhand"

# Run a ton of BioBlend test against our servers.
cd "$WORKING_DIR/test/bioblend/" && . ./test.sh && cd "$WORKING_DIR/"

# Test without install-repository wrapper
curl -v --fail POST -H "Content-Type: application/json" -H "x-api-key: fakekey" -d \
    '{
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "name": "cut_columns",
        "owner": "devteam",
        "changeset_revision": "cec635fab700",
        "new_tool_panel_section_label": "BEDTools"
    }' \
"http://localhost:8080/api/tool_shed_repositories"


# Test the 'new' tool installation script
docker_exec install-tools "$SAMPLE_TOOLS"
# Test the Conda installation
docker_exec_run bash -c 'export PATH=$GALAXY_CONFIG_TOOL_DEPENDENCY_DIR/_conda/bin/:$PATH && conda --version && conda install samtools -c bioconda --yes'

# Test if data persistence works
docker stop galaxy
docker rm -f galaxy

cd "$WORKING_DIR"
docker run -d -p 8080:80 \
    --name galaxy \
    --privileged=true \
    -v "$(pwd)/local_folder:/export/" \
    "${GALAXY_EXTRA_MOUNTS[@]}" \
    -e GALAXY_CONFIG_ALLOW_USER_DATASET_PURGE=True \
    -e GALAXY_CONFIG_ALLOW_PATH_PASTE=True \
    -e GALAXY_CONFIG_ALLOW_USER_DELETION=True \
    -e GALAXY_CONFIG_ENABLE_BETA_WORKFLOW_MODULES=True \
    -v /tmp/:/tmp/ \
    quay.io/bgruening/galaxy

echo 'Waiting for Galaxy to come up.'
galaxy_wait "$GALAXY_WAIT_TIMEOUT"

# Test if the tool installed previously is available
curl -v --fail 'http://localhost:8080/api/tools/toolshed.g2.bx.psu.edu/repos/devteam/cut_columns/Cut1/1.0.2'

# analyze image using dive tool
if [[ "$SKIP_DIVE" == "true" ]]; then
    echo "Skipping dive image analysis (dive not installed)."
else
    CI=true dive quay.io/bgruening/galaxy
fi

docker stop galaxy
docker rm -f galaxy
docker rmi -f $DOCKER_RUN_CONTAINER || true
