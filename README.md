# TP 5 : sécurisation de Kubernetes et du pipeline de déploiement

Application « Boutique Black Friday » (TP 1) et infrastructure Terraform Azure (TP 2), durcies puis protégées par un pipeline qui bloque les déploiements non conformes.

```
Internet ──► frontend (nginx) ──► backend (Python) ──► database (PostgreSQL)
             :8080                :8080                :5432
```

## Contenu du dépôt

| Dossier ou fichier | Rôle |
|---|---|
| `app/` | Code et Dockerfiles **durcis** du frontend et du backend |
| `k8s/` | Manifestes : namespace protégé, RBAC, base, backend, frontend, Network Policies |
| `tests-securite/` | Pods de test « pirates » (privilégié, root, sans droits réseau) |
| `terraform/` | TP 2 corrigé : VM, groupe élastique (VMSS + autoscale), réseau filtré |
| `cluster/` | Politique d'audit et modèle de configuration du chiffrement des Secrets |
| `scripts/` | Démarrage du labo, activation du chiffrement, contrôles de sécurité en local |
| `.github/workflows/` | Pipeline GitHub Actions (Gitleaks, Checkov, Trivy, approbation, déploiement) |
| `avant/` | Versions de départ **volontairement vulnérables** (pour les scans « avant ») |
| `rapports/` | Rapports de scan avant / après correction |
| `NOTE_SYNTHESE.md` | Mesures mises en place et risques résiduels |

## Prérequis

Docker, minikube, kubectl, ainsi que Trivy, Checkov (`pip install checkov`) et Gitleaks. Sous Windows : Docker Desktop (moteur WSL 2) et les commandes depuis un terminal WSL.

## Rejouer le labo

Tout d'un coup, avec un rapport des 35 vérifications dans `~/rapport-labo/` (page web, résumé et détail de chaque commande) :

```bash
./scripts/labo-complet.sh
```

Ou étape par étape :

```bash
./scripts/demarrer-labo.sh                       # cluster + Calico + audit
kubectl apply -f k8s/00-namespace.yaml           # namespace protégé (Pod Security "restricted")
kubectl apply -f k8s/10-rbac.yaml                # comptes et droits limités
kubectl create secret generic db-credentials -n boutique \
  --from-literal=username=boutique \
  --from-literal=password="$(openssl rand -base64 24)"
./scripts/activer-chiffrement.sh                 # chiffrement des Secrets dans etcd
docker build -t boutique-backend:1.0.0 app/backend
docker build -t boutique-frontend:1.0.0 app/frontend
minikube image load boutique-backend:1.0.0 boutique-frontend:1.0.0
kubectl apply -f k8s/                            # application + Network Policies
```

Tests de sécurité :

```bash
kubectl apply -f tests-securite/pod-privilegie.yaml       # doit être REFUSÉ
kubectl auth can-i get secrets -n boutique --as=system:serviceaccount:boutique:deployeur   # no
kubectl apply -f tests-securite/pod-pirate.yaml
kubectl exec -n boutique pirate -- pg_isready -h database -p 5432 -t 3                      # no response
./scripts/controles-securite.sh avant                     # le pipeline BLOQUE la version de départ
./scripts/controles-securite.sh                           # le pipeline ACCEPTE la version corrigée
```

## Machine virtuelle VMware

Le dossier `vm/` fabrique une VM Ubuntu 24.04 qui monte tout le labo seule au premier démarrage
(cloud-init), puis expose le site de la boutique (port 8080) et le rapport des tests (port 8081).

```bash
./vm/construire-vm.sh        # → vm/sortie/TP5-Labo-K8s.zip (vmx + vmdk + seed-cidata.iso)
```

Mode d'emploi côté PC : `vm/LISEZMOI-VMware.txt`.

## Pipeline

Le fichier `.github/workflows/securite-deploiement.yml` lance 3 contrôles en parallèle, puis attend une approbation humaine avant de déployer. Pour activer l'approbation : **Settings › Environments › New environment** « production » › **Required reviewers**.

Toute la procédure détaillée, avec captures et erreurs possibles, est dans la documentation du TP.
