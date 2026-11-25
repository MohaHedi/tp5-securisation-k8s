#!/usr/bin/env bash
# Active le chiffrement des Secrets au repos (etcd) sur un cluster minikube.
# Étapes : 1) générer une clé  2) copier la configuration dans le nœud
#          3) déclarer le fichier dans le manifeste de l'API Server  4) re-chiffrer les Secrets existants
set -euo pipefail
cd "$(dirname "$0")/.."

CONF=cluster/encryption-config.yaml        # ignoré par Git (.gitignore)
CIBLE=/etc/kubernetes/enc/encryption-config.yaml
MANIFESTE=/etc/kubernetes/manifests/kube-apiserver.yaml

echo "1/4 Génération d'une clé aléatoire de 32 octets"
CLE=$(head -c 32 /dev/urandom | base64)
sed "s|<CLE_32_OCTETS_EN_BASE64_GENEREE_PAR_LE_SCRIPT>|${CLE}|" cluster/encryption-config.exemple.yaml > "$CONF"
chmod 600 "$CONF"

echo "2/4 Copie de la configuration dans le nœud minikube"
minikube ssh -- "sudo mkdir -p /etc/kubernetes/enc && sudo chmod 700 /etc/kubernetes/enc"
minikube cp "$CONF" "minikube:${CIBLE}"
minikube ssh -- "sudo chmod 600 ${CIBLE}"

echo "3/4 Ajout du paramètre, du volume et du point de montage dans l'API Server"
# Sauvegarde HORS du dossier manifests : le kubelet lance tous les fichiers qui s'y trouvent !
minikube ssh -- "sudo cp ${MANIFESTE} /root/kube-apiserver.yaml.sauvegarde"
if minikube ssh -- "sudo grep -q encryption-provider-config ${MANIFESTE}" >/dev/null 2>&1; then
  echo "Déjà activé."; exit 0
fi
minikube ssh -- "sudo sed -i \
  -e '/^    - kube-apiserver\$/a\\    - --encryption-provider-config=${CIBLE}' \
  -e '/^    volumeMounts:\$/a\\    - mountPath: /etc/kubernetes/enc\\n      name: enc\\n      readOnly: true' \
  -e '/^  volumes:\$/a\\  - hostPath:\\n      path: /etc/kubernetes/enc\\n      type: DirectoryOrCreate\\n    name: enc' \
  ${MANIFESTE}"

echo "    Attente du redémarrage de l'API Server…"
sleep 20
until kubectl get --raw=/readyz >/dev/null 2>&1; do sleep 5; done

echo "4/4 Ré-écriture des Secrets existants pour qu'ils soient chiffrés"
kubectl get secrets --all-namespaces -o json | kubectl replace -f - >/dev/null
echo "Chiffrement au repos activé."
