# agent-server

A single Debian 13 machine that hosts coding agents, reachable over SSH and
rebuildable from bare metal without manual steps. Two stages: an unattended
install, then an Ansible run that configures the base system.

## What you need

- The Debian 13 amd64 netinst image and its `SHA256SUMS`, a USB stick, and a
  machine whose firmware boots it in UEFI mode
- `xorriso`, `cpio`, `gzip` and `openssl`, to build the ISO
- Ansible; `ansible-core` 2.14 or later is enough
- `sshpass` on the controller, for the first run's `-k`
- The private key at `~/.ssh/agent-server`

## Install

Build an ISO with the preseed inside it, from the netinst and its `SHA256SUMS`.
It asks for `devel`'s password, which only the ISO carries, so keep the ISO private:

```
install/build-iso.sh ~/Downloads/debian-13.7.0-amd64-netinst.iso
```

Write it to the one USB stick plugged in, after typing `yes`:

```
install/flash-usb.sh
```

Boot the stick once, in UEFI mode, from the one-time boot menu. Nothing to
answer or type. Read `install/README.md` first: the target disk is set in the
preseed, and it is erased whole.

## Configure

Once the machine has rebooted, run it once as `devel`, with its password:

```
cd ansible
ansible-playbook site.yml -k -K -e ansible_user=devel
```

Later runs connect on the key and need no flags. A second run changes nothing.

## Layout

- `install/` — the preseed, `build-iso.sh`, which builds it into the ISO, and
  `flash-usb.sh`, which writes the ISO to a stick
- `ansible/` — `site.yml` and the `users`, `base` and `ssh` roles; values live
  in `group_vars/agent_servers.yml`

The host comes up on `192.168.150.221` with one user, `devel`, in the `sudo`
group with the password typed at the ISO build, and root locked. The first
playbook run creates `ansible` with passwordless sudo and no password, gives
both users the key, and turns off password login. After that SSH is key-only,
so whoever holds the SSH key holds root; `devel`'s password works at the
keyboard and for its `sudo`.
