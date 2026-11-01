#!/usr/bin/env python3
# -* encoding: utf8 *-

# SPDX-FileCopyrightText: 2026 2026 Oliver Lorenz
#
# SPDX-License-Identifier: AGPL-3.0-or-later

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS_DIR = REPO_ROOT / ".github" / "workflows"
INVENTORY_PATH = REPO_ROOT / "inventory" / "hosts.yml"


def load_inventory():
    if not INVENTORY_PATH.is_file():
        return None
    # Imported lazily: environments without a local inventory checkout (e.g. the CI
    # pre-commit run) don't get here and needn't have PyYAML installed.
    import yaml

    # Expects the plain top-level-group YAML form: "<group>:\n  hosts:\n    <host>: {...}".
    return yaml.safe_load(INVENTORY_PATH.read_text()) or {}


def get_ready_hosts():
    inventory = load_inventory()
    if inventory is None:
        return None

    hosts = []
    for body in inventory.values():
        if not isinstance(body, dict):
            continue
        for host in body.get("hosts") or {}:
            if host not in hosts:
                hosts.append(host)

    return sorted(
        host
        for host in hosts
        if (REPO_ROOT / "inventory" / "host_vars" / host / "secrets.yml").is_file()
    )


def get_groups():
    inventory = load_inventory()
    if inventory is None:
        return None

    # Top-level keys are group names; "all" is Ansible's implicit group of every host.
    groups = (set(inventory) | {"all"}) - {"ungrouped"}
    return ["all"] + sorted(groups - {"all"})


def get_enabled_services():
    """Components in use by any host's vars.yml which run something in setup.yml.

    Mirrors bin/optimize.py's `activation_prefix` matching. Component names
    double as the service names for `just setup-service` (tags and groups).
    """
    import yaml

    class VarsLoader(yaml.SafeLoader):
        """Accepts Ansible-specific tags (like `!vault`) and ignores their values."""

    VarsLoader.add_multi_constructor("!", lambda loader, tag_suffix, node: None)

    used_variable_names = set()
    for path in sorted((REPO_ROOT / "inventory" / "host_vars").glob("*/vars.yml")):
        used_variable_names |= set(yaml.load(path.read_text(), Loader=VarsLoader) or {})
    if not used_variable_names:
        return []

    services = []
    for manifest_path in sorted((REPO_ROOT / "components").glob("*/component.yml")):
        manifest = yaml.load(manifest_path.read_text(), Loader=VarsLoader) or {}
        prefix = manifest.get("activation_prefix")
        if not isinstance(prefix, str):
            continue
        if prefix and not any(name.startswith(prefix) for name in used_variable_names):
            continue
        # `setup: []` means the component runs nothing in setup.yml
        if manifest.get("setup") == []:
            continue
        services.append(manifest_path.parent.name)
    return services


def replace_generated_block(text, marker, items):
    begin = f"# BEGIN GENERATED: {marker}"
    end = f"# END GENERATED: {marker}"
    pattern = re.compile(
        r"^( *)" + re.escape(begin) + r"\n(?:.*\n)*?( *)" + re.escape(end) + r"\n",
        re.MULTILINE,
    )

    def _sub(match):
        indent = match.group(1)
        body = "".join(f"{indent}- {item}\n" for item in items)
        return f"{indent}{begin}\n{body}{indent}{end}\n"

    return pattern.subn(_sub, text)


def main():
    hosts = get_ready_hosts()

    if hosts is None:
        print(
            "inventory/hosts.yml not found -- skipping "
            "(this check requires a local checkout of the private inventory submodule).",
        )
        return 0

    groups = get_groups()
    services = get_enabled_services()

    if not hosts:
        print(
            "::error::No hosts with inventory/host_vars/<host>/secrets.yml found -- refusing to generate an empty choice list.",
            file=sys.stderr,
        )
        return 1

    changed_files = []
    for path in sorted(WORKFLOWS_DIR.glob("*.yml")):
        text = path.read_text()
        original = text

        text, group_replacements = replace_generated_block(text, "groups", groups)
        text, host_replacements = replace_generated_block(text, "hosts", hosts)
        text, service_replacements = replace_generated_block(text, "services", services)

        if service_replacements and not services:
            print(
                f"::error::{path}: no services found to populate the 'services' choice list.",
                file=sys.stderr,
            )
            return 1

        if text != original:
            path.write_text(text)
            changed_files.append(path.relative_to(REPO_ROOT))

    if changed_files:
        print("Updated generated options in:")
        for path in changed_files:
            print(f"  {path}")
        return 1

    print("Generated workflow options are already up to date.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
