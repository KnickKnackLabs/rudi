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
