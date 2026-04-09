#!/usr/bin/env bash

# This is needed for Docker compose to have a unified alias for the main container.
# Modifying /etc/hosts can only happen during runtime not during build-time
echo "127.0.0.1      galaxy" >> /etc/hosts

# If the Galaxy config file is not in the expected place, copy from the sample
# and hope for the best (that the admin has done all the setup through env vars.)
if [ ! -f $GALAXY_CONFIG_FILE ]
  then
  # this should succesfully copy either .yml or .ini sample file to the expected location
  cp /export/config/galaxy${GALAXY_CONFIG_FILE: -4}.sample $GALAXY_CONFIG_FILE
fi

# Set number of Gunicorn workers via GUNICORN_WORKERS or default to 2
python3 /usr/local/bin/update_yaml_value "${GRAVITY_CONFIG_FILE}" "gravity.gunicorn.workers" "${GUNICORN_WORKERS:-2}" &> /dev/null

# Set number of Celery workers via CELERY_WORKERS or default to 2
python3 /usr/local/bin/update_yaml_value "${GRAVITY_CONFIG_FILE}" "gravity.celery.concurrency" "${CELERY_WORKERS:-2}" &> /dev/null

# Set number of Galaxy handlers via GALAXY_HANDLER_NUMPROCS or default to 2
python3 /usr/local/bin/update_yaml_value "${GRAVITY_CONFIG_FILE}" "gravity.handlers.handler.processes" "${GALAXY_HANDLER_NUMPROCS:-2}" &> /dev/null

# Initialize variables for optional ansible parameters
ANSIBLE_EXTRA_VARS_HTTPS_PROXY_PREFIX=""

# Configure proxy prefix filtering
if [[ ! -z $PROXY_PREFIX ]]
then
    echo "Configuring with proxy prefix: $PROXY_PREFIX"
    export GALAXY_CONFIG_GALAXY_URL_PREFIX="$PROXY_PREFIX"

    # TODO: Set this using GALAXY_CONFIG_INTERACTIVETOOLS_BASE_PATH after gravity config manager is updated to handle env vars properly
    ansible localhost -m replace -a "path=${GALAXY_CONFIG_FILE} regexp='^  #interactivetools_base_path:.*' replace='  interactivetools_base_path: ${PROXY_PREFIX}'" &> /dev/null
    
    python3 /usr/local/bin/update_yaml_value "${GRAVITY_CONFIG_FILE}" "gravity.tusd.extra_args" "-behind-proxy -base-path $PROXY_PREFIX/api/upload/resumable_upload" &> /dev/null

    ansible localhost -m replace -a "path=/etc/flower/flowerconfig.py regexp='^url_prefix.*' replace='url_prefix = \"$PROXY_PREFIX/flower\"'" &> /dev/null

    # Fix path to html assets
    ansible localhost -m replace -a "dest=$GALAXY_CONFIG_DIR/web/welcome.html regexp='(href=\"|\')[/\\w]*(/static)' replace='\\1${PROXY_PREFIX}\\2'" &> /dev/null
    
    # Set some other vars based on that prefix
    if [[ -z "$GALAXY_CONFIG_DYNAMIC_PROXY_PREFIX" ]]
    then
        export GALAXY_CONFIG_DYNAMIC_PROXY_PREFIX="$PROXY_PREFIX/gie_proxy"
    fi

    if [[ ! -z $GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL ]]
    then
        export GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL="${GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL}${PROXY_PREFIX}"
    fi

    if [[ "$USE_HTTPS_LETSENCRYPT" != "False" || "$USE_HTTPS" != "False" ]]
    then
        ANSIBLE_EXTRA_VARS_HTTPS_PROXY_PREFIX="--extra-vars nginx_prefix_location=$PROXY_PREFIX"
    else
        ansible-playbook -c local /ansible/nginx.yml \
        --extra-vars nginx_prefix_location="$PROXY_PREFIX"
    fi
fi

