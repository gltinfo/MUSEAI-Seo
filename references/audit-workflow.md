# SEO audit workflow for Muse

This is the detailed checklist for the `seo-audit` skill. It tells Muse exactly how to run the upstream claude-seo deterministic scripts on the VPS. Read it before every audit.

## The VPS and the runtime

- VPS host is `$MUSE_SEO_VPS_USER@$MUSE_SEO_VPS_HOST` on port 22 (defaults: user `root`, host `15.204.157.16`). To run the skill against another VPS, set `MUSE_SEO_VPS_HOST` (and `MUSE_SEO_VPS_USER` if the login differs) before running; the wrapper script `scripts/muse-audit.sh` reads the same variables.
- The upstream repo is cloned at `/root/claude-seo` on the VPS.
- The working runtime is the installed skill at `/root/.claude/skills/seo/` with its isolated venv at `/root/.claude/skills/seo/.venv/` and Python 3.12.16.
- Claude Code 2.1.322 is at `/root/.local/bin/claude` on the VPS.
- Use the installed launcher at `/root/.claude/skills/seo/scripts/claude-seo`.
- Do not use the repo copy at `/root/claude-seo/scripts/claude-seo` for running scripts. Its doctor check reports not ready because it looks for a managed environment next to the repo. The installed launcher reports ready true and browser ready true.
- Never call the venv Python directly. Every script goes through the launcher.

## The exact SSH prefix

Every SSH call from Muse must start with this prefix. It clears the proxy variables so SSH connects directly, and it uses the Muse key.

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy ssh -i /home/hatch/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=15 -p 22 ${MUSE_SEO_VPS_USER:-root}@${MUSE_SEO_VPS_HOST:-15.204.157.16}
```

## The exact launcher call

On the VPS, export the Python interpreter first. The system Python is 3.10 and the launcher refuses it. Without this export every script fails with a Python version error.

```bash
export CLAUDE_SEO_PYTHON=/root/.local/bin/python3.12
/root/.claude/skills/seo/scripts/claude-seo run <script>.py --json <args>
```

A full one-shot example:

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy ssh -i /home/hatch/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=15 -p 22 ${MUSE_SEO_VPS_USER:-root}@${MUSE_SEO_VPS_HOST:-15.204.157.16} 'export CLAUDE_SEO_PYTHON=/root/.local/bin/python3.12; /root/.claude/skills/seo/scripts/claude-seo run page_checks.py --url https://wirelessmouse.net/ --json'
```

## Upstream runtime inventory — what a fresh VPS install must have

The Muse skill itself is only 4 files. The upstream runtime it calls is vendored in this repo under `muse-ai/` (a verbatim copy of claude-seo v2.6.2, MIT-licensed; the code inside still calls itself claude-seo, so install it to `/root/claude-seo` on the VPS). When moving to another VPS, copy that folder over and verify it against this inventory (counted 2026-11-19; file counts exclude `.git`). Paths below are relative to `muse-ai/`.

- Upstream repo: https://github.com/AgriciDaniel/claude-seo, v2.6.2.
- Total: 575 files, 13 MB on disk including `.git` (9.5 MB working tree).
- 29 skills in `skills/`: seo, seo-agentic, seo-audit, seo-backlinks, seo-bing, seo-cluster, seo-competitor-pages, seo-content, seo-content-brief, seo-dataforseo, seo-drift, seo-ecommerce, seo-flow, seo-geo, seo-google, seo-hreflang, seo-image-gen, seo-images, seo-local, seo-maps, seo-page, seo-plan, seo-posthog, seo-programmatic, seo-schema, seo-shopify, seo-sitemap, seo-sxo, seo-technical.
- 20 agents in `agents/` (one `.md` file each): seo-agentic, seo-backlinks, seo-cluster, seo-content, seo-dataforseo, seo-drift, seo-ecommerce, seo-flow, seo-geo, seo-google, seo-image-gen, seo-local, seo-maps, seo-performance, seo-posthog, seo-schema, seo-sitemap, seo-sxo, seo-technical, seo-visual.
- 67 Python scripts in `scripts/` — these are what the launcher runs (`page_checks.py`, `transport_check.py`, `sitemap_discovery.py`, `fetch_page.py`, `parse_html.py`, `content_quality.py`, `agentic_check.py`, `pagespeed_check.py`, and the rest).
- 11 extensions in `extensions/`: ahrefs, banana, bing-webmaster, dataforseo, firecrawl, matomo, posthog, profound, seranking, shopify, unlighthouse.
- 157 test files in `tests/` (`test_*.py`), about 1,928 test functions (counted with grep).

