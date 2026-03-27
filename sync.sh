#!/bin/bash

# Ce script s'exécute À L'INTÉRIEUR du conteneur buildah via "buildah run".
# Il télécharge uniquement les packages de /packages.list et leurs dépendances.
# Nécessite un accès internet.

set -Eeuo pipefail

ARCH="${ARCH:-x86_64}"
CENTOS_VERSION="${CENTOS_VERSION:-9}"
EPEL_VERSION="${EPEL_VERSION:-${CENTOS_VERSION}}"
UPSTREAM_CENTOS="${UPSTREAM_CENTOS:-https://mirror.stream.centos.org}"
UPSTREAM_EPEL="${UPSTREAM_EPEL:-https://dl.fedoraproject.org/pub/epel}"

BASEOS_URL="${UPSTREAM_CENTOS}/${CENTOS_VERSION}-stream/BaseOS/${ARCH}/os/"
APPSTREAM_URL="${UPSTREAM_CENTOS}/${CENTOS_VERSION}-stream/AppStream/${ARCH}/os/"
RT_URL="${UPSTREAM_CENTOS}/${CENTOS_VERSION}-stream/RT/${ARCH}/os/"
EPEL_URL="${UPSTREAM_EPEL}/${EPEL_VERSION}/Everything/${ARCH}/"

PACKAGES_DIR="/var/www/packages"
mkdir -p "${PACKAGES_DIR}"

# Extraire la liste des packages (ignorer commentaires, lignes vides, exclusions)
mapfile -t PACKAGES < <(grep -v '^[[:space:]]*[#-]' /packages.list | grep -v '^[[:space:]]*$')

# Construire les flags d'exclusion (-x pkg) pour dnf5
EXCLUDE_FLAGS=()
while IFS= read -r pkg; do
  [[ -n "$pkg" ]] && EXCLUDE_FLAGS+=(-x "$pkg")
done < <(grep '^[[:space:]]*-' /packages.list | sed 's/^[[:space:]]*-[[:space:]]*//')

# coreutils-single est la variante allégée installée dans les images containers
# CentOS Stream 9. Elle entre en conflit avec coreutils (version complète) que
# nous voulons dans l'ISO. On la supprime avant le téléchargement.
echo "==> Suppression des packages containers incompatibles avec l'ISO cible..."
dnf remove -y coreutils-single 2>/dev/null || true

echo "==> Téléchargement de ${#PACKAGES[@]} packages + dépendances..."
echo "==> Exclusions : ${EXCLUDE_FLAGS[*]:-aucune}"

# "dnf download --resolve" télécharge les packages et toutes leurs dépendances
# sans tenir compte de ce qui est installé dans le conteneur.
# Les noms "up-*" évitent les conflits avec les repos système du conteneur.
dnf download \
  --resolve \
  --releasever="${CENTOS_VERSION}" \
  --repofrompath="up-baseos,${BASEOS_URL}" \
  --repofrompath="up-appstream,${APPSTREAM_URL}" \
  --repofrompath="up-rt,${RT_URL}" \
  --repofrompath="up-epel,${EPEL_URL}" \
  --repo=up-baseos --repo=up-appstream --repo=up-rt --repo=up-epel \
  --destdir="${PACKAGES_DIR}" \
  --nogpgcheck \
  --skip-broken \
  --allowerasing \
  "${EXCLUDE_FLAGS[@]+"${EXCLUDE_FLAGS[@]}"}" \
  "${PACKAGES[@]}"

echo "==> Génération des métadonnées du dépôt..."
createrepo_c "${PACKAGES_DIR}"

echo "==> Nettoyage du cache dnf..."
dnf clean all

RPM_COUNT=$(find "${PACKAGES_DIR}" -name "*.rpm" | wc -l)
TOTAL_SIZE=$(du -sh "${PACKAGES_DIR}" | cut -f1)
echo "==> Synchronisation terminée : ${RPM_COUNT} packages, ${TOTAL_SIZE} au total."
