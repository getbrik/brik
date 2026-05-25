(function() {
  "use strict";
  const raw = document.getElementById('brik-report').textContent;
  let data;
  try { data = JSON.parse(raw); }
  catch (e) {
    document.body.innerHTML = '<main><pre>Failed to parse embedded aggregate JSON: ' + (e && e.message) + '</pre></main>';
    return;
  }

  // Optional second data island: the plan that drove this run. When
  // present, it is the source of truth for the canonical execution order
  // and for the gate reason of every skipped stage. Pre-plan archives
  // and reports rendered without plan.json land here as null -- consumers
  // are written to degrade gracefully (use STAGE_ORDER fallback, do not
  // backfill missing stages).
  let plan = null;
  try {
    const planEl = document.getElementById('brik-plan');
    if (planEl && planEl.textContent) plan = JSON.parse(planEl.textContent);
  } catch (e) { plan = null; }
  const planStages = (plan && Array.isArray(plan.stages)) ? plan.stages : [];
  const planById = planStages.reduce((acc, p) => { acc[p.id] = p; return acc; }, {});

  const SEV_RANK = { critical: 4, high: 3, medium: 2, low: 1, info: 0 };
  const SEV_ORDER = ["critical", "high", "medium", "low", "info"];
  // Fallback order when plan.json is absent. promote (v0.6+) was missing
  // from the pre-plan list and is included here for symmetry with
  // lib/stages/promote.sh.
  const STAGE_ORDER_DEFAULT = ["init","release","build","lint","sast","scan","test","package","container-scan","promote","deploy","notify"];
  const STAGE_ORDER = planStages.length > 0
    ? planStages.map((p) => p.id)
    : STAGE_ORDER_DEFAULT;
  const PARALLEL = new Set(["lint","sast","scan","test"]);

  // Human-readable gate-reason -> sentence. Mirrors cli.plan._reason_text
  // (lib/cli/plan.sh) so the HTML and the terminal share the same wording.
  function planReasonText(p) {
    if (!p) return null;
    const flag = (p.gate && p.gate.opt_in_flag) || '';
    switch (p.reason) {
      case 'context-mismatch':
        return 'Context mismatch (this stage runs in a different context).';
      case 'opt-in-flag-missing':
        return flag
          ? 'Not requested: the ' + flag + ' flag was not passed (this stage is opt-in).'
          : 'Not requested: the required opt-in flag was not passed.';
      case 'no-impact':
        return "No changed file matched this stage's impact patterns.";
      case 'no-diff':
        return 'No diff context available; running conservatively.';
      case 'no-impact-declared':
        return 'No impact patterns declared; runs by default.';
      case 'context-match':
        return 'Applicable to current context.';
      case 'impacted':
        return 'Changed files match the impact patterns.';
      default:
        return p.reason || null;
    }
  }

  const stageRank = (n) => { const i = STAGE_ORDER.indexOf(n); return i < 0 ? 99 : i; };
  const sevRank = (s) => SEV_RANK[s] || 0;
  const escapeHtml = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
    { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]
  ));

  // Shared between every per-stage renderer (init, release, build, lint,
  // findings, scan, test, package, notify). Hoisted so the same closure is
  // reused instead of being recreated on each render call.
  const sectionLabel = (txt) =>
    '<div class="section-label">' + escapeHtml(txt) + '</div>';

  // Wrap a sub-section body in a stage-tile-shaped card. The section heading
  // is emitted separately by the caller via sectionLabel(...) BEFORE the
  // tile, matching the order section-label -> (stage-grid?) -> stage-tile
  // already used by release and build. Used by the verify stages (lint,
  // sast, scan, test, container-scan).
  const sectionTile = (bodyHtml) =>
    '<div class="stage-tile section-tile">' + bodyHtml + '</div>';

  const fmtDuration = (ms) => {
    if (ms == null || isNaN(ms)) return '-';
    if (ms < 1000) return Math.round(ms) + 'ms';
    const s = Math.floor(ms / 1000);
    if (s < 60) return s + 's';
    if (s < 3600) return Math.floor(s/60) + 'm' + String(s%60).padStart(2,'0') + 's';
    return Math.floor(s/3600) + 'h' + String(Math.floor((s%3600)/60)).padStart(2,'0') + 'm';
  };

  const totalDurationMs = () => {
    const a = Date.parse((data.pipeline||{}).started_at);
    const b = Date.parse((data.pipeline||{}).finished_at);
    if (isNaN(a) || isNaN(b)) return null;
    return b - a;
  };

  const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  function formatRelative(ms) {
    if (ms == null || ms < 0) return null;
    const s = Math.floor(ms / 1000);
    if (s < 60)        return s + 's ago';
    const m = Math.floor(s / 60);
    if (m < 60)        return m + 'm ago';
    const h = Math.floor(m / 60);
    if (h < 24)        return h + 'h ago';
    const d = Math.floor(h / 24);
    if (d < 30)        return d + 'd ago';
    return null;
  }
  function formatHumanDate(iso) {
    if (!iso) return '-';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return escapeHtml(iso);
    const abs = d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear()
              + ', ' + String(d.getHours()).padStart(2,'0')
              + ':' + String(d.getMinutes()).padStart(2,'0');
    const rel = formatRelative(Date.now() - d.getTime());
    return rel
      ? escapeHtml(abs) + ' <span class="muted">(' + escapeHtml(rel) + ')</span>'
      : escapeHtml(abs);
  }

  const $ = (id) => document.getElementById(id);

  function renderHero() {
    const p = data.pipeline || {};
    const status = p.status || 'unknown';
    const context = p.context || 'snapshot';
    const commit = p.commit || {};
    const sha = commit.sha || commit.short_sha || '';
    const cUrl = commitUrl(REPO, sha);

    // Hostnames feeding the tooltips. Pipeline URL host identifies the CI
    // platform; repo URL host identifies the forge (often a different host
    // than CI - e.g. Jenkins on jenkins.* fetches code from gitea.*).
    const pipelineHost = hostOf(p.url);
    const repoHost = REPO ? hostOf(REPO.base) : '';
    const pipelineTip = pipelineHost ? 'CI pipeline on ' + pipelineHost : 'CI pipeline';
    const commitTip   = repoHost ? 'Git commit on ' + repoHost : 'Git commit';
    const branchTip   = repoHost ? 'Git branch on ' + repoHost : 'Git branch';
    const tagTip      = repoHost ? 'Git tag on ' + repoHost    : 'Git tag';
    const emailTip    = commit.author_email ? 'Send email to ' + commit.author_email : '';

    // pipeline id, optionally linked to the platform pipeline view
    const idLink = p.url
      ? '<a href="' + escapeHtml(p.url) + '" target="_blank" rel="noopener" data-tooltip="' + escapeHtml(pipelineTip) + '">' + escapeHtml(p.id || '-') + '</a>'
      : escapeHtml(p.id || '-');

    // version fallback chain: commit.tag > summary.artifacts.version > release.new_version > short_sha
    const release = (data.stages || []).find((s) => s.stage === 'release');
    const versionVal = commit.tag
      || ((data.summary || {}).artifacts || {}).version
      || (release && release.business && release.business.new_version)
      || commit.short_sha
      || '';
    const tUrl = tagUrlOf(REPO, commit.tag);
    const versionInner = tUrl
      ? '<a href="' + escapeHtml(tUrl) + '" target="_blank" rel="noopener" data-tooltip="' + escapeHtml(tagTip) + '">' + escapeHtml(versionVal) + '</a>'
      : escapeHtml(versionVal);

    // commit row pieces
    const shaCopy = (commit.sha && commit.sha.length > (commit.short_sha || '').length)
      ? copyBtn(commit.sha, 'Copy full commit SHA')
      : '';
    const shaInner = commit.short_sha
      ? (cUrl
          ? '<a href="' + escapeHtml(cUrl) + '" target="_blank" rel="noopener" class="mono sha" data-tooltip="' + escapeHtml(commitTip) + '">' + escapeHtml(commit.short_sha) + '</a>' + shaCopy
          : '<span class="mono sha">' + escapeHtml(commit.short_sha) + '</span>' + shaCopy)
      : '';
    const authorInner = commit.author
      ? (commit.author_email
          ? '<a href="mailto:' + escapeHtml(commit.author_email) + '" data-tooltip="' + escapeHtml(emailTip) + '">' + escapeHtml(commit.author) + '</a>'
          : escapeHtml(commit.author))
      : '';
    const subjectInner = commit.message_subject
      ? '<span class="subject" title="' + escapeHtml(commit.message_subject) + '">' + escapeHtml(commit.message_subject) + '</span>'
      : '';

    // branch link - do NOT fall back to commit.ref because on a tag pipeline
    // GitLab sets ref to the tag name (e.g. "v1.4.2"), which would mislabel
    // the tag as a branch. The tag itself is already surfaced as the version
    // in the ids-row, so a missing branch simply omits the branch cell.
    const branchVal = commit.branch || '';
    const bUrl = treeUrl(REPO, branchVal);
    const branchInner = branchVal
      ? (bUrl
          ? '<a href="' + escapeHtml(bUrl) + '" target="_blank" rel="noopener" class="mono" data-tooltip="' + escapeHtml(branchTip) + '">' + escapeHtml(branchVal) + '</a>'
          : '<span class="mono">' + escapeHtml(branchVal) + '</span>')
      : '';

    const dateHtml = formatHumanDate(p.started_at);
    const total = fmtDuration(totalDurationMs());

    const dryRun = !!(p.tech && p.tech.dry_run === true);

    const idsRow = '<div class="ids-row">'
      + '<span class="pipeline-id mono">#' + idLink + '</span>'
      + '<span class="context-badge ' + escapeHtml(context) + '">' + escapeHtml(context) + '</span>'
      + (dryRun ? '<span class="dry-run-badge" title="BRIK_DRY_RUN=true: destructive actions were skipped">dry-run</span>' : '')
      + (versionVal ? '<span class="version">' + versionInner + '</span>' : '')
      + '</div>';

    const commitRow = (shaInner || subjectInner || authorInner)
      ? '<div class="commit">'
        + (shaInner     ? '<span class="commit-cell"><span class="label">commit</span> ' + shaInner + '</span>' : '')
        + (subjectInner ? '<span class="commit-cell">' + subjectInner + '</span>' : '')
        + (authorInner  ? '<span class="commit-cell"><span class="label">by</span> ' + authorInner + '</span>' : '')
        + '</div>'
      : '';

    $('hero').innerHTML = ''
      + '<h1 title="' + escapeHtml(p.project || 'pipeline') + '">' + escapeHtml(p.project || 'pipeline') + '</h1>'
      + '<span class="pill ' + status + '">' + escapeHtml(status) + '</span>'
      + idsRow
      + commitRow
      + '<div class="meta">'
      +   '<span class="meta-cell"><span class="label">platform</span> <span class="value">' + escapeHtml(p.platform || '-') + '</span></span>'
      +   (branchInner ? '<span class="meta-cell"><span class="label">branch</span> ' + branchInner + '</span>' : '')
      +   '<span class="meta-cell"><span class="label">started</span> <span class="value">' + dateHtml + '</span></span>'
      +   '<span class="meta-cell"><span class="label">duration</span> <span class="value mono">' + escapeHtml(total) + '</span></span>'
      + '</div>';
  }

  function renderTimeline() {
    // Build the canonical timeline from plan.stages (source of truth for
    // the execution flow) and backfill missing fragments. This makes
    // GitLab and Jenkins surface the same set of cells: previously
    // Jenkins-driven runs hid plan-skipped stages because the adapter
    // never wrote a fragment for them.
    const byId = (data.stages || []).reduce((acc, s) => {
      const id = s.stage || s.name || s.id;
      if (id) acc[id] = s;
      return acc;
    }, {});
    const orderedIds = planStages.length > 0
      ? planStages.map((p) => p.id)
      : (data.stages || []).map((s) => s.stage || s.name || s.id)
                            .sort((a,b) => stageRank(a) - stageRank(b));
    const stages = orderedIds.map((sid) => {
      const recorded = byId[sid];
      if (recorded) return recorded;
      // Synthesize a placeholder so renderStageCell renders the right
      // status pill. Plan decision drives classification; "running" is
      // reserved for the in-flight stage rendering this report (notify).
      const planEntry = planById[sid] || null;
      const planSkipped = planEntry && planEntry.decision === 'skip';
      return {
        stage: sid,
        status: planSkipped ? 'skipped' : 'running',
        tech: { status: planSkipped ? 'skipped' : 'running' }
      };
    });

    const rail = $('timeline-rail');
    rail.innerHTML = '';
    let i = 0;
    while (i < stages.length) {
      const s = stages[i];
      if (PARALLEL.has(s.stage)) {
        const group = [];
        while (i < stages.length && PARALLEL.has(stages[i].stage)) { group.push(stages[i]); i++; }
        rail.appendChild(renderParallelGroup(group));
      } else {
        rail.appendChild(renderStageCell(s));
        i++;
      }
    }
  }
  function renderStageCell(s) {
    const cell = document.createElement('div');
    cell.className = 'timeline-cell';
    const status = s.status || 'unknown';
    const job = (s.runner && s.runner.job_url) || '';
    const jobHtml = job ? '<div class="stage-job"><a href="' + escapeHtml(job) + '" target="_blank" rel="noopener">job</a></div>' : '';
    const stageDryRun = !!(s.tech && (s.tech.dry_run === true || s.tech.dry_run === 'true'));
    const dryRunHtml = stageDryRun
      ? '<div class="stage-dry-run" title="BRIK_DRY_RUN=true: destructive actions for this stage were skipped">dry-run</div>'
      : '';
    cell.innerHTML = ''
      + '<div class="stage-name">' + escapeHtml(s.stage || '-') + '</div>'
      + '<div class="stage-status ' + status + '">' + escapeHtml(status) + '</div>'
      + dryRunHtml
      + '<div class="stage-duration">' + fmtDuration(s.duration_ms) + '</div>'
      + jobHtml;
    return cell;
  }
  function renderParallelGroup(stages) {
    const wrap = document.createElement('div');
    wrap.className = 'timeline-cell parallel-group';
    const label = document.createElement('div');
    label.className = 'group-label';
    label.textContent = 'verify (parallel)';
    const children = document.createElement('div');
    children.className = 'group-children';
    stages.forEach((s) => children.appendChild(renderStageCell(s)));
    wrap.appendChild(label); wrap.appendChild(children);
    return wrap;
  }

  // Mount the interactive findings UI (counts + severity chips + search +
  // expandable cards) into a given container, scoped to a specific set of
  // items (typically a single stage's items). Replaces the former
  // renderFindings() global panel: each stage that emits findings.items
  // now hosts its own details panel.
  function mountFindingsPanel(container, items) {
    const all = (items || []).slice();
    all.sort((a,b) => sevRank(b.severity) - sevRank(a.severity) || (b.score||0) - (a.score||0));

    const counts = {};
    SEV_ORDER.forEach((k) => counts[k] = 0);
    all.forEach((f) => { counts[f.severity] = (counts[f.severity] || 0) + 1; });

    const toolbar = document.createElement('div');
    toolbar.className = 'findings-toolbar';
    const countsEl = document.createElement('div');
    countsEl.className = 'findings-counts';
    const totalLine = '<span class="count">' + all.length + ' findings</span>';
    const sevLines = SEV_ORDER.filter((k) => counts[k] > 0).map((k) => (
      '<span class="count sev-' + k + '"><span class="dot"></span>' + counts[k] + ' ' + k + '</span>'
    )).join('');
    countsEl.innerHTML = totalLine + sevLines;
    toolbar.appendChild(countsEl);

    const filters = document.createElement('div');
    filters.className = 'findings-filters';
    const chips = [{ key: 'all', label: 'all' }].concat(
      SEV_ORDER.filter((k) => counts[k] > 0).map((k) => ({ key: k, label: k, sev: k }))
    );
    chips.forEach((c) => {
      const chip = document.createElement('button');
      chip.className = 'chip' + (c.key === 'all' ? ' active' : '');
      chip.dataset.filter = c.key;
      if (c.sev) chip.dataset.sev = c.sev;
      chip.textContent = c.label;
      chip.addEventListener('click', () => {
        filters.querySelectorAll('.chip').forEach((x) => x.classList.remove('active'));
        chip.classList.add('active');
        renderList();
      });
      filters.appendChild(chip);
    });
    toolbar.appendChild(filters);
    container.appendChild(toolbar);

    const search = document.createElement('input');
    search.type = 'search';
    search.className = 'search-input';
    search.placeholder = 'Filter by id, package, message...';
    search.addEventListener('input', renderList);
    container.appendChild(search);

    const list = document.createElement('div');
    list.className = 'findings-list';
    container.appendChild(list);

    function activeFilter() {
      const a = filters.querySelector('.chip.active');
      return a ? a.dataset.filter : 'all';
    }
    function renderList() {
      const f = activeFilter();
      const q = (search.value || '').trim().toLowerCase();
      const matches = all.filter((it) => {
        if (f !== 'all' && it.severity !== f) return false;
        if (!q) return true;
        const hay = [
          it.id, it.message,
          it.package && it.package.name, it.package && it.package.version,
          it.tool && it.tool.name
        ].filter(Boolean).join(' ').toLowerCase();
        return hay.indexOf(q) !== -1;
      });
      list.innerHTML = '';
      if (matches.length === 0) {
        list.innerHTML = '<div class="findings-empty">No findings match the current filter.</div>';
        return;
      }
      matches.forEach((it) => list.appendChild(renderFindingCard(it)));
    }
    renderList();
  }
  function renderFindingCard(it) {
    const card = document.createElement('div');
    card.className = 'finding sev-' + (it.severity || 'info');
    card.dataset.open = 'false';
    const idHtml = it.help_uri
      ? '<a href="' + escapeHtml(it.help_uri) + '" target="_blank" rel="noopener" onclick="event.stopPropagation()">' + escapeHtml(it.id || '-') + '</a>'
      : escapeHtml(it.id || '-');
    const pkg = it.package
      ? escapeHtml(it.package.name + ' ' + it.package.version)
      : '<span class="faint">-</span>';
    const fix = (it.fix && it.fix.available)
      ? '<span class="fix">-&gt; ' + escapeHtml((it.fix.versions || []).join(', ')) + '</span>'
      : '<span class="faint">no fix</span>';

    card.innerHTML = ''
      + '<span class="sev-dot"></span>'
      + '<div class="ident">'
      + '  <span class="id">' + idHtml + '</span>'
      + '  <span class="pkg">' + pkg + '</span>'
      + '</div>'
      + '<div class="right">' + fix + '<span class="chev">&rsaquo;</span></div>'
      + buildFindingDetail(it);
    card.addEventListener('click', () => {
      card.dataset.open = card.dataset.open === 'true' ? 'false' : 'true';
    });
    return card;
  }
  function buildFindingDetail(it) {
    const rows = [];
    if (it.message) rows.push(['Message', escapeHtml(it.message)]);
    if (it.score != null) rows.push(['CVSS', escapeHtml(String(it.score))]);
    if (it.tool && it.tool.name) rows.push(['Tool', escapeHtml(it.tool.name + (it.tool.version ? ' ' + it.tool.version : ''))]);
    if (it.location && it.location.uri) {
      const region = (it.location.start_line != null) ? ':' + it.location.start_line : '';
      rows.push(['Location', escapeHtml(it.location.uri + region)]);
    }
    if (it.location && it.location.logical) rows.push(['Logical', escapeHtml(it.location.logical)]);
    if (it.cwe && it.cwe.length) rows.push(['CWE', it.cwe.map(escapeHtml).join(', ')]);
    if (it.help_uri) rows.push(['Advisory', '<a href="' + escapeHtml(it.help_uri) + '" target="_blank" rel="noopener" onclick="event.stopPropagation()">' + escapeHtml(it.help_uri) + '</a>']);
    if (rows.length === 0) return '';
    return '<dl class="finding-detail">'
      + rows.map((r) => '<dt>' + r[0] + '</dt><dd>' + r[1] + '</dd>').join('')
      + '</dl>';
  }

  // Policy preset descriptions (mirror lib/transverse/findings.sh A2 matrix).
  const POLICY_DESC = {
    pragmatic:  'Ignores findings below the severity floor, then those without an upstream fix or marked wont-fix. Fails the rest.',
    strict:     'Ignores findings below the severity floor only. Fails everything else, including findings with no upstream fix.',
    permissive: 'Effective floor is critical. Ignores anything below critical, plus criticals without a fix. Fails only criticals with an upstream fix.'
  };

  // Repo URL helpers ------------------------------------------------
  // Extract a display-friendly hostname (no scheme, no port, no path) so
  // tooltips can identify which forge a link points to without dumping the
  // full URL.
  function hostOf(url) {
    if (!url) return '';
    const m = String(url).match(/^https?:\/\/([^:/]+)/);
    return m ? m[1] : '';
  }
  // Hostname → platform mapping used when init captured the explicit
  // repo_url. Falls back to gitea for unknown self-hosted forges so deep
  // links work in private setups too.
  function platformFromHost(host) {
    if (!host) return null;
    const h = String(host).toLowerCase();
    if (h.includes('gitlab')) return 'gitlab';
    if (h.includes('github')) return 'github';
    if (h.includes('gitea'))  return 'gitea';
    if (h.includes('bitbucket')) return 'bitbucket';
    return null;
  }
  function detectRepo(p) {
    if (!p) return null;
    const commit = p.commit || {};
    // Preferred path: explicit repo URL captured by init (every platform).
    if (commit.repo_url) {
      const base = String(commit.repo_url).replace(/\.git$/, '').replace(/\/+$/, '');
      const m = base.match(/^https?:\/\/([^/]+)/);
      const host = m ? m[1] : '';
      const platform = platformFromHost(host) || 'gitea';
      return { base, platform };
    }
    // Legacy fallback: derive from pipeline.url shape.
    if (!p.url) return null;
    let m = p.url.match(/^(.+?)\/-\/pipelines\/[^/]+/);
    if (m) return { base: m[1], platform: 'gitlab' };
    m = p.url.match(/^(.+?)\/actions\/runs\/[^/]+/);
    if (m) return { base: m[1], platform: 'github' };
    return null;
  }
  function commitUrl(repo, sha) {
    if (!repo || !sha) return null;
    if (repo.platform === 'gitlab')    return repo.base + '/-/commit/' + sha;
    if (repo.platform === 'github')    return repo.base + '/commit/' + sha;
    if (repo.platform === 'gitea')     return repo.base + '/commit/' + sha;
    if (repo.platform === 'bitbucket') return repo.base + '/commits/' + sha;
    return null;
  }
  // Build a forge-specific URL pointing at a file blob at a given ref
  // (commit SHA or branch name). Used to make path values in the Policy
  // card click-through to the actual source on the forge.
  function blobUrl(repo, ref, path) {
    if (!repo || !ref || !path) return null;
    const p = String(path).replace(/^\//, '');
    if (repo.platform === 'gitlab') return repo.base + '/-/blob/' + ref + '/' + p;
    if (repo.platform === 'github') return repo.base + '/blob/' + ref + '/' + p;
    if (repo.platform === 'gitea')  return repo.base + '/src/commit/' + ref + '/' + p;
    return null;
  }
  // Convert a raw forge URL (the kind BRIK_POLICY_URL points at) into the
  // human-browseable blob view on the same forge. Returns null when the
  // input does not match any known raw-URL shape; callers should then
  // either show the URL as-is or fall back to plain text. Supported:
  //   GitLab : .../-/raw/<ref>/<path>             -> .../-/blob/<ref>/<path>
  //   Gitea  : .../raw/(branch|commit|tag)/<...>  -> .../src/(branch|commit|tag)/<...>
  //   GitHub : raw.githubusercontent.com/<o>/<r>/<ref>/<path>
  //                                               -> github.com/<o>/<r>/blob/<ref>/<path>
  //   Bitbucket: <repo>/raw/<ref>/<path>          -> <repo>/src/<ref>/<path>
  function gitRawToBlob(url) {
    if (!url) return null;
    const u = String(url);
    let m = u.match(/^(.+)\/-\/raw\/(.+)$/);
    if (m) return m[1] + '/-/blob/' + m[2];
    m = u.match(/^(.+?)\/raw\/(branch|commit|tag)\/(.+)$/);
    if (m) return m[1] + '/src/' + m[2] + '/' + m[3];
    m = u.match(/^https?:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/(.+)$/);
    if (m) return 'https://github.com/' + m[1] + '/' + m[2] + '/blob/' + m[3];
    m = u.match(/^(https?:\/\/bitbucket\.org\/[^/]+\/[^/]+)\/raw\/(.+)$/);
    if (m) return m[1] + '/src/' + m[2];
    return null;
  }
  function treeUrl(repo, ref) {
    if (!repo || !ref) return null;
    if (repo.platform === 'gitlab')    return repo.base + '/-/tree/' + ref;
    if (repo.platform === 'github')    return repo.base + '/tree/' + ref;
    if (repo.platform === 'gitea')     return repo.base + '/src/branch/' + ref;
    if (repo.platform === 'bitbucket') return repo.base + '/src/' + ref;
    return null;
  }
  function tagUrlOf(repo, tag) {
    if (!repo || !tag) return null;
    if (repo.platform === 'gitlab')    return repo.base + '/-/tags/' + tag;
    if (repo.platform === 'github')    return repo.base + '/releases/tag/' + tag;
    if (repo.platform === 'gitea')     return repo.base + '/releases/tag/' + tag;
    if (repo.platform === 'bitbucket') return repo.base + '/src/' + tag;
    return null;
  }
  const REPO = detectRepo(data.pipeline || {});

  // Format an ISO-8601 timestamp into [date, time] strings in UTC.
  // Returns null when the input cannot be parsed so callers can fall back
  // to the raw value.
  function splitIsoUtc(iso) {
    if (!iso) return null;
    const d = new Date(iso);
    if (isNaN(d.getTime())) return null;
    const pad = (n) => String(n).padStart(2, '0');
    const date = d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-' + pad(d.getUTCDate());
    const time = pad(d.getUTCHours()) + ':' + pad(d.getUTCMinutes()) + ':' + pad(d.getUTCSeconds()) + ' UTC';
    return [date, time];
  }

  // Format an expiry date (ISO date or full timestamp) as "YYYY-MM-DD" +
  // a relative chip ("in 12d", "today", "3d ago"). Colour the chip orange
  // when expiring within a week, red when already past, default otherwise.
  function formatExpiry(iso) {
    if (!iso) return null;
    const d = new Date(iso);
    if (isNaN(d.getTime())) return null;
    const pad = (n) => String(n).padStart(2, '0');
    const dateStr = d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-' + pad(d.getUTCDate());
    const days = Math.round((d.getTime() - Date.now()) / (24 * 3600 * 1000));
    let cls = 'expiry-rel';
    let txt;
    if (days < 0)       { cls += ' expired'; txt = Math.abs(days) + 'd ago'; }
    else if (days === 0){ cls += ' soon';    txt = 'today'; }
    else if (days <= 7) { cls += ' soon';    txt = 'in ' + days + 'd'; }
    else                {                    txt = 'in ' + days + 'd'; }
    return escapeHtml(dateStr) + ' <span class="' + cls + '">' + escapeHtml(txt) + '</span>';
  }

  function renderMeta() {
    const grid = $('meta-grid');
    grid.innerHTML = '';
    const policy = (data.summary || {}).policy;
    if (policy) {
      const lines = [['preset', policy.preset || '-']];

      // source: prefer a click-through to the file at the pipeline's
      // commit on the detected forge, otherwise plain text.
      const src = policy.source || '';
      const sha = ((data.pipeline || {}).commit || {}).sha
               || ((data.pipeline || {}).commit || {}).short_sha
               || '';
      const srcUrl = (src && REPO && sha) ? blobUrl(REPO, sha, src) : null;
      if (srcUrl) {
        const forge = hostOf(REPO.base) || REPO.platform;
        lines.push(['source',
          '<a href="' + escapeHtml(srcUrl) + '" target="_blank" rel="noopener"'
          + ' data-tooltip="Open ' + escapeHtml(src) + ' on ' + escapeHtml(forge)
          + '">' + escapeHtml(src) + '</a>',
          true
        ]);
      } else {
        lines.push(['source', src || '-']);
      }

      if (policy.org_policy_url) {
        const url = String(policy.org_policy_url);
        const filename = (url.split('/').pop() || url) || url;
        // Only link out when the URL can be rewritten to a forge blob
        // view (i.e. BRIK_POLICY_URL was set to a raw git endpoint).
        // Otherwise - file://, arbitrary HTTP host, internal mounts -
        // render plain text with the full URL surfaced on hover.
        const blob = gitRawToBlob(url);
        const html = blob
          ? '<a href="' + escapeHtml(blob) + '" target="_blank" rel="noopener"'
            + ' data-tooltip="Open ' + escapeHtml(filename) + ' on '
            + escapeHtml(hostOf(blob) || 'forge') + '">'
            + escapeHtml(filename) + '</a>'
          : '<span data-tooltip="' + escapeHtml(url) + '">'
            + escapeHtml(filename) + '</span>';
        lines.push(['org file', html, true]);
      }
      const split = splitIsoUtc(policy.org_policy_loaded_at);
      if (split) {
        lines.push(['loaded date', split[0]]);
        lines.push(['loaded time', split[1]]);
      } else if (policy.org_policy_loaded_at) {
        lines.push(['loaded at', policy.org_policy_loaded_at]);
      }
      const desc = POLICY_DESC[policy.preset] || '';
      grid.appendChild(kvCard('Policy', lines, desc));
    }
    const stages = (data.summary || {}).stages || {};
    grid.appendChild(kvCard('Stages', [
      ['total',   stages.total   || 0],
      ['passed',  stages.passed  || 0],
      ['failed',  stages.failed  || 0],
      ['skipped', stages.skipped || 0]
    ]));
    const business = (data.summary || {}).business || {};
    const pipelineBiz = ((data.pipeline || {}).business || {}).status || '-';
    grid.appendChild(kvCard('Business outcome', [
      ['status',  pipelineBiz],
      ['success', business.success_count || 0],
      ['warning', business.warning_count || 0],
      ['error',   business.error_count   || 0]
    ]));
    if ((policy && (policy.expiring_soon || []).length > 0)) {
      const lines = policy.expiring_soon.map((e) => {
        const label = e.id || e.glob || 'entry';
        const formatted = formatExpiry(e.expires);
        return formatted
          ? [label, formatted, true]
          : [label, e.expires || '-'];
      });
      grid.appendChild(kvCard('Expiring soon', lines));
    }
  }
  // Render a small key/value card. Each line is [k, v] (escaped) or
  // [k, v, true] where the third element flags v as pre-rendered HTML
  // (used for clickable links and similar inline composition).
  function kvCard(title, lines, desc) {
    const c = document.createElement('div');
    c.className = 'kv-card';
    c.innerHTML = '<h3>' + escapeHtml(title) + '</h3>'
      + lines.map((l) => {
          const vHtml = l[2] === true ? String(l[1]) : escapeHtml(String(l[1]));
          return '<div class="kv-line"><span class="k">' + escapeHtml(l[0])
               + '</span><span class="v">' + vHtml + '</span></div>';
        }).join('')
      + (desc ? '<div class="desc">' + escapeHtml(desc) + '</div>' : '');
    return c;
  }

  // Severity bar component shared by sast/scan/container-scan
  function severityBar(by_sev, total) {
    const t = total || SEV_ORDER.reduce((acc, k) => acc + (by_sev[k] || 0), 0);
    if (t === 0) return '<div class="hint">No findings.</div>';
    const segs = SEV_ORDER.filter((k) => (by_sev[k] || 0) > 0).map((k) => {
      const w = ((by_sev[k] || 0) / t * 100).toFixed(1);
      return '<div class="seg ' + k + '" style="width:' + w + '%;" title="' + by_sev[k] + ' ' + k + '"></div>';
    }).join('');
    const legend = SEV_ORDER.filter((k) => (by_sev[k] || 0) > 0).map((k) => (
      '<span class="lg sev-' + k + '"><span class="dot"></span>' + by_sev[k] + ' ' + k + '</span>'
    )).join('');
    return '<div class="sev-bar">' + segs + '</div>'
         + '<div class="sev-legend">' + legend + '</div>';
  }
  // Standard tile shape: label / value / optional sub. Use opts.warning
  // to flag the tile (orange-tinted border, warning bg) - the build stage
  // uses it for size_bytes=0 (empty artifact). opts.mono switches the
  // value to compact mono (13px) but most callers prefer the default
  // 16px and wrap mono fragments in <span class="mono"> inside the value
  // so all stages render tiles at the same scale.
  function tile(label, valueHtml, subHtml, opts) {
    opts = opts || {};
    const cls = opts.mono ? 'value mono' : 'value';
    const tileCls = 'stage-tile' + (opts.warning ? ' tile-warning' : '');
    return '<div class="' + tileCls + '">'
      + '<div class="label">' + escapeHtml(label) + '</div>'
      + '<div class="' + cls + '">' + valueHtml + '</div>'
      + (subHtml ? '<div class="sub">' + subHtml + '</div>' : '')
      + '</div>';
  }
  function fmtBytes(n) {
    if (n == null || isNaN(n)) return '-';
    if (n === 0) return '0 B';
    const u = ['B','KB','MB','GB','TB'];
    let i = 0; while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i === 0 ? n : n.toFixed(1)) + ' ' + u[i];
  }
  function trunc(s, n) { s = String(s == null ? '' : s); return s.length > n ? s.slice(0, n) + '...' : s; }
  function shaCell(sha) {
    if (!sha) return '<span class="faint">-</span>';
    return '<code class="mono" title="' + escapeHtml(sha) + '">' + escapeHtml(trunc(sha, 12)) + '</code>';
  }

  // Copy-to-clipboard button. Renders a small icon next to a value; the click
  // handler is delegated at document level (see bottom of this IIFE). Uses the
  // async Clipboard API when available and a hidden-textarea fallback for
  // file:// contexts where it may be blocked.
  //
  // opts.label : optional inline text (appears next to the icon, makes the
  //              button affordance unambiguous when several copy buttons sit
  //              side by side, e.g. "copy ref" vs "copy pull command").
  // opts.icon  : 'pull' renders a shell-prompt + chevron icon to signal
  //              "copy a runnable command"; otherwise the default copy icon.
  function copyBtn(value, tip, opts) {
    if (!value) return '';
    const o = opts || {};
    const isPull = (o.icon === 'pull');
    const iconSvg = isPull
      ? '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
        +   '<polyline points="5 8 9 12 5 16"/>'
        +   '<line x1="12" y1="17" x2="20" y2="17"/>'
        + '</svg>'
      : '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
        +   '<rect x="9" y="9" width="11" height="11" rx="2"/>'
        +   '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>'
        + '</svg>';
    const labelHtml = o.label
      ? '<span class="copy-btn-label">' + escapeHtml(o.label) + '</span>'
      : '';
    const cls = 'copy-btn' + (o.label ? ' copy-btn-labeled' : '');
    return '<button class="' + cls + '" type="button"'
      + ' data-copy="' + escapeHtml(value) + '"'
      + ' data-tooltip="' + escapeHtml(tip || 'Copy') + '"'
      + ' aria-label="' + escapeHtml(tip || 'Copy') + '">'
      + iconSvg + labelHtml + '</button>';
  }
  function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); resolve(); }
      catch (e) { reject(e); }
      finally { document.body.removeChild(ta); }
    });
  }

  // Classify a triggered_by value into a human-readable trigger reason.
  // Maps known GitLab CI_PIPELINE_SOURCE / Jenkins BUILD_CAUSE vocabularies;
  // anything else is treated as a user login.
  function classifyTrigger(value) {
    if (!value) return { kind: 'unknown', label: '' };
    var v = String(value).toLowerCase();
    var map = {
      push: 'pushed commit',
      web: 'manual (web UI)',
      api: 'manual (API)',
      trigger: 'pipeline trigger token',
      schedule: 'scheduled run',
      merge_request_event: 'merge request',
      external: 'external pipeline',
      pipeline: 'parent pipeline',
      chat: 'chatops',
      parent_pipeline: 'parent pipeline'
    };
    if (map[v]) return { kind: 'source', label: map[v] };
    if (v.indexOf('triggered') !== -1 || v.indexOf('started by') !== -1) {
      return { kind: 'cause', label: String(value) };
    }
    return { kind: 'user', label: 'user login' };
  }

  // Build a small table of required tools: name, version, presence.
  // Presence comes from tech.prereqs_present (booleans), versions from
  // tech.tool_versions (semver strings). Missing tools land with x marker.
  function buildToolsTable(presence, versions) {
    var names = ['yq', 'jq', 'jv'];
    var rows = names.map(function (name) {
      var p = presence[name];
      var present = (p === true || p === 'true');
      var ver = versions[name] || '';
      var marker = present
        ? '<span class="tool-ok" aria-label="present">'
          + '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8.5l3 3 7-7"/></svg>'
          + '</span>'
        : '<span class="tool-missing" aria-label="missing">'
          + '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4l8 8M12 4l-8 8"/></svg>'
          + '</span>';
      return '<tr>'
        + '<td class="tool-name mono">' + escapeHtml(name) + '</td>'
        + '<td class="tool-version mono">' + escapeHtml(ver || '-') + '</td>'
        + '<td class="tool-status">' + marker + '</td>'
        + '</tr>';
    });
    return '<table class="tools-table"><tbody>' + rows.join('') + '</tbody></table>';
  }

  // Derive a specific reason for an init failure from the available signals.
  // Falls back to the generic "exited with code N" message when nothing
  // specific is inferable.
  function initFailureReason(s) {
    var t = s.tech || {};
    var b = s.business || {};
    var ec = String(t.exit_code != null ? t.exit_code : (s.rc != null ? s.rc : ''));
    if (t.config_valid === false || t.config_valid === 'false') {
      return 'brik.yml validation failed - the configuration was rejected by the schema check.';
    }
    if (t.prereqs_present) {
      var missing = Object.keys(t.prereqs_present).filter(function (k) {
        return t.prereqs_present[k] !== true && t.prereqs_present[k] !== 'true';
      });
      if (missing.length) {
        return 'Required tool missing on the runner: ' + missing.join(', ') + '.';
      }
    }
    if (ec === '7' || ec === '2') {
      return 'Invalid brik.yml or input - init could not load a valid configuration.';
    }
    if (ec === '3') return 'A required tool is missing on the runner.';
    if (ec === '4') return 'Invalid execution environment detected by init.';
    return b.reason || ('Init exited with code ' + ec + '.');
  }

  // Per-stage renderers ----------------------------------------------
  // init's responsibility is discovery + pre-flight validation. Do not
  // re-show the commit (already in the hero); focus on what init decided:
  // stack/version, runner image, config validation, required tools, and
  // who/what triggered the run.
  function renderInit(b, t, r) {
    t = t || {}; r = r || {};
    // On failure, the dedicated failure banner (rendered above by
    // renderBusiness) already explains the cause. Skip the tiles to avoid
    // showing sparse half-data - e.g. a tools table with all "missing"
    // because prereqs_present was not written before init aborted.
    if (t.status === 'failed') return '';

    // --- Resolved configuration ---
    const stack    = t.stack || '';
    const stackV   = t.stack_version || '';
    const stackHtml = stack
      ? '<span class="stack-chip"><span class="lang">' + escapeHtml(stack) + '</span>'
        + (stackV ? '<span class="ver mono">' + escapeHtml(stackV) + '</span>' : '')
        + '</span>'
      : '<span class="hint">unknown</span>';
    const runnerImg = r.image || '';
    const runnerCell = runnerImg
      ? '<span class="mono image-ref">' + escapeHtml(runnerImg) + '</span>' + copyBtn(runnerImg, 'Copy image name')
      : '<span class="hint">unknown</span>';
    const cfgTiles = [
      tile('Stack', stackHtml, ''),
      tile('Runner image', runnerCell, '')
    ];

    // --- Pre-flight validation ---
    const cfgValid = t.config_valid;
    const cfgValidIsTrue  = (cfgValid === true || cfgValid === 'true');
    const cfgValidIsFalse = (cfgValid === false || cfgValid === 'false');
    const cfgPill = cfgValidIsTrue
      ? '<span class="status-pill ok">valid</span>'
      : (cfgValidIsFalse ? '<span class="status-pill bad">invalid</span>' : '<span class="hint">unknown</span>');
    const cfgFile = t.config_file || '';
    const cfgFileSub = cfgFile ? '<span class="mono faint" data-tooltip="' + escapeHtml(cfgFile) + '">' + escapeHtml(cfgFile.split('/').slice(-2).join('/')) + '</span>' : '';
    const toolsHtml = buildToolsTable(t.prereqs_present || {}, t.tool_versions || {});
    const validationTiles = [
      tile('brik.yml', cfgPill, cfgFileSub),
      tile('Required tools', toolsHtml, '')
    ];

    // --- Trigger context (single line: value + dot + reason) ---
    const trigBy = b.triggered_by || '';
    const trigClass = classifyTrigger(trigBy);
    const ctxRel = ((data.pipeline || {}).context === 'release') ? 'tag push (release)' : '';
    const trigReason = ctxRel || trigClass.label || '';
    const trigLine = (trigBy || trigReason)
      ? '<div class="trigger-line">'
        + (trigBy ? '<span class="trigger-value mono">' + escapeHtml(trigBy) + '</span>' : '<span class="trigger-value muted">-</span>')
        + (trigBy && trigReason ? '<span class="dot-sep">&middot;</span>' : '')
        + (trigReason ? '<span class="trigger-meta">' + escapeHtml(trigReason) + '</span>' : '')
        + '</div>'
      : '';

    return ''
      + sectionLabel('Resolved configuration')
      + '<div class="stage-grid">' + cfgTiles.join('') + '</div>'
      + sectionLabel('Pre-flight validation')
      + '<div class="stage-grid">' + validationTiles.join('') + '</div>'
      + (trigLine ? sectionLabel('Trigger context') + trigLine : '');
  }
  // release's responsibility is to decide the version that will ship and to
  // create/verify the git tag. Panel emphasises traceability: version
  // decision first (dominant), tag operation second.
  function renderRelease(b, t) {
    t = t || {};
    const fromV = b.previous_version || '-';
    const toV   = b.new_version || '-';
    const same  = (fromV === toV);
    const bump  = String(b.bump_type || '').toLowerCase();
    const tag   = b.tag || {};
    const tagName = tag.name || '';
    const tagSha  = tag.sha || '';
    const tUrl    = (tagName && REPO) ? tagUrlOf(REPO, tagName) : null;
    const repoHost = REPO ? hostOf(REPO.base) : '';

    // Bump classification (user-facing label).
    //   explicit + same  -> "tag-driven"
    //   patch/minor/major + diff -> "auto-bumped (<bump>)"
    //   same + other     -> "no bump"
    //   diff + other     -> bump value as-is
    let bumpLabel = '';
    if (bump === 'explicit' && same)                                       bumpLabel = 'tag-driven release';
    else if (!same && (bump === 'patch' || bump === 'minor' || bump === 'major')) bumpLabel = 'auto-bumped (' + bump + ')';
    else if (same)                                                         bumpLabel = 'no bump';
    else if (bump)                                                         bumpLabel = bump;

    // Version display: arrow only when there is a real bump; single big
    // value otherwise so the "no bump" case does not lie visually.
    const versionHtml = same
      ? '<div class="version-arrow same-version"><span class="to">' + escapeHtml(toV) + '</span></div>'
      : '<div class="version-arrow"><span class="from">' + escapeHtml(fromV) + '</span><span class="arrow">-&gt;</span><span class="to">' + escapeHtml(toV) + '</span></div>';

    // --- Section 1: Version decision ---
    const decisionTiles = [
      tile('Version', versionHtml, bumpLabel ? escapeHtml(bumpLabel) : '')
    ];
    if (t.strategy || t.tag_prefix) {
      const strat = t.strategy || '-';
      const prefix = t.tag_prefix ? "prefix '" + t.tag_prefix + "'" : '';
      decisionTiles.push(tile('Strategy', '<span class="mono">' + escapeHtml(strat) + '</span>', escapeHtml(prefix)));
    }

    // --- Section 2: Tag operation ---
    const tagTiles = [];
    if (tagName) {
      const tagTip = repoHost ? 'Git tag on ' + repoHost : 'Git tag';
      const nameHtml = tUrl
        ? '<a href="' + escapeHtml(tUrl) + '" target="_blank" rel="noopener" class="mono" data-tooltip="' + escapeHtml(tagTip) + '">' + escapeHtml(tagName) + '</a>'
        : '<span class="mono">' + escapeHtml(tagName) + '</span>';
      const props = tag.annotated ? 'annotated tag' : 'lightweight tag';
      tagTiles.push(tile('Tag name', nameHtml + copyBtn(tagName, 'Copy tag name'), props));
    }
    if (tagSha) {
      const shaShort = tagSha.length > 12 ? tagSha.slice(0, 12) : tagSha;
      tagTiles.push(tile('Tagged commit', '<span class="mono">' + escapeHtml(shaShort) + '</span>' + copyBtn(tagSha, 'Copy full commit SHA'), ''));
    }

    return ''
      + sectionLabel('Version decision')
      + '<div class="stage-grid">' + decisionTiles.join('') + '</div>'
      + (tagTiles.length ? sectionLabel('Tag operation') + '<div class="stage-grid">' + tagTiles.join('') + '</div>' : '');
  }

  // Specific failure reason for the release stage. Useful exit codes:
  // 5 = EXTERNAL_FAIL (git push refused), 6 = IO_FAILURE (local tag write).
  function releaseFailureReason(s) {
    const t = s.tech || {};
    const b = s.business || {};
    const ec = String(t.exit_code != null ? t.exit_code : (s.rc != null ? s.rc : ''));
    if (b.reason) return b.reason;
    if (ec === '5') return 'Could not push the git tag to the remote (external command failed).';
    if (ec === '6') return 'Could not write the git tag locally (I/O failure).';
    return null; // fall back to generic banner
  }
  // build's responsibility is to produce the deployable artifact. Panel
  // shows that artifact (file when known via main_file, otherwise directory)
  // plus its SHA-256, then the build method (stack + tool + command) as a
  // secondary single-line block. The runner-local path is intentionally
  // omitted: it is ephemeral and any registry coordinates belong to the
  // package stage (Docker image, PyPI/npm/Maven publish).
  function renderBuild(b, t) {
    t = t || {};
    const a = b.artifact || {};
    const main = a.main_file || '';
    const dirName = a.name || '';
    const displayName = main ? main.split('/').pop() : (dirName || '-');
    const isEmpty = (a.size_bytes != null && Number(a.size_bytes) === 0);
    const sizeBadge = (a.size_bytes != null)
      ? '<span class="size-badge' + (isEmpty ? ' warn' : '') + '">' + fmtBytes(a.size_bytes) + (isEmpty ? ' <span class="empty-mark">empty</span>' : '') + '</span>'
      : '';
    const subParts = [];
    if (a.type)     subParts.push(escapeHtml(a.type));
    if (main && dirName) subParts.push('in ' + escapeHtml(dirName) + '/');
    const subText = subParts.join(' &middot; ');
    const artifactValue = '<span class="mono">' + escapeHtml(displayName) + '</span>' + sizeBadge;
    const artifactTiles = [tile('Artifact', artifactValue, subText, { warning: isEmpty })];
    if (a.sha256) {
      artifactTiles.push(
        tile('SHA-256', shaCell(a.sha256) + copyBtn(a.sha256, 'Copy full SHA-256'), '')
      );
    }

    // --- Build method (secondary, single line like .trigger-line) ---
    const stack   = t.stack || '';
    const tool    = t.tool || '';
    const command = t.command || '';
    const methodParts = [];
    if (stack)   methodParts.push('<span class="method-key">stack</span> <span class="mono">' + escapeHtml(stack) + '</span>');
    if (tool && tool !== 'auto')     methodParts.push('<span class="method-key">tool</span> <span class="mono">' + escapeHtml(tool) + '</span>');
    if (tool === 'auto')             methodParts.push('<span class="method-key">tool</span> <span class="muted mono">auto</span>');
    if (command) methodParts.push('<span class="method-key">command</span> <span class="mono">' + escapeHtml(command) + '</span>');
    const methodLine = methodParts.length
      ? '<div class="method-line">' + methodParts.join('<span class="dot-sep">&middot;</span>') + '</div>'
      : '';

    return ''
      + sectionLabel('Produced artifact')
      + '<div class="stage-grid">' + artifactTiles.join('') + '</div>'
      + (methodLine ? sectionLabel('Build method') + methodLine : '');
  }
  // lint's responsibility is to verify code quality (linters) and style
  // (formatters). Panel: a checks table (one row per check), and a
  // violations subsection when SARIF was emitted - otherwise a discreet
  // "no SARIF reported" hint so the user understands why per-tool counts
  // are absent.
  function renderLint(b, t) {
    b = b || {}; t = t || {};
    const tools  = t.tools  || {};
    const checks = t.checks || [];
    const violations = b.violations || null;

    // --- Section 1: Quality checks (Check / Tool, one row per check) ---
    // Same 2-column shape as sast/scan/test for visual coherence. The
    // overall verdict is shown by the Violations counter below; per-check
    // breakdown (when SARIF was aggregated) lives in business.violations
    // .by_check inside the data island for debugging.
    const checkRows = checks.map((c) => {
      const tool = tools[c] || '-';
      return '<tr>'
        + '<td class="tool-name mono">' + escapeHtml(c) + '</td>'
        + '<td class="tool-version mono">' + escapeHtml(tool) + '</td>'
        + '</tr>';
    });

    let checksHtml;
    if (checkRows.length === 0) {
      checksHtml = '<div class="hint">No checks reported.</div>';
    } else {
      checksHtml = '<table class="tools-table lint-table"><thead><tr>'
        + '<th class="tool-name">Check</th>'
        + '<th class="tool-version">Tool</th>'
        + '</tr></thead><tbody>' + checkRows.join('') + '</tbody></table>';
    }

    // --- Section 2: Violations ---
    // Uses the same findingsCounter component as sast/scan/container-scan
    // so the visual treatment of the "primary result" is uniform across
    // every verify stage. Pass label='violation' so the counter pluralises
    // correctly ("0 violations" / "1 violation"). When SARIF was not
    // aggregated, the body becomes a discreet hint so the tile envelope
    // stays consistent across runs.
    let violationsBody;
    if (violations) {
      const total = violations.total || 0;
      const bySev = violations.by_severity || {};
      const state = (total === 0) ? 'clean' : 'dirty';
      violationsBody = findingsCounter(total, '', state, 'violation');
      if (total > 0) {
        violationsBody += '<div class="findings-severity-wrap">' + severityBar(bySev, total) + '</div>';
      }
    } else {
      violationsBody = '<div class="lint-no-sarif">No SARIF report aggregated - per-check violation counts unavailable. See job logs for tool output.</div>';
    }

    return ''
      + sectionLabel('Quality checks')
      + sectionTile(checksHtml)
      + sectionLabel('Violations')
      + sectionTile(violationsBody);
  }

  // Lint failure reason mapping: 10 = check failed (violations found),
  // 2 = invalid config / input, 3 = required tool missing.
  function lintFailureReason(s) {
    const t = s.tech || {};
    const b = s.business || {};
    const ec = String(t.exit_code != null ? t.exit_code : (s.rc != null ? s.rc : ''));
    const v = b.violations || null;
    if (ec === '10') {
      if (v && v.by_check) {
        const parts = Object.keys(v.by_check)
          .filter((k) => v.by_check[k] > 0)
          .map((k) => k + '=' + v.by_check[k]);
        if (parts.length) {
          return 'Linter found ' + (v.total || 0) + ' violation(s) [' + parts.join(', ') + ']. Fix the source and re-run.';
        }
      }
      return 'Linter found violations and exited non-zero. Check the job logs for details.';
    }
    if (ec === '2') return 'Invalid lint configuration or input.';
    if (ec === '3') return 'Required lint tool missing on the runner.';
    if (ec === '4') return 'Invalid lint execution environment.';
    return b.reason || null;
  }
  // Check / Tool table shell, used by every stage that surfaces tools.
  // Pass the rendered <tr> rows; the shell wraps them in the standard
  // tools-table chrome. The sast-table class is a semantic marker (no
  // unique CSS rule -- visual style comes from tools-table).
  function checkTableShell(bodyRowsHtml) {
    return '<table class="tools-table sast-table"><thead><tr>'
      + '<th class="tool-name">Check</th>'
      + '<th class="tool-version">Tool</th>'
      + '</tr></thead><tbody>' + bodyRowsHtml + '</tbody></table>';
  }
  // Single-row Check / Tool table, reused by sast, container-scan,
  // scan and package.
  function checkTable(checkLabel, toolName) {
    return checkTableShell(
      '<tr><td class="tool-name mono">' + escapeHtml(checkLabel) + '</td>'
      +   '<td class="tool-version mono">' + escapeHtml(toolName) + '</td></tr>'
    );
  }
  // Findings counter with three visual states:
  //   - clean   (green): total = 0, nothing detected
  //   - warning (orange): total > 0 but failing = 0 (everything ignored
  //                        by policy / suppressions). Non-actionable but
  //                        worth surfacing.
  //   - dirty   (red): failing > 0 -- requires action.
  // The optional `state` argument overrides the default 2-state derivation
  // (clean vs dirty). Callers that distinguish ignored from failing (sast,
  // container-scan) should pass an explicit state; callers without a
  // policy/ignored notion (scan deps, scan secrets) can omit it.
  function findingsCounter(total, chipHtml, state, label) {
    const resolved = state || (total === 0 ? 'clean' : 'dirty');
    const counterClass = 'findings-counter ' + resolved;
    const noun = label || 'finding';
    const counterHtml = '<div class="' + counterClass + '">'
      + '<span class="big-number">' + total + '</span>'
      + '<span class="counter-label">' + escapeHtml(noun) + (total === 1 ? '' : 's') + '</span>'
      + '</div>';
    return '<div class="findings-counter-row">' + counterHtml + (chipHtml || '') + '</div>';
  }
  // Shared renderer for findings stages (sast + container-scan).
  // Layout : checks table (Check / Tool, like lint) + a dominant findings
  // counter coloured green when zero / red when > 0, with a CWE coverage
  // chip alongside. Failing breakdown + severity bar + ignored disclosure
  // appear only when findings are non-empty. No SARIF download link
  // (workspace paths are not browseable from the report viewer).
  function renderFindingsStage(b, label, t) {
    b = b || {}; t = t || {};
    const f = b.findings || {};
    const bs = f.by_severity || {};
    const total = f.total || 0;

    // failing can be either a legacy number or the v1.1 object form.
    let failingTotal = 0, hasFix = 0, noFix = 0;
    if (typeof f.failing === 'number') {
      failingTotal = f.failing;
    } else if (f.failing && typeof f.failing === 'object') {
      failingTotal = f.failing.total || 0;
      hasFix = f.failing.has_fix || 0;
      noFix  = f.failing.no_fix  || 0;
    }
    const ignoredTotal = (f.ignored && f.ignored.total) || 0;
    const ignoredBySource   = (f.ignored && f.ignored.by_source)   || {};
    const ignoredBySeverity = (f.ignored && f.ignored.by_severity) || {};
    const cweCount = Array.isArray(f.cwe) ? f.cwe.length : 0;
    const isClean  = (total === 0);

    // --- Section 1: Security checks (Check / Tool table, lint-table style) ---
    const checkLabel = label || 'static analysis';
    const toolName   = t.tool || '-';
    const checksTable = checkTable(checkLabel, toolName);

    // --- Section 2: Findings counter + CWE chip ---
    // 3-state: green when total=0, orange when total>0 but failing=0
    // (everything ignored by policy), red when failing>0.
    const cweChip = cweCount > 0
      ? '<span class="cwe-chip" data-tooltip="Number of distinct CWE categories the ruleset covers"><span class="mono">' + cweCount + '</span> CWEs analysed</span>'
      : '';
    const counterState = (total === 0) ? 'clean'
                       : (failingTotal === 0) ? 'warning'
                       : 'dirty';
    const counterRow = findingsCounter(total, cweChip, counterState);

    // --- Failing breakdown + severity bar (only when total > 0) ---
    let detailsBlock = '';
    if (!isClean) {
      const fixSub = (hasFix > 0 || noFix > 0)
        ? ' <span class="muted mono">(has_fix: ' + hasFix + ' &middot; no_fix: ' + noFix + ')</span>'
        : '';
      detailsBlock = '<div class="findings-failing-line">'
        + '<span class="meta-key">Failing</span> '
        + '<span class="mono">' + failingTotal + '</span>'
        + fixSub
        + '</div>'
        + '<div class="findings-severity-wrap">' + severityBar(bs, total) + '</div>';
    }

    // --- Ignored disclosure (only if ignored.total > 0) ---
    // Renders explicit Source/Count and Severity/Count tables so every
    // severity (including critical and high) is visible at a glance. A
    // path-based policy intentionally captures all severities under the
    // matched globs -- this table makes that fact verifiable rather than
    // implied by a proportional bar.
    let ignoredBlock = '';
    if (ignoredTotal > 0) {
      const srcKeys = Object.keys(ignoredBySource);
      const srcRows = srcKeys.map((k) =>
        '<tr><td class="mono">' + escapeHtml(k) + '</td><td class="mono num">' + (ignoredBySource[k] || 0) + '</td></tr>'
      ).join('');
      const srcTable = srcKeys.length
        ? '<table class="ignored-source-table"><thead><tr><th>Source</th><th>Count</th></tr></thead><tbody>' + srcRows + '</tbody></table>'
        : '<div class="muted">No source attribution.</div>';

      const sevRows = SEV_ORDER.map((k) => {
        const n = ignoredBySeverity[k] || 0;
        const cls = (n > 0) ? ('sev-' + k) : 'muted';
        return '<tr class="' + cls + '">'
             + '<td><span class="dot"></span>' + escapeHtml(k) + '</td>'
             + '<td class="mono num">' + n + '</td>'
             + '</tr>';
      }).join('');
      const sevTable = '<table class="ignored-severity-table">'
        + '<thead><tr><th>Severity</th><th>Count</th></tr></thead>'
        + '<tbody>' + sevRows + '</tbody>'
        + '<tfoot><tr><td>total</td><td class="mono num">' + ignoredTotal + '</td></tr></tfoot>'
        + '</table>';

      ignoredBlock = '<details class="ignored-disclosure">'
        + '<summary><span class="chev">&rsaquo;</span> Ignored <span class="mono">' + ignoredTotal + '</span></summary>'
        + '<div class="ignored-body">'
        +   '<div class="section-label">By source</div>'
        +   srcTable
        +   '<div class="section-label">By severity</div>'
        +   sevTable
        + '</div>'
        + '</details>';
    }

    // --- Items disclosure (collapsed by default; mounted post-render with
    // mountFindingsPanel so the interactive UI -- severity chips, search,
    // expandable cards -- is scoped to this stage's items only). ---
    const items = Array.isArray(f.items) ? f.items : [];
    let itemsBlock = '';
    if (items.length > 0) {
      itemsBlock = '<details class="items-disclosure">'
        + '<summary><span class="chev">&rsaquo;</span> View items <span class="mono">' + items.length + '</span></summary>'
        + '<div class="findings-items-panel"></div>'
        + '</details>';
    }

    return ''
      + sectionLabel('Security checks')
      + sectionTile(checksTable)
      + sectionLabel('Findings')
      + sectionTile(counterRow + detailsBlock + ignoredBlock + itemsBlock);
  }
  // Scan stage: two sondes (dependency vulnerabilities + secret scan)
  // surfaced through the same Checks/Findings shape as lint and sast for
  // visual coherence. The Checks tile holds one 2-row Check/Tool table
  // (one row per sonde). The Findings tile holds a group per sonde, each
  // with its own counter and optional context (SBOM chip + severity bar
  // for deps; counter only for secrets - the count is the signal). The
  // sonde sub-label sits between the section-label and the counter so the
  // three-level hierarchy stays readable.
  function renderScan(b, t) {
    b = b || {}; t = t || {};

    // --- Dependencies sonde ---
    const deps     = b.deps || {};
    const dv       = deps.vulnerabilities || {};
    const depsTot  = dv.total || 0;
    const depsTool = (t.deps && t.deps.tool) || '-';
    const sbomFile = deps.sbom_path ? String(deps.sbom_path).split('/').pop() : '';
    const sbomChip = sbomFile
      ? '<span class="cwe-chip" data-tooltip="' + escapeHtml(deps.sbom_path) + '">SBOM: <span class="mono">' + escapeHtml(sbomFile) + '</span></span>'
      : '';
    const depsCounter    = findingsCounter(depsTot, sbomChip);
    let   depsDetails    = '';
    if (depsTot > 0) {
      const affected = (deps.affected_packages != null)
        ? '<div class="findings-failing-line"><span class="meta-key">Affected packages</span> <span class="mono">' + deps.affected_packages + '</span></div>'
        : '';
      depsDetails = affected + '<div class="findings-severity-wrap">' + severityBar(dv.by_severity || {}, depsTot) + '</div>';
    }

    // --- Secrets sonde ---
    const sec      = b.secret || {};
    const secTot   = sec.findings_count || 0;
    const secTool  = (t.secret && t.secret.tool) || '-';
    const secCounter    = findingsCounter(secTot, '');

    // Combined 2-row checks table: one row per sonde.
    const checksTable = checkTableShell(
      '<tr><td class="tool-name mono">dependency vulnerabilities</td>'
      +   '<td class="tool-version mono">' + escapeHtml(depsTool) + '</td></tr>'
      + '<tr><td class="tool-name mono">secret scan</td>'
      +   '<td class="tool-version mono">' + escapeHtml(secTool) + '</td></tr>'
    );

    // Two grouped findings: each gets a small sonde label above its counter.
    const findingsBody = ''
      + '<div class="scan-finding">'
      +   '<div class="scan-finding-label">dependency vulnerabilities</div>'
      +   depsCounter + depsDetails
      + '</div>'
      + '<div class="scan-finding">'
      +   '<div class="scan-finding-label">secret scan</div>'
      +   secCounter
      + '</div>';

    return ''
      + sectionLabel('Checks')
      + sectionTile(checksTable)
      + sectionLabel('Findings')
      + sectionTile(findingsBody);
  }
  // Test stage: three sections. Test execution shows the test tooling
  // (Check/Tool table, extra rows when framework or coverage_tool diverge
  // from the runner tool). Results shows the counts as a mini-table
  // (Passed/Failed/Skipped/Total) -- or a verdict fallback derived from
  // tech.status/tech.exit_code when business.tests was not harvested
  // (Java/Maven, or test stage that crashed before reports were collected).
  // Coverage keeps the existing line + branch bars with 80/60 thresholds.
  function renderTest(b, t) {
    b = b || {}; t = t || {};

    // --- Section 1: Test execution (Check / Tool, multi-row when divergent) ---
    const tool         = t.tool || '-';
    const framework    = t.framework || '';
    const coverageTool = t.coverage_tool || '';
    const rows = ['<tr><td class="tool-name mono">unit tests</td>'
                + '<td class="tool-version mono">' + escapeHtml(tool) + '</td></tr>'];
    if (framework && framework !== tool) {
      rows.push('<tr><td class="tool-name mono">framework</td>'
              + '<td class="tool-version mono">' + escapeHtml(framework) + '</td></tr>');
    }
    if (coverageTool && coverageTool !== 'auto' && coverageTool !== tool) {
      rows.push('<tr><td class="tool-name mono">coverage</td>'
              + '<td class="tool-version mono">' + escapeHtml(coverageTool) + '</td></tr>');
    }
    const checksTable = checkTableShell(rows.join(''));

    // --- Section 2: Results (counts mini-table, or fallback verdict) ---
    const tests = b.tests || null;
    const hasCounts = tests && (tests.total != null || tests.passed != null
                              || tests.failed != null || tests.skipped != null);
    let resultsBlock;
    if (hasCounts) {
      const passed  = tests.passed  || 0;
      const failed  = tests.failed  || 0;
      const skipped = tests.skipped || 0;
      const total   = tests.total != null ? tests.total : (passed + failed + skipped);
      resultsBlock = '<table class="results-table"><thead><tr>'
        + '<th>Passed</th><th>Failed</th><th>Skipped</th><th>Total</th>'
        + '</tr></thead><tbody><tr>'
        + '<td class="' + (passed > 0 ? 'cnt-good' : 'muted') + '">' + passed + '</td>'
        + '<td class="' + (failed > 0 ? 'cnt-bad'  : 'muted') + '">' + failed + '</td>'
        + '<td class="muted">' + skipped + '</td>'
        + '<td>' + total + '</td>'
        + '</tr></tbody></table>';
    } else {
      const ec = (t.exit_code != null) ? String(t.exit_code) : '';
      const verdict = (t.status === 'success') ? 'success'
                    : (t.status === 'failed')  ? 'failed'
                    : 'unknown';
      const verdictClass = (verdict === 'success') ? 'success'
                         : (verdict === 'failed')  ? 'failed'
                         : 'muted';
      const ecChip = ec ? ' <span class="muted mono">(exit ' + escapeHtml(ec) + ')</span>' : '';
      resultsBlock = '<div class="lint-no-sarif">No test counts reported. '
        + 'Verdict: <span class="value ' + verdictClass + '">' + escapeHtml(verdict) + '</span>'
        + ecChip
        + '</div>';
    }

    // --- Section 3: Coverage bars (lines + branches, 80/60 thresholds) ---
    const cov = b.coverage || {};
    const line   = parseFloat(cov.line_pct);
    const branch = parseFloat(cov.branch_pct);
    const bar = (label, pct) => {
      if (isNaN(pct)) return '';
      const cls = pct >= 80 ? '' : (pct >= 60 ? 'mid' : 'low');
      return '<div class="cov-bar">'
        + '<div class="row"><span class="k">' + label + '</span><span class="v">' + pct.toFixed(2) + '%</span></div>'
        + '<div class="track"><div class="fill ' + cls + '" style="width:' + Math.min(100, Math.max(0, pct)) + '%;"></div></div>'
        + '</div>';
    };
    const bars = [bar('lines', line), bar('branches', branch)]
      .filter(Boolean)
      .join('');
    const coverageBlock = bars
      ? bars
      : '<div class="hint">No coverage reported.</div>';

    return ''
      + sectionLabel('Test execution')
      + sectionTile(checksTable)
      + sectionLabel('Results')
      + sectionTile(resultsBlock)
      + sectionLabel('Coverage')
      + sectionTile(coverageBlock);
  }
  // Best-effort registry URL from the host. Internal/dev hosts (.test,
  // .local, .internal, or with an explicit port suggesting self-hosted
  // setup) get http://; everything else gets https://. We link to the
  // registry root rather than a tag-specific URL because the deep-link
  // format varies wildly across Nexus / Harbor / GHCR / Docker Hub.
  function registryUrl(host) {
    if (!host) return '';
    const dev = /\.(test|local|internal)(?::\d+)?$/i.test(host)
             || /:(8080|8082|5000|8081)$/i.test(host)
             || /^localhost(?::\d+)?$/i.test(host)
             || /^(127\.0\.0\.1|host\.docker\.internal)(?::\d+)?$/i.test(host);
    return (dev ? 'http://' : 'https://') + host + '/';
  }
  // Package stage: container image dominant with copy buttons (image ref
  // + docker pull command), digest as a secondary row with its own copy
  // button, then a 2-column metadata grid (Registry with a clickable
  // host + namespace/repository; Packager as a Check/Tool table).
  // When the stage was skipped (no packager configured) a dedicated
  // muted message replaces the panel entirely.
  function renderPackage(b, t) {
    b = b || {}; t = t || {};

    // --- Skipped fallback ---
    if (t.status === 'skipped' || b.status === 'skipped') {
      return '<div class="pkg-skipped">Package skipped (no packager configured).</div>';
    }

    const img = b.image || {};
    const reg = b.registry || {};
    const fullName = img.full_name
      || (img.name && img.tag ? img.name + ':' + img.tag : img.name);

    // --- Section 1: Container image (big + copy buttons) ---
    const m = fullName ? fullName.match(/^(?:(.+?)\/)?([^/]+\/[^:]+)(?::(.+))?$/) : null;
    let imgHtml = '<span class="image-ref">' + escapeHtml(fullName || '-') + '</span>';
    if (m) {
      imgHtml = '<span class="image-ref">'
        + (m[1] ? '<span class="registry">' + escapeHtml(m[1]) + '/</span>' : '')
        + '<span class="repo">' + escapeHtml(m[2]) + '</span>'
        + (m[3] ? '<span>:</span><span class="tag">' + escapeHtml(m[3]) + '</span>' : '')
        + '</span>';
    }
    const actions = fullName
      ? '<span class="pkg-actions">'
        + copyBtn(fullName, 'Copy image reference')
        + copyBtn('docker pull ' + fullName, 'Copy docker pull command', { icon: 'pull', label: 'docker pull' })
        + '</span>'
      : '';
    const imageBlock = fullName
      ? '<div class="pkg-image-row">' + imgHtml + actions + '</div>'
      : '<div class="pkg-skipped">No image produced.</div>';

    // --- Section 1b: Digest line (when present) ---
    const digestBlock = img.digest
      ? '<div class="pkg-digest-row">'
        + '<span class="meta-key">Digest</span>'
        + '<span class="digest-line">' + escapeHtml(img.digest) + '</span>'
        + copyBtn(img.digest, 'Copy digest')
        + '</div>'
      : '';

    // --- Section 2: Distribution (Registry tile + Packager tile) ---
    const regHost  = reg.host || '';
    // Prefer the explicit ui_url recorded at push time
    // (business.registry.ui_url) -- the docker push endpoint is rarely the
    // human-browseable URL (Nexus 3 splits :8082 push from :8081 UI).
    // Heuristic-derived URL is used only as a fallback for setups that
    // don't configure BRIK_PACKAGE_REGISTRY_UI_URL.
    const regUrl   = reg.ui_url
      ? String(reg.ui_url)
      : (regHost ? registryUrl(regHost) : '');
    const regValue = regHost
      ? (regUrl
          ? '<a class="meta-value" href="' + escapeHtml(regUrl) + '" target="_blank" rel="noopener" data-tooltip="Open registry">'
            + escapeHtml(regHost) + '</a>'
          : '<span class="meta-value">' + escapeHtml(regHost) + '</span>')
      : '<span class="meta-value muted">-</span>';
    const regSub = (reg.namespace || reg.repository)
      ? '<div class="meta-sub">' + escapeHtml((reg.namespace ? reg.namespace + '/' : '') + (reg.repository || '')) + '</div>'
      : '';
    const registryBlock = '<div class="pkg-meta-tile">'
      + '<span class="meta-key">Registry</span>'
      + regValue
      + regSub
      + '</div>';

    // Packager Check/Tool table - same shape as the leading Check/Tool
    // table of every other stage (lint Quality checks, sast Security
    // checks, scan Checks, test Test execution). It opens the package
    // panel for visual coherence: the user sees WHICH tool was used
    // before seeing the artifact and the distribution.
    const packager = t.packager || '-';
    const packagerTable = checkTable('container packaging', packager);

    return ''
      + sectionLabel('Packager')
      + sectionTile(packagerTable)
      + sectionLabel('Container image')
      + sectionTile(imageBlock + digestBlock)
      + sectionLabel('Distribution')
      + sectionTile(registryBlock);
  }
  // deploy.business shape (see brik/lib/stages/deploy.sh):
  //   { environments: [{name, target, namespace?, strategy?}], status, reason }
  // environments may be absent (deploy stage ran but did nothing actionable
  // for this pipeline). status='error' tints each env card red; the human
  // reason string (business.reason, e.g. "failure (fix available, not
  // applied)") is surfaced via the standard failureBanner upstream.
  const DEPLOY_TARGET_ICONS = {
    k8s: '<svg viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
      + '<circle cx="8" cy="3.5" r="1.2"/><circle cx="3.5" cy="12.3" r="1.2"/><circle cx="12.5" cy="12.3" r="1.2"/>'
      + '<path d="M8 4.7l-4 6.6M8 4.7l4 6.6M4.7 12.3h6.6"/></svg>',
    gitops: '<svg viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
      + '<circle cx="4" cy="3.5" r="1.2"/><circle cx="4" cy="12.5" r="1.2"/><circle cx="12" cy="8" r="1.2"/>'
      + '<path d="M4 4.7v6.6M4 8h2a3 3 0 0 0 3-3v-.5"/><path d="M9 7.5A3 3 0 0 0 6 4"/></svg>'
  };
  function deployTargetChip(target) {
    const t = (target || '').toLowerCase();
    const icon = DEPLOY_TARGET_ICONS[t] || '';
    return '<span class="deploy-target-chip" data-target="' + escapeHtml(t) + '">'
      + icon
      + '<span>' + escapeHtml(target || '-') + '</span>'
      + '</span>';
  }
  // One table row per environment. The Target cell keeps the colored
  // deployTargetChip so k8s / gitops stay visually distinct. Namespace
  // and Strategy degrade to a muted dash when absent (gitops envs have
  // no namespace; legacy entries may have no strategy).
  function deployEnvRow(env, isError) {
    const name = env.name || '-';
    const target = env.target || '-';
    const ns = env.namespace;
    const strat = env.strategy;
    const nameCls = 'deploy-env-name' + (isError ? ' error' : '');
    const nsCell = ns
      ? '<td class="mono">' + escapeHtml(ns) + '</td>'
      : '<td><span class="muted">-</span></td>';
    const stratCell = strat
      ? '<td>' + escapeHtml(strat) + '</td>'
      : '<td><span class="muted">-</span></td>';
    return '<tr>'
      + '<td class="' + nameCls + '">' + escapeHtml(name) + '</td>'
      + '<td>' + deployTargetChip(target) + '</td>'
      + nsCell
      + stratCell
      + '</tr>';
  }
  function deploySkipped() {
    return '<div class="deploy-skipped">'
      + '<div class="deploy-skipped-title">Deploy not executed</div>'
      + '<div class="deploy-skipped-body">No environments were deployed in this pipeline run.</div>'
      + '</div>';
  }
  function renderDeploy(b) {
    const envs = Array.isArray(b.environments) ? b.environments : [];
    if (envs.length === 0) return deploySkipped();
    const isError = b.status === 'error' || b.status === 'failed' || b.status === 'failure';
    const rows = envs.map((e) => deployEnvRow(e || {}, isError)).join('');
    const table = '<table class="deploy-env-table"><thead><tr>'
      + '<th>Environment</th><th>Target</th><th>Namespace</th><th>Strategy</th>'
      + '</tr></thead><tbody>' + rows + '</tbody></table>';
    return ''
      + sectionLabel('Environments')
      + sectionTile(table);
  }
  function deployFailureReason(s) {
    const b = s.business || {};
    if (b.reason) return b.reason;
    return null;
  }
  // Synthetic notify panel rendered from data.pipeline.notify (injected by
  // stages.notify after aggregation). Notify never emits a stage fragment in
  // .stages[] -- it is a meta-stage that consumes the aggregate -- so the
  // panel is composed outside STAGE_RENDERERS and appended at the end of
  // renderBusiness in its STAGE_ORDER position. Returns '' when the metadata
  // is absent (pre-notify-v2 archives) so the visual gracefully degrades.
  function renderNotifyPanel(n) {
    if (!n || typeof n !== 'object') return '';
    const channels = Array.isArray(n.channels) ? n.channels : [];
    const checkIcon = '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 8.5l3 3 7-7"/></svg>';
    const crossIcon = '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg>';
    const rows = channels.map((c) => {
      const cfgCls = c.configured ? 'notify-cfg-on' : 'notify-cfg-off';
      const cfgIcon = c.configured ? checkIcon : crossIcon;
      const sendCls = c.would_send ? 'notify-send-yes' : 'notify-send-no';
      const sendCell = c.would_send
        ? checkIcon
        : '<span class="notify-skip">-</span>';
      return '<tr>'
        + '<td><span class="notify-channel">' + escapeHtml(c.type || '-') + '</span></td>'
        + '<td class="col-icon ' + cfgCls + '">' + cfgIcon + '</td>'
        + '<td class="mono">' + escapeHtml(c.on || '-') + '</td>'
        + '<td class="col-icon ' + sendCls + '">' + sendCell + '</td>'
        + '</tr>';
    }).join('');
    const channelsTable = '<table class="notify-table">'
      + '<thead><tr>'
      + '<th>Channel</th><th>Configured</th><th>Policy</th><th>Will dispatch</th>'
      + '</tr></thead><tbody>' + rows + '</tbody></table>';
    // Gatekeeper renders the *pipeline verdict* - the final pass/fail
    // signal notify propagates to the CI runner so the job exits with
    // the correct code. Derived from pipeline.business.status:
    //   success -> PASS  ("All business checks passed")
    //   warning -> PASS  ("Non-critical issues - still shippable")
    //   error   -> FAIL  ("Critical failures - not shippable")
    // The visual makes the verdict unmissable (large coloured pill) and
    // explains the rationale in plain language so a reader does not need
    // the runtime semantics to understand the outcome.
    const gk = n.gatekeeper || {};
    const decision = gk.decision === 'fail' ? 'fail' : 'pass';
    const bstatus  = gk.business_status || 'unknown';
    const decisionLabel = decision === 'fail' ? 'FAIL' : 'PASS';
    const explanations = {
      success: 'All business checks passed. The pipeline is shippable.',
      warning: 'Non-critical issues detected. The pipeline is shippable but warnings warrant review.',
      error:   'Critical business failures detected. The pipeline is not shippable.',
      unknown: 'Business outcome could not be determined.'
    };
    const explanation = explanations[bstatus] || explanations.unknown;
    const gkCls = decision === 'fail' ? 'notify-gk-fail' : 'notify-gk-pass';
    const gkBlock = '<div class="notify-gatekeeper ' + gkCls + '">'
      + '<div class="notify-gk-header">'
      +   '<span class="notify-gk-verdict">' + decisionLabel + '</span>'
      +   '<span class="notify-gk-source">based on business status: '
      +     '<span class="notify-gk-bstatus">' + escapeHtml(bstatus) + '</span>'
      +   '</span>'
      + '</div>'
      + '<div class="notify-gk-explain">' + escapeHtml(explanation) + '</div>'
      + '</div>';
    return ''
      + sectionLabel('Channels')
      + sectionTile(channelsTable)
      + sectionLabel('Pipeline verdict')
      + sectionTile(gkBlock);
  }

  const STAGE_RENDERERS = {
    'init':           (b, t, r) => renderInit(b, t, r),
    'release':        (b, t) => renderRelease(b, t),
    'build':          (b, t) => renderBuild(b, t),
    'lint':           (b, t) => renderLint(b, t),
    'sast':           (b, t) => renderFindingsStage(b, 'static analysis', t),
    'scan':           (b, t) => renderScan(b, t),
    'test':           (b, t) => renderTest(b, t),
    'package':        (b, t) => renderPackage(b, t),
    'container-scan': (b, t) => renderFindingsStage(b, 'container vulns', t),
    'deploy':         (b)    => renderDeploy(b),
    'notify':         ()     => null
  };

  // Per-stage specific failure reason builders. Each function receives the
  // stage fragment object and returns a human-readable sentence, or null to
  // fall back to the generic "exited with code N" message.
  const STAGE_FAILURE_REASONS = {
    'init':    initFailureReason,
    'release': releaseFailureReason,
    'lint':    lintFailureReason,
    'deploy':  deployFailureReason
  };
  function failureBanner(s) {
    if (s.status !== 'failed') return '';
    const ec = (s.tech && s.tech.exit_code != null) ? s.tech.exit_code : (s.rc != null ? s.rc : '?');
    const job = (s.runner && s.runner.job_url) || '';
    const cta = job
      ? '<a class="cta" href="' + escapeHtml(job) + '" target="_blank" rel="noopener">View job logs &rarr;</a>'
      : '';
    const reasonFn = STAGE_FAILURE_REASONS[s.stage];
    const specific = reasonFn ? reasonFn(s) : null;
    const reasonHtml = specific
      ? '<span class="reason">' + escapeHtml(specific) + '</span>'
      : '<span class="reason">Stage exited with <span class="code">code ' + escapeHtml(String(ec)) + '</span>. Check the job logs for the root cause.</span>';
    return '<div class="failure-banner">'
      + '<span class="label">Failed</span>'
      + reasonHtml
      + cta
      + '</div>';
  }

  // Tile for a stage the planner marked skip (or the adapter never
  // executed). Renders the plan's reason instead of forwarding to a
  // per-stage renderer that would invent a zero-finding count from an
  // empty fragment (the issue plan.json was added to solve here).
  function renderSkippedTile(stageId, planEntry) {
    const reasonHtml = (() => {
      const txt = planReasonText(planEntry);
      if (txt) return '<span class="reason">' + escapeHtml(txt) + '</span>';
      return '<span class="reason">This stage was not executed for this run.</span>';
    })();
    return '<div class="skipped-banner">'
      + '<span class="label">Skipped</span>'
      + reasonHtml
      + '</div>';
  }

  // Tile for a stage the plan marked run but with no recorded fragment
  // yet -- typically the in-flight stage rendering the report (notify
  // aggregates its own pipeline, so its fragment lands after the HTML
  // is written). Better than guessing "skipped" from absence.
  function renderRunningTile() {
    return '<div class="skipped-banner">'
      + '<span class="label">Running</span>'
      + '<span class="reason">This stage was still in flight when the report was rendered.</span>'
      + '</div>';
  }

  function renderBusiness() {
    const list = $('business-list');
    list.innerHTML = '';
    // Build a canonical iteration order:
    //  - prefer plan.stages order (canonical execution flow),
    //  - else sort recorded stages by STAGE_ORDER rank.
    // For each id, prefer the recorded fragment; fall back to a
    // synthetic placeholder. Classification of a missing fragment is
    // driven by the plan's decision (skip vs run), not by guessing
    // from the empty fragment.
    const byId = (data.stages || []).reduce((acc, s) => {
      const id = s.stage || s.name || s.id;
      if (id) acc[id] = s;
      return acc;
    }, {});
    const orderedIds = planStages.length > 0
      ? planStages.map((p) => p.id)
      : (data.stages || []).map((s) => s.stage || s.name || s.id)
                            .sort((a,b) => stageRank(a) - stageRank(b));
    let any = false;
    orderedIds.forEach((sid) => {
      const planEntry = planById[sid] || null;
      const recorded = byId[sid] || null;
      const planSkipped = planEntry && planEntry.decision === 'skip';
      const techStatus = recorded && ((recorded.tech && recorded.tech.status) || recorded.status) || null;
      const isSkipped = techStatus === 'skipped' || planSkipped;
      const isRunningMissing = !recorded && planEntry && planEntry.decision === 'run';
      // notify is a meta-stage that consumes the aggregate. Its
      // per-stage payload lives at data.pipeline.notify (injected by
      // stages.notify), not at .stages[].business. Recognize it inside
      // the loop so we render exactly ONE notify tile -- the previous
      // trailing append was the source of the duplicate tile.
      const pipelineNotify = sid === 'notify' ? ((data.pipeline || {}).notify || null) : null;

      // Synthesize a fragment for missing entries so downstream code
      // can keep reading s.duration_ms / s.status uniformly.
      const s = recorded || { stage: sid, status: isSkipped ? 'skipped' : 'unknown', tech: { status: isSkipped ? 'skipped' : 'unknown' }, business: {} };
      const renderer = STAGE_RENDERERS[s.stage];
      const b = s.business || {};
      let inner = null;
      if (isSkipped) {
        // Skipped: render plan-driven reason instead of per-stage renderer.
        inner = renderSkippedTile(sid, planEntry);
      } else if (pipelineNotify) {
        // notify metadata available (channels, gatekeeper, ...).
        inner = renderNotifyPanel(pipelineNotify);
      } else if (isRunningMissing) {
        // In-flight, no fragment yet (typically notify rendering itself
        // before its metadata has been injected).
        inner = renderRunningTile();
      } else {
        if (renderer) inner = renderer(b, s.tech || {}, s.runner || {});
        if (inner == null && Object.keys(b).length === 0 && s.status !== 'failed') return;
        if (inner == null) inner = renderFlat(b);
      }
      any = true;
      const wrap = document.createElement('div');
      wrap.className = 'business-stage';
      const status = s.status || techStatus || 'unknown';
      const dur = s.duration_ms != null ? '<span class="duration-badge">' + fmtDuration(s.duration_ms) + '</span>' : '';
      const sectionDryRun = !!(s.tech && (s.tech.dry_run === true || s.tech.dry_run === 'true'));
      const dryChip = sectionDryRun
        ? ' <span class="stage-dry-run-chip" title="BRIK_DRY_RUN=true: destructive actions for this stage were skipped">dry-run</span>'
        : '';
      wrap.innerHTML = '<h3 class="' + status + '"><span class="stage-dot"></span><span class="stage-name">' + escapeHtml(sid) + '</span>' + dryChip + dur + '</h3>'
        + failureBanner(s)
        + inner;
      list.appendChild(wrap);

      // Mount the per-stage findings items panel if the renderer emitted a
      // placeholder. Scopes the search/filter UI to this stage's items.
      const placeholder = wrap.querySelector('.findings-items-panel');
      if (placeholder) {
        const items = ((b.findings || {}).items) || [];
        mountFindingsPanel(placeholder, items);
      }
    });
    // Notify is handled inside the canonical loop above (via
    // pipelineNotify branch). The legacy trailing append used to
    // duplicate the notify tile -- removed when plan-driven iteration
    // started covering notify natively.
    if (!any) {
      list.innerHTML = '<div class="findings-empty">No business payload reported.</div>';
    }
  }
  function renderFlat(b) {
    const lines = flattenBusiness(b);
    if (lines.length === 0) return '<div class="hint">No payload.</div>';
    return lines.map((l) => '<div class="kv-line"><span class="k">' + escapeHtml(l[0]) + '</span><span class="v">' + escapeHtml(String(l[1])) + '</span></div>').join('');
  }
  function flattenBusiness(b) {
    const out = [];
    const walk = (path, val) => {
      if (val === null || val === undefined) return;
      if (path[0] === 'findings') return;
      const t = typeof val;
      if (t === 'object' && !Array.isArray(val)) {
        for (const k of Object.keys(val)) walk(path.concat(k), val[k]);
      } else if (Array.isArray(val)) {
        if (val.every((x) => x == null || typeof x !== 'object')) {
          if (val.length > 0) out.push([path.join('.'), val.map((x) => x == null ? '' : x).join(', ')]);
        }
      } else if (t !== 'function') {
        out.push([path.join('.'), val]);
      }
    };
    walk([], b);
    out.sort((a, b) => a[0].localeCompare(b[0]));
    return out;
  }

  renderHero();
  renderTimeline();
  renderMeta();
  renderBusiness();

  // Delegated click handler for every copy-btn anywhere in the report.
  document.addEventListener('click', function (e) {
    const btn = e.target && e.target.closest ? e.target.closest('.copy-btn') : null;
    if (!btn) return;
    e.preventDefault();
    e.stopPropagation();
    const text = btn.dataset.copy;
    if (!text) return;
    const restoreTip = btn.dataset.tooltip || 'Copy';
    copyToClipboard(text).then(function () {
      btn.classList.add('copied');
      btn.dataset.tooltip = 'Copied!';
      setTimeout(function () {
        btn.classList.remove('copied');
        btn.dataset.tooltip = restoreTip;
      }, 1400);
    }).catch(function () {
      btn.dataset.tooltip = 'Copy failed';
      setTimeout(function () { btn.dataset.tooltip = restoreTip; }, 1400);
    });
  });
})();
