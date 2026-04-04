#!/usr/bin/env bats
# Tests for key-based access control — who can decrypt what.

load helpers

@test "add-user to named key only grants that key" {
  create_test_repo "test-repo"
  rudi init alpha

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  rudi add-user "$ada_fpr"
  rudi add-user "$bob_fpr" --key alpha

  # ada under default only
  [ -f "$RUDI_TARGET/.git-crypt/keys/default/0/$ada_fpr.gpg" ]
  [ ! -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$ada_fpr.gpg" ]

  # bob under alpha only
  [ -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$bob_fpr.gpg" ]
  [ ! -f "$RUDI_TARGET/.git-crypt/keys/default/0/$bob_fpr.gpg" ]
}

@test "user with named key only: decrypts assigned files, not default-key files" {
  create_test_repo "test-repo"
  rudi init alpha

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  rudi add-user "$ada_fpr"
  rudi add-user "$ada_fpr" --key alpha
  rudi add-user "$bob_fpr" --key alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Shared scratchpad"
  commit_file "notes/private.md" "Default-key content"

  git -C "$RUDI_TARGET" crypt lock --all

  local clone="$REPOS_DIR/bob-clone"
  clone_as_user "bob" "$clone"
  git -C "$clone" crypt unlock

  rudi_is_plaintext "$clone/shared.md"
  grep -q "Shared scratchpad" "$clone/shared.md"
  rudi_is_encrypted "$clone/notes/private.md"
}

@test "user with default key only: decrypts default files, not named-key files" {
  create_test_repo "test-repo"
  rudi init alpha

  local ada_fpr cal_fpr
  ada_fpr=$(create_test_user "ada")
  cal_fpr=$(create_test_user "cal")

  rudi add-user "$ada_fpr"
  rudi add-user "$ada_fpr" --key alpha
  rudi add-user "$cal_fpr"

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Shared scratchpad"
  commit_file "notes/private.md" "Default-key content"

  git -C "$RUDI_TARGET" crypt lock --all

  local clone="$REPOS_DIR/cal-clone"
  clone_as_user "cal" "$clone"
  git -C "$clone" crypt unlock

  rudi_is_plaintext "$clone/notes/private.md"
  grep -q "Default-key content" "$clone/notes/private.md"
  rudi_is_encrypted "$clone/shared.md"
}

@test "user with both keys can decrypt everything" {
  create_test_repo "test-repo"
  rudi init alpha

  local ada_fpr
  ada_fpr=$(create_test_user "ada")

  rudi add-user "$ada_fpr"
  rudi add-user "$ada_fpr" --key alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "shared.md" "Shared scratchpad"
  commit_file "notes/private.md" "Default-key content"

  git -C "$RUDI_TARGET" crypt lock --all

  local clone="$REPOS_DIR/ada-clone"
  clone_as_user "ada" "$clone"
  git -C "$clone" crypt unlock

  rudi_is_plaintext "$clone/shared.md"
  rudi_is_plaintext "$clone/notes/private.md"
}

@test "per-user keys isolate files from each other" {
  create_test_repo "test-repo"
  rudi init alpha beta

  local ada_fpr bob_fpr cal_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")
  cal_fpr=$(create_test_user "cal")

  # ada gets all keys, bob gets alpha, cal gets beta
  rudi add-user "$ada_fpr"
  rudi add-user "$ada_fpr" --key alpha
  rudi add-user "$ada_fpr" --key beta
  rudi add-user "$bob_fpr" --key alpha
  rudi add-user "$cal_fpr" --key beta

  rudi assign "notes/**"
  rudi assign "scratch.alpha.md" --key alpha
  rudi assign "scratch.beta.md" --key beta

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "scratch.alpha.md" "Alpha's scratchpad"
  commit_file "scratch.beta.md" "Beta's scratchpad"
  commit_file "notes/shared.md" "Shared notes"

  git -C "$RUDI_TARGET" crypt lock --all

  # bob sees alpha but not beta or default
  local bob_clone="$REPOS_DIR/bob-clone"
  clone_as_user "bob" "$bob_clone"
  git -C "$bob_clone" crypt unlock
  rudi_is_plaintext "$bob_clone/scratch.alpha.md"
  rudi_is_encrypted "$bob_clone/scratch.beta.md"
  rudi_is_encrypted "$bob_clone/notes/shared.md"

  # cal sees beta but not alpha or default
  export GNUPGHOME="$USERS_DIR/cal/g"
  local cal_clone="$REPOS_DIR/cal-clone"
  git clone -q "$RUDI_TARGET" "$cal_clone"
  git -C "$cal_clone" crypt unlock
  rudi_is_plaintext "$cal_clone/scratch.beta.md"
  rudi_is_encrypted "$cal_clone/scratch.alpha.md"
  rudi_is_encrypted "$cal_clone/notes/shared.md"
}

@test "adding a new key and user does not require re-keying" {
  create_test_repo "test-repo"
  rudi init alpha

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  rudi add-user "$ada_fpr"
  rudi add-user "$ada_fpr" --key alpha
  rudi add-user "$bob_fpr" --key alpha

  rudi assign "notes/**"
  rudi assign "scratch.alpha.md" --key alpha

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "scratch.alpha.md" "Alpha's scratchpad"
  commit_file "notes/shared.md" "Shared notes"

  # Add a new key + user after initial setup
  local cal_fpr
  cal_fpr=$(create_test_user "cal")
  rudi add-key beta
  rudi add-user "$cal_fpr" --key beta
  rudi add-user "$ada_fpr" --key beta
  rudi assign "scratch.beta.md" --key beta

  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "scratch.beta.md" "Beta's scratchpad"

  git -C "$RUDI_TARGET" crypt lock --all

  # bob (alpha only) still works — no re-keying needed
  local bob_clone="$REPOS_DIR/bob-clone"
  clone_as_user "bob" "$bob_clone"
  git -C "$bob_clone" crypt unlock
  rudi_is_plaintext "$bob_clone/scratch.alpha.md"
  rudi_is_encrypted "$bob_clone/scratch.beta.md"

  # cal (beta only) can read beta
  export GNUPGHOME="$USERS_DIR/cal/g"
  local cal_clone="$REPOS_DIR/cal-clone"
  git clone -q "$RUDI_TARGET" "$cal_clone"
  git -C "$cal_clone" crypt unlock
  rudi_is_plaintext "$cal_clone/scratch.beta.md"
  rudi_is_encrypted "$cal_clone/scratch.alpha.md"
}

@test "add-user is idempotent for same fingerprint and key" {
  create_test_repo "test-repo"
  rudi init alpha

  local fpr
  fpr=$(create_test_user "ada")
  rudi add-user "$fpr"

  # Count commits before
  local commits_before
  commits_before=$(git -C "$RUDI_TARGET" rev-list --count HEAD)

  # Adding same user again should succeed but not create a new commit
  run rudi add-user "$fpr"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* ]]

  local commits_after
  commits_after=$(git -C "$RUDI_TARGET" rev-list --count HEAD)
  [ "$commits_before" -eq "$commits_after" ]
}

@test "add-user same fingerprint to different key is not idempotent" {
  create_test_repo "test-repo"
  rudi init alpha

  local fpr
  fpr=$(create_test_user "ada")
  rudi add-user "$fpr"

  # Adding to a different key should work
  run rudi add-user "$fpr" --key alpha
  [ "$status" -eq 0 ]
  [[ "$output" != *"already"* ]]

  [ -f "$RUDI_TARGET/.git-crypt/keys/default/0/$fpr.gpg" ]
  [ -f "$RUDI_TARGET/.git-crypt/keys/alpha/0/$fpr.gpg" ]
}
