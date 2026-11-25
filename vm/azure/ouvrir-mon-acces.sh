#!/usr/bin/env bash
# Même chose que ouvrir-mon-acces.ps1, pour Linux, macOS ou WSL (après « az login »)
set -euo pipefail
ip=$(curl -fsS https://api.ipify.org)
echo "Votre adresse IP publique : $ip"
az network nsg rule update -g tp5-labo-rg --nsg-name labo-tp5-nsg -n autoriser-poste-admin \
  --source-address-prefixes "$ip/32" -o none
vm=$(az vm show -d -g tp5-labo-rg -n labo-tp5 --query publicIps -o tsv)
echo "Accès ouvert depuis $ip : http://$vm:8080 (site), http://$vm:8081 (rapport), ssh -i ~/.ssh/cle-tp5-azure eleve@$vm"
