# Requirements: agent-server

This repo turns one bare-metal machine into `agent-server`: a Debian 13 host
for coding agents that serves a local model over HTTP on the LAN. It does this
in three stages, each owned by one part of the repo:

1. **Install** (`install/`): an unattended Debian install from a USB stick.
2. **Configure** (`ansible/site.yml`): users, SSH, packages and updates.
3. **Model server** (`ansible/llm.yml`): llama.cpp serving one model behind an
   API key.

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
| GR-05 | Every download is pinned: the Debian ISO by Debian's `SHA256SUMS`, llama.cpp by a git tag, each model by its sha256. |
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
| AR-02 | The controller needs `ansible-core` 2.18 or later, the first release that supports Python 3.13 on the target. `site.yml` and `llm.yml` both start with `check-controller.yml`, which checks this on the controller and stops before any host is touched. |
| AR-03 | `users` role: fails first, changing nothing, if the public half of `ansible_ssh_private_key_file` is not in `agent_ssh_public_keys`. |
| AR-04 | `users` role: creates `ansible` with no password, and writes the `authorized_keys` of `ansible` and `devel` from `agent_ssh_public_keys`, whole, so a dropped key is removed. |
| AR-05 | `users` role: passwordless sudo in `/etc/sudoers.d/ansible`, validated with `visudo -cf`. `devel` keeps Debian's `%sudo` rule, which asks for its password. |
| AR-06 | `users` role: never sets or changes a password. `devel`'s comes from the install. |
| AR-07 | `ssh` role: drop-in with `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, validated with `sshd -t -f`, then reload `ssh`. |
| AR-08 | `base` role: the packages in `base_packages`, `unattended-upgrades` and its periodic config in `/etc/apt/apt.conf.d/20auto-upgrades`. No automatic reboot: reboot by hand when `/var/run/reboot-required` exists. |
| AR-09 | Roles run in the order `users`, `base`, `ssh`, so `ansible` has its key and sudo before password login is turned off. |

Hostname, timezone and NTP are set by the install alone (IR-03, IR-04).
Ansible does not manage them; if they drift, reinstall.

## 4. Model server (`llm.yml`)

`llm.yml` runs the `llm` role, after `site.yml`, as `ansible`. Its steps run
in this order: settings check, models, build, unit, checks, cleanup. Every
step that can fail without touching the service comes before the service is
restarted.

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
| LR-06 | A catalog entry is not a promise that the model works. A model is supported only if it runs on the pinned llama.cpp (`llm_tag`) and on the hardware above: CPU only, 64 GB RAM. The checks in LR-19 to LR-21 are what prove it. |
| LR-07 | Before any download, the free space in `llm_models_dir` must be at least the size of the missing wanted files plus `llm_disk_reserve` (5 GiB). The reserve covers Ansible's temporary download file. The old model's space is not freed first, because it stays until the new one passes its checks. If it does not fit, the run stops before the service is touched. |
| LR-08 | Each wanted file is read once per run to check its sha256. Missing files are downloaded and checked against their sha256. A file already there with the right sum is not downloaded again. The directory is `root:llama 0750`; each file is `root:llama 0640`. |

### Build

| ID | Requirement |
|----|-------------|
| LR-09 | Installs `llm_build_packages` and creates the system user `llama`, with no login shell and no home. |
| LR-10 | Clones `llm_repo` at the tag `llm_tag` into `llm_src_dir`. |
| LR-11 | Builds `llama-server` and `llama-bench` with `-DGGML_NATIVE=ON -DCMAKE_BUILD_TYPE=Release` on every run. The web UI is off (`-DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF`): by default llama.cpp downloads it at build time and falls back to `latest`, which GR-05 forbids. The build is incremental, so an unchanged tree is quick, and a build that failed last time is finished on the next run. It fails the run if either binary is missing afterwards. |

### Service

| ID | Requirement |
|----|-------------|
| LR-12 | The API key is 40 letters and digits, generated once in `llm_key_file` (`root:llama 0640`). Later runs never replace it, but set its owner, group and mode back if they drifted. It never appears in Ansible output. |
| LR-13 | A systemd unit `llama-server` runs as `llama`, listens on `llm_bind:llm_port`, serves `llm_model`, and reads the key from `llm_key_file`. It uses `--jinja`, `llm_threads` threads and an `llm_ctx` context, restarts on failure, and is enabled at boot. |
| LR-14 | The service restarts only when the build or the unit changed. Downloading an extra model does not restart it. |
| LR-15 | "The build" is the sha256 of `llama-server`, `llama-bench` and every shared library under `build/` (outside `CMakeFiles/`); "the unit" is the sha256 of the installed unit file. Each run compares both with what the service last passed its checks with, kept in `build/activated.sha256`, not with the start of the same run, and restarts if either differs. That file is written only after every check passes (LR-19 to LR-21). So a build or a unit that was written but never activated, for example because a run failed half way, was stopped with Ctrl-C or lost the host, still gets its restart on the next run. A missing file means a restart. |
| LR-16 | A restart that was due when a later task failed still runs in the same run (`force_handlers`). An interrupted run runs no handlers; LR-15 restarts on the next run instead. |
| LR-17 | The API is plain HTTP, for the LAN only. There is no TLS. |

### Checks after every run

| ID | Requirement |
|----|-------------|
| LR-18 | Pending restarts run before the checks, so the checks see the final process. |
| LR-19 | `/health` must answer 200 within 5 minutes (60 tries, 5 s apart). It answers 503 while the model loads. |
| LR-20 | `/v1/models` must answer 200 with the key and 401 without one. The key is not shown in the output. |
| LR-21 | A chat request with the key (`Say hi.`, at most 32 tokens) must answer within `llm_check_timeout` (120 s), and its reply must hold text in `content` or, for a reasoning model, in `reasoning_content`. `/health` only shows that the file loaded; this shows the model can answer. |

### Cleanup

| ID | Requirement |
|----|-------------|
| LR-22 | Only after every check passes, every `.gguf` in `llm_models_dir` that is not in the wanted list is deleted. Ansible owns this directory: a file copied there by hand is deleted too. |

### Switching models and failures

| ID | Requirement |
|----|-------------|
| LR-23 | To switch, add the model to `llm_models` if needed, change `llm_model` in `group_vars/agent_servers.yml`, commit, and run `llm.yml`. The run downloads the new model, restarts the service, checks it, and then deletes the old model. |
| LR-24 | The model is changed in the file, not with `-e llm_model=...`. Otherwise the next plain run switches back and deletes the new model. |
| LR-25 | Change `llm_tag` and `llm_model` in separate runs. Rollback (LR-27) covers a model change only. To undo a llama.cpp upgrade, set `llm_tag` back and run again; that rebuilds the old tag. |
| LR-26 | A failure before the restart (settings check, free space, overwrite guard, download, checksum, build) leaves the service running the current model. |
| LR-27 | A failure at or after the restart (load, `/health`, key checks, chat check) can leave the API down until rollback. The old file is still on the host, because cleanup did not run. Rollback is manual and runs through Ansible: set `llm_model` back and run `llm.yml`. That run does not download the old model again, and its cleanup deletes the failed one. Automatic rollback is not required. |

## 5. Requests (`bruno/`)

| ID | Requirement |
|----|-------------|
| QR-01 | A Bruno collection named `llama-server` with four requests: models, models without a key, a chat completion and a tool call. |
| QR-02 | Each request checks its status: 200 for the three with the key, 401 for the one without. |
| QR-03 | The `lan` environment sets `baseUrl` to `http://192.168.150.221:8080`. `apiKey` is a Bruno secret, so the key stays out of the repo. |

