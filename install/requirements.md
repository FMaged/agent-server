# Requirements: Debian install (preseed)

File produced: `preseed.cfg`. Target: `agent-server`, bare metal, UEFI.

## Scope

Preseed only installs Debian and leaves a host Ansible can reach. All
configuration is Ansible's job (`ansible/requirements.md`).

Preseed does not: place SSH keys, write sshd or sudoers files, set up
users beyond the bootstrap login, run a `late_command`, or install anything
beyond the packages listed below.

## Hardware

128 GB SATA SSD (LITEON CV8-8E128-11), 64 GB RAM, one wired interface, no dedicated GPU.

## Requirements

| ID | Requirement |
|----|-------------|
| IR-01 | Fully unattended; no prompts. Boot in UEFI mode. |
| IR-02 | Debian 13 `trixie` from `deb.debian.org`, with `main` and `non-free-firmware`, plus `trixie-updates` and `trixie-security`. |
| IR-03 | `en_US.UTF-8`, US keyboard, `Europe/Berlin`, hardware clock in UTC, NTP. |
| IR-04 | Static IPv4 `192.168.150.221/24`, gateway and DNS `192.168.150.1`, hostname `agent-server`, no domain. No DHCP. |
| IR-05 | Install to one explicit disk (`partman-auto/disk`). Existing LVM/RAID on it is discarded. |
| IR-06 | Layout: EFI 1 GB (FAT32), swap 8 GB, ext4 `/` on the rest. |
| IR-07 | GRUB for UEFI, also to the removable path. |
| IR-08 | Tasks `standard` and `ssh-server`, plus `sudo` and `python3`. No desktop. |
| IR-09 | Updates applied during install (`safe-upgrade`). No update policy set. |
| IR-10 | Root login disabled. One user, `ansible`, in group `sudo`, with a bootstrap password. |
| IR-11 | The installer reboots by itself when done. |

## Handoff to Ansible

| Item | Value |
|------|-------|
| Address | `192.168.150.221` |
| SSH user | `ansible`, bootstrap password (public in `preseed.cfg`) |
| Privilege | `sudo` with that password |
| Python | `/usr/bin/python3` |
| Not present | SSH key, sshd drop-ins, sudoers drop-ins |

Changing any of this is a requirements change on both sides.

## Open decisions

| ID | Topic | Default |
|----|-------|---------|
| OD-01 | Target disk | `/dev/sda`, the 128 GB SATA SSD. Closed. |
| OD-02 | Bootstrap password | Hash in `preseed.cfg`; replace for any host that is not on a private LAN. |
| OD-03 | Delivery | `preseed/url` over HTTP from the workstation. |

## Acceptance

1. Install runs to reboot with no prompts; only the target disk changed.
2. `lsblk` shows EFI 1 GB, swap 8 GB, ext4 root; `/sys/firmware/efi` exists.
3. `ip addr` shows `192.168.150.221/24`; `getent hosts deb.debian.org` works.
4. `hostname` returns `agent-server`.
5. `passwd -S root` shows `L`.
6. `ssh ansible@192.168.150.221` with the password works; `sudo -v` works.
7. `python3 --version` works; `apt update` succeeds against all three suites.
8. No Docker, Ollama, agent, key or application secret on the system.
