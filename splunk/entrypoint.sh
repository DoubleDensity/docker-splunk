#!/bin/bash

set -e

# If NFS parameters are passed in then try to mount the target
if [ -n "${NFS_EXPORT+set}" ] && [ -n "${NFS_MOUNT+set}" ]; then
    if [ -e ${NFS_MOUNT} ]; then
        mount -t nfs $NFS_EXPORT $NFS_MOUNT
    else
        mkdir $NFS_MOUNT
        mount -t nfs $NFS_EXPORT $NFS_MOUNT
    fi
    
    # Create bucket dirs if they don't already exist
    if [ ! -e ${NFS_MOUNT}/hotwarm ]; then
        mkdir ${NFS_MOUNT}/hotwarm
    fi
    if [ ! -e ${NFS_MOUNT}/cold ]; then
        mkdir ${NFS_MOUNT}/cold
    fi
    
    # Populate defaults for NFS storage in local index.conf
    echo "[nfsindex]" > ${SPLUNK_HOME}/etc/system/local/indexes.conf
    echo "homePath=${NFS_MOUNT}/hotwarm" >> ${SPLUNK_HOME}/etc/system/local/indexes.conf
    echo "coldPath=${NFS_MOUNT}/cold" >> ${SPLUNK_HOME}/etc/system/local/indexes.conf
    
    # Set our default input to use this index
    echo "index = [nfsindex]" >> ${SPLUNK_HOME}/etc/system/local/inputs.conf
fi



if [ "$1" = 'splunk' ]; then
  shift
  sudo -HEu ${SPLUNK_USER} ${SPLUNK_HOME}/bin/splunk "$@"
elif [ "$1" = 'start-service' ]; then
  # If user changed SPLUNK_USER to root we want to change permission for SPLUNK_HOME
  if [[ "${SPLUNK_USER}:${SPLUNK_GROUP}" != "$(stat --format %U:%G ${SPLUNK_HOME})" ]]; then
    chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${SPLUNK_HOME}
  fi

  # If these files are different override etc folder (possible that this is upgrade or first start cases)
  # Also override ownership of these files to splunk:splunk
  if ! $(cmp --silent /var/opt/splunk/etc/splunk.version ${SPLUNK_HOME}/etc/splunk.version); then
    cp -fR /var/opt/splunk/etc ${SPLUNK_HOME}
    chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${SPLUNK_HOME}/etc
    chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${SPLUNK_HOME}/var
  fi

  sudo -HEu ${SPLUNK_USER} ${SPLUNK_HOME}/bin/splunk start --accept-license --answer-yes --no-prompt
  trap "sudo -HEu ${SPLUNK_USER} ${SPLUNK_HOME}/bin/splunk stop" SIGINT SIGTERM EXIT

  if [[ -n ${SPLUNK_FORWARD_SERVER} ]]; then
    if ! sudo -HEu ${SPLUNK_USER} ${SPLUNK_HOME}/bin/splunk list forward-server -auth admin:changeme | grep -q "${SPLUNK_FORWARD_SERVER}"; then
      sudo -HEu ${SPLUNK_USER} ${SPLUNK_HOME}/bin/splunk add forward-server "${SPLUNK_FORWARD_SERVER}" -auth admin:changeme
    fi
  fi

  sudo -HEu ${SPLUNK_USER} tail -n 0 -f ${SPLUNK_HOME}/var/log/splunk/splunkd_stderr.log &
  wait
else
  "$@"
fi