Fresh VPS install checklist:

1. Clone this repo to the new VPS and copy the vendored runtime into place: `git clone https://github.com/gltinfo/MUSEAI-Seo && cp -r MUSEAI-Seo/muse-ai /root/claude-seo` (the upstream GitHub repo https://github.com/AgriciDaniel/claude-seo is the fallback source).
2. Install the skill to `/root/.claude/skills/seo/` with Python 3.12 (`CLAUDE_SEO_PYTHON=/root/.local/bin/python3.12`). Do not run scripts from the repo copy at `/root/claude-seo/scripts/claude-seo`; only the installed launcher reports ready.
3. Verify the install with the launcher: `/root/.claude/skills/seo/scripts/claude-seo doctor --json` must report `ready` true, Python 3.12, `browser_ready` true.
4. Verify the inventory on the new VPS. If any count is short, the install is incomplete — do not audit until it matches:
   - `find /root/claude-seo -path '*/.git' -prune -o -type f -print | wc -l` → 575
   - `ls /root/claude-seo/skills | wc -l` → 29
   - `ls /root/claude-seo/agents | wc -l` → 20
   - `ls /root/claude-seo/scripts/*.py | wc -l` → 67
   - `ls /root/claude-seo/extensions | wc -l` → 11
   - `find /root/claude-seo/tests -name 'test_*.py' | wc -l` → 157
5. Add Muse's SSH key to the new VPS and set `MUSE_SEO_VPS_HOST` to the new IP (and `MUSE_SEO_VPS_USER` if the login differs). The skill reads both from the environment; the defaults still point at the old VPS.

## Step 0. Check runtime readiness

Run this before the audit and stop if it reports not ready.

```bash
/root/.claude/skills/seo/scripts/claude-seo doctor --json
```

A ready runtime reports `ready` true, `python_version` 3.12 and `browser_ready` true. If it reports not ready, tell the user and run setup only when the user asks to repair it.

## Step 1. The 47 page checks

Command:

```bash
/root/.claude/skills/seo/scripts/claude-seo run page_checks.py --url <url> --json
```

Output is always JSON with `facts`, `findings` and `not_checked`. Each finding has an id, a severity and evidence quoted from the page. The 47 checks are:

- Title: missing-title, title-too-long, title-too-short, title-not-reflected-in-content
- Meta description: missing-meta-description, meta-description-too-long, description-not-reflected-in-content, duplicate-meta-tags
- Headings: missing-h1, multiple-h1, heading-level-skip
- Canonical and robots: missing-canonical, canonical-points-elsewhere, noindex, noindex-header, nofollow, meta-refresh-redirect, hreflang-missing-self
- Document: missing-doctype, missing-charset, charset-mismatch, missing-lang, missing-viewport, uses-frames, deprecated-html-tags, placeholder-text
- Images: images-missing-alt, images-missing-dimensions, first-image-lazy-loaded
- Links: links-without-text, generic-anchor-text, links-to-http, mixed-content
- URL: url-too-long, url-has-parameters, url-uppercase, url-underscores, url-non-ascii, url-double-slash
- Size and structure: html-over-2mb, deep-dom, wide-dom-node, thin-content
- Social and structured data: missing-open-graph, missing-og-image, og-url-differs-from-canonical, invalid-jsonld

Severity rules in the script: noindex and noindex-header are Critical. Canonical pointing elsewhere is High. Multiple H1, heading skips, Open Graph gaps, doctype, deprecated tags, generic anchors, http links, long URLs, uppercase URLs, underscores, non-ASCII URLs, double slashes, deep DOM and wide DOM nodes are Low. The rest are review level. Treat multiple H1 as Low in the script output but confirm by hand whether the most prominent heading names the page.

## Step 2. Transport check

Command:

```bash
/root/.claude/skills/seo/scripts/claude-seo run transport_check.py --json <url>
```

It reads the TLS certificate, grades transport security and headers, and checks the http to https and www redirects. Look for TLS 1.0 or 1.1 still enabled, weak ciphers, a missing HSTS header, a certificate expiring within 30 days, and a redirect chain longer than one hop. A favicon that returns 302 instead of 200 is a small transport finding, not a page finding.

## Step 3. Sitemap discovery

Command:

```bash
/root/.claude/skills/seo/scripts/claude-seo run sitemap_discovery.py --json --expand <url>
```

It reads `robots.txt` Sitemap declarations and common sitemap paths, follows a sitemap index one level, and reports per-file statistics. Check that every child sitemap is under 50,000 URLs and under 50 MB, that lastmod dates are real and uniform, that there are no duplicates, no cross-host URLs and no non-canonical, noindexed or redirected URLs. Record the number of sitemap files and the URL count of each child file. The `--sample` flag keeps 20 sample URLs per file by default. Read the totals from `expanded.files` in the JSON output, where each file has `url_count` and the index file has `child_count`. On wirelessmouse.net this reports 17 expanded files and 2,635 URLs.

## Step 4. Fetch and parse the page

Commands:

```bash
/root/.claude/skills/seo/scripts/claude-seo run fetch_page.py --json --render never --output /tmp/muse-audit-<domain>/home.html <url>
/root/.claude/skills/seo/scripts/claude-seo run parse_html.py --json --url <url> /tmp/muse-audit-<domain>/home.html
```

`fetch_page.py` fetches through `url_safety.py`, which is the mandatory SSRF and DNS rebinding guard. Never fetch a user supplied URL with curl or a bare script. Use `--render always` instead of `--render never` only when the page loads its main content with JavaScript. `parse_html.py` returns the title, meta description, meta robots, canonical, heading outline, images with src, alt, size, loading and lazy method, internal and external links, and schema blocks. Add `--probe-images` to record the format actually served for each image instead of trusting the file extension.

## Step 5. Content quality

Command:

```bash
/root/.claude/skills/seo/scripts/claude-seo run content_quality.py --json /tmp/muse-audit-<domain>/home.html
```

It scores visible text against the Google Quality Rater Guidelines. It flags scaled content abuse, filler phrases and AI pattern markers. The default quality threshold is 60 and the script exits non-zero below it. Also run this on two or three guide pages, not only the homepage, when the site is a publisher. For uncited claims, run:

```bash
/root/.claude/skills/seo/scripts/claude-seo run content_verify.py --json <text-file>
```

For templated titles and descriptions across pages, collect title and description pairs and run:

```bash
/root/.claude/skills/seo/scripts/claude-seo run metadata_template.py --pairs-file <pairs.json> --json
```

## Step 6. Schema checks

Read the schema blocks from the `parse_html.py` output. Check that every JSON-LD block parses, that required properties are present, that dates and URLs are absolute, and that no placeholder text remains. Never recommend retired types. HowTo, SpecialAnnouncement, ClaimReview, VehicleListing, EstimatedSalary and LearningVideo are retired. FAQPage has had no rich result since 2026-05-07, so flag it as info only and do not recommend adding it. Use QAPage for genuine question and answer content. For author pages, draft a ProfilePage with `schema_generate.py`:

```bash
/root/.claude/skills/seo/scripts/claude-seo run schema_generate.py profile --help
```

For product pages, validate merchant listing fields with:

```bash
/root/.claude/skills/seo/scripts/claude-seo run schema_ecommerce_validate.py <schema.json>
```

## Step 7. Agent readiness and AI search

Command:

```bash
/root/.claude/skills/seo/scripts/claude-seo run agentic_check.py --json <url>
```

It checks server rendering, the robots.txt groups and Content-Signal values, llms.txt, Markdown delivery, ai-catalog.json, the well-known directory and WebMCP markup. Do not use `--ua-matrix` without the site owner's authorization, because it re-requests the page with AI agent user agents. Read `robots.txt` by hand as well and record which AI crawlers are disallowed, separating training crawlers from search and citation crawlers. GPTBot trains, OAI-SearchBot cites. ClaudeBot trains, Claude-SearchBot cites. Google-Extended trains, Googlebot cites. Applebot-Extended trains, Applebot cites. A site that blocks the citation crawlers while publishing an llms.txt file is contradicting itself, and that is a finding. Never claim that llms.txt improves Google Search ranking, because Google states that it ignores it.

## Step 8. Performance

Command, optional and best effort:

```bash
/root/.claude/skills/seo/scripts/claude-seo run pagespeed_check.py --json --psi-only <url>
```

It calls PageSpeed Insights v5 and combines the result with CrUX field data when a key is present. Without a Google API key it uses shared quota and can fail, so record the failure and move on. Verified on wirelessmouse.net on 2026-11-18: the keyless call failed with PSI rate limit exceeded and the JSON output carried that error for both mobile and desktop. Add a Google API key to get real PageSpeed data. For CrUX history alone, use `crux_history.py`. Judge LCP at 2.5 seconds or less, INP at 200 milliseconds or less and CLS at 0.1 or less, all at the 75th percentile.

## Step 9. Drift baseline and compare

Capture a baseline before fixes:

```bash
/root/.claude/skills/seo/scripts/claude-seo run drift_baseline.py --skip-cwv <url>
```

Compare after fixes:

```bash
/root/.claude/skills/seo/scripts/claude-seo run drift_compare.py --skip-cwv <url>
```

Show history with:

```bash
/root/.claude/skills/seo/scripts/claude-seo run drift_history.py <url>
```

The compare step applies 17 rules. Critical findings are schema removed, canonical changed or removed, noindex added, and H1 removed or changed. Baselines live in SQLite on the VPS, so run baseline and compare on the same VPS.

## Step 10. Backlinks, only when asked

Run the Common Crawl check first, because it needs no key:

```bash
/root/.claude/skills/seo/scripts/claude-seo run commoncrawl_graph.py --help
```

Then verify each claimed backlink actually links to the site:

```bash
/root/.claude/skills/seo/scripts/claude-seo run verify_backlinks.py --help
```

Moz and Bing need free signup credentials. DataForSEO needs a paid account. Check which credentials exist first:

```bash
/root/.claude/skills/seo/scripts/claude-seo run backlinks_auth.py --check
```

## Step 11. Google data, only with credentials

Check what is configured before promising any Google data:

```bash
/root/.claude/skills/seo/scripts/claude-seo run google_auth.py --check
```

Without credentials, say that PageSpeed field data, Search Console and GA4 are not available. Never invent traffic numbers.

## Failure handling

- A script that exits non-zero is a failed step. Save its stderr, name it in the report, and keep going with the other steps.
- A script that reports a missing runtime is a setup problem, not an audit finding. Tell the user and stop the audit.
- A URL that fails the safety check is refused for a reason. Report the refusal and do not work around it.
- A page that returns a redirect to the homepage for an unknown URL is a soft 404 finding. Record the start URL, the redirect target and the final status code.
