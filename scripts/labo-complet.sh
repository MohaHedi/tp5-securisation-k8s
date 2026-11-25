#!/usr/bin/env bash
# Monte TOUT le labo du TP 5 de A à Z, puis prouve chaque protection par une vraie tentative d'attaque.
#   ./scripts/labo-complet.sh
# Le labo repart de zéro à chaque lancement (le namespace « boutique » est recréé).
# Résultat : ~/rapport-labo/index.html (page web), rapport.txt (résumé), details.txt (chaque commande et sa sortie)
# Taille du cluster réglable : CPUS=2 MEMOIRE=4g ./scripts/labo-complet.sh
# Prérequis : docker, minikube, kubectl, jq, openssl, git, checkov, trivy, gitleaks (+ terraform, facultatif)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

RAPPORT=${RAPPORT:-$HOME/rapport-labo}
mkdir -p "$RAPPORT"
RESULTATS=$RAPPORT/resultats.tsv
DETAILS=$RAPPORT/details.txt
: > "$RESULTATS"
: > "$DETAILS"
rm -f "$RAPPORT/.termine"
export NS=boutique SA=system:serviceaccount:boutique:deployeur
ETAPE="Préparation"
DEBUT=$(date +%s)
PF=""

# ─── Petites fonctions ───────────────────────────────────────────────────────
titre() {
  ETAPE=$1
  printf '\n\033[1;34m━━ %s\033[0m\n' "$1"
  printf '\n=== %s\n' "$1" >> "$DETAILS"
}

# lancer <commande> : une action de mise en place, qui doit réussir
lancer() {
  printf '  \033[2m$ %s\033[0m\n' "$1"
  printf '$ %s\n' "$1" >> "$DETAILS"
  if bash -c "$1" >> "$DETAILS" 2>&1; then return 0; fi
  printf '  \033[1;31m✘ la commande a échoué (détails : %s)\033[0m\n' "$DETAILS"
  return 1
}

# verifier "<ce qu'on prouve>" <attendu> <commande>
#   attendu = reussit | echoue | un texte que la sortie doit contenir
verifier() {
  local quoi=$1 attendu=$2 commande=$3 sortie rc etat
  printf '$ %s\n' "$commande" >> "$DETAILS"
  sortie=$(bash -c "$commande" 2>&1); rc=$?
  printf '%s\n(code de sortie %s)\n' "$sortie" "$rc" >> "$DETAILS"
  case $attendu in
    reussit) if [ "$rc" -eq 0 ]; then etat=OK; else etat=KO; fi ;;
    echoue)  if [ "$rc" -ne 0 ]; then etat=OK; else etat=KO; fi ;;
    *)       if grep -qF -- "$attendu" <<<"$sortie"; then etat=OK; else etat=KO; fi ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\n' "$etat" "$ETAPE" "$quoi" "$commande" \
    "$(head -c 400 <<<"$sortie" | tr '\t\n\r' '   ')" >> "$RESULTATS"
  if [ "$etat" = OK ]; then printf '  \033[1;32m✔\033[0m %s\n' "$quoi"
  else printf '  \033[1;31m✘ %s\033[0m\n' "$quoi"; fi
}

# noter "<information>" <commande> : une mesure, sans attendu (ex. nombre de failles)
noter() {
  local quoi=$1 commande=$2 sortie
  printf '$ %s\n' "$commande" >> "$DETAILS"
  sortie=$(bash -c "$commande" 2>&1)
  printf '%s\n' "$sortie" >> "$DETAILS"
  printf 'INFO\t%s\t%s\t%s\t%s\n' "$ETAPE" "$quoi" "$commande" "$(head -c 400 <<<"$sortie" | tr '\t\n\r' '   ')" >> "$RESULTATS"
  printf '  \033[1;36mℹ\033[0m %s : %s\n' "$quoi" "$(head -c 160 <<<"$sortie" | tr '\n' ' ')"
}

arreter() {
  printf 'KO\t%s\tLabo interrompu : %s\t-\tvoir details.txt\n' "$ETAPE" "$1" >> "$RESULTATS"
  generer_rapport
  printf '\033[1;41;97m  LABO INTERROMPU : %s (détails : %s)  \033[0m\n' "$1" "$DETAILS"
  exit 1
}

ETCD='kubectl exec -n kube-system etcd-minikube -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/var/lib/minikube/certs/etcd/ca.crt --cert=/var/lib/minikube/certs/etcd/server.crt --key=/var/lib/minikube/certs/etcd/server.key get /registry/secrets/boutique/db-credentials'

