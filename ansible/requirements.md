# Requirements: configuration (Ansible)

Ansible owns everything after the install (`install/requirements.md`).
The host arrives with one `devel` user and its password, `sudo`,
`python3` and `openssh-server`, and nothing else configured.

## Requirements

| ID | Requirement |
|----|-------------|
| AR-01 | First run connects as `devel` with its password: `ansible-playbook site.yml -k -K -e ansible_user=devel`. Later runs connect as `ansible`. Needs `sshpass` and `ansible-core` 2.18 or later on the controller. |
| AR-02 | `users` role: creates `ansible` with no password, and writes the `authorized_keys` of `ansible` and `devel` from `agent_ssh_public_keys`, whole, so a dropped key is removed. |
| AR-03 | `users` role: passwordless sudo in `/etc/sudoers.d/ansible`, validated with `visudo -cf`. `devel` keeps Debian's `%sudo` rule, which asks for its password. |
| AR-04 | `users` role: never sets or changes a password. `devel`'s comes from the install. |
| AR-05 | `ssh` role: drop-in with `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, validated with `sshd -t -f`, then reload `ssh`. |
| AR-06 | `base` role: base packages, `unattended-upgrades` and its periodic config. No automatic reboot: reboot by hand when `/var/run/reboot-required` exists. |
| AR-07 | Roles run in the order `users`, `base`, `ssh`. |
| AR-08 | Values live in `group_vars/agent_servers.yml`. |
| AR-09 | Every task is idempotent: a second run reports no changes. |
| AR-10 | `users` role: fails first, changing nothing, if the public half of `ansible_ssh_private_key_file` is not in `agent_ssh_public_keys`. |

## Out of scope

Docker, Ollama, the AI agent, application secrets and the firewall are later
roles with their own requirements.

Hostname, timezone and NTP are set by the install alone (IR-03, IR-04).
Ansible does not manage them; if they drift, reinstall.

## Acceptance

1. First run as `devel` with `-k -K` succeeds; the second run, key only, reports 0 changed.
2. `ssh root@host` fails; `ssh ansible@host` with the key works; with a password it fails.
3. `passwd -S ansible` shows `L`; as `ansible`, `sudo -n true` works; as `devel`, `sudo` asks for the password.
4. `ansible agent_servers -m ping` returns `pong`.
5. `systemctl is-enabled apt-daily-upgrade.timer` returns `enabled`.
