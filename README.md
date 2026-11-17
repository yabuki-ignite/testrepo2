# Work IQ Preview Plugin

Preview **3.1.2** names both plugins in a precedence rule shared verbatim with
stable, so promotions carry it unchanged. **3.1.1** qualified cross-plugin
precedence by installed version: prefer preview only when it is newer than
stable. The preceding **3.1.0**
version-only update aligned the **2.2.3** package beyond stable **3.0.0**.
Capabilities and MCP configuration are unchanged. Earlier release notes below
retain their original version numbers.

Agent-host-neutral WorkIQ tools for compatible AI agents. Find workplace evidence
with `retrieve` and explicit Grounding, then write the answer locally. Use `ask`
only for a requested Copilot or named-agent answer, and entity tools for specific
Microsoft 365 and Business Applications reads and operations.

If `workiq` and `workiq-preview` are both installed, prefer **workiq-preview
only if its installed version is higher than workiq's** for overlapping requests. Compare numeric
`MAJOR.MINOR.PATCH` versions; prefer stable on ties, older preview or unknown
versions. Use the selected plugin's skill and configured tools; unavailable
retrieval does not trigger automatic `ask` or plugin fallback.
Current `retrieve.query` and `search_paths.query` are single nonblank strings,
not arrays. The skill verifies exact sources and read/write intent before acting.
Teams guidance covers exact directory/member identity, topic/marker/URL reads
and known action contracts, plus extended routes for activity, message and chat
management, members and tags, settings and work location, meetings and channel
content, while preserving preview source restrictions, confirmation and
non-replay recovery.

