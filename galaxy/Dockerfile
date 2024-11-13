# Galaxy - Stable
#
# VERSION       Galaxy in Docker

# TODO
#
# * README: only Docker next to Docker is supported
# * NodeJS is getting globally installed via the playbook, this is not needed anymore isn't it?
# * the playbooks are not cleaning anything up
#

FROM buildpack-deps:22.04 AS build_base

ENV GALAXY_ROOT_DIR=/galaxy \
    GALAXY_VIRTUAL_ENV=/galaxy_venv \
    GALAXY_HOME=/home/galaxy \
    GALAXY_CONDA_PREFIX=/tool_deps/_conda \
    MINIFORGE_VERSION=24.3.0-0


# Install miniforge and then virtualenv from conda
FROM build_base AS build_miniforge

ADD ./bashrc $GALAXY_HOME/.bashrc

RUN curl -s -L https://github.com/conda-forge/miniforge/releases/download/$MINIFORGE_VERSION/Miniforge3-$MINIFORGE_VERSION-Linux-x86_64.sh > ~/miniforge.sh \
    && /bin/bash ~/miniforge.sh -b -p $GALAXY_CONDA_PREFIX/ \
    && rm ~/miniforge.sh \
    && ln -s $GALAXY_CONDA_PREFIX/etc/profile.d/conda.sh /etc/profile.d/conda.sh \
    && echo ". $GALAXY_CONDA_PREFIX/etc/profile.d/conda.sh" >> $GALAXY_HOME/.bashrc \
    && echo "conda activate base" >> $GALAXY_HOME/.bashrc \
    && export PATH=$GALAXY_CONDA_PREFIX/bin/:$PATH \
    && conda config --add channels bioconda \
    && conda install virtualenv pip ephemeris \
    && conda clean --packages -t -i \
    && cp -r ~/.conda $GALAXY_HOME && cp ~/.condarc $GALAXY_HOME \
    && find $GALAXY_CONDA_PREFIX -name '*.pyc' -delete


FROM build_base AS build_galaxy

ARG GALAXY_RELEASE=release_24.1
ARG GALAXY_REPO=https://github.com/galaxyproject/galaxy

ENV NODE_OPTIONS=--max-old-space-size=4096

COPY --from=build_miniforge /tool_deps /tool_deps

RUN mkdir $GALAXY_ROOT_DIR $GALAXY_VIRTUAL_ENV \
    # download latest stable release of Galaxy.
    && curl -L -s $GALAXY_REPO/archive/$GALAXY_RELEASE.tar.gz | tar xzf - --strip-components=1 -C $GALAXY_ROOT_DIR \
    && PATH=$GALAXY_CONDA_PREFIX/bin/:$PATH virtualenv $GALAXY_VIRTUAL_ENV \
    # Install galaxy client
    && cd $GALAXY_ROOT_DIR && ./scripts/common_startup.sh \
    && . $GALAXY_VIRTUAL_ENV/bin/activate \
    && pip install "weasyprint>=61.2" watchdog --index-url https://wheels.galaxyproject.org/simple --extra-index-url https://pypi.python.org/simple \
    && deactivate \
    # cleanup
    && find config \( -name 'node_modules' -o -name '.cache' -o -name '.parcel-cache' \) -type d -prune -exec rm -rf '{}' + \
    && find $GALAXY_ROOT_DIR -name '*.pyc' -delete && find $GALAXY_VIRTUAL_ENV -name '*.pyc' -delete \ 
    && rm -rf $GALAXY_ROOT_DIR/client/node_modules/ $GALAXY_VIRTUAL_ENV/src/


FROM ubuntu:22.04 AS galaxy_cluster_base

ENV GALAXY_ROOT_DIR=/galaxy \
    GALAXY_VIRTUAL_ENV=/galaxy_venv \
    GALAXY_LOGS_DIR=/home/galaxy/logs \
    GALAXY_CONFIG_DIR=/etc/galaxy \
    GALAXY_USER=galaxy \
    GALAXY_UID=1450 \
    GALAXY_GID=1450 \
    GALAXY_HOME=/home/galaxy \
    GALAXY_CONDA_PREFIX=/tool_deps/_conda \
    EXPORT_DIR=/export \
    DEBIAN_FRONTEND=noninteractive \
    PG_VERSION=15

