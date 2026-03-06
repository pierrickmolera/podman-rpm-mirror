#!/bin/bash

set -Eeuo pipefail

# Compute podman command line arguments
declare -a PODMAN_ARGS=()

# Inject the desired CentOS Stream version as build arguments
declare CENTOS_VERSION="10"
PODMAN_ARGS+=( --arg CENTOS_VERSION="${CENTOS_VERSION}" --arg EPEL_VERSION="${CENTOS_VERSION}" )

# Tag the resulting image with the current date
declare TS="$(date -I)"
PODMAN_ARGS+=( -t "localhost/mirrors/centos-stream-${CENTOS_VERSION}:${TS}" )

# Run rsync on the previous dataset if available, to speed up transfer and save on storage.
if podman image inspect "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest" &>/dev/null; then
  PODMAN_ARGS+=( --from "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest" )
fi

# Build the image.
# Note: during the build, the repositories will be synced and the result will be stored in the image.
podman build "${PODMAN_ARGS[@]}" .
podman tag "localhost/mirrors/centos-stream-${CENTOS_VERSION}:${TS}" "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest"

# Here you can add the "podman push" command to send the mirror to your registry.
# Do not forget to disable layer compression otherwise the push & pull operations
# will be very slow!
