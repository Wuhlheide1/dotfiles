#!/usr/bin/env bash
# One-off: move Ollama's model store (/var/lib/ollama) from the SATA SSD onto
# the Linux half of the Samsung 990 PRO (nvme0n1p4, btrfs). Run with sudo.
# Non-destructive: only creates a new @ollama subvolume and copies into it;
# nothing on either disk is deleted. The old copy stays at
# /var/lib/ollama.sata-bak until you remove it yourself.
set -euo pipefail

UUID=9c19893c-7aa6-4e56-aaed-59597f6f716e
OPTS=rw,noatime,ssd,discard=async,space_cache=v2

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
[[ -b /dev/disk/by-uuid/$UUID ]] || { echo "NVMe partition $UUID not found"; exit 1; }
[[ -e /var/lib/ollama.sata-bak ]] && { echo "/var/lib/ollama.sata-bak exists — already moved?"; exit 1; }

echo "==> Mounting the NVMe partition at /mnt/nvme"
mkdir -p /mnt/nvme
mountpoint -q /mnt/nvme || mount -o "$OPTS,subvolid=5" UUID=$UUID /mnt/nvme
echo "    already on it:"; ls -A /mnt/nvme | sed 's/^/      /'

echo "==> Creating the @ollama subvolume"
[[ -d /mnt/nvme/@ollama ]] || btrfs subvolume create /mnt/nvme/@ollama

echo "==> Copying models (~8 GB)"
systemctl stop ollama
cp -a /var/lib/ollama/. /mnt/nvme/@ollama/
chown ollama:ollama /mnt/nvme/@ollama
chmod 755 /mnt/nvme/@ollama

echo "==> Adding fstab entries (backup: /etc/fstab.pre-nvme-bak)"
cp /etc/fstab /etc/fstab.pre-nvme-bak
grep -q "$UUID" /etc/fstab || cat >>/etc/fstab <<EOF

# Samsung 990 PRO, Linux half (nvme0n1p4): whole volume + Ollama's models
UUID=$UUID  /mnt/nvme        btrfs  $OPTS,subvolid=5,nofail        0 0
UUID=$UUID  /var/lib/ollama  btrfs  $OPTS,subvol=/@ollama,nofail   0 0
EOF
systemctl daemon-reload

echo "==> Switching /var/lib/ollama over (old copy -> /var/lib/ollama.sata-bak)"
mv /var/lib/ollama /var/lib/ollama.sata-bak
mkdir /var/lib/ollama
mount /var/lib/ollama
findmnt /var/lib/ollama

systemctl start ollama
for _ in $(seq 20); do curl -s localhost:11434/api/tags >/dev/null && break; sleep 0.5; done
if curl -s localhost:11434/api/tags | grep -q gemma4; then
    echo "==> Done: Ollama is serving its models from the NVMe."
    echo "    Once you're happy, free the 8 GB on the SATA SSD with:"
    echo "      sudo rm -r /var/lib/ollama.sata-bak"
else
    echo "!! Ollama doesn't list gemma4 from the new location."
    echo "   Old copy untouched at /var/lib/ollama.sata-bak; fstab backup at /etc/fstab.pre-nvme-bak."
    exit 1
fi
