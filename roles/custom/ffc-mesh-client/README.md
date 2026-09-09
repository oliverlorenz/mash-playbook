<!--
SPDX-FileCopyrightText: 2026 Oliver Lorenz

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# ffc-mesh-client Ansible role

An [Ansible](https://www.ansible.com/) role which installs the
[ffc-mesh-client](https://github.com/FreifunkChemnitz/ffc-mesh-client)
(`fastd` + `batman-adv` mesh client for Freifunk Chemnitz) as a
[Docker](https://www.docker.com/) container wrapped in a systemd service.

The container joins the FFC mesh, obtains a globally routed **public IPv6**
(reachable from the internet without any port-forward) and routes its own
traffic – and that of sidecar containers sharing its network namespace – through
the Freifunk exit gateways. It is **not** a full Freifunk node: no WiFi, no
client SSID; only the uplink / `mesh_vpn` side, comparable to a VPN client
container like `gluetun`.

This role *implicitly* depends on:

- [`com.devture.ansible.role.playbook_help`](https://github.com/devture/com.devture.ansible.role.playbook_help)
- [`com.devture.ansible.role.systemd_docker_base`](https://github.com/devture/com.devture.ansible.role.systemd_docker_base)
- [`com.devture.ansible.role.systemd_service_manager`](https://github.com/devture/com.devture.ansible.role.systemd_service_manager)

Check [`defaults/main.yml`](defaults/main.yml) for the full list of supported options.

## Configuration

At minimum you need to set:

- `ffc_mesh_client_fastd_secret` — the fastd secret key. Generate a keypair once with:

  ```sh
  docker run --rm --entrypoint "fastd --generate-key" \
    ghcr.io/freifunkchemnitz/ffc-mesh-client:latest
  ```

  Use the `Secret:` value here. If the supernodes don't auto-accept unknown
  keys, register the `Public:` value with Freifunk Chemnitz.

- `ffc_mesh_client_mesh_mac` — a stable, locally-administered MAC for `bat0`.
  It also determines the container's public Freifunk IPv6 via EUI-64, so keep
  it fixed once chosen. Example: `02:ff:c0:11:22:33` →
  `2001:bc8:3f13:ffc2:ff:c0ff:fe11:2233`.

- `ffc_mesh_client_container_image_registry_username` /
  `ffc_mesh_client_container_image_registry_password` — a GitHub username plus a
  personal access token with the `read:packages` scope, because the GHCR
  package is private. Leave both empty if the package has been made public.

`ffc_mesh_client_fastd_secret` and the registry password are secrets — define
them in an ansible-vault-encrypted file (e.g.
`inventory/host_vars/<server>/vault.yml`), not in plain `group_vars`.

### Host prerequisite: the `batman-adv` kernel module

`batman-adv` cannot be loaded from inside the container. By default this role
loads it on the host (`modprobe`) and makes it persistent
(`/etc/modules-load.d/batman-adv.conf`). Set
`ffc_mesh_client_host_manage_batman_adv_module: false` to manage it yourself.

The container also needs `/dev/net/tun` on the host and the `NET_ADMIN` +
`NET_RAW` capabilities. If that turns out to be insufficient on your
host/kernel, set `ffc_mesh_client_container_privileged: true`.

## Routing modes

- `ffc_mesh_client_default_via_mesh: true` (default) — the container's entire
  default route goes through the Freifunk exit. Sidecar containers started with
  `network_mode: "service:ffc-mesh-client"` inherit this.
- `ffc_mesh_client_default_via_mesh: false` — only NAT'ed / routed clients go
  via FFC; the container's own default route stays on the real uplink.

## IPv6

The container's IPv6 comes from the mesh (`bat0`, SLAAC out of
`2001:bc8:3f13:ffc2::/64`). The role's own Docker network is therefore created
**without** an IPv6 subnet (`ffc_mesh_client_container_network_ipv6_enabled:
false`), even when the playbook-global `devture_systemd_docker_base_ipv6_enabled`
is `true`: a second, Docker-managed IPv6 default route on `eth0` competes with
`bat0`'s (same metric 1024) and breaks the symmetric return path that inbound
traffic to the public mesh IPv6 relies on.

## Exposing a sidecar service

Because sidecar containers share this container's network namespace, publish
their ports **here** (`ffc_mesh_client_container_published_ports`), not on the
sidecar. The container is also directly reachable over its Freifunk IPv6
(logged at startup) without any port-forward — a service in the shared netns
just has to listen on `::`, not only `127.0.0.1`.

## Checking status

```sh
docker logs ffc-mesh-client                                 # startup log incl. the public IPv6
docker exec ffc-mesh-client batctl meshif bat0 gwl          # mesh gateways + TQ (good: >200)
docker exec ffc-mesh-client curl -s https://ifconfig.co/json  # IPv4 exit IP (NAT)
docker exec ffc-mesh-client curl -s6 https://ifconfig.co      # IPv6 = the container's own address
```
