# Copilot Pages creation and editing

## Required before use

- [Mutation safeguards](mutation-work-iq.md)
- [Action contract](do-action-work-iq.md)

## Intent and availability

Use the Pages provider to create a shareable Microsoft 365 Copilot Page / Loop
page, or edit an existing grounded Page in place. A request to put content into
a Loop page or draft a shareable Copilot Page belongs here. Suggested text in
chat is not persisted Page creation. Clarify an ambiguous "page" before writing.
Word, Excel and PowerPoint artifacts use [Office artifacts](office-artifacts-work-iq.md);
downloading a named SharePoint site-page file uses
[site-page download](sharepoint-page-work-iq.md). Do not substitute these routes.

The source provider is disabled with an empty tenant allowlist. Installing this
skill does not enable it or prove authorization or backend connectivity.
For an unavailable or unfamiliar connected action, establish support with
`search_paths` and the action schema (`get_schema`, `operationType: "action"`).
Do not probe availability with a write or call the AugLoop backend directly.
Explicit denial stops without switching tools, persistence paths or providers.

## Action contracts

Use WorkIQ `do_action` on these virtual catalog paths:

| Intent | actionUrl | Required jsonBody fields |
| --- | --- | --- |
| Create a new Page | `/pages/create_page` | `userRequest` |
| Edit an existing Page in place | `/pages/edit_page` | `userRequest`, `artifactUrl` |

`userRequest` is a non-empty string containing the user's creation request,
topic and content requirements, or their requested edits. The workflow generates
the Page content; do not require a caller-supplied artifact filename or import
the Office artifact `taskDescription` / `appName` contract. These are not Pages
request fields. Do not invent conversation IDs, sensitivity labels, message
annotations, entity keys, page IDs or other app metadata.

For editing, copy the exact existing Page URL from the user or grounded search
results into `artifactUrl`. Preserve the complete URL unchanged, including its
encoding and query parameters. Do not reconstruct or invent it, use a local path
or generated filename, or put the target URL only in `userRequest`.
If the Page URL is not grounded, obtain it before calling; do not create a
replacement Page. `artifactUrl` identifies the existing target, not an output.

Resolve the exact target and requested effects, prepare the content or edits,
then obtain required approval under the mutation prerequisites. Prior approval
must still apply; changed target, scope or content requires renewed confirmation.
An edit modifies the existing Page in place. Declined approval or failed target
validation stops without retry or another persistence path.

After applicable approval, a creation example is:

```json
{
  "actionUrl": "/pages/create_page",
  "jsonBody": {
    "userRequest": "Create a Copilot Page with a planning agenda to review open questions and agree next steps."
  }
}
```

The edit example is a template: replace `artifactUrl` with the complete verbatim
grounded Page URL, never send the placeholder or invent a demonstration URL.
Derive `userRequest` from the actual approved edits, not this example:

```json
{
  "actionUrl": "/pages/edit_page",
  "jsonBody": {
    "userRequest": "Add a Next steps section listing the agreed follow-up actions; preserve all other content.",
    "artifactUrl": "{verbatimExistingPageUrl}"
  }
}
```

## Outcomes and bounded recovery

Call once for each distinct creation request and once for the final edit.
These writes are non-idempotent. A slow call, timeout, transport failure or
ambiguous response does not authorize replay. A 202 is accepted/pending, not
completion; HTTP success alone does not establish a successful Page workflow.
Inspect the full MCP result and any nested errors before reporting success.

Creation must return a Microsoft 365 Copilot Page (`.page`) `resource_link`.
An `.html` link or a local/SharePoint file path is an incorrect result: the
Copilot Page workflow did not run. Do not present it as a created Page, rename
its extension or fabricate a `.page` URL. Share the actual returned Page link
so the user can open and collaborate on it; preserve response metadata.

For editing, any returned `resource_link` must also identify a Copilot Page
(`.page`), not HTML or a local/SharePoint file path. A confirmed successful
in-place edit may return no new link; report the confirmed update without
inventing one. An unexplained empty/null result is not confirmed edit success.

Before any recovery, read [recovery](troubleshooting.md).
For creation, do not retry after a write attempt unless the tool explicitly
instructs recovery and retry, and the retry is demonstrably safe and authorized;
never replay an ambiguous write.
For editing, only an explicitly reported concurrent-edit conflict permits
recovery: fetch the latest Page through a supported read, regenerate the edit,
obtain renewed approval if content or scope changes, then retry once with the
same verbatim `artifactUrl`. If no supported latest-Page read is available,
stop and disclose the limitation; do not invent a `/pages/` read endpoint.
Do not retry other edit failures or exceed the one conflict retry.
For an ambiguous outcome, reconcile only through a supported safe read or
report outcome unknown. Do not invent a status or polling endpoint.

## Provider source

Aligned to the provider's
[OpenAPI specification](https://o365exchange.visualstudio.com/O365%20Core/_git/work-iq-ecosys?path=%2Fsources%2Fdev%2FProviders%2FConfig%2Fpages%2Fpages.spec.yaml&version=GC3cb555deed5aa7559b6f980a342b7e65d6a289dc&_a=contents)
and [provider README](https://o365exchange.visualstudio.com/O365%20Core/_git/work-iq-ecosys?path=%2Fsources%2Fdev%2FProviders%2FConfig%2Fpages%2FREADME.md&version=GC3cb555deed5aa7559b6f980a342b7e65d6a289dc&_a=contents)
at `3cb555deed5aa7559b6f980a342b7e65d6a289dc`. Offline checks do not establish
deployment, provider enablement or observed model behavior.
