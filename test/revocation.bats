#!/usr/bin/env bats
# Tests for remove-user and rotate-key — revoking access.

load helpers

@test "remove-user deletes gpg file from key directory" {
  create_test_repo "test-repo"

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  rudi init --user "$ada_fpr" alpha
  rudi add-user "$bob_fpr" --key alpha

  [ -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$bob_fpr.gpg" ]

  rudi remove-user "$bob_fpr" --key alpha

  [ ! -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$bob_fpr.gpg" ]
  [ -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$ada_fpr.gpg" ]
}

@test "remove-user creates a commit" {
  create_test_repo "test-repo"

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")
  rudi init --user "$ada_fpr" alpha
  rudi add-user "$bob_fpr" --key alpha

  local before after
  before=$(git -C "$RUDI_TARGET" rev-list --count HEAD)

  rudi remove-user "$bob_fpr" --key alpha

  after=$(git -C "$RUDI_TARGET" rev-list --count HEAD)
  [ "$after" -gt "$before" ]
}

@test "remove-user fails for nonexistent fingerprint" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  run rudi remove-user "0000000000000000000000000000000000000000" --key alpha
  [ "$status" -ne 0 ]
}

@test "remove-user fails for nonexistent key" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  run rudi remove-user "$ada_fpr" --key nonexistent
  [ "$status" -ne 0 ]
}

@test "removed user cannot decrypt on fresh clone" {
  create_test_repo "test-repo"

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  rudi init --user "$ada_fpr" alpha
  rudi add-user "$bob_fpr" --key alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Sensitive content"
  commit_file "notes/private.md" "Default-key content"

  rudi remove-user "$bob_fpr" --key alpha

  git -C "$RUDI_TARGET" crypt lock --all

  local clone="$REPOS_DIR/bob-clone"
  clone_as_user "bob" "$clone"

  run git -C "$clone" crypt unlock
  rudi_is_encrypted "$clone/shared.md"
}

@test "rotate-key fails when git-crypt lock fails" {
  create_test_repo "test-repo"

  local fpr="0000000000000000000000000000000000000000"
  mkdir -p "$RUDI_TARGET/.git-crypt/keys/alpha/0"
  touch "$RUDI_TARGET/.git-crypt/keys/alpha/0/$fpr.gpg"
  printf 'shared.md filter=git-crypt-alpha diff=git-crypt-alpha\n' > "$RUDI_TARGET/.gitattributes"
  printf 'Sensitive content\n' > "$RUDI_TARGET/shared.md"
  git -C "$RUDI_TARGET" add .gitattributes shared.md .git-crypt/keys/alpha/0/$fpr.gpg

  local real_git mock_git
  real_git=$(command -v git)
  mock_git="$TEST_DIR/git-lock-fails"
  cat > "$mock_git" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "-C" ]; then
  target="\$2"
  shift 2
  if [ "\${1:-}" = "crypt" ] && [ "\${2:-}" = "lock" ]; then
    echo "mock git-crypt lock failure" >&2
    exit 42
  fi
  exec "$real_git" -C "\$target" "\$@"
fi
exec "$real_git" "\$@"
EOF
  chmod +x "$mock_git"

  export GIT="$mock_git"
  run rudi rotate-key --key alpha
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error: git-crypt lock for key 'alpha' failed"* ]]
  [[ "$output" == *"mock git-crypt lock failure"* ]]
}

@test "rotate-key generates a new symmetric key" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Content to re-encrypt"
  commit_file "notes/private.md" "Default-key content"

  local old_key="$TEST_DIR/old-alpha.key"
  git -C "$RUDI_TARGET" crypt export-key --key-name alpha "$old_key"

  rudi rotate-key --key alpha

  local new_key="$TEST_DIR/new-alpha.key"
  git -C "$RUDI_TARGET" crypt export-key --key-name alpha "$new_key"

  ! cmp -s "$old_key" "$new_key"
}

@test "rotate-key preserves file content" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Important content that must survive rotation"
  commit_file "notes/private.md" "Default-key content"

  rudi rotate-key --key alpha

  rudi_is_plaintext "$RUDI_TARGET/shared.md"
  grep -q "Important content that must survive rotation" "$RUDI_TARGET/shared.md"

  rudi_is_plaintext "$RUDI_TARGET/notes/private.md"
  grep -q "Default-key content" "$RUDI_TARGET/notes/private.md"
}

@test "rotate-key re-adds remaining collaborators" {
  create_test_repo "test-repo"

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  rudi init --user "$ada_fpr" alpha
  rudi add-user "$bob_fpr" --key alpha

  rudi assign "shared.md" --key alpha
  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Shared content"

  rudi remove-user "$bob_fpr" --key alpha
  if ! git -C "$RUDI_TARGET" diff --quiet; then
    git -C "$RUDI_TARGET" add .
    git -C "$RUDI_TARGET" commit -q -m "Update generated collaborator manifest"
  fi
  rudi rotate-key --key alpha

  [ -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$ada_fpr.gpg" ]
  [ ! -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$bob_fpr.gpg" ]
}

@test "full offboarding: remove + rotate + verify isolation" {
  create_test_repo "test-repo"

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  rudi init --user "$ada_fpr" alpha
  rudi add-user "$bob_fpr" --key alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Post-rotation content"
  commit_file "notes/private.md" "Default-key content"

  rudi remove-user "$bob_fpr" --key alpha
  rudi rotate-key --key alpha

  git -C "$RUDI_TARGET" crypt lock --all

  local ada_clone="$REPOS_DIR/ada-clone"
  clone_as_user "ada" "$ada_clone"
  git -C "$ada_clone" crypt unlock

  rudi_is_plaintext "$ada_clone/shared.md"
  rudi_is_plaintext "$ada_clone/notes/private.md"

  export GNUPGHOME="$USERS_DIR/bob/g"
  local bob_clone="$REPOS_DIR/bob-clone"
  git clone -q "$RUDI_TARGET" "$bob_clone"
  run git -C "$bob_clone" crypt unlock
  rudi_is_encrypted "$bob_clone/shared.md"
}
