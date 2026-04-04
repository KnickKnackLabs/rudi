#!/usr/bin/env bats
# Tests for rudi status and rudi status --json

load helpers

# --- Text output ---

@test "status shows keys when unlocked" {
  create_test_repo "test-repo"
  rudi init

  run rudi status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "default (initialized)"
}

@test "status shows collaborators" {
  create_test_repo "test-repo"
  rudi init
  local fpr
  fpr=$(create_test_user "ada")
  rudi add-user "$fpr"

  run rudi status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "default: 1 user(s)"
}

@test "status shows patterns" {
  create_test_repo "test-repo"
  rudi init
  rudi assign "notes/**"

  run rudi status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "notes/\*\*"
}

# --- JSON output ---

@test "status --json outputs valid JSON" {
  create_test_repo "test-repo"
  rudi init

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "status --json shows initialized and unlocked when init'd" {
  create_test_repo "test-repo"
  rudi init

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.initialized == true'
  echo "$output" | jq -e '.unlocked == true'
}

@test "status --json shows keys" {
  create_test_repo "test-repo"
  rudi init

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.keys | length > 0'
  echo "$output" | jq -e '.keys | index("default") != null'
}

@test "status --json shows multiple keys" {
  create_test_repo "test-repo"
  rudi init alpha

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.keys | length == 2'
  echo "$output" | jq -e '.keys | index("default") != null'
  echo "$output" | jq -e '.keys | index("alpha") != null'
}

@test "status --json shows collaborator counts" {
  create_test_repo "test-repo"
  rudi init
  local fpr
  fpr=$(create_test_user "ada")
  rudi add-user "$fpr"

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.collaborators.default == 1'
}

@test "status --json shows patterns" {
  create_test_repo "test-repo"
  rudi init
  rudi assign "notes/**"
  rudi assign "submodules/.manifest"

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.patterns | length == 2'
  echo "$output" | jq -e '.patterns | index("notes/**") != null'
  echo "$output" | jq -e '.patterns | index("submodules/.manifest") != null'
}

@test "status --json shows not initialized for bare repo" {
  export RUDI_TARGET="$REPOS_DIR/bare"
  mkdir -p "$RUDI_TARGET"
  git -C "$RUDI_TARGET" init -q -b main

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.initialized == false'
  echo "$output" | jq -e '.unlocked == false'
  echo "$output" | jq -e '.keys == []'
}

@test "status --json shows locked after lock" {
  create_test_repo "test-repo"
  rudi init
  local fpr
  fpr=$(create_test_user "ada")
  rudi add-user "$fpr"
  rudi assign "secret.md"
  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "secret.md" "top secret"

  rudi lock

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.initialized == true'
  echo "$output" | jq -e '.unlocked == false'
}

@test "status --json shows unlocked after unlock" {
  create_test_repo "test-repo"
  rudi init
  local fpr
  fpr=$(create_test_user "ada")
  rudi add-user "$fpr"
  rudi assign "secret.md"
  commit_file ".gitattributes" "$(cat "$RUDI_TARGET/.gitattributes")"
  commit_file "secret.md" "top secret"

  rudi lock
  export GNUPGHOME="$USERS_DIR/ada/g"
  rudi unlock

  run rudi status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.unlocked == true'
}
