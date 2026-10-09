# Unattended install

`preseed.cfg` answers every question the Debian 13 (trixie) installer asks, so
the install runs start to finish without a prompt and reboots into a host that
accepts your SSH key.

## Before you start

`preseed.cfg` carries the public half of the `agent-server` keypair, and the
private half has to be on the machine you will run Ansible from. To use a
different key, replace the one on the `authorized_keys` line. It is the only
credential the host will have: no password is set and root is locked.

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

`sudo` works without a password, which is the only route to root, and root
itself is locked. The account has the console password set in `preseed.cfg` —
usable at the keyboard only, since sshd refuses passwords. Running the playbook
in `ansible/` removes that password and takes ownership of the sudo drop-in, so
log in at the console *before* the first playbook run if you need to.

A reinstall gives the host a new SSH host key, which SSH refuses as a mismatch.
Drop the stale entry with `ssh-keygen -R 192.168.1.50`.
