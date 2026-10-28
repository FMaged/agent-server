# Requirements: configuration (Ansible)

Ansible owns everything after the install (`install/requirements.md`).
The host arrives with one `ansible` user, a bootstrap password, `sudo`,
`python3` and `openssh-server`, and nothing else configured.

## Requirements

| ID | Requirement |
|----|-------------|
| AR-01 | First run connects with the bootstrap password: `ansible-playbook site.yml -k -K`. Needs `sshpass` and `ansible-core` 2.14 or later on the controller. |
| AR-02 | `users` role: writes the `ansible` user's `authorized_keys` from `agent_ssh_public_keys`, whole, so a dropped key is removed. |
| AR-03 | `users` role: passwordless sudo in `/etc/sudoers.d/ansible`, validated with `visudo -cf`. Written before the password is removed. |
| AR-04 | `users` role: locks the bootstrap password (`*`), leaving the key as the only credential. |
| AR-05 | `ssh` role: drop-in with `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, validated with `sshd -t -f`, then reload `ssh`. |
| AR-06 | `base` role: base packages, `unattended-upgrades` and its periodic config. |
| AR-07 | Roles run in the order `users`, `base`, `ssh`. |
| AR-08 | Values live in `group_vars/agent_servers.yml`. |
| AR-09 | Every task is idempotent: a second run reports no changes. |

## Out of scope

Docker, Ollama, the AI agent, application secrets and the firewall are later
roles with their own requirements.

## Acceptance

1. First run with `-k -K` succeeds; the second run, key only, reports 0 changed.
2. `ssh root@host` fails; `ssh ansible@host` with the key works; with a password it fails.
3. `passwd -S ansible` shows `L`; `sudo -n true` works.
4. `ansible agent_servers -m ping` returns `pong`.
5. `systemctl is-enabled apt-daily-upgrade.timer` returns `enabled`.
