# Requirements: agent-server

This repo turns one bare-metal machine into `agent-server`: a Debian 13 host
for coding agents that serves a local model over HTTP on the LAN. It does this
in three stages, each owned by one part of the repo:

1. **Install** (`install/`): an unattended Debian install from a USB stick.
2. **Configure** (`ansible/site.yml`): users, SSH, packages, updates and
   Docker.
3. **Model server** (`ansible/llm.yml`): llama.cpp in a Docker container,
   serving one model behind an API key.

After the install, nobody logs in to change the server. Every change is made
in this repo and applied with a playbook run.

## Target

| Item | Value |
|------|-------|
| Hardware | 128 GB SATA SSD (LITEON CV8-8E128-11), 64 GB RAM, one wired interface, no dedicated GPU |
| Firmware | UEFI. BIOS/CSM boot is not supported. |
| Address | Static `192.168.150.221/24`, gateway and DNS `192.168.150.1` |
| Hostname | `agent-server`, no domain |

## Rules for the whole repo

| ID | Requirement |
|----|-------------|
| GR-01 | The machine can be rebuilt from bare metal with no manual steps beyond building the ISO, writing the stick, booting it and running the playbooks. |
| GR-02 | After the install, the server is changed only through Ansible. No step needs someone to log in and change the host. A read-only login, for example to read the API key, is allowed. |
| GR-03 | No secret is committed: not `devel`'s password or its hash, not the SSH private key, not the API key. Model weights are not committed either. |
| GR-04 | Every playbook is idempotent: a second run with the same values reports 0 changed and restarts nothing. |
| GR-05 | Every download is pinned: the Debian ISO by Debian's `SHA256SUMS`, the llama.cpp image by its digest, each model by its sha256. |
| GR-06 | Ansible values live in `ansible/group_vars/agent_servers.yml`. |

## 1. Install (preseed)

The install only puts Debian on the disk and leaves a host Ansible can reach.
It does not place SSH keys, write sshd or sudoers files, add users beyond
`devel`, run a `late_command`, or install anything beyond the packages below.

| ID | Requirement |
|----|-------------|
| IR-01 | Fully unattended; no prompts. Boot in UEFI mode. |
| IR-02 | Debian 13 `trixie` from `deb.debian.org`, with `main` and `non-free-firmware`, plus `trixie-updates` and `trixie-security`. |
| IR-03 | `en_US.UTF-8`, German (`de`) keyboard, `Europe/Berlin`, hardware clock in UTC, NTP. |
| IR-04 | Static IPv4 `192.168.150.221/24`, gateway and DNS `192.168.150.1`, hostname `agent-server`, no domain. No DHCP. |
| IR-05 | Install to one explicit disk (`partman-auto/disk`). Existing LVM/RAID on it is discarded. |
| IR-06 | Layout: EFI 1 GB (FAT32), swap 8 GB, ext4 `/` on the rest. |
| IR-07 | GRUB for UEFI, also to the removable path. |
| IR-08 | Tasks `standard` and `ssh-server`, plus `sudo` and `python3`. No desktop. |
| IR-09 | Updates applied during install (`safe-upgrade`). No update policy set. |
| IR-10 | Root login disabled. One user, `devel`, in group `sudo`, with its password. |
| IR-11 | The installer reboots by itself when done. |
| IR-12 | The preseed reaches the installer inside the ISO (BR-04), not over the network. |

## 2. ISO build

| ID | Requirement |
|----|-------------|
| BR-01 | `install/build-iso.sh`, bash. Runs as a normal user: no root, no loop mounts. Needs `xorriso`, `cpio`, `gzip` and `openssl`, and stops naming any that is missing. |
| BR-02 | Input: the official Debian 13 amd64 netinst ISO, given as an argument. Checked against Debian's `SHA256SUMS` before it is modified. |
| BR-03 | Asks for `devel`'s password twice and hashes it with `openssl passwd -6`. The hash replaces `@PASSWORD_HASH@` in the ISO's copy of `preseed.cfg` only; the committed file keeps the placeholder. |
| BR-04 | `preseed.cfg` is added to `install.amd/initrd.gz` as `/preseed.cfg`, so it is read before the first question, network included. |
| BR-05 | The UEFI GRUB menu gets a default entry that starts the install after a 5 s timeout. Nothing is typed at the boot line. |
| BR-06 | `md5sum.txt` is regenerated, and the original boot records are kept, so the image boots from a USB stick written with `dd`. |
| BR-07 | Output: `install/build/agent-server.iso`. It is built to a temporary file and then moved into place, so a failed build keeps the previous ISO and leaves no partial file. `install/build/` is in `.gitignore`. Nothing else is left behind. |
| BR-08 | The ISO carries `devel`'s hash, so it is private: the script runs with `umask 077`, `install/build/` is `0700` and the ISO is `0600`, even if the directory already existed with looser rights. |
| BR-09 | Every change to `preseed.cfg` or to the password needs a rebuild. |
| BR-10 | The ISO erases the disk without asking. Boot it once, from the firmware's one-time boot menu, so that after IR-11 the installed system boots, not the ISO again. |
| BR-11 | `install/flash-usb.sh`, bash. Writes the ISO with `dd` to the one USB disk found, after a typed `yes`. Stops with none or several. |

