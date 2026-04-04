# test/helpers.bash — BATS test fixtures for rudi
# Loaded via `load helpers` in each .bats file

# Tests must be run via `mise run test` (or `rudi test`)
if [ -z "${MISE_CONFIG_ROOT:-}" ]; then
  echo "MISE_CONFIG_ROOT not set — run tests via: mise run test" >&2
  exit 1
fi

source "$MISE_CONFIG_ROOT/lib/common.sh"

setup() {
  # Use a short temp path — gpg-agent's Unix socket has a 104-char limit on macOS.
  # BATS_TEST_TMPDIR paths are too deep and cause "can't connect to gpg-agent" errors.
  export TEST_DIR=$(mktemp -d /tmp/rudi.XXXXXX)

  # Isolated GPG home — never touch the real keyring
  export GNUPGHOME="$TEST_DIR/gpg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"

  # Per-user GPG homes (simulating different people)
  export USERS_DIR="$TEST_DIR/u"
  mkdir -p "$USERS_DIR"

  # Test repos
  export REPOS_DIR="$TEST_DIR/r"
  mkdir -p "$REPOS_DIR"
}

teardown() {
  # Kill gpg-agents to prevent accumulation on macOS
  gpgconf --homedir "$GNUPGHOME" --kill gpg-agent 2>/dev/null || true
  if [ -d "$USERS_DIR" ]; then
    for user_home in "$USERS_DIR"/*/g; do
      [ -d "$user_home" ] && gpgconf --homedir "$user_home" --kill gpg-agent 2>/dev/null || true
    done
  fi
  rm -rf "$TEST_DIR"
}

# rudi() wrapper — calls tasks via mise, just like real usage.
# RUDI_TARGET must be set by the test (the repo rudi operates on).
rudi() {
  if [ -z "${RUDI_TARGET:-}" ]; then
    echo "RUDI_TARGET not set" >&2
    return 1
  fi
  cd "$MISE_CONFIG_ROOT" && CALLER_PWD="$RUDI_TARGET" mise run -q "$@"
}
export -f rudi

# Create a test git repo and set it as the rudi target.
# Args: $1 = repo name (created under REPOS_DIR)
# Sets RUDI_TARGET.
create_test_repo() {
  local name="$1"
  export RUDI_TARGET="$REPOS_DIR/$name"
  mkdir -p "$RUDI_TARGET"
  git -C "$RUDI_TARGET" init -q -b main
  git -C "$RUDI_TARGET" config user.email "rudi@test.local"
  git -C "$RUDI_TARGET" config user.name "rudi-test"
  git -C "$RUDI_TARGET" config commit.gpgsign false
}

# Generate an ephemeral GPG key for a test user.
# Args: $1 = username
# Creates: $USERS_DIR/<username>/gnupg with a GPG key
# Prints: fingerprint
# Side effect: public key imported into $GNUPGHOME
create_test_user() {
  local username="$1"
  local user_gpghome="$USERS_DIR/$username/g"
  mkdir -p "$user_gpghome"
  chmod 700 "$user_gpghome"

  # Generate key (stderr to /dev/null, stdout untouched for subshell capture)
  gpg --homedir "$user_gpghome" --batch --passphrase '' --quick-gen-key \
    "$username <$username@rudi.test>" default default never >/dev/null 2>&1

  # Extract fingerprint
  local fpr
  fpr=$(gpg --homedir "$user_gpghome" --batch --with-colons --list-keys \
    "$username" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')

  if [ -z "$fpr" ]; then
    echo "Error: failed to generate GPG key for $username" >&2
    return 1
  fi

  # Import public key into the main GNUPGHOME so git-crypt can use it
  gpg --homedir "$user_gpghome" --batch --armor --export "$fpr" \
    | gpg --homedir "$GNUPGHOME" --batch --import 2>/dev/null

  echo "$fpr"
}

# Create a file in the target repo, stage, and commit.
# Args: $1 = relative file path, $2 = content
commit_file() {
  local filepath="$1"
  local content="$2"
  mkdir -p "$RUDI_TARGET/$(dirname "$filepath")"
  printf '%s\n' "$content" > "$RUDI_TARGET/$filepath"
  git -C "$RUDI_TARGET" add .
  git -C "$RUDI_TARGET" commit -q -m "Add $filepath"
}

# Simulate cloning a repo as a specific user.
# Args: $1 = username, $2 = destination dir
# Clones RUDI_TARGET, switches GNUPGHOME to user's keyring.
clone_as_user() {
  local username="$1"
  local dest_dir="$2"
  git clone -q "$RUDI_TARGET" "$dest_dir"
  export GNUPGHOME="$USERS_DIR/$username/g"
}
