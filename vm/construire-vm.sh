#!/usr/bin/env bash
# Fabrique la VM VMware du labo à partir de l'image cloud OFFICIELLE d'Ubuntu 24.04.
#   ./vm/construire-vm.sh
# Prérequis (Ubuntu ou WSL) : sudo apt install qemu-utils xorriso zip git curl
# Résultat : vm/sortie/TP5-Labo-K8s/ (.vmx + .vmdk + seed-cidata.iso) et vm/sortie/TP5-Labo-K8s.zip
# Seuls les fichiers COMMITÉS du dépôt vont dans la VM : la clé de chiffrement locale n'y est jamais copiée.
set -euo pipefail
cd "$(dirname "$0")"
VM=$PWD
PROJET=$(git rev-parse --show-toplevel)
SORTIE=${SORTIE:-$VM/sortie}
NOM=TP5-Labo-K8s
IMAGE=noble-server-cloudimg-amd64.img
URL=https://cloud-images.ubuntu.com/noble/current
TAILLE_DISQUE=${TAILLE_DISQUE:-40G}

mkdir -p "$SORTIE/cache"
rm -rf "${SORTIE:?}/$NOM" "$SORTIE/$NOM.zip"
mkdir -p "$SORTIE/$NOM"

echo "1/4 Image Ubuntu 24.04 officielle (vérifiée avec l'empreinte publiée par Ubuntu)"
cd "$SORTIE/cache"
[ -f "$IMAGE" ] || curl -fL --retry 5 -o "$IMAGE" "$URL/$IMAGE"
curl -fsSL "$URL/SHA256SUMS" -o SHA256SUMS
grep " \*$IMAGE\$" SHA256SUMS | sha256sum -c -

echo "2/4 Disque VMware de $TAILLE_DISQUE (Ubuntu agrandit sa partition tout seul au 1er démarrage)"
qemu-img convert -O qcow2 "$IMAGE" disque.qcow2
qemu-img resize -q disque.qcow2 "$TAILLE_DISQUE"
qemu-img convert -O vmdk -o subformat=monolithicSparse,adapter_type=lsilogic,compat6 \
  disque.qcow2 "$SORTIE/$NOM/$NOM.vmdk"
rm -f disque.qcow2

echo "3/4 CD de configuration « CIDATA » : cloud-init + projet"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/cidata"
git clone --quiet --no-local "$PROJET" "$TMP/tp5-securisation-k8s"
DEPOT=$(git -C "$PROJET" remote get-url origin 2>/dev/null || true)
if [ -n "$DEPOT" ]; then git -C "$TMP/tp5-securisation-k8s" remote set-url origin "$DEPOT"
else git -C "$TMP/tp5-securisation-k8s" remote remove origin; fi
tar -czf "$TMP/cidata/tp5-securisation-k8s.tar.gz" -C "$TMP" tp5-securisation-k8s
cp "$VM/cloud-init/user-data" "$VM/cloud-init/meta-data" "$TMP/cidata/"
xorriso -as mkisofs -quiet -V CIDATA -J -r -o "$SORTIE/$NOM/seed-cidata.iso" "$TMP/cidata"

echo "4/4 Machine VMware + archive zip"
cp "$VM/$NOM.vmx" "$VM/LISEZMOI-VMware.txt" "$SORTIE/$NOM/"
(cd "$SORTIE" && zip -q -r -1 "$NOM.zip" "$NOM")
ls -lh "$SORTIE/$NOM" "$SORTIE/$NOM.zip"
echo "Terminé : ouvrez $NOM.vmx avec VMware Workstation (Fichier › Ouvrir)."