ENV GALAXY_CONFIG_FILE=$GALAXY_CONFIG_DIR/galaxy.yml \
    GALAXY_CONFIG_JOB_CONFIG_FILE=$GALAXY_CONFIG_DIR/job_conf.xml \
    GALAXY_CONFIG_JOB_METRICS_CONFIG_FILE=$GALAXY_CONFIG_DIR/job_metrics_conf.yml \
    GALAXY_CONFIG_TUS_UPLOAD_STORE=/tmp/tus_upload_store \
    GALAXY_CONFIG_INTERACTIVETOOLS_MAP=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/database/interactivetools_map.sqlite \
    GRAVITY_CONFIG_FILE=$GALAXY_CONFIG_DIR/gravity.yml \
    GALAXY_POSTGRES_UID=1550 \
    GALAXY_POSTGRES_GID=1550 \
    # Define the default postgresql database path
    PG_DATA_DIR_DEFAULT=/var/lib/postgresql/$PG_VERSION/main/ \
    PG_CONF_DIR_DEFAULT=/etc/postgresql/$PG_VERSION/main/ \
    PG_DATA_DIR_HOST=$EXPORT_DIR/postgresql/$PG_VERSION/main/

ADD --chmod=755 ./common_cleanup.sh /usr/bin/common_cleanup.sh

RUN echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/02apt-speedup \
    && echo "Acquire::http {No-Cache=True;};" > /etc/apt/apt.conf.d/no-cache \
    && echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/99no-install-recommends \
    && apt-get -qq update && apt-get install -y locales \
    && locale-gen en_US.UTF-8 && dpkg-reconfigure locales \
    && apt-get autoremove -y && apt-get clean \
    && /usr/bin/common_cleanup.sh

ADD ansible/ /ansible/

# Install ansible and other dependencies
RUN apt-get -qq update \
    && apt install -y software-properties-common dirmngr gpg gpg-agent \
    && apt install -y sudo ca-certificates nano git gridengine-common gridengine-drmaa1.0 libswitch-perl \
    && add-apt-repository ppa:ansible/ansible-7 \
    && apt install -y ansible \
    # Make python3 standard
    && update-alternatives --install /usr/bin/python python /usr/bin/python3 10 \
    && apt purge -y software-properties-common systemd && apt-get autoremove -y && apt-get clean \
    # Install ansible roles
    && ansible-galaxy install -r /ansible/requirements.yml -p /ansible/roles \
    && groupadd -r $GALAXY_USER -g $GALAXY_GID \
    && useradd -u $GALAXY_UID -r -g $GALAXY_USER -d $GALAXY_HOME -m -c "Galaxy user" --shell /bin/bash $GALAXY_USER \
    # Create the postgres user before apt-get does (with the configured UID/GID) to facilitate sharing $EXPORT_DIR/postgresql with non-Linux hosts
    && groupadd -r postgres -g $GALAXY_POSTGRES_GID \
    && adduser --system --quiet --home /var/lib/postgresql --no-create-home --shell /bin/bash --gecos "" --uid $GALAXY_POSTGRES_UID --gid $GALAXY_POSTGRES_GID postgres \
    && mkdir -p $GALAXY_ROOT_DIR $GALAXY_VIRTUAL_ENV $GALAXY_CONFIG_DIR $GALAXY_CONFIG_DIR/web $GALAXY_LOGS_DIR $EXPORT_DIR \
    && chown -R $GALAXY_USER:$GALAXY_USER $GALAXY_ROOT_DIR $GALAXY_VIRTUAL_ENV $GALAXY_CONFIG_DIR $GALAXY_LOGS_DIR $EXPORT_DIR \
    && /usr/bin/common_cleanup.sh

COPY --chown=$GALAXY_USER:$GALAXY_USER --from=build_miniforge /tool_deps /tool_deps

