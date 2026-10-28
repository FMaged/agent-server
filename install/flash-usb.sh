#!/usr/bin/env bash
# Writes build/agent-server.iso to the one USB stick plugged in, after asking.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
iso=$here/build/agent-server.iso
[ -f "$iso" ] || { echo "missing: $iso, run build-iso.sh first" >&2; exit 1; }

mapfile -t disks < <(lsblk -dnpo NAME,TRAN,TYPE | awk '$2 == "usb" && $3 == "disk" {print $1}')
case ${#disks[@]} in
    0) echo "no USB stick found" >&2; exit 1 ;;
    1) dev=${disks[0]} ;;
    *) echo "more than one USB disk, unplug all but the stick: ${disks[*]}" >&2; exit 1 ;;
esac

lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS "$dev"
read -rp "Erase everything on $dev and write the ISO? [yes/no] " answer
[ "$answer" = yes ] || { echo "aborted"; exit 1; }

for part in $(lsblk -lnpo NAME,MOUNTPOINTS "$dev" | awk 'NF > 1 {print $1}'); do
    sudo umount "$part"
done
sudo dd if="$iso" of="$dev" bs=4M conv=fsync status=progress
echo "done, $dev can be removed"
