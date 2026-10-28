# agent-server

A single Debian 13 machine that hosts coding agents, reachable over SSH and
rebuildable from bare metal without manual steps. Two stages: an unattended
install, then an Ansible run that configures the base system.

## What you need

- A Debian 13 netinst image, and a machine whose firmware boots it in UEFI mode
- Ansible with the `community.general` collection — Debian's `ansible` package
  includes it, a bare `ansible-core` install does not
- `sshpass` on the controller, for the first run's `-k`
- The private key at `~/.ssh/agent-server`

## Install

Serve the preseed from this directory:

```
python3 -m http.server 8000 --directory install/
```

Boot the netinst in UEFI mode and add to its boot line:

```
auto=true priority=critical preseed/url=http://<workstation-ip>:8000/preseed.cfg
```

Nothing to answer. Read `install/README.md` first: the bootstrap password and
the target disk are both set in the preseed, and the disk is erased whole.

## Configure

Once the machine has rebooted, run it once with the bootstrap password:

```
cd ansible
ansible-playbook site.yml -k -K
```

Later runs connect on the key and need no flags. A second run changes nothing.

## Layout

- `install/` — the preseed and how to serve it
- `ansible/` — `site.yml` and the `users`, `base` and `ssh` roles; values live
  in `group_vars/agent_servers.yml`

The host comes up on `192.168.150.221` as `ansible`, with a bootstrap password
and root locked. The first playbook run installs the key, removes the password
and turns off password login. After that SSH is key-only, so whoever holds the
SSH key holds root.