if [ "$USE_HTTPS_LETSENCRYPT" != "False" ]
then
    echo "Settting up letsencrypt"
    PATH=$GALAXY_CONDA_PREFIX/bin/:$PATH ansible-playbook -c local /ansible/nginx.yml \
    --extra-vars '{"nginx_servers": ["galaxy_redirect_ssl", "interactive_tools_redirect_ssl"]}' \
    --extra-vars '{"nginx_ssl_servers": ["galaxy_https", "interactive_tools_https"]}' \
    --extra-vars nginx_ssl_role=usegalaxy_eu.certbot \
    --extra-vars "{\"certbot_domains\": [\"$GALAXY_DOMAIN\"]}" \
    --extra-vars nginx_conf_ssl_certificate_key=/etc/ssl/user/privkey-$GALAXY_USER.pem \
    --extra-vars nginx_conf_ssl_certificate=/etc/ssl/certs/fullchain.pem \
    $ANSIBLE_EXTRA_VARS_HTTPS_PROXY_PREFIX
fi
if [ "$USE_HTTPS" != "False" ]
then
    if [ -f /export/server.key -a -f /export/server.crt ]
    then
        echo "Copying SSL keys"
        ssl_key_content=$(cat /export/server.key | sed 's/$/\\n/' | tr -d '\n')
        ansible-playbook -c local /ansible/nginx.yml \
        --extra-vars '{"nginx_servers": ["galaxy_redirect_ssl", "interactive_tools_redirect_ssl"]}' \
        --extra-vars '{"nginx_ssl_servers": ["galaxy_https", "interactive_tools_https"]}' \
        --extra-vars nginx_ssl_src_dir=/export \
        --extra-vars "{\"sslkeys\": {\"server.key\": \"$ssl_key_content\"}}" \
        --extra-vars nginx_conf_ssl_certificate_key=/etc/ssl/private/server.key \
        --extra-vars nginx_conf_ssl_certificate=/etc/ssl/certs/server.crt \
        $ANSIBLE_EXTRA_VARS_HTTPS_PROXY_PREFIX
    else
        echo "Setting up self-signed SSL keys"
        ansible-playbook -c local /ansible/nginx.yml \
        --extra-vars '{"nginx_servers": ["galaxy_redirect_ssl", "interactive_tools_redirect_ssl"]}' \
        --extra-vars '{"nginx_ssl_servers": ["galaxy_https", "interactive_tools_https"]}' \
        --extra-vars nginx_ssl_role=galaxyproject.self_signed_certs \
        --extra-vars nginx_conf_ssl_certificate_key=/etc/ssl/private/$GALAXY_DOMAIN.pem \
        --extra-vars nginx_conf_ssl_certificate=/etc/ssl/certs/$GALAXY_DOMAIN.crt \
        --extra-vars "{\"openssl_domains\": [\"$GALAXY_DOMAIN\"]}" \
        $ANSIBLE_EXTRA_VARS_HTTPS_PROXY_PREFIX
    fi
fi

if [[ "$USE_HTTPS_LETSENCRYPT" != "False" || "$USE_HTTPS" != "False" ]]
then
    # Check if GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL has http but not https
    if [[ $GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL == "http:"* ]]
    then
        GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL=${GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL/http:/https:}
        export GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL
    fi
fi

# Disable authentication of flower
if [[ ! -z $DISABLE_FLOWER_AUTH ]]; then
    # disable authentification
    echo "Disable flower authentification "
    cp /etc/nginx/flower_auth.conf /etc/nginx/flower_auth.conf.source
    echo "# No authentication defined" > /etc/nginx/flower_auth.conf
fi

# Try to guess if we are running under --privileged mode
if [[ ! -z $HOST_DOCKER_LEGACY ]]; then
    if mount | grep "/proc/kcore"; then
        PRIVILEGED=false
    else
        PRIVILEGED=true
    fi
else
    # Taken from http://stackoverflow.com/questions/32144575/how-to-know-if-a-docker-container-is-running-in-privileged-mode
    ip link add dummy0 type dummy 2>/dev/null
    if [[ $? -eq 0 ]]; then
        PRIVILEGED=true
        # clean the dummy0 link
        ip link delete dummy0 2>/dev/null
    else
        PRIVILEGED=false
    fi
fi

cd $GALAXY_ROOT_DIR
. $GALAXY_VIRTUAL_ENV/bin/activate

