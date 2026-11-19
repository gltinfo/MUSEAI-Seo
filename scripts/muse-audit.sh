#!/usr/bin/env bash
# muse-audit.sh - Muse SEO audit wrapper for claude-seo on the VPS.
#
# Usage: muse-audit.sh <url>
#
# Read-only: it fetches pages and runs audit scripts, it never edits the site
# and it never submits anything. Each step saves its JSON output under
# /tmp/muse-audit-<domain>/ on this machine. A step that fails is recorded
# as FAIL and the wrapper keeps going with the next step.
#
# Upstream: claude-seo v2.6.2, installed on the VPS at
# /root/.claude/skills/seo/ with Python 3.12.16. The wrapper calls every
# script through the installed launcher, never through the venv Python.
#
# VPS host: set MUSE_SEO_VPS_HOST (and MUSE_SEO_VPS_USER) to run against
# another VPS. Defaults below keep the current VPS working as-is.
set -uo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "Usage: $0 <url>" >&2
  exit 2
fi

case "$URL" in
  http://*|https://*) ;;
  *)
    echo "ERROR: URL must start with http:// or https://" >&2
    exit 2
    ;;
esac

HOST="$(printf '%s' "$URL" | sed -e 's#^[a-z]*://##' -e 's#/.*$##' -e 's#:.*$##')"
case "$HOST" in
  localhost|127.*|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|169.254.*|*.local)
    echo "ERROR: refusing non-public host $HOST" >&2
    exit 2
    ;;
esac

DOMAIN="$HOST"
OUT="/tmp/muse-audit-$DOMAIN"
REMOTE_DIR="/tmp/muse-audit-$DOMAIN"
mkdir -p "$OUT"

VPS_HOST="${MUSE_SEO_VPS_HOST:-15.204.157.16}"
VPS_USER="${MUSE_SEO_VPS_USER:-root}"
SSH=(env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy ssh -i /home/hatch/.ssh/id_ed25519 -o UserKnownHostsFile=/home/hatch/.ssh/known_hosts -o BatchMode=yes -o ConnectTimeout=15 -p 22 "$VPS_USER@$VPS_HOST")
LAUNCHER='/root/.claude/skills/seo/scripts/claude-seo'

remote() {
  "${SSH[@]}" "export CLAUDE_SEO_PYTHON=/root/.local/bin/python3.12; $1"
}

run_step() {
  local name="$1"
  local cmd="$2"
  echo "--- $name ---"
  if remote "$cmd" > "$OUT/$name.json" 2> "$OUT/$name.err"; then
    echo "PASS" > "$OUT/$name.status"
    echo "PASS $name"
  else
    echo "FAIL" > "$OUT/$name.status"
    echo "FAIL $name, see $OUT/$name.err"
  fi
  return 0
}

echo "Auditing $URL"
echo "Outputs: $OUT"
remote "mkdir -p $REMOTE_DIR"

run_step doctor "$LAUNCHER doctor --json"
run_step page_checks "$LAUNCHER run page_checks.py --url $URL --json"
run_step transport_check "$LAUNCHER run transport_check.py --json $URL"
run_step sitemap_discovery "$LAUNCHER run sitemap_discovery.py --json --expand $URL"
run_step fetch_page "$LAUNCHER run fetch_page.py --json --render never --output $REMOTE_DIR/home.html $URL"
run_step parse_html "$LAUNCHER run parse_html.py --json --url $URL $REMOTE_DIR/home.html"
run_step parse_html_probe "$LAUNCHER run parse_html.py --json --probe-images --url $URL $REMOTE_DIR/home.html"
run_step content_quality "$LAUNCHER run content_quality.py --json $REMOTE_DIR/home.html"
run_step agentic_check "$LAUNCHER run agentic_check.py --json $URL"
run_step pagespeed_check "$LAUNCHER run pagespeed_check.py --json --psi-only $URL"

echo "--- summary ---"
if command -v python3 >/dev/null 2>&1; then
  OUT="$OUT" python3 - <<'PY'
import json
import os

out = os.environ["OUT"]

def load(name):
    path = os.path.join(out, name + ".json")
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return None

def first_text(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list) and value:
        first = value[0]
        return first if isinstance(first, str) else str(first)
    return ""

parsed = load("parse_html") or {}
checks = load("page_checks") or {}
sitemap = load("sitemap_discovery") or {}
transport = load("transport_check") or {}
quality = load("content_quality") or {}
agentic = load("agentic_check") or {}

title = parsed.get("title") or (checks.get("facts") or {}).get("title") or "unknown"
print("title: " + str(title))

headings = parsed.get("h1") or []
if isinstance(headings, str):
    headings = [headings]
print("h1 count: " + str(len(headings)))
for heading in headings:
    print("h1: " + str(heading)[:120])

findings = checks.get("findings") or []
counts = {}
for finding in findings:
    severity = finding.get("severity", "unknown")
    counts[severity] = counts.get(severity, 0) + 1
print("page_checks findings: " + str(len(findings)) + " " + str(counts))
for finding in findings:
    print("finding: " + str(finding.get("severity")) + " " + str(finding.get("id")))

sitemaps = (sitemap.get("expanded") or {}).get("files") or []
total_urls = 0
for entry in sitemaps:
    if isinstance(entry, dict):
        value = entry.get("url_count")
        if isinstance(value, int):
            total_urls += value
print("sitemap files: " + str(len(sitemaps)) + " total urls counted: " + str(total_urls))
for entry in sitemaps:
    if isinstance(entry, dict) and entry.get("kind") == "sitemapindex":
        print("sitemap index children: " + str(entry.get("child_count")))

tls = (transport.get("tls") or {})
print("transport: protocol " + str(tls.get("protocol")) + " cert expires in " + str(tls.get("days_until_expiry")) + " days")
print("transport findings: " + str((transport.get("summary") or {}).get("total", "see transport_check.json")))
print("content quality: " + str(quality.get("overall_quality") or quality.get("score") or "see content_quality.json"))
agentic_checks = agentic.get("checks") or []
agentic_counts = {}
for check in agentic_checks:
    status = check.get("status", "unknown")
    agentic_counts[status] = agentic_counts.get(status, 0) + 1
print("agentic checks: " + str(len(agentic_checks)) + " " + str(agentic_counts))

pagespeed = load("pagespeed_check") or {}
psi_error = (pagespeed.get("error") or "")
if psi_error:
    print("pagespeed: failed, " + str(psi_error)[:200])

for name in ("doctor", "page_checks", "transport_check", "sitemap_discovery",
             "fetch_page", "parse_html", "parse_html_probe", "content_quality",
             "agentic_check", "pagespeed_check"):
    status_path = os.path.join(out, name + ".status")
    try:
        with open(status_path, encoding="utf-8") as handle:
            status = handle.read().strip()
    except Exception:
        status = "not run"
    print("step " + name + ": " + status)
PY
else
  echo "python3 not found, skipping summary"
  ls -la "$OUT"
fi

echo "Done. Outputs in $OUT"
