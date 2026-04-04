#!/usr/bin/env bats
# Tests for COLLABORATORS manifest and key verification.

load helpers

@test "collaborators generates manifest with all users and keys" {
  create_test_repo "test-repo"

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")

  rudi init --user "$ada_fpr" alpha
  rudi add-user "$bob_fpr" --key alpha

  rudi collaborators

  local manifest="$RUDI_TARGET/.git-crypt/COLLABORATORS"
  [ -f "$manifest" ]

  grep -q "$ada_fpr" "$manifest"
  grep -q "$bob_fpr" "$manifest"

  grep -q "Keys:.*default" "$manifest"
  grep -q "Keys:.*alpha" "$manifest"
}

@test "collaborators includes vendored public keys" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  rudi collaborators

  local manifest="$RUDI_TARGET/.git-crypt/COLLABORATORS"

  grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$manifest"
  grep -q "END PGP PUBLIC KEY BLOCK" "$manifest"
}

@test "collaborators shows pattern-to-key mapping in header" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  rudi assign "notes/**"
  rudi assign "shared.md" --key alpha
  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"

  rudi collaborators

  local manifest="$RUDI_TARGET/.git-crypt/COLLABORATORS"

  grep -q "default:.*notes/\*\*" "$manifest"
  grep -q "alpha:.*shared.md" "$manifest"
}

@test "add-user automatically regenerates manifest" {
  create_test_repo "test-repo"

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")
  rudi init --user "$ada_fpr" alpha
  rudi add-user "$bob_fpr" --key alpha

  local manifest="$RUDI_TARGET/.git-crypt/COLLABORATORS"
  [ -f "$manifest" ]
  grep -q "$bob_fpr" "$manifest"
}

@test "remove-user automatically regenerates manifest" {
  create_test_repo "test-repo"

  local ada_fpr bob_fpr
  ada_fpr=$(create_test_user "ada")
  bob_fpr=$(create_test_user "bob")
  rudi init --user "$ada_fpr" alpha
  rudi add-user "$bob_fpr" --key alpha

  local manifest="$RUDI_TARGET/.git-crypt/COLLABORATORS"
  grep -q "$bob_fpr" "$manifest"

  rudi remove-user "$bob_fpr" --key alpha

  ! grep -q "$bob_fpr" "$manifest"
  grep -q "$ada_fpr" "$manifest"
}

@test "verify confirms matching fingerprint from manifest" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  rudi collaborators

  run rudi verify "$ada_fpr"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Verified"
}

@test "verify rejects mismatched fingerprint" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  rudi collaborators

  run rudi verify "0000000000000000000000000000000000000000"
  [ "$status" -ne 0 ]
}

@test "verify works with --key-file from stdin" {
  create_test_repo "test-repo"

  local ada_fpr
  ada_fpr=$(create_test_user "ada")
  rudi init --user "$ada_fpr" alpha

  local pubkey
  pubkey=$(gpg --homedir "$USERS_DIR/ada/g" --armor --export "$ada_fpr" 2>/dev/null)

  run bash -c "echo '$pubkey' | CALLER_PWD='$RUDI_TARGET' mise -C '$MISE_CONFIG_ROOT' run -q verify '$ada_fpr' --key-file -"
  [ "$status" -eq 0 ]
}
