<!--
SPDX-FileCopyrightText: 2020 - 2024 MDAD project contributors
SPDX-FileCopyrightText: 2020 - 2024 Slavi Pantaleev
SPDX-FileCopyrightText: 2020 Aaron Raimist
SPDX-FileCopyrightText: 2020 Chris van Dijk
SPDX-FileCopyrightText: 2020 Dominik Zajac
SPDX-FileCopyrightText: 2020 Mickaël Cornière
SPDX-FileCopyrightText: 2022 François Darveau
SPDX-FileCopyrightText: 2022 Julian Foad
SPDX-FileCopyrightText: 2022 Warren Bailey
SPDX-FileCopyrightText: 2023 Antonis Christofides
SPDX-FileCopyrightText: 2023 Felix Stupp
SPDX-FileCopyrightText: 2023 Julian-Samuel Gebühr
SPDX-FileCopyrightText: 2023 Pierre 'McFly' Marty
SPDX-FileCopyrightText: 2024 Thomas Miceli
SPDX-FileCopyrightText: 2024 - 2025 Suguru Hirahara

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Setting up Pterodactyl Panel

This is an [Ansible](https://www.ansible.com/) role which installs [Pterodactyl Panel](https://github.com/pterodactyl/panel) to run as a [Docker](https://www.docker.com/) container wrapped in a systemd service.

See the project's [documentation](https://github.com/pterodactyl/panel) to learn what Pterodactyl Panel does and why it might be useful to you.

## Prerequisites

To run an Pterodactyl Panel it is necessary to prepare an server.

If you are looking for an Ansible role for Pterodactyl Panel, you can check out [ansible-role-pterodactyl-panel](https://github.com/mother-of-all-self-hosting/ansible-role-pterodactyl-panel) maintained by the [Mother-of-All-Self-Hosting (MASH)](https://github.com/mother-of-all-self-hosting) team.

## Adjusting the playbook configuration

To enable Pterodactyl Panel with this role, add the following configuration to your `vars.yml` file.

**Note**: the path should be something like `inventory/host_vars/mash.example.com/vars.yml` if you use the [MASH Ansible playbook](https://github.com/mother-of-all-self-hosting/mash-playbook).

```yaml
########################################################################
#                                                                      #
# pterodactyl_panel                                                         #
#                                                                      #
########################################################################

pterodactyl_panel_enabled: true

########################################################################
#                                                                      #
# /pterodactyl_panel                                                        #
#                                                                      #
########################################################################
```

### Exposing the instance (optional)

By default, the Pterodactyl Panel is not exposed externally, as it is mainly intended to be used in the internal network, connected to the Pterodactyl Panel server.

To expose it to the internet, add the following configuration to your `vars.yml` file. Make sure to replace `example.com` with your own value.

```yaml
pterodactyl_panel_hostname: "example.com"

pterodactyl_panel_container_labels_traefik_enabled: true
```

After adjusting the hostname, make sure to adjust your DNS records to point the domain to your server.

**Note**: hosting Pterodactyl Panel under a subpath (by configuring the `pterodactyl_panel_path_prefix` variable) does not seem to be possible due to Pterodactyl Panel's technical limitations.

>[!NOTE]
> When exposing the instance, it is recommended to consider to set a password (see [this section](https://github.com/pterodactyl/panelconfiguration/additional-options/#password) for the necessary configuration) as well as enable a service for authentication such as [authentik](https://goauthentik.io/) and [Tinyauth](https://tinyauth.app) based on your use-case.

### Extending the configuration

There are some additional things you may wish to configure about the component.

Take a look at:

- [`defaults/main.yml`](../defaults/main.yml) for some variables that you can customize via your `vars.yml` file. You can override settings (even those that don't have dedicated playbook variables) using the `pterodactyl_panel_environment_variables_additional_variables` variable

See [the official documentation](https://github.com/pterodactyl/panelconfiguration/) for a complete list of Pterodactyl Panel's config options that you could put in `pterodactyl_panel_environment_variables_additional_variables`.

## Installing

After configuring the playbook, run the installation command of your playbook as below:

```sh
ansible-playbook -i inventory/hosts setup.yml --tags=setup-all,start
```

If you use the MASH playbook, the shortcut commands with the [`just` program](https://github.com/mother-of-all-self-hosting/mash-playbook/blob/main/docs/just.md) are also available: `just install-all` or `just setup-all`

## Usage

After running the command for installation, Pterodactyl Panel becomes available internally to other services on the same network. If the service is exposed to the internet, it becomes available at the specified hostname like `https://example.com`.

To get started, refer to [the documentation](https://github.com/pterodactyl/panel) and other pages for guides about how to display pictures on devices.

## Troubleshooting

### Check the service's logs

You can find the logs in [systemd-journald](https://www.freedesktop.org/software/systemd/man/systemd-journald.service.html) by logging in to the server with SSH and running `journalctl -fu pterodactyl-panel` (or how you/your playbook named the service, e.g. `mash-pterodactyl-panel`).