Upstream **2.1.2** supplied the skill, references, and host manifests from
[upstream PR #216](https://github.com/microsoft/work-iq/pull/216) at
[`607c331bd7bc6391c13b8f398650326a90361cad`](https://github.com/microsoft/work-iq/commit/607c331bd7bc6391c13b8f398650326a90361cad).
Local marketplace installation examples and hosted MCP configuration are retained.

Local **2.2.3** adds a preview-only
[Office artifact route](./skills/workiq-preview/references/office-artifacts-work-iq.md)
for `/office-agent-mcp/generate_artifact` and `/office-agent-mcp/edit_artifact`
through WorkIQ `do_action`. It preserves the provider's required final-content
Markdown outlines, exact app names, verbatim edit URLs, approval, non-replay and
MCP result/sensitivity handling. The provider source is pinned to
`3cb555deed5aa7559b6f980a342b7e65d6a289dc`; it is disabled with an empty tenant
allowlist in all rings. This guidance neither enables it nor proves availability.
Stable, hosted MCP configuration, ordinary files routes and retrieve-first
policy are unchanged. Offline loading and contract checks are not live tests.

The same **2.2.3** update adds a separate
[Copilot Pages route](./skills/workiq-preview/references/pages-work-iq.md)
for `/pages/create_page` and `/pages/edit_page`, aligned to the same provider
revision. Pages use the user's non-empty `userRequest`, plus the exact existing
Page URL for edits, not Office artifact outlines or app metadata. Creation
requires a `.page` resource link; confirmed in-place edits may return no new
link. Only an explicit concurrent-edit conflict permits one edit retry after
reading the latest Page and regenerating the edit. The Pages provider is also
disabled and tenant-gated. SharePoint site-page downloads stay on their existing
route; no live Page creation or editing is performed by offline checks.

The [Files CLI reference](./skills/workiq-preview/references/workiq-files-cli.md) is imported from upstream [PR #233](https://github.com/microsoft/work-iq/pull/233) at commit [`df4d30a76af341cceb4a0d428bb4b30e5abae506`](https://github.com/microsoft/work-iq/commit/df4d30a76af341cceb4a0d428bb4b30e5abae506). Its entry point is adapted to the local files route index; existing Graph drive-content and mail-attachment downloads remain on entity tools.

Local version **2.2.1** added plain-language routing examples, a polarity-sensitive
URL guard, shared private-read rules, and focused Business Applications and
SharePoint references. It keeps the modular structure and original loading
ceilings. The preview policy remains retrieve-first with explicit Grounding.

Local **2.2.2** adds constraint-preserving empty-result recovery, exact
version/type/source checks, mail-window/unread and attachment acquisition,
relationship/year preservation, current-plan approval and effective-recipient
checks. The [content reader leaf](./skills/workiq-preview/references/files-content-work-iq.md)
separates available parsing/visual evidence from bytes and requested artifact
completion. Unsupported capabilities remain explicit limitations.

The [disposition matrix](../../tests/workiq-preview-eval-recommendations.json)
covers W01-W56 and the six additional preview follow-ups.
Synthetic transaction contracts and checker negatives are offline specifications,
not model compliance or reproduced CompeteBench-v2 failures. No production recall,
activation, quality, latency or cost uplift is established.

Review follow-up separates supported default mark-unread behaviour from an
explicit timestamp boundary. Unread state must not depend on message-list order;
the connected WorkIQ contract governs whether cutoff omission is supported.
The explicit-cutoff lookup uses the exact selected message; it does not assume
OData projection support on a single-message read.

Local version **2.2.2** adds an M365 Copilot agent/plugin lifecycle handoff to
WIQD via the `awesome-copilot` marketplace. Ordinary preview data routing and
the original loading ceilings are unchanged; stable remains **2.0.2**.

**2.2.2** also adds Teams guidance ported from upstream PRs #212 and #218 through
a Teams extended route index: unread chats, reactions, pins and threads; quote
replies, pins, message removal and chat creation or rename; members and tags;
team and channel settings, archiving and work location; meetings, transcripts and
AI insights; and tabs, apps, channel files and attachments. Read-only and
read-state tasks find an existing 1:1 chat and never create one.

Channel-file lookup still uses the channel's files folder and message
attachments. File-search deletion parity removes the remaining drive-root search
prohibition wording, personal-drive search scope commentary and empty-search
known-parent fallback. Ordinary known-folder reads, file mutations, the
channel-file `/search/query` restriction and WIQD handoff remain. No replacement
route, version or MCP configuration change is introduced.

## Reminder results

The [reminder route](skills/workiq-preview/references/calendar-reminders-work-iq.md)
reports every matching reminder or an evidenced scoped zero-match result, with
coverage limits separate from known results. Failed reads and incomplete
relevant pages cannot be reported as empty. Existing actual-workday, timezone,
schema, denial and bounded-recovery prerequisites remain in force; this change
does not validate new endpoints or all-calendar coverage. Version stays 2.2.2.

## Reference-led parity follow-ups

Version **2.2.2** is unchanged. Only the main skill's retrieval-routing sentence
changes, removing its unconditional grounding requirement. Operational details
remain in selected references, including:

- [Batch mechanics](./skills/workiq-preview/references/fetch-work-iq.md#batches-paging-and-host-caps):
  Graph's 50-URL ceiling, lower advertised limits, provider-homogeneous batches
  and per-result handling. The Graph ceiling and mixed-provider fallback were
  checked against MCP source revision `0327388f5`, not the deployed service.
- [Mail attachments](./skills/workiq-preview/references/mail-attachments-work-iq.md):
  actual attachment identity and the bounded first Inbox file download. Other
  folder/date/chronological requests keep their supported acquisition contracts.
- [Teams presence and sync](./skills/workiq-preview/references/teams-presence-work-iq.md):
  load the function contract before delta, without loading it for every presence read.
- [Library metadata](./skills/workiq-preview/references/sharepoint-library-metadata.md):
  requested inline tables/aggregates, disclosed output limits and diagnostic-specific
  local filtering/sorting. Unsupported continuation fallbacks remain excluded.
- [Business operations](./skills/workiq-preview/references/business-applications-actions.md):
  table deletion needs a supported discovered path and confirmation of whole-table scope.
- [Retrieval](./skills/workiq-preview/references/retrieve-work-iq.md):
  source-based strategy selection, status, proposal comparison and ownership
  examples use retrieve plus local synthesis, not implicit ask delegation.

The original loading ceilings, stable plugin, manifests and MCP configuration
are unchanged. The Inbox recipe remains inherited, not live-validated; use it
only when the connected contract supports the exact combination.

Run the plugin-local follow-up checks from the repository root:

```powershell
node --test plugins\workiq-preview\tests\guidance.test.mjs
```

These offline checks cover published guidance, loading plans and negative
mutations, not observed model compliance or live Microsoft 365 behavior.
Repository-wide documentation and test files are unchanged by these follow-ups.

## Progressive guidance loading

Preview also adapts the stable changes from
[local PR #24807](https://microsoftgraph.visualstudio.com/Graph%20Developer%20Experiences/_git/work-iq-skills/pullrequest/24807)
at `d066b30c9e8abe00f0f1ca4a4ce1a4ca548a456e`
(upstream PR #238 at `6fdf077b8942621c35f0990998abd8359d4ff0e1`).
Before summarizing status from retrieved evidence, structured reads or delegated
answers, load the shared [status safeguards](./skills/workiq-preview/references/status-work-iq.md).
Preserve material qualifiers, milestone boundaries, unconfirmed approvals and
substantive source dates. Personal-drive root-search recipes and their routing
guidance are removed without replacement routes or new prohibition rules;
independent identity and encoding safeguards remain.
Version **2.2.2**, retrieve-first routing and the original loading ceilings remain
unchanged. Static checks do not establish model compliance.

`SKILL.md` keeps routing and universal safety rules. Read the selected domain
index, then only the operation leaf and its `Required before use` links before
the relevant call. Mutation prerequisites load before writes; recovery loads
before retry or reconciliation. Before any same-objective retrieval follow-up,
load the evidence-repair route, including after successful but insufficient or
capped evidence. Such gaps do not themselves authorize broader retrieval.

Leaves are package-local and never require the stable package. Reuse only
available verbatim guidance; reread on uncertainty and stop if required text is
unavailable. This is not a host-enforced loader, unloading mechanism or proof of
model behavior.

## General rules and examples

Use entity tools when the user identifies a specific item or a bounded/filtered
listing: "list my unread emails from Alex this week" is a mail read.
"What did Alex say about the release?" needs retrieved evidence and local
synthesis. "Ask Copilot to summarize the release" explicitly requests its answer.
A name or date alone does not identify the data source. Multi-domain tasks follow
each operation's instructions, not one generic recipe.

Examples retain details that cannot safely be inferred: API paths, casing,
wrappers, typed IDs, query restrictions, etags and effect distinctions.
Variable subjects, recipients, task titles and durations are request-derived
placeholders, not defaults. Keep contrastive examples that teach a different
concept, such as DST boundary offsets or escaping before URL encoding.

Shared rules may be consolidated only when required before the relevant call,
through `Required before use` links or an explicit condition-specific before-use
instruction. Conditional requirements apply to their step, not to every route.
Action-wrapper leaves are retained because they attach
mutation prerequisites to write routes; known recipes still need no redundant
discovery. Static review and byte counts do not establish model compliance,
actual loading, latency or answer-quality improvements.

### Scoped reads and truthful output

- [People](./skills/workiq-preview/references/people-work-iq.md#directory-relationships-and-hierarchy-scope):
  resolve the requested subject, relationship and hierarchy depth; an empty
  subtree is not the manager's team, and a partial population is not a full total.
- [Output](./skills/workiq-preview/SKILL.md#read-results-and-queries):
  retain readable names and actual source links; never invent links or expose
  credential-bearing URLs as citations.
- [Selection](./skills/workiq-preview/references/mutation-work-iq.md#selection-and-disclosure):
  show relevant minimum identifying details, not unrelated private records;
  the shared [read/disclosure rules](./skills/workiq-preview/SKILL.md#read-results-and-queries)
  also apply to authorised own-private-data reads.
- [Content](./skills/workiq-preview/references/fetch-blob-work-iq.md#content-versus-pointers):
  delivered bytes may be a pointer/stub rather than the requested body. A missing
  content reader is a capability limitation, not permission to guess endpoints.
- [Queries](./skills/workiq-preview/SKILL.md#read-results-and-queries):
  establish combination support. [Named-event lookup](./skills/workiq-preview/references/calendar-read-work-iq.md#named-event-lookup)
  uses a bounded view and local matching unless another supported contract applies.

Shared output/query safeguards are always loaded. Known recipes need no discovery;
continuation/cap handling and URL comparison load the corresponding fetch
mechanics before use. Offline checks cover owner reachability, operative
polarity and the unchanged upstream loading ceilings, including negative
fixtures. Commands and the sanitized acceptance catalog are documented in
[CONTRIBUTING.md](../../CONTRIBUTING.md). These do not establish actual host
loading, model compliance or native citation-event emission.

### Business Applications and SharePoint

- [Business Applications](./skills/workiq-preview/references/business-applications.md)
  discovers concrete environments, resources and operations. The
  [action leaf](./skills/workiq-preview/references/business-applications-actions.md)
  requires mutation prerequisites; missing named capabilities do not authorize
  execute-work, and read access does not establish write/customization privilege.
- [SharePoint sites](./skills/workiq-preview/references/sharepoint-sites-work-iq.md)
  resolves supplied sites and group-backed libraries using returned IDs.
  [Structured search](./skills/workiq-preview/references/sharepoint-search-work-iq.md)
  is for explicitly requested listings/searches, not a replacement for ordinary
  preview retrieval. The [page leaf](./skills/workiq-preview/references/sharepoint-page-work-iq.md)
  handles explicitly named site-page downloads with driveItem identity.
- [Library metadata](./skills/workiq-preview/references/sharepoint-library-metadata.md)
  reads actual columns and checks the requested population and count coverage.
  Mixed column/content requests use structured fields plus local synthesis,
  not implicit ask delegation. Explicit denial remains terminal on every route.

These are adapted guidance, not new backend capabilities or live validation.

## Package identity and host bindings

Use the reviewed repository source commit and plugin version, not a hand-vendored
version label alone. Capture a deterministic package SHA-256 and per-file hashes:

```bash
node scripts/workiq-preview-provenance.mjs
```

Run from a checkout of the approved revision. The command only reads local files
and Git; it does not install, publish or connect to Microsoft 365. The digest
covers the skill/references, README, three host manifests and MCP configuration.
A dirty-package flag means it is not an immutable release identity. Preserve
the output with run evidence outside the plugin; do not embed a self-referential
digest into the hashed package. Pin the approved source/version/hash through the
normal sync process, recording any adaptation diff.

The digest covers actual local skill-tree bytes, including ignored/untracked
files. `package_worktree_dirty` is Git's ordinary status summary, which excludes
ignored files; false is not approval or proof of release identity. Extra local
files can change the digest while Git remains clean. Compare the full digest
and file inventory against the approved artifact, not that Boolean alone.

Copilot, Claude and Codex manifests point to `./skills/`; the bundled MCP
configuration names `workiq-preview`. Use each host's supported loader/connector
and resolve exact advertised tool names from its connected catalog. Do not infer
tool prefixes, rewrite server-identity policy to fit a harness, or silently bind
stable tools. Matching manifests are not proof of actual host loading.

For each approved run, record host/build, intended and actually loaded file
hashes, effective MCP identity/binding, tool/schema and effective instruction
hashes, and any binding/adaptation differences. Record listing/frontmatter,
core-body and reference exposure separately, including project/server guidance;
an absent explicit skill invocation does not prove an unguided run. Unobservable
exposure is unknown. Description-only and forced-load comparisons require a
controlled design and separate model/budget approval; publication, plugin
installation and real host validation also remain separate actions. Never store
credentials, credential-bearing URLs or raw business content in provenance.

## Installation

Use the selected host's plugin/skill loader and MCP connection mechanism. This
package includes `.github/plugin/plugin.json`, `.claude-plugin/plugin.json`, and
`.codex-plugin/plugin.json`; see [installation by host](../../PLUGINS.md#installation-by-host).
The shared skill policy is the same across hosts. Connecting MCP tools alone
does not automatically load the bundled instructions.

### Via GitHub Copilot CLI Plugin Marketplace

Run from the repository root:

```bash
copilot plugin install ./plugins/workiq-preview
```

Restart your Copilot CLI session after installation to load the skill.
Alternatively, register this checkout with `/plugin marketplace add .`, then
install:

```bash
/plugin install workiq-preview@work-iq-skills
```

### Bundled hosted MCP configuration

The bundled `.mcp.json` uses the configuration below. Apply it through your host's
supported remote-MCP connector; configuration wrappers and OAuth fields are
host-specific and should not be copied blindly between clients.

```json
{
  "mcpServers": {
    "workiq-preview": {
      "type": "http",
      "url": "https://workiq.svc.cloud.microsoft/mcp",
      "oauthClientId": "ba081686-5d24-4bc6-a0d6-d034ecffed87",
      "oauthPublicClient": true,
      "auth": {
        "redirectPort": 12798
      }
    }
  }
}
```

The plugin connects to the hosted WorkIQ MCP prod endpoint. It does **not** launch a local MCP server for tool calls.

## Updating

The MCP tool surface is served by the hosted WorkIQ endpoint above, so updating a local package is not required for MCP tool calls.
To update skill policy, reinstall/reload the plugin using the selected host's
mechanism and start a fresh session where required. Record loading and behavioral
validation per host; a Copilot CLI check does not validate other agents.

## Usage

The plugin exposes the WorkIQ MCP tool surface — read **and** write — from `https://workiq.svc.cloud.microsoft/mcp`.

### Gather work context (`retrieve`, preview)

Use `retrieve` first for workplace questions, summaries, comparisons, and implementation context the calling agent will answer itself. It returns hits and grounding `markdown` with citations and source metadata. Question wording or a request to summarize does not imply delegation.

| Strategy | When to use |
|----------|-------------|
| `grounding` (API default) | The answer is known to be in indexed M365 content, such as SharePoint, OneDrive, Teams or Outlook. |
| `copilot` | The source is unknown, connected enterprise sources might be needed, or broader retrieval is explicitly requested. Start here directly within the authorized source scope, without a Grounding probe. |

Send `strategy` explicitly, even though omission defaults to `grounding`.
Both strategies return evidence, not an `ask` answer: `copilot` strategy is still
caller-owned retrieval, not delegation. `GraphConnectors` requires `copilot`;
never silently drop a required source or broaden an explicit Grounding-only scope.
Dataverse and Power BI are roadmap sources, not currently supported retrieval
sources, even if a Dataverse capability appears in the schema. Disclose that
limitation rather than claiming support.

Follow the [published retrieval contract](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/work-iq/mcp/retrieve)
and discover the connected tool's current schema for argument shapes.

**Availability is tenant-dependent.** Discover the actual tool and schema; installing this plugin does not enable preview retrieval. If absent or unable to select a required strategy, disclose the limitation. No automatic `ask` fallback: the user must select delegated answering as an alternative. Exact entity operations remain on entity tools. Never bypass an access/policy denial.

Synthesize sufficient evidence locally. Empty results, caps, errors, and timeouts do not automatically justify broader retrieval. At most one targeted broader escalation per objective is allowed for a concrete missing source within the user's scope; no repeated strategy switching or final `ask` resynthesis.

```
"Gather work context and design decisions to ground my Project X implementation"
"Find Project X evidence across our connected enterprise sources"
"Gather Project X rollout context from indexed SharePoint, email, and Teams content"
```

See the [retrieve reference](./skills/workiq-preview/references/retrieve-work-iq.md) for parameters, capability filters, citations, and bounded recovery.

### Intentional agent delegation (`ask`, `list_agents`)

Use `ask` when the user explicitly requests Copilot's or a specific agent's answer. Default Copilot needs no retrieval or discovery preflight. For a named agent, reuse its known ID or discover it with `list_agents`; resolve ambiguity without silently substituting Copilot. Attribute the answer and reuse the returned `conversationId` only for an appropriate continuation with the same agent.

```
"Ask Microsoft 365 Copilot what is blocking Project Aurora"
"Ask the release-readiness agent whether Aurora is ready to ship"
"Ask that same agent which of those blockers is most urgent"
```

### Structured reads (`fetch`, `search_paths`, `get_schema`, `fetch_blob`)

```
"List my unread emails from Sarah this week"
"What meetings do I have Monday?"
"Show me the channels in the DevX team"
"List files in my OneDrive 'Specs' folder"
"Who are Rob's direct reports?"
```

### Writes (`create_entity`, `update_entity`, `delete_entity`, `do_action`)

> ⚠️ Mutations require specific confirmation, including persisted drafts and read-state changes. A read-only action such as free/busy is not a mutation merely because it uses `do_action`. The skill preserves the intended action, executes once, and reports completed, accepted/pending, blocked, awaiting confirmation, or unknown outcomes from actual evidence.

```
"Send the draft email to the engineering distribution list"
"Create a calendar event Friday at 3pm with the design team"
"Accept the 2pm meeting from Rob"
"Decline the Monday standup — I'll catch up on the recording"
"Mark Sarah's last three emails as read"
"Reply to the deadline thread with 'on track for Friday'"
"Move the design review thread to the Archive folder"
```

`fetch_blob` downloads binary content up to 4 MB and returns it base64-encoded with metadata.

File objects at `workiq://file/{id}`, `/api/beta/files/{id}` or `/api/files/{id}`, and WorkIQ `file-transfer` client actions use the skill's [Files CLI reference](./skills/workiq-preview/references/workiq-files-cli.md). The CLI requires Node.js 20+; installing the plugin does not install it or accept its terms. EULA acceptance requires explicit user permission.

> ⚠️ `upload_blob` is not released. Creating an upload session is supported separately from sending bytes: “session created; no bytes uploaded” is not “file replaced.”

### Building or publishing an M365 Copilot agent or plugin

WorkIQ Preview handles Microsoft 365 **data**, not the agent/plugin development
lifecycle. Requests such as "create a declarative agent", "validate my agent",
or "publish my M365 plugin" are handed off to **Work IQ Dev Tools (WIQD)**.

> **Preview:** WIQD is experimental, not production-ready, and not officially
> supported. Expect breaking changes.

The skill checks loaded skills and installed plugins first. If WIQD is missing,
it asks for explicit confirmation before installing from `awesome-copilot`:

```bash
copilot plugin install wiqd@awesome-copilot
```

`awesome-copilot` (`github/awesome-copilot`) is included by default in Copilot CLI.
If it is not registered, the skill asks for approval before adding it with
`copilot plugin marketplace add github/awesome-copilot`.

Restart your Copilot CLI session after installation, then re-send your original
request so the `wiqd` skill can guide setup and the lifecycle.
See the [handoff reference](./skills/workiq-preview/references/wiqd.md).
Other hosts use their supported plugin managers; Copilot CLI installation
does not install WIQD into another host.

## Skills

The skill opens with a compact dispatcher. Read the applicable canonical contract:
[files](./skills/workiq-preview/references/files-work-iq.md),
[calendar](./skills/workiq-preview/references/calendar-work-iq.md),
[mail](./skills/workiq-preview/references/mail-work-iq.md),
[Teams](./skills/workiq-preview/references/teams-work-iq.md), or
[agents](./skills/workiq-preview/references/agents-work-iq.md).
The [targeted workflows guide](./skills/workiq-preview/references/workflows-work-iq.md) dispatches
setup, people, and cross-domain sequencing; it is not a universal preflight.
[Troubleshooting](./skills/workiq-preview/references/troubleshooting.md)
owns operation-aware recovery.

| Skill | Description |
|-------|-------------|
| [**workiq-preview**](./skills/workiq-preview/SKILL.md) | Retrieve-first context with source-based strategy selection; intentional agent delegation; exact reads/writes and Graph downloads on entity tools; WorkIQ files API transfers via Files CLI |

## Platform Support

Supported on `win_x64`, `win_arm64`, `linux_x64`, `linux_arm64`, `osx_x64`, and `osx_arm64`.

## License

See the root [LICENSE](../../LICENSE) file.
