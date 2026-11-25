# Image durcie du backend (version APRÈS correction)
# - image de base minimale (alpine) et version figée
# - construction en deux étapes : les outils de build ne partent pas en production
# - utilisateur non-root, aucun secret dans l'image

# Étape 1 : installation des dépendances
FROM python:3.13-alpine AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Étape 2 : image finale, minimale
FROM python:3.13-alpine
# pip n'est plus utile une fois les dépendances copiées : on le retire (moins de code = moins de failles)
RUN apk upgrade --no-cache \
 && addgroup -g 10001 -S boutique \
 && adduser -u 10001 -S -G boutique -H -s /sbin/nologin boutique \
 && python -m pip uninstall -y --root-user-action=ignore pip \
 && rm -rf /usr/local/lib/python3.13/ensurepip
COPY --from=build /install /usr/local
WORKDIR /app
COPY --chown=10001:10001 app.py .
USER 10001:10001
EXPOSE 8080
HEALTHCHECK NONE
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--worker-tmp-dir", "/tmp", "--access-logfile", "-", "app:app"]