### Handoff to Ansible

| Item | Value |
|------|-------|
| Address | `192.168.150.221` |
| SSH user | `devel`, its password (typed at `build-iso.sh`) |
| Privilege | `sudo` with that password |
| Python | `/usr/bin/python3` (3.13 on Debian 13) |
| Not present | SSH key, sshd drop-ins, sudoers drop-ins |

Changing any of this is a requirements change on both sides.

## 3. Configure (`site.yml`)

| ID | Requirement |
|----|-------------|
| AR-01 | First run connects as `devel` with its password: `ansible-playbook site.yml -k -K -e ansible_user=devel`. Later runs connect as `ansible` with the key at `~/.ssh/agent-server`. The controller needs `sshpass` for the first run. |
| AR-02 | The controller needs `ansible-core` 2.18 or later, the first release that supports Python 3.13 on the target, and the `community.docker` collection 4.0 or later, from `ansible/requirements.yml` (`ansible-galaxy collection install -r requirements.yml`). `site.yml` and `llm.yml` both start with `check-controller.yml`, which checks both on the controller and stops before any host is touched. |
| AR-03 | `users` role: fails first, changing nothing, if the public half of `ansible_ssh_private_key_file` is not in `agent_ssh_public_keys`. |
| AR-04 | `users` role: creates `ansible` with no password, and writes the `authorized_keys` of `ansible` and `devel` from `agent_ssh_public_keys`, whole, so a dropped key is removed. |
| AR-05 | `users` role: passwordless sudo in `/etc/sudoers.d/ansible`, validated with `visudo -cf`. `devel` keeps Debian's `%sudo` rule, which asks for its password. |
| AR-06 | `users` role: never sets or changes a password. `devel`'s comes from the install. |
| AR-07 | `ssh` role: drop-in with `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, validated with `sshd -t -f`, then reload `ssh`. |
| AR-08 | `base` role: the packages in `base_packages`, `unattended-upgrades` and its periodic config in `/etc/apt/apt.conf.d/20auto-upgrades`. No automatic reboot: reboot by hand when `/var/run/reboot-required` exists. |
| AR-09 | Roles run in the order `users`, `base`, `ssh`, `docker`, so `ansible` has its key and sudo before password login is turned off. |
| AR-10 | `docker` role: installs Debian's `docker.io`, `docker-cli` and `docker-compose` (the `docker compose` plugin), not Docker's own apt repository, so `unattended-upgrades` (AR-08) updates them like every other package. Docker is enabled at boot. |
| AR-11 | `docker` role: `/etc/docker/daemon.json` sets the `journald` log driver, so container logs rotate with the journal instead of growing under `/var/lib/docker`, and `live-restore`, so an upgrade of Docker does not stop the running containers. A change to the file restarts Docker. |
| AR-12 | `docker` role: nobody is added to the `docker` group, because it is equal to root. Docker is used through `sudo`. |

Hostname, timezone and NTP are set by the install alone (IR-03, IR-04).
Ansible does not manage them; if they drift, reinstall.

## 4. Model server (`llm.yml`)

`llm.yml` runs the `llm` role, after `site.yml`, as `ansible`. Its steps run
in this order: settings check, models, image, container, checks, cleanup.
Every step that can fail without touching the service comes before the
container is recreated.

### Settings check

| ID | Requirement |
|----|-------------|
| LR-01 | Before it changes anything, the role checks that `llm_model` and every entry in `llm_download` are keys of `llm_models`, and that every catalog entry is valid (LR-03, LR-04). A bad value stops the run with the list of valid names. |

### Models

| ID | Requirement |
|----|-------------|
| LR-02 | `llm_model` is the one model the service runs. `llm_download` lists extra models to keep on the host; it is empty by default. Together they are the wanted list. |
| LR-03 | `llm_models` is the catalog, and must not be empty. Each entry needs: `file`, a plain name that starts with a letter or digit, uses only letters, digits, `.`, `_` and `-`, and ends in `.gguf` (no `/`, no hidden file); `url`, starting with `https://`; `sha256`, 64 lowercase hex digits; `size`, the size in bytes as a whole number above 0. The sha256 and size come from the Hugging Face API (`https://huggingface.co/api/models/<repo>/tree/main`). |
| LR-04 | Each entry is one single-file GGUF. Split models (`-00001-of-00002.gguf`) are rejected until the role supports them. No two entries share a `file`. Every entry is checked, not only the wanted ones, before anything on the host changes (LR-01). |
| LR-05 | A new revision of a model gets a new catalog key and a new file name. If a wanted file is already on the host with a different sha256, the run stops and never overwrites it, because a rollback may need it. |
| LR-06 | A catalog entry is not a promise that the model works. A model is supported only if it runs on the pinned llama.cpp (`llm_image`) and on the hardware above: CPU only, 64 GB RAM. The checks in LR-19 to LR-21 are what prove it. |
| LR-07 | Before any download, the free space in `llm_models_dir` must be at least the size of the missing wanted files plus `llm_disk_reserve` (5 GiB). The reserve covers Ansible's temporary download file and a new image. The old model's space is not freed first, because it stays until the new one passes its checks. If it does not fit, the run stops before the service is touched. |
| LR-08 | Each wanted file is read once per run to check its sha256. Missing files are downloaded and checked against their sha256. A file already there with the right sum is not downloaded again. The directory is `root:llama 0750`; each file is `root:llama 0640`. |

