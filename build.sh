#!/bin/bash

set -Eeuo pipefail

# The version of CentOS Stream to mirror.
declare CENTOS_VERSION="10"
declare EPEL_VERSION="${EPEL_VERSION:-${CENTOS_VERSION}}"

# Sync process configuration
declare IMAGE_BASE="localhost/mirrors/centos-stream-${CENTOS_VERSION}"
declare IMAGE_TAG="$(date -I)"
declare RSYNC_MIRROR="${RSYNC_MIRROR:-rsync://mirror.in2p3.fr}"
declare CENTOS_PATH="${CENTOS_PATH:-/pub/linux/centos-stream}"
declare EPEL_PATH="${EPEL_PATH:-/pub/epel}"
declare RSYNC_OPTS="-azH --progress --delete --exclude-from=${BASH_SOURCE[0]%/*}/rsync-excludes.txt"

# Pre-requisites
if ! rsync -V &>/dev/null; then
  echo "rsync is required on the host to synchronize the repositories. Please install it and try again." >&2
  exit 1
fi

##
## First stage: build the base image with the necessary tools to synchronize the repositories.
##
if ! podman image inspect "${IMAGE_BASE}:base" &>/dev/null; then
  # Compute podman command line arguments
  declare -a PODMAN_ARGS=()
  PODMAN_ARGS+=( --file Containerfile.base )
  PODMAN_ARGS+=( -t "${IMAGE_BASE}:base" )
  podman build "${PODMAN_ARGS[@]}" .
fi

##
## Second stage: build the image with the synchronized repositories using buildah.
##
if ! podman image inspect "${IMAGE_BASE}:latest" &>/dev/null; then
  podman tag "${IMAGE_BASE}:base" "${IMAGE_BASE}:latest"
fi

# TODO: Maybe let the user specify the Buildah container name to be able have different sessions running in parallel?
# Currently, the container name is deterministic to be able to resume a build if it fails or is interrupted.
# In that case, the synchronization will be resumed from the last successful step instead of starting from scratch.
# But, it is assumed that only one build per version of CentOS Stream is running at the same time to avoid conflicts on the container name.
BUILDAH_CONTAINER_NAME="buildah-sync-centos-${CENTOS_VERSION}"
if buildah inspect "$BUILDAH_CONTAINER_NAME" &>/dev/null; then
  echo "Resuming build with existing Buildah container: ${BUILDAH_CONTAINER_NAME}"
else
   # Create Buildah container from the base image.
  echo "Creating Buildah container from ${IMAGE_BASE}:latest..."
  BUILDAH_CONTAINER_NAME=$(buildah from --name="${BUILDAH_CONTAINER_NAME}" "${IMAGE_BASE}:latest")
fi

# Expect unprivileged buildah, so it is mandatory to run the sync script from an dedicated user namespace.
echo "Starting synchronization in a modified user namespace..."
export CENTOS_VERSION EPEL_VERSION RSYNC_MIRROR CENTOS_PATH EPEL_PATH RSYNC_OPTS
if [ $UID -eq 0 ]; then
  function cleanup {
    if [ -n "$container_to_umount" ]; then
      buildah umount "$container_to_umount" || true
    fi
  }
  trap cleanup EXIT
  export BUILDAH_ROOT=$(buildah mount "$BUILDAH_CONTAINER_NAME")
  container_to_umount="$BUILDAH_CONTAINER_NAME"
  "${BASH_SOURCE[0]%/*}/sync.sh"
else
  buildah unshare --mount=BUILDAH_ROOT="$BUILDAH_CONTAINER_NAME" "${BASH_SOURCE[0]%/*}/sync.sh"
fi

# Finalize the image
echo "Creating final image ${IMAGE_BASE} with tag ${IMAGE_TAG} + latest..."
buildah umount "$BUILDAH_CONTAINER_NAME"
container_to_umount="" # Unset the variable so that the cleanup function does not try to unmount it again.
buildah commit --quiet "$BUILDAH_CONTAINER_NAME" "${IMAGE_BASE}:${IMAGE_TAG}"
buildah tag "${IMAGE_BASE}:${IMAGE_TAG}" "${IMAGE_BASE}:latest"
buildah rm "$BUILDAH_CONTAINER_NAME"

echo "Build complete."
