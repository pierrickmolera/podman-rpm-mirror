#!/bin/bash

set -Eeuo pipefail

# Version de CentOS Stream à miroir.
declare CENTOS_VERSION="9"
declare EPEL_VERSION="${EPEL_VERSION:-${CENTOS_VERSION}}"
declare ARCH="${ARCH:-x86_64}"

# Miroirs upstream (modifiables via variables d'environnement)
declare UPSTREAM_CENTOS="${UPSTREAM_CENTOS:-https://mirror.stream.centos.org}"
declare UPSTREAM_EPEL="${UPSTREAM_EPEL:-https://dl.fedoraproject.org/pub/epel}"

declare IMAGE_BASE="localhost/mirrors/centos-stream-${CENTOS_VERSION}"
declare IMAGE_TAG="$(date -I)"

##
## Première étape : construire l'image de base si elle n'existe pas.
##
if ! podman image inspect "${IMAGE_BASE}:base" &>/dev/null; then
  echo "Construction de l'image de base..."
  podman build \
    --file Containerfile.base \
    -t "${IMAGE_BASE}:base" \
    --security-opt label=disable \
    .
fi

##
## Deuxième étape : construire l'image miroir avec les packages sélectionnés.
##
if ! podman image inspect "${IMAGE_BASE}:latest" &>/dev/null; then
  podman tag "${IMAGE_BASE}:base" "${IMAGE_BASE}:latest"
fi

BUILDAH_CONTAINER_NAME="buildah-sync-centos-${CENTOS_VERSION}"
if buildah inspect "${BUILDAH_CONTAINER_NAME}" &>/dev/null; then
  echo "Reprise du conteneur buildah existant : ${BUILDAH_CONTAINER_NAME}"
else
  echo "Création du conteneur buildah depuis ${IMAGE_BASE}:latest..."
  buildah from --name="${BUILDAH_CONTAINER_NAME}" "${IMAGE_BASE}:latest"
fi

# Préparer le conteneur en résolvant les conflits
echo "==> Préparation du conteneur (résolution des conflits)..."
buildah run "${BUILDAH_CONTAINER_NAME}" -- bash -c '
    if rpm -q coreutils-single &>/dev/null; then
        dnf swap -y coreutils-single coreutils --allowerasing || 
        dnf remove -y coreutils-single
    fi
'


# Exécuter sync.sh À L'INTÉRIEUR du conteneur.
# packages.list et sync.sh sont montés en lecture seule le temps de l'exécution.
# Les packages téléchargés persistent dans la couche inscriptible du conteneur.
echo "Démarrage du téléchargement des packages..."
# Chemin absolu requis par buildah run --volume
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
export CENTOS_VERSION EPEL_VERSION ARCH UPSTREAM_CENTOS UPSTREAM_EPEL
buildah run \
  --network=host \
  --env CENTOS_VERSION \
  --env EPEL_VERSION \
  --env ARCH \
  --env UPSTREAM_CENTOS \
  --env UPSTREAM_EPEL \
  --volume "${SCRIPT_DIR}/packages.list:/packages.list:ro,z" \
  --volume "${SCRIPT_DIR}/sync.sh:/sync.sh:ro,z" \
  "${BUILDAH_CONTAINER_NAME}" \
  -- bash /sync.sh

# Finaliser l'image
echo "Création de l'image finale ${IMAGE_BASE}:${IMAGE_TAG}..."
BUILDAH_TMPDIR="${HOME}/.local/share/buildah-tmp"
mkdir -p "${BUILDAH_TMPDIR}"
export TMPDIR="${BUILDAH_TMPDIR}"
buildah commit --quiet "${BUILDAH_CONTAINER_NAME}" "${IMAGE_BASE}:${IMAGE_TAG}"
buildah tag "${IMAGE_BASE}:${IMAGE_TAG}" "${IMAGE_BASE}:latest"
buildah rm "${BUILDAH_CONTAINER_NAME}"

echo "Build terminé. Image : ${IMAGE_BASE}:${IMAGE_TAG}"

##
## Troisième étape (optionnelle) : créer l'ISO bootable.
## Activer avec : CREATE_ISO=1 ./build.sh
##
if [ "${CREATE_ISO:-0}" = "1" ]; then
  export IMAGE_BASE CENTOS_VERSION
  "${BASH_SOURCE[0]%/*}/create-iso.sh"
fi
