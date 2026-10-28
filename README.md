# agent-server

A single Debian 13 machine that hosts coding agents, reachable over SSH and
rebuildable from bare metal without manual steps. Two stages: an unattended
install, then an Ansible run that configures the base system.

## What you need

- The Debian 13 amd64 netinst image and its `SHA256SUMS`, a USB stick, and a
  machine whose firmware boots it in UEFI mode
- `xorriso`, `cpio` and `gzip`, to build the ISO
- Ansible; `ansible-core` is enough
- `sshpass` on the controller, for the first run's `-k`
- The private key at `~/.ssh/agent-server`

## Install

Build an ISO with the preseed inside it, from the netinst and its `SHA256SUMS`:

```
install/build-iso.sh ~/Downloads/debian-13.7.0-amd64-netinst.iso
```

Write `install/build/agent-server.iso` to a USB stick and boot it once, in UEFI
mode, from the one-time boot menu. Nothing to answer or type. Read
`install/README.md` first: the bootstrap password and the target disk are both
set in the preseed, and the disk is erased whole.

## Configure

Once the machine has rebooted, run it once with the bootstrap password:

```
cd ansible
ansible-playbook site.yml -k -K
```

Later runs connect on the key and need no flags. A second run changes nothing.

## Layout

- `install/` — the preseed and the script that builds it into the ISO
- `ansible/` — `site.yml` and the `users`, `base` and `ssh` roles; values live
  in `group_vars/agent_servers.yml`

The host comes up on `192.168.150.221` as `ansible`, with a bootstrap password
and root locked. The first playbook run installs the key, removes the password
and turns off password login. After that SSH is key-only, so whoever holds the
SSH key holds root.
