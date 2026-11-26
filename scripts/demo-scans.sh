#!/usr/bin/env bash
# Démonstration en classe : scanner l'image Docker avec Trivy, le Terraform du TP 2 avec Checkov,
# et corriger 3 alertes EN DIRECT. À lancer sur le labo déjà monté (VM Azure ou VMware).
#   ./scripts/demo-scans.sh                 Entrée = étape suivante (environ 10 minutes)
#   DEMO_AUTO=1 ./scripts/demo-scans.sh     sans pause (pour tester avant l'oral)
cd "$(dirname "$0")/.." || exit 1
DEMO=$HOME/demo-checkov

pause() { [ -n "${DEMO_AUTO:-}" ] || read -rp $'\n\033[90m[Entrée] étape suivante...\033[0m '; }
etape() { printf '\n\033[1;34m━━━ %s ━━━\033[0m\n' "$1"; printf '\033[33m À dire : %s\033[0m\n\n' "$2"; }
cmd() { printf '\033[1;32m$ %s\033[0m\n' "$1"; bash -c "$1" 2>&1; echo; }
resume_trivy() { jq -r '[.Results[].Vulnerabilities[]?.Severity] | group_by(.) | map("  \(.[0]) : \(length)") | .[]' "$1"; }

# ─── PARTIE 1 : TRIVY, L'IMAGE DOCKER ───────────────────────────────────────
etape "1.1 Trivy · le Dockerfile de départ" "Voici l'image du backend avant correction : vieille image Python complète, utilisateur root, et un mot de passe écrit en dur."
cmd "cat avant/backend/Dockerfile"
pause

etape "1.2 Trivy · on scanne l'image de départ" "Trivy compare chaque logiciel de l'image à une base de failles connues (les CVE). Résultat : des milliers de failles."
printf '\033[1;32m$ trivy image --scanners vuln boutique-backend:avant\033[0m\n'
trivy image --quiet --scanners vuln --format json boutique-backend:avant > /tmp/trivy-avant.json 2>/dev/null
echo "Nombre de failles par gravité :"; resume_trivy /tmp/trivy-avant.json
echo; echo "5 exemples de failles CRITIQUES :"
jq -r '[.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL")] | unique_by(.VulnerabilityID) | .[:5][] | "  \(.VulnerabilityID)  \(.PkgName) \(.InstalledVersion) → corrigée en \(.FixedVersion // "pas encore")"' /tmp/trivy-avant.json
echo
printf '\033[33m Trivy lit aussi le Dockerfile lui-même (les erreurs de configuration) :\033[0m\n'
cmd "trivy config --quiet --severity HIGH,CRITICAL avant/backend 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g' | grep -E '^Failures|^DS-[0-9]+ ' | cut -c1-110"
pause

etape "1.3 Trivy · les 3 corrections du Dockerfile" "DS-0002 : on ne tourne plus en root (USER 10001). DS-0031 : plus de mot de passe dans l'image. DS-0029 : plus d'apt-get, on part d'une image Alpine récente et légère, ce qui supprime aussi des milliers de failles."
cmd "grep -nE '^FROM|^USER|DB_PASSWORD|pip uninstall' avant/backend/Dockerfile app/backend/Dockerfile"
pause

etape "1.4 Trivy · on scanne l'image corrigée" "Même scan, sur l'image corrigée : il ne reste presque rien, et aucune faille haute ou critique."
printf '\033[1;32m$ trivy image --scanners vuln boutique-backend:1.0.0\033[0m\n'
trivy image --quiet --scanners vuln --format json boutique-backend:1.0.0 > /tmp/trivy-apres.json 2>/dev/null
echo "Nombre de failles par gravité :"; resume_trivy /tmp/trivy-apres.json
cmd "trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 app/backend > /dev/null 2>&1 && echo 'Dockerfile corrigé : 0 erreur haute ou critique' || echo 'Dockerfile corrigé : erreurs restantes'"
pause

etape "1.5 Trivy · la barrière du pipeline" "Dans le pipeline, Trivy renvoie le code 1 s'il trouve une faille haute ou critique corrigeable : la mise en ligne est bloquée."
cmd "trivy image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 boutique-backend:avant > /dev/null 2>&1; echo \"image de départ  → code \$?  (1 = BLOQUÉE)\""
cmd "trivy image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 boutique-backend:1.0.0 > /dev/null 2>&1; echo \"image corrigée → code \$?  (0 = ACCEPTÉE)\""
pause

# ─── PARTIE 2 : CHECKOV, LE TERRAFORM DU TP 2 ───────────────────────────────
rm -rf "$DEMO" && cp -r avant/terraform "$DEMO"
etape "2.1 Checkov · on scanne le Terraform de départ du TP 2" "Checkov relit le code Terraform avant même de créer quoi que ce soit sur Azure. Il trouve 11 alertes."
cmd "cd $DEMO && checkov -d . --compact --quiet | grep -E '^Passed|^Check:'"
pause

