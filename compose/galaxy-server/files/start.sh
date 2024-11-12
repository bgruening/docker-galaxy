#!/bin/bash

create_user() {
  GALAXY_PROXY_PREFIX=$(cat $GALAXY_CONFIG_DIR/GALAXY_PROXY_PREFIX.txt)
  echo "Waiting for Galaxy..."
  until [ "$(curl -L -s -o /dev/null -w '%{http_code}' ${GALAXY_URL:-nginx}$GALAXY_PROXY_PREFIX)" -eq "200" ] && echo Galaxy started; do
    sleep 0.1;
  done;
  echo "Creating admin user $GALAXY_DEFAULT_ADMIN_USER with key $GALAXY_DEFAULT_ADMIN_KEY and password $GALAXY_DEFAULT_ADMIN_PASSWORD if not existing"
  . $GALAXY_VIRTUAL_ENV/bin/activate
  python /usr/local/bin/create_galaxy_user.py --user "$GALAXY_DEFAULT_ADMIN_EMAIL" --password "$GALAXY_DEFAULT_ADMIN_PASSWORD" \
  -c "$GALAXY_CONFIG_FILE" --username "$GALAXY_DEFAULT_ADMIN_USER" --key "$GALAXY_DEFAULT_ADMIN_KEY"
  deactivate
}

