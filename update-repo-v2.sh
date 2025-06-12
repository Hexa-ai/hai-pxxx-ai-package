#!/bin/bash

#-------------------------------------------------------------------------------
# update-repo.sh - Met à jour, signe et publie un dépôt APT simple.
#
# Usage: ./update-repo.sh <distribution> <architecture>
# Exemple: ./update-repo.sh bookworm arm64
#-------------------------------------------------------------------------------

# Arrête le script immédiatement si une commande échoue, si une variable non
# définie est utilisée, ou si une commande dans un pipe échoue.
set -euo pipefail

# --- Configuration ---
# Votre ID de clé GPG pour la signature du dépôt.
# Pour le trouver : gpg --list-secret-keys --keyid-format LONG
YOUR_GPG_KEY_ID="9D6564E7E5C6D079052DBEFF51376752E18F354A"

# --- Validation des arguments ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <distribution> <architecture>"
    echo "Exemple: $0 bookworm arm64"
    exit 1
fi

DIST="$1"
ARCH="$2"
REPO_ROOT=$(pwd)
POOL_DIR="pool/main"
DIST_DIR="$REPO_ROOT/dists/$DIST"
COMP_DIR="main/binary-$ARCH"

echo "### Démarrage de la mise à jour du dépôt pour '$DIST/$ARCH' ###"

# --- Vérifications préalables ---
if ! command -v dpkg-scanpackages &> /dev/null || ! command -v gpg &> /dev/null; then
    echo "Erreur : 'dpkg-dev' et 'gpg' doivent être installés." >&2
    exit 1
fi

if [ -z "$(find "$POOL_DIR" -name '*.deb' -print -quit)" ]; then
    echo "Erreur : Aucun fichier .deb trouvé dans le dossier '$POOL_DIR'." >&2
    exit 1
fi

if [ -z "$YOUR_GPG_KEY_ID" ]; then
    echo "Erreur : La variable YOUR_GPG_KEY_ID n'est pas configurée dans le script." >&2
    exit 1
fi

# --- Processus de mise à jour ---
echo "1. Création de la structure de répertoires..."
mkdir -p "$DIST_DIR/$COMP_DIR"

echo "2. Génération du fichier 'Packages'..."
dpkg-scanpackages --multiversion "$POOL_DIR" /dev/null > "$DIST_DIR/$COMP_DIR/Packages"

echo "3. Compression du fichier 'Packages'..."
gzip -k -f "$DIST_DIR/$COMP_DIR/Packages"

echo "4. Création du fichier 'Release'..."
# Le fichier Release est créé à chaque fois pour avoir la date à jour.
cat > "$DIST_DIR/Release" << EOF
Origin: Mon Depot APT Personnalise
Label: Mon Depot
Suite: $DIST
Codename: $DIST
Components: main
Architectures: $ARCH
Date: $(date -Ru)
EOF

echo "5. Calcul des sommes de contrôle pour le fichier 'Release'..."
# On se place dans le répertoire de la distribution pour avoir des chemins relatifs propres.
(
    cd "$DIST_DIR" || exit 1
    # Ajoute les en-têtes de section pour les checksums
    echo "MD5Sum:" >> Release
    echo "SHA1:" >> Release
    echo "SHA256:" >> Release

    # Calcule les hashes pour tous les fichiers d'index (Packages, Packages.gz, etc.)
    # et les ajoute sous la bonne section dans le fichier Release.
    for f in $(find "$COMP_DIR" -type f); do
        sed -i "/^MD5Sum:/a\ $(md5sum "$f" | cut --delimiter=' ' --fields=1) $(stat --format=%s "$f") $f" Release
        sed -i "/^SHA1:/a\ $(sha1sum "$f" | cut --delimiter=' ' --fields=1) $(stat --format=%s "$f") $f" Release
        sed -i "/^SHA256:/a\ $(sha256sum "$f" | cut --delimiter=' ' --fields=1) $(stat --format=%s "$f") $f" Release
    done
)

echo "6. Signature du fichier 'Release' avec la clé GPG $YOUR_GPG_KEY_ID..."
# Crée la signature "inline" (InRelease) et la signature détachée (Release.gpg)
gpg --batch --yes --default-key "$YOUR_GPG_KEY_ID" --clearsign -o "$DIST_DIR/InRelease" "$DIST_DIR/Release"
gpg --batch --yes --default-key "$YOUR_GPG_KEY_ID" -abs -o "$DIST_DIR/Release.gpg" "$DIST_DIR/Release"

echo ""
echo "### ✅ Dépôt mis à jour avec succès pour '$DIST/$ARCH' ! ###"
echo ""
echo "Paquets trouvés et listés dans '$DIST_DIR/$COMP_DIR/Packages':"
grep "^Package:" "$DIST_DIR/$COMP_DIR/Packages" | sed 's/^Package: / - /'

echo ""
echo "N'oubliez pas de commiter et pusher les changements :"
echo "  git add ."
echo "  git commit -m \"Repo: Mise à jour pour $DIST/$ARCH - $(date -I)\""
echo "  git push"
