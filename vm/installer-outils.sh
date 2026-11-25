#!/usr/bin/env bash
# Lancé UNE fois par cloud-init (en root) au 1er démarrage de la VM :
#   1) installe les outils du labo, en versions figées et vérifiées (empreinte SHA-256)
#   2) installe les services : montage du labo, site de la boutique (:8080), rapport (:8081)
#   3) affiche l'état du labo à la connexion
# Journal : /var/log/tp5-installation.log
set -euo pipefail
exec > >(tee -a /var/log/tp5-installation.log) 2>&1

ELEVE=eleve
PROJET=/home/$ELEVE/tp5-securisation-k8s
RAPPORT=/home/$ELEVE/rapport-labo
KUBECTL_VERSION=v1.34.0          # même version que le cluster
MINIKUBE_VERSION=v1.39.0
TERRAFORM_VERSION=1.17.2
CHECKOV_VERSION=3.4.11
TRIVY_IMAGE=aquasec/trivy:0.76.2
GITLEAKS_IMAGE=zricethezav/gitleaks:v8.30.0

etape() { printf '\n==> %s\n' "$1"; }

# telecharger <url> <destination> <empreinte attendue | url du fichier .sha256>
telecharger() {
  local attendu=$3
  case $attendu in http*) attendu=$(curl -fsSL "$attendu" | awk '{print $1}') ;; esac
  curl -fsSL --retry 5 "$1" -o "$2"
  echo "$attendu  $2" | sha256sum -c -
}

etape "Docker : démarrage et accès pour $ELEVE"
usermod -aG docker "$ELEVE"
systemctl enable --now docker
systemctl restart docker          # prend en compte /etc/docker/daemon.json (miroir)

etape "kubectl $KUBECTL_VERSION et minikube $MINIKUBE_VERSION"
telecharger "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl" /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl.sha256"
telecharger "https://storage.googleapis.com/minikube/releases/$MINIKUBE_VERSION/minikube-linux-amd64" /usr/local/bin/minikube \
  "https://storage.googleapis.com/minikube/releases/$MINIKUBE_VERSION/minikube-linux-amd64.sha256"
chmod 755 /usr/local/bin/kubectl /usr/local/bin/minikube

etape "Terraform $TERRAFORM_VERSION (TP 2)"
TMP=$(mktemp -d)
curl -fsSL --retry 5 -o "$TMP/sums" "https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_SHA256SUMS"
telecharger "https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" "$TMP/tf.zip" \
  "$(awk '/linux_amd64.zip$/{print $1}' "$TMP/sums")"
unzip -oq "$TMP/tf.zip" terraform -d /usr/local/bin
rm -rf "$TMP"

etape "Checkov $CHECKOV_VERSION (analyse des fichiers de configuration)"
PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install --force "checkov==$CHECKOV_VERSION"

etape "Trivy et Gitleaks (lancés en conteneur, versions figées)"
docker pull -q "$TRIVY_IMAGE"
docker pull -q "$GITLEAKS_IMAGE"
cat > /usr/local/bin/trivy <<EOF
#!/usr/bin/env bash
# Trivy en conteneur : il lit les images locales via le socket Docker
exec docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ \\
  -v "\$PWD:/projet" -w /projet $TRIVY_IMAGE "\$@"
EOF
cat > /usr/local/bin/gitleaks <<EOF
#!/usr/bin/env bash
# Gitleaks en conteneur, avec l'identité de l'utilisateur (sinon Git refuse un dépôt « d'un autre »)
exec docker run --rm --user "\$(id -u):\$(id -g)" \\
  -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \\
  -v "\$PWD:/projet" -w /projet $GITLEAKS_IMAGE "\$@"
EOF
chmod 755 /usr/local/bin/trivy /usr/local/bin/gitleaks

etape "Services du labo"
install -d -o "$ELEVE" -g "$ELEVE" "$RAPPORT"
cat > /etc/systemd/system/labo-tp5.service <<EOF
[Unit]
Description=TP 5 : montage du labo Kubernetes sécurisé (1er démarrage) ou redémarrage du cluster
Wants=network-online.target
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$ELEVE
Environment=HOME=/home/$ELEVE
WorkingDirectory=$PROJET
ExecStart=$PROJET/vm/demarrage-vm.sh
TimeoutStartSec=infinity

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/boutique-web.service <<EOF
[Unit]
Description=TP 5 : site de la boutique accessible depuis le PC (port 8080)
After=labo-tp5.service
Wants=labo-tp5.service

[Service]
User=$ELEVE
Environment=HOME=/home/$ELEVE
ExecStart=/usr/local/bin/kubectl port-forward --address 0.0.0.0 -n boutique svc/frontend 8080:80
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/rapport-web.service <<EOF
[Unit]
Description=TP 5 : rapport du labo accessible depuis le PC (port 8081)
After=network-online.target

[Service]
User=$ELEVE
ExecStart=/usr/bin/python3 -m http.server 8081 --directory $RAPPORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

etape "Message d'accueil (écran de connexion et après connexion)"
cat > /etc/issue <<'EOF'
Ubuntu 24.04 · VM du TP 5 « Sécurisation de Kubernetes »   (\n, \l)
  Adresse IP : \4
  Identifiant : eleve   ·   mot de passe initial : kubernetes (à changer à la 1re connexion)

EOF
cat > /etc/update-motd.d/90-tp5 <<EOF
#!/bin/sh
R=$RAPPORT
IP=\$(hostname -I | awk '{print \$1}')
echo
echo "  ── TP 5 · Labo Kubernetes sécurisé ──────────────────────────────"
if [ -f \$R/.termine ]; then
  echo "  Labo prêt depuis le \$(cat \$R/.termine)"
  echo "  \$(head -2 \$R/rapport.txt | tail -1)"
  echo "  Depuis le navigateur du PC :"
  echo "    site de la boutique : http://\$IP:8080"
  echo "    rapport des tests   : http://\$IP:8081"
  echo "  Dans ce terminal : cat ~/rapport-labo/rapport.txt   ·   cd ~/tp5-securisation-k8s"
else
  echo "  Le labo se monte tout seul (20 à 40 min au 1er démarrage)."
  echo "  Suivre en direct : tail -f ~/rapport-labo/journal.txt"
fi
echo
EOF
chmod 755 /etc/update-motd.d/90-tp5
chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true

etape "Activation et démarrage du montage du labo (en arrière-plan)"
systemctl daemon-reload
systemctl enable labo-tp5.service boutique-web.service rapport-web.service
systemctl start rapport-web.service
systemctl start --no-block labo-tp5.service boutique-web.service
echo "Installation des outils terminée."