# Decide container routing based on runtime capabilities; prefer Singularity when available.
docker_ok=false
if [ -S /var/run/docker.sock ] || command -v docker >/dev/null 2>&1; then
    docker_ok=true
fi

singularity_cmd=""
if command -v singularity >/dev/null 2>&1; then
    singularity_cmd="singularity"
elif command -v apptainer >/dev/null 2>&1; then
    singularity_cmd="apptainer"
fi

singularity_ok=false
if $PRIVILEGED && [ -n "$singularity_cmd" ]; then
    singularity_ok=true
fi

dest_default="${GALAXY_DESTINATIONS_DEFAULT:-}"
dest_docker="${GALAXY_DESTINATIONS_DOCKER_DEFAULT:-}"

if [ -z "$dest_default" ] || { $singularity_ok && [ "$dest_default" = "slurm_cluster" ]; }; then
    if $singularity_ok; then
        dest_default="slurm_cluster_singularity"
    elif $docker_ok; then
        dest_default="slurm_cluster_docker"
    else
        dest_default="slurm_cluster"
    fi
    export GALAXY_DESTINATIONS_DEFAULT="$dest_default"
fi

if [ -z "$dest_docker" ]; then
    if $docker_ok; then
        dest_docker="slurm_cluster_docker"
    else
        dest_docker="$dest_default"
    fi
    export GALAXY_DESTINATIONS_DOCKER_DEFAULT="$dest_docker"
else
    dest_docker="$GALAXY_DESTINATIONS_DOCKER_DEFAULT"
fi

if $singularity_ok; then
    export SINGULARITY_CACHEDIR="${SINGULARITY_CACHEDIR:-/export/container_cache/singularity/mulled}"
    export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-$SINGULARITY_CACHEDIR}"
    echo "Container routing: default -> ${dest_default} (Singularity via ${singularity_cmd}); Docker -> ${dest_docker}"
elif $docker_ok; then
    echo "Container routing: default -> ${dest_default} (Docker socket detected); Docker -> ${dest_docker}"
else
    echo "Container routing: no Docker/Singularity detected; using ${dest_default}"
fi

cvmfs_repos="${CVMFS_REPOSITORIES:-data.galaxyproject.org singularity.galaxyproject.org}"
cvmfs_repos="${cvmfs_repos//,/ }"

if $PRIVILEGED; then
    umount /var/lib/docker

    if command -v mount.cvmfs >/dev/null 2>&1; then
        chmod 666 /dev/fuse || true
        for repo in $cvmfs_repos; do
            repo_dir="/cvmfs/$repo"
            mkdir -p "$repo_dir"
            if ! mountpoint -q "$repo_dir"; then
                echo "Mounting CVMFS repo $repo"
                mount -t cvmfs "$repo" "$repo_dir" || echo "Warning: failed to mount $repo"
            fi
        done
    else
        echo "Info: CVMFS client not available; install CVMFS or use the sidecar via docker-compose --profile cvmfs."
    fi
else
    echo "Info: CVMFS mounts disabled (not running privileged). Use --privileged or the CVMFS sidecar in docker-compose."
fi

if ! mountpoint -q /cvmfs 2>/dev/null; then
    for repo in $cvmfs_repos; do
        repo_dir="/cvmfs/$repo"
        mkdir -p "$repo_dir"
        if [ "$repo" = "singularity.galaxyproject.org" ]; then
            mkdir -p "$repo_dir/all"
        fi
    done
    chown -R "$GALAXY_USER:$GALAXY_USER" /cvmfs
fi

if [[ ! -z $STARTUP_EXPORT_USER_FILES ]]; then
    # If /export/ is mounted, export_user_files file moving all data to /export/
    # symlinks will point from the original location to the new path under /export/
    # If /export/ is not given, nothing will happen in that step
    echo "Checking /export..."
    python3 /usr/local/bin/export_user_files.py $PG_DATA_DIR_DEFAULT
    mkdir -p /export/container_cache/singularity/mulled
    export_cache_owner="$(stat -c '%u:%g' /export/container_cache 2>/dev/null || echo '')"
    if [[ "$export_cache_owner" != "${GALAXY_UID}:${GALAXY_GID}" ]]; then
        chown -R "$GALAXY_USER:$GALAXY_USER" /export/container_cache
    fi
