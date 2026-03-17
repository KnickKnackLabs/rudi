#!/usr/bin/env bats
# Tests for remove-user and rotate-key — revoking access.

load helpers

@test "remove-user deletes gpg file from key directory" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  run_rudi add-user "$ada_fpr" --key alpha
  run_rudi add-user "$bob_fpr" --key alpha

  [ -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$bob_fpr.gpg" ]

  run_rudi remove-user "$bob_fpr" --key alpha

  [ ! -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$bob_fpr.gpg" ]
  # ada's key should still be there
  [ -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$ada_fpr.gpg" ]
}

@test "remove-user creates a commit" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  run_rudi add-user "$ada_fpr" --key alpha

  local before after
  before=$(git -C "$RUDI_TARGET" rev-list --count HEAD)

  run_rudi remove-user "$ada_fpr" --key alpha

  after=$(git -C "$RUDI_TARGET" rev-list --count HEAD)
  [ "$after" -gt "$before" ]
}

@test "remove-user fails for nonexistent fingerprint" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  run_rudi add-user "$ada_fpr" --key alpha

  run run_rudi remove-user "0000000000000000000000000000000000000000" --key alpha
  [ "$status" -ne 0 ]
}

@test "remove-user fails for nonexistent key" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  run_rudi add-user "$ada_fpr" --key alpha

  run run_rudi remove-user "$ada_fpr" --key nonexistent
  [ "$status" -ne 0 ]
}

@test "removed user cannot decrypt on fresh clone" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  # Both get alpha key
  run_rudi add-user "$ada_fpr"
  run_rudi add-user "$ada_fpr" --key alpha
  run_rudi add-user "$bob_fpr" --key alpha

  run_rudi assign "notes/**"
  run_rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Sensitive content"
  commit_file "notes/private.md" "Default-key content"

  # Remove bob
  run_rudi remove-user "$bob_fpr" --key alpha

  # Lock everything
  git -C "$RUDI_TARGET" crypt lock --all

  # bob clones fresh — should fail to decrypt alpha-key files
  local clone="$REPOS_DIR/bob-clone"
  clone_as_user "bob" "$clone"

  # unlock will partially succeed (bob has no keys) or fail entirely
  run git -C "$clone" crypt unlock
  # Whether unlock fails or succeeds, shared.md should stay encrypted
  rudi_is_encrypted "$clone/shared.md"
}

@test "rotate-key generates a new symmetric key" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  run_rudi add-user "$ada_fpr"
  run_rudi add-user "$ada_fpr" --key alpha

  run_rudi assign "notes/**"
  run_rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Content to re-encrypt"
  commit_file "notes/private.md" "Default-key content"

  # Export the old key for comparison
  local old_key="$TEST_DIR/old-alpha.key"
  git -C "$RUDI_TARGET" crypt export-key --key-name alpha "$old_key"

  # Rotate
  run_rudi rotate-key --key alpha

  # Export the new key
  local new_key="$TEST_DIR/new-alpha.key"
  git -C "$RUDI_TARGET" crypt export-key --key-name alpha "$new_key"

  # Keys should be different
  ! cmp -s "$old_key" "$new_key"
}

@test "rotate-key preserves file content" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  run_rudi add-user "$ada_fpr"
  run_rudi add-user "$ada_fpr" --key alpha

  run_rudi assign "notes/**"
  run_rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Important content that must survive rotation"
  commit_file "notes/private.md" "Default-key content"

  run_rudi rotate-key --key alpha

  # Content should be preserved
  rudi_is_plaintext "$RUDI_TARGET/shared.md"
  grep -q "Important content that must survive rotation" "$RUDI_TARGET/shared.md"

  # Default-key files should be unaffected
  rudi_is_plaintext "$RUDI_TARGET/notes/private.md"
  grep -q "Default-key content" "$RUDI_TARGET/notes/private.md"
}

@test "rotate-key re-adds remaining collaborators" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  run_rudi add-user "$ada_fpr"
  run_rudi add-user "$ada_fpr" --key alpha
  run_rudi add-user "$bob_fpr" --key alpha

  run_rudi assign "shared.md" --key alpha
  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Shared content"

  # Remove bob, then rotate
  run_rudi remove-user "$bob_fpr" --key alpha
  run_rudi rotate-key --key alpha

  # ada should still have access (re-added during rotation)
  [ -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$ada_fpr.gpg" ]

  # bob should NOT have access
  [ ! -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$bob_fpr.gpg" ]
}

@test "full offboarding: remove + rotate + verify isolation" {
  create_test_repo "test-repo"
  run_rudi init alpha

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  run_rudi add-user "$ada_fpr"
  run_rudi add-user "$ada_fpr" --key alpha
  run_rudi add-user "$bob_fpr" --key alpha

  run_rudi assign "notes/**"
  run_rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Post-rotation content"
  commit_file "notes/private.md" "Default-key content"

  # Offboard bob: remove + rotate
  run_rudi remove-user "$bob_fpr" --key alpha
  run_rudi rotate-key --key alpha

  # Lock and verify ada can still access
  git -C "$RUDI_TARGET" crypt lock --all

  local ada_clone="$REPOS_DIR/ada-clone"
  clone_as_user "ada" "$ada_clone"
  git -C "$ada_clone" crypt unlock

  rudi_is_plaintext "$ada_clone/shared.md"
  rudi_is_plaintext "$ada_clone/notes/private.md"

  # bob cannot access the rotated key's files
  export GNUPGHOME="$USERS_DIR/bob/g"
  local bob_clone="$REPOS_DIR/bob-clone"
  git clone -q "$RUDI_TARGET" "$bob_clone"
  run git -C "$bob_clone" crypt unlock
  rudi_is_encrypted "$bob_clone/shared.md"
}
