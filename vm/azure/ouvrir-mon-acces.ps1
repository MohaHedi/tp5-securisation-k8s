# Ouvre l'accès à la VM du labo depuis le réseau où vous êtes en ce moment (maison, école, partage 4G…)
# et ferme l'ancien : une seule adresse autorisée à la fois.
# Usage (PowerShell, après « az login ») :  .\vm\azure\ouvrir-mon-acces.ps1
$ip = (Invoke-RestMethod https://api.ipify.org).Trim()
Write-Host "Votre adresse IP publique : $ip"
az network nsg rule update -g tp5-labo-rg --nsg-name labo-tp5-nsg -n autoriser-poste-admin `
  --source-address-prefixes "$ip/32" -o none
$vm = az vm show -d -g tp5-labo-rg -n labo-tp5 --query publicIps -o tsv
Write-Host "Accès ouvert depuis $ip :"
Write-Host "  site de la boutique : http://${vm}:8080"
Write-Host "  rapport des tests   : http://${vm}:8081"
Write-Host "  terminal            : ssh -i `$HOME\.ssh\cle-tp5-azure eleve@$vm"