### Image

| ID | Requirement |
|----|-------------|
| LR-09 | Creates the system user `llama`, with no login shell and no home. The container runs with its uid and gid, so the `root:llama` rights on the models and the key apply inside it too. |
| LR-10 | `llm_image` is llama.cpp's CPU server image, pinned by digest: `ghcr.io/ggml-org/llama.cpp:server-b11960@sha256:8052c13edd987de8858f8150031e025ac3d66823f09cf3ec8220899c4abce220`, the image llama.cpp published for its `v0.8.0` tag. The tag is for people; Docker uses the digest. The image picks the best code for the host's CPU when it starts (`GGML_CPU_ALL_VARIANTS`), so nothing is built on the host. |
| LR-11 | The image is pulled before the container is touched, so a failed pull leaves the running container as it is. The same image has `llama bench`: `sudo docker exec llama-server /app/llama bench -m /models/<file>`. |

### Container

| ID | Requirement |
|----|-------------|
| LR-12 | The API key is 40 letters and digits, generated once in `llm_key_file` (`root:llama 0640`). Later runs never replace it, but set its owner, group and mode back if they drifted. It never appears in Ansible output. |
| LR-13 | `llm_compose_dir/compose.yaml` defines one service, in a container named `llama-server`. It runs `llm_image` as `llama`, mounts `llm_models_dir` and `llm_key_file` read-only, and serves `llm_model` with the key, `--jinja`, `llm_threads` threads and an `llm_ctx` context. It listens on port 8080 inside the container, where the image's own health check looks, and publishes it on `llm_bind:llm_port` only. It drops every capability, sets `no-new-privileges`, and has `restart: unless-stopped`, so Docker starts it at boot. |
| LR-14 | The container is recreated only when the compose file or the image changed. Downloading an extra model does not recreate it. |
| LR-15 | Each run brings the service up with `docker compose`, which compares the running container with the compose file and recreates it if they differ. So a compose file that was written but never applied, for example because a run failed, was stopped with Ctrl-C or lost the host, is applied on the next run. There is no record file and no handler. |
| LR-16 | The role removes what the source build left: it stops, disables and deletes the `llama-server` systemd unit before the container starts, so the port is free, and deletes `/opt/llama.cpp`. A host that ran the source build keeps `build-essential` and `cmake`. |
| LR-17 | The API is plain HTTP, for the LAN only. There is no TLS. |

### Checks after every run