fi

# Delete compiled templates in case they are out of date
if [[ ! -z $GALAXY_CONFIG_TEMPLATE_CACHE_PATH ]]; then
    rm -rf $GALAXY_CONFIG_TEMPLATE_CACHE_PATH/*
fi

# Enable loading of dependencies on startup. Such as LDAP.
# Adapted from galaxyproject/galaxy/scripts/common_startup.sh
if [[ ! -z $LOAD_GALAXY_CONDITIONAL_DEPENDENCIES ]]
    then
        echo "Installing optional dependencies in galaxy virtual environment..."
        sudo -E -H -u $GALAXY_USER bash -c '
            : ${GALAXY_WHEELS_INDEX_URL:="https://wheels.galaxyproject.org/simple"}
            : ${PYPI_INDEX_URL:="https://pypi.python.org/simple"}
            GALAXY_CONDITIONAL_DEPENDENCIES=$(PYTHONPATH=lib "$GALAXY_VIRTUAL_ENV/bin/python" -c "import galaxy.dependencies; print(\"\\n\".join(galaxy.dependencies.optional(\"$GALAXY_CONFIG_FILE\")))")
            if [ -n "$GALAXY_CONDITIONAL_DEPENDENCIES" ]; then
                deps_file="$(mktemp)"
                printf "%s\n" "$GALAXY_CONDITIONAL_DEPENDENCIES" > "$deps_file"
                /usr/local/bin/uv pip install \
                    --python "$GALAXY_VIRTUAL_ENV/bin/python" \
                    -r "$deps_file" \
                    --index-url "${GALAXY_WHEELS_INDEX_URL}" \
                    --extra-index-url "${PYPI_INDEX_URL}"
                rm -f "$deps_file"
            fi
        '
fi

if [[ ! -z $LOAD_GALAXY_CONDITIONAL_DEPENDENCIES ]] && [[ ! -z $LOAD_PYTHON_DEV_DEPENDENCIES ]]
    then
        echo "Installing development requirements in galaxy virtual environment..."
        sudo -E -H -u $GALAXY_USER bash -c '
            : ${GALAXY_WHEELS_INDEX_URL:="https://wheels.galaxyproject.org/simple"}
            : ${PYPI_INDEX_URL:="https://pypi.python.org/simple"}
            dev_requirements="./lib/galaxy/dependencies/dev-requirements.txt"
            if [ -f "$dev_requirements" ]; then
                /usr/local/bin/uv pip install \
                    --python "$GALAXY_VIRTUAL_ENV/bin/python" \
                    -r "$dev_requirements" \
                    --index-url "${GALAXY_WHEELS_INDEX_URL}" \
                    --extra-index-url "${PYPI_INDEX_URL}"
            fi
        '
fi

# Enable Test Tool Shed
if [[ ! -z $ENABLE_TTS_INSTALL ]]
    then
        echo "Enable installation from the Test Tool Shed."
        export GALAXY_CONFIG_TOOL_SHEDS_CONFIG_FILE=$GALAXY_HOME/tool_sheds_conf.xml
fi

# Remove all default tools from Galaxy by default
if [[ ! -z $BARE ]]
    then
        echo "Remove all tools from the tool_conf.xml file."
        export GALAXY_CONFIG_TOOL_CONFIG_FILE=$GALAXY_ROOT_DIR/test/functional/tools/upload_tool_conf.xml
fi

# If auto installing conda envs, make sure bcftools is installed for __set_metadata__ tool
if [[ ! -z $GALAXY_CONFIG_CONDA_AUTO_INSTALL ]]
    then
        if [ ! -d "/tool_deps/_conda/envs/__bcftools@1.5" ]; then
            su $GALAXY_USER -c "/tool_deps/_conda/bin/conda create -y --override-channels --channel iuc --channel conda-forge --channel bioconda --channel defaults --name __bcftools@1.5 bcftools=1.5"
            su $GALAXY_USER -c "/tool_deps/_conda/bin/conda clean --tarballs --yes"
        fi
fi

if [[ $NONUSE != *"postgres"* ]]
    then
        # Backward compatibility for exported postgresql directories before version 15.08.
        # In previous versions postgres has the UID/GID of 102/106. We changed this in
        # https://github.com/bgruening/docker-galaxy-stable/pull/71 to GALAXY_POSTGRES_UID=1550 and
        # GALAXY_POSTGRES_GID=1550
        if [ -e /export/postgresql/ ];
            then
                if [ `stat -c %g /export/postgresql/` == "106" ];
                    then
                        chown -R postgres:postgres /export/postgresql/
                fi
        fi
fi


if [[ ! -z $ENABLE_CONDOR ]]
    then
        if [[ ! -z $CONDOR_HOST ]]
        then
            echo "Enabling Condor with external scheduler at $CONDOR_HOST"
        echo "# Config generated by startup.sh
CONDOR_HOST = $CONDOR_HOST
ALLOW_ADMINISTRATOR = *
ALLOW_OWNER = *
ALLOW_READ = *
ALLOW_WRITE = *
ALLOW_CLIENT = *
ALLOW_NEGOTIATOR = *
DAEMON_LIST = MASTER, SCHEDD
UID_DOMAIN = galaxy
DISCARD_SESSION_KEYRING_ON_STARTUP = False
TRUST_UID_DOMAIN = true" > /etc/condor/condor_config.local
        fi

        if [[ -e /export/condor_config ]]
        then
            echo "Replacing Condor config by locally supplied config from /export/condor_config"
            rm -f /etc/condor/condor_config
            ln -s /export/condor_config /etc/condor/condor_config
        fi
fi


# Copy or link the slurm/munge config files
if [ -e /export/slurm.conf ]
then
    rm -f /etc/slurm/slurm.conf
    ln -s /export/slurm.conf /etc/slurm/slurm.conf
else
    # Configure SLURM with runtime hostname.
    # Use absolute path to python so virtualenv is not used.
    mkdir -p /etc/slurm
    /usr/bin/python /usr/sbin/configure_slurm.py
fi
mkdir -p /tmp/slurm /var/log/slurm /var/lib/slurm/slurmctld
chown -R $GALAXY_USER:$GALAXY_USER /tmp/slurm /var/log/slurm /var/lib/slurm
if [ -e /export/munge.key ]
then
    rm -f /etc/munge/munge.key
    ln -s /export/munge.key /etc/munge/munge.key
    chmod 400 /export/munge.key
fi

# link the gridengine config file
if [ -e /export/act_qmaster ]
then
    rm -f /var/lib/gridengine/default/common/act_qmaster
    ln -s /export/act_qmaster /var/lib/gridengine/default/common/act_qmaster
fi

# Waits until postgres is ready
function wait_for_postgres {
    echo "Checking if database is up and running"
    until /usr/local/bin/check_database.py 2>&1 >/dev/null; do sleep 5; echo "Waiting for database"; done
    echo "Database connected"
}

# Waits until rabbitmq is ready
function wait_for_rabbitmq {
    echo "Checking if RabbitMQ is up and running"
    until rabbitmqctl status 2>&1 >/dev/null; do sleep 5; echo "Waiting for RabbitMQ"; done
    echo "RabbitMQ is ready"
}

# Waits until docker daemon is ready
function wait_for_docker {
    echo "Checking if docker daemon is up and running"
    until docker version 2>&1 >/dev/null; do sleep 5; echo "Waiting for docker daemon"; done
    echo "Docker daemon is ready"
}

function wait_for_munge {
    local retries=20
    echo "Checking if munge is up and running"
    until munge -n >/dev/null 2>&1; do
        if [[ $retries -le 0 ]]; then
            echo "Munge did not become ready"
            return 1
        fi
        retries=$((retries - 1))
        sleep 1
    done
    echo "Munge is ready"
}

# $NONUSE can be set to include postgres, cron, proftp, nodejs, condor, slurmd, slurmctld,
# celery, rabbitmq, redis, flower or tusd
# if included we will _not_ start these services.
function start_supervisor {
    supervisord -c /etc/supervisor/supervisord.conf
    sleep 5

    if [[ ! -z $SUPERVISOR_MANAGE_POSTGRES && ! -z $SUPERVISOR_POSTGRES_AUTOSTART ]]; then
        if [[ $NONUSE != *"postgres"* ]]
        then
            echo "Starting postgres"
            supervisorctl start postgresql
        fi
    fi

    if [[ ! -z $SUPERVISOR_MANAGE_CRON ]]; then
        if [[ $NONUSE != *"cron"* ]]
        then
            echo "Starting cron"
            supervisorctl start cron
        fi
    fi

    if [[ ! -z $SUPERVISOR_MANAGE_PROFTP ]]; then
        if [[ $NONUSE != *"proftp"* ]]
        then
            echo "Starting ProFTP"
            supervisorctl start proftpd
        fi
    fi

    if [[ ! -z $SUPERVISOR_MANAGE_CONDOR ]]; then
        if [[ $NONUSE != *"condor"* ]]
        then
            echo "Starting condor"
            supervisorctl start condor
        fi
    fi

    if [[ ! -z $SUPERVISOR_MANAGE_SLURM ]]; then
        echo "Starting munge"
        supervisorctl start munge
        wait_for_munge || true

        if [[ $NONUSE != *"slurmctld"* ]]
        then
            echo "Starting slurmctld"
            supervisorctl start slurmctld
        fi
        if [[ $NONUSE != *"slurmd"* ]]
        then
            echo "Starting slurmd"
            supervisorctl start slurmd
        fi
    else
        echo "Starting munge"
        mkdir -p /var/run/munge && chown -R root:root /var/run/munge
        /usr/sbin/munged -f -F --num-threads="${MUNGE_NUM_THREADS:-2}" &
        wait_for_munge || true

        if [[ $NONUSE != *"slurmctld"* ]]
        then
            echo "Starting slurmctld"
            /usr/sbin/slurmctld -L $GALAXY_LOGS_DIR/slurmctld.log
        fi
        if [[ $NONUSE != *"slurmd"* ]]
        then
            echo "Starting slurmd"
            /usr/sbin/slurmd -L $GALAXY_LOGS_DIR/slurmd.log
        fi
    fi

    if [[ ! -z $SUPERVISOR_MANAGE_RABBITMQ ]]; then
        if [[ $NONUSE != *"rabbitmq"* ]]
        then
            echo "Starting rabbitmq"
            supervisorctl start rabbitmq

            wait_for_rabbitmq
            echo "Configuring rabbitmq users"
            ansible-playbook -c local /usr/local/bin/configure_rabbitmq_users.yml &> /dev/null

            echo "Restarting rabbitmq"
            supervisorctl restart rabbitmq
        fi    
    fi

    if [[ ! -z $SUPERVISOR_MANAGE_REDIS ]]; then
        if [[ $NONUSE != *"redis"* ]]
        then
            echo "Starting redis"
            supervisorctl start redis
        fi
    fi

    if [[ ! -z $SUPERVISOR_MANAGE_FLOWER ]]; then 
        if [[ $NONUSE != *"flower"* && $NONUSE != *"celery"* && $NONUSE != *"rabbitmq"* ]]
        then
            echo "Starting flower"
            supervisorctl start flower
        fi
    fi
}

function start_gravity {
    if [[ ! -z $GRAVITY_MANAGE_CELERY ]]; then
        if [[ $NONUSE == *"celery"* ]]
        then
            echo "Disabling Galaxy celery app"
            python3 /usr/local/bin/update_yaml_value "${GRAVITY_CONFIG_FILE}" "gravity.celery.enable" "false" &> /dev/null
            python3 /usr/local/bin/update_yaml_value "${GRAVITY_CONFIG_FILE}" "gravity.celery.enable_beat" "false" &> /dev/null
        else
            export GALAXY_CONFIG_ENABLE_CELERY_TASKS='true'
            if [[ $NONUSE != *"redis"* ]]
            then
                # Configure Galaxy to use Redis as the result backend for Celery tasks
                ansible localhost -m replace -a "path=${GALAXY_CONFIG_FILE} regexp='^  #celery_conf:' replace='  celery_conf:'" &> /dev/null
                ansible localhost -m replace -a "path=${GALAXY_CONFIG_FILE} regexp='^  #  result_backend:.*' replace='    result_backend: redis://127.0.0.1:6379/0'" &> /dev/null 
            fi
        fi
    fi

    if [[ ! -z $GRAVITY_MANAGE_GX_IT_PROXY ]]; then
        if [[ $NONUSE == *"nodejs"* ]]
        then
            echo "Disabling nodejs"
            python3 /usr/local/bin/update_yaml_value "${GRAVITY_CONFIG_FILE}" "gravity.gx_it_proxy.enable" "false" &> /dev/null
        else
            # TODO: Remove this after gravity config manager is updated to handle env vars properly
            ansible localhost -m replace -a "path=${GALAXY_CONFIG_FILE} regexp='^  #interactivetools_enable:.*' replace='  interactivetools_enable: true'" &> /dev/null
        fi
    fi

    if [[ ! -z $GRAVITY_MANAGE_TUSD ]]; then
        if [[ $NONUSE == *"tusd"* ]]
        then
            echo "Disabling Galaxy tusd app"
            python3 /usr/local/bin/update_yaml_value "${GRAVITY_CONFIG_FILE}" "gravity.tusd.enable" "false" &> /dev/null
            cp /etc/nginx/delegated_uploads.conf /etc/nginx/delegated_uploads.conf.source 
            echo "# No delegated uploads" > /etc/nginx/delegated_uploads.conf
        else
            # TODO: Remove this after gravity config manager is updated to handle env vars properly
            ansible localhost -m replace -a "path=${GALAXY_CONFIG_FILE} regexp='^  #galaxy_infrastructure_url:.*' replace='  galaxy_infrastructure_url: ${GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL}'" &> /dev/null
        fi
    fi

    if [[ $NONUSE != *"rabbitmq"* ]]
    then
        # Set AMQP internal connection for Galaxy
        export GALAXY_CONFIG_AMQP_INTERNAL_CONNECTION="pyamqp://galaxy:galaxy@localhost:5672/galaxy"
    fi

    # Set the SUPERVISORD_SOCKET to overwrite gravity's default.
    # The default will put the socket into the export dir, into gravity's state directory. And this caused some problems to start supervisord.  
    export SUPERVISORD_SOCKET=${SUPERVISORD_SOCKET:-/tmp/galaxy_supervisord.sock}
    # Start galaxy services using gravity
    /usr/local/bin/galaxyctl -d start
}

if [[ ! -z $SUPERVISOR_POSTGRES_AUTOSTART ]]; then
    if [[ $NONUSE != *"postgres"* ]]
    then
        # Change the data_directory of postgresql in the main config file
        ansible localhost -m lineinfile -a "line='data_directory = \'$PG_DATA_DIR_HOST\'' dest=$PG_CONF_DIR_DEFAULT/postgresql.conf backup=yes state=present regexp='data_directory'" &> /dev/null
    fi
fi

if $PRIVILEGED; then
    # In privileged mode autofs and CVMFS may be available, so only append existing files.
    export GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH="${GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH},/cvmfs/data.galaxyproject.org/byhand/location/tool_data_table_conf.xml,/cvmfs/data.galaxyproject.org/managed/location/tool_data_table_conf.xml"

    echo "Enable Galaxy Interactive Tools."
    export GALAXY_CONFIG_INTERACTIVETOOLS_ENABLE=True
    export GALAXY_CONFIG_TOOL_CONFIG_FILE="$GALAXY_CONFIG_TOOL_CONFIG_FILE,$GALAXY_INTERACTIVE_TOOLS_CONFIG_FILE"

    # Update domain-based interactive tools nginx configuration with the galaxy domain if provided
    if [[ ! -z $GALAXY_DOMAIN ]]; then
        sed -i "s/\(\.interactivetool\.\)[^;]*/\1$GALAXY_DOMAIN/g" /etc/nginx/interactive_tools_common.conf
    fi

    if [[ -z $DOCKER_PARENT ]]; then
        #build the docker in docker environment
        # Ensure cgroup mounts are set up without triggering dind "no command" warnings.
        bash /root/cgroupfs_mount.sh true
        start_supervisor
        start_gravity
        supervisorctl start docker
        wait_for_docker
    else
        #inheriting /var/run/docker.sock from parent, assume that you need to
        #run docker with sudo to validate
        echo "$GALAXY_USER ALL = NOPASSWD : ALL" >> /etc/sudoers
        start_supervisor
        start_gravity
    fi
    if  [[ ! -z $PULL_IT_IMAGES ]]; then
        echo "About to pull IT images. Depending on the size, this may take a while!"

        for it in {JUPYTER,RSTUDIO,ETHERCALC,PHINCH,NEO}; do
            enabled_var_name="GALAXY_IT_FETCH_${it}";
            if [[ ${!enabled_var_name} ]]; then
                # Store name in a var
                image_var_name="GALAXY_IT_${it}_IMAGE"
                # And then read from that var
                docker pull "${!image_var_name}"
            fi
        done
    fi
