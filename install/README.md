# Unattended install

`preseed.cfg` answers every question the Debian 13 (trixie) installer asks, so
the install runs start to finish without a prompt and reboots into a plain
Debian with SSH, `sudo` and Python. It configures nothing else: keys, sshd and
sudo are set by the playbook in `ansible/`.

## Before you start

The only login is `ansible` with the password hash in `preseed.cfg`. Root is
locked. Replace the hash if you do not know its password.

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

The host comes up on `192.168.150.221` as `ansible`. Run the playbook once with
the bootstrap password; it installs your key, closes password login and
removes the password:

```
cd ansible && ansible-playbook site.yml -k -K
```

A reinstall gives the host a new SSH host key, which SSH refuses as a mismatch.
Drop the stale entry with `ssh-keygen -R 192.168.150.221`.
