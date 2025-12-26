#!/bin/bash
# À configurer :
rm dists/bookworm/main/binary-arm64/Packages
rm dists/bookworm/main/binary-arm64/Packages.gz
DIST="bookworm"
YOUR_GPG_KEY_ID="9D6564E7E5C6D079052DBEFF51376752E18F354A" # Ton ID de clé GPG
REPO_ROOT=$(pwd) # S'assure qu'on est à la racine du repo git (ex: /home/admin/test/hello)

echo "Updating repository for $DIST (arm64 only)..."
echo "Using GPG Key ID: $YOUR_GPG_KEY_ID"

# Vérifier qu'il y a des packages .deb dans pool/main/
if [ -z "$(find pool/main -name '*.deb' -print -quit)" ]; then # Chemin relatif ici aussi
    echo "Error: No .deb files found in pool/main/"
    exit 1
fi

# Créer la structure de répertoires nécessaire pour arm64
mkdir -p $REPO_ROOT/dists/$DIST/main/binary-arm64

# Générer le fichier Packages pour arm64
echo "Generating Packages file for arm64..."
# UTILISER L'OPTION -m ET UN CHEMIN RELATIF POUR 'binarypath'
# Ceci suppose que le script est exécuté depuis REPO_ROOT
dpkg-scanpackages -m pool/main /dev/null > $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages

# Compresser le fichier Packages pour arm64
echo "Compressing Packages file for arm64..."
gzip -k -f $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages

# Définir les chemins pour les fichiers Release
RELEASE_FILE=$REPO_ROOT/dists/$DIST/Release
INRELEASE_FILE=$REPO_ROOT/dists/$DIST/InRelease
RELEASE_GPG_FILE=$REPO_ROOT/dists/$DIST/Release.gpg

# Créer le contenu de base du fichier Release
echo "Creating Release file..."
cat > $RELEASE_FILE << EOF
Origin: Mon Depot APT Personnalise
Label: Mon Depot
Suite: $DIST
Codename: $DIST
Components: main
Architectures: arm64
Date: $(date -Ru)
EOF

# Calculer et ajouter les checksums au fichier Release
echo "Generating checksums for Release file..."
(
    cd $REPO_ROOT/dists/$DIST || exit 1 
    {
        echo "MD5Sum:"
        find main/binary-arm64 -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(md5sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done

        echo "SHA1:"
        find main/binary-arm64 -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(sha1sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done

        echo "SHA256:"
        find main/binary-arm64 -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(sha256sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done
    } >> $RELEASE_FILE 
)

# Signer le fichier Release
echo "Signing the Release file..."
if [ -z "$YOUR_GPG_KEY_ID" ]; then
    echo "Error: YOUR_GPG_KEY_ID is not set in the script. Cannot sign the repository."
    exit 1
fi

gpg --batch --yes --default-key "$YOUR_GPG_KEY_ID" --clearsign -o $INRELEASE_FILE $RELEASE_FILE
gpg --batch --yes --default-key "$YOUR_GPG_KEY_ID" -abs -o $RELEASE_GPG_FILE $RELEASE_FILE

# cd $REPO_ROOT # Normalement pas nécessaire si on n'a pas changé de répertoire globalement

echo "Repository updated and signed successfully for arm64!"
echo "Packages found and listed in dists/$DIST/main/binary-arm64/Packages:"
grep "^Package:" $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages || echo " (No packages found or Packages file empty)"
# Tu peux aussi faire un `cat $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages` ici pour vérifier tout le contenu

echo ""
echo "N'oubliez pas d'ajouter votre clé publique GPG 'votre-cle-publique.asc' au dépôt si ce n'est pas fait."
echo "Et de commiter & pusher les changements :"
echo "  git add ."
echo "  git commit -m \"Update APT repository for $DIST (arm64) - $(date)\""
echo "  git push"
