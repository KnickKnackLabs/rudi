#!/usr/bin/env bash
# common.sh — shared helpers for rudi
# All functions namespaced rudi_

# Resolve the target directory (the repo rudi is operating on).
# Uses CALLER_PWD (set by shiv shim) or falls back to PWD.
rudi_target_dir() {
  echo "${CALLER_PWD:-$PWD}"
}

# Check if a file is encrypted (git-crypt binary format).
# Args: $1 = full path to file
# Returns 0 if encrypted, 1 if plaintext.
rudi_is_encrypted() {
  local filepath="$1"
  # git-crypt encrypted files start with \x00GITCRYPT magic header
  if head -c 10 "$filepath" 2>/dev/null | grep -q "GITCRYPT"; then
    return 0
  fi
  # Fallback: file(1) reports "data" for binary
  if file -b "$filepath" 2>/dev/null | grep -q "data"; then
    return 0
  fi
  return 1
}

# Check if a file is readable plaintext.
# Args: $1 = full path to file
# Returns 0 if plaintext, 1 if encrypted.
rudi_is_plaintext() {
  ! rudi_is_encrypted "$1"
}

# Require git-crypt to be installed.
rudi_require_git_crypt() {
  if ! command -v git-crypt &>/dev/null; then
    echo "Error: git-crypt not found. Run: rudi install" >&2
    exit 1
  fi
}

# Require the target directory to be a git repo.
rudi_require_git() {
  local target="$1"
  if ! git -C "$target" rev-parse --git-dir &>/dev/null; then
    echo "Error: not a git repository: $target" >&2
    exit 1
  fi
}