# Install necessary components and dependencies for running Galaxy
RUN PATH=$GALAXY_CONDA_PREFIX/bin/:$PATH virtualenv $GALAXY_VIRTUAL_ENV \
    && chown -R $GALAXY_USER:$GALAXY_USER $GALAXY_VIRTUAL_ENV \
    && ansible-playbook /ansible/provision.yml \
    --extra-vars galaxy_server_dir=$GALAXY_ROOT_DIR \
    --extra-vars galaxy_venv_dir=$GALAXY_VIRTUAL_ENV \
    --extra-vars galaxy_logs_dir=$GALAXY_LOGS_DIR \
    --extra-vars galaxy_user_name=$GALAXY_USER \
    --extra-vars galaxy_config_file=$GALAXY_CONFIG_FILE \
    --extra-vars galaxy_config_dir=$GALAXY_CONFIG_DIR \
    --extra-vars gravity_config_file=$GRAVITY_CONFIG_FILE \
    --extra-vars galaxy_job_conf_path=$GALAXY_CONFIG_JOB_CONFIG_FILE \
    --extra-vars galaxy_job_metrics_conf_path=$GALAXY_CONFIG_JOB_METRICS_CONFIG_FILE \
    --extra-vars postgresql_version=$PG_VERSION \
    --extra-vars supervisor_postgres_config_path=$PG_CONF_DIR_DEFAULT/postgresql.conf \
    --extra-vars redis_venv_dir=$GALAXY_VIRTUAL_ENV \
    --extra-vars redis_venv_user=$GALAXY_USER \
    --extra-vars galaxy_user_name=$GALAXY_USER \
    --extra-vars proftpd_sql_db=galaxy@galaxy \
    --extra-vars proftpd_sql_user=$GALAXY_USER \
    --extra-vars proftpd_sql_password=$GALAXY_USER \
    --extra-vars galaxy_ftp_upload_dir=$EXPORT_DIR/ftp \
    --extra-vars tus_upload_store_path=$GALAXY_CONFIG_TUS_UPLOAD_STORE \
    --extra-vars gx_it_proxy_sessions_path=$GALAXY_CONFIG_INTERACTIVETOOLS_MAP \
    # Install flower separately as systemd tasks (tagged with 'service') have to be skipped
    && PATH=$GALAXY_CONDA_PREFIX/bin/:$PATH ansible-playbook /ansible/flower.yml --skip-tags service \
    --extra-vars flower_venv_dir=$GALAXY_VIRTUAL_ENV \
    --extra-vars flower_db_file=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/database/flower.db \
    --extra-vars flower_user=$GALAXY_USER \
    --extra-vars flower_group=$GALAXY_USER \
    --extra-vars flower_venv_user=$GALAXY_USER \
    --extra-vars flower_venv_group=$GALAXY_USER \
    && chown -R $GALAXY_USER:$GALAXY_USER $GALAXY_VIRTUAL_ENV \
    && apt purge -y software-properties-common dirmngr gpg gpg-agent && apt-get autoremove -y && apt-get clean \
    && /usr/bin/common_cleanup.sh


FROM galaxy_cluster_base AS final

LABEL maintainer="Björn A. Grüning <bjoern.gruening@gmail.com>"

ENV GALAXY_CONFIG_MANAGED_CONFIG_DIR=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/database/config \
    GALAXY_CONFIG_TOOL_CONFIG_FILE=$GALAXY_CONFIG_DIR/tool_conf.xml \
    GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH=$GALAXY_CONFIG_DIR/tool_data_table_conf.xml \
    GALAXY_CONFIG_WATCH_TOOL_DATA_DIR=True \
    GALAXY_CONFIG_TOOL_DEPENDENCY_DIR=$EXPORT_DIR/tool_deps \
    GALAXY_CONFIG_TOOL_PATH=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/tools \
    GALAXY_DEFAULT_ADMIN_USER=admin \
    GALAXY_DEFAULT_ADMIN_EMAIL=admin@example.org \
    GALAXY_DEFAULT_ADMIN_PASSWORD=password \
    GALAXY_DEFAULT_ADMIN_KEY=fakekey \
    GALAXY_DESTINATIONS_DEFAULT=slurm_cluster \
    GALAXY_RUNNERS_ENABLE_SLURM=True \
    GALAXY_RUNNERS_ENABLE_CONDOR=False \
    GALAXY_CONFIG_DATABASE_CONNECTION=postgresql://galaxy:galaxy@localhost:5432/galaxy?client_encoding=utf8 \
    GALAXY_CONFIG_ADMIN_USERS=admin@example.org \
    GALAXY_CONFIG_BOOTSTRAP_ADMIN_API_KEY=HSNiugRFvgT574F43jZ7N9F3 \
    GALAXY_CONFIG_BRAND="Galaxy Docker Build" \
    GALAXY_CONFIG_STATIC_ENABLED=False \
    GALAXY_INTERACTIVE_TOOLS_CONFIG_FILE=$GALAXY_CONFIG_DIR/tool_conf_interactive.xml \
    # The following ENV var can be used to set the number of gunicorn workers
    GUNICORN_WORKERS=2 \
    # The following ENV var can be used to set the number of celery workers
    CELERY_WORKERS=2 \
    # Set HTTPS to use a self-signed certificate (or your own certificate in $EXPORT_DIR/{server.key,server.crt})
    USE_HTTPS=False \
    # Set USE_HTTPS_LENSENCRYPT and GALAXY_DOMAIN to a domain that is reachable to get a letsencrypt certificate
    USE_HTTPS_LETSENCRYPT=False \
    GALAXY_DOMAIN=localhost \
    # Set the number of Galaxy handlers
    GALAXY_HANDLER_NUMPROCS=2 \
    # Setting a standard encoding. This can get important for things like the unix sort tool.
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8

