#!/usr/bin/env bats
# Tests for rudi init and assign — key creation and pattern routing.

load helpers

@test "init creates default and named key directories" {
  create_test_repo "test-repo"

  run_rudi init alpha
  [ $? -eq 0 ]

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/default" ]
  [ -f "$RUDI_TARGET/.git/git-crypt/keys/alpha" ]
}

@test "init with multiple named keys" {
  create_test_repo "test-repo"
  run_rudi init alpha beta gamma

  local fpr
  fpr=$(create_test_user "ada")
  run_rudi add-user "$fpr"
  run_rudi add-user "$fpr" --key alpha
  run_rudi add-user "$fpr" --key beta
  run_rudi add-user "$fpr" --key gamma

  [ -d "$RUDI_TARGET/.git-crypt/keys/default" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/alpha" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/beta" ]
  [ -d "$RUDI_TARGET/.git-crypt/keys/gamma" ]
}

@test "add-key adds a named key to existing repo" {
  create_test_repo "test-repo"
  run_rudi init alpha

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/default" ]
  [ -f "$RUDI_TARGET/.git/git-crypt/keys/alpha" ]
  [ ! -f "$RUDI_TARGET/.git/git-crypt/keys/beta" ]

  run_rudi add-key beta

  [ -f "$RUDI_TARGET/.git/git-crypt/keys/beta" ]
}

@test "assign routes patterns to correct keys" {
  create_test_repo "test-repo"
  run_rudi init alpha

  run_rudi assign "notes/**"
  run_rudi assign "shared.md" --key alpha

  grep -q 'filter=git-crypt diff=git-crypt' "$RUDI_TARGET/.gitattributes"
  grep -q 'filter=git-crypt-alpha diff=git-crypt-alpha' "$RUDI_TARGET/.gitattributes"
}
