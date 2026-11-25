# Ouvre l'accès à la VM du labo depuis le réseau où vous êtes en ce moment (maison, école, partage 4G...)
# et ferme l'ancien : une seule adresse autorisée à la fois.
# Lancer :  powershell -ExecutionPolicy Bypass -File .\ouvrir-mon-acces.ps1   (après « az login »)
# Chaque commande tient sur UNE ligne : on peut aussi copier-coller le fichier entier dans PowerShell.
$abonnement = "Azure for Students"
$ip = (Invoke-RestMethod https://api.ipify.org).Trim()
Write-Host "Votre adresse IP publique : $ip"
az network nsg rule update --subscription $abonnement -g tp5-labo-rg --nsg-name labo-tp5-nsg -n autoriser-poste-admin --source-address-prefixes "$ip/32" -o none
if ($LASTEXITCODE -ne 0) { Write-Host "ÉCHEC : rien n'a été changé. Vérifiez « az login » et l'abonnement « $abonnement » (az account list -o table)." -ForegroundColor Red; return }
$vm = az vm show --subscription $abonnement -d -g tp5-labo-rg -n labo-tp5 --query publicIps -o tsv
Write-Host "Accès ouvert depuis $ip :" -ForegroundColor Green
Write-Host "  site de la boutique : http://${vm}:8080"
Write-Host "  rapport des tests   : http://${vm}:8081"
Write-Host "  terminal            : ssh -i $HOME\.ssh\cle-tp5-azure eleve@$vm"
