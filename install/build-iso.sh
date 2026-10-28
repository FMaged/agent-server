#!/usr/bin/env bash
# Builds build/agent-server.iso: the Debian netinst with preseed.cfg in its initrd.
set -euo pipefail

iso=${1:?usage: build-iso.sh <debian-13-amd64-netinst.iso>}
here=$(cd "$(dirname "$0")" && pwd)
out=$here/build/agent-server.iso

for tool in xorriso cpio gzip openssl; do
    command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done

# Debian's SHA256SUMS must sit next to the ISO.
(cd "$(dirname "$iso")" && grep " $(basename "$iso")\$" SHA256SUMS | sha256sum -c --quiet)

# Prompts twice; the hash goes only into the ISO.
hash=$(openssl passwd -6)

work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT

xorriso -osirrox on -indev "$iso" -report_about FAILURE \
    -extract /install.amd/initrd.gz "$work/initrd.gz" \
    -extract /boot/grub/grub.cfg "$work/grub.cfg" \
    -extract /md5sum.txt "$work/md5sum.txt"
chmod u+w "$work"/*

gunzip "$work/initrd.gz"
sed "s|@PASSWORD_HASH@|$hash|" "$here/preseed.cfg" > "$work/preseed.cfg"
(cd "$work" && echo preseed.cfg | cpio -o -A -H newc -R 0:0 --quiet -F "$work/initrd")
gzip -9 "$work/initrd"

# Appended last so nothing earlier in the file overrides the default.
cat >> "$work/grub.cfg" <<'EOF'
menuentry --id agent-server 'Install agent-server (erases the disk)' {
    linux    /install.amd/vmlinuz priority=critical --- quiet
    initrd   /install.amd/initrd.gz
}
set default=agent-server
set timeout=5
EOF

for f in install.amd/initrd.gz boot/grub/grub.cfg; do
    sum=$(md5sum < "$work/$(basename "$f")" | cut -d' ' -f1)
    sed -i "s|^[0-9a-f]\{32\}  \./$f\$|$sum  ./$f|" "$work/md5sum.txt"
done

mkdir -p "$here/build"
rm -f "$out"
xorriso -indev "$iso" -outdev "$out" -report_about FAILURE \
    -map "$work/initrd.gz" /install.amd/initrd.gz \
    -map "$work/grub.cfg" /boot/grub/grub.cfg \
    -map "$work/md5sum.txt" /md5sum.txt \
    -boot_image any replay
echo "$out"
