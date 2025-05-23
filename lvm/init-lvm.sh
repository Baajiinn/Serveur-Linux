#!/bin/bash
set -euxo pipefail

LOGFILE="/var/log/init_lvm.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo -e "\n=== Initialisation des volumes LVM + quotas XFS (sécurisé) ===\n"

# 0) Variables disques — ne jamais inclure /dev/xvda ou nvme0n1 !
DISK1="/dev/nvme1n1"
DISK2="/dev/nvme2n1"

# 1) Validation des disques
for d in "$DISK1" "$DISK2"; do
    # existe et est bloc
    if [ ! -b "$d" ]; then
        echo "[ERROR] Le disque $d n'existe pas ! Annulation." && exit 1
    fi
    # ne pas être monté
    if mount | grep -qE "^$d"; then
        echo "[ERROR] $d est déjà monté ! Annulation." && exit 1
    fi
    # vérifier qu'il ne contient pas la racine
    ROOT_DEV=$(findmnt -n -o SOURCE /)
    if [ "$d" = "$ROOT_DEV" ]; then
        echo "[ERROR] $d est le volume racine ! Annulation." && exit 1
    fi
done

# 2) Confirmation manuelle
read -p "⚠️  Toutes les données de $DISK1 et $DISK2 seront perdues. Continuer ? [yes/NO] " CONF
if [ "$CONF" != "yes" ]; then
    echo "Annulation par l'utilisateur." && exit 0
fi

# 3) Installation outils
echo "[STEP] Installation des paquets"
sudo dnf install -y lvm2 xfsprogs quota

# 4) Table de partition et PV
for DISK in "$DISK1" "$DISK2"; do
    echo "[INFO] Partitionnement de $DISK"
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary 0% 100%
    sleep 1
    PART="${DISK}p1"   # NOTE : p1 pour NVMe
    if [ -b "$PART" ]; then
        echo "[INFO] Création du PV sur $PART"
        pvcreate "$PART"
    else
        echo "[ERROR] La partition $PART n'existe pas !" >&2
        exit 1
    fi
done

# 5) VG creation
VG="vg_data"
if ! vgs --noheadings -o vg_name | grep -qw "$VG"; then
    vgcreate "$VG" "${DISK1}1" "${DISK2}1"
fi

# 6) LVs fixes + lv_home
declare -A LVS=( [lv_tmp]=400M [lv_var]=400M [lv_srv]=400M [lv_swap]=448M [lv_backup]=2G )
for name in "${!LVS[@]}"; do
    if ! lvs --noheadings -o lv_name "$VG" | grep -qw "$name"; then
        lvcreate -L "${LVS[$name]}" -n "$name" "$VG"
    fi
done
if ! lvs --noheadings -o lv_name "$VG" | grep -qw lv_home; then
    lvcreate -l 100%FREE -n lv_home "$VG"
fi

# 7) Montage + fstab
declare -A MPTS=( [lv_home]="/home" [lv_srv]="/srv" [lv_var]="/var" [lv_tmp]="/tmp" [lv_backup]="/backup" )
for lv in "${!MPTS[@]}"; do
    dev="/dev/$VG/$lv"
    mp="${MPTS[$lv]}"
    # format si besoin
    blkid "$dev" || mkfs.xfs -f "$dev"
    mkdir -p "$mp"
    # fstab entry
    grep -q "^$dev" /etc/fstab || {
        opts="defaults"
        [[ "$mp" == "/home" ]] && opts="$opts,usrquota"
        echo "$dev $mp xfs $opts 0 2" >> /etc/fstab
    }
    # monter
    mountpoint -q "$mp" || mount "$mp"
done

# 8) Swap
swapdev="/dev/$VG/lv_swap"
blkid "$swapdev" | grep -q swap || mkswap "$swapdev"
swapon "$swapdev"
grep -q "^$swapdev" /etc/fstab || echo "$swapdev none swap sw 0 0" >> /etc/fstab

# 9) Quotas
echo "[STEP] Activation des quotas sur /home"
quotaon /home

echo -e "\n✅ Terminé sans toucher au root. Voir $LOGFILE\n"