etape "2.2 Checkov · correction 1 : le SSH ouvert à tout Internet" "La règle SSH accepte « * », donc le monde entier. On la limite à l'adresse IP de l'administrateur."
python3 - "$DEMO/main.tf" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'(name\s+= "ssh"[\s\S]*?source_address_prefix\s+= )"\*"', r'\1"203.0.113.10/32" # IP de l’administrateur', s, count=1)
open(p, 'w').write(s)
EOF
cmd "cd $DEMO && diff -u $PWD/avant/terraform/main.tf main.tf | grep -E '^[-+][^-+]'"
cmd "cd $DEMO && checkov -d . --check CKV_AZURE_10 --compact --quiet | grep -E '^Passed'"
pause

etape "2.3 Checkov · correction 2 : le mot de passe remplacé par une clé SSH" "Les VM acceptaient un mot de passe, en plus écrit en dur dans le code. On passe à une clé SSH, et le mot de passe disparaît du code."
python3 - "$DEMO/main.tf" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'variable "admin_password" \{[\s\S]*?\n\}', 'variable "cle_ssh_publique" {\n  type        = string\n  description = "Clé SSH PUBLIQUE de l\'administrateur (jamais de mot de passe)"\n}', s, count=1)
s = s.replace('  admin_password                  = var.admin_password\n  disable_password_authentication = false\n',
              '  disable_password_authentication = true\n  admin_ssh_key {\n    username   = "azureuser"\n    public_key = var.cle_ssh_publique\n  }\n')
open(p, 'w').write(s)
EOF
cmd "cd $DEMO && diff -u $PWD/avant/terraform/main.tf main.tf | grep -E '^[-+][^-+]' | grep -v 'source_address_prefix'"
cmd "cd $DEMO && checkov -d . --check CKV_AZURE_1,CKV_AZURE_49,CKV_AZURE_149,CKV_AZURE_178 --compact --quiet | grep -E '^Passed'"
pause

etape "2.4 Checkov · correction 3 : les disques chiffrés sur le serveur" "Les disques du groupe élastique n'étaient pas chiffrés sur le serveur physique d'Azure. Une seule ligne suffit."
python3 - "$DEMO/main.tf" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('  instances                       = 2\n', '  instances                       = 2\n  encryption_at_host_enabled      = true\n', 1)
s = s.replace('  size                            = "Standard_B2s"\n', '  size                            = "Standard_B2s"\n  encryption_at_host_enabled      = true\n', 1)
open(p, 'w').write(s)
EOF
cmd "cd $DEMO && grep -n 'encryption_at_host_enabled' main.tf"
cmd "cd $DEMO && checkov -d . --check CKV_AZURE_97 --compact --quiet | grep -E '^Passed'"
pause

etape "2.5 Checkov · le bilan des 3 corrections" "3 corrections ont supprimé 8 alertes sur 11. Il en reste 3, et elles s'expliquent."
cmd "cd $DEMO && checkov -d . --compact --quiet | grep -E '^Passed|^Check:'"
echo "  CKV_AZURE_160 (HTTP ouvert à Internet) : c'est voulu, un site web doit être public."
echo "  CKV_AZURE_119 (IP publique sur la VM)  : c'est voulu, c'est la porte d'entrée de l'administrateur."
echo "  CKV_AZURE_50  (extensions des VM)      : corrigée dans notre version finale (allow_extension_operations = false)."
pause

etape "2.6 Checkov · notre version finale" "Dans notre vrai code, les 2 exceptions sont écrites dans le code avec leur justification : plus aucune alerte."
cmd "checkov -d terraform --compact --quiet | grep -E '^Passed'"
cmd "grep -n 'checkov:skip' terraform/main.tf"
pause

# ─── PARTIE 3 (bonus) : CHECKOV, LES MANIFESTES KUBERNETES ──────────────────
etape "3. Bonus · Checkov sur les manifestes Kubernetes" "Même outil, sur les fichiers YAML de Kubernetes : 21 alertes au départ, 0 après nos corrections."
cmd "checkov -d avant/k8s --framework kubernetes --compact --quiet | grep -E '^Passed'"
cmd "checkov -d k8s --framework kubernetes --compact --quiet | grep -E '^Passed'"

printf '\n\033[1;42;97m  Démonstration terminée : image et Terraform scannés, 3 corrections faites en direct.  \033[0m\n'
printf "\033[33m À dire : les scanners trouvent les erreurs avant la mise en ligne ; dans le pipeline, ils bloquent tout seuls.\033[0m\n"
