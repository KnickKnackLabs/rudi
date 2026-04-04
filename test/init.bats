#!/usr/bin/env bats
# Tests for rudi init and assign — key creation and pattern routing.

load helpers

@test "init creates default and named key directories" {
  create_test_repo "test-repo"
  local fpr
  fpr=$(create_test_user "ada")

  rudi init --user "$fpr" alpha
  [ $? -eq 0 ]

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/default" ]
  [ -f "$RUDI_TARGET/.git/git-crypt/keys/alpha" ]
}

@test "init with multiple named keys" {
  create_test_repo "test-repo"
  local fpr
  fpr=$(create_test_user "ada")

  rudi init --user "$fpr" alpha beta gamma

  [ -d "$RUDI_TARGET/.git-crypt/keys/default" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/alpha" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/beta" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/gamma" ]
}

@test "init fails without --user" {
  create_test_repo "test-repo"

  run rudi init
  [ "$status" -ne 0 ]
  [[ "$output" == *"--user"* ]]
}

@test "init --no-user skips user requirement" {
  create_test_repo "test-repo"

  run rudi init --no-user
  [ "$status" -eq 0 ]
  [ -d "$RUDI_TARGET/.git/git-crypt" ]
}

@test "init is idempotent on already-initialized repo" {
  create_test_repo "test-repo"
  local fpr
  fpr=$(create_test_user "ada")
  rudi init --user "$fpr" alpha

  # Running init again should succeed, not error
  run rudi init --user "$fpr" alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
}

@test "add-key adds a named key to existing repo" {
  create_test_repo "test-repo"
  local fpr
  fpr=$(create_test_user "ada")
  rudi init --user "$fpr" alpha

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/default" ]
  [ -f "$RUDI_TARGET/.git/git-crypt/keys/alpha" ]
  [ ! -f "$RUDI_TARGET/.git/git-crypt/keys/beta" ]

  rudi add-key beta

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/beta" ]
}

@test "assign routes patterns to correct keys" {
  create_test_repo "test-repo"
  local fpr
  fpr=$(create_test_user "ada")
  rudi init --user "$fpr" alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  grep -q 'filter=git-crypt diff=git-crypt' "$RUDI_TARGET/.gitattributes"
  grep -q 'filter=git-crypt-alpha diff=git-crypt-alpha' "$RUDI_TARGET/.gitattributes"
}

@test "assign stages .gitattributes" {
  create_test_repo "test-repo"
  local fpr
  fpr=$(create_test_user "ada")
  rudi init --user "$fpr"

  rudi assign "notes/**"

  # .gitattributes should be staged
  run git -C "$RUDI_TARGET" diff --cached --name-only
  [[ "$output" == *".gitattributes"* ]]
}

@test "assign is idempotent" {
  create_test_repo "test-repo"
  local fpr
  fpr=$(create_test_user "ada")
  rudi init --user "$fpr"

  rudi assign "notes/**"
  rudi assign "notes/**"

  # Pattern should appear exactly once
  local count
  count=$(grep -c 'notes/\*\*' "$RUDI_TARGET/.gitattributes")
  [ "$count" -eq 1 ]
}