# start copy lib/tools. Looks very hacky.
tools_dir="/galaxy/lib/galaxy/tools/"
exp_dir="/export$tools_dir"
mkdir -p $exp_dir
chown "$GALAXY_USER:$GALAXY_USER" $exp_dir
cp -rf $tools_dir/* $exp_dir
# end copy lib/tools.

# First start?? Check if something exists that indicates that environment is not new.. Config file? Something in DB maybe??

echo "Initialization: Check if files already exist, export otherwise."

# Create initial $GALAXY_ROOT in $EXPORT_DIR if not already existent
mkdir -p "$EXPORT_DIR/$GALAXY_ROOT"

declare -A exports=( ["$GALAXY_STATIC_DIR"]="$EXPORT_DIR/$GALAXY_STATIC_DIR" \
                     ["$GALAXY_CONFIG_TOOL_PATH"]="$EXPORT_DIR/$GALAXY_CONFIG_TOOL_PATH" \
                     ["$GALAXY_CONFIG_TOOL_DEPENDENCY_DIR"]="$EXPORT_DIR/$GALAXY_CONFIG_TOOL_DEPENDENCY_DIR" \
                     ["$GALAXY_CONFIG_TOOL_DATA_PATH"]="$EXPORT_DIR/$GALAXY_CONFIG_TOOL_DATA_PATH" \
                     ["$GALAXY_VIRTUAL_ENV"]="$EXPORT_DIR/$GALAXY_VIRTUAL_ENV" )

# shellcheck disable=SC2143,SC2086,SC2010
for galaxy_dir in "${!exports[@]}"; do
  exp_dir=${exports[$galaxy_dir]}
  if [ ! -d  $exp_dir ] || [ -z "$(ls -A $exp_dir)" ]; then
    echo "Exporting $galaxy_dir to $exp_dir"
    mkdir $exp_dir
    chown "$GALAXY_USER:$GALAXY_USER" $exp_dir
    cp -rpf $galaxy_dir/* $exp_dir
  fi
  rm -rf $galaxy_dir
  ln -v -s $exp_dir $galaxy_dir
  chown -h "$GALAXY_USER:$GALAXY_USER" $galaxy_dir
done

# Export galaxy_config seperately (special treatment because of plugins-dir)
# shellcheck disable=SC2143,SC2086,SC2010
if [ ! -d  "$EXPORT_DIR/$GALAXY_CONFIG_DIR" ] || [ -z "$(ls -p $EXPORT_DIR/$GALAXY_CONFIG_DIR | grep -v /)" ]; then
  # Move config to $EXPORT_DIR and create symlink
  mkdir "$EXPORT_DIR/$GALAXY_CONFIG_DIR"
  chown "$GALAXY_USER:$GALAXY_USER" "$EXPORT_DIR/$GALAXY_CONFIG_DIR"
  cp -rpf $GALAXY_CONFIG_DIR/* $EXPORT_DIR/$GALAXY_CONFIG_DIR
  cp -rpf $GALAXY_CONFIG_DIR/plugins/* $EXPORT_DIR/$GALAXY_CONFIG_DIR/plugins
fi
rm -rf "$GALAXY_CONFIG_DIR"
ln -v -s "$EXPORT_DIR/$GALAXY_CONFIG_DIR" "$GALAXY_CONFIG_DIR"
chown -h "$GALAXY_USER:$GALAXY_USER" "$GALAXY_CONFIG_DIR"

# Export database-folder (used for job files etc)
rm -rf "$GALAXY_DATABASE_PATH"
mkdir -p "$EXPORT_DIR/$GALAXY_DATABASE_PATH"
chown "$GALAXY_USER:$GALAXY_USER" "$EXPORT_DIR/$GALAXY_DATABASE_PATH"
ln -v -s "$EXPORT_DIR/$GALAXY_DATABASE_PATH" "$GALAXY_DATABASE_PATH"
chown -h "$GALAXY_USER:$GALAXY_USER" "$GALAXY_DATABASE_PATH"

# Try to guess if we are running under --privileged mode
if mount | grep "/proc/kcore"; then
  PRIVILEGED=false
else
  PRIVILEGED=true
  echo "Privileged mode detected"
  chmod 666 /var/run/docker.sock
fi

if $PRIVILEGED; then
  echo "Mounting CVMFS"
  chmod 666 /dev/fuse
  if [ ! -d /cvmfs/data.galaxyproject.org ] ; then mkdir /cvmfs/data.galaxyproject.org ; fi
  mount -t cvmfs data.galaxyproject.org /cvmfs/data.galaxyproject.org
  if [ ! -d /cvmfs/singularity.galaxyproject.org ] ; then mkdir /cvmfs/singularity.galaxyproject.org ; fi
  mount -t cvmfs singularity.galaxyproject.org /cvmfs/singularity.galaxyproject.org
fi

echo "Finished initialization"

echo "Waiting for RabbitMQ..."
until nc -z -w 2 rabbitmq 5672 && echo RabbitMQ started; do
  sleep 1;
done;

echo "Waiting for Postgres..."
until nc -z -w 2 postgres 5432 && echo Postgres started; do
  sleep 1;
done;

if [ "$SKIP_LOCKING" != "true" ]; then
  echo "Waiting for Galaxy configurator to finish and release lock"
  until [ ! -f "$GALAXY_CONFIG_DIR/configurator.lock" ] && echo Lock released; do
    sleep 0.1;
  done;
fi

if [ -f "/htcondor_config/galaxy.conf" ]; then
  echo "HTCondor config file found"

  cp -f "/htcondor_config/galaxy.conf" /etc/condor/condor_config.local
  echo "Starting HTCondor.."
  service condor start
fi

if [ -f /etc/munge/munge.key ]; then
  echo "Munge key found"
  echo "Starting Munge.."
  /etc/init.d/munge start
fi

# In case the user wants the default admin to be created, do so.
if [[ -n $GALAXY_DEFAULT_ADMIN_USER ]]; then
  # Run in background and wait for Galaxy having finished starting up
  create_user &
fi

# Ensure proper permission (the configurator might have changed them "by mistake")
chown -RL "$GALAXY_USER:$GALAXY_GROUP" "$GALAXY_CONFIG_DIR"

echo "Starting Galaxy now.."
cd "$GALAXY_ROOT" || { echo "Error: Could not change to $GALAXY_ROOT"; exit 1; }
HOME=/home/galaxy "$GALAXY_VIRTUAL_ENV/bin/uwsgi" --yaml "$GALAXY_CONFIG_DIR/galaxy.yml" --uid "$GALAXY_UID" --gid "$GALAXY_GID"