else
    echo "Disable Galaxy Interactive Tools. Start with --privileged to enable ITs."
    export GALAXY_CONFIG_INTERACTIVETOOLS_ENABLE=False
    start_supervisor
    start_gravity
fi

wait_for_postgres

# Make sure the database is automatically updated
if [[ ! -z $GALAXY_AUTO_UPDATE_DB ]]
then
    echo "Updating Galaxy database"
    sh manage_db.sh -c $GALAXY_CONFIG_FILE upgrade
fi

# In case the user wants the default admin to be created, do so.
if [[ ! -z $GALAXY_DEFAULT_ADMIN_USER ]]
    then
        echo "Creating admin user $GALAXY_DEFAULT_ADMIN_USER with key $GALAXY_DEFAULT_ADMIN_KEY and password $GALAXY_DEFAULT_ADMIN_PASSWORD if not existing"
        python /usr/local/bin/create_galaxy_user.py --user "$GALAXY_DEFAULT_ADMIN_EMAIL" --password "$GALAXY_DEFAULT_ADMIN_PASSWORD" \
        -c "$GALAXY_CONFIG_FILE" --username "$GALAXY_DEFAULT_ADMIN_USER" --key "$GALAXY_DEFAULT_ADMIN_KEY"
    # If there is a need to execute actions that would require a live galaxy instance, such as adding workflows, setting quotas, adding more users, etc.
    # then place a file with that logic named post-start-actions.sh on the /export/ directory, it should have access to all environment variables
    # visible here.
    # The file needs to be executable (chmod a+x post-start-actions.sh)
        if [ -x /export/post-start-actions.sh ]
            then
           # uses ephemeris, present in docker-galaxy-stable, to wait for the local instance
           /tool_deps/_conda/bin/galaxy-wait -g http://127.0.0.1 -v --timeout 600 > $GALAXY_LOGS_DIR/post-start-actions.log &&
           /export/post-start-actions.sh >> $GALAXY_LOGS_DIR/post-start-actions.log &
    fi
