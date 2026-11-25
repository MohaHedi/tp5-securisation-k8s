# Frontend durci : nginx sans privilèges (utilisateur 101, port 8080)
# Variante "slim" (moins de paquets installés = moins de failles), branche principale 1.31
FROM nginxinc/nginx-unprivileged:1.31-alpine-slim
USER root
RUN apk upgrade --no-cache
USER 101
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
# Contrôle de santé pour Docker (Checkov CKV_DOCKER_2) ; dans Kubernetes, ce sont les sondes du Deployment qui servent
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
