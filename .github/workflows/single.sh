#!/bin/bash
set -ex

# Change the default docker data directory as /mnt has more space
sudo mkdir -p /mnt/docker

if [ ! -f /etc/docker/daemon.json ]; then
    echo '{}' | sudo tee /etc/docker/daemon.json
fi

sudo jq '."data-root"="/mnt/docker"' /etc/docker/daemon.json > /tmp/docker_daemon.json
sudo mv /tmp/docker_daemon.json /etc/docker/daemon.json

sudo systemctl daemon-reload && sudo systemctl restart docker

docker --version
docker info

export GALAXY_HOME=/home/galaxy
export GALAXY_USER=admin@example.org
export GALAXY_USER_EMAIL=admin@example.org
export GALAXY_USER_PASSWD=password
export BIOBLEND_GALAXY_API_KEY=fakekey
export BIOBLEND_GALAXY_URL=http://localhost:8080

sudo apt-get update -qq
#sudo apt-get install docker-ce --no-install-recommends -y -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew"
sudo apt-get install sshpass --no-install-recommends -y

DIVE_VERSION=$(curl -sL "https://api.github.com/repos/wagoodman/dive/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -OL https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb
sudo apt install ./dive_${DIVE_VERSION}_linux_amd64.deb
rm ./dive_${DIVE_VERSION}_linux_amd64.deb

pip3 install ephemeris

# start building this repo
sudo chown 1450 /tmp && sudo chmod a=rwx /tmp

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
cd "$WORKING_DIR"
docker build -t quay.io/bgruening/galaxy galaxy/
#container_size_check   quay.io/bgruening/galaxy  1500

mkdir local_folder
docker run -d -p 8080:80 -p 8021:21 -p 8022:22 \
    --name galaxy \
    --privileged=true \
    -v "$(pwd)/local_folder:/export/" \
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

echo 'Waiting for Galaxy to come up.'
galaxy-wait -g $BIOBLEND_GALAXY_URL --timeout 600

curl -v --fail $BIOBLEND_GALAXY_URL/api/version

# Test self-signed HTTPS
docker_run -d --name httpstest -p 443:443 -e "USE_HTTPS=True" $DOCKER_RUN_CONTAINER
sleep 30
docker logs httpstest

sleep 180s && curl -v -k --fail https://127.0.0.1:443/api/version
echo | openssl s_client -connect 127.0.0.1:443 2>/dev/null | openssl x509 -issuer -noout| grep localhost

docker stop httpstest && docker rm httpstest

# Test FTP Server upload
date > time.txt
# FIXME passive mode does not work, it would require the container to run with --net=host
#curl -v --fail -T time.txt ftp://localhost:8021 --user $GALAXY_USER:$GALAXY_USER_PASSWD || true
# Test FTP Server get
#curl -v --fail ftp://localhost:8021 --user $GALAXY_USER:$GALAXY_USER_PASSWD

# Test SFTP Server
sshpass -p $GALAXY_USER_PASSWD sftp -v -P 8022 -o User=$GALAXY_USER -o "StrictHostKeyChecking no" localhost <<< $'put time.txt'

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
    -e GALAXY_CONFIG_ALLOW_USER_DATASET_PURGE=True \
    -e GALAXY_CONFIG_ALLOW_PATH_PASTE=True \
    -e GALAXY_CONFIG_ALLOW_USER_DELETION=True \
    -e GALAXY_CONFIG_ENABLE_BETA_WORKFLOW_MODULES=True \
    -v /tmp/:/tmp/ \
    quay.io/bgruening/galaxy

echo 'Waiting for Galaxy to come up.'
galaxy-wait -g $BIOBLEND_GALAXY_URL --timeout 600

# Test if the tool installed previously is available
curl -v --fail 'http://localhost:8080/api/tools/toolshed.g2.bx.psu.edu/repos/devteam/cut_columns/Cut1/1.0.2'

# analyze image using dive tool
CI=true dive quay.io/bgruening/galaxy

docker stop galaxy
docker rm -f galaxy
docker rmi -f $DOCKER_RUN_CONTAINER
