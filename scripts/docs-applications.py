#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["ruamel.yaml>=0.18"]
# ///
"""Regenerate the app tables in docs/kubernetes/applications.md.

The app list, Exposure and Uses columns and the Disabled table are derived
from kubernetes/apps. Purpose and Upstream are hand-written: they are read
back from the current page and kept. Only the region between the
`apps:start` and `apps:end` markers is rewritten.

Usage: docs-applications.py [--check]
  --check  exit non-zero if the page is out of date or an app has no purpose
"""

import re
import sys
from pathlib import Path

import warnings

from ruamel.yaml import YAML
from ruamel.yaml.error import ReusedAnchorWarning, YAMLError

ROOT = Path(__file__).resolve().parent.parent
APPS = ROOT / "kubernetes" / "apps"
PAGE = ROOT / "docs" / "kubernetes" / "applications.md"
REPO_TREE = "https://github.com/bykaj/home-ops/tree/main/kubernetes/apps"
START, END = "<!-- apps:start -->", "<!-- apps:end -->"
TODO = "TODO"

# Platform: what runs, connects, secures, stores, backs up, upgrades or
# observes the cluster, plus shared backing services. Workloads: apps used for
# their own sake. Every namespace must be in exactly one of these.
PLATFORM = {
    "actions-runner-system",
    "cert-manager",
    "database",
    "external-secrets",
    "flux-system",
    "kube-system",
    "network",
    "observability",
    "rook-ceph",
    "security",
    "system",
    "system-upgrade",
}
WORKLOADS = {"ai", "default", "development", "downloads", "media"}

# Component path (relative to kubernetes/components) -> (label, link)
COMPONENTS = {
    "dragonfly": ("dragonfly", "components.md#dragonfly"),
    "dragonfly/authentication": ("dragonfly", "components.md#dragonfly"),
    "gpu": ("gpu", "components.md#gpu"),
    "kopiur/backup": ("backup", "components.md#kopiurbackup"),
    "postgres": ("postgres", "components.md#postgres"),
    "zeroscaler/nfs": ("scale-to-zero", "components.md#zeroscalernfs"),
}

GATEWAYS = {"envoy-external": "external", "envoy-internal": "internal"}


# Reusing an anchor name is valid YAML 1.2 and common in this repo
warnings.simplefilter("ignore", ReusedAnchorWarning)
yaml = YAML(typ="safe", pure=True)
# A bare `=` (e.g. AlertmanagerConfig matchType) resolves to the YAML 1.1 value tag
yaml.constructor.add_constructor("tag:yaml.org,2002:value", lambda c, node: c.construct_scalar(node))
# Ignore custom tags such as authentik blueprint `!Find`
yaml.constructor.add_multi_constructor("!", lambda c, suffix, node: None)


def load_docs(path: Path) -> list:
    try:
        return [d for d in yaml.load_all(path.read_text()) if d]
    except YAMLError as e:
        sys.exit(f"error: cannot parse {path.relative_to(ROOT)}: {e}")


def walk(node):
    """Yield every mapping in a YAML tree."""
    if isinstance(node, dict):
        yield node
        for v in node.values():
            yield from walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v)


def is_redirect_only(route: dict) -> bool:
    rules = route.get("rules") or []
    return bool(rules) and all(
        not r.get("backendRefs")
        and any(f.get("type") == "RequestRedirect" for f in r.get("filters") or [])
        for r in rules
    )


def exposure(app_dir: Path) -> str:
    found = set()
    for path in app_dir.rglob("*.yaml"):
        # Config files (often templated, not valid YAML) never carry routes
        if path.name == "ks.yaml" or "parentRefs" not in path.read_text():
            continue
        for doc in load_docs(path):
            for m in walk(doc):
                refs = m.get("parentRefs")
                if not isinstance(refs, list) or is_redirect_only(m):
                    continue
                for ref in refs:
                    if isinstance(ref, dict) and ref.get("name") in GATEWAYS:
                        found.add(GATEWAYS[ref["name"]])
    for level in ("external", "internal"):
        if level in found:
            return level
    return "—"