ouvrir_site() {   # accès temporaire au site (port 18080) le temps des tests
  [ -n "$PF" ] && kill "$PF" 2>/dev/null
  kubectl port-forward -n "$NS" svc/frontend 18080:80 >/dev/null 2>&1 &
  PF=$!
  for _ in $(seq 1 15); do curl -s -o /dev/null localhost:18080 && return 0; sleep 2; done
}

generer_rapport() {
  [ -n "$PF" ] && kill "$PF" 2>/dev/null
  local ok ko duree
  ok=$(grep -c '^OK' "$RESULTATS"); ko=$(grep -c '^KO' "$RESULTATS")
  duree=$(( ($(date +%s) - DEBUT) / 60 ))

  { echo "TP 5 · Rapport du labo — $(date '+%d/%m/%Y %H:%M') — durée ${duree} min"
    echo "Résultat : $ok vérification(s) réussie(s), $ko en échec"
    echo "OK = le labo se comporte comme prévu. Lignes AVANT : sans la protection, l'attaque passe (c'est la preuve du danger)."
    awk -F'\t' '{ s = ($1=="OK") ? "[ OK ]" : ($1=="KO") ? "[ÉCHEC]" : "[INFO]";
                  if ($2 != e) { print "\n" $2; e = $2 }
                  print "  " s " " $3 ($1=="INFO" ? " : " $5 : "") }' "$RESULTATS"
  } > "$RAPPORT/rapport.txt"

  {
    cat <<EOF
<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rapport du labo TP 5</title>
<style>
body{font:16px/1.5 system-ui,sans-serif;margin:0;background:#f6f5f1;color:#1d1d1f}
main{max-width:980px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:28px;margin:0 0 4px}.sous{color:#555;margin:0 0 20px}
.bilan{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:24px}
.bilan div{background:#fff;border-radius:12px;padding:14px 20px;box-shadow:0 1px 3px #0001}
.bilan b{display:block;font-size:30px}.vert{color:#1a7f37}.rouge{color:#c62828}
h2{font-size:19px;margin:28px 0 8px}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px #0001}
td{padding:10px 12px;border-top:1px solid #eee;vertical-align:top}
td.e{width:84px;font-weight:700;white-space:nowrap}
details{margin-top:4px}summary{cursor:pointer;color:#555;font-size:14px}
pre{white-space:pre-wrap;word-break:break-word;background:#1d1d1f;color:#e8e8e8;padding:10px;border-radius:8px;font-size:13px;margin:6px 0 0}
</style></head><body><main>
<h1>Rapport du labo · TP 5 Sécurisation Kubernetes</h1>
<p class="sous">$(date '+%d/%m/%Y à %H:%M') · machine $(hostname) · durée ${duree} min · <a href="details.txt">toutes les commandes et leurs sorties</a></p>
<div class="bilan"><div><b class="vert">$ok</b>vérifications réussies</div><div><b class="$([ "$ko" -eq 0 ] && echo vert || echo rouge)">$ko</b>en échec</div></div>
<p class="sous">OK = le labo se comporte comme prévu. Pour les lignes « AVANT », l'attaque réussit sans la protection : c'est la preuve du danger, rejouée ensuite et bloquée.</p>
EOF
    awk -F'\t' '
      function h(x){ gsub(/&/,"\\&amp;",x); gsub(/</,"\\&lt;",x); gsub(/>/,"\\&gt;",x); return x }
      { if ($2 != e) { if (e != "") print "</table>"; print "<h2>" h($2) "</h2><table>"; e = $2 }
        cls = ($1=="OK") ? "vert" : ($1=="KO") ? "rouge" : ""
        lib = ($1=="OK") ? "✔ OK" : ($1=="KO") ? "✘ ÉCHEC" : "ℹ INFO"
        print "<tr><td class=\"e " cls "\">" lib "</td><td>" h($3) "<details><summary>commande et résultat</summary><pre>$ " h($4) "\n" h($5) "</pre></details></td></tr>" }
      END { if (e != "") print "</table>" }' "$RESULTATS"
    echo "</main></body></html>"
  } > "$RAPPORT/index.html"

  echo
  if [ "$ko" -eq 0 ]; then
    printf '\033[1;42;97m  LABO TERMINÉ : %s vérifications réussies, aucune en échec (%s min)  \033[0m\n' "$ok" "$duree"
  else
    printf '\033[1;43;30m  LABO TERMINÉ : %s réussies, %s en ÉCHEC — voir %s  \033[0m\n' "$ok" "$ko" "$RAPPORT/rapport.txt"
  fi
}

# ─── 0. Outils ───────────────────────────────────────────────────────────────
titre "0. Outils nécessaires"
for outil in docker minikube kubectl jq openssl git checkov trivy gitleaks; do
  command -v "$outil" >/dev/null || arreter "outil manquant : $outil"
done
echo "  tous les outils sont présents"

# ─── 1. Cluster ──────────────────────────────────────────────────────────────
titre "1. Cluster minikube (Calico + journaux d'audit)"
lancer ./scripts/demarrer-labo.sh || arreter "le cluster ne démarre pas"
verifier "Calico, le plugin réseau qui applique les Network Policies, tourne" reussit \
  'kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath="{.items[*].status.phase}" | grep -q Running'
verifier "L'API Server écrit un journal d'audit" reussit \
  'kubectl logs -n kube-system kube-apiserver-minikube | grep -q "\"kind\":\"Event\""'
# On repart de zéro (utile si on relance le script)
lancer 'kubectl delete namespace boutique --ignore-not-found --wait=true --timeout=300s; kubectl delete clusterrolebinding deployeur-admin --ignore-not-found; kubectl config delete-context deployeur@minikube >/dev/null 2>&1; true'

# ─── 2. Images de l'application (TP 1) ───────────────────────────────────────
titre "2. Images Docker de l'application (TP 1)"
lancer 'docker build -q -t boutique-backend:1.0.0 app/backend' || arreter "construction de l'image backend"
lancer 'docker build -q -t boutique-frontend:1.0.0 app/frontend' || arreter "construction de l'image frontend"
lancer 'docker build -q -t boutique-backend:avant -f avant/backend/Dockerfile .' || arreter "construction de l'image de départ"
lancer 'docker pull -q postgres:17-alpine && docker pull -q busybox:1.37' || arreter "téléchargement des images de base"
lancer 'minikube image load boutique-backend:1.0.0 boutique-frontend:1.0.0 postgres:17-alpine busybox:1.37' || arreter "chargement des images dans minikube"
verifier "L'image backend tourne avec un utilisateur normal (pas root)" "10001" \
  'docker inspect boutique-backend:1.0.0 --format "{{.Config.User}}"'

# ─── 3. Pod Security Standards ───────────────────────────────────────────────
titre "3. Étape 1 · Pod Security Standards (le règlement à l'entrée)"
lancer 'kubectl create namespace boutique'
verifier "AVANT : sans règlement, un Pod privilégié est accepté (danger)" reussit \
  'kubectl apply -f tests-securite/pod-privilegie.yaml'
lancer 'kubectl delete pod pod-privilegie -n boutique --now --wait=true'
lancer 'kubectl apply -f k8s/00-namespace.yaml'
verifier "Le namespace applique le niveau « restricted »" "restricted" \
  'kubectl get namespace boutique -o jsonpath="{.metadata.labels.pod-security\.kubernetes\.io/enforce}"'
verifier "APRÈS : un Pod privilégié est REFUSÉ" "violates PodSecurity" \
  'kubectl apply -f tests-securite/pod-privilegie.yaml'
verifier "APRÈS : un Pod qui tourne en root est REFUSÉ" "violates PodSecurity" \
  'kubectl apply -f tests-securite/pod-root.yaml'

# ─── 4. RBAC ─────────────────────────────────────────────────────────────────
titre "4. Étape 2 · RBAC (chacun son badge)"
lancer 'kubectl create serviceaccount deployeur -n boutique && kubectl create clusterrolebinding deployeur-admin --clusterrole=cluster-admin --serviceaccount=boutique:deployeur'
verifier "AVANT : avec cluster-admin, le compte deployeur lit les secrets de tout le cluster (danger)" reussit \
  'kubectl auth can-i get secrets -n kube-system --as=$SA'
lancer 'kubectl delete clusterrolebinding deployeur-admin && kubectl apply -f k8s/10-rbac.yaml'
verifier "deployeur PEUT déployer l'application dans boutique (son travail)" reussit \
  'kubectl auth can-i create deployments -n boutique --as=$SA'
verifier "deployeur PEUT lire les journaux des Pods" reussit \
  'kubectl auth can-i get pods/log -n boutique --as=$SA'
verifier "deployeur NE PEUT PAS lire les Secrets" echoue \
  'kubectl auth can-i get secrets -n boutique --as=$SA'
verifier "deployeur NE PEUT PAS ouvrir un terminal dans un conteneur (exec)" echoue \
  'kubectl auth can-i create pods/exec -n boutique --as=$SA'
verifier "deployeur NE PEUT PAS agir sur kube-system" echoue \
  'kubectl auth can-i create deployments -n kube-system --as=$SA'
verifier "deployeur NE PEUT PAS supprimer un namespace" echoue \
  'kubectl auth can-i delete namespaces --as=$SA'
verifier "deployeur NE PEUT PAS supprimer un nœud" echoue \
  'kubectl auth can-i delete nodes --as=$SA'
lancer 'TOKEN=$(kubectl create token deployeur -n boutique --duration=2h) && kubectl config set-credentials deployeur --token="$TOKEN" >/dev/null && kubectl config set-context deployeur@minikube --cluster=minikube --user=deployeur --namespace=boutique >/dev/null'
verifier "Avec le vrai jeton de deployeur, lire les Secrets est refusé (Forbidden)" "Forbidden" \
  'kubectl --context deployeur@minikube get secrets'

# ─── 5. Secrets et chiffrement ───────────────────────────────────────────────
titre "5. Étape 3 · Secrets chiffrés (le coffre-fort)"
verifier "AVANT : le mot de passe est écrit en clair dans l'image de départ (danger)" "DB_PASSWORD=" \
  'docker inspect boutique-backend:avant --format "{{range .Config.Env}}{{println .}}{{end}}"'
lancer 'kubectl create secret generic db-credentials -n boutique --from-literal=username=boutique --from-literal=password="$(openssl rand -base64 24)"'
lancer ./scripts/activer-chiffrement.sh || arreter "activation du chiffrement"
verifier "L'API Server utilise la configuration de chiffrement" "encryption-provider-config" \
  'kubectl get pod kube-apiserver-minikube -n kube-system -o yaml'
verifier "Dans etcd, le Secret est chiffré (préfixe secretbox)" "k8s:enc:secretbox:v1" \
  "$ETCD | strings | head -3"
verifier "Dans etcd, le mot « password » n'apparaît plus en clair" echoue \
  "$ETCD | strings | grep -q password"
verifier "Les applications autorisées lisent toujours le Secret" "boutique" \
  'kubectl get secret db-credentials -n boutique -o jsonpath="{.data.username}" | base64 -d'

# ─── 6. Déploiement de l'application ─────────────────────────────────────────
titre "6. Déploiement de l'application sécurisée"
lancer 'kubectl apply -f k8s/20-database.yaml -f k8s/30-backend.yaml -f k8s/40-frontend.yaml'
lancer 'kubectl rollout status statefulset/database -n boutique --timeout=300s && kubectl rollout status deployment/backend -n boutique --timeout=300s && kubectl rollout status deployment/frontend -n boutique --timeout=300s' \
  || arreter "l'application ne démarre pas"
ouvrir_site
verifier "Le site répond et affiche les produits de la base" '"prix"' \
  'curl -s --max-time 10 localhost:18080/api/produits'
verifier "Le backend tourne avec l'utilisateur 10001 (pas root)" "uid=10001" \
  'kubectl exec -n boutique deploy/backend -- id'
verifier "Disque en lecture seule : impossible de modifier le code du backend" echoue \
  'kubectl exec -n boutique deploy/backend -- touch /app/pirate.txt'

# ─── 7. Network Policies ─────────────────────────────────────────────────────
titre "7. Étape 4 · Network Policies (des portes fermées)"
lancer 'kubectl apply -f tests-securite/pod-pirate.yaml && kubectl wait --for=condition=Ready pod/pirate -n boutique --timeout=180s'
verifier "AVANT : le Pod pirate joint la base de données (danger)" "accepting connections" \
  'kubectl exec -n boutique pirate -- pg_isready -h database -p 5432 -t 3'
lancer 'kubectl apply -f k8s/50-network-policies.yaml && sleep 10'
verifier "APRÈS : le Pod pirate ne joint plus la base" echoue \
  'kubectl exec -n boutique pirate -- pg_isready -h database -p 5432 -t 3'
verifier "APRÈS : le frontend ne peut pas parler directement à la base" echoue \
  'kubectl exec -n boutique deploy/frontend -- nc -z -w 3 database 5432'
verifier "Le seul chemin ouvert fonctionne : backend → base, port 5432" reussit \
  "kubectl exec -n boutique deploy/backend -- python -c \"import socket; socket.create_connection(('database', 5432), 3)\""
ouvrir_site
verifier "Le site fonctionne toujours après la fermeture des portes" '"prix"' \
  'curl -s --max-time 10 localhost:18080/api/produits'

# ─── 8. Scans de sécurité (Trivy, Checkov, Gitleaks) ─────────────────────────
titre "8. Étape 5 · Scans de sécurité (Trivy, Checkov, Gitleaks)"
noter "Trivy · failles de l'image de départ (python:3.9, root)" \
  'trivy image --quiet --scanners vuln --format json boutique-backend:avant | jq -r "[.Results[].Vulnerabilities[]?.Severity] | group_by(.) | map(\"\(.[0]) \(length)\") | join(\", \")"'
noter "Trivy · failles de l'image corrigée" \
  'trivy image --quiet --scanners vuln --format json boutique-backend:1.0.0 | jq -r "[.Results[].Vulnerabilities[]?.Severity] | group_by(.) | map(\"\(.[0]) \(length)\") | join(\", \")"'
noter "Checkov · version de départ (Kubernetes + Terraform)" \
  'for d in avant/k8s avant/terraform; do printf "%s → " $d; checkov -d $d --compact --quiet 2>/dev/null | grep -m1 "^Passed"; done'
noter "Checkov · version corrigée (Kubernetes + Terraform)" \
  'for d in k8s terraform; do printf "%s → " $d; checkov -d $d --compact --quiet 2>/dev/null | grep -m1 "^Passed"; done'
verifier "Les contrôles du pipeline BLOQUENT la version de départ" echoue \
  './scripts/controles-securite.sh avant'
verifier "Les contrôles du pipeline ACCEPTENT la version corrigée" reussit \
  './scripts/controles-securite.sh'

# ─── 9. Pipeline GitHub Actions ──────────────────────────────────────────────
titre "9. Étape 6 · Pipeline GitHub Actions"
verifier "Le pipeline contient les 3 contrôles et l'approbation humaine (environment production)" "environment: production" \
  'grep -E "gitleaks|checkov|trivy|environment:" .github/workflows/securite-deploiement.yml'

# ─── 10. Journaux d'audit ────────────────────────────────────────────────────
titre "10. Étape 7 · Journaux d'audit (les caméras)"
lancer 'kubectl --context deployeur@minikube get secret db-credentials; kubectl --context deployeur@minikube exec deploy/backend -- id; sleep 3; true'
verifier "Le journal a enregistré qui a tenté de lire le Secret, et le refus (403)" '"code":403' \
  'kubectl logs -n kube-system kube-apiserver-minikube | grep "^{" | jq -c "select(.user.username==\"$SA\" and .objectRef.resource==\"secrets\" and .verb==\"get\") | {heure: .stageTimestamp, qui: .user.username, action: .verb, objet: .objectRef.name, code: .responseStatus.code}" | tail -1'
verifier "Le journal a enregistré la tentative d'exec refusée" '"code":403' \
  'kubectl logs -n kube-system kube-apiserver-minikube | grep "^{" | jq -c "select(.user.username==\"$SA\" and .objectRef.subresource==\"exec\") | {heure: .stageTimestamp, action: .verb, code: .responseStatus.code}" | tail -1'

# ─── 11. Terraform du TP 2 ───────────────────────────────────────────────────
titre "11. Terraform du TP 2 (VM + élasticité Azure)"
if command -v terraform >/dev/null; then
  verifier "Le code Terraform corrigé est valide (fournisseur azurerm)" "Success" \
    'rm -rf /tmp/tf-tp2 && cp -r terraform /tmp/tf-tp2 && cd /tmp/tf-tp2 && terraform init -backend=false -input=false -no-color >/dev/null && terraform validate -no-color'
else
  noter "Terraform" 'echo "non installé : vérification ignorée"'
fi
noter "Ressources décrites (déploiement réel = compte Azure, payant)" \
  'grep -oE "^resource \"[a-z_]+\"" terraform/main.tf | cut -d\" -f2 | sort | uniq -c | awk "{printf \"%s ×%s, \", \$2, \$1}"'

# ─── Fin ─────────────────────────────────────────────────────────────────────
lancer 'kubectl delete pod pirate -n boutique --now --ignore-not-found'
generer_rapport
date '+%d/%m/%Y %H:%M' > "$RAPPORT/.termine"
grep -q '^KO' "$RESULTATS" && exit 1
exit 0
