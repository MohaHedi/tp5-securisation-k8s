#!/usr/bin/env bash
# Démarre le cluster minikube du TP 5 :
#   - plugin réseau Calico (indispensable : il applique les Network Policies)
#   - journaux d'audit de l'API Server activés
set -euo pipefail
cd "$(dirname "$0")/.."

# minikube copie automatiquement ~/.minikube/files/* dans le nœud au démarrage
mkdir -p ~/.minikube/files/etc/ssl/certs
cp cluster/audit-policy.yaml ~/.minikube/files/etc/ssl/certs/audit-policy.yaml

minikube start \
  --driver=docker \
  --kubernetes-version=v1.34.0 \
  --cni=calico \
  --cpus=4 --memory=8g \
  --extra-config=apiserver.audit-policy-file=/etc/ssl/certs/audit-policy.yaml \
  --extra-config=apiserver.audit-log-path=-

kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
kubectl get nodes
