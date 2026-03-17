/** @jsxImportSource jsx-md */

import { readFileSync, readdirSync } from "fs";
import { join, resolve } from "path";

import {
  Heading, Paragraph, CodeBlock, Blockquote, LineBreak, HR,
  Bold, Code, Link, Italic,
  Badge, Badges, Center, Details, Section,
  Table, TableHead, TableRow, Cell,
  List, Item,
  Raw, HtmlLink, Sub, Align, HtmlTable, HtmlTr, HtmlTd,
  box, labeledBox, sideBySide,
} from "readme/src/components";

// ── Dynamic data ─────────────────────────────────────────────

const REPO_DIR = resolve(import.meta.dirname);

// Count tests across all .bats files
const testDir = join(REPO_DIR, "test");
const testFiles = readdirSync(testDir).filter((f) => f.endsWith(".bats"));
const allTestSrc = testFiles
  .map((f) => readFileSync(join(testDir, f), "utf-8"))
  .join("\n");
const testNames = [...allTestSrc.matchAll(/@test "(.+?)"/g)].map((m) => m[1]);
const testCount = testNames.length;

// Extract task descriptions from mise task files
const tasksDir = join(REPO_DIR, ".mise/tasks");
const taskFiles = readdirSync(tasksDir).filter(
  (f) => !f.startsWith(".") && f !== "test"
);

interface TaskInfo {
  name: string;
  description: string;
  args: string;
  flags: string;
}

