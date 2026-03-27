# Miroir RPM sélectif et ISO d'installation air-gap pour CentOS Stream 9

Construit un miroir RPM minimal (~1-2 Go) contenant uniquement les packages de
`packages.list` et leurs dépendances, puis génère une ISO d'installation
auto-suffisante (air-gap) pour CentOS Stream 9 avec kernel temps-réel.

## Vue d'ensemble

```
packages.list          build.sh               output/
(source de vérité) --> [sync + ISO build] --> install-centos-stream-9-YYYY-MM-DD.iso
```

Le pipeline en trois étapes :

1. **Sync** — `sync.sh` s'exécute dans un conteneur buildah et télécharge via
   `dnf download --resolve` uniquement les packages listés + leurs dépendances.
2. **Commit** — Le résultat est commité comme image OCI (`localhost/mirrors/centos-stream-9:YYYY-MM-DD`).
3. **ISO** — `create-iso.sh` démarre un pod (miroir nginx + builder), extrait le
   boot ISO officiel, y injecte les packages et le kickstart, et produit l'ISO finale.

---

## Prérequis

```sh
sudo dnf install -y podman buildah
```

Le boot ISO officiel CentOS Stream 9 doit être présent à la racine du projet :

```sh
curl -O https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-boot.iso
mv CentOS-Stream-9-latest-x86_64-boot.iso boot.iso
```

> Ce fichier (~800 Mo) n'est nécessaire que pour la création de l'ISO.
> Il contient l'environnement installeur Anaconda et n'est pas modifié.

---

## Étape 1 — Définir la liste des packages

Éditer `packages.list` pour ajouter ou retirer des packages.

**Syntaxe :**
```
# commentaire (ligne ignorée)
pkg-name        # inclure ce package et ses dépendances
-pkg-name       # exclure ce package (utile pour forcer une variante, ex: -kernel)
```

**Exemple :**
```
# Kernel temps-réel à la place du kernel standard
-kernel
-kernel-core
kernel-rt
kernel-rt-core
```

> `packages.list` est la source de vérité unique. Toute modification nécessite
> de relancer `build.sh` pour régénérer le miroir et l'ISO.

---

## Étape 2 — Construire le miroir

```sh
./build.sh
```

Ce script :

1. Construit l'image de base (`Containerfile.base`) si elle n'existe pas encore —
   CentOS Stream 9 + nginx + createrepo_c + dnf-plugins-core.
2. Crée un conteneur buildah depuis cette image.
3. Monte `packages.list` et `sync.sh` en lecture seule dans le conteneur et exécute
   `sync.sh` à l'intérieur via `buildah run`.
4. `sync.sh` télécharge tous les packages via `dnf download --resolve` depuis les
   repos upstream (BaseOS, AppStream, RT, EPEL) et génère les métadonnées avec
   `createrepo_c`.
5. Commite le résultat comme image `localhost/mirrors/centos-stream-9:YYYY-MM-DD`
   (~2.7 Go).

**Variables d'environnement disponibles :**

| Variable | Défaut | Description |
|----------|--------|-------------|
| `UPSTREAM_CENTOS` | `https://mirror.stream.centos.org` | Miroir CentOS upstream |
| `UPSTREAM_EPEL` | `https://dl.fedoraproject.org/pub/epel` | Miroir EPEL upstream |
| `ARCH` | `x86_64` | Architecture cible |

---

## Étape 3 — Générer l'ISO d'installation

```sh
CREATE_ISO=1 ./build.sh
```

Ce script (via `create-iso.sh` puis `create-iso-inner.sh`) :

1. Démarre un pod composé de deux conteneurs :
   - **mirror** : sert les packages via nginx sur le port 8080
   - **builder** : exécute `create-iso-inner.sh`
2. Récupère tous les packages depuis le miroir via `dnf reposync`.
3. Génère les métadonnées du repo embarqué avec `createrepo_c`.
4. Extrait le boot ISO officiel avec `xorriso`.
5. Copie les packages dans l'arbre ISO sous `/Packages`.
6. Patche `.treeinfo` pour déclarer le variant `BaseOS` avec le dossier `/Packages`.
7. Génère le kickstart offline en remplaçant les URLs réseau par `cdrom`.
8. Injecte `inst.ks=cdrom:/ks.cfg` dans les bootloaders BIOS (`isolinux.cfg`) et
   UEFI (`grub.cfg`).
9. Reconstruit l'ISO avec `xorriso`.

**Résultat :** `./output/install-centos-stream-9-YYYY-MM-DD.iso` (~2.8 Go)

**Variable d'environnement :**

| Variable | Défaut | Description |
|----------|--------|-------------|
| `BOOT_ISO` | `./boot.iso` | Chemin vers le boot ISO officiel |

---

## Étape 4 — Tester l'ISO dans une VM

```sh
virt-install \
  --name test-centos9-rt \
  --memory 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/test-centos9.qcow2,format=qcow2,bus=virtio,size=50 \
  --cdrom ./output/install-centos-stream-9-$(date -I).iso \
  --network network=default \
  --os-variant rhel9-unknown \
  --boot uefi
```

L'installation est entièrement automatique grâce au kickstart embarqué.
La VM s'éteint automatiquement en fin d'installation (`poweroff`).

**Nettoyage après test :**
```sh
virsh destroy test-centos9-rt
virsh undefine test-centos9-rt --nvram
rm -f /var/lib/libvirt/images/test-centos9.qcow2
```

---

## Structure des fichiers

```
.
├── build.sh                # Script principal (miroir + ISO)
├── packages.list           # Source de vérité : packages à inclure
├── sync.sh                 # Téléchargement des packages (s'exécute dans le conteneur)
├── Containerfile.base      # Image de base : CentOS Stream 9 + nginx + outils
├── nginx.conf              # Configuration nginx pour servir les packages
├── kickstart.cfg           # Kickstart d'installation (patché pour cdrom dans l'ISO)
├── create-iso.sh           # Orchestration de la création ISO (pod podman)
├── create-iso-inner.sh     # Construction ISO (s'exécute dans le conteneur builder)
├── boot.iso                # Boot ISO officiel CentOS Stream 9 (à fournir)
└── output/                 # ISO générées
    ├── install-centos-stream-9-YYYY-MM-DD.iso
    └── install-centos-stream-9-YYYY-MM-DD.iso.md5
```

---

## Personnalisation du kickstart

`kickstart.cfg` configure l'installation automatique :

- **Partitionnement** : disque `vda`, partition root XFS unique
- **Réseau** : DHCP sur `enp1s0`, hostname `localhost.localdomain`
- **Compte** : utilisateur `admin` dans le groupe `wheel`, sudo sans mot de passe
- **SSH** : authentification par clé uniquement (mot de passe désactivé)
- **SELinux** : enforcing
- **Post-install** : tous les repos désactivés (mode air-gap)

Adapter les valeurs `rootpw`, `user`, `sshkey`, `network` et `ignoredisk` à
l'environnement cible avant de relancer `CREATE_ISO=1 ./build.sh`.

---

## Chiffres

| Élément | Taille |
|---------|--------|
| Miroir RPM (image OCI) | ~2.7 Go |
| ISO d'installation | ~2.8 Go |
| Packages inclus | ~594 |
| Durée du build (réseau rapide) | ~5-10 min |

---

## Auteurs

- Nicolas Massé
- Claude Code

## Licence

MIT License.
