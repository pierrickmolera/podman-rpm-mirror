#!/bin/bash

set -Eeuo pipefail

# The version of CentOS Stream to mirror.
declare CENTOS_VERSION="10"

##
## First stage: build the base image with the necessary tools to synchronize the repositories.
##
if ! podman image inspect "localhost/mirrors/centos-stream-${CENTOS_VERSION}:base" &>/dev/null; then
  # Compute podman command line arguments
  declare -a PODMAN_ARGS=()
  PODMAN_ARGS+=( --file Containerfile.base )
  PODMAN_ARGS+=( -t "localhost/mirrors/centos-stream-${CENTOS_VERSION}:base" )
  podman build "${PODMAN_ARGS[@]}" .
fi

##
## Second stage: build the image with the synchronized repositories.
##
if ! podman image inspect "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest" &>/dev/null; then
  podman tag "localhost/mirrors/centos-stream-${CENTOS_VERSION}:base" "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest"
fi

# Tag the resulting image with the current date
declare TS="$(date -I)"

# Compute podman command line arguments
declare -a PODMAN_ARGS=()
PODMAN_ARGS+=( --build-arg CENTOS_VERSION="${CENTOS_VERSION}" --build-arg EPEL_VERSION="${CENTOS_VERSION}" )
PODMAN_ARGS+=( --file Containerfile.sync )
PODMAN_ARGS+=( --from "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest" )
PODMAN_ARGS+=( -t "localhost/mirrors/centos-stream-${CENTOS_VERSION}:${TS}" )
podman build "${PODMAN_ARGS[@]}" .

# Tag the image with "latest" as well.
podman tag "localhost/mirrors/centos-stream-${CENTOS_VERSION}:${TS}" "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest"

# Here you can add the "podman push" command to send the mirror to your registry.
# Do not forget to disable layer compression otherwise the push & pull operations
# will be very slow!
