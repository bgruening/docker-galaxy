#!/bin/bash
set -e

if [ "$1" = './wait-for-it.sh' ]; then
    if [ -z "$(getent passwd $RUN_USER)" ]; then
      echo "Creating user $RUN_USER:$RUN_GROUP"
      mkdir -p ${IRIDA_DATA_DIR}
      groupadd --gid ${RUN_GROUP_GID} -r ${RUN_GROUP} && \
      useradd --uid ${RUN_USER_UID} -g ${RUN_GROUP} -d /home/${CATALINA_HOME} ${RUN_USER}
      rm -rf ${CATALINA_HOME}/logs
      rm -rf ${CATALINA_HOME}/webapps
      rm -rf ${CATALINA_HOME}/temp
      chown -R ${RUN_USER}:${RUN_GROUP}        ${CATALINA_HOME}/                   \
          && gosu ${RUN_USER} mkdir -p ${CATALINA_HOME}/logs                       \
          && gosu ${RUN_USER} mkdir -p ${CATALINA_HOME}/webapps                    \
          && gosu ${RUN_USER} mkdir -p ${CATALINA_HOME}/temp                    \
          && chown -R ${RUN_USER}:${RUN_GROUP} ${CATALINA_HOME}/work               \
          && chown -R ${RUN_USER}:${RUN_GROUP} ${CATALINA_HOME}/conf               \
          && chown -R ${RUN_USER}:${RUN_GROUP} ${IRIDA_DATA_DIR} .                 \
          && gosu ${RUN_USER} mkdir -p ${IRIDA_DATA_DIR}/{sequence,reference,output,assembly}
    fi

	exec gosu "${RUN_USER}:${RUN_GROUP}" "$@"
fi

exec "$@"
