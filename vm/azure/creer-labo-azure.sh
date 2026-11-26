#!/usr/bin/env bash
# Crée sur Azure la VM du labo TP 5 : même installation automatique que la VM VMware
# (cloud-init + vm/installer-outils.sh), le labo complet se monte seul au 1er démarrage.
#   ./vm/azure/creer-labo-azure.sh <votre IP publique> [clé publique SSH]
# Prérequis : az login. Variables : REGION (denmarkeast), RG (tp5-labo-rg), TAILLE (Standard_B2as_v2)
# Supprimer tout ensuite :  az group delete -n tp5-labo-rg --yes
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
IP_ADMIN=${1:?"Usage : $0 <votre IP publique> [clé publique SSH]"}
CLE=${2:-$HOME/.ssh/id_ed25519.pub}
REGION=${REGION:-denmarkeast}
RG=${RG:-tp5-labo-rg}
VM=labo-tp5
TAILLE=${TAILLE:-Standard_B2as_v2}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "1/5 Configuration cloud-init avec le projet (fichiers commités, sans la vidéo ni les captures)"
git archive --format=tar --prefix=tp5-securisation-k8s/ HEAD -- . ':!docs' ':!rapports' | xz -9e > "$TMP/projet.tar.xz"
cat > "$TMP/user-data" <<EOF
#cloud-config
# VM Azure du TP 5 : pas de CD CIDATA sur Azure, le projet voyage dans cette configuration
# (texte en ASCII uniquement : les accents ont ete abimes en route lors du premier essai)
hostname: $VM
locale: fr_FR.UTF-8
timezone: Europe/Paris
write_files:
  - path: /etc/docker/daemon.json
    content: |
      {"registry-mirrors": ["https://mirror.gcr.io"]}
  - path: /etc/ssh/sshd_config.d/10-tp5-port443.conf
    content: |
      # SSH aussi sur le port 443, que les reseaux d'ecole bloquent rarement
      Port 22
      Port 443
  - path: /var/lib/tp5/projet.tar.xz
    encoding: b64
    content: $(base64 -w0 "$TMP/projet.tar.xz")
runcmd:
  - tar -xJf /var/lib/tp5/projet.tar.xz -C /home/eleve
  - git -C /home/eleve/tp5-securisation-k8s init -q
  - git -C /home/eleve/tp5-securisation-k8s add -A
  - git -C /home/eleve/tp5-securisation-k8s -c user.name="Groupe TP5" -c user.email=groupe-tp5@users.noreply.github.com commit -qm "Projet TP 5"
  - chown -R eleve:eleve /home/eleve/tp5-securisation-k8s
  - bash /home/eleve/tp5-securisation-k8s/vm/installer-outils.sh
  - [sh, -c, "printf 'VM Azure du TP 5 - connexion par cle SSH uniquement (ssh eleve@IP)\\n\\n' > /etc/issue"]
EOF
if LC_ALL=C grep -q '[^ -~]' "$TMP/user-data"; then echo "La configuration doit rester en ASCII"; exit 1; fi
if command -v cloud-init >/dev/null; then cloud-init schema -c "$TMP/user-data" || exit 1; fi
taille=$(base64 -w0 "$TMP/user-data" | wc -c)
echo "    configuration : $taille octets encodés (limite Azure : 65 536)"
[ "$taille" -le 65536 ] || { echo "Configuration trop grande pour Azure"; exit 1; }

echo "2/5 Groupe de ressources $RG ($REGION)"
az group create -n "$RG" -l "$REGION" -o none

echo "3/5 Pare-feu : SSH (22 et 443), site (8080) et rapport (8081) ouverts UNIQUEMENT pour $IP_ADMIN"
az network nsg create -g "$RG" -n "$VM-nsg" -o none
az network nsg rule create -g "$RG" --nsg-name "$VM-nsg" -n autoriser-poste-admin --priority 100 \
  --source-address-prefixes "$IP_ADMIN" --destination-port-ranges 22 443 8080 8081 --protocol Tcp --access Allow -o none

echo "4/5 VM $TAILLE Ubuntu 24.04 : clé SSH seulement, disques chiffrés sur l'hôte, démarrage sécurisé (10 min de création, puis 30 à 50 min de montage du labo)"
az vm create -g "$RG" -n "$VM" --image Canonical:ubuntu-24_04-lts:server:latest --size "$TAILLE" \
  --admin-username eleve --authentication-type ssh --ssh-key-values "$CLE" \
  --nsg "$VM-nsg" --public-ip-sku Standard --os-disk-size-gb 64 --storage-sku StandardSSD_LRS \
  --encryption-at-host true --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true \
  --custom-data "$TMP/user-data" -o none

echo "5/5 Arrêt automatique chaque soir à 19 h, heure de Paris (18:00 UTC) pour économiser le crédit"
if ! az vm auto-shutdown -g "$RG" -n "$VM" --time 1800 -o none 2>/dev/null; then
  echo "    Arrêt automatique indisponible dans la région $REGION : arrêtez la VM après usage :"
  echo "    az vm deallocate -g $RG -n $VM      (et pour la relancer : az vm start -g $RG -n $VM)"
fi

IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
# Le message de connexion de la VM affiche cette IP publique (la VM ne voit que son IP privée)
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
  --scripts "mkdir -p /var/lib/tp5 && echo $IP > /var/lib/tp5/ip-publique" -o none
cat <<EOF

VM créée : $IP
  Suivre le montage du labo :  ssh eleve@$IP 'tail -f ~/rapport-labo/journal.txt'
  Site de la boutique       :  http://$IP:8080
  Rapport des tests         :  http://$IP:8081
  Tout supprimer            :  az group delete -n $RG --yes
EOF
