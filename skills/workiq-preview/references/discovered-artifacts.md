# Downloading discovered artifacts

After selecting a `discover` entry, inspect references at every nesting level.
Download its required supported WorkIQ guidance bundles before source queries
or drafting; an inline summary does not replace an original or companion.
Do not download unrelated entries.

## Download and read

The helper accepts exact HTTPS URLs on `workiq.svc.cloud.microsoft` or
`test.workiq.svc.cloud.dev.microsoft`, with either
`/api/catalogs/artifact-references/{reference}` or
`/api/catalogs/{catalog}/artifacts/{artifact}`. Pass the exact returned URL,
including its query; only `type` and `version` query parameters are supported.
Do not reconstruct IDs, rewrite origins, add routing headers or discard an
unsupported query parameter. Other required references need a known authorized
reader; otherwise disclose the missing guidance and stop dependent work.

Set `$skillRoot` to the actual installed directory containing this `SKILL.md`
and `$artifactUrl` to the selected exact reference. Use PowerShell 7.2+ and a
fresh temporary directory outside the installed skill and checkout:

```powershell
$workDir = Join-Path ([IO.Path]::GetTempPath()) ("workiq-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir -ErrorAction Stop | Out-Null
$outPath = Join-Path $workDir 'artifact.zip'
$downloader = Join-Path $skillRoot 'scripts\download-discovered-artifact.ps1'
& $downloader -ReferenceUrl $artifactUrl -OutFile $outPath -NonInteractive
```

Equivalent invocations from default platform shells:

```bash
# macOS, Linux or WSL.
"$skillRoot/scripts/download-discovered-artifact.sh" \
  -ReferenceUrl "$artifactUrl" -OutFile "$outPath" -NonInteractive
```

```batch
rem Windows Command Prompt
call "%skillRoot%\scripts\download-discovered-artifact.cmd" -ReferenceUrl "%artifactUrl%" -OutFile "%outPath%" -NonInteractive
```

Verify the JSON result has `state: completed`, `contentType: application/zip`
and an existing local `path`. It also reports `bytesWritten` and `sha256`, not
the reference URL, token or artifact bytes. Use the host-approved archive
extractor with its normal safety policy and a fresh destination:

```powershell
Expand-Archive -LiteralPath $outPath -DestinationPath (Join-Path $workDir 'artifact') -ErrorAction Stop
```

Honor any additional archive validation required by the host; do not bypass
its restrictions. If extraction is unavailable, rejected or fails, disclose
the gap and stop dependent work. Read the extracted `SKILL.md` and its required
references before source queries or drafting. Do not execute downloaded scripts,
install plugins or render active content. Keep artifacts outside the installed
skill; remove only this request's known temporary files when no longer needed.

The helper validates the WorkIQ URL, blocks redirects and content encodings,
streams to a staging file, verifies declared length and reports a hash. It does
not validate ZIP content, archive entries or extraction resource limits. On
failure it removes its own staging file and leaves any existing destination
untouched. Existing destinations require intentional `-Overwrite`; do not use
it just to retry.

## Runtime and authentication

PowerShell 7.2+ (`pwsh`) is required on Windows, macOS, Linux and WSL. The `.cmd`
and `.sh` wrappers invoke the same PowerShell implementation. No packages are
installed. Scripts are bundled under `scripts/` beside this skill's `SKILL.md`;
do not assume they are on `PATH`.

The helper is separate from the host's MCP authentication. It uses, in order,
an explicitly supplied `-AccessToken`, `WORKIQ_ACCESS_TOKEN`, or a cached
credential refreshed through Microsoft identity. Use only a credential already
authorized for the intended WorkIQ account and environment; the helper does not
verify that its account matches the MCP session. If that binding is unknown,
stop and ask the user to establish it. Never inspect another account's token
store, extract a token from the host, or print/log credentials.

Agent-driven examples must use `-NonInteractive`. It prevents browser/device-code
login, but can refresh the helper's existing cached credential. Missing usable
credentials returns `AUTH_REQUIRED`; do not respond by retrying without this
flag. Interactive setup requires explicit user direction and should be run by
the user in a terminal:

```powershell
# Only for user-directed authentication; never an automatic retry.
& $downloader -ReferenceUrl $artifactUrl -OutFile $outPath -DeviceCode
```

Without `-NonInteractive` or `-DeviceCode`, browser sign-in uses a loopback
callback and may fall back to device code. Refresh tokens are saved through
Windows DPAPI, macOS Keychain or Linux Secret Service when available; the helper
warns if saving fails. No plaintext credential cache is created. `-Logout`
removes only this helper's cached credential and likewise requires explicit
direction; it does not sign out the MCP connection.

`-Environment Test` explicitly maps a validated production reference to the test
origin and adds the test endpoint header. Never select it automatically or
change environments after a denial. Default requests preserve the returned
origin, path and query; an already returned test URL uses the test endpoint.

## Failure handling

`REFERENCE_EXPIRED` (HTTP 404) allows one fresh `discover` lookup and one download
with its newly returned reference. Authentication/access rejection, redirects,
unsupported references, unsafe archives and incomplete responses are not
permission to change accounts, environments or download mechanisms. Disclose
the concrete limitation and stop dependent execution. Any answer supported
independently of missing required guidance must be labelled partial.

These are catalog guidance bundles, not OneDrive/SharePoint documents. Ordinary
file and attachment downloads continue through their existing
[fetch_blob contract](fetch-blob-work-iq.md); the helper is not a way around its
size limits or an access denial.
