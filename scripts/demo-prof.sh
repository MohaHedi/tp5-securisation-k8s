#!/usr/bin/env bash
# Démonstration en direct pour le professeur, sur le labo déjà monté (VM Azure ou VMware).
# Chaque étape : ce qu'il faut dire, la commande, le vrai résultat. Entrée = étape suivante.
#   ./scripts/demo-prof.sh                  démonstration complète (environ 10 minutes)
#   DEMO_AUTO=1 ./scripts/demo-prof.sh      sans pause (pour tester avant l'oral)
#   TP2_SITE=1.2.3.4 ./scripts/demo-prof.sh adresse du site du TP 2 (charge de l'étape 0)
cd "$(dirname "$0")/.." || exit 1
SA=system:serviceaccount:boutique:deployeur
TP2_SITE=${TP2_SITE:-9.205.92.166}
ETCD='kubectl exec -n kube-system etcd-minikube -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/var/lib/minikube/certs/etcd/ca.crt --cert=/var/lib/minikube/certs/etcd/server.crt --key=/var/lib/minikube/certs/etcd/server.key'

pause() { [ -n "${DEMO_AUTO:-}" ] || read -rp $'\n\033[90m[Entrée] étape suivante...\033[0m '; }
etape() { printf '\n\033[1;34m━━━ %s ━━━\033[0m\n' "$1"; printf '\033[33m À dire : %s\033[0m\n\n' "$2"; }
cmd() { printf '\033[1;32m$ %s\033[0m\n' "$1"; bash -c "$1" 2>&1; echo; }
oui_non() { [ -n "${DEMO_AUTO:-}" ] && return 1; read -rp "$1 [o/N] " r; [ "$r" = o ] || [ "$r" = O ]; }

# Préparation silencieuse : le jeton du compte deployeur expire, on en recrée un pour la démo
TOKEN=$(kubectl create token deployeur -n boutique --duration=1h) &&
  kubectl config set-credentials deployeur --token="$TOKEN" >/dev/null &&
  kubectl config set-context deployeur@minikube --cluster=minikube --user=deployeur --namespace=boutique >/dev/null
kubectl delete pod pirate -n boutique --ignore-not-found --now >/dev/null 2>&1

etape "0. Le labo tourne" "Un vrai Kubernetes (minikube) avec Calico, et la boutique du TP 1 : 5 Pods."
cmd "kubectl get nodes"
cmd "kubectl get pods -n boutique"
if oui_non "Lancer la charge sur le site du TP 2 (300 visiteurs pendant 10 min, pour voir l'élasticité à la fin) ?"; then
  nohup ab -k -c 300 -t 600 -n 100000000 "http://$TP2_SITE/" > /tmp/charge-tp2.log 2>&1 &
  echo "Charge lancée vers http://$TP2_SITE : regardez le nombre de VM dans le portail Azure dans 7 à 10 minutes."
fi
pause

etape "1. Pod Security Standards : le règlement à l'entrée" "Le namespace applique le niveau restricted : un Pod qui demande tous les pouvoirs est refusé dès la porte."
cmd "kubectl get namespace boutique -L pod-security.kubernetes.io/enforce"
cmd "kubectl apply -f tests-securite/pod-privilegie.yaml"
cmd "kubectl apply -f tests-securite/pod-root.yaml"
pause

etape "2. RBAC : chacun son badge" "Le compte deployeur peut déployer l'application, mais ni lire les mots de passe, ni ouvrir un terminal, ni toucher au reste."
cmd "kubectl auth can-i create deployments -n boutique --as=$SA"
cmd "kubectl auth can-i get secrets -n boutique --as=$SA"
cmd "kubectl auth can-i create pods/exec -n boutique --as=$SA"
cmd "kubectl auth can-i delete nodes --as=$SA"
printf '\033[33m Vraie tentative avec le jeton du compte :\033[0m\n'
cmd "kubectl --context deployeur@minikube get secrets"
pause

etape "3. Secrets chiffrés : le coffre-fort" "Le mot de passe n'est plus dans le code. Dans etcd, la base de Kubernetes, il est chiffré : on ne lit que secretbox et des caractères illisibles."
cmd "kubectl get secret db-credentials -n boutique"
cmd "$ETCD get /registry/secrets/boutique/db-credentials | strings | head -3 | cut -c1-60"
pause

etape "4. Network Policies : des portes fermées" "Tout est fermé par défaut. Un Pod pirate qui respecte les règles de sécurité ne joint pourtant pas la base : seul le backend y a droit."
cmd "kubectl get networkpolicy -n boutique"
cmd "kubectl apply -f tests-securite/pod-pirate.yaml && kubectl wait --for=condition=Ready pod/pirate -n boutique --timeout=120s"
cmd "kubectl exec -n boutique pirate -- pg_isready -h database -p 5432 -t 3"
cmd "kubectl exec -n boutique deploy/backend -- python -c \"import socket; socket.create_connection(('database', 5432), 3); print('backend vers base : autorisé')\""
cmd "curl -s localhost:8080/api/produits"
pause

etape "5. Scans : le contrôle qualité" "Trivy cherche les failles de l'image, Checkov les erreurs de réglage, Gitleaks les mots de passe oubliés."
if oui_non "Rejouer les 3 contrôles sur la version de départ, puis sur la version corrigée (environ 3 minutes) ?"; then
  cmd "./scripts/controles-securite.sh avant"
  cmd "./scripts/controles-securite.sh"
else
  cmd "sed -n '/Étape 5/,/Étape 6/p' ~/rapport-labo/rapport.txt | head -8"
fi
pause

etape "6. Pipeline GitHub Actions : robots puis humain" "À chaque envoi sur GitHub, les 3 contrôles tournent, puis un humain doit approuver avant la mise en ligne."
echo "Montrer dans le navigateur : https://github.com/MohaHedi/tp5-securisation-k8s/actions"
echo "  - le 1er passage, en échec : Checkov a bloqué un Dockerfile sans contrôle de santé"
echo "  - le 2e passage, vert, avec l'approbation de MohaHedi, puis le déploiement réussi"
pause

etape "7. Journaux d'audit : les caméras" "On fait une action interdite avec le compte deployeur, et le journal la garde : qui, quoi, quand, et le refus."
cmd "kubectl --context deployeur@minikube get secret db-credentials"
sleep 3
cmd "kubectl logs -n kube-system kube-apiserver-minikube | grep '^{' | jq -c 'select(.user.username==\"$SA\" and .objectRef.resource==\"secrets\" and .verb==\"get\") | {heure: .stageTimestamp, qui: .user.username, action: .verb, objet: .objectRef.name, code: .responseStatus.code}' | tail -1"
pause

kubectl delete pod pirate -n boutique --now --ignore-not-found >/dev/null 2>&1
printf '\n\033[1;42;97m  Démonstration terminée : chaque attaque a été bloquée.  \033[0m\n'
printf "\033[33m À dire : 4 niveaux de protection (personnes, réseau, conteneurs, données), contrôlés par le pipeline et enregistrés par l'audit.\033[0m\n"
echo "Rapport complet des 35 vérifications : http://<IP de la VM>:8081"
