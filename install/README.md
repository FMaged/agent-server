# Unattended install

`preseed.cfg` answers every question the Debian 13 (trixie) installer asks, so
the install runs start to finish without a prompt and reboots into a plain
Debian with SSH, `sudo` and Python. It configures nothing else: keys, sshd and
sudo are set by the playbook in `ansible/`.

`build-iso.sh` puts the preseed into the netinst's initrd, where the installer
reads it before its first question, the network included.

## Before you start

The only login is `ansible` with the password hash in `preseed.cfg`. Root is
locked. Replace the hash if you do not know its password. The ISO carries that
hash, so do not publish it.

Check that `partman-auto/disk` names the target machine's disk. It is set to
`/dev/sda`; an NVMe SSD is usually `/dev/nvme0n1`. That disk is erased whole.

## Build the ISO

Needs `xorriso`, `cpio` and `gzip`. Download the netinst and its `SHA256SUMS`
into the same directory from
`https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/`, then:

```
install/build-iso.sh ~/Downloads/debian-13.7.0-amd64-netinst.iso
```

This writes `install/build/agent-server.iso`. Rebuild after every change to
`preseed.cfg`. Write it to a USB stick (all data on the stick is lost):

```
install/flash-usb.sh
```

It finds the stick, shows it, and writes only after you type `yes`. Plug in
one USB disk only; with none or several it stops.

## Boot it

Boot the stick **in UEFI mode**, with CSM off, from the firmware's one-time boot
menu. After 5 seconds the installer starts on its own and erases the disk. The
partition layout depends on UEFI; a BIOS/CSM boot is not supported.

Use the one-time menu, not the boot order: the installer reboots when done, and
a stick that boots first again starts the install again.

The installer still needs the network: it downloads packages from
`deb.debian.org`.

## After it reboots

The host comes up on `192.168.150.221` as `ansible`. Run the playbook once with
the bootstrap password; it installs your key, closes password login and
removes the password:

```
cd ansible && ansible-playbook site.yml -k -K
```

A reinstall gives the host a new SSH host key, which SSH refuses as a mismatch.
Drop the stale entry with `ssh-keygen -R 192.168.150.221`.
