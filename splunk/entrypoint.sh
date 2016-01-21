#!/bin/bash

set -e

# Start rpcbind for NFSv3 mounts
service rpcbind start

# If NFS parameters are passed in then try to mount the target
if [ -n "${NFS_EXPORT+set}" ] && [ -n "${NFS_MOUNT+set}" ]; then
    if [ -e ${NFS_MOUNT} ]; then
        echo "Attempting to mount ${NFS_EXPORT} to ${NFS_MOUNT}"
        mount -t nfs $NFS_EXPORT $NFS_MOUNT
    else
        echo "Creating ${NFS_MOUNT}"
        mkdir -p $NFS_MOUNT
        echo "Attempting to mount ${NFS_EXPORT} to ${NFS_MOUNT}"
        mount -t nfs $NFS_EXPORT $NFS_MOUNT
    fi    
    
    if [ -n "${INDEX_NAME+set}" ]; then
        # Create bucket dirs if they don't already exist
        if [ ! -e ${NFS_MOUNT}/hotwarm ]; then
            mkdir ${NFS_MOUNT}/hotwarm
        fi
        if [ ! -e ${NFS_MOUNT}/cold ]; then
            mkdir ${NFS_MOUNT}/cold
        fi
        if [ ! -e ${NFS_MOUNT}/thawed ]; then
            mkdir ${NFS_MOUNT}/thawed
        fi  
    
        chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${NFS_MOUNT}/*
        chmod -R 775 ${NFS_MOUNT}/*
                   
        # Populate defaults for NFS storage in local index.conf
        echo "[${INDEX_NAME}]" > ${SPLUNK_HOME}/etc/system/local/indexes.conf
        echo "homePath=${NFS_MOUNT}/hotwarm" >> ${SPLUNK_HOME}/etc/system/local/indexes.conf
        echo "coldPath=${NFS_MOUNT}/cold" >> ${SPLUNK_HOME}/etc/system/local/indexes.conf
        echo "thawedPath=${NFS_MOUNT}/thawed" >> ${SPLUNK_HOME}/etc/system/local/indexes.conf
        
        if [ -n "${maxWarmDBCount+set}" ]; then
            echo "maxWarmDBCount=${maxWarmDBCount}" >> ${SPLUNK_HOME}/etc/system/local/indexes.conf
        fi        
        if [ -n "${maxTotalDataSizeMB+set}" ]; then
            echo "maxTotalDataSizeMB=${maxTotalDataSizeMB}" >> ${SPLUNK_HOME}/etc/system/local/indexes.conf
        fi
    
        # Set our default input to use this index
        echo "index = nfsindex" >> ${SPLUNK_HOME}/etc/system/local/inputs.conf
     fi
fi

if [ -n "${FSCK+set}" ]; then
	echo "Offline fsck requested!"
	echo "Copying default Splunk configs from /tmp to /opt/splunk/etc"
	cp -v /tmp/splunk-launch.conf /opt/splunk/etc
	mkdir -p /opt/splunk/etc/myinstall/
	cp -v /tmp/splunkd.xml.cfg-default /opt/splunk/etc/myinstall/
	cp -v /tmp/splunkd.xml.cfg-default /opt/splunk/etc/myinstall/splunkd.xml
	chown -R splunk.splunk /opt/splunk/etc/myinstall/
	chmod 644 /opt/splunk/etc/myinstall/splunkd.xml.cfg-default
	chmod 644 /opt/splunk/etc/myinstall/splunkd.xml
	${SPLUNK_HOME}/bin/splunk fsck repair --all-buckets-all-indexes
	exit 0;
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
