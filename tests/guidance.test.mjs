import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { loadRoute, scenarioProblems } from '../../../tests/workiq-guidance/loading-contract.mjs';

const skill = new URL('../skills/workiq-preview/', import.meta.url);
const read = file => fs.readFileSync(new URL(file, skill), 'utf8');
const plain = text => text.replace(/[*`]/g, '').replace(/\s+/g, ' ');
const load = (id, options) => loadRoute(fileURLToPath(skill), id, options);
const retrieval = read('references/retrieve-work-iq.md');
const details = read('references/retrieve-details-work-iq.md');
const examples = [...details.matchAll(/```json\s*\n([\s\S]*?)```/g)]
  .map(match => JSON.parse(match[1]));

test('Pages load their own action safeguards without changing Office or site-page routes', () => {
  const scenario = { id: 'pages', owner: () => 'references/pages-work-iq.md',
    required: ['references/files-work-iq.md', 'references/mutation-work-iq.md',
      'references/do-action-work-iq.md'], limit: 20000 };
  assert.deepEqual(scenarioProblems('workiq-preview', scenario, load(scenario.id)), []);
  for (const dependency of ['Mutation safeguards', 'Action contract']) {
    const incomplete = load(scenario.id, {
      read: file => read(file).replace(new RegExp(`^- \\[${dependency}\\].*\\n`, 'm'), ''),
    });
    assert.ok(scenarioProblems('workiq-preview', scenario, incomplete)
      .some(error => error.includes('required owner/prerequisite')));
  }
  for (const id of ['office-artifacts', 'sharepoint-page', 'files-read', 'files-download',
    'files-cli', 'wiqd', 'semantic-context', 'delegation']) {
    assert.ok(!load(id).files.includes('references/pages-work-iq.md'), id);
  }
  assert.ok(!load('pages').files.includes('references/office-artifacts-work-iq.md'));
  assert.ok(!load('pages').files.includes('references/sharepoint-page-work-iq.md'));
  assert.match(read('SKILL.md'), /Office\/Loop Pages creation\/editing/);
});

test('Pages examples use distinct minimal create and edit action bodies', () => {
  const guide = read('references/pages-work-iq.md');
  assert.match(guide, /Use WorkIQ `do_action` on these virtual catalog paths/);
  assert.match(guide, /\| Create a new Page \| `\/pages\/create_page` \| `userRequest` \|/);
  assert.match(guide, /\| Edit an existing Page in place \| `\/pages\/edit_page` \| `userRequest`, `artifactUrl` \|/);
  const requests = [...guide.matchAll(/```json\s*\n([\s\S]*?)```/g)].map(match => JSON.parse(match[1]));
  assert.equal(requests.length, 2);
  assert.equal(requests[0].actionUrl, '/pages/create_page');
  assert.deepEqual(Object.keys(requests[0].jsonBody), ['userRequest']);
  assert.equal(requests[1].actionUrl, '/pages/edit_page');
  assert.deepEqual(Object.keys(requests[1].jsonBody).sort(), ['artifactUrl', 'userRequest']);
  for (const request of requests) {
    assert.equal(typeof request.jsonBody.userRequest, 'string');
    assert.ok(request.jsonBody.userRequest.trim());
    assert.ok(!('appName' in request.jsonBody));
    assert.ok(!('taskDescription' in request.jsonBody));
  }
  assert.equal(requests[1].jsonBody.artifactUrl, '{verbatimExistingPageUrl}');
  assert.match(plain(guide), /never send the placeholder or invent a demonstration URL/);
  assert.match(plain(guide), /do not require a caller-supplied artifact filename/);
});

test('Pages edit identity and success rules distinguish confirmed edits from creation', () => {
  const body = plain(read('references/pages-work-iq.md'));
  const rules = [
    /Preserve the complete URL unchanged, including its encoding and query parameters/,
    /or put the target URL only in userRequest/,
    /If the Page URL is not grounded, obtain it before calling; do not create a replacement Page/,
    /Declined approval or failed target validation stops without retry or another persistence path/,
    /Creation must return a Microsoft 365 Copilot Page \(\.page\) resource_link/,
    /An \.html link or a local\/SharePoint file path is an incorrect result/,
    /A confirmed successful in-place edit may return no new link; report the confirmed update without inventing one/,
    /An unexplained empty\/null result is not confirmed edit success/,
  ];
  for (const rule of rules) assert.match(body, rule);
  assert.doesNotMatch(body.replace('Preserve the complete URL unchanged', 'Normalize the complete URL'), rules[0]);
  assert.doesNotMatch(body.replace('is an incorrect result', 'is a correct result'), rules[5]);
  assert.doesNotMatch(body.replace('is not confirmed edit success', 'is confirmed edit success'), rules[7]);
});

test('Pages recovery allows only its bounded conflict retry, never ambiguous write replay', () => {
  const body = plain(read('references/pages-work-iq.md'));
  const rules = [
    /source provider is disabled with an empty tenant allowlist/,
    /Explicit denial stops without switching tools, persistence paths or providers/,
    /do not retry after a write attempt unless the tool explicitly instructs recovery and retry/,
    /never replay an ambiguous write/,
    /only an explicitly reported concurrent-edit conflict permits recovery/,
    /fetch the latest Page through a supported read, regenerate the edit/,
    /obtain renewed approval if content or scope changes/,
    /retry once with the same verbatim artifactUrl/,
    /If no supported latest-Page read is available, stop/,
    /Do not retry other edit failures or exceed the one conflict retry/,
  ];
  for (const rule of rules) assert.match(body, rule);
  assert.doesNotMatch(body.replace('only an explicitly reported concurrent-edit conflict', 'any error'), rules[4]);
  assert.doesNotMatch(body.replace('retry once with the same verbatim', 'retry repeatedly with a new'), rules[7]);
});

test('Office artifact actions load their own mutation and action prerequisites', () => {
  const scenario = { id: 'office-artifacts', owner: () => 'references/office-artifacts-work-iq.md',
    required: ['references/files-work-iq.md', 'references/mutation-work-iq.md',
      'references/do-action-work-iq.md'], limit: 20000 };
  const route = load(scenario.id);
  assert.deepEqual(scenarioProblems('workiq-preview', scenario, route), []);
  for (const dependency of ['Mutation safeguards', 'Action contract']) {
    const incomplete = load(scenario.id, {
      read: file => read(file).replace(new RegExp(`^- \\[${dependency}\\].*\\n`, 'm'), ''),
    });
    assert.ok(scenarioProblems('workiq-preview', scenario, incomplete)
      .some(error => error.includes('required owner/prerequisite')));
  }
  for (const id of ['files-read', 'files-download', 'files-cli', 'wiqd', 'semantic-context', 'delegation']) {
    assert.ok(!load(id).files.includes('references/office-artifacts-work-iq.md'), id);
  }
  assert.match(read('references/files-work-iq.md'),
    /\| office-artifacts \| Create\/edit Word, Excel, PowerPoint content \|/);
});

test('Office artifact guidance maps creation and in-place editing to distinct action bodies', () => {
  const guide = read('references/office-artifacts-work-iq.md');
  assert.match(guide, /Use WorkIQ `do_action`; do not call the backend directly/);
  assert.match(guide, /\| Create a new artifact \| `\/office-agent-mcp\/generate_artifact` \| `taskDescription`, `appName` \|/);
  assert.match(guide, /\| Edit an existing artifact in place \| `\/office-agent-mcp\/edit_artifact` \| `taskDescription`, `appName`, `artifactUrl` \|/);
  assert.match(guide, /`appName` is exactly `Word`, `Excel` or `PowerPoint`/);
  assert.match(guide, /`userRequest` is optional for both actions/);
  assert.match(plain(guide), /No other request fields are authored/);
  assert.match(guide, /There is no `\/office-agent-mcp\/upload_artifact` action/);
  const requests = [...guide.matchAll(/```json\s*\n([\s\S]*?)```/g)].map(match => JSON.parse(match[1]));
  assert.equal(requests.length, 1);
  const request = requests[0];
  assert.equal(request.actionUrl, '/office-agent-mcp/generate_artifact');
  assert.deepEqual(Object.keys(request.jsonBody).sort(), ['appName', 'taskDescription', 'userRequest']);
  assert.equal(request.jsonBody.appName, 'Word');
  assert.match(request.jsonBody.taskDescription, /\n# Planning agenda\n## Topics\n- Review open questions/);
  assert.doesNotMatch(request.jsonBody.taskDescription, /\{|\[|TODO|TBD/);
});

test('Office artifact preparation preserves final content, edit identity and approval', () => {
  const body = plain(read('references/office-artifacts-work-iq.md'));
  const rules = [
    /Do not send unsupported assertions to the generator as facts/,
    /full Markdown outline/,
    /actual final prose, bullets and numbers/,
    /Do not delegate structure decisions/,
    /complete Markdown outline of the intended changes/,
    /Preserve the requested edit scope and unrelated content/,
    /including first-person self-reviews/,
    /merge valid editing instructions unless replaced, reversed or cancelled/,
    /Copy artifactUrl verbatim; never reconstruct, re-encode, shorten or correct any character/,
    /obtain required approval for the prepared content and effects/,
    /Editing changes the referenced file in place/,
  ];
  for (const rule of rules) assert.match(body, rule);
  assert.doesNotMatch(body.replace('never reconstruct', 'freely reconstruct'), rules[8]);
  assert.doesNotMatch(body.replace('obtain required approval', 'skip required approval'), rules[9]);
  const editRules = [
    /For added or updated sections, include the actual final content under each heading/,
    /For removed sections, do not provide replacement content/,
    /identify the exact heading\/section to delete and clearly mark it as a removal/,
  ];
  for (const rule of editRules) assert.match(body, rule);
  assert.doesNotMatch(body.replace('do not provide replacement content', 'provide replacement content'),
    editRules[1]);
});

test('Office artifact outcomes reject false success, denial bypass and mutation replay', () => {
  const body = plain(read('references/office-artifacts-work-iq.md'));
  const rules = [
    /disabled with an empty tenant allowlist in every ring/,
    /Installing this skill does not enable the provider/,
    /Explicit access, policy or privilege denial stops/,
    /Both POST actions are non-idempotent/,
    /do not automatically recreate or re-edit/,
    /A 202 is accepted\/pending, not done/,
    /isMcpError: true independently means failure even on HTTP 200, including when no details are present/,
    /Missing final output is unresolved, not success/,
    /content block with type: "resource_link"/,
    /Return its actual uri and readable name/,
    /including _meta.sensitivityLabel when present/,
    /When provided, preserve errorDetails without claiming creation or editing/,
  ];
  for (const rule of rules) assert.match(body, rule);
  assert.doesNotMatch(body.replace('do not automatically recreate', 'automatically recreate'), rules[4]);
  assert.doesNotMatch(body.replace('independently means failure', 'means success'), rules[6]);
  assert.doesNotMatch(body.replace('including when no details are present', 'only when details are present'),
    rules[6]);
});

test('entrypoint delegates strategy selection without forcing grounding or ask', () => {
  const entry = read('SKILL.md');
  assert.match(entry, /grounding retrieve for known\s+indexed M365 content; otherwise select strategy in its reference/);
  assert.doesNotMatch(entry, /with explicit grounding retrieve,\s+then write the answer locally/);
  assert.match(entry, /Use ask only when the user requests Copilot or a named agent's answer/);
  for (const owner of ['teams-targets', 'tasks-contract']) {
    assert.match(read(`references/${owner}-work-iq.md`), /source-based strategy selection/);
  }
});

test('source scope selects strategy, including unknown sources without a probe', () => {
  const rules = [
    /\| Known indexed M365 content \| grounding \|/,
    /\| Unknown sources, possible connected\/external sources, mixed scope or explicit broader retrieval \| copilot directly, without a Grounding probe \|/,
    /\| Required GraphConnectors \| copilot \|/,
  ];
  for (const rule of rules) {
    assert.match(retrieval, rule);
    assert.doesNotMatch(retrieval.replace(/\| (grounding|copilot)(?= |\|)/g, '| ask'), rule);
  }
  assert.match(retrieval, /Grounding-only plus a required broader source \| Explain conflict/);
  assert.match(retrieval, /Both strategies return evidence, not an ask answer/);
  assert.match(read('references/retrieve-repair-work-iq.md'),
    /unknown-source first call uses copilot directly, not a Grounding probe/);
});

test('default, source support and error rules agree across retrieval guidance', () => {
  const owners = [retrieval, details, fs.readFileSync(new URL('../README.md', import.meta.url), 'utf8')];
  for (const text of owners) {
    const body = plain(text);
    assert.match(body, /(?:API default(?::| is)|omission defaults to) grounding/i);
    assert.doesNotMatch(body, /(?:default.{0,30}(?:remains|is)|omitted default is) copilot/i);
    assert.match(body, /Dataverse and Power BI are (?:unsupported )?roadmap sources/);
    assert.doesNotMatch(body, /TeamsMessages, Dataverse, GraphConnectors/);
  }
  assert.match(plain(retrieval), /isError true or stoppedReason error is failure, even with hits/);
  assert.match(details, /https:\/\/learn\.microsoft\.com\/en-us\/microsoft-365\/copilot\/extensibility\/work-iq\/mcp\/retrieve/);
});

test('source-based examples use actual retrieve shapes and preserve required capabilities', () => {
  assert.equal(examples.length, 3);
  for (const example of examples) assert.equal(typeof example.query, 'string');
  assert.equal(examples[0].strategy, 'copilot');
  assert.ok(!('capabilities' in examples[0]));
  assert.equal(examples[1].strategy, 'grounding');
  assert.deepEqual(examples[1].capabilities.map(item => item.name),
    ['OneDriveAndSharePoint', 'Email', 'TeamsMessages']);
  assert.equal(examples[2].strategy, 'copilot');
  assert.deepEqual(examples[2].capabilities, [{ name: 'GraphConnectors' }]);
  for (const request of ['What is the project status', 'Compare the two named proposals', 'Who owns the service']) {
    const row = retrieval.split('\n').find(line => line.includes(request));
    assert.match(row, /\| retrieve:/);
    assert.doesNotMatch(row, /retrieve with grounding:|\| ask:/);
  }
});

test('Graph batch boundary, provider grouping and successful siblings are operative', () => {
  const body = plain(read('references/fetch-work-iq.md'));
  const rules = [
    /Batch independent exact reads only within one provider/,
    /For Graph reads, use at most 50 URLs per entityUrls call/,
    /split larger sets into chunks of 50 or fewer/,
    /or a lower connected-contract limit/,
    /Mixed-provider batches fall back to the legacy Graph pipeline, not cross-provider aggregation/,
    /Do not probe larger batches/,
    /individual result status/,
    /Retain successful results/,
  ];
  for (const rule of rules) assert.match(body, rule);
  assert.doesNotMatch(body.replaceAll('50', '51'), rules[1]);
  assert.doesNotMatch(body.replace('only within', 'across'), rules[0]);
  assert.doesNotMatch(body.replace('Retain successful', 'Discard successful'), rules.at(-1));
});

test('attachment and delta contracts load only for their selected operations', () => {
  const scenario = { id: 'mail-attachments', owner: () => 'references/mail-attachments-work-iq.md',
    required: ['references/fetch-work-iq.md', 'references/fetch-blob-work-iq.md'], limit: 21000 };
  assert.deepEqual(scenarioProblems('workiq-preview', scenario, load(scenario.id)), []);
  assert.ok(!load('mail-read').files.includes('references/fetch-blob-work-iq.md'));
  assert.match(read('references/mail-read-work-iq.md'),
    /Before selecting or\s+downloading attachments, read \[attachments\]\(mail-attachments-work-iq\.md\)/);
  const missingBinary = load(scenario.id, {
    read: file => read(file).replace('- [Binary handling](fetch-blob-work-iq.md)', ''),
  });
  assert.ok(scenarioProblems('workiq-preview', scenario, missingBinary)
    .some(error => error.includes('required owner/prerequisite')));
  assert.ok(!load('teams-presence').files.includes('references/call-function-work-iq.md'));
  const deltaPrerequisite = /Before channel delta, read \[functions\]\(call-function-work-iq\.md\)/;
  const presence = read('references/teams-presence-work-iq.md');
  assert.match(presence, deltaPrerequisite);
  assert.doesNotMatch(presence.replace('Before channel delta, read', 'After channel delta, optionally read'),
    deltaPrerequisite);
});

test('domain batching links remain conditional prerequisites', () => {
  for (const owner of ['calendar-base', 'files-identity', 'mail-read',
    'sharepoint-library-metadata', 'teams-query-limits', 'teams-presence']) {
    const file = owner === 'sharepoint-library-metadata' ? `${owner}.md` : `${owner}-work-iq.md`;
    assert.match(read(`references/${file}`),
      /[Bb]efore batching[\s\S]{0,140}\(fetch-work-iq\.md#batches-paging-and-host-caps\)/, file);
  }
});

test('bounded Inbox recipe requires supported combinations, actual kinds and complete bytes', () => {
  const guide = read('references/mail-attachments-work-iq.md');
  const recipe = JSON.parse(guide.match(/```json\s*\n([\s\S]*?)```/)[1]);
  assert.deepEqual(recipe, { entityUrls: [
    '/me/mailFolders/inbox/messages?$filter=hasAttachments%20eq%20true&$top=10'
    + '&$select=id,subject,receivedDateTime,hasAttachments'
    + '&$expand=attachments($select=id,name,contentType,size,isInline)',
  ] });
  const body = plain(guide);
  for (const rule of [
    'not the newest attachment or a complete inventory',
    'connected contract supports this exact query combination',
    'disclose the limitation without probing variants',
    'Do not add $orderby, $skip or extra filters',
    'In returned order, choose the first message',
    'Skip reference/item attachments',
    'Missing kind or incomplete attachment data is unresolved',
    'do not follow @odata.nextLink, enumerate the mailbox',
    'Compare both path segments character-for-character',
    'Keep trailing = and the literal /$value suffix',
    'actual verified materialized file path',
    'not an ask or retrieve workflow',
    'An error is not an empty page',
  ]) assert.ok(body.includes(rule), rule);
});

test('metadata coverage and whole-table deletion retain their safeguards', () => {
  const metadata = plain(read('references/sharepoint-library-metadata.md'));
  for (const rule of ['specifically rejects a non-indexed filter or sort',
    'A generic 400 is not that diagnostic', 'Explicit denial stops',
    'Put the requested inventory, breakdown and aggregates in the message',
    'state the exact number of omitted rows', 'disclose the undelivered rows',
    'Never present incomplete source coverage as complete']) assert.ok(metadata.includes(rule), rule);
  const actions = plain(read('references/business-applications-actions.md'));
  assert.match(actions, /Delete a table \| delete_entity on the exact discovered table path/);
  assert.match(actions, /only when supported and the user confirmed deletion of the whole table, not a record/);
});
