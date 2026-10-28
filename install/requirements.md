# Requirements: Debian install (preseed)

Files produced: `preseed.cfg`; `build-iso.sh`, which builds it into a Debian
netinst ISO; and `flash-usb.sh`, which writes that ISO to a USB stick.
Target: `agent-server`, bare metal, UEFI.

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
| IR-12 | The preseed reaches the installer inside the ISO (BR-03), not over the network. |

## ISO build

| ID | Requirement |
|----|-------------|
| BR-01 | `install/build-iso.sh`, bash. Runs as a normal user: no root, no loop mounts. Needs `xorriso`, `cpio` and `gzip`, and stops naming any that is missing. |
| BR-02 | Input: the official Debian 13 amd64 netinst ISO, given as an argument. Checked against Debian's `SHA256SUMS` before it is modified. |
| BR-03 | `preseed.cfg` is added to `install.amd/initrd.gz` as `/preseed.cfg`, so it is read before the first question, network included. |
| BR-04 | The UEFI GRUB menu gets a default entry that starts the install after a 5 s timeout. Nothing is typed at the boot line. BIOS boot is not supported. |
| BR-05 | `md5sum.txt` is regenerated, and the original boot records are kept, so the image boots from a USB stick written with `dd`. |
| BR-06 | Output: `install/build/agent-server.iso`, overwritten on each run. `install/build/` is in `.gitignore`. Nothing else is left behind. |
| BR-07 | Every change to `preseed.cfg` needs a rebuild. The bootstrap hash is public in `preseed.cfg` and the ISO alike; a host off the private LAN needs a new one (OD-02). |
| BR-08 | The ISO erases the disk without asking. Boot it once, from the firmware's one-time boot menu, so that after IR-11 the installed system boots, not the ISO again. |
| BR-09 | `install/flash-usb.sh`, bash. Writes the ISO with `dd` to the one USB disk found, after a typed `yes`. Stops with none or several. |

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
| OD-03 | Delivery | Built into the netinst ISO by `build-iso.sh`. Replaces `preseed/url`, whose network answers came too late. Closed. |

## Acceptance

1. `build-iso.sh` with the netinst ISO writes `install/build/agent-server.iso`; a second run replaces it without error.
2. Booted in UEFI mode, the ISO installs to reboot with no keypress and no prompts; only the target disk changed.
3. After that reboot the installed system boots, not the installer.
4. `lsblk` shows EFI 1 GB, swap 8 GB, ext4 root; `/sys/firmware/efi` exists.
5. `ip addr` shows `192.168.150.221/24`; `getent hosts deb.debian.org` works.
6. `hostname` returns `agent-server`; `timedatectl` shows `Europe/Berlin`, and `timedatectl show -p NTPSynchronized` returns `NTPSynchronized=yes`.
7. `passwd -S root` shows `L`.
8. `ssh ansible@192.168.150.221` with the password works; `sudo -v` works.
9. `python3 --version` works; `apt update` succeeds against all three suites.
10. No Docker, Ollama, agent, key or application secret on the system.
