# Office artifact creation and editing

## Required before use

- [Mutation safeguards](mutation-work-iq.md)
- [Action contract](do-action-work-iq.md)

## Intent

Use the Office Agent provider for a requested new Word document, Excel workbook
or PowerPoint presentation, or content changes to an existing one. Finding,
reading, downloading, renaming, moving and uploading files remain on their
existing files routes. Writing suggested text in chat is not artifact creation.
This is not the WIQD agent/plugin lifecycle route or implicit ask delegation.

## Availability and action paths

The provider defines these virtual catalog actions, not Graph resources or
AugLoop REST endpoints. Use WorkIQ `do_action`; do not call the backend directly.

| Intent | actionUrl | Required jsonBody fields |
| --- | --- | --- |
| Create a new artifact | `/office-agent-mcp/generate_artifact` | `taskDescription`, `appName` |
| Edit an existing artifact in place | `/office-agent-mcp/edit_artifact` | `taskDescription`, `appName`, `artifactUrl` |

`appName` is exactly `Word`, `Excel` or `PowerPoint`, matching the requested
artifact. `userRequest` is optional for both actions. No other request fields
are authored; do not add Graph wrappers, file bytes, output paths, conversation
IDs, locale, flights or sensitivity labels to `jsonBody`. Caller metadata
forwarding requires separately established platform support.

The source configuration is disabled with an empty tenant allowlist in every
ring. Installing this skill does not enable the provider or establish backend
access. For an unavailable or unfamiliar connected action, use `search_paths`
and its action schema (`get_schema`, `operationType: "action"`) to establish
support, not a mutation probe. Explicit access, policy or privilege denial stops;
do not bypass it with another provider, agent, plugin or direct backend call.
Do not use a mutation to test availability or claim rollout from this guidance.

## Prepare content and approval

Gather the requested source facts with the appropriate read/retrieval routes
before composing the artifact. Do not send unsupported assertions to the
generator as facts. Clarify a missing essential fact or accurately state the
limitation; do not invent values or insert placeholder tokens.

For `generate_artifact`, `taskDescription` must include the document type,
purpose and audience, followed by a full Markdown outline. Supply `#`/`##`/`###`
headings for every section and subsection, bullet lists, Markdown tables for
tabular content and fenced blocks where needed. Under each heading supply the
actual final prose, bullets and numbers, not instructions to decide the content.
End with formatting and styling preferences. Do not delegate structure decisions
to the generator or use bracketed fill-ins, TODOs or TBDs.

For `edit_artifact`, supply a complete Markdown outline of the intended changes:
identify the document type and the exact sections to add, remove or update.
For added or updated sections, include the actual final content under each
heading. For removed sections, do not provide replacement content; identify the
exact heading/section to delete and clearly mark it as a removal. End with
formatting and styling preferences. Preserve the requested edit scope and
unrelated content. Do not turn an edit into new artifact creation.

Keep the user's framing and grammatical person, including first-person
self-reviews. If supplied, `userRequest` is the concise effective user request,
separate from the full outline. Preserve intent, constraints and relevant
refinements; merge valid editing instructions unless replaced, reversed or
cancelled. Ignore unrelated remarks and acknowledgments, not valid instructions
in the same turn. Do not invent requirements.

Editing requires the exact existing artifact URL from the user or an
authoritative result. Copy `artifactUrl` verbatim; never reconstruct, re-encode,
shorten or correct any character, including tenant, personal path or filename.
Resolve ambiguity before editing, not by choosing a similar file.

Before either action, apply the mutation prerequisites and obtain required
approval for the prepared content and effects. Editing changes the referenced
file in place; creation produces a new artifact. Reconfirm changed scope,
target or content; a request for suggestions alone does not approve persistence.

For example, after applicable approval, this creation request has final content
rather than an outline placeholder; derive real requests from the user's task:

```json
{
  "actionUrl": "/office-agent-mcp/generate_artifact",
  "jsonBody": {
    "appName": "Word",
    "taskDescription": "Word document. Purpose: record the agreed agenda. Audience: meeting attendees.\n# Planning agenda\n## Topics\n- Review open questions.\n- Agree next steps.\n## Desired outcome\nAn agreed list of next steps.\nFormatting: use a simple heading hierarchy and readable body text.",
    "userRequest": "Create a Word document with an agenda to review open questions and agree next steps."
  }
}
```

An edit uses the edit action, its change outline and the additional verbatim
`artifactUrl`; it does not use a Graph update body or a generated replacement URL.
There is no `/office-agent-mcp/upload_artifact` action in this provider.

## Execute once and inspect the result

Both POST actions are non-idempotent. Execute the approved action once. The
provider has a 30-minute timeout budget; a slow or interrupted call is not
permission to replay. Before any recovery, load [recovery](troubleshooting.md).
After an ambiguous timeout or transport failure, use only a supported safe read
to reconcile or report outcome unknown; do not automatically recreate or re-edit.
Do not invent a status or polling endpoint. A 202 is accepted/pending, not done.

HTTP success alone is not artifact success. Inspect the complete tool result:
`isMcpError: true` independently means failure even on HTTP 200, including when
no details are present. When provided, preserve `errorDetails` without claiming
creation or editing. Missing final output is unresolved, not success.

Successful results contain a `content` block with `type: "resource_link"`.
Return its actual `uri` and readable `name`, retaining `mimeType`, description
and response metadata, including `_meta.sensitivityLabel` when present. Never
fabricate a shareable URL or strip sensitivity information. A returned artifact
link establishes the reported creation/edit result, not independent verification
of every content or formatting requirement. For requested inspection, follow
the [content reader](files-content-work-iq.md) and disclose reader limitations.

## Provider source

Aligned to the provider's
[OpenAPI specification](https://o365exchange.visualstudio.com/O365%20Core/_git/work-iq-ecosys?path=%2Fsources%2Fdev%2FProviders%2FConfig%2Foffice-agent-mcp%2Foffice-agent-mcp.spec.yaml&version=GC3cb555deed5aa7559b6f980a342b7e65d6a289dc&_a=contents)
and [provider README](https://o365exchange.visualstudio.com/O365%20Core/_git/work-iq-ecosys?path=%2Fsources%2Fdev%2FProviders%2FConfig%2Foffice-agent-mcp%2FREADME.md&version=GC3cb555deed5aa7559b6f980a342b7e65d6a289dc&_a=contents)
at `3cb555deed5aa7559b6f980a342b7e65d6a289dc`. Offline checks do not establish
provider deployment, authorization, connectivity or observed model behavior.
