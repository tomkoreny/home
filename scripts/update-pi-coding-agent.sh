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

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Build a package-lock.json from the published tarball. The package does not
# ship a lockfile, but buildNpmPackage needs one for reproducible npm deps.
npm pack --silent "$PACKAGE@$VERSION" --pack-destination "$TMPDIR" >/dev/null
mkdir "$TMPDIR/pkg"
tar -xzf "$TMPDIR"/*.tgz -C "$TMPDIR/pkg" --strip-components=1
(
  cd "$TMPDIR/pkg"
  npm install --package-lock-only --ignore-scripts --include=dev >/dev/null
)
cp "$TMPDIR/pkg/package-lock.json" "$LOCK_FILE"

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