fi

# Reinstall tools if the user want to
if [[ ! -z $GALAXY_AUTO_UPDATE_TOOLS ]]
    then
        /tool_deps/_conda/bin/galaxy-wait -g http://127.0.0.1 -v --timeout 600 > /home/galaxy/logs/post-start-actions.log &&
        OLDIFS=$IFS
        IFS=','
        for TOOL_YML in `echo "$GALAXY_AUTO_UPDATE_TOOLS"`
        do
            echo "Installing tools from $TOOL_YML"
            /tool_deps/_conda/bin/shed-tools install -g "http://127.0.0.1" -a "$GALAXY_DEFAULT_ADMIN_KEY" -t "$TOOL_YML"
            /tool_deps/_conda/bin/conda clean --tarballs --yes
        done
        IFS=$OLDIFS
fi

# migrate custom Visualisations (Galaxy plugins)
# this is needed for by the new client build system
python3 ${GALAXY_ROOT_DIR}/scripts/plugin_staging.py

# Enable verbose output
if [ `echo ${GALAXY_LOGGING:-'no'} | tr [:upper:] [:lower:]` = "full" ]
    then
        tail -f /var/log/supervisor/* /var/log/nginx/* $GALAXY_LOGS_DIR/*.log
    else
        tail -f $GALAXY_LOGS_DIR/*.log
fi
