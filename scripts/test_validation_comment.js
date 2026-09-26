// Exercises scripts/validation-comment.js with mocked Octokit / fs / core.
//
// Run with `node --test scripts/test_validation_comment.js` (Node 20+).

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { run, MARKER } = require(path.join(__dirname, 'validation-comment.js'));

const REPO = { owner: 'lunch-money', repo: 'category-templates' };
const FULL_NAME = `${REPO.owner}/${REPO.repo}`;
const CORE = { info: () => {}, warning: () => {}, error: () => {} };
const FS_WITH_LOG = { readFileSync: () => 'validator output details\n' };
const FS_MISSING = {
  readFileSync: () => {
    const err = new Error('ENOENT');
    err.code = 'ENOENT';
    throw err;
  },
};

function buildContext({
  event = 'pull_request',
  pull_requests = [],
  head_sha = 'headsha',
  conclusion = 'failure',
  html_url = 'https://github.com/lunch-money/category-templates/actions/runs/1',
} = {}) {
  return {
    repo: REPO,
    payload: {
      workflow_run: { event, pull_requests, head_sha, conclusion, html_url, id: 1 },
    },
  };
}

function openPR({ number, headSha, state = 'open', baseFullName = FULL_NAME }) {
  return {
    number,
    state,
    base: { repo: { full_name: baseFullName } },
    head: { sha: headSha },
  };
}

function buildGithub({ prByNumber = {}, associated = [], comments = [] } = {}) {
  const calls = {
    associated: [],
    prGet: [],
    listComments: [],
    createComment: [],
    updateComment: [],
    deleteComment: [],
  };
  const github = {
    paginate: async (fn, params) => {
      const res = await fn(params);
      return res && res.data !== undefined ? res.data : res;
    },
    rest: {
      repos: {
        listPullRequestsAssociatedWithCommit: async (params) => {
          calls.associated.push(params);
          return { data: associated };
        },
      },
      pulls: {
        get: async ({ pull_number }) => {
          calls.prGet.push(pull_number);
          const pr = prByNumber[pull_number];
          if (!pr) throw new Error(`unexpected PR fetch for #${pull_number}`);
          return { data: pr };
        },
      },
      issues: {
        listComments: async (params) => {
          calls.listComments.push(params);
          return { data: comments };
        },
        createComment: async (params) => {
          calls.createComment.push(params);
          return { data: { id: 1001, ...params } };
        },
        updateComment: async (params) => {
          calls.updateComment.push(params);
          return { data: { id: params.comment_id } };
        },
        deleteComment: async (params) => {
          calls.deleteComment.push(params);
          return { data: {} };
        },
      },
    },
  };
  return { github, calls };
}

test('same-repo PR uses workflow_run.pull_requests[0] without hitting the associated-commits API', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 42: openPR({ number: 42, headSha: 'sha-abc' }) },
  });
  const context = buildContext({ pull_requests: [{ number: 42 }], head_sha: 'sha-abc' });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'created');
  assert.equal(result.pull_number, 42);
  assert.equal(calls.associated.length, 0);
  assert.equal(calls.createComment.length, 1);
  assert.equal(calls.createComment[0].issue_number, 42);
  assert.ok(calls.createComment[0].body.startsWith(MARKER));
  assert.match(calls.createComment[0].body, /validator output details/);
});

test('fork PR (empty pull_requests) falls back to listPullRequestsAssociatedWithCommit', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 7: openPR({ number: 7, headSha: 'forksha' }) },
    associated: [{ number: 7 }],
  });
  const context = buildContext({ pull_requests: [], head_sha: 'forksha' });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'created');
  assert.equal(result.pull_number, 7);
  assert.equal(calls.associated.length, 1);
  assert.equal(calls.associated[0].commit_sha, 'forksha');
  assert.equal(calls.associated[0].owner, REPO.owner);
  assert.equal(calls.associated[0].repo, REPO.repo);
});

