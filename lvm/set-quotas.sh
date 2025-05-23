#!/bin/bash
set -euxo pipefail

# Journalisation
LOG="/var/log/set_quotas.log"
exec > >(tee -a "$LOG") 2>&1

echo -e "\n[INFO] Lancement du script set-quotas.sh\n"

# 1) Remonter /home avec usrquota si besoin
if ! mount | grep '/home' | grep -q usrquota; then
    echo "[INFO] Remontage de /home avec usrquota..."
    mount -o remount,usrquota /home || {
        echo "[ERREUR] Impossible de remonter /home avec usrquota." >&2
        exit 1
    }
fi

# 2) Vérifier à nouveau que /home est monté avec usrquota
if ! mount | grep '/home' | grep -q usrquota; then
    echo "[ERREUR] Le système de fichiers /home n'est toujours pas monté avec usrquota."
    echo "→ Vérifiez /etc/fstab et relancez ce script."
    exit 1
fi

echo "[INFO] /home est monté avec usrquota, on peut appliquer les quotas."

# 3) Activer les quotas (si pas déjà fait)
quotaon /home || true

# 4) Paramètres de quota (ajustez selon vos besoins)
SOFT_BLOCKS=500000   # 500 Mo
HARD_BLOCKS=600000   # 600 Mo
SOFT_INODES=1000
HARD_INODES=1500

echo "[INFO] Application des quotas :"
echo "       Soft blocks = $SOFT_BLOCKS"
echo "       Hard blocks = $HARD_BLOCKS"
echo "       Soft inodes = $SOFT_INODES"
echo "       Hard inodes = $HARD_INODES"

# 5) Parcours des répertoires utilisateurs dans /home
for USER in /home/*; do
    # Ne conserver que le nom, pas le chemin complet
    USERNAME=$(basename "$USER")

    # Ne traiter que si l'utilisateur existe
    if id "$USERNAME" &>/dev/null; then
        echo "[INFO] Définition du quota pour $USERNAME..."
        setquota -u "$USERNAME" \
            "$SOFT_BLOCKS" "$HARD_BLOCKS" \
            "$SOFT_INODES" "$HARD_INODES" /home
    else
        echo "[WARN] L'utilisateur $USERNAME n'existe pas, ignoré."
    fi
done

echo -e "\n[INFO] Quotas définis avec succès pour tous les utilisateurs de /home."