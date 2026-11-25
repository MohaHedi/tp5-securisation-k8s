#!/usr/bin/env bash
# Lancé à chaque démarrage de la VM par le service labo-tp5 (utilisateur eleve) :
#   1er démarrage : monte tout le labo et teste chaque protection (scripts/labo-complet.sh)
#   ensuite       : redémarre simplement le cluster déjà monté
# Journal : ~/rapport-labo/journal.txt
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
RAPPORT=$HOME/rapport-labo
mkdir -p "$RAPPORT"
exec >> "$RAPPORT/journal.txt" 2>&1
echo "===== $(date '+%d/%m/%Y %H:%M') · démarrage de la VM"

# Le cluster prend la mémoire de la VM moins 2,5 Go (laissés à Ubuntu, Docker et aux scanners)
memoire=$(( $(free -m | awk '/^Mem:/{print $2}') - 2560 ))
[ "$memoire" -lt 3000 ] && memoire=3000
CPUS=$(nproc)
export MEMOIRE=${memoire}m CPUS

if [ -f "$RAPPORT/.termine" ]; then
  echo "Labo déjà monté : redémarrage du cluster"
  minikube start || exit 1
  # Au redémarrage, minikube peut régénérer le manifeste de l'API Server : on remet le chiffrement (même clé)
  ./scripts/activer-chiffrement.sh || exit 1
  kubectl wait --for=condition=Ready pods --all -n boutique --timeout=600s
else
  # Le labo est jugé monté même si une vérification échoue : le rapport le signale
  ./scripts/labo-complet.sh
  [ -f "$RAPPORT/.termine" ] || exit 1
fi
exit 0
