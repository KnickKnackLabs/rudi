# rudi

**R**estricted **U**ntil **D**ecryption **I**nvoked

Multi-key git-crypt encryption for tiered access control. Different people decrypt different files based on their role.

## Problem

git-crypt repos use a single key — you either decrypt everything or nothing. This breaks when you need tiered access:
- Humans need to read `HUMAN.md` and agent identity files, but not private agent notes
- Different humans should only see their own scratchpad
- Agents see everything

## Approach

git-crypt natively supports named keys (`--key-name`). rudi explores and packages this capability.

## Status

Experiment phase — proving out multi-key git-crypt behavior via BATS tests.

Tracked in [or#104](https://github.com/ricon-family/or/issues/104).

## Testing

```bash
mise run test           # all phases
mise run test:phase1    # bootstrap access
mise run test:phase2    # multi-key edge cases
mise run test:phase3    # per-human HUMAN.md
```
