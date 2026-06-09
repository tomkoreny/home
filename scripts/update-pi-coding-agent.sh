#!/usr/bin/env bash
set -euo pipefail

PACKAGE="@earendil-works/pi-coding-agent"
NIX_FILE="modules/home/packages/default.nix"
LOCK_FILE="modules/home/packages/pi-coding-agent-lock.json"

usage() {
  cat <<'EOF'
Usage: scripts/update-pi-coding-agent.sh [version]

Updates the custom pi-coding-agent Nix package to the requested npm version,
or to the latest version if omitted.

Environment:
  BUILD_ATTR   Nix build target used to discover/validate npmDepsHash.
               Defaults to tom@macos on Darwin, tom@nixos elsewhere.

Examples:
  scripts/update-pi-coding-agent.sh
  scripts/update-pi-coding-agent.sh 0.73.1
  BUILD_ATTR='.#homeConfigurations.tom@nixos.activationPackage' scripts/update-pi-coding-agent.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Run from repository root, regardless of caller cwd.
cd "$(git rev-parse --show-toplevel)"

if [[ ! -f "$NIX_FILE" ]]; then
  echo "error: cannot find $NIX_FILE" >&2
  exit 1
fi

if ! command -v npm >/dev/null; then
  echo "error: npm is required" >&2
  exit 1
fi

if ! command -v nix >/dev/null; then
  echo "error: nix is required" >&2
  exit 1
fi

if [[ -z "${BUILD_ATTR:-}" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    BUILD_ATTR='.#homeConfigurations.tom@macos.activationPackage'
  else
    BUILD_ATTR='.#homeConfigurations.tom@nixos.activationPackage'
  fi
fi

WORKDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Use an isolated npm cache so root-owned or corrupt user cache entries do not
# break package-lock generation.
export npm_config_cache="${npm_config_cache:-$WORKDIR/npm-cache}"
mkdir -p "$npm_config_cache"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(npm view "$PACKAGE" version)"
fi

echo "Updating $PACKAGE to $VERSION"

META_JSON="$(npm view "$PACKAGE@$VERSION" version dist.integrity --json)"
INTEGRITY="$(node -e 'const meta = JSON.parse(process.argv[1]); console.log(meta["dist.integrity"] || meta.dist?.integrity || "")' "$META_JSON")"

if [[ -z "$INTEGRITY" ]]; then
  echo "error: could not read npm dist.integrity for $PACKAGE@$VERSION" >&2
  exit 1
fi

# Build or reuse a lockfile from the published tarball. Some pi releases ship
# npm-shrinkwrap.json instead of package-lock.json; buildNpmPackage is happy as
# long as we provide equivalent lock content as package-lock.json in postPatch.
npm pack --silent "$PACKAGE@$VERSION" --pack-destination "$WORKDIR" >/dev/null
mkdir "$WORKDIR/pkg"
tar -xzf "$WORKDIR"/*.tgz -C "$WORKDIR/pkg" --strip-components=1
(
  cd "$WORKDIR/pkg"
  npm install --package-lock-only --ignore-scripts --include=dev >/dev/null
)
if [[ -f "$WORKDIR/pkg/package-lock.json" ]]; then
  cp "$WORKDIR/pkg/package-lock.json" "$LOCK_FILE"
elif [[ -f "$WORKDIR/pkg/npm-shrinkwrap.json" ]]; then
  cp "$WORKDIR/pkg/npm-shrinkwrap.json" "$LOCK_FILE"
else
  echo "error: npm did not produce package-lock.json or npm-shrinkwrap.json" >&2
  exit 1
fi

# Newer pi shrinkwraps can omit integrity for sibling workspace packages even
# though they resolve to npm registry tarballs. Fill those from npm metadata so
# Nix's npm-deps parser can consume the lockfile reproducibly.
node - "$LOCK_FILE" <<'EOF'
const fs = require("fs");
const { execFileSync } = require("child_process");
const [file] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(file, "utf8"));
let changed = false;

function packageNameFromLockPath(lockPath) {
  const marker = "node_modules/";
  const idx = lockPath.lastIndexOf(marker);
  if (idx === -1) return null;
  const parts = lockPath.slice(idx + marker.length).split("/");
  if (parts[0]?.startsWith("@")) return `${parts[0]}/${parts[1]}`;
  return parts[0] || null;
}

for (const [lockPath, entry] of Object.entries(lock.packages || {})) {
  if (!lockPath || entry.integrity || !entry.version || !entry.resolved) continue;
  if (!entry.resolved.startsWith("https://registry.npmjs.org/")) continue;

  const name = packageNameFromLockPath(lockPath);
  if (!name) continue;

  const integrity = execFileSync(
    "npm",
    ["view", `${name}@${entry.version}`, "dist.integrity"],
    { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
  ).trim();

  if (!integrity) {
    console.error(`error: missing npm dist.integrity for ${name}@${entry.version}`);
    process.exit(1);
  }

  entry.integrity = integrity;
  changed = true;
}

if (changed) {
  fs.writeFileSync(file, JSON.stringify(lock, null, 2) + "\n");
}
EOF

# Update the Nix expression and intentionally set a fake npmDepsHash. The first
# nix build prints the real hash, which we paste back below.
node - "$NIX_FILE" "$VERSION" "$INTEGRITY" <<'EOF'
const fs = require("fs");
const [file, version, integrity] = process.argv.slice(2);
let text = fs.readFileSync(file, "utf8");

function replace(regex, replacement, label) {
  if (!regex.test(text)) {
    console.error(`error: failed to find ${label} in ${file}`);
    process.exit(1);
  }
  text = text.replace(regex, replacement);
}

replace(
  /(pname = "pi-coding-agent";\n\s*version = ")[^"]+(";)/,
  `$1${version}$2`,
  "pi-coding-agent version",
);

replace(
  /(url = "https:\/\/registry\.npmjs\.org\/@earendil-works\/pi-coding-agent\/-\/pi-coding-agent-\$\{version\}\.tgz";\n\s*hash = ")[^"]+(";)/,
  `$1${integrity}$2`,
  "pi-coding-agent source hash",
);

replace(
  /npmDepsHash = (?:"[^"]+"|lib\.fakeHash);/,
  "npmDepsHash = lib.fakeHash;",
  "pi-coding-agent npmDepsHash",
);

fs.writeFileSync(file, text);
EOF

echo "Discovering npmDepsHash via: nix build '$BUILD_ATTR' --no-link"
set +e
BUILD_OUTPUT="$(nix build "$BUILD_ATTR" --no-link 2>&1)"
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -eq 0 ]]; then
  echo "warning: nix build unexpectedly succeeded with lib.fakeHash; leaving npmDepsHash unchanged" >&2
  exit 0
fi

NPM_DEPS_HASH="$(printf '%s\n' "$BUILD_OUTPUT" | node -e '
let input = "";
process.stdin.on("data", d => input += d);
process.stdin.on("end", () => {
  const match = input.match(/got:\s+(sha256-[A-Za-z0-9+/=]+)/);
  if (match) console.log(match[1]);
});
')"

if [[ -z "$NPM_DEPS_HASH" ]]; then
  printf '%s\n' "$BUILD_OUTPUT" >&2
  echo "error: could not parse npmDepsHash from nix output" >&2
  exit 1
fi

node - "$NIX_FILE" "$NPM_DEPS_HASH" <<'EOF'
const fs = require("fs");
const [file, hash] = process.argv.slice(2);
let text = fs.readFileSync(file, "utf8");
text = text.replace(/npmDepsHash = lib\.fakeHash;/, `npmDepsHash = "${hash}";`);
fs.writeFileSync(file, text);
EOF

echo "Validating final build via: nix build '$BUILD_ATTR' --no-link"
nix build "$BUILD_ATTR" --no-link

echo "Updated $PACKAGE to $VERSION"
echo "  src.hash    = $INTEGRITY"
echo "  npmDepsHash = $NPM_DEPS_HASH"