function parseTask(name: string): TaskInfo {
  const src = readFileSync(join(tasksDir, name), "utf-8");
  const desc = src.match(/#MISE description="(.+?)"/)?.[1] ?? "";
  const argMatches = [...src.matchAll(/#USAGE arg "(.+?)"/g)];
  const flagMatches = [...src.matchAll(/#USAGE flag "(.+?)"/g)];
  const args = argMatches.map((m) => m[1]).join(" ");
  const flags = flagMatches.map((m) => m[1]).join(", ");
  return { name, description: desc, args, flags };
}

const tasks = taskFiles.map(parseTask);

// ── Helpers ──────────────────────────────────────────────────

// Draw the access matrix: users × keys → files
const accessMatrix = [
  "         ┌──────────────┐",
  "         │  .gitattributes  ← pattern → key mapping",
  "         └──────┬───────┘",
  "                │",
  "    ┌───────────┴───────────┐",
  "    │                       │",
  "  notes/**             HUMAN.md",
  "  filter=git-crypt     filter=git-crypt-bootstrap",
  "    │                       │",
  "    ▼                       ▼",
  "┌────────┐           ┌───────────┐",
  "│default │           │ bootstrap │    ← named keys",
  "│  key   │           │    key    │",
  "└───┬────┘           └─────┬─────┘",
  "    │                      │",
  "    │  ┌───────────────────┤",
  "    │  │                   │",
  "    ▼  ▼                   ▼",
  "  Agent               Human        ← collaborators",
  "  (both keys)         (bootstrap only)",
  "  sees: ALL           sees: HUMAN.md",
].join("\n");

// Lifecycle diagram
const lifecycle = [
  "   init ─── add-key ─── assign ─── add-user",
  "    │                                  │",
  "    │          collaborators ◄──────────┤",
  "    │          (auto-generated)         │",
  "    │                                   │",
  "    │    ┌──── remove-user ◄────────────┘",
  "    │    │         │",
  "    │    │    rotate-key    ← full revocation",
  "    │    │         │",
  "    ▼    ▼         ▼",
  "   status    verify    ← audit & verify",
].join("\n");

// Logo
const logo = box([
  "     ╔═══════════════════════╗",
  "     ║   R · U · D · I       ║",
  "     ╚═══════════════════════╝",
  "",
  "  Restricted Until Decryption",
  "          Invoked",
], { padding: 2 });

// ── README ───────────────────────────────────────────────────

const readme = (
  <>
    <Center>
      <Raw>{`<pre>\n${logo}\n</pre>\n\n`}</Raw>

      <Heading level={1}>rudi</Heading>

      <Paragraph>
        <Bold>Multi-key encryption for repos where different people should see different things.</Bold>
      </Paragraph>

      <Badges>
        <Badge label="tests" value={`${testCount} passing`} color="brightgreen" />
        <Badge label="tasks" value={`${tasks.length}`} color="blue" />
        <Badge label="wraps" value="git-crypt" color="4a4a4a" />
        <Badge label="shell" value="bash" color="4EAA25" logo="gnubash" logoColor="white" />
      </Badges>
    </Center>

    <LineBreak />

    <Section title="The problem">
      <Paragraph>
        {"git-crypt encrypts files in a repo. But it uses a "}
        <Bold>single key</Bold>
        {" — you either decrypt everything or nothing. That breaks when you need tiered access:"}
      </Paragraph>

      <List>
        <Item>{"A human needs to read agent identity files, but not private agent notes"}</Item>
        <Item>{"Different humans should only see their own scratchpad"}</Item>
        <Item>{"A CI pipeline needs config secrets, but not personnel data"}</Item>
        <Item>{"A contractor needs shared docs, but not internal notes"}</Item>
      </List>

      <Paragraph>
        {"git-crypt actually supports "}
        <Link href="https://github.com/AGWA/git-crypt">named keys</Link>
        {" via "}
        <Code>--key-name</Code>
        {", but the feature is undocumented, has edge cases, and no tooling. rudi wraps it into something usable."}
      </Paragraph>
    </Section>

    <LineBreak />

    <Section title="How it works">
      <Center>
        <Raw>{`<pre>\n${accessMatrix}\n</pre>\n\n`}</Raw>
      </Center>

      <Paragraph>
        {"Each named key encrypts a different set of files. Each collaborator gets access to specific keys. The "}
        <Code>.gitattributes</Code>
        {" file maps patterns to keys. The result: fine-grained, per-file access control in a single repo."}
      </Paragraph>
    </Section>

    <LineBreak />

    <Section title="Quick start">
      <CodeBlock lang="bash">{`# Install
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
rudi add-user <human-fpr> --key bootstrap # only sees HUMAN.md`}</CodeBlock>

      <Paragraph>
        {"The human can now "}
        <Code>git clone</Code>
        {" and "}
        <Code>git-crypt unlock</Code>
        {" — they'll see HUMAN.md in plaintext while notes/ stays encrypted."}
      </Paragraph>
    </Section>

    <LineBreak />

    <Section title="Revocation">
      <Paragraph>
        {"This is the part git-crypt never solved. rudi makes offboarding a two-step process:"}
      </Paragraph>

      <CodeBlock lang="bash">{`# Step 1: Remove access (prevents future clones from granting the key)
rudi remove-user <fingerprint> --key bootstrap

# Step 2: Rotate the key (re-encrypts files with a fresh key)
rudi rotate-key --key bootstrap`}</CodeBlock>

      <Paragraph>
        {"After rotation, the old symmetric key is gone. Even if the removed user cached it, "}
        {"the files are now encrypted with a completely different key. Remaining collaborators "}
        {"are automatically re-added to the new key."}
      </Paragraph>

      <Details summary="What rotate-key does under the hood">
        <List ordered>
          <Item>{"Saves plaintext content of all files under the target key"}</Item>
          <Item>{"Locks the key's files"}</Item>
          <Item>{"Deletes the old symmetric key and all .gpg wrappers"}</Item>
          <Item>{"Generates a fresh symmetric key"}</Item>
          <Item>{"Re-adds all remaining collaborators"}</Item>
          <Item>{"Unlocks and restores file contents — now encrypted under the new key"}</Item>
        </List>
      </Details>
    </Section>

    <LineBreak />

    <Section title="Audit trail">
      <Paragraph>
        {"Every "}
        <Code>add-user</Code>
        {" and "}
        <Code>remove-user</Code>
        {" automatically regenerates a "}
        <Code>COLLABORATORS</Code>
        {" manifest — a vendored record of who can decrypt what:"}
      </Paragraph>

      <CodeBlock>{`# Who can decrypt this repo
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
...`}</CodeBlock>

      <Paragraph>
        {"The manifest is self-contained — anyone can import a public key block, compute its fingerprint, and verify it matches. No keyserver required. Git history shows exactly when each collaborator was added or removed."}
      </Paragraph>

      <CodeBlock lang="bash">{`# Verify a collaborator's key against the manifest
rudi verify <fingerprint>

# Or verify from an external key file
rudi verify <fingerprint> --key-file pubkey.asc`}</CodeBlock>
    </Section>

    <LineBreak />

    <Section title="Lifecycle">
      <Center>
        <Raw>{`<pre>\n${lifecycle}\n</pre>\n\n`}</Raw>
      </Center>
    </Section>

    <LineBreak />

    <Section title="Commands">
      <Table>
        <TableHead>
          <Cell>Command</Cell>
          <Cell>Description</Cell>
          <Cell>Key flags</Cell>
        </TableHead>
        {tasks.map((t) => (
          <TableRow>
            <Cell><Code>{`rudi ${t.name}`}</Code></Cell>
            <Cell>{t.description}</Cell>
            <Cell>{t.flags ? <Code>{t.flags}</Code> : "—"}</Cell>
          </TableRow>
        ))}
      </Table>
    </Section>

    <LineBreak />

    <Section title="Use cases">
      <HtmlTable>
        <HtmlTr>
          <HtmlTd width="50%" valign="top">
            <Paragraph><Bold>Agent home bootstrap</Bold></Paragraph>
            <Paragraph>
              {"Human clones an agent home, needs to read HUMAN.md and identity files but not private agent notes. Named key gives them exactly the access they need."}
            </Paragraph>
            <Paragraph><Bold>Multi-human isolation</Bold></Paragraph>
            <Paragraph>
              {"Each human gets their own scratchpad (HUMAN.alice.md, HUMAN.bob.md) encrypted with their own key. Agents see everything. Humans see only their own file."}
            </Paragraph>
          </HtmlTd>
          <HtmlTd width="50%" valign="top">
            <Paragraph><Bold>Contractor access</Bold></Paragraph>
            <Paragraph>
              {"External collaborator gets a named key scoped to shared files. When the engagement ends: remove-user + rotate-key. Clean offboarding."}
            </Paragraph>
            <Paragraph><Bold>CI/CD secrets</Bold></Paragraph>
            <Paragraph>
              {"Export a named key as a symmetric key file, inject as a CI secret. The pipeline decrypts only its config — no GPG keyring needed."}
            </Paragraph>
          </HtmlTd>
        </HtmlTr>
      </HtmlTable>
    </Section>

    <LineBreak />

    <Section title="Discoveries">
      <Paragraph>
        {"Things we learned by testing git-crypt's multi-key behavior that aren't documented anywhere:"}
      </Paragraph>

      <Table>
        <TableHead>
          <Cell>Behavior</Cell>
          <Cell>Finding</Cell>
        </TableHead>
        <TableRow>
          <Cell><Code>git-crypt lock</Code>{" (no flags)"}</Cell>
          <Cell>{"Locks only default-key files. Named-key files stay plaintext."}</Cell>
        </TableRow>
        <TableRow>
          <Cell><Code>git-crypt lock --all</Code></Cell>
          <Cell>{"Locks all keys. This is what you almost always want."}</Cell>
        </TableRow>
        <TableRow>
          <Cell><Code>git-crypt unlock</Code></Cell>
          <Cell>{"Unlocks ALL keys the user has access to. No per-key unlock via GPG."}</Cell>
        </TableRow>
        <TableRow>
          <Cell><Code>git-crypt status -e</Code></Cell>
          <Cell>{"Shows encrypted files but NOT which key protects them. Limitation."}</Cell>
        </TableRow>
        <TableRow>
          <Cell>.gitattributes patterns</Cell>
          <Cell>{"Can't parameterize key names in globs. Each file-to-key mapping needs an explicit line."}</Cell>
        </TableRow>
        <TableRow>
          <Cell>Adding new keys</Cell>
          <Cell>{"Additive — no re-keying of existing files needed."}</Cell>
        </TableRow>
      </Table>
    </Section>

    <LineBreak />

    <Section title="Development">
      <CodeBlock lang="bash">{`git clone https://github.com/KnickKnackLabs/rudi.git
cd rudi && mise trust && mise install
mise run test`}</CodeBlock>

      <Paragraph>
        {`${testCount} tests across ${testFiles.length} suites (`}
        {testFiles.map((f) => <Code>{f.replace(".bats", "")}</Code>).reduce(
          (acc: any[], el, i) => i === 0 ? [el] : [...acc, ", ", el], []
        )}
        {"). Tests use "}
        <Link href="https://github.com/bats-core/bats-core">BATS</Link>
        {" with ephemeral GPG keys and isolated git repos — no real keys or keyrings are touched."}
      </Paragraph>
    </Section>

    <LineBreak />

    <Center>
      <HR />

      <Sub>
        <Italic>{"Different people, different keys, same repo."}</Italic>
        <Raw>{"<br />"}</Raw>{"\n"}
        <Raw>{"<br />"}</Raw>{"\n"}
        {"This README was generated with "}
        <HtmlLink href="https://github.com/KnickKnackLabs/readme">readme</HtmlLink>
        {"."}
      </Sub>
    </Center>
  </>
);

console.log(readme);
