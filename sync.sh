#!/bin/bash

set -Eeuo pipefail

# Create directory structure
echo "Creating directory structure..."
mkdir -p "${BUILDAH_ROOT}/var/www/centos/${CENTOS_VERSION}-stream"
mkdir -p "${BUILDAH_ROOT}/var/www/epel/${EPEL_VERSION}"

# Start synchronization using rsync with the specified options
echo "Starting synchronization from ${RSYNC_MIRROR}..."
rsync ${RSYNC_OPTS} "${RSYNC_MIRROR}${CENTOS_PATH}/${CENTOS_VERSION}-stream/" "${BUILDAH_ROOT}/var/www/centos/${CENTOS_VERSION}-stream/"
rsync ${RSYNC_OPTS} "${RSYNC_MIRROR}${EPEL_PATH}/${EPEL_VERSION}/" "${BUILDAH_ROOT}/var/www/epel/${EPEL_VERSION}/"

echo "Synchronization complete."
