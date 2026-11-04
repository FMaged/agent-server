# agent-server

A single Debian 13 machine that hosts coding agents, reachable over SSH and
rebuildable from bare metal without manual steps. Two stages: an unattended
install, then an Ansible run that configures the base system.

## What you need

- The Debian 13 amd64 netinst image and its `SHA256SUMS`, a USB stick, and a
  machine whose firmware boots it in UEFI mode
- `xorriso`, `cpio`, `gzip` and `openssl`, to build the ISO
- Ansible; `ansible-core` 2.18 or later (Debian 13 has Python 3.13)
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

`ansible` does not exist yet, so this run logs in as `devel` and creates it.
Every later run drops the flags and connects as `ansible` on the key:

```
ansible-playbook site.yml
```

A second run changes nothing.

## Model server

After `site.yml`, `llm.yml` builds llama.cpp at the tag in `llm_tag`, downloads
`llm_model` and any extras in `llm_download` (checked against their sha256) and
starts `llama-server` on `llm_bind:llm_port`, serving `llm_model`. All are set
in `group_vars/agent_servers.yml`.

To switch models, set `llm_model` to another key of `llm_models` and run
`llm.yml` again. It checks the new model fits on the disk, downloads it,
restarts the service, and waits until the model answers a chat request. Only
then does it delete every `.gguf` that is not `llm_model` or in `llm_download`.
If the download fails, the old model keeps serving. If the new model fails
after the restart, the API is down but the old file is still there: set
`llm_model` back and run again. Change `llm_tag` and `llm_model` in separate
runs. `REQUIREMENTS.md` lists every failure case.

```
ansible-playbook llm.yml
```

Requests need the API key, which the first run generates on the host. Read it
with `ssh -i ~/.ssh/agent-server ansible@192.168.150.221 sudo cat /etc/llama/api-key`,
then:

```
curl -H "Authorization: Bearer <key>" http://192.168.150.221:8080/v1/models
```

`bruno/` is a Bruno collection with the same calls: models, no key (expect
401), a chat completion and a tool call. Open it in Bruno, pick the `lan`
environment and paste the key into its `apiKey` secret.

The traffic is plain HTTP, so use it on the LAN only.

## Layout

- `REQUIREMENTS.md` — what the repo must do, stage by stage, and how to check it
- `install/` — the preseed, `build-iso.sh`, which builds it into the ISO, and
  `flash-usb.sh`, which writes the ISO to a stick
- `bruno/` — Bruno requests for the model server
- `ansible/` — `site.yml`, `llm.yml` and the `users`, `base`, `ssh` and `llm`
  roles; values live in `group_vars/agent_servers.yml`

The host comes up on `192.168.150.221` with one user, `devel`, in the `sudo`
group with the password typed at the ISO build, and root locked. The first
playbook run creates `ansible` with passwordless sudo and no password, gives
both users the key, and turns off password login. After that SSH is key-only,
so whoever holds the SSH key holds root; `devel`'s password works at the
keyboard and for its `sudo`.