## Out of scope

Docker, Ollama, the AI agent itself, application secrets and the firewall.
Each will be a later role with its own requirements.

## Open decisions

| ID | Topic | Default |
|----|-------|---------|
| OD-01 | Target disk | `/dev/sda`, the 128 GB SATA SSD. Closed. |
| OD-02 | `devel`'s password | Typed at each build; the hash is only in the ISO. Closed. |
| OD-03 | Delivery of the preseed | Built into the netinst ISO by `build-iso.sh`. Replaces `preseed/url`, whose network answers came too late. Closed. |
| OD-04 | Reading the API key | `ssh -i ~/.ssh/agent-server ansible@192.168.150.221 sudo cat /etc/llama/api-key`. A read-only login, which GR-02 allows. Closed. |
| OD-05 | Version check in `llm.yml` | Both playbooks import `check-controller.yml` (AR-02). Closed. |
| OD-06 | Rollback after a failed switch | Manual, through Ansible (LR-27). Closed. Automatic rollback, which would restore the previous unit, restart it and check it again, may be added later. |

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

1. With `ansible-core` older than 2.18, `site.yml` and `llm.yml` each stop before they connect to the host.
2. First run as `devel` with `-k -K` succeeds; the second run, key only, reports 0 changed.
3. `ssh root@host` fails; `ssh ansible@host` with the key works; with a password it fails.
4. `passwd -S ansible` shows `L`; as `ansible`, `sudo -n true` works; as `devel`, `sudo` asks for the password.
5. `ansible agent_servers -m ping` returns `pong`.
6. `systemctl is-enabled apt-daily-upgrade.timer` returns `enabled`.

### Model server

1. The first `llm.yml` run builds llama.cpp, downloads `llm_model`, starts the service and passes LR-19 to LR-21.
2. A second run reports 0 changed: no download, no deletion, no restart.
3. An unknown `llm_model`, two entries with the same `file`, or any entry that breaks LR-03 or LR-04 (for example a negative `size`, a missing `url` or `sha256`, a `file` with a `/`, or a split GGUF) fails the run before any package is installed.
4. If the build of a new `llm_tag` fails while the old binary is still there, the next run finishes the build and restarts the service. The same holds when only `llama-bench` is missing.
5. If a run writes a new build and then fails, at the build or at any check after the restart, the next run restarts the service again and only then updates `build/activated.sha256`.
6. A change to a shared library alone, with both binaries unchanged, restarts the service.
7. A `.gguf` copied into `llm_models_dir` by hand is gone after the next run.
8. All four Bruno requests pass their status checks against the running server.
9. With `llm_key_file` set to `root:root 0600` by hand, the next run sets it back to `root:llama 0640`, and the key is unchanged.

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
9. A switch stopped with Ctrl-C after the unit is written and before the restart: the next run restarts the service, checks DeepSeek, and only then deletes the Qwen file.