COPY --chown=$GALAXY_USER:$GALAXY_USER --from=build_galaxy $GALAXY_ROOT_DIR $GALAXY_ROOT_DIR
COPY --chown=$GALAXY_USER:$GALAXY_USER --from=build_galaxy $GALAXY_VIRTUAL_ENV $GALAXY_VIRTUAL_ENV
COPY --chown=$GALAXY_USER:$GALAXY_USER --from=build_miniforge $GALAXY_HOME $GALAXY_HOME
COPY --chown=$GALAXY_USER:$GALAXY_USER --from=build_miniforge /etc/profile.d/conda.sh /etc/profile.d/conda.sh

ADD --chown=$GALAXY_USER:$GALAXY_USER ./reports.yml.sample $GALAXY_CONFIG_DIR/reports.yml
ADD --chown=$GALAXY_USER:$GALAXY_USER ./sample_tool_list.yaml $GALAXY_HOME/ephemeris/sample_tool_list.yaml

# Activate Interactive Tools during runtime
ADD --chown=$GALAXY_USER:$GALAXY_USER ./tool_conf_interactive.xml.sample $GALAXY_INTERACTIVE_TOOLS_CONFIG_FILE

RUN mkdir -p $GALAXY_CONFIG_TUS_UPLOAD_STORE \
    && ln -s /tool_deps/ $GALAXY_CONFIG_TOOL_DEPENDENCY_DIR \
    && chown $GALAXY_USER:$GALAXY_USER $GALAXY_CONFIG_TOOL_DEPENDENCY_DIR $GALAXY_CONFIG_TUS_UPLOAD_STORE \
    # Configure Galaxy to use the Tool Shed
    && cp $GALAXY_HOME/.bashrc ~/ \
    && su $GALAXY_USER -c "cp $GALAXY_ROOT_DIR/config/galaxy.yml.sample $GALAXY_CONFIG_FILE" \
    && su $GALAXY_USER -c "cp $GALAXY_ROOT_DIR/config/tool_conf.xml.sample $GALAXY_CONFIG_TOOL_CONFIG_FILE" \
    && curl -o $GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH \
    -L https://raw.githubusercontent.com/galaxyproject/usegalaxy-playbook/8adb1f82c94fe95b09df2a2816440ce2420b7d39/env/main/files/galaxy/config/tool_data_table_conf.xml \
    && chown $GALAXY_USER:$GALAXY_USER $GALAXY_CONFIG_DIR/reports.yml $GALAXY_HOME/ephemeris/sample_tool_list.yaml $GALAXY_INTERACTIVE_TOOLS_CONFIG_FILE $GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH \
    && chmod 0644 $GALAXY_CONFIG_DIR/reports.yml $GALAXY_HOME/ephemeris/sample_tool_list.yaml $GALAXY_INTERACTIVE_TOOLS_CONFIG_FILE $GALAXY_CONFIG_TOOL_DATA_TABLE_CONFIG_PATH

# Include all needed scripts from the host
ADD ./setup_postgresql.py /usr/local/bin/setup_postgresql.py

# Configure PostgreSQL
# 1. Remove all old configuration
# 2. Create DB-user 'galaxy' with password 'galaxy' in database 'galaxy'
# 3. Create Galaxy Admin User 'admin@example.org' with password 'admin' and API key 'admin'

RUN cd / \
    && rm $PG_DATA_DIR_DEFAULT -rf \
    && python /usr/local/bin/setup_postgresql.py --dbuser galaxy --dbpassword galaxy --db-name galaxy --dbpath $PG_DATA_DIR_DEFAULT --dbversion $PG_VERSION \
    && service postgresql start \
    && service postgresql stop

WORKDIR $GALAXY_ROOT_DIR

# Updating genome informations from UCSC
# RUN su $GALAXY_USER -c "export GALAXY=$GALAXY_ROOT_DIR && sh ./cron/updateucsc.sh.sample"

