#!/usr/bin/env bats
# Tests for rudi init and assign — key creation and pattern routing.

load helpers

@test "init creates default and named key directories" {
  create_test_repo "test-repo"

  rudi init alpha
  [ $? -eq 0 ]

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/default" ]
  [ -f "$RUDI_TARGET/.git/git-crypt/keys/alpha" ]
}

@test "init with multiple named keys" {
  create_test_repo "test-repo"
  rudi init alpha beta gamma

  local fpr
  fpr=$(create_test_user "ada")
  rudi add-user "$fpr"
  rudi add-user "$fpr" --key alpha
  rudi add-user "$fpr" --key beta
  rudi add-user "$fpr" --key gamma

  [ -d "$RUDI_TARGET/.git-crypt/keys/default" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/alpha" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/beta" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/gamma" ]
}

@test "init is idempotent on already-initialized repo" {
  create_test_repo "test-repo"
  rudi init alpha

  # Running init again should succeed, not error
  run rudi init alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
}

@test "add-key adds a named key to existing repo" {
  create_test_repo "test-repo"
  rudi init alpha

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/default" ]
  [ -f "$RUDI_TARGET/.git/git-crypt/keys/alpha" ]
  [ ! -f "$RUDI_TARGET/.git/git-crypt/keys/beta" ]

  rudi add-key beta

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/beta" ]
}

@test "assign routes patterns to correct keys" {
  create_test_repo "test-repo"
  rudi init alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha

  grep -q 'filter=git-crypt diff=git-crypt' "$RUDI_TARGET/.gitattributes"
  grep -q 'filter=git-crypt-alpha diff=git-crypt-alpha' "$RUDI_TARGET/.gitattributes"
}
