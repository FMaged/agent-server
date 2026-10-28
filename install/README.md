# Unattended install

`preseed.cfg` answers every question the Debian 13 (trixie) installer asks, so
the install runs start to finish without a prompt and reboots into a plain
Debian with SSH, `sudo` and Python. It configures nothing else: keys, sshd and
sudo are set by the playbook in `ansible/`.

`build-iso.sh` puts the preseed into the netinst's initrd, where the installer
reads it before its first question, the network included.

## Before you start

The only login is `devel`, with the password you type when you build the ISO.
Root is locked. The hash is in the ISO only, never in the repo, so keep the ISO
private.

Check that `partman-auto/disk` names the target machine's disk. It is set to
`/dev/sda`; an NVMe SSD is usually `/dev/nvme0n1`. That disk is erased whole.

## Build the ISO

Needs `xorriso`, `cpio`, `gzip` and `openssl`. Download the netinst and its `SHA256SUMS`
into the same directory from
`https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/`, then:

```
install/build-iso.sh ~/Downloads/debian-13.7.0-amd64-netinst.iso
```

It asks for `devel`'s password twice, then writes
`install/build/agent-server.iso`. Rebuild after every change to `preseed.cfg`
or to the password. Write it to a USB stick (all data on the stick is lost):

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

The host comes up on `192.168.150.221` with `devel`. Run the playbook once as
`devel`, with its password; it creates `ansible`, installs your key and closes
password login:

```
cd ansible && ansible-playbook site.yml -k -K -e ansible_user=devel
```

A reinstall gives the host a new SSH host key, which SSH refuses as a mismatch.
Drop the stale entry with `ssh-keygen -R 192.168.150.221`.
