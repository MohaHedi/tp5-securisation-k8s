#!/usr/bin/env bash
# Rejoue en local les 3 contrôles du pipeline GitHub Actions.
#   ./scripts/controles-securite.sh          → contrôle le code actuel (version corrigée)
#   ./scripts/controles-securite.sh avant    → contrôle la version de départ (dossier avant/)
# Prérequis : gitleaks, checkov et trivy installés (ou leurs images Docker).
cd "$(dirname "$0")/.." || exit 1
MODE=${1:-apres}
ECHECS=0

etape() { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }
ok()    { printf '\033[1;32m  ✔ %s\033[0m\n' "$1"; }
ko()    { printf '\033[1;31m  ✘ %s\033[0m\n' "$1"; ECHECS=$((ECHECS + 1)); }

if [ "$MODE" = "avant" ]; then
  SECRETS_CIBLE=avant; K8S=avant/k8s; TF=avant/terraform; IMAGE=boutique-backend:avant
else
  SECRETS_CIBLE=.;     K8S=k8s;       TF=terraform;       IMAGE=boutique-backend:1.0.0
fi

etape "1/3 Secrets (Gitleaks) : $SECRETS_CIBLE"
# Comme le pipeline : en mode normal on scanne l'historique Git (les fichiers ignorés par Git ne comptent pas)
if [ "$MODE" = "avant" ]; then COMMANDE=(gitleaks dir avant); else COMMANDE=(gitleaks git .); fi
if "${COMMANDE[@]}" --no-banner --redact --log-level error >/dev/null 2>&1; then
  ok "aucun secret trouvé"
else
  ko "secrets détectés dans le code"
fi

etape "2/3 Infrastructure as Code (Checkov) : $K8S + $TF"
for dossier in "$K8S" "$TF"; do
  resume=$(checkov -d "$dossier" --compact --quiet 2>/dev/null | grep -E '^Passed' | head -1)
  if checkov -d "$dossier" --compact --quiet >/dev/null 2>&1; then
    ok "$dossier → $resume"
  else
    ko "$dossier → $resume"
  fi
done

etape "3/3 Image Docker (Trivy) : $IMAGE"
if trivy image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE" >/dev/null 2>&1; then
  ok "aucune faille HAUTE ou CRITIQUE corrigeable"
else
  total=$(trivy image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --format json "$IMAGE" 2>/dev/null \
          | jq '[.Results[].Vulnerabilities[]?] | length')
  ko "$total failles HAUTES ou CRITIQUES corrigeables"
fi

echo
if [ "$ECHECS" -eq 0 ]; then
  printf '\033[1;42;97m  RÉSULTAT : tous les contrôles sont verts → le déploiement peut être approuvé  \033[0m\n'
else
  printf '\033[1;41;97m  RÉSULTAT : %s contrôle(s) en échec → DÉPLOIEMENT BLOQUÉ  \033[0m\n' "$ECHECS"
  exit 1
fi
