#!/usr/bin/env bats
# Tests for lock/unlock behavior with multiple keys.

load helpers

# Shared setup: repo with default + alpha keys, one user with both keys,
# files committed under both keys.
setup_multi_key_repo() {
  create_test_repo "test-repo"

  local fpr
  fpr=$(create_test_user "ada")

  rudi init --user "$fpr" alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Alpha-key content"
  commit_file "notes/private.md" "Default-key content"
}

# --- rudi lock/unlock task tests ---

@test "rudi lock locks all keys by default" {
  setup_multi_key_repo

  rudi lock

  rudi_is_encrypted "$RUDI_TARGET/shared.md"
  rudi_is_encrypted "$RUDI_TARGET/notes/private.md"
}

@test "rudi lock --key locks only that key's files" {
  setup_multi_key_repo

  rudi lock --key alpha

  rudi_is_encrypted "$RUDI_TARGET/shared.md"
  rudi_is_plaintext "$RUDI_TARGET/notes/private.md"
}

@test "rudi unlock restores all locked files" {
  setup_multi_key_repo

  rudi lock
  rudi_is_encrypted "$RUDI_TARGET/shared.md"
  rudi_is_encrypted "$RUDI_TARGET/notes/private.md"

  export GNUPGHOME="$USERS_DIR/ada/g"
  rudi unlock

  rudi_is_plaintext "$RUDI_TARGET/shared.md"
  rudi_is_plaintext "$RUDI_TARGET/notes/private.md"
}

@test "rudi unlock after partial lock restores files" {
  setup_multi_key_repo

  rudi lock --key alpha
  rudi_is_encrypted "$RUDI_TARGET/shared.md"

  export GNUPGHOME="$USERS_DIR/ada/g"
  rudi unlock
  rudi_is_plaintext "$RUDI_TARGET/shared.md"
}

# --- raw git-crypt behavior (documenting quirks) ---

@test "git-crypt lock --key-name locks only that key's files" {
  setup_multi_key_repo

  rudi_is_plaintext "$RUDI_TARGET/shared.md"
  rudi_is_plaintext "$RUDI_TARGET/notes/private.md"

  git -C "$RUDI_TARGET" crypt lock --key-name alpha

  rudi_is_encrypted "$RUDI_TARGET/shared.md"
  rudi_is_plaintext "$RUDI_TARGET/notes/private.md"
}

@test "git-crypt lock with no flags locks only default-key files" {
  setup_multi_key_repo

  git -C "$RUDI_TARGET" crypt lock

  # FINDING: bare 'lock' only locks default-key files
  rudi_is_encrypted "$RUDI_TARGET/notes/private.md"
  rudi_is_plaintext "$RUDI_TARGET/shared.md"
}

@test "symmetric key export works per named key" {
  setup_multi_key_repo

  local alpha_key="$TEST_DIR/alpha.key"
  local default_key="$TEST_DIR/default.key"

  git -C "$RUDI_TARGET" crypt export-key --key-name alpha "$alpha_key"
  git -C "$RUDI_TARGET" crypt export-key "$default_key"

  [ -f "$alpha_key" ]
  [ -f "$default_key" ]
  [ -s "$alpha_key" ]
  [ -s "$default_key" ]

  # Keys should be different
  ! cmp -s "$alpha_key" "$default_key"
}

@test "git-crypt status shows files from all keys" {
  setup_multi_key_repo

  local status_output
  status_output=$(git -C "$RUDI_TARGET" crypt status -e 2>&1)

  echo "$status_output" | grep -q "shared.md"
  echo "$status_output" | grep -q "notes/private.md"
}

@test "git-crypt status does not show which key protects which file" {
  setup_multi_key_repo

  # Documenting a limitation: status -e shows no key name info
  local status_output
  status_output=$(git -C "$RUDI_TARGET" crypt status -e 2>&1)

  ! echo "$status_output" | grep -qw "alpha"
}
