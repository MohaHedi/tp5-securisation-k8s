# Frontend durci : nginx sans privilèges (utilisateur 101, port 8080)
# Variante "slim" (moins de paquets installés = moins de failles), branche principale 1.31
FROM nginxinc/nginx-unprivileged:1.31-alpine-slim
USER root
RUN apk upgrade --no-cache
USER 101
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