test('stale run: PR head SHA no longer matches workflow_run.head_sha → skip, no writes', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 9: openPR({ number: 9, headSha: 'newsha' }) },
    associated: [{ number: 9 }],
  });
  const context = buildContext({ pull_requests: [], head_sha: 'oldsha' });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'skipped');
  assert.equal(result.reason, 'no-matching-pr');
  assert.equal(calls.createComment.length, 0);
  assert.equal(calls.updateComment.length, 0);
  assert.equal(calls.deleteComment.length, 0);
});

test('closed PR: skip, no comment operations', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 3: openPR({ number: 3, headSha: 'zzz', state: 'closed' }) },
    associated: [{ number: 3 }],
  });
  const context = buildContext({ pull_requests: [], head_sha: 'zzz' });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'skipped');
  assert.equal(result.reason, 'no-matching-pr');
  assert.equal(calls.createComment.length, 0);
});

test('PR targeting a different repository: skip', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 12: openPR({ number: 12, headSha: 'aaa', baseFullName: 'someone/else' }) },
    associated: [{ number: 12 }],
  });
  const context = buildContext({ pull_requests: [], head_sha: 'aaa' });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'skipped');
  assert.equal(calls.createComment.length, 0);
});

test('conclusion=success with existing comment: delete it', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 42: openPR({ number: 42, headSha: 'sha-abc' }) },
    comments: [{ id: 99, user: { type: 'Bot' }, body: `${MARKER}\nprevious failure` }],
  });
  const context = buildContext({
    pull_requests: [{ number: 42 }],
    head_sha: 'sha-abc',
    conclusion: 'success',
  });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'deleted');
  assert.equal(calls.deleteComment.length, 1);
  assert.equal(calls.deleteComment[0].comment_id, 99);
});

test('conclusion=success with no existing comment: no-op', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 42: openPR({ number: 42, headSha: 'sha-abc' }) },
    comments: [],
  });
  const context = buildContext({
    pull_requests: [{ number: 42 }],
    head_sha: 'sha-abc',
    conclusion: 'success',
  });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'noop');
  assert.equal(calls.deleteComment.length, 0);
  assert.equal(calls.createComment.length, 0);
});

test('failure with existing comment: update in place, no duplicate', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 42: openPR({ number: 42, headSha: 'sha-abc' }) },
    comments: [{ id: 55, user: { type: 'Bot' }, body: `${MARKER}\nold` }],
  });
  const context = buildContext({ pull_requests: [{ number: 42 }], head_sha: 'sha-abc' });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'updated');
  assert.equal(calls.updateComment.length, 1);
  assert.equal(calls.updateComment[0].comment_id, 55);
  assert.equal(calls.createComment.length, 0);
});

test('non-pull_request event (e.g. push): skip without touching PR APIs', async () => {
  const { github, calls } = buildGithub();
  const context = buildContext({ event: 'push', head_sha: 'x' });

  const result = await run({ github, context, core: CORE, fs: FS_WITH_LOG });

  assert.equal(result.action, 'skipped');
  assert.equal(result.reason, 'not-a-pull-request');
  assert.equal(calls.associated.length, 0);
  assert.equal(calls.prGet.length, 0);
  assert.equal(calls.listComments.length, 0);
});

test('missing artifact falls back to the "no captured output" default body', async () => {
  const { github, calls } = buildGithub({
    prByNumber: { 42: openPR({ number: 42, headSha: 'sha-abc' }) },
  });
  const context = buildContext({ pull_requests: [{ number: 42 }], head_sha: 'sha-abc' });

  const warnings = [];
  const core = { info: () => {}, warning: (msg) => warnings.push(msg), error: () => {} };

  const result = await run({ github, context, core, fs: FS_MISSING });

  assert.equal(result.action, 'created');
  assert.match(
    calls.createComment[0].body,
    /The validation workflow did not pass, but no captured validator output was available\./,
  );
  assert.equal(warnings.length, 1);
});
