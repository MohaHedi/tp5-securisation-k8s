# Rapports de scan : avant / après correction

| Outil | Cible | Avant | Après |
|---|---|---|---|
| **Trivy** | Image backend | 15 134 failles (CRITICAL 236, HIGH 2 651, MEDIUM 8 205, LOW 3 431, UNKNOWN 611) | 12 failles (MEDIUM 7, LOW 5), **0 HIGH, 0 CRITICAL** |
| **Trivy** | Image frontend | non mesuré (image de départ identique à l'image de base) | 14 failles (HIGH 3, MEDIUM 7, LOW 4), 0 CRITICAL, voir la note ci-dessous |
| **Checkov** | Terraform (TP 2) | 9 réussis, **11 échecs** | 18 réussis, **0 échec**, 2 exceptions justifiées |
| **Checkov** | Manifestes Kubernetes | 69 réussis, **21 échecs** (+ 1 secret base64) | 280 réussis, **0 échec**, 6 exceptions justifiées |
| **Checkov** | Dockerfile backend | 45 réussis, **2 échecs** | 43 réussis, **0 échec** |
| **Gitleaks** | Code source | **4 secrets** détectés | **0 secret** dans l'historique Git |

## Les alertes corrigées (exemples)

| Alerte | Problème | Correction |
|---|---|---|
| `CKV_AZURE_10` | SSH ouvert à tout Internet (`source_address_prefix = "*"`) | SSH limité à l'IP de l'administrateur (`var.ip_admin_autorisee`, avec une règle de validation) |
| `CKV_AZURE_149` / `CKV_AZURE_178` / `CKV_AZURE_1` / `CKV_AZURE_49` | Connexion aux VM par mot de passe | Clé SSH uniquement, `disable_password_authentication = true` |
| `CKV_AZURE_97` / `CKV_AZURE_151` | Disques non chiffrés sur l'hôte | `encryption_at_host_enabled = true` |
| `CKV_AZURE_50` | Extensions de VM autorisées | `allow_extension_operations = false` |
| `CKV_K8S_16` / `CKV_K8S_23` / `CKV_K8S_20` | Conteneur privilégié, root, élévation de privilèges | `securityContext` durci (non-root, `allowPrivilegeEscalation: false`, `capabilities: drop ALL`) |
| `CKV_K8S_14` | Image en `latest` | Version figée `1.0.0` |
| `CKV_K8S_10` à `CKV_K8S_13` | Pas de limites CPU et mémoire | `requests` et `limits` sur tous les conteneurs |
| `CKV_K8S_8` / `CKV_K8S_9` | Pas de sondes de santé | `livenessProbe` et `readinessProbe` |
| `CKV_K8S_22` | Système de fichiers modifiable | `readOnlyRootFilesystem: true` |
| `CKV_K8S_38` | Jeton de l'API monté dans chaque Pod | `automountServiceAccountToken: false` |
| `CKV_K8S_40` | UID bas (risque de collision avec l'hôte) | UID 10001, 10070, 10101 |
| `CKV_DOCKER_3` | Pas d'utilisateur dédié dans l'image | `USER 10001:10001` |
| `CKV_SECRET_6` + Gitleaks | Mot de passe dans le Dockerfile et dans un Secret YAML | Secret généré au hasard et créé directement dans le cluster |

## Note sur l'environnement du labo

Le labo a été monté dans un environnement Linux dans le cloud, dont le proxy bloque les miroirs de paquets Alpine et Debian. Conséquences :

- `apk upgrade` n'a pas pu s'exécuter pendant la construction : les 3 failles HAUTES du frontend (musl, zlib) seraient corrigées sur une machine normale ou dans le pipeline GitHub ;
- dans l'image « avant », la ligne `apt-get install curl vim netcat` n'a pas pu s'exécuter : ses failles viennent donc toutes de l'image de base `python:3.9`.

Les Dockerfiles livrés sont les versions normales, sans adaptation au proxy.
