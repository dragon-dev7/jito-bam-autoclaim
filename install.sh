#!/usr/bin/env bash
# Installs jito-bam-autoclaim on a Solana validator (Ubuntu/Debian).
#
#   curl -fsSL https://raw.githubusercontent.com/dragon-dev7/jito-bam-autoclaim/main/install.sh -o install.sh
#   less install.sh          # read it first
#   sudo bash install.sh
#
# What it does:
#   1. clones and builds the official jito-foundation/jito-bam-boost-cli (needs Rust / cargo)
#   2. installs /usr/local/bin/jito-bam-autoclaim
#   3. writes /etc/jito-bam-autoclaim.conf, finding the identity keypair of your running validator
#   4. adds a cron job (every 4 hours) and log rotation
#   5. does a dry run so you can see what it would claim
#
# Options (environment variables):
#   CLI_DIR=/root/jito-bam-boost-cli   reuse an existing checkout instead of /opt/jito-bam-boost-cli
#   RPC_URL=https://...                your RPC (default: public mainnet)
#   SIGNER=/path/identity.json         skip auto-detection
set -euo pipefail

REPO_RAW=https://raw.githubusercontent.com/dragon-dev7/jito-bam-autoclaim/main
CLI_REPO=https://github.com/jito-foundation/jito-bam-boost-cli.git
CLI_DIR=${CLI_DIR:-/opt/jito-bam-boost-cli}
CONF=/etc/jito-bam-autoclaim.conf
BIN=/usr/local/bin/jito-bam-autoclaim
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

say() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root (sudo bash install.sh)"

say "Checking tools"
missing=()
for t in git curl python3 flock; do command -v "$t" >/dev/null || missing+=("$t"); done
if [ ${#missing[@]} -gt 0 ]; then
  say "Installing: ${missing[*]}"
  apt-get update -qq && apt-get install -y -qq git curl python3 util-linux
fi
for p in pkg-config libssl-dev build-essential; do
  dpkg -s "$p" >/dev/null 2>&1 || { say "Installing build dependency $p"; apt-get install -y -qq "$p"; }
done

CARGO=$(command -v cargo || true)
[ -z "$CARGO" ] && [ -x "$HOME/.cargo/bin/cargo" ] && CARGO=$HOME/.cargo/bin/cargo
[ -n "$CARGO" ] || die "Rust is not installed. Install it with: curl https://sh.rustup.rs -sSf | sh   then run this again."

say "Getting jito-bam-boost-cli into $CLI_DIR"
if [ -d "$CLI_DIR/.git" ]; then
  git -C "$CLI_DIR" pull --ff-only
else
  git clone --depth 1 "$CLI_REPO" "$CLI_DIR"
fi

say "Building (release). The first build takes a few minutes."
(cd "$CLI_DIR" && "$CARGO" build --release -p jito-bam-boost-cli)
CLI_BIN=$CLI_DIR/target/release/jito-bam-boost-cli
[ -x "$CLI_BIN" ] || die "build finished but $CLI_BIN is missing"

say "Installing $BIN"
if [ -f "$HERE/jito-bam-autoclaim" ]; then
  install -m 755 "$HERE/jito-bam-autoclaim" "$BIN"
else
  curl -fsSL "$REPO_RAW/jito-bam-autoclaim" -o "$BIN" && chmod 755 "$BIN"
fi

# Find the identity keypair of the running validator (the same logic the script uses)
if [ -z "${SIGNER:-}" ]; then
  for pid in $(pgrep -f 'agave-validator|solana-validator' || true); do
    exe=$(basename "$(readlink -f "/proc/$pid/exe" 2>/dev/null)" 2>/dev/null || true)
    case "$exe" in agave-validator|solana-validator) ;; *) continue ;; esac
    mapfile -d '' args < "/proc/$pid/cmdline"
    for i in "${!args[@]}"; do
      a=${args[$i]}; p=""
      case "$a" in --identity=*) p=${a#--identity=} ;; --identity|-i) p=${args[$((i + 1))]:-} ;; esac
      [ -n "$p" ] || continue
      [[ "$p" == /* ]] || p="$(readlink -f "/proc/$pid/cwd")/$p"
      [ -f "$p" ] && { SIGNER=$p; break 2; }
    done
  done
fi

if [ -f "$CONF" ]; then
  say "Keeping existing $CONF"
else
  [ -n "${SIGNER:-}" ] && say "Identity keypair: $SIGNER" || say "Running validator not found: set SIGNER in $CONF by hand"
  cat > "$CONF" <<EOF
# jito-bam-autoclaim settings
RPC_URL=${RPC_URL:-https://api.mainnet-beta.solana.com}
CLI_BIN=$CLI_BIN
# Identity keypair that receives the boost. Empty = detect from the running validator on every run.
SIGNER=${SIGNER:-}
# Optional Telegram notifications
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
EOF
  chmod 600 "$CONF"
fi

say "Adding cron job and log rotation"
cat > /etc/cron.d/jito-bam-autoclaim <<'EOF'
# Claim Jito BAM Boost rewards every 4 hours (claims stay open 10 epochs)
23 */4 * * * root /usr/local/bin/jito-bam-autoclaim >> /var/log/jito-bam-autoclaim.log 2>&1
EOF
cat > /etc/logrotate.d/jito-bam-autoclaim <<'EOF'
/var/log/jito-bam-autoclaim.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
EOF

say "Dry run: what would be claimed now"
"$BIN" --dry-run || true

cat <<EOF

Done.
  Settings:  $CONF
  Log:       /var/log/jito-bam-autoclaim.log
  Run now:   jito-bam-autoclaim
EOF
