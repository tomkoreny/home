#!/usr/bin/env python3
"""Move hand-pinned versions to upstream's latest release.

`nix flake update` only moves inputs that track a branch. Anything pinned to a
release (a version string plus a fixed-output hash, or a tag in a flake URL)
stays put until someone notices, which is how Helium sat seven months behind.
This script bumps those pins in place; the workflow validates the result and
reverts the bumps if they break evaluation.

Policies:
  auto        always follow the latest release
  same-major  follow automatically within the current major version; a new
              major opens an issue instead, because it may need real changes
  manual      never bump; open an issue when a new release appears

Rolling downloads have no version: upstream replaces the file behind a fixed
URL, which invalidates the pinned hash. They are re-hashed on every run and are
never reverted, because the old content can no longer be downloaded.
`--rolling` refreshes only those; revert-pin-bumps.sh uses it to re-apply them
after restoring the files a failed bump touched.

Writes one line per bumped pin to the file named by $BUMP_SUMMARY, and one line
per refreshed rolling download to $ROLLING_SUMMARY.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


@dataclass
class Source:
    """A fixed-output download whose hash follows the version."""

    marker: str  # unique substring of the `url = "...";` line in the file
    url: str  # concrete URL with {version} placeholder


@dataclass
class Pin:
    name: str
    policy: str
    latest: callable
    # file -> regex whose group 1 is the pinned version (first one is canonical)
    versions: dict[str, str]
    sources: dict[str, list[Source]] = field(default_factory=dict)


@dataclass
class Rolling:
    """A fixed-output download whose URL stays put while its content changes."""

    name: str
    path: str
    url: str  # exactly as written on the `url = "...";` line in the file


def github_latest(repo: str):
    def fetch() -> str:
        tag = subprocess.run(
            ["gh", "api", f"repos/{repo}/releases/latest", "--jq", ".tag_name"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        return tag.removeprefix("v")
    return fetch


def github_latest_tag(repo: str):
    """For projects that push version tags without publishing GitHub releases."""
    def fetch() -> str:
        tags = subprocess.run(
            ["gh", "api", f"repos/{repo}/tags?per_page=100", "--jq", ".[].name"],
            check=True, capture_output=True, text=True,
        ).stdout.split()
        versions = [tag.removeprefix("v") for tag in tags if re.fullmatch(r"v?\d+(\.\d+)*", tag)]
        if not versions:
            raise RuntimeError(f"{repo} has no plain version tags")
        return max(versions, key=lambda v: [int(n) for n in v.split(".")])
    return fetch


def github_latest_prefixed(repo: str, prefix: str):
    """For monorepos whose releases/latest may belong to a different product."""
    def fetch() -> str:
        tags = subprocess.run(
            ["gh", "api", f"repos/{repo}/releases?per_page=100", "--jq",
             ".[] | select(.draft == false and .prerelease == false) | .tag_name"],
            check=True, capture_output=True, text=True,
        ).stdout.split()
        versions = [tag.removeprefix(prefix) for tag in tags if re.fullmatch(rf"{re.escape(prefix)}\d+(\.\d+)*", tag)]
        if not versions:
            raise RuntimeError(f"{repo} has no stable {prefix} releases")
        return max(versions, key=lambda v: [int(n) for n in v.split(".")])
    return fetch


def betterbird_latest() -> str:
    request = urllib.request.Request(
        "https://www.betterbird.eu/downloads/", headers={"User-Agent": "tomkoreny-home-ci"}
    )
    page = urllib.request.urlopen(request, timeout=60).read().decode()
    builds = set(re.findall(r"betterbird-(\d+\.\d+\.\d+esr-bb\d+)\.en-US\.linux-x86_64\.tar\.xz", page))
    if not builds:
        raise RuntimeError("no Betterbird Linux build found on the downloads page")
    return max(builds, key=lambda v: [int(n) for n in re.findall(r"\d+", v)])


def moshi_hook_latest() -> str:
    # moshi-hook has no public repository; its installer resolves this file.
    request = urllib.request.Request(
        "https://cdn.getmoshi.app/hook/latest/version.txt", headers={"User-Agent": "tomkoreny-home-ci"}
    )
    return urllib.request.urlopen(request, timeout=60).read().decode().strip().removeprefix("v")


def flake_tag(repo: str, prefix: str = "v") -> str:
    return rf'url = "github:{re.escape(repo)}/{prefix}([^"]+)"'


PINS = [
    Pin(
        "helium", "auto", github_latest("imputnet/helium-linux"),
        {"modules/home/helium/default.nix": r'^  version = "([^"]+)";'},
        {"modules/home/helium/default.nix": [Source(
            "helium-linux/releases/download",
            "https://github.com/imputnet/helium-linux/releases/download/{version}/helium-{version}-x86_64.AppImage",
        )]},
    ),
    # Patched at build time (modules/home/helium/default.nix): a new major may
    # move the service worker internals the managed-style import relies on.
    Pin(
        "stylus", "same-major", github_latest("openstyles/stylus"),
        {"modules/home/helium/default.nix": r'^  stylusVersion = "([^"]+)";'},
        {"modules/home/helium/default.nix": [Source(
            "openstyles/stylus/releases/download",
            "https://github.com/openstyles/stylus/releases/download/v{version}/stylus-chrome-mv3-v{version}-id.zip",
        )]},
    ),
    Pin(
        "betterbird", "same-major", betterbird_latest,
        {"modules/home/betterbird/package.nix": r'^  version = "([^"]+)";'},
        {"modules/home/betterbird/package.nix": [
            Source("LinuxArchive", "https://www.betterbird.eu/downloads/LinuxArchive/betterbird-{version}.en-US.linux-x86_64.tar.xz"),
            Source("MacDiskImage", "https://www.betterbird.eu/downloads/MacDiskImage/betterbird-{version}.en-US.mac-arm64.dmg"),
        ]},
    ),
    Pin(
        "orca-ide", "auto", github_latest("stablyai/orca"),
        {"homes/x86_64-linux/tom@nixos/orca.nix": r'^  version = "([^"]+)";'},
        {"homes/x86_64-linux/tom@nixos/orca.nix": [Source(
            "stablyai/orca/releases/download",
            "https://github.com/stablyai/orca/releases/download/v{version}/orca-linux.AppImage",
        )]},
    ),
    Pin(
        "komai", "auto", github_latest("etkecc/komai"),
        {"modules/home/komai/default.nix": r'^  version = "([^"]+)";'},
        {"modules/home/komai/default.nix": [
            Source("x86_64.AppImage", "https://github.com/etkecc/komai/releases/download/v{version}/komai-{version}-x86_64.AppImage"),
            Source("macos-arm64.dmg", "https://github.com/etkecc/komai/releases/download/v{version}/komai-{version}-macos-arm64.dmg"),
        ]},
    ),
    Pin(
        "mtplx", "same-major", github_latest("youssofal/MTPLX"),
        {"modules/home/mtplx/package.nix": r'^  version = "([^"]+)";'},
        {"modules/home/mtplx/package.nix": [Source(
            "MTPLX/releases/download",
            "https://github.com/youssofal/MTPLX/releases/download/v{version}/MTPLX-{version}.dmg",
        )]},
    ),
    Pin(
        "moshi-hook", "auto", moshi_hook_latest,
        {"modules/home/moshi-hook/package.nix": r'^  version = "([^"]+)";'},
        {"modules/home/moshi-hook/package.nix": [Source(
            "cdn.getmoshi.app/hook",
            "https://cdn.getmoshi.app/hook/v{version}/moshi-hook_Linux_x86_64.tar.gz",
        )]},
    ),
    Pin("herdr", "auto", github_latest("herdrdev/herdr"), {"flake.nix": flake_tag("herdrdev/herdr")}),
    # Homebrew's CLI must stay at least as new as the hourly-updated taps.
    Pin("brew", "same-major", github_latest("Homebrew/brew"), {"flake.nix": flake_tag("Homebrew/brew", "")}),
    # Boot-critical Secure Boot tooling: always a human decision.
    Pin("lanzaboote", "manual", github_latest("nix-community/lanzaboote"), {"flake.nix": flake_tag("nix-community/lanzaboote")}),
    Pin(
        "jellyfin-mpv-shim", "same-major", github_latest("jellyfin/jellyfin-mpv-shim"),
        {
            "flake.nix": flake_tag("jellyfin/jellyfin-mpv-shim"),
            "homes/x86_64-linux/tom@nixos/default.nix": r'jellyfin-mpv-shim\.overridePythonAttrs \(old: \{\n    version = "([^"]+)";',
        },
    ),
    Pin(
        "jellyfin-apiclient-python", "same-major", github_latest_tag("jellyfin/jellyfin-apiclient-python"),
        {
            "flake.nix": flake_tag("jellyfin/jellyfin-apiclient-python"),
            "homes/x86_64-linux/tom@nixos/default.nix": r'jellyfin-apiclient-python\.overridePythonAttrs \(_: \{\n    version = "([^"]+)";',
        },
    ),
    Pin(
        "python-mpv-jsonipc", "same-major", github_latest("iwalton3/python-mpv-jsonipc"),
        {
            "flake.nix": flake_tag("iwalton3/python-mpv-jsonipc"),
            "homes/x86_64-linux/tom@nixos/default.nix": r'python-mpv-jsonipc\.overridePythonAttrs \(_: \{\n    version = "([^"]+)";',
        },
    ),
    Pin("default-shader-pack", "same-major", github_latest("iwalton3/default-shader-pack"), {"flake.nix": flake_tag("iwalton3/default-shader-pack")}),
]

# Catppuccin regenerates this export in place under a rolling release tag. The
# Helium module's generator rejects an export that lost a selected style, and
# build-moving.sh builds helium-browser, so a bad regeneration fails CI.
ROLLING = [
    Rolling(
        "catppuccin-userstyles-export", "modules/home/helium/default.nix",
        "https://github.com/catppuccin/userstyles/releases/download/all-userstyles-export/import.json",
    ),
]


def major(version: str) -> int:
    return int(re.match(r"\d+", version).group())


def prefetch(url: str) -> str:
    result = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", url],
        check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout)["hash"]


def replace_version(text: str, pattern: str, new: str, path: str) -> str:
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise RuntimeError(f"{path}: pattern {pattern!r} no longer matches")
    return text[: match.start(1)] + new + text[match.end(1):]


def hash_pattern(marker: str) -> str:
    return rf'(url = "[^"\n]*{re.escape(marker)}[^"\n]*";\n\s*hash = ")([^"]+)(";)'


def replace_hash(text: str, marker: str, new_hash: str, path: str) -> str:
    updated, count = re.subn(hash_pattern(marker), lambda m: m.group(1) + new_hash + m.group(3), text)
    if count != 1:
        raise RuntimeError(f"{path}: expected one url/hash pair for {marker!r}, found {count}")
    return updated


def open_issue(title: str, body: str) -> None:
    existing = subprocess.run(
        ["gh", "issue", "list", "--state", "open", "--search", f'"{title}" in:title', "--json", "title"],
        check=True, capture_output=True, text=True,
    ).stdout
    if any(issue["title"] == title for issue in json.loads(existing)):
        return
    subprocess.run(["gh", "issue", "create", "--title", title, "--body", body], check=True)


def bump(pin: Pin) -> str | None:
    first_path, first_pattern = next(iter(pin.versions.items()))
    current_match = re.search(first_pattern, (ROOT / first_path).read_text(), re.MULTILINE)
    if not current_match:
        raise RuntimeError(f"{first_path}: pattern {first_pattern!r} no longer matches")
    current = current_match.group(1)
    latest = pin.latest()
    if not re.match(r"\d", latest):
        raise RuntimeError(f"unexpected upstream version {latest!r}")
    if latest == current:
        return None
    if pin.policy == "manual" or (pin.policy == "same-major" and major(latest) != major(current)):
        open_issue(
            f"Update pinned {pin.name} to {latest}",
            f"`{pin.name}` is pinned to `{current}`; upstream's latest release is `{latest}`.\n\n"
            f"Its policy is `{pin.policy}`, so the scheduled update does not move it automatically. "
            f"Pinned in: {', '.join(f'`{path}`' for path in pin.versions)}.",
        )
        return None

    edits: dict[str, str] = {}
    for path, pattern in pin.versions.items():
        edits[path] = replace_version(edits.get(path) or (ROOT / path).read_text(), pattern, latest, path)
    for path, sources in pin.sources.items():
        for source in sources:
            new_hash = prefetch(source.url.format(version=latest))
            edits[path] = replace_hash(edits.get(path) or (ROOT / path).read_text(), source.marker, new_hash, path)
    for path, text in edits.items():
        (ROOT / path).write_text(text)
    return f"{pin.name} {current} -> {latest}"


def refresh(download: Rolling) -> str | None:
    text = (ROOT / download.path).read_text()
    match = re.search(hash_pattern(download.url), text)
    if not match:
        raise RuntimeError(f"{download.path}: no url/hash pair for {download.url!r}")
    current = match.group(2)
    latest = prefetch(download.url)
    if latest == current:
        return None
    (ROOT / download.path).write_text(replace_hash(text, download.url, latest, download.path))
    return f"{download.name} {current} -> {latest}"


def check_all(items: list, check, summary_variable: str) -> None:
    changed, failed = [], []
    for item in items:
        try:
            result = check(item)
        except Exception as error:  # one broken upstream must not block the rest
            print(f"::warning::{item.name}: {error}", file=sys.stderr)
            open_issue(
                f"Pin check failing for {item.name}",
                f"The scheduled update could not check or bump `{item.name}`:\n\n```\n{error}\n```",
            )
            failed.append(item.name)
            continue
        if result:
            print(result)
            changed.append(result)
    summary = os.environ.get(summary_variable)
    if summary:
        Path(summary).write_text("".join(f"{line}\n" for line in changed))
    if failed:
        print(f"::warning::could not check: {', '.join(failed)}", file=sys.stderr)


def main(args: list[str]) -> int:
    if args not in ([], ["--rolling"]):
        print("usage: bump-pins.py [--rolling]", file=sys.stderr)
        return 2
    if not args:
        check_all(PINS, bump, "BUMP_SUMMARY")
    check_all(ROLLING, refresh, "ROLLING_SUMMARY")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
