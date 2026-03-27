
#!/bin/bash

# Ce script s'exécute À L'INTÉRIEUR du conteneur ISO builder.
# Il est invoqué par create-iso.sh via podman run.
#
# Variables d'environnement attendues : CENTOS_VERSION, EPEL_VERSION, ARCH
# Volumes attendus :
#   /boot.iso       → boot ISO officiel CentOS Stream (lecture seule)
#   /kickstart.cfg  → kickstart d'installation
#   /output         → répertoire de sortie

set -Eeuo pipefail

PACKAGES_URL="http://localhost:8080/packages/"

WORK_DIR="/tmp/iso-work"
PACKAGES_DIR="${WORK_DIR}/packages"
ISO_TREE="${WORK_DIR}/iso-tree"

##
## Étape 1 : Récupérer tous les packages depuis le miroir local.
##
echo "==> Récupération des packages depuis le miroir local..."
mkdir -p "${PACKAGES_DIR}"

dnf reposync \
  --repofrompath="mirror,${PACKAGES_URL}" \
  --repo=mirror \
  --destdir="${WORK_DIR}/reposync" \
  --download-metadata \
  --norepopath \
  --setopt="mirror.gpgcheck=0"

find "${WORK_DIR}/reposync" -name "*.rpm" -exec mv {} "${PACKAGES_DIR}/" \;

echo "==> Génération des métadonnées du dépôt embarqué..."
createrepo_c "${PACKAGES_DIR}"

##
## Étape 2 : Extraire le contenu du boot ISO officiel.
##
echo "==> Extraction du boot ISO..."
mkdir -p "${ISO_TREE}"
xorriso -osirrox on -indev /boot.iso -extract / "${ISO_TREE}" 2>/dev/null
chmod -R u+w "${ISO_TREE}"

##
## Étape 3 : Intégrer les packages dans l'arbre ISO.
##
echo "==> Intégration des packages dans l'arbre ISO..."
cp -r "${PACKAGES_DIR}" "${ISO_TREE}/Packages"

##
## Étape 4 : Patcher .treeinfo pour déclarer le variant BaseOS.
##
echo "==> Mise à jour de .treeinfo..."
cat >> "${ISO_TREE}/.treeinfo" << 'EOF'

[variant-BaseOS]
id = BaseOS
name = BaseOS
packages = Packages
repository = .
type = variant
uid = BaseOS
EOF

##
## Étape 5 : Modifier les fichiers de boot pour inclure le kickstart automatiquement
##
echo "==> Configuration du kickstart dans les fichiers de boot..."

# Générer le kickstart offline : remplacer la source réseau par cdrom
# et supprimer les directives repo réseau (le .treeinfo déclare le repo embarqué)
sed \
  -e 's|^url --url=.*|cdrom|' \
  -e '/^repo --name=/d' \
  /kickstart.cfg > "${ISO_TREE}/ks.cfg"

# Modifier isolinux.cfg pour BIOS boot
if [ -f "${ISO_TREE}/isolinux/isolinux.cfg" ]; then
    echo "==> Modification d'isolinux.cfg pour BIOS..."
    cp "${ISO_TREE}/isolinux/isolinux.cfg" "${ISO_TREE}/isolinux/isolinux.cfg.orig"
    
    # Remplacer les entrées de boot pour ajouter inst.ks automatiquement
    sed -i 's/append initrd=initrd\.img/append initrd=initrd.img inst.ks=cdrom:\/ks.cfg quiet/' "${ISO_TREE}/isolinux/isolinux.cfg"
    
    # Réduire le timeout pour démarrage automatique (3 secondes)
    sed -i 's/timeout [0-9]*/timeout 30/' "${ISO_TREE}/isolinux/isolinux.cfg"
fi

# Modifier grub.cfg pour UEFI boot
if [ -f "${ISO_TREE}/EFI/BOOT/grub.cfg" ]; then
    echo "==> Modification de grub.cfg pour UEFI..."
    cp "${ISO_TREE}/EFI/BOOT/grub.cfg" "${ISO_TREE}/EFI/BOOT/grub.cfg.orig"
    
    # Ajouter inst.ks aux lignes linuxefi
    sed -i 's/linuxefi \/images\/pxeboot\/vmlinuz/linuxefi \/images\/pxeboot\/vmlinuz inst.ks=cdrom:\/ks.cfg quiet/' "${ISO_TREE}/EFI/BOOT/grub.cfg"
    
    # Réduire le timeout GRUB
    sed -i 's/set timeout=[0-9]*/set timeout=3/' "${ISO_TREE}/EFI/BOOT/grub.cfg"
fi

# Modifier GRUB pour les systèmes plus récents si nécessaire
if [ -f "${ISO_TREE}/EFI/BOOT/grubx64.cfg" ]; then
    echo "==> Modification de grubx64.cfg..."
    cp "${ISO_TREE}/EFI/BOOT/grubx64.cfg" "${ISO_TREE}/EFI/BOOT/grubx64.cfg.orig"
    sed -i 's/linux \/images\/pxeboot\/vmlinuz/linux \/images\/pxeboot\/vmlinuz inst.ks=cdrom:\/ks.cfg quiet/' "${ISO_TREE}/EFI/BOOT/grubx64.cfg"
fi

##
## Étape 6 : Créer un fichier .discinfo personnalisé
##
echo "==> Mise à jour de .discinfo..."
if [ -f "${ISO_TREE}/.discinfo" ]; then
    # Garder la première ligne (timestamp) et modifier les autres
    head -n1 "${ISO_TREE}/.discinfo" > "${ISO_TREE}/.discinfo.new"
    echo "CentOS Stream ${CENTOS_VERSION} Custom Install" >> "${ISO_TREE}/.discinfo.new"
    echo "x86_64" >> "${ISO_TREE}/.discinfo.new"
    mv "${ISO_TREE}/.discinfo.new" "${ISO_TREE}/.discinfo"
fi

##
## Étape 7 : Reconstruire l'ISO finale avec xorriso (sans mkksiso)
##
echo "==> Reconstruction de l'ISO finale..."

# Calculer la taille pour être sûr d'avoir assez d'espace
ISO_SIZE=$(du -sm "${ISO_TREE}" | cut -f1)
echo "==> Taille estimée de l'ISO: ${ISO_SIZE}MB"

xorriso -as mkisofs \
  -o /output/install.iso \
  -R -J -T --joliet-long \
  -V "CS${CENTOS_VERSION}-Custom" \
  -A "CentOS Stream ${CENTOS_VERSION} Custom Installation" \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  --efi-boot images/efiboot.img \
  -eltorito-alt-boot \
  -no-emul-boot \
  "${ISO_TREE}"

##
## Étape 8 : Vérification et résumé
##
echo "==> Vérification de l'ISO créée..."
if [ -f /output/install.iso ]; then
    ISO_FINAL_SIZE=$(ls -lh /output/install.iso | awk '{print $5}')
    echo "==> ISO créée avec succès : install.iso (${ISO_FINAL_SIZE})"
    
    # Optionnel : calculer le checksum
    echo "==> Calcul du checksum MD5..."
    cd /output
    md5sum install.iso > install.iso.md5
    echo "==> Checksum sauvegardé dans install.iso.md5"
else
    echo "==> ERREUR: L'ISO n'a pas été créée correctement"
    exit 1
fi

echo "==> Création de l'ISO terminée avec succès (sans mkksiso)."