| ID | Requirement |
|----|-------------|
| LR-18 | The checks run after `docker compose` has brought the container up, so they see the final process. |
| LR-19 | `/health` must answer 200 within 5 minutes (60 tries, 5 s apart). It answers 503 while the model loads. |
| LR-20 | `/v1/models` must answer 200 with the key and 401 without one. The key is not shown in the output. |
| LR-21 | A chat request with the key (`Say hi.`, at most 32 tokens) must answer within `llm_check_timeout` (120 s), and its reply must hold text in `content` or, for a reasoning model, in `reasoning_content`. `/health` only shows that the file loaded; this shows the model can answer. |

### Cleanup

| ID | Requirement |
|----|-------------|
| LR-22 | Only after every check passes, every `.gguf` in `llm_models_dir` that is not in the wanted list is deleted. Ansible owns this directory: a file copied there by hand is deleted too. In the same step, every `ghcr.io/ggml-org/llama.cpp` image other than `llm_image` is removed. |

### Switching models and failures

| ID | Requirement |
|----|-------------|
| LR-23 | To switch, add the model to `llm_models` if needed, change `llm_model` in `group_vars/agent_servers.yml`, commit, and run `llm.yml`. The run downloads the new model, recreates the container, checks it, and then deletes the old model. |
| LR-24 | The model is changed in the file, not with `-e llm_model=...`. Otherwise the next plain run switches back and deletes the new model. |
| LR-25 | Change `llm_image` and `llm_model` in separate runs. To undo a llama.cpp upgrade, set `llm_image` back and run again. If the new image failed its checks, the old one is still on the host (LR-22), so nothing is pulled. |
| LR-26 | A failure before the container is recreated (settings check, free space, overwrite guard, download, checksum, pull) leaves the service running the current model. |
| LR-27 | A failure at or after the recreate (load, `/health`, key checks, chat check) can leave the API down until rollback. The old file is still on the host, because cleanup did not run. Rollback is manual and runs through Ansible: set `llm_model` back and run `llm.yml`. That run does not download the old model again, and its cleanup deletes the failed one. Automatic rollback is not required. |

## 5. Requests (`bruno/`)

| ID | Requirement |
|----|-------------|
| QR-01 | A Bruno collection named `llama-server` with four requests: models, models without a key, a chat completion and a tool call. |
| QR-02 | Each request checks its status: 200 for the three with the key, 401 for the one without. |
| QR-03 | The `lan` environment sets `baseUrl` to `http://192.168.150.221:8080`. `apiKey` is a Bruno secret, so the key stays out of the repo. |

## Out of scope

Ollama, the AI agent itself, application secrets and the firewall. Each will
be a later role with its own requirements. The firewall must allow for the
rules Docker writes for published ports, which bypass the host's own input
rules.

## Open decisions

| ID | Topic | Default |
|----|-------|---------|
| OD-01 | Target disk | `/dev/sda`, the 128 GB SATA SSD. Closed. |
| OD-02 | `devel`'s password | Typed at each build; the hash is only in the ISO. Closed. |
| OD-03 | Delivery of the preseed | Built into the netinst ISO by `build-iso.sh`. Replaces `preseed/url`, whose network answers came too late. Closed. |
| OD-04 | Reading the API key | `ssh -i ~/.ssh/agent-server ansible@192.168.150.221 sudo cat /etc/llama/api-key`. A read-only login, which GR-02 allows. Closed. |
| OD-05 | Version check in `llm.yml` | Both playbooks import `check-controller.yml` (AR-02). Closed. |
| OD-06 | Rollback after a failed switch | Manual, through Ansible (LR-27). Closed. Automatic rollback, which would restore the previous compose file, recreate the container and check it again, may be added later. |
| OD-07 | How llama.cpp runs | In Docker, from llama.cpp's published image (LR-10), instead of a source build under systemd. It drops the build, the build record and the restart handler, and `docker compose` applies an interrupted change on the next run (LR-15). Closed. |
| OD-08 | Where Docker comes from | Debian's packages (AR-10), not Docker's apt repository: no extra signing key, and security updates come with the rest of the system. Closed. |
| OD-09 | Container network | A port published on `llm_bind` only, not host networking, so the image's own health check on `localhost:8080` works. Closed. |

## Acceptance

### Install

