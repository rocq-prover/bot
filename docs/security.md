# Security Reference — Rocq Bot (`coqbot` / `rocqbot`)

Single source of truth for the security posture of this repository: threat model,
vulnerability findings, architecture, control objectives, remediation plan, and disclosure policy.

> [!IMPORTANT]
> **Audit basis**: This document reflects the **verified state of the current source tree** as reviewed. Claims are supported by cited source evidence. Aspirational controls that are not yet implemented are not presented as implemented.

| Field | Value |
|-------|-------|
| Scope | `src/`, `bot-components/`, shell scripts, deployment manifests, GitHub Actions workflows |
| Method | Manual source-code review of the full tree; local reproduction of injection mechanics in `/bin/sh` |
| Audit date | 2026-09-04 |
| Last updated | 2026-09-04 |
| Public entry point | `SECURITY.md` at the repository root links here |

---

## How to read this document

1. Every finding cites `file:line` and quotes the deciding expression.
2. Finding identifiers (CRITICAL-1, HIGH-1, MEDIUM-1, …) are stable labels for cross-reference and remediation tracking.
3. Colored badges mark severity and attacker position. See the [Severity color key](#severity-color-key) below.
4. "Reachable by" names the weakest attacker position (P1 to P6) that suffices.
5. Status labels: `CONFIRMED`, `LIKELY`, `POTENTIAL`, `NOT_REPRODUCED`, `FIXED-VERIFIED`, `FIXED-UNVERIFIED`, `FALSE-POSITIVE`, `UNKNOWN`.

### Severity color key

| Marker | Severity | Meaning |
|--------|----------|---------|
| ![Critical](https://img.shields.io/badge/Critical-c0392b) | Critical | Unauthenticated RCE or abuse of privileged credentials on an attacker-chosen target |
| ![High](https://img.shields.io/badge/High-e67e22) | High | Privileged effect with one precondition |
| ![Medium](https://img.shields.io/badge/Medium-f39c12) | Medium | Bounded effect: needs an account/config, or cost/integrity/leak impact |
| ![Low](https://img.shields.io/badge/Low-3498db) | Low | Hardening gap or latent defect with no currently reachable exploit path |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | Info | Operational or hygiene observation, not a vulnerability |
| ![Accepted](https://img.shields.io/badge/Accepted-27ae60) | Accepted | Documented design risk; residual control is intentional |

---

## 1. Executive Summary

The bot is an internet-facing HTTP server that holds a GitHub App RSA private key, a GitHub Personal Access Token, and GitLab API tokens. Three of its seven routes accept requests with no authentication at all, and two more fail open when their authentication header is absent.

The single most severe issue is **remote command execution on the bot host**, reachable by any internet client with one unauthenticated HTTP POST, via an unbalanced shell quote in `src/ci/minimization.ml:1394`. This is reproduced with evidence in [CRITICAL-2](#critical-2).

| Severity | Count | Identifiers |
|----------|------:|-------------|
| ![Critical](https://img.shields.io/badge/Critical-c0392b) Critical | 4 | CRITICAL-1, CRITICAL-2, CRITICAL-3, CRITICAL-4 |
| ![High](https://img.shields.io/badge/High-e67e22) High | 6 | HIGH-1 through HIGH-6 |
| ![Medium](https://img.shields.io/badge/Medium-f39c12) Medium | 10 | MEDIUM-1, MEDIUM-3 through MEDIUM-11 |
| ![Low](https://img.shields.io/badge/Low-3498db) Low | 9 | LOW-1 through LOW-9 |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) Info | 8 | INFO-1 through INFO-8 |
| ![Accepted](https://img.shields.io/badge/Accepted-27ae60) Accepted | 3 | ACCEPTED-1, ACCEPTED-2, ACCEPTED-3 |

Three controls are correctly implemented and must not be regressed: constant-time secret comparison via `Eqaf.equal`, the fail-closed rejection of unsigned check-run re-requests, and the fail-closed behaviour of `get_team_membership` on error.

---

## 2. Security Verdict

> **NOT SAFE FOR PRODUCTION** (Gate 0 — Unsafe)

Four independently exploitable Critical conditions exist:

- **CRITICAL-1**: Unauthenticated command-and-control via minimizer callbacks
- **CRITICAL-2**: Remote code execution on the bot host via shell injection
- **CRITICAL-3**: Unauthenticated attacker-controlled Docker image in a trusted workflow
- **CRITICAL-4**: GitHub webhooks without `installation.id` bypass all signature verification

None of these require any GitHub or GitLab account. An anonymous internet client can trigger all four.

---

## 3. Architecture

### System Classification

The bot is a **Privileged Event-Driven DevOps Automation** service. Compromise of the bot is equivalent to compromise of every GitHub organization and GitLab project where it is installed.

### Privileged Capabilities

| Capability | Credential | Scope |
|------------|------------|-------|
| Mint GitHub installation tokens | App RSA private key | Every installed org |
| Push/delete branches in `rocq-community/run-coq-bug-minimizer` | GitHub PAT | That repository |
| Force-push to GitLab mirrors | GitLab tokens (per instance) | All mirrored repos |
| Create/update/delete GitHub Checks and comments | Installation tokens | Per-org |
| Retry GitLab jobs and pipelines | GitLab tokens | All visible projects |
| Execute shell commands on the bot host | Process privileges | Bot host filesystem |
| Trigger GitHub Actions workflows | PAT push to trusted repo | `rocq-community/*` |

---

## 4. Source File Index by Security Category

This section maps every security-relevant source file to its category. Use this as the primary navigation aid when reviewing or remediating a specific security area.

### 4.1 HTTP Server and Request Routing

| File | Role | Key Security Properties |
|------|------|------------------------|
| `src/bot.ml` | Main entry point, HTTP server, path dispatch | Body buffering before auth (MEDIUM-7), no method enforcement (INFO-6) |

### 4.2 Webhook Authentication

| File | Role | Key Security Properties |
|------|------|------------------------|
| `bot-components/github/GitHub_subscriptions.ml` | GitHub webhook parser and HMAC verifier | CRITICAL-4 (auth bypass), LOW-1 (SHA-1 only) |
| `bot-components/gitlab/GitLab_subscriptions.ml` | GitLab webhook parser and token verifier | HIGH-1 (missing token accepted) |
| `src/webhooks/github.ml` | GitHub event dispatcher | MEDIUM-1 (no authorization on minimize) |
| `src/webhooks/gitlab.ml` | GitLab event dispatcher | HIGH-1 consumer (`signed` flag ignored) |
| `src/webhooks/minimizer.ml` | Minimizer callback dispatcher | CRITICAL-1, CRITICAL-3 (no auth) |
| `src/webhooks/scheduled.ml` | Stale-PR scheduler handler | LOW-2 (non-constant-time comparison) |

### 4.3 Authorization

| File | Role | Key Security Properties |
|------|------|------------------------|
| `src/webhooks/github.ml` | Comment-command authorization | MEDIUM-1 (minimize has no team check) |
| `src/actions/pr_sync.ml` | PR sync and CI gate | MEDIUM-9 (author vs. pusher identity mismatch) |
| `src/utils/bench.ml` | Bench authorization | LOW-9 (auth after API work) |
| `bot-components/github/GitHub_automation.ml` | Merge authorization | Contains correct team-membership gate |

### 4.4 Identity and Resource Binding

| File | Role | Key Security Properties |
|------|------|------------------------|
| `bot-components/github/GitHub_installations.ml` | Installation ID → token mapping | MEDIUM-11 (unauthenticated minting), confused deputy via caller-supplied owner |
| `bot-components/github/GitHub_GitLab_sync.ml` | GitHub↔GitLab repository mapping | HIGH-2 (unmapped path fallback), MEDIUM-6 (coqbot.toml retargeting) |
| `src/config/repo_config.ml` | Repository configuration | Controls CI dispatch; repository-controlled data |

### 4.5 Command Execution (P0 Priority)

| File | Role | Key Security Properties |
|------|------|------------------------|
| `bot-components/utils/Git_utils.ml` | Shell subprocess wrapper (`execute_cmd` via `Lwt_process.shell`) | HIGH-4 (credential in log/URL), HIGH-5 (`repo_url` unquoted), HIGH-6 (SHA unquoted) |
| `src/ci/minimization.ml` | CI minimization orchestration | CRITICAL-2 (RCE via unbalanced quote at line 1394) |
| `src/utils/coq.ml` | Coq bug minimizer subprocess | Uses `Filename.quote_command` (correct); PAT in argv (HIGH-4) |
| `coq_bug_minimizer.sh` | Bash: push minimizer branch | PAT in push URL argv (HIGH-4) |
| `run_ci_minimization.sh` | Bash: CI minimization branch | PAT in push URL argv (HIGH-4); attacker-controlled `docker_image` in `sed` (CRITICAL-3) |
| `make_ancestor.sh` | Bash: git merge ancestor | PR title and number in git commit message args (quoted, assessed safe) |

### 4.6 Git and Repository Security

| File | Role | Key Security Properties |
|------|------|------------------------|
| `bot-components/utils/Git_utils.ml` | `git_fetch`, `git_push`, `git_test_modified`, `git_make_ancestor` | HIGH-5 (`repo_url` unquoted), HIGH-6 (SHA unquoted) |
| `bot-components/github/GitHub_GitLab_sync.ml` | Mirror action (fetch from GitHub, push to GitLab) | HIGH-5 via unquoted repo URL |
| `src/actions/pr_sync.ml` | PR update: fetch, merge, push to GitLab | HIGH-5 call sites |
| `bot-components/github/GitHub_automation.ml` | PR close: delete remote GitLab branch | Call site for `git_delete` |

### 4.7 Credential Storage and Loading

| File | Role | Key Security Properties |
|------|------|------------------------|
| `src/config/config.ml` | Credential loading from TOML/env | HIGH-3 (secret defaults), credential loading patterns |
| `bot-components/core/Bot_info.ml` | Bot credential struct | PAT accessor used throughout |
| `bot-components/github/GitHub_app.ml` | JWT generation, installation token minting | LOW-5 (no clock-skew margin) |
| `bot-components/github/GitHub_installations.ml` | Installation token cache (40 min TTL) | INFO-3 (in-process cache) |
| `.bot-env` | Local dev credentials (never committed) | INFO-5 (live credentials on disk) |

### 4.8 HTTP Client and SSRF

| File | Role | Key Security Properties |
|------|------|------------------------|
| `bot-components/utils/HTTP_utils.ml` | HTTP client, redirect follower, artifact downloader | MEDIUM-4 (no SSRF allowlist, unlimited redirects) |
| `src/ci/minimization.ml` | Calls `download_to` with caller-supplied URL | MEDIUM-4 source |

### 4.9 API Clients and Serialization

| File | Role | Key Security Properties |
|------|------|------------------------|
| `bot-components/github/GitHub_mutations.ml` | GitHub REST/GraphQL mutations | MEDIUM-10 (JSON by concatenation, commit ref in path) |
| `bot-components/github/GitHub_queries.ml` | GitHub GraphQL queries | Team membership queries used for authorization |
| `bot-components/gitlab/GitLab_mutations.ml` | GitLab REST mutations (retry, play) | LOW-6 (JSON by concatenation), MEDIUM-3 (`url_part` in path) |
| `bot-components/gitlab/GitLab_queries.ml` | GitLab REST queries (build trace) | LOW-7 (status code ignored) |

### 4.10 CI/CD Logic

| File | Role | Key Security Properties |
|------|------|------------------------|
| `src/ci/job_status.ml` | GitLab job → GitHub Check translation | LOW-4 (trace published to GitHub) |
| `src/ci/minimization.ml` | CI minimization orchestration | CRITICAL-1, CRITICAL-2, CRITICAL-3, MEDIUM-4 |
| `src/ci/documentation.ml` | Documentation artifact status | Calls `send_status_check`; currently safe via allowlist |
| `bot-components/ci/pipeline.ml` | Pipeline event → Check summary | MEDIUM-5 (pipeline variables published) |
| `src/actions/pr_sync.ml` | PR update flow | MEDIUM-9 |

### 4.11 Supply Chain

| File | Role | Key Security Properties |
|------|------|------------------------|
| `Dockerfile` | Development Docker image | Inherits from untagged `coqbot` image (mutable) |
| `release.Dockerfile` | Production Docker image | Pinned to `alpine:3.20` (tag, not digest) |
| `.github/workflows/ci.yml` | CI workflow | Uses action tags, not digest pins |
| `.github/workflows/deploy_heroku.yml` | Heroku deploy workflow | Third-party `akhileshns/heroku-deploy@v3.13.15` (mutable tag) |
| `.github/workflows/publish_docker.yml` | Docker publish workflow | `actions/checkout@v2` (old version), mutable tags |
| `coq-bot.opam` | OCaml dependencies | Version ranges, not pinned to digests |

### 4.12 Tests

| File | Role | Key Security Properties |
|------|------|------------------------|
| `tests/test_webhook.ml` | Webhook parsing tests | **Contains incorrect assertion about CRITICAL-4** (must be updated) |
| `tests/test_pat_usage.ml` | PAT dependency tests | Tests PAT requirement for minimizer; does not test injection |
| `tests/test_git_utils.ml` | Git URL parser tests | No injection tests |
| `tests/test_minimize_parser.ml` | Minimize parser tests | Parses bot command syntax |
| `tests/test_string_utils.ml` | String utility tests | No security-specific coverage |

---

## 5. System Context Diagram

```mermaid
flowchart LR
  subgraph External["External Actors (UNTRUSTED)"]
    NET["Internet client\nany anonymous actor"]
    GH["GitHub App\nwebhooks"]
    GL["GitLab\nwebhooks"]
    ACT["run-coq-bug-minimizer\nGitHub Actions"]
    CRON["Scheduler"]
  end

  subgraph Bot["bot.exe — single Cohttp server, single Lwt event loop"]
    ROUTER["src/bot.ml\npath dispatch only"]
    WGH["src/webhooks/github.ml\nHMAC-SHA1 (conditional)"]
    WGL["src/webhooks/gitlab.ml\nToken (optional — HIGH-1)"]
    WMIN["src/webhooks/minimizer.ml\nNO AUTHENTICATION"]
    WSCH["src/webhooks/scheduled.ml\nbody secret"]
    SHELL["Git_utils.execute_cmd\nLwt_process.shell = /bin/sh -c\nShell injection sink"]
  end

  subgraph Creds["Credentials held in process"]
    KEY["GitHub App RSA key"]
    PAT["GitHub PAT"]
    GLT["GitLab tokens (per instance)"]
    TOKC["Installation token cache\n40 min TTL"]
  end

  subgraph Targets["Privileged targets"]
    GHAPI["GitHub REST + GraphQL"]
    GLAPI["GitLab REST + GraphQL"]
    GLREPO["GitLab mirrors\nforce push"]
    MINREPO["rocq-community/\nrun-coq-bug-minimizer"]
  end

  NET --> ROUTER
  GH --> ROUTER
  GL --> ROUTER
  ACT --> ROUTER
  CRON --> ROUTER

  ROUTER --> WGH
  ROUTER --> WGL
  ROUTER --> WMIN
  ROUTER --> WSCH

  WGH --> SHELL
  WGL --> GHAPI
  WMIN --> SHELL
  WSCH --> GHAPI

  KEY --> TOKC
  TOKC --> GHAPI
  PAT --> MINREPO
  GLT --> GLAPI
  GLT --> GLREPO
  SHELL --> GLREPO
  SHELL --> MINREPO
```

---

## 6. Assets

| Asset | Where it lives | Blast radius if abused |
|-------|----------------|------------------------|
| GitHub App RSA private key | `Config.github_private_key` from `GITHUB_PRIVATE_KEY`; used by `GitHub_app.make_jwt` | Mints installation tokens for every org where the App is installed |
| GitHub Personal Access Token | `Bot_info.github_pat`, from `github.api_token` or `GITHUB_ACCESS_TOKEN` | Push and delete branches in `rocq-community/run-coq-bug-minimizer` as the `coqbot` user |
| GitLab tokens, one per instance | `Bot_info.gitlab_instances` hashtable | Force-push to GitLab mirrors, retry and play CI jobs, read job traces |
| GitHub webhook secret | `Config.github_webhook_secret` | Forge signed GitHub App webhooks |
| GitLab webhook secret | `Config.gitlab_webhook_secret`; defaults to the GitHub secret when unset (`src/config/config.ml:74`) | Forge GitLab Job and Pipeline events |
| Daily-schedule secret | `Config.daily_schedule_secret`; same default (`src/config/config.ml:83`) | Drive `/check-stale-pr`: comment on, label, and close pull requests |
| Installation token cache | `GitHub_installations.installation_tokens` | Org-level GitHub write tokens, valid up to 40 minutes; survives in process memory |

---

## 7. HTTP surface and current authentication state

| Route | Legacy aliases | Authentication as implemented | Fails open? |
|-------|----------------|-------------------------------|:-----------:|
| `/github` | `/push`, `/pull_request` | HMAC-SHA1 over `X-Hub-Signature`, but only when `installation.id` parses as an integer | Yes |
| `/gitlab` | `/job`, `/pipeline` | `X-Gitlab-Token` compared with `Eqaf.equal`, but only when the header is present | Yes |
| `/coq-bug-minimizer` | -- | None | n/a |
| `/ci-minimization` | -- | None | n/a |
| `/resume-ci-minimization` | -- | None | n/a |
| `/check-stale-pr` | -- | Secret embedded in the request body, compared with `String.equal` | No |

```mermaid
flowchart TD
  REQ["POST body"] --> P{"path"}

  P --> |"/github /push /pull_request"| GHJ{"installation.id\nparses as int?"}
  GHJ --> |"yes"| SIG{"X-Hub-Signature\npresent and valid?"}
  SIG --> |"yes"| OKS["ACCEPT signed"]
  SIG --> |"no"| REJ["REJECT 401"]
  GHJ --> |"no -- exception swallowed"| OPEN1["ACCEPT UNSIGNED\nCRITICAL-4"]

  P --> |"/gitlab /job /pipeline"| GLH{"X-Gitlab-Token\nheader present?"}
  GLH --> |"yes"| GLC{"matches secret?"}
  GLC --> |"yes"| OKG["ACCEPT signed=true"]
  GLC --> |"no"| REJ
  GLH --> |"no"| OPEN2["ACCEPT signed=false\nhandlers never read the flag\nHIGH-1"]

  P --> |"minimizer routes"| OPEN3["ACCEPT unconditionally\nCRITICAL-1 CRITICAL-3"]

  P --> |"/check-stale-pr"| SEC{"body secret ==\nschedule secret?"}
  SEC --> |"yes"| OKC["ACCEPT"]
  SEC --> |"no"| REJ

  classDef start fill:#eceff1,stroke:#546e7a,color:#263238
  classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20
  classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
  classDef wiring fill:#b2dfdb,stroke:#00796b,color:#004d40
  classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037

  class REQ start
  class P,GHJ,SIG,GLH,GLC,SEC question
  class OKS,OKG,OKC,REJ domain
  class OPEN1,OPEN3 transport
  class OPEN2 wiring
```

---

## 8. Attacker positions

| | ID | Position | Capability without any privilege |
|---|----|----------|----------------------------------|
| ![P1](https://img.shields.io/badge/P1-8e44ad) | P1 | Internet client | POST arbitrary bodies to any route |
| ![P2](https://img.shields.io/badge/P2-8e44ad) | P2 | GitHub commenter | Comment on a pull request or issue in an installed repository, producing a legitimately signed event |
| ![P3](https://img.shields.io/badge/P3-8e44ad) | P3 | Pull request author | Supply branch content that the bot merges and mirrors to GitLab |
| ![P4](https://img.shields.io/badge/P4-8e44ad) | P4 | GitLab project maintainer | Read the shared GitLab webhook secret from their own project settings |
| ![P5](https://img.shields.io/badge/P5-8e44ad) | P5 | Log or process reader | Read dyno stdout, a log aggregator, or `ps` output on the bot host |
| ![P6](https://img.shields.io/badge/P6-8e44ad) | P6 | Holder of one leaked secret | Forge events on every channel that shares that secret value |

---

## 9. Findings index

| ID | Title | Sev | Status | CWE | Category | Reachable by | Primary location |
|----|-------|-----|--------|-----|----------|--------------|-----------------|
| CRITICAL-1 | Minimizer callbacks have no authentication | ![Critical](https://img.shields.io/badge/Critical-c0392b) | `CONFIRMED` | CWE-306 | Authentication, Confused deputy | P1 | `src/bot.ml:60`, `src/ci/minimization.ml:1376` |
| CRITICAL-2 | Shell command injection in the branch-delete command | ![Critical](https://img.shields.io/badge/Critical-c0392b) | `CONFIRMED` | CWE-78 | Injection | P1 | `src/ci/minimization.ml:1394` |
| CRITICAL-3 | Unauthenticated resume writes an attacker-chosen workflow image | ![Critical](https://img.shields.io/badge/Critical-c0392b) | `CONFIRMED` | CWE-306 | Authentication, Supply chain | P1 | `src/ci/minimization.ml:1409`, `run_ci_minimization.sh:55` |
| CRITICAL-4 | GitHub webhooks without `installation.id` skip signature verification | ![Critical](https://img.shields.io/badge/Critical-c0392b) | `CONFIRMED` | CWE-347 | Authentication | P1 | `bot-components/github/GitHub_subscriptions.ml:249-263` |
| HIGH-1 | GitLab webhooks without a token are processed as valid | ![High](https://img.shields.io/badge/High-e67e22) | `CONFIRMED` | CWE-306 | Authentication | P1 | `bot-components/gitlab/GitLab_subscriptions.ml:114-119` |
| HIGH-2 | Unmapped GitLab path is used directly as a GitHub `owner/repo` | ![High](https://img.shields.io/badge/High-e67e22) | `CONFIRMED` | CWE-20 | Input validation, Confused deputy | P1 with HIGH-1 | `bot-components/github/GitHub_GitLab_sync.ml:49-56` |
| HIGH-3 | GitLab and schedule secrets default to the GitHub webhook secret | ![High](https://img.shields.io/badge/High-e67e22) | `CONFIRMED` | CWE-1188 | Secret management | P6 | `src/config/config.ml:70-86` |
| HIGH-4 | Tokens printed in command logs, git URLs, and process argv | ![High](https://img.shields.io/badge/High-e67e22) | `CONFIRMED` | CWE-532 | Credential exposure | P5 | `bot-components/utils/Git_utils.ml:20` |
| HIGH-5 | `git_fetch` and `git_push` interpolate remote URLs into a shell unquoted | ![High](https://img.shields.io/badge/High-e67e22) | `CONFIRMED` | CWE-78 | Injection | P1 with CRITICAL-4; P2 with MEDIUM-6 | `bot-components/utils/Git_utils.ml:44,50` |
| HIGH-6 | `git_test_modified` interpolates commit SHAs into a shell unquoted | ![High](https://img.shields.io/badge/High-e67e22) | `CONFIRMED` | CWE-78 | Injection | P1 with CRITICAL-4 | `bot-components/utils/Git_utils.ml:80` |
| MEDIUM-1 | Minimize, CI-minimize, and resume commands have no authorization check | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-862 | Authorization | P2 | `src/webhooks/github.ml:77,98,111` |
| MEDIUM-2 | *(Reserved / Retired label)* | -- | -- | -- | -- | -- | -- |
| MEDIUM-3 | Check re-run trusts `external_id` and retries GitLab as the bot | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-20 | Input validation | P2 with a signed event | `bot-components/utils/Minimize_parser.ml:179-190`, `bot-components/gitlab/GitLab_mutations.ml:7` |
| MEDIUM-4 | Caller-supplied URLs are fetched with no allowlist | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-918 | SSRF | P1, P2 | `src/ci/minimization.ml:256` |
| MEDIUM-5 | GitLab pipeline variables are copied into public GitHub Checks | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-200 | Information leak | P1 with HIGH-1 | `bot-components/ci/pipeline.ml:10-14` |
| MEDIUM-6 | Default-branch `coqbot.toml` retargets where the GitLab token pushes | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-20 | Input validation | P2 as a repo admin | `bot-components/github/GitHub_GitLab_sync.ml:91-134` |
| MEDIUM-7 | No body-size limit, no replay store, quadratic regexes | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-400 | Availability | P1 | `src/bot.ml:46` |
| MEDIUM-8 | One GitLab webhook secret shared by all mapped projects | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-1188 | Secret management | P4 | `src/bot.ml:12-13` |
| MEDIUM-9 | CI configuration gate checks the PR author, not the pusher | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-863 | Authorization | P2 | `src/actions/pr_sync.ml:55-58` |
| MEDIUM-10 | Commit status body built by string concatenation; commit ref unvalidated in the URL path | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-116 | Injection, Input validation | P1 with HIGH-1 | `bot-components/github/GitHub_mutations.ml:272,278` |
| MEDIUM-11 | Unauthenticated routes drive installation-token minting | ![Medium](https://img.shields.io/badge/Medium-f39c12) | `CONFIRMED` | CWE-770 | Availability | P1 | `bot-components/github/GitHub_installations.ml:52-79` |
| LOW-1 | HMAC uses the SHA-1 header only | ![Low](https://img.shields.io/badge/Low-3498db) | `CONFIRMED` | CWE-328 | Cryptography | P1 | `bot-components/github/GitHub_subscriptions.ml:253-258` |
| LOW-2 | Stale-PR secret comparison is not constant-time | ![Low](https://img.shields.io/badge/Low-3498db) | `CONFIRMED` | CWE-208 | Cryptography | P6 | `src/webhooks/scheduled.ml:13` |
| LOW-3 | GraphQL node IDs are unvalidated opaque strings | ![Low](https://img.shields.io/badge/Low-3498db) | `CONFIRMED` | CWE-20 | Input validation | P1 with CRITICAL-1 | `bot-components/github/GitHub_ID.ml` |
| LOW-4 | Token-backed job traces are published to GitHub | ![Low](https://img.shields.io/badge/Low-3498db) | `CONFIRMED` | CWE-200 | Information leak | P1 with HIGH-1 | `src/ci/job_status.ml:78-115` |
| LOW-5 | JWT `iat` has no clock-skew margin | ![Low](https://img.shields.io/badge/Low-3498db) | `CONFIRMED` | CWE-703 | Availability | n/a | `bot-components/github/GitHub_app.ml:23-27` |
| LOW-6 | `play_job` builds its JSON body by string concatenation | ![Low](https://img.shields.io/badge/Low-3498db) | `POTENTIAL` | CWE-116 | Injection, latent | none today | `bot-components/gitlab/GitLab_mutations.ml:45` |
| LOW-7 | `get_build_trace` ignores the HTTP status code | ![Low](https://img.shields.io/badge/Low-3498db) | `CONFIRMED` | CWE-754 | Information leak | P1 with HIGH-1 | `bot-components/gitlab/GitLab_queries.ml:22-24` |
| LOW-8 | Attacker input raises uncaught exceptions in the request path | ![Low](https://img.shields.io/badge/Low-3498db) | `CONFIRMED` | CWE-248 | Availability | P1 with HIGH-1 | `bot-components/github/GitHub_GitLab_sync.ml:58-63` |
| LOW-9 | Bench authorization is decided after the API work it guards | ![Low](https://img.shields.io/badge/Low-3498db) | `CONFIRMED` | CWE-696 | Authorization ordering | P2 | `src/utils/bench.ml:245-301` |
| INFO-1 | Exception hook prints raw exception text | ![Info](https://img.shields.io/badge/Info-7f8c8d) | `CONFIRMED` | -- | Logging | -- | `src/bot.ml:73-78` |
| INFO-2 | TLS and platform IAM are outside this codebase | ![Info](https://img.shields.io/badge/Info-7f8c8d) | `CONFIRMED` | -- | Deployment | -- | `src/bot.ml:70` |
| INFO-3 | Installation tokens live in an in-process hashtable | ![Info](https://img.shields.io/badge/Info-7f8c8d) | `CONFIRMED` | -- | Key management | -- | `bot-components/github/GitHub_installations.ml:8-9` |
| INFO-4 | No secret-rotation runbook | ![Info](https://img.shields.io/badge/Info-7f8c8d) | `CONFIRMED` | -- | Process | -- | -- |
| INFO-5 | Live credentials present in `.bot-env` on disk | ![Info](https://img.shields.io/badge/Info-7f8c8d) | `CONFIRMED` | -- | Secret hygiene | -- | `.bot-env` |
| INFO-6 | No HTTP method enforcement on any route | ![Info](https://img.shields.io/badge/Info-7f8c8d) | `CONFIRMED` | -- | Hardening | -- | `src/bot.ml:39-67` |
| INFO-7 | GitHub App private key PEM in the workspace is world-readable | ![Info](https://img.shields.io/badge/Info-7f8c8d) | `CONFIRMED` | -- | Secret hygiene | -- | `app-bot-demo.2025-10-31.private-key.pem` |
| INFO-8 | No CORS restrictions or origin validation | ![Info](https://img.shields.io/badge/Info-7f8c8d) | `CONFIRMED` | -- | Hardening | -- | `src/bot.ml:39-67` |

---

## 10. Attack chains

The critical findings are not independent. CRITICAL-4 and HIGH-1 are the sources that make several injection sinks attacker-reachable.

```mermaid
flowchart LR
  C1["CRITICAL-1<br/>no auth on<br/>minimizer routes"] --> C2["CRITICAL-2<br/>shell injection<br/>-> RCE on host"]
  C1 --> IMP["Post comments as<br/>the GitHub App on<br/>any thread"]
  C1 --> DEL["PAT branch delete<br/>on any repo"]
  C1 --> M4["MEDIUM-4<br/>SSRF"]
  C3["CRITICAL-3<br/>no auth on<br/>resume route"] --> WF["Attacker image in a<br/>trusted Actions workflow"]

  C4["CRITICAL-4<br/>unsigned GitHub<br/>webhooks accepted"] --> H5["HIGH-5<br/>unquoted remote URL<br/>-> RCE on host"]
  C4 --> H6["HIGH-6<br/>unquoted commit SHA<br/>-> RCE on host"]
  C4 --> MIR["Force-push to<br/>GitLab mirrors"]

  H1["HIGH-1<br/>tokenless GitLab<br/>webhooks accepted"] --> H2["HIGH-2<br/>arbitrary repo<br/>as target"]
  H1 --> M5["MEDIUM-5<br/>content injected into<br/>public Checks"]
  H1 --> M10["MEDIUM-10<br/>status API body and<br/>path injection"]
  H1 --> L4["LOW-4 / LOW-7<br/>trace and error bodies<br/>published"]
  H2 --> FAKE["Fake CI verdicts on<br/>rocq-prover/rocq"]

  M6["MEDIUM-6<br/>coqbot.toml<br/>retargeting"] --> H5

  classDef start fill:#eceff1,stroke:#546e7a,color:#263238
  classDef wiring fill:#b2dfdb,stroke:#00796b,color:#004d40
  classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100

  class C1,C3,C4,C2,H5,H6 transport
  class H1,H2,M6 wiring
  class IMP,DEL,M4,WF,MIR,M5,M10,L4,FAKE start
```

---

## 11. ![Critical](https://img.shields.io/badge/Critical-c0392b) Critical findings

### ![Critical](https://img.shields.io/badge/Critical-c0392b) CRITICAL-1 -- Minimizer callbacks have no authentication

**CWE-306 Missing Authentication for Critical Function. Status: `CONFIRMED`. Reachable by P1.**

**Related files**: `src/bot.ml`, `src/webhooks/minimizer.ml`, `src/ci/minimization.ml`

The router dispatches three routes with no secret, no HMAC, and no caller identity:

```ocaml
(* src/bot.ml:60-62 *)
| "/coq-bug-minimizer" | "/ci-minimization" | "/resume-ci-minimization" ->
    Minimizer.handle_minimizer_webhook ~bot_info ~key ~app_id ~endpoint:path
      ~body
```

`coq_bug_minimizer_results_action` splits the first body line into space-separated
fields and trusts every one of them:

```ocaml
(* src/ci/minimization.ml:1376-1397 *)
match Str.split (Str.regexp " ") stamp with
| [id; author; repo_name; branch_name; owner; _repo; _ (*pr_number*)]
| [id; author; repo_name; branch_name; owner; _repo] ->
    (fun () ->
      Bot_components.Github_installations.action_as_github_app ~bot_info
        ~key ~app_id ~owner
        (Bot_components.GitHub_mutations.post_comment
           ~id:(Bot_components.GitHub_ID.of_string id) ~message:(...) )
      >>= Utils.report_on_posting_comment
      <&> ( Git_utils.execute_cmd
              (f "git push https://%s:%s@github.com/%s.git --delete '%s"
                 bot_info.github_name (Bot_info.github_pat bot_info)
                 repo_name branch_name ) >>= ... ) )
```

| Stamp field | Attacker controls | Effect |
|-------------|-------------------|--------|
| `owner` | Any org name | `action_as_github_app` resolves the real installation and mints a real org-scoped token |
| `id` | Any GraphQL node ID | The bot posts a comment on that thread as the GitHub App |
| `repo_name` | Any `owner/repo` | PAT-authenticated `git push --delete` against it |
| `branch_name` | Any string | Branch deleted, and shell injection per CRITICAL-2 |

Both effects are joined with `<&>`, which evaluates both operands into promises before
joining, so the PAT command starts even when the `owner` lookup subsequently fails.

**Fix.** Require a shared secret on all three routes, sent as a header and compared with
`Eqaf.equal`. The secret must be provisioned into `run-coq-bug-minimizer` as an Actions
secret. Additionally bind the callback to state the bot created: record the branch names
the bot pushed and reject stamps that do not match a pending job.

---

<a id="critical-2"></a>

### ![Critical](https://img.shields.io/badge/Critical-c0392b) CRITICAL-2 -- Shell command injection in the branch-delete command

**CWE-78 OS Command Injection. Status: `CONFIRMED`. Reachable by P1 through CRITICAL-1.**

**Related files**: `src/ci/minimization.ml`, `bot-components/utils/Git_utils.ml`

```ocaml
(* src/ci/minimization.ml:1393-1397 *)
Git_utils.execute_cmd
  (f "git push https://%s:%s@github.com/%s.git --delete '%s"
     bot_info.github_name
     (Bot_info.github_pat bot_info)
     repo_name branch_name )
```

The string is executed through `/bin/sh`:

```ocaml
(* bot-components/utils/Git_utils.ml:20-22 *)
Lwt_io.printf "Executing command: %s\n" command
>>= fun () ->
let process = Lwt_process.open_process_full (Lwt_process.shell command) in
```

Three defects sit on the same line:

| # | Defect | Consequence |
|---|--------|-------------|
| 1 | A single quote is opened before `branch_name` and never closed | The total quote count is `1 + count(branch_name)`; the shell only parses when `branch_name` contains an odd number of quotes |
| 2 | `repo_name` is interpolated with no quoting | Shell metacharacters pass through the URL segment |
| 3 | The full command, including the PAT, is printed before execution with no `~mask` | Credential disclosure, see HIGH-4 |

**Reproduction.** Because `Str.split (Str.regexp " ")` forbids spaces in `branch_name`,
the payload must be space-free and must balance the quote. `';id` satisfies both. Run
locally against `sh` with `git push` replaced by `echo`:

| `branch_name` | Resulting shell command | Result |
|---------------|-------------------------|--------|
| `run-coq-bug-minimizer-123` | `echo git push URL --delete 'run-coq-bug-minimizer-123` | `Syntax error: Unterminated quoted string`, exit 2 |
| `';id` | `echo git push URL --delete '';id` | `id` executes, exit 0 |
| `';echo${IFS}RCE-PROOF` | `echo git push URL --delete '';echo${IFS}RCE-PROOF` | `RCE-PROOF` printed, exit 0; `${IFS}` supplies the missing spaces |

Two conclusions follow, and the second matters for the fix:

1. Arbitrary command execution on the bot host is available to any unauthenticated
   internet client, and the bot host holds the App private key, the PAT, and the GitLab
   tokens in process memory and environment.
2. **The benign path is already broken.** With a normal branch name the command is
   always a shell syntax error, so branch cleanup in `run-coq-bug-minimizer` has never
   worked on this code path. The delete is dead code that only functions when an
   attacker supplies the balancing quote.

**Fix.** Do not build a shell string. Use `Lwt_process.exec` with an argument vector, or
at minimum `Stdlib.Filename.quote_command`, and pass the credential through a git
credential helper or `http.extraHeader` rather than embedding it in the URL.

---

### ![Critical](https://img.shields.io/badge/Critical-c0392b) CRITICAL-3 -- Unauthenticated resume writes an attacker-chosen workflow image

**CWE-306 Missing Authentication for Critical Function. Status: `CONFIRMED`. Reachable by P1.**

**Related files**: `src/ci/minimization.ml`, `run_ci_minimization.sh`

`/resume-ci-minimization` parses `docker_image` and the remaining fields straight from
the unauthenticated body:

```ocaml
(* src/ci/minimization.ml:1414-1449 *)
match Str.split (Str.regexp " ") stamp with
| [comment_thread_id; _author; _repo_name; _branch_name; owner; repo; pr_number] -> (
    message |> String.split ~on:'\n'
    |> function
    | docker_image :: target :: ci_targets_joined :: opam_switch
      :: failing_urls :: passing_urls :: base :: head
      :: extra_arguments_joined :: bug_file_lines -> ...
```

`docker_image` is then substituted into the workflow file of a trusted repository and
pushed with the PAT:

```bash
# run_ci_minimization.sh:55
sed -i 's~^\(\s*\)[^:\s]*custom_image:.*$~\1custom_image: '"'${docker_image}'~" .github/workflows/main.yml
# run_ci_minimization.sh:78
git push --set-upstream "https://$bot_name:$token@github.com/$repo_name.git" "$branch_name"
```

No proof is required that a corresponding minimization job exists. An attacker chooses
the container image that a workflow in `rocq-community/run-coq-bug-minimizer` will run,
and chooses `bug.v` contents. This is a supply-chain foothold in a repository that
project members trust, not merely wasted CI minutes.

**Fix.** Authenticate the route as in CRITICAL-1, and validate `docker_image` against a
registry and repository allowlist before it reaches `sed`.

---

### ![Critical](https://img.shields.io/badge/Critical-c0392b) CRITICAL-4 -- GitHub webhooks without `installation.id` skip signature verification

**CWE-347 Improper Verification of Cryptographic Signature. Status: `CONFIRMED`. Reachable by P1.**

**Related files**: `bot-components/github/GitHub_subscriptions.ml`, `tests/test_webhook.ml`

```ocaml
(* bot-components/github/GitHub_subscriptions.ml:248-263 *)
( try
    let install_id =
      json |> member "installation" |> member "id" |> to_int
    in
    (* if there is an install id, the webhook should be signed *)
    match Header.get headers "X-Hub-Signature" with
    | Some signature ->
        let expected =
          Digestif.SHA1.(to_raw_string (hmac_string ~key:secret body))
          |> Ohex.encode |> f "sha1=%s"
        in
        if Eqaf.equal signature expected then Ok (Some install_id)
        else Error "Webhook signed but with wrong signature."
    | None ->
        Error "Webhook comes from a GitHub App, but it is not signed."
  with Yojson.Json_error _ | Type_error _ -> Ok None )
```

The signature check is inside the `try` block whose only purpose is to read
`installation.id`. Omit that field and `to_int` raises `Type_error` (or if the payload is malformed/missing the installation object, `Yojson.Json_error`), the handler returns
`Ok None`, and the event is decoded and dispatched with no HMAC verification.

The compensating claim in the test suite is incorrect:

```ocaml
(* tests/test_webhook.ml *)
(* Webhooks without installation.id are still accepted by receive_github, but any action
   requiring GitHub API access will fail because action_as_github_app requires a GitHub
   App installation. *)
```

`action_as_github_app` does not need `install_id` from the event. It looks the
installation up by the `owner` field taken from the request body
(`GitHub_installations.ml:52-79`), so unsigned events do obtain real tokens.

| Unsigned event | Handler | Action taken |
|----------------|---------|--------------|
| `PullRequestUpdated` | `github.ml:277` | `git_fetch` on an attacker-supplied `html_url`, merge, force-push to GitLab; see HIGH-5, HIGH-6 |
| `PullRequestClosed` | `github.ml:260` | Delete the GitLab `pr-N` ref with the GitLab token |
| `IssueOpened` | `github.ml:335` | Start a minimizer job, comment as the bot |
| `CommentCreated` | `github.ml:358` | Same minimize and CI-minimize paths |
| `IssueClosed` | `github.ml:284` | Milestone mutation |
| `CheckRunReRequested` | `github.ml:363` | Rejected with 401. Correct, fail-closed |
| `merge now`, `run CI`, `bench` | `github.ml:133,159,178,198` | Blocked, all require `Option.is_some install_id` |

**Fix.** Verify the signature before and independently of parsing the body. Require
`X-Hub-Signature-256` on every GitHub route with no exception, and treat a missing
`installation.id` as a decode error rather than as an unauthenticated-but-valid event.

---

## 12. ![High](https://img.shields.io/badge/High-e67e22) High findings

### ![High](https://img.shields.io/badge/High-e67e22) HIGH-1 -- GitLab webhooks without a token are processed as valid

**CWE-306. Status: `CONFIRMED`. Reachable by P1.**

**Related files**: `bot-components/gitlab/GitLab_subscriptions.ml`, `src/webhooks/gitlab.ml`

```ocaml
(* bot-components/gitlab/GitLab_subscriptions.ml:113-125 *)
( match Header.get headers "X-Gitlab-Token" with
  | Some header_secret ->
      if Eqaf.equal secret header_secret then return true
      else Error "Webhook password mismatch."
  | None ->
      return false )
>>= fun signed ->
match Header.get headers "X-Gitlab-Event" with
| Some event -> (
  try
    let json = Yojson.Basic.from_string body in
    gitlab_event ~event json |> Result.map ~f:(fun r -> (signed, r))
```

A missing header yields `signed = false`, which is not an error. Both handlers in
`src/webhooks/gitlab.ml:19,30` bind the flag as `_` and never consult it.

| Forged payload achieves | Code path |
|-------------------------|-----------|
| Create or overwrite any GitHub Check Run, including a false success | `Job.job_action`, `Job_status.pipeline_action` |
| Read a GitLab job trace with the bot's token and publish it on GitHub | `job_failure` -> `GitLab_queries.get_build_trace` |
| Retry any GitLab job the token can reach | `GitLab_mutations.retry_job` |
| Trigger auto-minimization of the Rocq pipeline | `pipeline_action` with `auto_minimize_on_failure` |

**Fix.** Return `Error` when the header is absent. The `signed` flag then becomes
redundant and should be removed rather than left as a trap for future handlers.

---

### ![High](https://img.shields.io/badge/High-e67e22) HIGH-2 -- Unmapped GitLab path is used directly as a GitHub `owner/repo`

**CWE-20. Status: `CONFIRMED`. Reachable by P1 in combination with HIGH-1.**

**Related files**: `bot-components/github/GitHub_GitLab_sync.ml`

```ocaml
(* bot-components/github/GitHub_GitLab_sync.ml:48-56 *)
let github_full_name =
  match Hashtbl.find gitlab_mapping full_name_with_domain with
  | Some value -> value
  | None ->
      Stdio.printf "Warning: No correspondence found for GitLab repository %s.\n"
        full_name_with_domain ;
      gitlab_repo_full_name
```

The fallback is the raw GitLab path. A forged Job event whose
`repository.homepage` is `https://anything/rocq-prover/rocq` needs no mapping entry: the
bot resolves the GitHub target to `rocq-prover/rocq`, mints a real installation token,
and writes Checks there.

**Fix.** Return an error when the mapping lookup misses. A repository the operator has
not configured is not a repository the bot should act on.

---

### ![High](https://img.shields.io/badge/High-e67e22) HIGH-3 -- GitLab and schedule secrets default to the GitHub webhook secret

**CWE-1188 Insecure Default Initialization. Status: `CONFIRMED`. Reachable by P6.**

**Related files**: `src/config/config.ml`

```ocaml
(* src/config/config.ml:70-86 *)
let gitlab_webhook_secret toml_data =
  match subkey_value toml_data "gitlab" "webhook_secret" with
  | None ->
      Option.value ~default:(github_webhook_secret toml_data)
        (Sys.getenv "GITLAB_WEBHOOK_SECRET")
  | Some secret -> secret

let daily_schedule_secret toml_data =
  match subkey_value toml_data "github" "daily_schedule_secret" with
  | None ->
      Option.value ~default:(github_webhook_secret toml_data)
        (Sys.getenv "DAILY_SCHEDULE_SECRET")
  | Some secret -> secret
```

The three channels have different exposure. The GitHub webhook secret is visible to
every GitHub App administrator; the GitLab secret is visible to the maintainers of every
mapped GitLab project; the schedule secret travels in an HTTP request body. Sharing one
value means the weakest holder can forge on all three channels. `README.md:312-313`
documents the fallback as intended behaviour, so this is a design decision to reverse,
not an oversight to patch quietly.

**Fix.** Require all three secrets explicitly and fail startup when any is missing.
Silent credential reuse should never be a default.

---

### ![High](https://img.shields.io/badge/High-e67e22) HIGH-4 -- Tokens printed in command logs, git URLs, and process argv

**CWE-532 Insertion of Sensitive Information into Log File. Status: `CONFIRMED`. Reachable by P5.**

**Related files**: `bot-components/utils/Git_utils.ml`, `coq_bug_minimizer.sh`, `run_ci_minimization.sh`

```ocaml
(* bot-components/utils/Git_utils.ml:19-22 *)
let execute_cmd ?(mask = []) command =
  Lwt_io.printf "Executing command: %s\n" command
  >>= fun () ->
  let process = Lwt_process.open_process_full (Lwt_process.shell command) in
```

`mask` is consumed only by `report_status`, which runs on a non-zero exit
(`Git_utils.ml:7-16`). The unconditional print at line 20 happens first and is never
masked.

| Call site | Credential exposed | Masking |
|-----------|--------------------|---------| 
| `src/ci/minimization.ml:1394` | GitHub PAT inside the push URL | No `~mask` argument at all |
| `src/utils/coq.ml:12-24` | GitHub PAT as a positional argument | `~mask` passed, but the print at line 20 precedes it |
| `bot-components/github/GitHub_GitLab_sync.ml:42` | GitLab token inside `https://oauth2:TOKEN@host` | No mask; every `mirror_action` and `update_pr` |
| `coq_bug_minimizer.sh:39`, `run_ci_minimization.sh:78` | GitHub PAT in the child process argv | Visible in `ps` to any host user |

**Fix.** Apply the mask inside `execute_cmd` before the print, and remove credentials
from command lines entirely by using a git credential helper. Redaction is a backstop;
not placing the secret on the command line is the control.

---

### ![High](https://img.shields.io/badge/High-e67e22) HIGH-5 -- `git_fetch` and `git_push` interpolate remote URLs into a shell unquoted

**CWE-78. Status: `CONFIRMED`. Reachable by P1 with CRITICAL-4, or by P2 with MEDIUM-6.**

**Related files**: `bot-components/utils/Git_utils.ml`

```ocaml
(* bot-components/utils/Git_utils.ml:43-54 *)
let git_fetch ?(force = true) remote_ref local_branch_name =
  f "git fetch --quiet -fu %s %s%s:%s" remote_ref.repo_url
    (if force then "+" else "")
    (Stdlib.Filename.quote remote_ref.name)
    (Stdlib.Filename.quote local_branch_name)

let git_push ?(force = true) ?(options = "") ~remote_ref ~local_ref () =
  f "git push %s %s%s:%s %s" remote_ref.repo_url
    (if force then " +" else " ")
    (Stdlib.Filename.quote local_ref)
    (Stdlib.Filename.quote remote_ref.name)
    options
```

Ref names are quoted; `repo_url` and `options` are not. Two sources reach `repo_url`:

1. `pr_info.head.branch.repo_url` and `pr_info.base.branch.repo_url`, read from
   `repo.html_url` in the pull request payload (`GitHub_subscriptions.ml:40`). On a
   signed event GitHub controls this. On an unsigned event, CRITICAL-4 hands it to the
   attacker.
2. `gitlab_repo`, built at `GitHub_GitLab_sync.ml:42` from `gitlab_domain` and
   `gitlab_full_name`. Both can originate from a repository's own `coqbot.toml` under
   MEDIUM-6, which makes this reachable without CRITICAL-4.

**Fix.** Quote `repo_url`, and preferably move `git_fetch` and `git_push` to an argument
vector so quoting correctness is structural rather than remembered.

---

### ![High](https://img.shields.io/badge/High-e67e22) HIGH-6 -- `git_test_modified` interpolates commit SHAs into a shell unquoted

**CWE-78. Status: `CONFIRMED`. Reachable by P1 with CRITICAL-4.**

**Related files**: `bot-components/utils/Git_utils.ml`, `src/actions/pr_sync.ml`

```ocaml
(* bot-components/utils/Git_utils.ml:78-82 *)
let git_test_modified ~base ~head pattern =
  let command =
    f {|git diff %s...%s --name-only | grep "%s"|} base head pattern
  in
  Lwt_unix.system command
```

`Lwt_unix.system` runs the string through `/bin/sh`, and none of the three
interpolations is quoted. The call sites pass raw commit SHAs from the webhook payload:

```ocaml
(* src/actions/pr_sync.ml:46-48 *)
git_test_modified ~base:pr_info.base.sha ~head:pr_info.head.sha
  ".*gitlab.*\\.yml"

(* src/actions/pr_sync.ml:85-86 *)
git_test_modified ~base:pr_info.base.sha ~head:pr_info.head.sha
  "dev/ci/docker/.*Dockerfile.*"
```

`base.sha` and `head.sha` come from `commit_info_of_json`
(`GitHub_subscriptions.ml:38-42`) with no format validation. On an unsigned event the
attacker controls both, and unlike CRITICAL-2 there is no quote-balancing constraint and
no restriction on spaces. This is a second independent path to command execution on the
bot host.

The severity is High rather than Critical only because it requires CRITICAL-4 as the
source. Closing CRITICAL-4 alone leaves the sink in place for any future caller that
passes non-GitHub data.

**Fix.** Quote all three arguments, or replace the `git diff | grep` pipeline with
`git diff --name-only` executed via an argument vector plus an OCaml-side pattern match.
Validate that SHAs match `[0-9a-f]{7,40}` at the parsing boundary.

---

## 13. ![Medium](https://img.shields.io/badge/Medium-f39c12) Medium findings

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-1 -- Minimize, CI-minimize, and resume commands have no authorization check

**CWE-862 Missing Authorization. Status: `CONFIRMED`. Reachable by P2.**

**Related files**: `src/webhooks/github.ml`

```ocaml
(* src/webhooks/github.ml:76-92 *)
match minimize_text_of_body body with
| Some (options, script) ->
    (fun () ->
      init_git_bare_repository ~bot_info
      >>= fun () ->
      Bot_components.Github_installations.action_as_github_app ~bot_info ~key
        ~app_id ~owner:comment_info.issue.issue.owner (fun ~bot_info ->
          Minimization.run_coq_minimizer ~bot_info ~script ... ) )
    |> Lwt.async ;
```

No team check and no `install_id` check. The comparison across commands, corrected
against the source:

| Command | Team check | `install_id` required | Enforcing code |
|---------|------------|:---------------------:|----------------|
| `merge now` | `@rocq-prover/pushers` | Yes | `GitHub_automation.ml:97-108` |
| `run CI` | `@rocq-prover/contributors` | Yes | `pr_sync.ml:171-191` |
| `bench`, `bench native` | `@rocq-prover/contributors` | Yes | `bench.ml:291-305` |
| `minimize` | None | No | `github.ml:77` |
| `ci minimize` | None | No | `github.ml:111` |
| `resume ci minimize` | None | No | `github.ml:98` |

The last three are the outliers. Any account that can comment on an installed repository
starts a PAT-authenticated push and a GitHub Actions run. Execution of the submitted
script happens on GitHub Actions, which is by design (ACCEPTED-3); the gap is that
nothing gates who may start it.

**Fix.** Apply the same `get_team_membership` gate already used by `run CI`.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-3 -- Check re-run trusts `external_id` and retries GitLab as the bot

**CWE-20. Status: `CONFIRMED`. Requires a signed event, so P2 with a legitimate check re-request.**

**Related files**: `bot-components/utils/Minimize_parser.ml`, `bot-components/gitlab/GitLab_mutations.ml`

Unsigned re-runs are rejected at `github.ml:363-365`; that control is correct. Signed
re-runs parse the identifier and act on it:

```ocaml
(* bot-components/utils/Minimize_parser.ml:179-190 *)
let parse_check_run_external_id external_id =
  match String.split ~on:',' external_id with
  | [http_repo_url; url_part] -> (
    match Git_utils.parse_gitlab_repo_url ~http_repo_url with
    | Error _ -> None
    | Ok (gitlab_domain, _) -> Some (gitlab_domain, url_part) )
  | [url_part] ->
      (* Backward compatibility *)
      Some ("gitlab.com", url_part)
  | _ -> None
```

```ocaml
(* bot-components/gitlab/GitLab_mutations.ml:5-7 *)
let generic_retry ~bot_info ~gitlab_domain ~url_part =
  let uri =
    f "https://%s/api/v4/%s/retry" gitlab_domain url_part |> Uri.of_string
```

`url_part` is placed verbatim into the API path. `gitlab_domain` is constrained, because
`gitlab_name_and_token` rejects domains absent from the configuration. `url_part` is
not: it is not bound to a job the bot created, nor to the installation that raised the
event. The result is a `POST .../retry` oracle for any path the token can reach.

**Fix.** Require `external_id` to match `projects/<int>/(jobs|pipelines)/<int>` and
reject the single-field legacy form.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-4 -- Caller-supplied URLs are fetched with no allowlist

**CWE-918 Server-Side Request Forgery. Status: `CONFIRMED`. Reachable by P1 and P2.**

**Related files**: `src/ci/minimization.ml`, `bot-components/utils/HTTP_utils.ml`

```ocaml
(* src/ci/minimization.ml:220-258 *)
| Some (MinimizeAttachment {url}) -> (
  match parse_github_artifact_url url with
  | Some (ArtifactInfo {...}) -> (* GitHub artifact path, authenticated *)
  | None ->
      Bot_components.HTTP_utils.download_to ~uri:(Uri.of_string url)
        bug_file_ch
```

`download_cps` (`HTTP_utils.ml:168-194`) follows redirects recursively with no
allowlist on scheme, host, port, or address range, and no redirect-count limit.

| Entry point | Requirement | Additional exposure |
|-------------|-------------|---------------------|
| Signed comment with `@bot minimize [desc](url)` | A GitHub account (P2) | Requests originate from the bot host: cloud metadata, link-local, internal services |
| `/resume-ci-minimization` body | None (P1) | Same, with no account, and combines with CRITICAL-3 |

**Fix.** Allowlist scheme `https` and the artifact hosts actually needed, resolve the
host and reject private, loopback, and link-local addresses before connecting, and cap
the redirect chain.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-5 -- GitLab pipeline variables are copied into public GitHub Checks

**CWE-200. Status: `CONFIRMED`. Reachable by P1 with HIGH-1.**

**Related files**: `bot-components/ci/pipeline.ml`

```ocaml
(* bot-components/ci/pipeline.ml:9-14 *)
let create_pipeline_summary ?summary_top pipeline_info pipeline_url =
  let variables =
    List.map pipeline_info.variables ~f:(fun (key, value) ->
        f "- %s: %s" key value )
    |> String.concat ~sep:"\n"
```

`pipeline_info_of_json` reads `object_attributes.variables`
(`GitLab_subscriptions.ml:78-84`) and the summary is passed verbatim to
`create_check_run` (`job_status.ml:362-369`), becoming a public Check body. Two distinct
risks: genuine GitLab variables that hold credentials are published, and under HIGH-1 an
attacker injects arbitrary Markdown into a Check on a repository they do not control.

**Fix.** Publish only an explicit allowlist of variable names, for example `FULL_CI` and
`SKIP_DOCKER`, which are the only ones the bot's own logic reads.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-6 -- Default-branch `coqbot.toml` retargets where the GitLab token pushes

**CWE-20. Status: `CONFIRMED`. Reachable by P2 acting as an administrator of an installed repository.**

**Related files**: `bot-components/github/GitHub_GitLab_sync.ml`

```ocaml
(* bot-components/github/GitHub_GitLab_sync.ml:84-134 *)
( match Hashtbl.find github_mapping gh_repo with
  | None -> (
      GitHub_queries.get_default_branch ~bot_info ~owner:issue.owner ~repo:issue.repo
      >>= function
      | Ok branch -> (
          GitHub_queries.get_file_content ~bot_info ~owner:issue.owner
            ~repo:issue.repo ~branch
            ~file_name:(f "%s.toml" bot_info.github_name)
          >>= function
          | Ok (Some content) ->
              let gl_domain = ... (* mapping.gitlab_domain from the TOML *) in
              let gl_repo   = ... (* mapping.gitlab from the TOML *) in
              ...
              Lwt.return (gl_domain, gl_repo)
```

Anyone who installs the App on a repository they control, and who is not listed in
`[mappings]`, chooses `gl_domain` and `gl_repo`. The bot then builds
`https://oauth2:TOKEN@<gl_domain>/<gl_repo>.git` and pushes there. Two consequences:

1. The GitLab token is presented to a host of the attacker's choosing, which discloses
   it to that host.
2. The resulting URL flows unquoted into a shell command, which is HIGH-5 without
   needing CRITICAL-4.

The code acknowledges the gap at `GitHub_GitLab_sync.ml:148`:
`(* TODO: generalize to use repository mappings, with enhanced security *)`.

**Fix.** Accept the discovered mapping only when `gl_domain` is a configured GitLab
instance, and require the operator to confirm new mappings rather than adopting them
from repository content.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-7 -- No body-size limit, no replay store, quadratic regexes

**CWE-400 Uncontrolled Resource Consumption. Status: `CONFIRMED`. Reachable by P1.**

**Related files**: `src/bot.ml`

`src/bot.ml:46` calls `Cohttp_lwt.Body.to_string body` with no cap, for every route,
before any authentication decision. The whole body is buffered in memory. The bot then
runs backtracking `Str` regexes over it:

```ocaml
(* src/ci/minimization.ml:1377 and 1411 *)
if String_utils.string_match ~regexp:"\\([^\n]+\\)\n\\([^\r]*\\)" body then
```

`Str` is a backtracking engine and `String_utils.string_match` uses `Str.search_forward`,
which retries at every start offset. A large body containing no newline makes
`[^\n]+` consume to the end and fail at every offset, giving quadratic behaviour. The
server is a single Lwt event loop, so this stalls all request handling, not just the
attacker's connection.

`X-GitHub-Delivery` is never read, so signed webhooks can be replayed indefinitely, and
there is no concurrency cap on the `Lwt.async` side effects the handlers spawn.

**Fix.** Reject bodies above a fixed size before parsing, verify authentication before
running any regex over the body, record `X-GitHub-Delivery` in a bounded replay cache,
and bound in-flight `Lwt.async` work.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-8 -- One GitLab webhook secret shared by all mapped projects

**CWE-1188. Status: `CONFIRMED`. Reachable by P4.**

**Related files**: `src/bot.ml`

```ocaml
(* src/bot.ml:12-13 *)
(* TODO: make webhook secret project-specific *)
let gitlab_webhook_secret = Config.gitlab_webhook_secret toml_data
```

Every mapped GitLab project is configured with the same token value, and every project
maintainer can read it from their own project settings. Once HIGH-1 is closed, this
becomes the primary remaining forgery path: a maintainer of the least-trusted mapped
project can forge Job and Pipeline events for `coq/coq`.

**Fix.** Key the secret by GitLab project or instance in the configuration and select it
using the payload's project identity before verification.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-9 -- CI configuration gate checks the PR author, not the pusher

**CWE-863 Incorrect Authorization. Status: `CONFIRMED`. Reachable by P2.**

**Related files**: `src/actions/pr_sync.ml`

```ocaml
(* src/actions/pr_sync.ml:55-58 *)
(* This is an approximation:
   we are checking who the PR author is and not who is pushing. *)
GitHub_queries.get_team_membership ~bot_info ~org:"rocq-prover"
  ~team:"contributors" ~user:pr_info.issue.user )
```

The in-source comment is accurate. The gate exists to stop untrusted contributors from
bypassing the manual bench job by editing the GitLab CI configuration, but it evaluates
`pr_info.issue.user`, the PR author. If a contributors member opens a PR and a
non-member later pushes a commit that edits `*gitlab*.yml`, the author check passes and
CI runs on the non-member's configuration change. The `synchronize` payload carries the
pusher in `sender.login`, which the bot does not read.

**Fix.** Evaluate membership for the actor who produced the event, and treat author and
actor as distinct throughout the authorization logic.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-10 -- Commit status body built by string concatenation; commit ref unvalidated in the URL path

**CWE-116 Improper Encoding. Status: `CONFIRMED`. Reachable by P1 with HIGH-1.**

**Related files**: `bot-components/github/GitHub_mutations.ml`

```ocaml
(* bot-components/github/GitHub_mutations.ml:266-280 *)
let send_status_check ~bot_info ~repo_full_name ~commit ~state ~url ~context
    ~description =
  ...
  let body =
    {|{"state": "|} ^ state ^ {|","target_url":"|} ^ url
    ^ {|", "description": "|} ^ description ^ {|", "context": "|} ^ context
    ^ {|"}|}
    |> Cohttp_lwt.Body.of_string
  in
  let uri =
    "https://api.github.com/repos/" ^ repo_full_name ^ "/statuses/" ^ commit
    |> Uri.of_string
```

Two separate defects:

| Defect | Current reachability |
|--------|----------------------|
| JSON assembled by concatenation with no escaping of `state`, `url`, `description`, or `context` | Not currently exploitable. The sole caller is `documentation.ml:19,25`, where `context` derives from `job_info.build_name`, and `send_doc_url` only runs when `Repo_config.is_doc_artifact_job cfg build_name` holds, which restricts `build_name` to the configured `doc_artifact_jobs` allowlist. The other three arguments are literals or config-derived |
| `commit` interpolated into the REST path with no validation | Exploitable. `commit` is `job_info.common_info.head_commit`, taken from the GitLab payload by `extract_commit` (`GitLab_subscriptions.ml:7-25`) with no format check. Under HIGH-1 an attacker sets it freely and steers the authenticated POST to another path under `/repos/<owner>/<repo>/` |

The JSON half is a latent defect held closed by an allowlist elsewhere in the codebase.
That is a fragile invariant: any future caller of `send_status_check` reintroduces the
injection. Both halves should be fixed together.

**Fix.** Build the body with `Yojson` and validate `commit` against `[0-9a-f]{7,40}` at
the point it is parsed out of the webhook.

---

### ![Medium](https://img.shields.io/badge/Medium-f39c12) MEDIUM-11 -- Unauthenticated routes drive installation-token minting

**CWE-770 Allocation Without Limits. Status: `CONFIRMED`. Reachable by P1.**

**Related files**: `bot-components/github/GitHub_installations.ml`

```ocaml
(* bot-components/github/GitHub_installations.ml:52-79 *)
let action_as_github_app ~bot_info ~key ~app_id ~owner action =
  match Hashtbl.find installation_ids owner with
  | Some install_id -> ...
  | None -> (
      GitHub_app.get_installations ~bot_info ~key ~app_id
      >>= function ...
```

Every request naming an owner that is not already cached triggers a signed
`GET /app/installations` call. The `owner` field is attacker-chosen on the
unauthenticated minimizer routes (CRITICAL-1) and on unsigned GitHub webhooks
(CRITICAL-4). A stream of distinct owner names therefore drives unbounded App-level API
calls and RSA signing operations.

The cache itself is bounded, because `installation_ids` is only populated for owners that
actually resolve, so this is rate-limit and CPU exhaustion rather than memory growth.
Exhausting the App's API quota disables every legitimate bot function until the window
resets, so the impact is a full functional outage from unauthenticated traffic. This is
distinct from MEDIUM-7: the amplification is in outbound API calls and asymmetric crypto,
not in request-body handling.

**Fix.** Authenticate before resolving any installation, negatively cache unknown owners
with a short TTL, and rate-limit the installation lookup path.

---

## 14. ![Low](https://img.shields.io/badge/Low-3498db) Low findings

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-1 -- HMAC uses the SHA-1 header only

**CWE-328. Status: `CONFIRMED`.**

**Related files**: `bot-components/github/GitHub_subscriptions.ml`

`GitHub_subscriptions.ml:253-258` reads `X-Hub-Signature` and computes HMAC-SHA1. The comparison is constant-time via `Eqaf.equal`, and HMAC-SHA1 is not practically forgeable without the key, so this is a header-choice issue rather than a break. GitHub's documented preferred header is `X-Hub-Signature-256`. The bot never reads it, so if GitHub stops sending the SHA-1 header, verification falls into the `None` branch. Combined with CRITICAL-4 that branch is not uniformly fail-closed.

**Fix.** Prefer `X-Hub-Signature-256`, accept SHA-1 only as a transitional fallback.

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-2 -- Stale-PR secret comparison is not constant-time

**CWE-208. Status: `CONFIRMED`.**

**Related files**: `src/webhooks/scheduled.ml`

`src/webhooks/scheduled.ml:13` uses `String.equal secret daily_schedule_secret`,
which short-circuits at the first differing byte. The secret also travels in the request
body as the third colon-separated field, so it appears in any access log that records
bodies, and replay is free because there is no nonce or timestamp.

**Fix.** Use `Eqaf.equal`, move the secret to a header, and add a timestamp window.

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-3 -- GraphQL node IDs are unvalidated opaque strings

**CWE-20. Status: `CONFIRMED`.**

**Related files**: `bot-components/github/GitHub_ID.ml`

`GitHub_ID.of_string` wraps any string. The type carries no evidence that an
ID is well formed or that it names a node the bot created. Validation must therefore
happen at each call site, and the minimizer callbacks do not do it, which is what makes
CRITICAL-1's comment impersonation possible.

**Fix.** Bind IDs to bot-created state at the callback boundary. A phantom-typed or
smart-constructor `GitHub_ID` would make the omission a type error.

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-4 -- Token-backed job traces are published to GitHub

**CWE-200. Status: `CONFIRMED`.**

**Related files**: `src/ci/job_status.ml`

On job failure the bot reads `/jobs/:id/trace` with the GitLab token and
embeds an excerpt in the Check body (`job_status.ml:78-115`). Under HIGH-1 the job ID is
attacker-chosen, and any credential a legitimate trace contains becomes public GitHub
content. Reporting the trace is the feature; treating a token-authenticated read as
publishable without scrubbing is the defect.

**Fix.** Scrub known secret patterns before publishing, and restrict trace reads to jobs
in projects the event was authenticated for.

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-5 -- JWT `iat` has no clock-skew margin

**CWE-703. Status: `CONFIRMED`.**

**Related files**: `bot-components/github/GitHub_app.ml`

```ocaml
(* bot-components/github/GitHub_app.ml:22-27 *)
let issuedAt = Unix.time () |> Int.of_float in
let payload =
  f {|{ "iat": %d, "exp": %d, "iss": %d }|} issuedAt
    (issuedAt + (55 * 10)) app_id
```

`exp` is `iat + 550` seconds, inside GitHub's 10-minute maximum. GitHub rejects JWTs
dated in the future, so forward clock skew on the host makes installation-token minting
fail. This is availability only: it fails closed.

**Fix.** Backdate `iat` by 60 seconds.

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-6 -- `play_job` builds its JSON body by string concatenation

**CWE-116, latent. Status: `POTENTIAL`.**

**Related files**: `bot-components/gitlab/GitLab_mutations.ml`

```ocaml
(* bot-components/gitlab/GitLab_mutations.ml:39-48 *)
key_value_pairs
|> List.map ~f:(fun (k, v) -> f {|{ "key": "%s", "value": "%s" }|} k v)
|> String.concat ~sep:","
|> f {|{ "job_variables_attributes": [%s] }|}
```

Not exploitable today: the only caller passes the literal
`[("coq_native", "yes")]` (`github.ml:185`). Recorded because it is the same defect class
as MEDIUM-10 and becomes exploitable the moment a caller forwards user input.

**Fix.** Build the body with `Yojson`.

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-7 -- `get_build_trace` ignores the HTTP status code

**CWE-754. Status: `CONFIRMED`.**

**Related files**: `bot-components/gitlab/GitLab_queries.ml`

```ocaml
(* bot-components/gitlab/GitLab_queries.ml:22-24 *)
Client.get ~headers uri
>>= fun (_response, body) ->
Cohttp_lwt.Body.to_string body |> Lwt.map Result.return
```

The response status is discarded, so a 401, 403, or 404 body is returned as though it
were the job trace. It then flows through `trace_action` and into a public GitHub Check.
This turns HIGH-1's forged job IDs into an oracle that publishes GitLab API error
responses, and it silently corrupts the retry heuristics in `trace_action`.

**Fix.** Check the status and return `Error` on anything other than 200.

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-8 -- Attacker input raises uncaught exceptions in the request path

**CWE-248. Status: `CONFIRMED`.**

**Related files**: `bot-components/github/GitHub_GitLab_sync.ml`

`github_repo_of_gitlab_project_path` calls `failwith` when the resolved name does not
split into exactly two segments:

```ocaml
(* bot-components/github/GitHub_GitLab_sync.ml:58-64 *)
match Str.split (Str.regexp "/") github_full_name with
| [owner; repo] -> (owner, repo)
| _ ->
    failwith
      (f "Could not split repository full name %s into (owner, repo)."
         github_full_name )
```

Reached from `src/webhooks/gitlab.ml:19` in the synchronous `match` scrutinee, not inside
`Lwt.async`. Under HIGH-1, a forged `repository.homepage` of
`https://host/a/b/c` combined with HIGH-2's fallback produces a three-segment name and
raises out of the handler. Cohttp isolates this per connection, so the process survives,
but the request terminates without a controlled response.

`Utils.toml_of_string` uses `Toml.Parser.unsafe` on repository-supplied `coqbot.toml`
content (`GitHub_GitLab_sync.ml:100,107`), which raises on malformed TOML and silently
aborts PR synchronisation through the async exception hook.

**Fix.** Return `Result` instead of raising in both places, and respond with 400.

### ![Low](https://img.shields.io/badge/Low-3498db) LOW-9 -- Bench authorization is decided after the API work it guards

**CWE-696 Incorrect Behavior Order. Status: `CONFIRMED`.**

**Related files**: `src/utils/bench.ml`

```ocaml
(* src/utils/bench.ml:245-305 *)
let* gitlab_check_summary = (* get_pull_request_refs, get_pipeline_summary *) in
let* process_summary = (* regex the summary for build_id and project_id *) in
let* allowed_to_bench =
  GitHub_queries.get_team_membership ~bot_info ~org ~team
    ~user:comment_info.author
in
match (allowed_to_bench, process_summary) with
| Ok true, Ok (build_id, project_id) -> GitLab_mutations.play_job ...
| Error err, _ | _, Error err ->
    GitHub_mutations.post_comment ~bot_info ~message:err ~id:pr.id
| Ok false, _ -> GitHub_automation.inform_user_not_in_contributors ...
```

The authorization decision is correct and fail-closed, and `play_job` runs only for
`Ok true`. Two ordering problems remain. Every commenter, authorized or not, causes two
GitHub GraphQL queries first. And because the `Error err` arm is matched before
`Ok false`, an unauthorized commenter who also triggers a summary-parsing failure
receives the internal error text as a comment instead of the not-in-team message.

**Fix.** Evaluate membership first and return early. Keep authorization decisions ahead
of the work they protect, and keep their failure messages distinct from operational
errors.

---

## 15. ![Info](https://img.shields.io/badge/Info-7f8c8d) Info

| | ID | Observation | Detail |
|---|----|-------------|--------|
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | INFO-1 | Exception hook prints raw exception text | `src/bot.ml:73-78`. If a library exception carries a URL containing a token it is logged. Related to HIGH-4 |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | INFO-2 | TLS terminated outside the process | `Server.create` at `src/bot.ml:70-71` binds a plain TCP port with no TLS. Normal for the Heroku deployment; a direct public bind would put webhook secrets on the wire |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | INFO-3 | Installation tokens in process memory | `GitHub_installations.ml:8-9`, cached about 40 minutes. Reading process memory is equivalent to holding those org tokens until expiry. A restart flushes the cache; the App key and PAT do not rotate on restart |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | INFO-4 | No secret-rotation runbook | The rotation procedure for the App key, PAT, GitLab tokens, and the three webhook secrets is not written down. `SECURITY.md` covers reporting, not rotation |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | INFO-5 | Live credentials in `.bot-env` | Contains an App ID, a GitHub PAT, a webhook secret, a full RSA private key, and two GitLab tokens. Mode `0600`, listed in `.gitignore`. Verified never committed: `git log --all --diff-filter=A` shows no matching path. Rotate anyway, since the values have been present in a shared workspace |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | INFO-6 | No HTTP method enforcement | `src/bot.ml:39-67` dispatches on path only and never inspects `Request.meth`. Every route answers any verb. No authentication consequence today, because the affected routes have none, but it widens the surface for browser-originated and cache-related tricks |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | INFO-7 | App private key PEM is world-readable | `app-bot-demo.2025-10-31.private-key.pem` is mode `0664` in the workspace, while `.bot-env` holding the same class of secret is `0600`. Gitignored via `*.private-key.pem` and never committed. `chmod 600`, then move it out of the workspace and rotate |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | INFO-8 | No CORS restrictions or origin validation | `src/bot.ml:39-67` returns no CORS headers or origin checks. Once auth is added, origin checking prevents browser-originated CSRF |

---

## 16. ![Accepted](https://img.shields.io/badge/Accepted-27ae60) Accepted risks

These are design decisions, documented so that reports about them can be closed quickly.

| | ID | Risk | Why accepted | Residual control |
|---|----|------|--------------|-----------------|
| ![Accepted](https://img.shields.io/badge/Accepted-27ae60) | ACCEPTED-1 | Untrusted PR heads are merged and force-pushed to GitLab as `pr-N` | This is the product. `pr_sync.ml` merging head with base and pushing is working as designed | GitLab protected-branch and protected-variable configuration, an operator responsibility documented at `README.md:47-50`. The bot cannot read those settings |
| ![Accepted](https://img.shields.io/badge/Accepted-27ae60) | ACCEPTED-2 | `@bot merge now` merges on one comment | The gates are deliberate: not the author, in assignees, no `needs:*` label, has a `kind:*` label, has a milestone, review decision `APPROVED`, target branch `master`, comment not email-originated, and membership of `@rocq-prover/pushers` (`GitHub_automation.ml:10-108`) | Account compromise of a pusher is out of scope. The email-origin rejection is an authenticity control and should be kept |
| ![Accepted](https://img.shields.io/badge/Accepted-27ae60) | ACCEPTED-3 | The minimizer runs commenter-supplied Coq and shell scripts | Execution is on GitHub Actions in `run-coq-bug-minimizer`, not on the bot host | Who may start it is MEDIUM-1 and is not accepted. Host-side execution via CRITICAL-2 is not accepted |

---

## 17. What is not a vulnerability here

| Claim | Assessment |
|-------|-----------|
| Rocq or Coq kernel soundness | Out of scope for this repository. Welcomed as public issues on the Rocq repository |
| GitHub, GitLab, or Heroku platform security | Out of scope except where consumed by this bot |
| Account compromise of a user with bot repository access | Out of scope |
| HMAC-SHA1 being collision-weak | Not a forgery path without the key. The real issue is header choice, LOW-1 |
| `Eqaf.equal` on the GitHub and GitLab secrets | Correct. Constant-time comparison, and it should not be replaced with `String.equal` |
| Rejecting a check re-run when `install_id` is absent | Correct. This branch is fail-closed and is the model the other routes should follow |
| `get_team_membership` returning `Error` | Correct. Every caller treats `Error` as denial, so the query fails closed |
| `members(query:$user, first:1)` returning one node | Sound. The result is scoped to the team and the code still requires an exact `login` match, so the worst case is a false denial |
| `Filename.quote` on git ref names | Correct. Ref names are quoted; the gap is the unquoted URL and SHA arguments, HIGH-5 and HIGH-6 |
| TLS terminated outside the process | Normal for this deployment style, INFO-2 |
| Global `Str` match state shared across requests | Reviewed and no exploitable instance found. Every `string_match` is followed by its `Str.matched_group` reads with no intervening `Lwt` bind, and no `Lwt_preemptive` thread uses `Str`. The pattern remains fragile and any future `>>=` between a match and a group read would be a real state-confusion bug |

---

## 18. Control objectives and current state

| ID | Objective | State | Blocking findings |
|----|-----------|-------|-------------------|
| P1 | Every route authenticates, fail-closed | OPEN | CRITICAL-1, CRITICAL-3, CRITICAL-4, HIGH-1 |
| P2 | Human commands authorize the actor before acting | PARTIAL | MEDIUM-1, MEDIUM-9, LOW-9 |
| P3 | Privileged credentials are bound to a proven identity, never to a caller-supplied field | OPEN | CRITICAL-1, HIGH-2, MEDIUM-3, MEDIUM-6, LOW-3 |
| P4 | Distinct secrets per channel and per project | OPEN | HIGH-3, MEDIUM-8 |
| P5 | No credential appears in argv, a URL, or a log line | OPEN | HIGH-4, INFO-1 |
| P6 | External data never reaches a shell as a string | OPEN | CRITICAL-2, HIGH-5, HIGH-6 |
| P7 | Structured payloads are built by an encoder, never by concatenation | OPEN | MEDIUM-10, LOW-6 |
| P8 | Bot output integrity: Checks and comments reflect real events | OPEN | CRITICAL-1, CRITICAL-4, HIGH-1, MEDIUM-5 |
| P9 | Abuse resistance: size limits, replay protection, rate limits | OPEN | MEDIUM-7, MEDIUM-11 |
| P10 | Outbound requests are restricted to intended hosts | OPEN | MEDIUM-4 |
| P11 | Published content is scrubbed of secrets | OPEN | MEDIUM-5, LOW-4, LOW-7 |
| P12 | Documented disclosure process and rotation runbook | PARTIAL | INFO-4 |

---

## 19. Remediation plan

Ordered by risk reduction per unit of work. Stage 1 items should land before this
document is made public, because it contains a working exploitation recipe for
CRITICAL-2.

### ![Critical](https://img.shields.io/badge/Critical-c0392b) Stage 1 -- Before public disclosure

| # | Action | Closes | Location |
|---|--------|--------|----------|
| 1 | Replace the shell string in the branch delete with an argument vector; move the PAT out of the URL | CRITICAL-2, part of HIGH-4 | `src/ci/minimization.ml:1394` |
| 2 | Require a shared secret on all three minimizer routes, compared with `Eqaf.equal` | CRITICAL-1, CRITICAL-3, part of MEDIUM-4, MEDIUM-11 | `src/bot.ml:60`, `src/webhooks/minimizer.ml` |
| 3 | Verify `X-Hub-Signature-256` before parsing the body, unconditionally | CRITICAL-4, LOW-1 | `bot-components/github/GitHub_subscriptions.ml:243` |
| 4 | Return `Error` when `X-Gitlab-Token` is absent; delete the now-dead `signed` flag | HIGH-1 | `bot-components/gitlab/GitLab_subscriptions.ml:114-119` |
| 5 | Quote or vectorise `repo_url` in `git_fetch` and `git_push`, and all three arguments of `git_test_modified` | HIGH-5, HIGH-6 | `bot-components/utils/Git_utils.ml:44,50,80` |
| 6 | Rotate every credential in `.bot-env` and the workspace PEM; `chmod 600` the PEM and move it out of the tree | INFO-5, INFO-7 | `.bot-env`, `app-bot-demo.2025-10-31.private-key.pem` |

### ![High](https://img.shields.io/badge/High-e67e22) Stage 2 -- Within one sprint

| # | Action | Closes | Location |
|---|--------|--------|----------|
| 7 | Require all three webhook secrets explicitly; fail startup when any is missing | HIGH-3 | `src/config/config.ml:70-86` |
| 8 | Apply `mask` inside `execute_cmd` before the print; adopt a git credential helper | HIGH-4 | `bot-components/utils/Git_utils.ml:19-22` |
| 9 | Error out when the GitLab mapping lookup misses, instead of using the raw path | HIGH-2 | `bot-components/github/GitHub_GitLab_sync.ml:49-56` |
| 10 | Gate `minimize`, `ci minimize`, and `resume` on `@rocq-prover/contributors` | MEDIUM-1 | `src/webhooks/github.ml:77,98,111` |
| 11 | Constrain `external_id` to `projects/<int>/jobs/<int>` or `projects/<int>/pipelines/<int>`; drop the legacy single-field form | MEDIUM-3 | `bot-components/utils/Minimize_parser.ml:179-190` |
| 12 | Allowlist the attachment fetch: `https` only, host allowlist, reject private and link-local addresses, cap redirects | MEDIUM-4 | `src/ci/minimization.ml:256`, `bot-components/utils/HTTP_utils.ml:168` |

### ![Medium](https://img.shields.io/badge/Medium-f39c12) Stage 3 -- Hardening

| # | Action | Closes | Location |
|---|--------|--------|----------|
| 13 | Enforce a body-size limit and authenticate before regexing; add `X-GitHub-Delivery` replay caching; cap in-flight async work | MEDIUM-7 | `src/bot.ml:39-67` |
| 14 | Negatively cache unknown owners and rate-limit installation lookup | MEDIUM-11 | `bot-components/github/GitHub_installations.ml:52-79` |
| 15 | Per-project GitLab webhook secrets | MEDIUM-8 | `src/bot.ml:12-13` |
| 16 | Allowlist pipeline variable names in Check summaries | MEDIUM-5 | `bot-components/ci/pipeline.ml:9-14` |
| 17 | Build all JSON with `Yojson`; validate `commit` against `[0-9a-f]{7,40}` | MEDIUM-10, LOW-6 | `bot-components/github/GitHub_mutations.ml:266-280`, `bot-components/gitlab/GitLab_mutations.ml:45` |
| 18 | Require a configured GitLab instance for discovered `coqbot.toml` mappings | MEDIUM-6 | `bot-components/github/GitHub_GitLab_sync.ml:84-134` |
| 19 | Authorize on the event actor rather than the PR author | MEDIUM-9 | `src/actions/pr_sync.ml:55-58` |
| 20 | Move the membership check ahead of the API work in bench; separate authorization messages from error messages | LOW-9 | `src/utils/bench.ml:245-305` |
| 21 | Constant-time compare and header transport for the schedule secret | LOW-2 | `src/webhooks/scheduled.ml:13` |
| 22 | Check the HTTP status in `get_build_trace`; scrub traces before publishing | LOW-7, LOW-4 | `bot-components/gitlab/GitLab_queries.ml:22-24` |
| 23 | Replace `failwith` and `Toml.Parser.unsafe` with `Result` on attacker-reachable paths | LOW-8 | `bot-components/github/GitHub_GitLab_sync.ml:58-64,100,107` |
| 24 | Backdate JWT `iat` by 60 seconds | LOW-5 | `bot-components/github/GitHub_app.ml:23` |
| 25 | Enforce POST on all webhook routes | INFO-6 | `src/bot.ml:39-67` |
| 26 | Write the secret-rotation runbook | INFO-4 | `docs/` |

```mermaid
flowchart LR
  S1["Stage 1<br/>Close unauthenticated RCE<br/>and fail-open auth"]
  S2["Stage 2<br/>Secret separation,<br/>authorization, allowlists"]
  S3["Stage 3<br/>Abuse resistance,<br/>encoding, hygiene"]
  PUB["Safe to publish<br/>this document"]

  S1 --> PUB
  S1 --> S2 --> S3

  classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20
  classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
  classDef wiring fill:#b2dfdb,stroke:#00796b,color:#004d40
  classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037

  class S1 transport
  class S2 wiring
  class S3 question
  class PUB domain
```

---

## 20. Regression tests to add

Each test should fail against the current tree and pass after the corresponding fix.
`tests/test_webhook.ml` currently asserts the CRITICAL-4 behaviour as correct and must be
updated rather than extended.

| Test | Asserts | Guards |
|------|---------|--------|
| `receive_github` with no `installation.id` and no signature | Returns `Error` | CRITICAL-4 |
| `receive_github` with a valid `installation.id` and a wrong signature | Returns `Error` | CRITICAL-4 |
| `receive_gitlab` with no `X-Gitlab-Token` | Returns `Error` | HIGH-1 |
| Minimizer route with no shared-secret header | Returns 401 | CRITICAL-1, CRITICAL-3 |
| Branch delete with a benign branch name | Command exits 0, proving the unbalanced quote is gone | CRITICAL-2 |
| Branch delete with `branch_name = "';id"` | The value is passed as one literal argument and no extra process is spawned | CRITICAL-2 |
| `git_fetch` and `git_push` with `repo_url` containing `;`, `$()`, and a space | The value survives as a single argument | HIGH-5 |
| `git_test_modified` with `base = "a;id"` | The value survives as a single argument | HIGH-6 |
| `parse_check_run_external_id "projects/1/jobs/2/../../../groups/1"` | Returns `None` | MEDIUM-3 |
| Startup with `GITLAB_WEBHOOK_SECRET` unset | Startup fails | HIGH-3 |
| `execute_cmd ~mask:[secret]` | The secret never appears on stdout, including on success | HIGH-4 |
| Attachment fetch against `http://127.0.0.1/` and `http://169.254.169.254/` | Rejected before connecting | MEDIUM-4 |
| `send_status_check` with `commit = "abc/../../other"` | Rejected at validation | MEDIUM-10 |
| Body above the size limit | Rejected before any regex runs | MEDIUM-7 |

---

## 21. Vulnerability disclosure policy

`SECURITY.md` at the repository root is the public entry point and should link here.

| Item | Policy |
|------|--------|
| Supported version | The `master` branch and the single deployed instance |
| Reporting channel | GitHub private security advisories, preferred; or a direct message on Zulip to a maintainer listed in `CITATION.cff` |
| Do not | Open a public issue, or exploit the production instance |
| Include | Affected endpoint, source file and line, what an attacker achieves, and a proof-of-concept request |
| Acknowledgement | 5 business days |
| Status update | 14 days |
| Fix, critical | 30 days |
| Fix, other | 90 days |
| Embargo | 90 days from the initial report |
| Credit | Given in the fix commit and changelog unless anonymity is requested |

### In scope

- Authentication or authorization bypass on any route, including the legacy aliases
  `/push`, `/pull_request`, `/job`, and `/pipeline`.
- Causing the bot to comment, create or update Check Runs, delete branches, or merge
  pull requests without a legitimate triggering event.
- Causing the bot to expose or misuse any credential listed in [Assets](#6-assets).
- Shell injection or code execution on the bot host.
- Credential exposure via logs, process argv, or HTTP responses.
- Server-side request forgery from the bot host.
- Confused-deputy attacks that make the bot act for an attacker using its own credentials.

### Out of scope

- Rocq and Coq kernel soundness.
- GitHub, GitLab, and Heroku platform security, except as consumed by this bot.
- Account compromise of a user who has access to the bot's repositories.
- GitLab CI variable exposure on mirrored pull request branches, which is ACCEPTED-1 and
  an operator responsibility.
- Timing attacks requiring an impractical request volume against the running server.
- Issues in `rocq-community/run-coq-bug-minimizer` that are independent of this code.

### Known and already documented

Reports on the following are still welcome, especially with an exploitation path not
described here, but they are already recorded in this document: CRITICAL-1 through
CRITICAL-4, HIGH-1 through HIGH-6, and the shared-secret defaults in HIGH-3 and
MEDIUM-8.
