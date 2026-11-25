# Note de synthèse : risques résiduels (TP 5)

## 1. Ce qui a été mis en place

| Mesure | Ce qu'elle empêche | Preuve dans le labo |
|---|---|---|
| RBAC limité au namespace `boutique` | Un compte de déploiement compromis ne peut ni lire les Secrets, ni entrer dans un Pod, ni toucher aux autres namespaces | `kubectl auth can-i` : 3 « yes », 5 « no » ; vraies tentatives refusées en `403 Forbidden` |
| Network Policies (deny-all + flux autorisés) | Un Pod compromis ne peut pas joindre la base de données | `pg_isready` du Pod pirate : *accepting connections* → *no response* |
| Pod Security Standards `restricted` | Pods privilégiés, root, avec élévation de privilèges ou sans seccomp | Pods `pod-privilegie` et `pod-root` refusés à la création |
| Secret généré au hasard, monté en fichier | Mot de passe dans le code, dans l'image ou dans Git | `gitleaks` : 4 fuites dans la version de départ, 0 après |
| Chiffrement des Secrets au repos (`secretbox`) | Lecture des mots de passe par quelqu'un qui accède à etcd ou à ses sauvegardes | etcd contient `k8s:enc:secretbox:v1:cle-tp5` au lieu du mot de passe en clair |
| Images durcies (alpine, multi-étapes, non-root) | Failles connues, outils exploitables par un attaquant | Trivy backend : 15 134 failles (236 critiques) → 12 (0 haute, 0 critique) |
| Analyse IaC (Checkov) | Mauvaises configurations Kubernetes, Terraform, Dockerfile | Terraform 11 → 0 échec, Kubernetes 22 → 0, Dockerfile 2 → 0 |
| Pipeline bloquant + approbation | Déploiement d'un code non conforme ou non validé par un humain | `.github/workflows/securite-deploiement.yml` ; script local `controles-securite.sh` |
| Journaux d'audit de l'API Server | Actions non tracées | Actions du compte `deployeur` retrouvées (heure, action, ressource, code 200/403) |

## 2. Risques résiduels

Note : **P** = probabilité, **I** = impact (F = faible, M = moyen, É = élevé).

| # | Risque résiduel | P | I | Pourquoi il reste | Mesure recommandée |
|---|---|---|---|---|---|
| 1 | La clé de chiffrement etcd est stockée sur le même nœud que les données | M | É | Le fournisseur `secretbox` utilise une clé locale : qui vole le disque du nœud vole aussi la clé | En production : **KMS v2** avec **Azure Key Vault** (option native d'AKS), rotation régulière de la clé |
| 2 | Les images ne sont pas référencées par **digest** et il n'y a pas de registre privé | M | É | Labo minikube sans registre (exceptions Checkov CKV_K8S_43 et CKV_K8S_15 documentées) | Pousser les images dans **Azure Container Registry**, les référencer par `@sha256:…`, signer avec **cosign** et n'accepter que les images signées (Kyverno ou Azure Policy) |
| 3 | De nouvelles failles apparaissent chaque jour dans les images | É | M | Trivy ne voit que les failles connues le jour du scan ; il reste 12 failles faibles/moyennes (backend) | Scan planifié chaque nuit, mises à jour automatiques (Dependabot ou Renovate), reconstruction régulière des images |
| 4 | 3 failles HAUTES (musl, zlib) dans l'image frontend **du labo** | F | M | Le miroir Alpine était bloqué dans l'environnement du labo, donc `apk upgrade` n'a pas pu s'exécuter | Sur une machine normale et dans le pipeline GitHub, `apk upgrade` (déjà dans le Dockerfile) les corrige ; le pipeline bloque tant qu'elles existent |
| 5 | Les scanners ne détectent pas tout | M | É | Le mot de passe par défaut du Terraform de départ n'a été vu **ni par Gitleaks ni par Checkov** | Revue de code obligatoire (pull request), règles Gitleaks personnalisées, hook `pre-commit` sur les postes |
| 6 | Un secret déjà poussé reste dans l'historique Git | M | É | Supprimer le fichier ne supprime pas les anciens commits | Considérer le secret comme compromis : **le changer immédiatement**, puis nettoyer l'historique (`git filter-repo`) |
| 7 | Qui peut créer un Pod dans le namespace peut lire le Secret (en le montant) | F | É | RBAC sur les Secrets ne couvre pas ce chemin indirect | Limiter qui peut créer des Pods, utiliser un **CSI Secrets Store** relié à Azure Key Vault, surveiller les accès dans l'audit |
| 8 | Le trafic entre Pods n'est pas chiffré | F | M | Les Network Policies filtrent, mais ne chiffrent pas | Chiffrement mTLS par un service mesh (Linkerd, Istio) ou chiffrement WireGuard avec Calico/Cilium ; TLS vers PostgreSQL |
| 9 | Les journaux d'audit sont dans la sortie de l'API Server | M | M | Ils disparaissent au redémarrage et un administrateur pourrait les effacer | Les envoyer vers un SIEM (Azure Monitor / Log Analytics, Elastic), avec rétention et alertes ; ajouter **Falco** pour surveiller les Pods en fonctionnement |
| 10 | Les Network Policies dépendent du plugin réseau | F | É | Sans plugin compatible, elles sont ignorées **sans aucune erreur** | Vérifier le plugin (Calico ici) et garder un test automatique « le pirate ne joint pas la base » |
| 11 | Chaîne d'approvisionnement du pipeline | F | É | Les actions GitHub sont référencées par version, pas par empreinte | Épingler chaque action par SHA de commit, Dependabot pour les mettre à jour, permissions minimales (déjà en lecture seule) |
| 12 | Identité du pipeline en production | M | É | La démo déploie sur un cluster kind éphémère avec un compte administrateur | En production : connexion **OIDC** sans secret long terme (`azure/login`) et déploiement avec le compte limité `deployeur` |
| 13 | Fichier d'état Terraform (TP 2) | M | É | Le state contient l'infrastructure (parfois des secrets) ; le backend distant est préparé mais commenté | Activer le backend `azurerm` (stockage chiffré, accès Azure AD, verrouillage, versionnement) ; ne jamais versionner `*.tfstate` (déjà dans `.gitignore`) |
| 14 | Données de la base non persistantes et non sauvegardées | É | M | Le labo utilise un `emptyDir` | PersistentVolume chiffré, sauvegardes testées (Velero), ou base managée (Azure Database for PostgreSQL) |

## 3. Conclusion

Le cluster applique maintenant le **moindre privilège** à quatre niveaux : les **personnes** (RBAC), le **réseau** (Network Policies), les **conteneurs** (Pod Security Standards, images durcies) et les **données** (Secrets chiffrés). Le pipeline empêche qu'une régression arrive en production sans être vue.

Les risques qui restent concernent surtout ce qu'un labo local ne peut pas faire : un coffre de clés externe (KMS), un registre d'images privé et signé, et une journalisation centralisée. Sur Azure, ils se traitent avec Key Vault, Container Registry et Azure Monitor.
