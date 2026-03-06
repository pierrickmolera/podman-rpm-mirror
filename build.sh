#!/bin/bash

set -Eeuo pipefail

declare CENTOS_VERSION="10"
declare TS="$(date -I)"
declare -a PODMAN_ARGS=()

# Run rsync on the previous dataset if available, to speed up transfer and save on storage.
if podman image inspect "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest" &>/dev/null; then
  PODMAN_ARGS+=( --from "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest" )
fi

podman build -t "localhost/mirrors/centos-stream-${CENTOS_VERSION}:${TS}" "${PODMAN_ARGS[@]}" .
podman tag "localhost/mirrors/centos-stream-${CENTOS_VERSION}:${TS}" "localhost/mirrors/centos-stream-${CENTOS_VERSION}:latest"

# Here you can add the "podman push" command to send the mirror to your registry.
# Do not forget to disable layer compression otherwise the push & pull operations
# will be very slow!