def uses(app_dir: Path) -> str:
    labels = {}
    for doc in load_docs(app_dir / "ks.yaml"):
        for comp in (doc.get("spec") or {}).get("components") or []:
            name = comp.split("components/", 1)[-1]
            if name not in COMPONENTS:
                sys.exit(f"error: {app_dir.relative_to(ROOT)} uses unknown component {name!r}; add it to COMPONENTS")
            label, link = COMPONENTS[name]
            labels[label] = f"[{label}]({link})"
    return ", ".join(labels[k] for k in sorted(labels)) or "—"


def discover():
    """Return ({ns: [app]}, {ns: [app]}) for enabled and disabled apps."""
    enabled, disabled = {}, {}
    for ns_dir in sorted(p for p in APPS.iterdir() if p.is_dir()):
        ns = ns_dir.name
        if ns not in PLATFORM | WORKLOADS:
            sys.exit(f"error: namespace {ns!r} is in neither PLATFORM nor WORKLOADS")
        text = (ns_dir / "kustomization.yaml").read_text()
        for commented, app in re.findall(r"^\s*(#\s*)?-\s*\./([^/]+)/ks\.yaml\s*$", text, re.M):
            (disabled if commented else enabled).setdefault(ns, []).append(app)
        listed = set(enabled.get(ns, []) + disabled.get(ns, []))
        for app_dir in ns_dir.iterdir():
            if (app_dir / "ks.yaml").exists() and app_dir.name not in listed:
                sys.exit(f"error: {app_dir.relative_to(ROOT)} is not listed in {ns}/kustomization.yaml")
    return enabled, disabled


def existing_rows(text: str) -> dict:
    """Read Purpose and Upstream back from the current tables."""
    rows = {}
    pattern = re.compile(r"^\| \[[^\]]+\]\(" + re.escape(REPO_TREE) + r"/([^/]+)/([^)/]+)\) \|(.*)\|$", re.M)
    for ns, app, rest in pattern.findall(text):
        cells = [c.strip() for c in rest.split(" | ")]
        rows[(ns, app)] = {"purpose": cells[0], "upstream": cells[-1] if len(cells) == 4 else "—"}
    return rows


def render(enabled, disabled, rows) -> tuple[str, list]:
    missing = []
    out = []
    for title, group in (("Platform", PLATFORM), ("Workloads", WORKLOADS)):
        out += [f"## {title}", ""]
        for ns in sorted(n for n in enabled if n in group):
            out += [
                f"### `{ns}`",
                "",
                "| App | Purpose | Exposure | Uses | Upstream |",
                "| --- | --- | --- | --- | --- |",
            ]
            for app in sorted(enabled[ns]):
                app_dir = APPS / ns / app
                row = rows.get((ns, app), {"purpose": TODO, "upstream": "—"})
                if row["purpose"] in ("", TODO):
                    missing.append(f"{ns}/{app}")
                out.append(
                    f"| [{app}]({REPO_TREE}/{ns}/{app}) | {row['purpose'] or TODO} "
                    f"| {exposure(app_dir)} | {uses(app_dir)} | {row['upstream']} |"
                )
            out.append("")
    out += [
        "## Disabled",
        "",
        "Manifests kept in the repository but commented out of their namespace",
        "`kustomization.yaml`:",
        "",
        "| Namespace | Apps |",
        "| --- | --- |",
    ]
    for ns in sorted(disabled):
        links = ", ".join(f"[{a}]({REPO_TREE}/{ns}/{a})" for a in sorted(disabled[ns]))
        out.append(f"| `{ns}` | {links} |")
    return "\n".join(out), missing


def main() -> int:
    check = "--check" in sys.argv[1:]
    text = PAGE.read_text()
    if START not in text or END not in text:
        sys.exit(f"error: {PAGE.relative_to(ROOT)} has no {START} / {END} markers")
    head, rest = text.split(START, 1)
    body, tail = rest.split(END, 1)

    enabled, disabled = discover()
    generated, missing = render(enabled, disabled, existing_rows(body))
    new = f"{head}{START}\n\n{generated}\n\n{END}{tail}"

    rc = 0
    if missing:
        print(f"apps without a purpose in {PAGE.relative_to(ROOT)}: {', '.join(missing)}", file=sys.stderr)
        rc = 1
    if new != text:
        if check:
            print(f"{PAGE.relative_to(ROOT)} is out of date; run `just docs-apps`", file=sys.stderr)
            return 1
        PAGE.write_text(new)
        print(f"updated {PAGE.relative_to(ROOT)}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
