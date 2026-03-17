<div align="center">

<pre>
+----------------------------------+,|       ╔═══════════════════════╗  |,|       ║   R · U · D · I       ║  |,|       ╚═══════════════════════╝  |,|                                  |,|    Restricted Until Decryption   |,|            Invoked               |,+----------------------------------+
</pre>

# rudi

**Multi-key encryption for repos where different people should see different things.**

![tests: 34 passing](https://img.shields.io/badge/tests-34%20passing-brightgreen?style=flat)
![tasks: 10](https://img.shields.io/badge/tasks-10-blue?style=flat)
![wraps: git-crypt](https://img.shields.io/badge/wraps-git--crypt-4a4a4a?style=flat)
![shell: bash](https://img.shields.io/badge/shell-bash-4EAA25?style=flat&logo=gnubash&logoColor=white)

</div>

<br />

## The problem

git-crypt encrypts files in a repo. But it uses a **single key** — you either decrypt everything or nothing. That breaks when you need tiered access:

- A human needs to read agent identity files, but not private agent notes
- Different humans should only see their own scratchpad
- A CI pipeline needs config secrets, but not personnel data
- A contractor needs shared docs, but not internal notes

git-crypt actually supports [named keys](https://github.com/AGWA/git-crypt) via `--key-name`, but the feature is undocumented, has edge cases, and no tooling. rudi wraps it into something usable.

<br />

## How it works

<div align="center">

<pre>
         ┌──────────────┐
         │  .gitattributes  ← pattern → key mapping
         └──────┬───────┘
                │
    ┌───────────┴───────────┐
    │                       │
  notes/**             HUMAN.md
  filter=git-crypt     filter=git-crypt-bootstrap
    │                       │
    ▼                       ▼
┌────────┐           ┌───────────┐
│default │           │ bootstrap │    ← named keys
│  key   │           │    key    │
└───┬────┘           └─────┬─────┘
    │                      │
    │  ┌───────────────────┤
    │  │                   │
    ▼  ▼                   ▼
  Agent               Human        ← collaborators
  (both keys)         (bootstrap only)
  sees: ALL           sees: HUMAN.md
</pre>

</div>

Each named key encrypts a different set of files. Each collaborator gets access to specific keys. The `.gitattributes` file maps patterns to keys. The result: fine-grained, per-file access control in a single repo.

<br />

## Quick start

```bash
# Install
shiv install rudi

# Initialize a repo with a named key
cd my-repo
rudi init bootstrap

# Assign files to keys
rudi assign "notes/**"                    # default key
rudi assign "HUMAN.md" --key bootstrap    # named key

# Add collaborators
rudi add-user <agent-fpr>                 # default key (sees notes/**)
rudi add-user <agent-fpr> --key bootstrap # also sees HUMAN.md
rudi add-user <human-fpr> --key bootstrap # only sees HUMAN.md
```

The human can now `git clone` and `git-crypt unlock` — they'll see HUMAN.md in plaintext while notes/ stays encrypted.

<br />

## Revocation

This is the part git-crypt never solved. rudi makes offboarding a two-step process:

```bash
# Step 1: Remove access (prevents future clones from granting the key)
rudi remove-user <fingerprint> --key bootstrap

# Step 2: Rotate the key (re-encrypts files with a fresh key)
rudi rotate-key --key bootstrap
```

After rotation, the old symmetric key is gone. Even if the removed user cached it, the files are now encrypted with a completely different key. Remaining collaborators are automatically re-added to the new key.

<details>
<summary><b>What rotate-key does under the hood</b></summary>

1. Saves plaintext content of all files under the target key
2. Locks the key's files
3. Deletes the old symmetric key and all .gpg wrappers
4. Generates a fresh symmetric key
5. Re-adds all remaining collaborators
6. Unlocks and restores file contents — now encrypted under the new key

</details>

<br />

## Audit trail

Every `add-user` and `remove-user` automatically regenerates a `COLLABORATORS` manifest — a vendored record of who can decrypt what:

```
# Who can decrypt this repo
# Patterns per key:
#   default: notes/**
#   bootstrap: HUMAN.md, agents/*/AGENTS.md

## alice <alice@example.com>
## Fingerprint: ABC123...
## Keys: default, bootstrap
-----BEGIN PGP PUBLIC KEY BLOCK-----
...
-----END PGP PUBLIC KEY BLOCK-----

## bob <bob@example.com>
## Fingerprint: DEF456...
## Keys: bootstrap
-----BEGIN PGP PUBLIC KEY BLOCK-----
...
```

The manifest is self-contained — anyone can import a public key block, compute its fingerprint, and verify it matches. No keyserver required. Git history shows exactly when each collaborator was added or removed.

```bash
# Verify a collaborator's key against the manifest
rudi verify <fingerprint>

# Or verify from an external key file
rudi verify <fingerprint> --key-file pubkey.asc
```

<br />

## Lifecycle

<div align="center">

<pre>
   init ─── add-key ─── assign ─── add-user
    │                                  │
    │          collaborators ◄──────────┤
    │          (auto-generated)         │
    │                                   │
    │    ┌──── remove-user ◄────────────┘
    │    │         │
    │    │    rotate-key    ← full revocation
    │    │         │
    ▼    ▼         ▼
   status    verify    ← audit & verify
</pre>

</div>

<br />

## Commands

| Command | Description | Key flags |
| --- | --- | --- |
| `rudi init` | Initialize git-crypt with default and optional named keys | — |
| `rudi install` | Install git-crypt (brew on macOS, binary download on Linux) | — |
| `rudi collaborators` | Regenerate COLLABORATORS manifest for all keys | — |
| `rudi verify` | Verify a GPG public key matches a claimed fingerprint | `-f --key-file <file>` |
| `rudi remove-user` | Remove a GPG user from a key | `-k --key <name>` |
| `rudi add-user` | Add a GPG user to a key | `-k --key <name>` |
| `rudi status` | Show multi-key encryption status | — |
| `rudi assign` | Assign a file pattern to an encryption key | `-k --key <name>` |
| `rudi rotate-key` | Rotate a named key (re-encrypt files with a new key) | `-k --key <name>` |
| `rudi add-key` | Add a named encryption key | — |

<br />

## Use cases

<table>
  <tr>
    <td width="50%" valign="top">

**Agent home bootstrap**

Human clones an agent home, needs to read HUMAN.md and identity files but not private agent notes. Named key gives them exactly the access they need.

**Multi-human isolation**

Each human gets their own scratchpad (HUMAN.alice.md, HUMAN.bob.md) encrypted with their own key. Agents see everything. Humans see only their own file.


</td>
    <td width="50%" valign="top">

**Contractor access**

External collaborator gets a named key scoped to shared files. When the engagement ends: remove-user + rotate-key. Clean offboarding.

**CI/CD secrets**

Export a named key as a symmetric key file, inject as a CI secret. The pipeline decrypts only its config — no GPG keyring needed.


</td>
  </tr>
</table>

<br />

## Discoveries

Things we learned by testing git-crypt's multi-key behavior that aren't documented anywhere:

| Behavior | Finding |
| --- | --- |
| `git-crypt lock` (no flags) | Locks only default-key files. Named-key files stay plaintext. |
| `git-crypt lock --all` | Locks all keys. This is what you almost always want. |
| `git-crypt unlock` | Unlocks ALL keys the user has access to. No per-key unlock via GPG. |
| `git-crypt status -e` | Shows encrypted files but NOT which key protects them. Limitation. |
| .gitattributes patterns | Can't parameterize key names in globs. Each file-to-key mapping needs an explicit line. |
| Adding new keys | Additive — no re-keying of existing files needed. |

<br />

## Development

```bash
git clone https://github.com/KnickKnackLabs/rudi.git
cd rudi && mise trust && mise install
mise run test
```

34 tests across 5 suites (`access`, `init`, `revocation`, `lock`, `collaborators`). Tests use [BATS](https://github.com/bats-core/bats-core) with ephemeral GPG keys and isolated git repos — no real keys or keyrings are touched.

<br />

<div align="center">

---

<sub>
*Different people, different keys, same repo.*<br />
<br />
This README was generated with <a href="https://github.com/KnickKnackLabs/readme">readme</a>.
</sub></div>