1. `build-iso.sh` with the netinst ISO asks for the password twice and writes `install/build/agent-server.iso`; a second run replaces it without error.
2. Under `umask 0022`, and with an existing `install/build/` at `0755`, the result is a `0700` directory and a `0600` ISO. A build stopped half way keeps the previous ISO and leaves no partial file.
3. Booted in UEFI mode, the ISO installs to reboot with no keypress and no prompts; only the target disk changed.
4. After that reboot the installed system boots, not the installer.
5. `lsblk` shows EFI 1 GB, swap 8 GB, ext4 root; `/sys/firmware/efi` exists.
6. `ip addr` shows `192.168.150.221/24`; `getent hosts deb.debian.org` works.
7. `hostname` returns `agent-server`; `timedatectl` shows `Europe/Berlin`, and `timedatectl show -p NTPSynchronized` returns `NTPSynchronized=yes`.
8. `passwd -S root` shows `L`.
9. `ssh devel@192.168.150.221` with the password works; `sudo -v` works.
10. `python3 --version` works; `apt update` succeeds against all three suites.
11. No Docker, Ollama, agent, key or application secret on the system.

### Configure

1. With `ansible-core` older than 2.18, or without `community.docker` 4.0, `site.yml` and `llm.yml` each stop before they connect to the host.
2. First run as `devel` with `-k -K` succeeds; the second run, key only, reports 0 changed.
3. `ssh root@host` fails; `ssh ansible@host` with the key works; with a password it fails.
4. `passwd -S ansible` shows `L`; as `ansible`, `sudo -n true` works; as `devel`, `sudo` asks for the password.
5. `ansible agent_servers -m ping` returns `pong`.
6. `systemctl is-enabled apt-daily-upgrade.timer` returns `enabled`.
7. `systemctl is-enabled docker` returns `enabled`; `docker compose version` works.
8. `sudo docker info` shows the `journald` logging driver and `Live Restore Enabled: true`; `getent group docker` lists no members.

### Model server

1. The first `llm.yml` run pulls `llm_image`, downloads `llm_model`, starts the container and passes LR-19 to LR-21.
2. A second run reports 0 changed: no download, no deletion, no restart.
3. An unknown `llm_model`, two entries with the same `file`, or any entry that breaks LR-03 or LR-04 (for example a negative `size`, a missing `url` or `sha256`, a `file` with a `/`, or a split GGUF) fails the run before anything on the host changes.
4. A wrong digest in `llm_image` fails the run at the pull, and the running container keeps serving.
5. Changing only `llm_threads` recreates the container; adding a model to `llm_download` only does not.
6. On a host that ran the source build, the first run removes the `llama-server` unit and `/opt/llama.cpp`, and the container serves the same model without downloading it again.
7. A `.gguf` copied into `llm_models_dir` by hand is gone after the next run.
8. All four Bruno requests pass their status checks against the running server.
9. With `llm_key_file` set to `root:root 0600` by hand, the next run sets it back to `root:llama 0640`, and the key is unchanged.
10. After a reboot, the container is back and passes LR-19 to LR-21 without a playbook run.
11. After a successful change of `llm_image`, `sudo docker image ls ghcr.io/ggml-org/llama.cpp` lists only the new image. After a failed one, it lists both.
12. `sudo docker exec llama-server /app/llama bench -m /models/<llm_model's file>` prints a benchmark table.

### Switching models

All of these start from `qwen3-8b` running and `llm_download` empty.

1. Changing `llm_model` to `deepseek-r1-distill-qwen-7b` and running `llm.yml` leaves only the DeepSeek file in `llm_models_dir`, and the service answers a chat request with it.
2. With `llm_download: [qwen3-8b]`, the same switch keeps both files.
3. A broken download URL or a wrong sha256 fails the run. Qwen is still serving, and its file is still there.
4. With a `llm_disk_reserve` larger than the free space, the run fails before the download, and Qwen is still serving.
5. A catalog change that gives `Qwen3-8B-Q4_K_M.gguf` a different sha256 fails the run; the file on the host is unchanged.
6. A new model that passes `/health` but returns an empty reply, or no reply within the timeout, fails the run. The Qwen file is still there.
7. A new model that cannot load fails the run at `/health`, and the Qwen file is still there. Setting `llm_model` back and running again restores Qwen without a download, passes all checks, and deletes the failed file.
8. A second run after a successful switch reports 0 changed: no download, no deletion, no restart.
9. A switch stopped with Ctrl-C after the compose file is written and before the container is recreated: the next run recreates it, checks DeepSeek, and only then deletes the Qwen file.
