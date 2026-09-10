<!--
SPDX-FileCopyrightText: 2026 Oliver Lorenz

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# ffc-hello Ansible role

A tiny demo/smoke-test service: an `nginx` container that returns `hello world`
on port 80, run as a **sidecar of the [`ffc-mesh-client`](../ffc-mesh-client)
container** — it joins that container's network namespace
(`--network=container:ffc-mesh-client`), so it has no network of its own and is
reachable exactly where ffc-mesh-client is: directly from the internet over
ffc-mesh-client's public Freifunk IPv6, **without any port-forward**.

nginx listens on both `0.0.0.0:80` and `[::]:80` (the mesh reachability is IPv6).

Depends on:

- the `ffc-mesh-client` role being enabled on the same host
- [`com.devture.ansible.role.systemd_docker_base`](https://github.com/devture/com.devture.ansible.role.systemd_docker_base)

## Configuration

Usually nothing. Optional knobs (see [`defaults/main.yml`](defaults/main.yml)):

- `ffc_hello_response_body` — the text to return (single line; default `hello world`)
- `ffc_hello_listen_port` — the port inside the shared netns (default `80`)
- `ffc_hello_version` — the `nginx` image tag (default `1.29-alpine`)
- `ffc_hello_shared_netns_container` — the container whose netns to join
  (default: `ffc-mesh-client`)

## systemd coupling

The service is `BindsTo=` + `PartOf=` `ffc-mesh-client.service`: it stops when
ffc-mesh-client stops and restarts when ffc-mesh-client restarts. This is
required because ffc-mesh-client's container (and therefore its netns) is
recreated on every restart, which invalidates the `container:` netns handle.

## Ports

A `--network=container:` sidecar **cannot publish host ports**. To also reach
this over a host port (in addition to the Freifunk IPv6), publish it on the
ffc-mesh-client container: `ffc_mesh_client_container_published_ports: ["8080:80"]`.

## Check

```sh
# from any host with IPv6 (the address is logged by `docker logs ffc-mesh-client`):
curl "http://[2001:bc8:3f13:ffc2:ff:c0ff:feXX:XXXX]/"     # -> hello world

# on the server itself:
docker exec ffc-mesh-client curl -s http://[::1]/          # -> hello world
```
