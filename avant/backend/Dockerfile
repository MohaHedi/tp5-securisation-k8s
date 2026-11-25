# ⚠ VERSION AVANT CORRECTION - VOLONTAIREMENT NON SÉCURISÉE (dossier pédagogique)
# Problèmes : image ancienne et lourde, tag flottant, utilisateur root,
# mot de passe écrit en dur dans l'image, outils inutiles en production.
FROM python:3.9
RUN apt-get update && apt-get install -y curl vim netcat-openbsd
WORKDIR /app
COPY app/backend/requirements.txt .
RUN pip install -r requirements.txt
COPY app/backend/app.py .
ENV DB_PASSWORD="Bf2026_xK9mQ7vLt3Rz8WpN4cJ"
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