ENV GALAXY_CONFIG_JOB_WORKING_DIRECTORY=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/database/job_working_directory \
    GALAXY_CONFIG_FILE_PATH=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/database/files \
    GALAXY_CONFIG_NEW_FILE_PATH=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/database/tmp \
    GALAXY_CONFIG_TEMPLATE_CACHE_PATH=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/database/compiled_templates \
    GALAXY_CONFIG_CITATION_CACHE_DATA_DIR=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/database/citations/data \
    GALAXY_CONFIG_FTP_UPLOAD_DIR=$EXPORT_DIR/ftp \
    GALAXY_CONFIG_FTP_UPLOAD_SITE=example.org \
    GALAXY_CONFIG_USE_PBKDF2=True \
    GALAXY_CONFIG_NGINX_X_ACCEL_REDIRECT_BASE=/_x_accel_redirect \
    GALAXY_CONFIG_DYNAMIC_PROXY_MANAGE=False \
    GALAXY_CONFIG_VISUALIZATION_PLUGINS_DIRECTORY=config/plugins/visualizations \
    GALAXY_CONFIG_TRUST_JUPYTER_NOTEBOOK_CONVERSION=True \
    GALAXY_CONFIG_SANITIZE_ALL_HTML=False \
    GALAXY_CONFIG_WELCOME_URL=$GALAXY_CONFIG_DIR/web/welcome.html \
    GALAXY_CONFIG_OVERRIDE_DEBUG=False \
    GALAXY_CONFIG_ENABLE_QUOTAS=True \
    GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL=http://$GALAXY_DOMAIN \
    GALAXY_CONFIG_OUTPUTS_TO_WORKING_DIRECTORY=True \
    GALAXY_CONDA_PREFIX=$GALAXY_CONFIG_TOOL_DEPENDENCY_DIR/_conda

# Container Style
ADD --chown=$GALAXY_USER:$GALAXY_USER GalaxyDocker.png $GALAXY_CONFIG_DIR/web/welcome_image.png
ADD --chown=$GALAXY_USER:$GALAXY_USER welcome.html $GALAXY_CONFIG_DIR/web/welcome.html


# Activate additional Tool Sheds
# Activate the Test Tool Shed during runtime, useful for testing repositories.
ADD --chown=$GALAXY_USER:$GALAXY_USER ./tool_sheds_conf.xml $GALAXY_HOME/tool_sheds_conf.xml

# Script that enables easier downstream installation of tools (e.g. for different Galaxy Docker flavours)
ADD install_tools_wrapper.sh /usr/bin/install-tools
# script to install BioJS visualizations
ADD install_biojs_vis.sh /usr/bin/install-biojs
RUN chmod +x /usr/bin/install-tools /usr/bin/install-biojs && \
    cd /usr/bin/ && curl https://git.embl.de/grp-gbcs/galaxy-dir-sync/raw/master/src/galaxy-dir-sync.py > galaxy-dir-sync.py && \
    chmod +x galaxy-dir-sync.py

# use https://github.com/krallin/tini/ as tiny but valid init and PID 1
ADD https://github.com/krallin/tini/releases/download/v0.18.0/tini /sbin/tini
RUN chmod +x /sbin/tini

ADD --chown=$GALAXY_USER:$GALAXY_USER --chmod=755 ./run.sh $GALAXY_ROOT_DIR/run.sh

# This needs to happen here and not above, otherwise the Galaxy start
# (without running the startup.sh script) will crash because integrated_tool_panel.xml could not be found.
ENV GALAXY_CONFIG_INTEGRATED_TOOL_PANEL_CONFIG=$EXPORT_DIR/${GALAXY_ROOT_DIR#/}/integrated_tool_panel.xml

# Expose port 80, 443 (webserver), 21 (FTP server), 4002 (Proxy), 9002 (supvisord web app)
EXPOSE 21
EXPOSE 80
EXPOSE 443
EXPOSE 4002
EXPOSE 9002

# Mark folders as imported from the host.
VOLUME ["/export/", "/data/", "/var/lib/docker"]

ADD startup.sh /usr/bin/startup
ENV SUPERVISOR_POSTGRES_AUTOSTART=False \
    SUPERVISOR_MANAGE_POSTGRES=True \
    SUPERVISOR_MANAGE_CRON=True \
    SUPERVISOR_MANAGE_PROFTP=True \
    SUPERVISOR_MANAGE_CONDOR=True \
    SUPERVISOR_MANAGE_SLURM= \
    SUPERVISOR_MANAGE_RABBITMQ=True \
    SUPERVISOR_MANAGE_REDIS=True \
    SUPERVISOR_MANAGE_FLOWER=True \
    GRAVITY_MANAGE_CELERY=True \
    GRAVITY_MANAGE_GX_IT_PROXY=True \
    GRAVITY_MANAGE_TUSD=True \
    GRAVITY_MANAGE_REPORTS=True \
    HOST_DOCKER_LEGACY= \
    STARTUP_EXPORT_USER_FILES=True \
    LOAD_GALAXY_CONDITIONAL_DEPENDENCIES=True

ENTRYPOINT ["/sbin/tini", "--"]

# Autostart script that is invoked during container start
CMD ["/usr/bin/startup"]
