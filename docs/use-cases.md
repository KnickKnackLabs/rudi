# rudi — Use Cases

**R**estricted **U**ntil **D**ecryption **I**nvoked

rudi wraps git-crypt's multi-key feature to give different people access to different files in the same repo. Here's what that enables.

## 1. Agent Home Bootstrap

**Problem:** A human clones an agent home (fold, den) onto a new machine. Everything in `notes/` is encrypted. They can't read HUMAN.md or create identity files because they're not a decrypter — and they shouldn't need access to private agent notes just to bootstrap.

**Solution:** Two keys. The default key protects agent-only files (`notes/**`). A named key (e.g. `bootstrap`) protects files the human needs (`HUMAN.md`, `agents/*/AGENTS.md`). The human gets only the `bootstrap` key.

```bash
rudi init bootstrap
rudi assign "notes/**"                    # default key — agents only
rudi assign "HUMAN.md" --key bootstrap    # bootstrap key — human + agents
rudi assign "agents/*/AGENTS.md" --key bootstrap
rudi add-user <agent-fpr>                 # agent gets default key
rudi add-user <agent-fpr> --key bootstrap # agent also gets bootstrap key
rudi add-user <human-fpr> --key bootstrap # human gets bootstrap key only
```

The human can now clone, unlock, read/write HUMAN.md and identity files, but cannot read agent notes.

## 2. Multi-Human Isolation

**Problem:** Multiple humans interact with the same agent home. Each human's scratchpad (HUMAN.md equivalent) should be private — Human A shouldn't read Human B's threads, and vice versa. Agents need to see everything.

**Solution:** Per-human named keys. Each human gets their own key and their own scratchpad file.

```bash
rudi init alice bob
rudi assign "notes/**"                        # default — agents only
rudi assign "HUMAN.alice.md" --key alice      # alice's scratchpad
rudi assign "HUMAN.bob.md" --key bob          # bob's scratchpad
rudi add-user <agent-fpr>                     # agent gets all keys
rudi add-user <agent-fpr> --key alice
rudi add-user <agent-fpr> --key bob
rudi add-user <alice-fpr> --key alice         # alice decrypts only her file
rudi add-user <bob-fpr> --key bob             # bob decrypts only his file
```

Each human sees only their own scratchpad. Agents see all scratchpads plus the private notes.

## 3. Tiered Confidentiality

**Problem:** A repo has files at different sensitivity levels. Some are internal (all team members can see), some are restricted (only certain people). A single encryption key forces all-or-nothing access.

**Solution:** Named keys per tier.

```bash
rudi init internal restricted
rudi assign "docs/internal/**" --key internal
rudi assign "docs/restricted/**" --key restricted
rudi add-user <everyone-fpr> --key internal       # whole team
rudi add-user <leadership-fpr> --key restricted   # restricted access
```

## 4. Contractor / External Collaborator Access

**Problem:** An external collaborator needs access to specific files in a private repo, but shouldn't see everything. You don't want to split the repo or maintain a separate fork.

**Solution:** A named key scoped to the collaborator's files.

```bash
rudi init external
rudi assign "shared/**" --key external    # files the contractor needs
rudi assign "internal/**"                 # default key — team only
rudi add-user <contractor-fpr> --key external
```

When the engagement ends, remove the contractor's key (see "Key Removal" below).

## 5. Symmetric Key Distribution

**Problem:** A CI system or automation pipeline needs to decrypt specific files, but GPG key management is impractical in that environment.

**Solution:** Export a named key as a symmetric key file and inject it as a CI secret.

```bash
rudi init ci
rudi assign "config/secrets/**" --key ci
git-crypt export-key --key-name ci ci.key
# Store ci.key as a CI secret, use `git-crypt unlock ci.key` in the pipeline
```

The CI system decrypts only what it needs. No GPG keyring required.

---

## Known Limitations

### `git-crypt status` shows no key information

`git-crypt status -e` lists encrypted files but does **not** show which key protects which file. You see:

```
encrypted: HUMAN.md
encrypted: notes/secret.md
```

But not:

```
encrypted (alpha): HUMAN.md
encrypted (default): notes/secret.md
```

**Workaround:** rudi's `status` task parses `.gitattributes` to show the key-to-pattern mapping. The pattern tells you which key a file falls under. This is accurate but doesn't handle edge cases like overlapping patterns.

**Why this matters:** When debugging "why can't user X read file Y?", you need to know which key protects Y, then check if X has that key. Without rudi's status view, you'd have to manually inspect `.gitattributes`.

### `lock` (no flags) only locks default-key files

`git-crypt lock` without arguments locks **only** files under the default key. Named-key files remain plaintext. Use `git-crypt lock --all` to lock everything, or `git-crypt lock --key-name <name>` to lock a specific key.

### `unlock` has no `--key-name` flag

`git-crypt unlock` (GPG mode) unlocks **all** keys the user has access to. You cannot selectively unlock just one named key via GPG. Selective unlock is only possible with symmetric key files (`git-crypt unlock <keyfile>`).

### `.gitattributes` patterns can't parameterize key names

You cannot write `HUMAN.*.md filter=git-crypt-*`. Each file-to-key mapping requires an explicit `.gitattributes` line. Adding a new user with their own key means adding a new line to `.gitattributes`.

### Key removal is not natively supported

git-crypt has no `remove-gpg-user` command. See "Key Removal" below.

---

## Key Removal (Future Work)

git-crypt doesn't provide a built-in way to remove a user's access. The `.gpg` files in `.git-crypt/keys/<name>/0/` can be deleted from the repo, but this only prevents future unlocks — **it does not revoke access to data the user has already decrypted or to the symmetric key they may have cached.**

True revocation requires:
1. Delete the user's `.gpg` file from `.git-crypt/keys/<name>/0/`
2. Rotate the affected key (generate a new one, re-encrypt all files under it)
3. Re-add all remaining users to the new key

This is painful manually but automatable. rudi could provide:

```bash
rudi remove-user <fingerprint> [--key <name>]    # delete .gpg file
rudi rotate-key <name>                            # re-encrypt with new key
```

The `rotate-key` operation is the hard part — it requires decrypting all affected files, re-initializing the key, re-adding all remaining users, and re-encrypting. But it's a deterministic process that mise tasks can orchestrate.

For the common case (offboarding someone from an org), the pragmatic approach is:
1. Remove their `.gpg` file (prevents future clones from granting access)
2. Rotate keys only if the data is sensitive enough to warrant it
3. Accept that historical git data remains accessible to anyone who had the key

This matches how most secret rotation works — you rotate the secret going forward, you don't try to retroactively un-share it.
