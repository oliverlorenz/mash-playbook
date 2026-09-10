<!--
SPDX-FileCopyrightText: 2026 Oliver Lorenz

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# unattended-upgrades Ansible role

Installs and configures Debian/Ubuntu [`unattended-upgrades`](https://wiki.debian.org/UnattendedUpgrades)
on the host itself, so security updates are applied via systemd timers between
playbook runs.

This complements the `cleanup` role (`system_cleanup_apt`), which only upgrades
packages while the playbook is running.

## Usage

Enable it per host in `inventory/host_vars/<host>/vars.yml`:

```yaml
unattended_upgrades_enabled: true
```

The role keeps the distribution's stock origin list (security pocket only) and
only manages two `apt.conf.d` drop-ins:

- `20auto-upgrades` — turns the periodic update/upgrade tasks on
- `52unattended-upgrades-mash.conf` — auto-reboot, mail and autoremove overrides
  (loaded after `50unattended-upgrades`, so it wins)

See `defaults/main.yml` for all options (auto-reboot time, `unattended_upgrades_mail`,
`unattended_upgrades_remove_unused_dependencies`, ...).

Setting `unattended_upgrades_enabled: false` removes the role's drop-ins and
disables the periodic tasks, but deliberately leaves the `unattended-upgrades`
package and the `apt-daily*` timers (part of a stock install) in place.
