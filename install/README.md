# Unattended install

`preseed.cfg` answers every question the Debian 13 (trixie) installer asks, so
the install runs start to finish without a prompt and reboots into a host that
accepts your SSH key.

## Before you start

Replace `PASTE_YOUR_SSH_PUBLIC_KEY_HERE` in `preseed.cfg` with your SSH public
key. It is the only credential the host will have: no password is set and root
is locked.

Check that `partman-auto/disk` names the target machine's disk. It is set to
`/dev/sda`; an NVMe SSD is usually `/dev/nvme0n1`. That disk is erased whole.

## Serve it

From the repository root:

```
python3 -m http.server 8000 --directory install/
```

## Boot the installer

Boot the Debian 13 netinst image **in UEFI mode**, with CSM off, and add to the
installer's boot line:

```
auto=true priority=critical preseed/url=http://<workstation-ip>:8000/preseed.cfg
```

Use the workstation's LAN address — the installer fetches the file over the
network, so `localhost` is its own loopback. UEFI is not optional: the
partition recipe is chosen from the firmware mode the installer booted in, and
a BIOS/CSM install lays out a disk that UEFI firmware then refuses to boot.

## After it reboots

The host comes up on `192.168.1.50` as `agent`:

```
ssh agent@192.168.1.50
```

`sudo` does not work yet. No password exists, and the sudoers drop-in comes
from the playbook in `ansible/`.

A reinstall gives the host a new SSH host key, which SSH refuses as a mismatch.
Drop the stale entry with `ssh-keygen -R 192.168.1.50`.
