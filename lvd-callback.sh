#!/bin/bash

LOGFILE="/var/log/hai-emergency.log"
echo "[$(date)] ⚡ COUPURE COURANT DÉTECTÉE (LVD). Arrêt d'urgence..." >> $LOGFILE

# -----------------------------------------------------------------------------
# ÉTAPE 1 : Sauvegarde CODESYS (Priorité Haute)
# -----------------------------------------------------------------------------
# Le runtime Codesys a besoin d'un signal d'arrêt pour écrire ses variables RETAIN.
if systemctl is-active --quiet codesyscontrol; then
    echo "Arrêt de CODESYS..." >> $LOGFILE
    systemctl stop codesyscontrol
fi

# -----------------------------------------------------------------------------
# ÉTAPE 2 : Arrêt de l'application HAI (DataPlug / MQTT)
# -----------------------------------------------------------------------------
# Ferme proprement la connexion SQLite (StoreAndForward) et le broker MQTT.
if systemctl is-active --quiet hai-pxxx-ai; then
    echo "Arrêt de HAI-OS..." >> $LOGFILE
    systemctl stop hai-pxxx-ai
fi

# -----------------------------------------------------------------------------
# ÉTAPE 3 : Arrêt des conteneurs critiques (PostgreSQL & Node-RED)
# -----------------------------------------------------------------------------
# Basé sur vos services définis dans main.py.
# On arrête d'abord Postgres pour qu'il ferme ses transactions proprement.
# L'option --no-block rend la commande asynchrone pour ne pas bloquer le script
# si le conteneur met trop de temps à s'arrêter (le 'sync' reste prioritaire).

echo "Signal d'arrêt envoyé aux conteneurs..." >> $LOGFILE

# 1. Base de données (Priorité absolue pour éviter la corruption)
if systemctl is-active --quiet container-postgres; then
    systemctl stop container-postgres --no-block
fi

# 2. Applications (Node-RED, Ignition, Grafana)
# On les arrête en groupe pour gagner du temps
for service in container-nodered container-ignition container-grafana; do
    if systemctl is-active --quiet $service; then
        systemctl stop $service --no-block
    fi
done

# On attend 2 secondes maximum pour laisser aux conteneurs le temps de finir
# Si le supercondensateur est petit, réduisez ce temps ou supprimez cette pause.
sleep 2

# -----------------------------------------------------------------------------
# ÉTAPE 4 : Synchronisation disque (OBLIGATOIRE)
# -----------------------------------------------------------------------------
# C'est ici que la "magie" opère. Cette commande force Linux à écrire
# tout ce qui est en RAM vers la carte SD/SSD.
echo "Synchronisation du système de fichiers..." >> $LOGFILE
sync
sync  # Une deuxième fois par sécurité (vieille habitude d'admin sys)

# -----------------------------------------------------------------------------
# ÉTAPE 5 : Extinction finale
# -----------------------------------------------------------------------------
echo "Arrêt du système." >> $LOGFILE
sleep 0.5
sudo poweroff