// Runs on `workflow_run` "completed" events for the Validate workflow.
//
// The privileged half of the fork-safe PR-commenter split: this file lives on the
// default branch, is loaded via a sparse-checkout of the default branch only, and
// never runs contributor code. Its job is to figure out which pull request the
// completed workflow_run corresponds to and either post/update or clear a sticky
// "validation" comment on that PR.

const MARKER = '<!-- category-templates-validation-comment -->';
const MAX_COMMENT_LENGTH = 65000;
const DEFAULT_ARTIFACT_PATH = 'validation-result/validation-comment.md';

async function resolvePullRequest({ github, context, workflowRun }) {
  const { owner, repo } = context.repo;
  const headSha = workflowRun.head_sha;

  let candidateNumbers = [];
  if (Array.isArray(workflowRun.pull_requests) && workflowRun.pull_requests.length > 0) {
    candidateNumbers = workflowRun.pull_requests.map((pr) => pr.number);
  } else {
    const associated = await github.paginate(
      github.rest.repos.listPullRequestsAssociatedWithCommit,
      { owner, repo, commit_sha: headSha, per_page: 100 },
    );
    candidateNumbers = associated.map((pr) => pr.number);

    // GitHub can return no associated PRs when the workflow ran against a
    // commit owned by a fork. In that case, resolve the contributor's open PR
    // from the head repository owner and branch included in workflow_run.
    if (candidateNumbers.length === 0) {
      const headOwner = workflowRun.head_repository?.owner?.login;
      const headBranch = workflowRun.head_branch;
      if (headOwner && headBranch) {
        const forkPulls = await github.paginate(github.rest.pulls.list, {
          owner,
          repo,
          state: 'open',
          head: `${headOwner}:${headBranch}`,
          per_page: 100,
        });
        candidateNumbers = forkPulls.map((pr) => pr.number);
      }
    }
  }

  for (const number of candidateNumbers) {
    const { data: pr } = await github.rest.pulls.get({ owner, repo, pull_number: number });
    if (pr.base?.repo?.full_name !== `${owner}/${repo}`) continue;
    if (pr.state !== 'open') continue;
    if (pr.head?.sha !== headSha) continue;
    return pr;
  }
  return null;
}

async function findExistingComment({ github, owner, repo, issue_number }) {
  const comments = await github.paginate(github.rest.issues.listComments, {
    owner,
    repo,
    issue_number,
    per_page: 100,
  });
  return comments.find((c) => c.user?.type === 'Bot' && c.body?.includes(MARKER)) ?? null;
}

function buildBody({ details, runUrl }) {
  let body = [
    MARKER,
    '### Template validation needs attention',
    '',
    details,
    '',
    `[Open the validation run](${runUrl}) for the full logs.`,
  ].join('\n');
  if (body.length > MAX_COMMENT_LENGTH) {
    body = [
      body.slice(0, MAX_COMMENT_LENGTH - 250),
      '',
      'Output truncated because it is too long for a GitHub comment.',
      '',
      `[Open the validation run](${runUrl}) for the full logs.`,
    ].join('\n');
  }
  return body;
}

function readDetails({ fs, artifactPath, core }) {
  try {
    return fs.readFileSync(artifactPath, 'utf8').trim();
  } catch (error) {
    core?.warning?.(`Could not read validation output artifact: ${error.message}`);
    return 'The validation workflow did not pass, but no captured validator output was available.';
  }
}

async function run({
  github,
  context,
  core,
  fs,
  artifactPath = DEFAULT_ARTIFACT_PATH,
}) {
  const workflowRun = context.payload.workflow_run;
  if (workflowRun.event !== 'pull_request') {
    core.info(`Skipping: workflow_run event is ${workflowRun.event}, not pull_request.`);
    return { action: 'skipped', reason: 'not-a-pull-request' };
  }

  const pr = await resolvePullRequest({ github, context, workflowRun });
  if (!pr) {
    core.info(`Skipping: no open PR in this repo currently owns commit ${workflowRun.head_sha}.`);
    return { action: 'skipped', reason: 'no-matching-pr' };
  }

  const { owner, repo } = context.repo;
  const issue_number = pr.number;
  const runUrl = workflowRun.html_url;
  const existing = await findExistingComment({ github, owner, repo, issue_number });

  if (workflowRun.conclusion === 'success') {
    if (existing) {
      await github.rest.issues.deleteComment({ owner, repo, comment_id: existing.id });
      core.info(`Cleared validation comment on #${issue_number}.`);
      return { action: 'deleted', pull_number: issue_number };
    }
    core.info(`No validation comment to clear on #${issue_number}.`);
    return { action: 'noop', pull_number: issue_number };
  }

  const details = readDetails({ fs, artifactPath, core });
  const body = buildBody({ details, runUrl });

  if (existing) {
    await github.rest.issues.updateComment({ owner, repo, comment_id: existing.id, body });
    core.info(`Updated validation comment on #${issue_number}.`);
    return { action: 'updated', pull_number: issue_number };
  }

  await github.rest.issues.createComment({ owner, repo, issue_number, body });
  core.info(`Created validation comment on #${issue_number}.`);
  return { action: 'created', pull_number: issue_number };
}

module.exports = {
  run,
  resolvePullRequest,
  findExistingComment,
  buildBody,
  readDetails,
  MARKER,
  MAX_COMMENT_LENGTH,
  DEFAULT_ARTIFACT_PATH,
};
