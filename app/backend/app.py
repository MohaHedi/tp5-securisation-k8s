"""Boutique Black Friday - API backend (application du TP 1, reprise au TP 5).

Le mot de passe de la base n'est JAMAIS écrit dans le code ni dans l'image :
il est lu dans un fichier monté depuis un Secret Kubernetes.
"""
import os

import pg8000.native
from flask import Flask, jsonify

app = Flask(__name__)


def lire_mot_de_passe():
    """Lit le mot de passe dans le fichier indiqué par DB_PASSWORD_FILE."""
    chemin = os.environ.get("DB_PASSWORD_FILE", "/var/run/secrets/db/password")
    with open(chemin, encoding="utf-8") as fichier:
        return fichier.read().strip()


def connexion():
    return pg8000.native.Connection(
        host=os.environ.get("DB_HOST", "database"),
        port=int(os.environ.get("DB_PORT", "5432")),
        database=os.environ.get("DB_NAME", "boutique"),
        user=os.environ.get("DB_USER", "boutique"),
        password=lire_mot_de_passe(),
        timeout=3,
    )


@app.get("/api/sante")
def sante():
    """Sonde de santé (liveness) : le processus répond."""
    return jsonify(statut="ok")


@app.get("/api/pret")
def pret():
    """Sonde de disponibilité (readiness) : la base est joignable."""
    try:
        conn = connexion()
        conn.run("SELECT 1")
        conn.close()
        return jsonify(statut="pret")
    except Exception as erreur:  # noqa: BLE001 - on renvoie l'état, pas la pile
        return jsonify(statut="indisponible", raison=type(erreur).__name__), 503


@app.get("/api/produits")
def produits():
    conn = connexion()
    lignes = conn.run("SELECT nom, prix FROM produits ORDER BY id")
    conn.close()
    return jsonify([{"nom": nom, "prix": float(prix)} for nom, prix in lignes])


@app.get("/api/info")
def info():
    """Montre sous quelle identité tourne le conteneur (utile pour le TP)."""
    return jsonify(uid=os.getuid(), gid=os.getgid(), hote=os.uname().nodename)
