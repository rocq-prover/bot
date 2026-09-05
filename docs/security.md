# 🔐 Rocq Bot Security Audit

> Single source of truth for the security posture of this repository: threat model,
> confirmed findings with cited source evidence, attack chains, remediation plan, and
> disclosure policy. Generated per the methodology in `docs/master_prompt.md`.

> [!IMPORTANT]
> **Audit basis:** this document reflects the verified state of the current source tree.
> Every finding cites `file:line` and quotes the deciding expression. Controls that are
> not yet implemented are not presented as implemented.

| Field | Value |
|---|---|
| Target | Rocq Prover Bot (`coqbot` / `rocqbot`) |
| Scope | `src/`, `bot-components/`, `*.sh`, `Dockerfile`, `release.Dockerfile`, `*.toml`, GitHub Actions workflows |
| Revision | `d0d80c0` |
| Branch | `security_audit` |
| Audit date | 2026-09-05 |
| Method | Manual source review with input-to-sink data-flow tracing; local reproduction of the shell-injection mechanics in `/bin/sh` |
| Core question | Can an untrusted person cause a privileged operation they are not authorized to cause? |

### How to read this document

1. Severity uses the four-tier model from `master_prompt.md`: 🔴 P0, 🟠 P1, 🟡 P2, 🟢 P3,
   plus informational and accepted items.
2. Finding IDs (P0-01, P1-02, ...) are stable labels for cross-reference and tracking.
3. "Reachable by" names the weakest attacker position (P1..P6, see
   [Attacker positions](#-attacker-positions)) that suffices.
4. Status labels: `CONFIRMED`, `LIKELY`, `POTENTIAL`, `NOT-REPRODUCED`, `FALSE-POSITIVE`.

### Severity key

| Marker | Tier | Meaning |
|---|---|---|
| ![Critical](https://img.shields.io/badge/P0-c0392b) | 🔴 P0 | Unauthenticated RCE, auth/authz bypass, credential theft, or abuse of privileged credentials against an attacker-chosen target |
| ![High](https://img.shields.io/badge/P1-e67e22) | 🟠 P1 | Privileged effect reachable with one precondition |
| ![Medium](https://img.shields.io/badge/P2-f39c12) | 🟡 P2 | Bounded effect: needs an account/config, or has cost/integrity/leak impact |
| ![Low](https://img.shields.io/badge/P3-3498db) | 🟢 P3 | Hardening gap or latent defect with no currently reachable exploit path |
| ![Info](https://img.shields.io/badge/Info-7f8c8d) | ⚪ Info | Operational or hygiene observation, not a vulnerability |
| ![Accepted](https://img.shields.io/badge/Accepted-27ae60) | ✅ Accepted | Documented design risk; residual control is intentional |

---

## 🚦 Executive dashboard

The bot is an internet-facing HTTP server holding a GitHub App RSA private key, a GitHub
PAT, and GitLab API tokens. Three of its routes (the minimizer callbacks) have **no
authentication at all**, and two more **fail open** when their auth header is absent
(GitHub without `installation.id`, GitLab without the token). From those openings an
anonymous client reaches **host command execution**, an **attacker-controlled Docker
image / workflow injection in trusted CI**, and use of the bot's **cross-org GitHub App
privileges** (confused deputy).

| Category | Status |
|---|---|
| 🔐 Authentication | 🔴 At risk |
| 👤 Authorization | 🟠 Needs work |
| 💻 Host execution | 🔴 At risk |
| ⚙️ CI security | 🔴 At risk |
| 🐳 Docker trust | 🔴 At risk |
| 🎯 Resource binding | 🔴 At risk |
| 🔑 Credential handling | 🟠 Needs work |
| 🌐 SSRF / network | 🟡 Moderate |
| 🧨 DoS / hardening | 🟡 Moderate |

| Tier | Count | IDs |
|---|---:|---|
| 🔴 P0 | 4 | P0-01 .. P0-04 |
| 🟠 P1 | 6 | P1-01 .. P1-06 |
| 🟡 P2 | 10 | P2-01 .. P2-10 |
| 🟢 P3 | 9 | P3-01 .. P3-09 |
| ⚪ Info | 8 | INFO-1 .. INFO-8 |
| ✅ Accepted | 3 | ACCEPTED-1 .. ACCEPTED-3 |

### Overall verdict

# 🟠 NOT SAFE UNTIL P0 FIXES ARE APPLIED

### Security score: 2 / 10

- **Why:** an anonymous HTTP client reaches host RCE, trusted-CI code execution, and the
  bot's GitHub App privileges through routes that perform no authentication.
- **What prevents a higher score:** four independent P0 conditions, all reachable by 🌐
  anonymous attackers, plus systemic exposure of the GitHub PAT and a second anonymous
  RCE path (P1-05/P1-06 chained through P0-03).
- **What must change:** authenticate the minimizer callbacks against server-side job
  state, make both webhook verifiers fail closed, and replace the shell-string git
  invocations with argv calls that keep the PAT off the command line.

---

## ✅ Correct controls - do not regress

These are implemented correctly and must be preserved by any fix:

- Constant-time secret comparison via `Eqaf.equal` for the GitHub signature
  (`GitHub_subscriptions.ml:259`) and the GitLab token (`GitLab_subscriptions.ml:116`).
- Fail-closed rejection of unsigned check-run re-requests (`src/webhooks/github.ml:363`).
- `get_team_membership` authorization on the `merge now`, `bench`, and `run CI` commands
  (`GitHub_automation.ml:97`, `bench.ml:292`, `pr_sync.ml:171`); each treats `Error` as
  denial (fails closed).
- Stripping the `Authorization` header on outbound redirects
  (`HTTP_utils.ml:54`), preventing credential forwarding to redirect targets.
- Argv-based, PAT-masked minimizer git calls via `Filename.quote_command` in
  `src/utils/coq.ml:12,24,55`.
- The email-origin rejection in `merge now` (`GitHub_automation.ml`), an authenticity
  control.

---

## 📊 Vulnerability summary

| ID | Tier | Status | Vulnerability | Attacker | Impact |
|---|---|---|---|---|---|
| P0-01 | 🔴 | `CONFIRMED` | Minimizer callbacks have no authentication | 🌐 P1 | 🔑 Bot privileges; enables P0-02/P0-04 |
| P0-02 | 🔴 | `CONFIRMED` | Host RCE via unbalanced-quote shell injection (branch delete) | 🌐 P1 | 💻 Host command execution |
| P0-03 | 🔴 | `CONFIRMED` | GitHub webhook signature skipped without `installation.id` | 🌐 P1 | 🔑 Forge any GitHub event |
| P0-04 | 🔴 | `CONFIRMED` | Unauth resume writes attacker-chosen Docker image / workflow | 🌐 P1 | ⚙️ Code execution with CI secrets |
| P1-01 | 🟠 | `CONFIRMED` | GitLab webhook accepted without a token (`signed` ignored) | 🌐 P1 | ⚙️ Forge job/pipeline events |
| P1-02 | 🟠 | `CONFIRMED` | Unmapped GitLab path used directly as GitHub `owner/repo` | 🌐 P1+P1-01 | 🎯 Confused deputy on any repo |
| P1-03 | 🟠 | `CONFIRMED` | GitLab and schedule secrets default to the GitHub secret | 🔑 P6 | 🔑 One leak forges many channels |
| P1-04 | 🟠 | `CONFIRMED` | Tokens printed in logs, git URLs, and process argv | 🔑 P5 | 🔑 Credential disclosure |
| P1-05 | 🟠 | `CONFIRMED` | `git_fetch`/`git_push` interpolate remote URL unquoted | 🌐 P1+P0-03 | 💻 Host command execution |
| P1-06 | 🟠 | `CONFIRMED` | `git_test_modified` interpolates commit SHAs unquoted | 🌐 P1+P0-03 | 💻 Host command execution |
| P2-01 | 🟡 | `CONFIRMED` | Minimize/CI-minimize/resume commands have no authorization | 👤 P2 | ⚙️ Unauthorized minimizer CI run |
| P2-02 | 🟡 | `CONFIRMED` | Check re-run trusts `external_id` -> GitLab retry oracle | 👤 P2 | GitLab retry on any reachable path |
| P2-03 | 🟡 | `CONFIRMED` | Caller-supplied URLs fetched with no allowlist (SSRF) | 🌐 P1 | 🌐 Arbitrary outbound fetch |
| P2-04 | 🟡 | `CONFIRMED` | GitLab pipeline variables copied into public GitHub Checks | 🌐 P1-01 | 🔑 Secret/Markdown leak |
| P2-05 | 🟡 | `CONFIRMED` | Default-branch `coqbot.toml` retargets the GitLab push | 👤 P2 | 🎯 Token to attacker host |
| P2-06 | 🟡 | `CONFIRMED` | No body-size limit, no replay store, quadratic regex | 🌐 P1 | 🧨 Availability |
| P2-07 | 🟡 | `CONFIRMED` | One GitLab webhook secret shared by all mapped projects | 🛠️ P4 | 🔑 Cross-project forgery |
| P2-08 | 🟡 | `CONFIRMED` | CI-config gate checks the PR author, not the pusher | 👤 P2 | 👤 Authorization bypass |
| P2-09 | 🟡 | `CONFIRMED` | Status JSON by concatenation; commit ref unvalidated in path | 🌐 P1-01 | Injection / path steering |
| P2-10 | 🟡 | `CONFIRMED` | Unauthenticated routes drive installation-token minting | 🌐 P1 | 🧨 API-quota exhaustion |
| P3-01 | 🟢 | `CONFIRMED` | HMAC uses the SHA-1 header only | 🌐 P1 | Hardening |
| P3-02 | 🟢 | `CONFIRMED` | Stale-PR secret comparison not constant-time | 🔑 P6 | Timing |
| P3-03 | 🟢 | `CONFIRMED` | GraphQL node IDs are unvalidated opaque strings | 🌐 P1+P0-01 | Enables impersonation |
| P3-04 | 🟢 | `CONFIRMED` | Token-backed job traces published to GitHub | 🌐 P1-01 | Info leak |
| P3-05 | 🟢 | `CONFIRMED` | JWT `iat` has no clock-skew margin | n/a | Availability (fails closed) |
| P3-06 | 🟢 | `POTENTIAL` | `play_job` builds JSON by concatenation (latent) | none today | Latent injection |
| P3-07 | 🟢 | `CONFIRMED` | `get_build_trace` ignores the HTTP status code | 🌐 P1-01 | Info leak / oracle |
| P3-08 | 🟢 | `CONFIRMED` | Attacker input raises uncaught exceptions in request path | 🌐 P1-01 | Availability |
| P3-09 | 🟢 | `CONFIRMED` | Bench authorization decided after the API work it guards | 👤 P2 | Ordering / message leak |

A maintainer should be able to understand the situation from this table alone.

---

## 🗺️ Attack surface

| Surface | Public? | Authentication | Privilege | Main risk |
|---|---:|---|---|---|
| GitHub webhook (`/github`, `/push`, `/pull_request`) | Yes | HMAC-SHA1, **fails open without `installation.id`** | High | 🔐 P0-03 |
| GitLab webhook (`/gitlab`, `/job`, `/pipeline`) | Yes | Token, **result ignored by caller** | High | 🔐 P1-01 |
| `/coq-bug-minimizer` | Yes | **None** | High | 💻 P0-01, P0-02 |
| `/ci-minimization` | Yes | **None** | High | ⚙️ P0-01 |
| `/resume-ci-minimization` | Yes | **None** | High | 🐳 P0-01, P0-04 |
| `/check-stale-pr` | Yes | Body secret (non-constant-time) | Medium | 🔑 P3-02 |
| Git commands | Indirect | Depends on caller | High | 💻 P0-02, P1-05, P1-06 |
| Docker / minimizer CI | Indirect | Depends on caller | High | 🐳 P0-04 |
| Outbound HTTP | Indirect | n/a | Medium | 🌐 P2-03 |

### Attacker positions

| ID | Position | Capability without any privilege |
|---|---|---|
| 🌐 P1 | Internet client | POST arbitrary bodies to any route |
| 👤 P2 | GitHub commenter | Comment on a PR/issue in an installed repo, producing a legitimately signed event |
| 🔀 P3 | Pull request author | Supply branch content the bot merges and mirrors to GitLab |
| 🛠️ P4 | GitLab project maintainer | Read the shared GitLab webhook secret from their own project settings |
| 💻 P5 | Log or process reader | Read dyno stdout, a log aggregator, or `ps` output on the bot host |
| 🔑 P6 | Holder of one leaked secret | Forge events on every channel that shares that secret value |

---

## 🧱 Trust boundaries

```mermaid
flowchart TB
    net["🌐 Internet / untrusted"]

    gh["GitHub webhook: HMAC ❌ fails open (P0-03)"]
    gl["GitLab webhook: token ❌ result ignored (P1-01)"]
    mz["Minimizer callbacks ❌ no auth (P0-01)"]
    sc["Scheduler: shared secret ⚠️"]

    bot["Rocq Bot: auth / authz / resource map"]

    shell["Git / shell on host 💻"]
    ci["Minimizer CI + Docker ⚙️🐳"]
    ghapi["GitHub App tokens (cross-org) 🔑"]
    glapi["GitLab tokens 🔑"]

    net --> gh --> bot
    net --> gl --> bot
    net --> mz --> bot
    net --> sc --> bot
    bot --> shell
    bot --> ci
    bot --> ghapi
    bot --> glapi

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037
    classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class net start
    class gh,gl,mz,sc question
    class bot transport
    class shell,ci shared
    class ghapi,glapi domain
```

Every boundary between the internet and the bot is broken or weak (❌/⚠️), and the
privileged sinks behind them are fully exposed.

### Authentication state by route

```mermaid
flowchart TD
  REQ["POST body"] --> P{"path"}

  P --> |"/github /push /pull_request"| GHJ{"installation.id parses?"}
  GHJ --> |"yes"| SIG{"X-Hub-Signature valid?"}
  SIG --> |"yes"| OKS["ACCEPT signed"]
  SIG --> |"no"| REJ["REJECT 401"]
  GHJ --> |"no - exception swallowed"| OPEN1["ACCEPT UNSIGNED (P0-03)"]

  P --> |"/gitlab /job /pipeline"| GLH{"X-Gitlab-Token present?"}
  GLH --> |"yes"| GLC{"matches secret?"}
  GLC --> |"yes"| OKG["ACCEPT signed=true"]
  GLC --> |"no"| REJ
  GLH --> |"no"| OPEN2["ACCEPT signed=false, flag ignored (P1-01)"]

  P --> |"minimizer routes"| OPEN3["ACCEPT unconditionally (P0-01, P0-04)"]

  P --> |"/check-stale-pr"| SEC{"body secret == schedule secret?"}
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

## 💥 Most dangerous attack paths

### 🔴 Chain 1 - Anonymous -> host RCE (P0-01 + P0-02)

```mermaid
flowchart TB
    a["🌐 Anonymous client"]
    p["POST /coq-bug-minimizer (no auth)"]
    body["body line 1 -> branch_name, repo_name"]
    cmd["git push ... --delete '%s  (quote never closed)"]
    sh["Git_utils.execute_cmd -> Lwt_process.shell"]
    rce["💥 Host command execution"]

    a --> p --> body --> cmd --> sh --> rce

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
    classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class a start
    class p transport
    class body,cmd question
    class sh shared
    class rce domain
```

### 🔴 Chain 2 - Anonymous -> attacker image in trusted CI (P0-01 + P0-04)

```mermaid
flowchart TB
    a["🌐 Anonymous client"]
    p["POST /resume-ci-minimization (no auth)"]
    img["message line 1 -> docker_image"]
    sedn["run_ci_minimization.sh: sed splice into .github/workflows/main.yml"]
    push["git push to rocq-community/run-coq-bug-minimizer"]
    exec["⚙️ Workflow runs attacker image / injected YAML with CI secrets"]

    a --> p --> img --> sedn --> push --> exec

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
    classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class a start
    class p transport
    class img,sedn question
    class push shared
    class exec domain
```

### 🔴 Chain 3 - Anonymous -> second host RCE via forged webhook (P0-03 + P1-05/P1-06)

```mermaid
flowchart TB
    a["🌐 Anonymous client"]
    w["Webhook JSON with no installation field"]
    bypass["Signature check skipped (P0-03)"]
    ev["PullRequestUpdated: attacker repo_url / SHA"]
    sink["git_fetch / git_test_modified via /bin/sh (P1-05, P1-06)"]
    rce["💥 Host command execution"]

    a --> w --> bypass --> ev --> sink --> rce

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
    classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class a start
    class w transport
    class bypass,ev question
    class sink shared
    class rce domain
```

### 🔴 Chain 4 - Anonymous -> cross-org GitHub App abuse (P0-01)

An attacker chooses `owner` in the callback body; `action_as_github_app ~owner` mints an
installation token for that org and posts an attacker-supplied message to an
attacker-supplied node id - the bot acts as a confused deputy across every org where it
is installed.

### 🟠 Chain 5 - Tokenless GitLab -> fake CI verdicts (P1-01 + P1-02)

A tokenless Job/Pipeline event whose `repository.homepage` names any repo is accepted
(P1-01), and the unmapped path falls back to that raw `owner/repo` (P1-02), so the bot
mints a real installation token and writes Checks (including a false success) on a repo
the operator never configured.

---

## 🧩 Root-cause map

```mermaid
flowchart TB
    root["Security root causes"]

    auth["🔐 Missing / fail-open authentication"]
    shell["💻 Unsafe shell command construction"]
    citrust["⚙️ Untrusted input becomes trusted CI"]
    bind["🎯 Credential bound to caller-supplied field"]
    hard["🧨 Missing limits + encoding + hygiene"]

    root --> auth
    root --> shell
    root --> citrust
    root --> bind
    root --> hard

    auth --> a1["P0-01 minimizer callbacks"]
    auth --> a2["P0-03 GitHub no installation.id"]
    auth --> a3["P1-01 GitLab signed ignored"]
    auth --> a4["P2-01 minimize authz, P2-08 pusher"]

    shell --> s1["P0-02 branch delete RCE"]
    shell --> s2["P1-04 PAT in command + log"]
    shell --> s3["P1-05 repo_url, P1-06 SHA"]

    citrust --> c1["P0-04 docker_image + sed splice"]

    bind --> b1["P1-02 unmapped path"]
    bind --> b2["P2-02 external_id, P2-05 coqbot.toml"]

    hard --> h1["P2-03 SSRF, P2-06 DoS"]
    hard --> h2["P1-03/P2-07 shared secrets"]
    hard --> h3["P2-09 encoding, P3-* hygiene"]

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class root start
    class auth,shell,citrust,bind,hard shared
    class a1,a2,a3,a4,s1,s2,s3,c1,b1,b2,h1,h2,h3 domain
```

Two changes remove most of the risk: authenticate the callbacks/webhooks fail-closed
(the 🔐 branch) and replace shell strings with argv (the 💻 branch).

---

## 🔴 P0 findings

## 🔴 P0-01 - Minimizer callbacks have no authentication

> **Status:** `CONFIRMED` · **Tier:** 🔴 P0 · **Attacker:** 🌐 P1 · **CWE-306**
>
> **Affected:** `src/bot.ml:60`, `src/webhooks/minimizer.ml:7`, `src/ci/minimization.ml:1376`

### 💥 Impact

The three minimizer endpoints are dispatched with no secret, HMAC, or job lookup. Any
anonymous client can drive every action reachable from them: posting comments as the
GitHub App into any org where the bot is installed (confused deputy), the branch-delete
command that yields host RCE (P0-02), and CI resumption with an attacker-chosen Docker
image (P0-04). This callback is the root enabler for the worst chains in this report.

### 🎯 Attack path

```mermaid
flowchart TB
    a["🌐 Anonymous client"]
    p["POST /coq-bug-minimizer | /ci-minimization | /resume-ci-minimization"]
    h["handle_minimizer_webhook (no ~secret parameter)"]
    act["coq_bug_minimizer_results_action / resume action"]
    sinks["post_comment as App · branch delete · CI resume"]

    a --> p --> h --> act --> sinks

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class a start
    class p transport
    class h,act shared
    class sinks domain
```

### 🔬 Evidence

`src/bot.ml:60` routes the three paths straight to the handler with no secret:

```ocaml
| "/coq-bug-minimizer" | "/ci-minimization" | "/resume-ci-minimization" ->
    Minimizer.handle_minimizer_webhook ~bot_info ~key ~app_id ~endpoint:path ~body
```

`coq_bug_minimizer_results_action` splits the first body line into space-separated fields
and trusts every one (`src/ci/minimization.ml:1380`):

```ocaml
match Str.split (Str.regexp " ") stamp with
| [id; author; repo_name; branch_name; owner; _repo; _ (*pr_number*)]
| [id; author; repo_name; branch_name; owner; _repo] -> ...
```

| Stamp field | Attacker controls | Effect |
|---|---|---|
| `owner` | Any org | `action_as_github_app ~owner` mints a real org-scoped token (`GitHub_installations.ml:52`) |
| `id` | Any node ID | Bot posts a comment on that thread as the GitHub App |
| `repo_name` | Any `owner/repo` | PAT-authenticated `git push --delete` against it |
| `branch_name` | Any string | Branch deleted, plus shell injection per P0-02 |

### 🧩 Root cause

The endpoints were designed for a trusted GitHub Actions workflow to call back, but
nothing binds the caller to that workflow or to a bot-created job. No shared secret, no
server-side job state.

### 🛠️ Fix

Mint a random opaque job id when the bot starts a minimization, store
`{job_id -> owner, repo, branch, thread, ...}` server-side, and require the callback to
present the `job_id` plus a callback secret (compared with `Eqaf.equal`). Reject unknown
ids. Derive `owner`, `repo`, and `branch_name` from stored state, never from the body.

### 🧪 Regression test

Callback with an unknown job id / missing secret returns 401; a valid stored id succeeds.

### ⚠️ Residual risk

The callback secret becomes a credential to protect; scope it to these endpoints
(see P1-03) and rotate on leak.

---

## 🔴 P0-02 - Host RCE via unbalanced-quote shell injection

> **Status:** `CONFIRMED` · **Tier:** 🔴 P0 · **Attacker:** 🌐 P1 (via P0-01) · **CWE-78**
>
> **Affected:** `src/ci/minimization.ml:1393`, `bot-components/utils/Git_utils.ml:20`

### 💥 Impact

After posting the callback comment, the bot deletes the minimizer branch with a git
command built by string interpolation. The branch value is placed after a single quote
that is never closed, and both `repo_name` and `branch_name` come from the
unauthenticated callback body. A crafted value ends the intended argument and starts a
second shell command - arbitrary code execution on the bot host, which holds the App
key, the PAT, and the GitLab tokens.

### 🎯 Attack path

```mermaid
flowchart TB
    a["🌐 Anonymous client"]
    body["stamp: id author repo_name branch_name owner ..."]
    fmt["git push https://.../%s.git --delete '%s  (unbalanced quote)"]
    sh["execute_cmd -> Lwt_process.shell (/bin/sh -c)"]
    rce["💥 Arbitrary command on bot host"]

    a --> body --> fmt --> sh --> rce

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class a start
    class body,fmt question
    class sh shared
    class rce domain
```

### 🔬 Evidence

`src/ci/minimization.ml:1393`:

```ocaml
Git_utils.execute_cmd
  (f "git push https://%s:%s@github.com/%s.git --delete '%s"
     bot_info.github_name
     (Bot_info.github_pat bot_info)
     repo_name branch_name )
```

The string is executed through `/bin/sh` (`bot-components/utils/Git_utils.ml:20`):

```ocaml
Lwt_io.printf "Executing command: %s\n" command
>>= fun () ->
let process = Lwt_process.open_process_full (Lwt_process.shell command) in
```

Because `Str.split (Str.regexp " ")` forbids spaces in `branch_name`, the payload must be
space-free and balance the quote; `${IFS}` supplies spaces. Reproduced against `sh` with
`git push` replaced by `echo`:

| `branch_name` | Result |
|---|---|
| `run-coq-bug-minimizer-123` | `Unterminated quoted string`, exit 2 (the benign path is already broken) |
| `';id` | `id` executes, exit 0 |
| `';echo${IFS}RCE-PROOF` | `RCE-PROOF` printed, exit 0 |

Note the second row's corollary: with a normal branch name this command is always a shell
syntax error, so branch cleanup has never worked on this path - it only "works" when an
attacker supplies the balancing quote.

### 🧩 Root cause

Command built by string interpolation instead of an argv API, with a literally
unbalanced quote. Same class as P1-05/P1-06.

### 🛠️ Fix

Do not build a shell string. Use `Lwt_process.exec` with an argument vector (or
`Stdlib.Filename.quote_command`, or `Git_utils.git_delete`, which already quotes via
`Filename.quote`), and pass the credential via a git credential helper or
`http.extraHeader` rather than embedding it in the URL. Pass `~mask:[github_pat]`.

### 🧪 Regression test

Command builder with `branch_name = "';id"` yields a single shell-safe token; benign
branch name exits 0 (proving the unbalanced quote is gone).

### ⚠️ Residual risk

Option injection (a branch starting with `-`) still applies to git; add a `--` separator.

---

## 🔴 P0-03 - GitHub webhook signature skipped when `installation.id` is absent

> **Status:** `CONFIRMED` · **Tier:** 🔴 P0 · **Attacker:** 🌐 P1 · **CWE-347**
>
> **Affected:** `bot-components/github/GitHub_subscriptions.ml:248`, `tests/test_webhook.ml`

### 💥 Impact

Signature verification runs only inside a branch guarded by successfully reading
`installation.id`. If the payload omits `installation` (or it is malformed), the inner
handler catches the exception and returns `Ok None` - no signature checked - and the
event is still dispatched. An anonymous attacker forges any GitHub event (comment, push,
PR) by omitting the field, which also unlocks P1-05/P1-06 (a second RCE path).

### 🎯 Attack path

```mermaid
flowchart TB
    a["🌐 Anonymous client"]
    body["Webhook JSON without installation field"]
    tryb["parse installation.id -> Type_error"]
    catch["with ... -> Ok None (signature not checked)"]
    proc["github_event dispatched"]

    a --> body --> tryb --> catch --> proc

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class a start
    class body,tryb question
    class catch shared
    class proc domain
```

### 🔬 Evidence

`bot-components/github/GitHub_subscriptions.ml:248`:

```ocaml
( try
    let install_id = json |> member "installation" |> member "id" |> to_int in
    (* if there is an install id, the webhook should be signed *)
    match Header.get headers "X-Hub-Signature" with
    | Some signature -> ... if Eqaf.equal signature expected then Ok (Some install_id) ...
    | None -> Error "Webhook comes from a GitHub App, but it is not signed."
  with Yojson.Json_error _ | Type_error _ -> Ok None )
>>= fun install_id -> ... github_event ~event json ...
```

`install_id = None` proceeds to `github_event`. Unsigned events that then act include:

| Unsigned event | Handler | Action |
|---|---|---|
| `PullRequestUpdated` | `github.ml:277` | `git_fetch` on attacker `html_url`, merge, force-push to GitLab (P1-05, P1-06) |
| `PullRequestClosed` | `github.ml:260` | Delete GitLab `pr-N` ref with the GitLab token |
| `IssueOpened` / `CommentCreated` | `github.ml:335,358` | Start a minimizer job / comment as the bot |
| `CheckRunReRequested` | `github.ml:363` | Rejected 401 - correct, fail-closed |
| `merge now`, `run CI`, `bench` | `github.ml:133,159,178` | Blocked (require `Option.is_some install_id`) |

The compensating comment in `tests/test_webhook.ml` is incorrect:
`action_as_github_app` does not need the event's `install_id`; it resolves the
installation from the body's `owner` (`GitHub_installations.ml:52`), so unsigned events
do obtain real tokens.

### 🧩 Root cause

Authentication is entangled with optional metadata parsing, and the exception path
returns a success value (`Ok None`) instead of rejecting. Fails open.

### 🛠️ Fix

Verify the HMAC (prefer `X-Hub-Signature-256`) over the raw body unconditionally, before
parsing any JSON fields. Remove the unsigned/legacy acceptance path or gate it behind an
explicit, default-off flag. Update the test to assert rejection.

### 🧪 Regression test

Event with no `installation` and a missing/invalid signature returns `Error`; valid
`installation.id` with a wrong signature returns `Error`.

### ⚠️ Residual risk

Genuinely unsigned legacy senders stop working; that is the intended outcome - configure
a secret on them.

---

## 🔴 P0-04 - Unauthenticated resume writes an attacker-chosen workflow image

> **Status:** `CONFIRMED` · **Tier:** 🔴 P0 · **Attacker:** 🌐 P1 · **CWE-306 / supply chain**
>
> **Affected:** `src/ci/minimization.ml:1414`, `run_ci_minimization.sh:56,78`

### 💥 Impact

`/resume-ci-minimization` (unauthenticated, P0-01) parses `docker_image` from the body
and passes it to `run_ci_minimization.sh`, which splices it into `.github/workflows/
main.yml` with `sed` and pushes the branch to the trusted
`rocq-community/run-coq-bug-minimizer` repo. The attacker chooses the container image that
runs in that repo's Actions - i.e. runs arbitrary code with whatever secrets and write
scope that workflow holds. Because the value is spliced inside single quotes with `sed`,
an image containing a quote or newline can inject arbitrary workflow YAML.

### 🎯 Attack path

```mermaid
flowchart TB
    a["🌐 Anonymous client"]
    msg["message line 1 -> docker_image (unvalidated)"]
    arg["run_ci_minimization.sh custom_image arg"]
    sedn["sed splice into .github/workflows/main.yml"]
    push["git push to rocq-community/run-coq-bug-minimizer"]
    exec["⚙️🐳 Attacker image / YAML executes with CI secrets"]

    a --> msg --> arg --> sedn --> push --> exec

    classDef start fill:#eceff1,stroke:#546e7a,color:#263238
    classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037
    classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
    classDef shared fill:#e1bee7,stroke:#7b1fa2,color:#4a148c
    classDef domain fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20

    class a start
    class msg question
    class arg transport
    class sedn,push shared
    class exec domain
```

### 🔬 Evidence

`docker_image` is taken from the callback message and forwarded verbatim
(`src/ci/minimization.ml:1424`, `:1447`). The script splices and pushes it:

`run_ci_minimization.sh:56`:

```bash
sed -i 's~^\(\s*\)[^:\s]*custom_image:.*$~\1custom_image: '"'${docker_image}'~" .github/workflows/main.yml
```

`run_ci_minimization.sh:78`:

```bash
git push --set-upstream "https://$bot_name:$token@github.com/$repo_name.git" "$branch_name"
```

The same `sed`-splice pattern applies to `coq_version`/`ocaml_version` in
`coq_bug_minimizer.sh:32-33`.

### 🧩 Root cause

Untrusted callback input becomes trusted CI configuration with no validation and via a
text splice that does not preserve the data/code boundary. The missing security boundary
is the vulnerability, not that minimization runs in CI (see ACCEPTED-3).

### 🛠️ Fix

Derive `docker_image` from server-side job state (P0-01), validate it against an
allowlisted registry plus an immutable digest (`registry/name@sha256:...`), and replace
the `sed` splice with a structured YAML edit so the value cannot alter workflow
structure.

### 🧪 Regression test

`docker_image` with a quote/newline, or a non-allowlisted registry, is rejected /
leaves `main.yml` structurally unchanged.

### ⚠️ Residual risk

Deployment-dependent: impact scales with the secrets and write scope granted to the
`run-coq-bug-minimizer` workflow. Minimize those as defense in depth.

---

## 🟠 P1 findings

## 🟠 P1-01 - GitLab webhooks without a token are processed as valid

> **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **Attacker:** 🌐 P1 · **CWE-306**
>
> **Affected:** `bot-components/gitlab/GitLab_subscriptions.ml:113`, `src/webhooks/gitlab.ml:19,30`

### 💥 Impact

When `X-Gitlab-Token` is absent, the verifier returns `signed = false` inside an `Ok`
value rather than an error, and both dispatch handlers bind the flag as `_` and never
consult it. An anonymous client forges Job and Pipeline events, causing the bot to post
Check Runs (including a false success), retry jobs, read job traces with the bot token,
and trigger auto-minimization on `rocq-prover/rocq`.

### 🔬 Evidence

`bot-components/gitlab/GitLab_subscriptions.ml:113`:

```ocaml
( match Header.get headers "X-Gitlab-Token" with
  | Some header_secret ->
      if Eqaf.equal secret header_secret then return true
      else Error "Webhook password mismatch."
  | None -> return false )
>>= fun signed ->
```

`src/webhooks/gitlab.ml:19` binds and discards `signed`:
`| Ok (_, JobEvent ({common_info= {http_repo_url}} as job_info)) -> ...`. A missing header
is accepted; a present-but-wrong token is rejected - so the check is bypassed by omitting
the header.

### 🧩 Root cause

Authentication returns a Boolean the caller can ignore, and the "missing credential" case
maps to `false`/continue instead of reject.

### 🛠️ Fix

Return `Error` when the token is missing or wrong, so there is no `signed` flag to forget;
then delete the flag. Keep the `github_repo_of_gitlab_url` mapping as resource binding.

### 🧪 Regression test

Job Hook with no token returns `Error`; wrong token returns `Error`; correct token
processes.

---

## 🟠 P1-02 - Unmapped GitLab path is used directly as a GitHub `owner/repo`

> **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **Attacker:** 🌐 P1 with P1-01 · **CWE-20**
>
> **Affected:** `bot-components/github/GitHub_GitLab_sync.ml:48`

### 💥 Impact

When the GitLab->GitHub mapping lookup misses, the fallback is the raw GitLab path. A
forged Job event whose `repository.homepage` is `https://anything/rocq-prover/rocq` needs
no mapping entry: the bot resolves the target to `rocq-prover/rocq`, mints a real
installation token, and writes Checks there - a confused deputy on any installed repo.

### 🔬 Evidence

`bot-components/github/GitHub_GitLab_sync.ml:48`:

```ocaml
let github_full_name =
  match Hashtbl.find gitlab_mapping full_name_with_domain with
  | Some value -> value
  | None ->
      Stdio.printf "Warning: No correspondence found for GitLab repository %s.\n" full_name_with_domain ;
      gitlab_repo_full_name
```

### 🧩 Root cause

A lookup miss falls back to attacker-influenced data instead of failing.

### 🛠️ Fix

Return an error when the mapping lookup misses. A repository the operator has not
configured is not one the bot should act on.

### 🧪 Regression test

A Job event for an unmapped repo is rejected rather than acted on.

---

## 🟠 P1-03 - GitLab and schedule secrets default to the GitHub webhook secret

> **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **Attacker:** 🔑 P6 · **CWE-1188**
>
> **Affected:** `src/config/config.ml:70,79`

### 💥 Impact

`gitlab_webhook_secret` and `daily_schedule_secret` both default to
`github_webhook_secret` when unset. The three channels have different exposure (App
admins, GitLab project maintainers, an HTTP body), so sharing one value lets the weakest
holder forge on all three. `README.md:312-313` documents this as intended - a design to
reverse, not a quiet patch.

### 🔬 Evidence

`src/config/config.ml:70`:

```ocaml
let gitlab_webhook_secret toml_data =
  match subkey_value toml_data "gitlab" "webhook_secret" with
  | None -> Option.value ~default:(github_webhook_secret toml_data) (Sys.getenv "GITLAB_WEBHOOK_SECRET")
  | Some secret -> secret
(* daily_schedule_secret has the same default at :79 *)
```

### 🛠️ Fix

Require all three secrets explicitly and fail startup when any is missing. Silent
credential reuse should never be a default.

### 🧪 Regression test

Startup with `GITLAB_WEBHOOK_SECRET` unset (and no config value) fails.

---

## 🟠 P1-04 - Tokens printed in command logs, git URLs, and process argv

> **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **Attacker:** 💻 P5 · **CWE-532**
>
> **Affected:** `bot-components/utils/Git_utils.ml:19`, `src/ci/minimization.ml:1394`, `coq_bug_minimizer.sh:39`, `run_ci_minimization.sh:78`

### 💥 Impact

`execute_cmd` logs the full command with `Lwt_io.printf "Executing command: %s\n"` before
running it; `mask` is consumed only by `report_status` on a non-zero exit, so the initial
print is never masked. Credentials placed in command strings (the PAT in the P0-02 push
URL, the GitLab token in `https://oauth2:TOKEN@host` mirror pushes) are logged in
cleartext and appear in process argv.

### 🔬 Evidence

`bot-components/utils/Git_utils.ml:19`:

```ocaml
let execute_cmd ?(mask = []) command =
  Lwt_io.printf "Executing command: %s\n" command
  >>= fun () ->
  let process = Lwt_process.open_process_full (Lwt_process.shell command) in
```

| Call site | Credential | Masking |
|---|---|---|
| `src/ci/minimization.ml:1394` | GitHub PAT in push URL | No `~mask` at all |
| `src/utils/coq.ml:24,55` | GitHub PAT as argv | `~mask` passed, but the print at :20 precedes it |
| `GitHub_GitLab_sync.ml:42` | GitLab token in `oauth2:TOKEN@host` | No mask; every mirror/update |
| `coq_bug_minimizer.sh:39`, `run_ci_minimization.sh:78` | PAT in child argv | Visible in `ps` |

### 🛠️ Fix

Apply the mask inside `execute_cmd` before the print, and remove credentials from command
lines entirely via a git credential helper. Redaction is a backstop; keeping the secret
off the command line is the control.

### 🧪 Regression test

`execute_cmd ~mask:[secret]` never emits the secret on stdout, including on success.

---

## 🟠 P1-05 - `git_fetch` and `git_push` interpolate remote URLs into a shell unquoted

> **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **Attacker:** 🌐 P1 with P0-03; 👤 with P2-05 · **CWE-78**
>
> **Affected:** `bot-components/utils/Git_utils.ml:44,50`

### 💥 Impact

Ref names are quoted with `Filename.quote`, but `repo_url` and `options` are not. `repo_url`
derives from `repo.html_url` in the PR payload (`GitHub_subscriptions.ml:40`); under P0-03
an attacker controls it, giving a second host-RCE path independent of the minimizer
callback. It is also reachable without P0-03 via P2-05 (`coqbot.toml` retargeting).

### 🔬 Evidence

`bot-components/utils/Git_utils.ml:44`:

```ocaml
let git_fetch ?(force = true) remote_ref local_branch_name =
  f "git fetch --quiet -fu %s %s%s:%s" remote_ref.repo_url
    (if force then "+" else "")
    (Stdlib.Filename.quote remote_ref.name)
    (Stdlib.Filename.quote local_branch_name)

let git_push ?(force = true) ?(options = "") ~remote_ref ~local_ref () =
  f "git push %s %s%s:%s %s" remote_ref.repo_url ...
```

### 🛠️ Fix

Quote `repo_url`, and preferably move both to an argument vector so quoting is structural.
Add `--` before user refs to block option injection.

### 🧪 Regression test

`repo_url` containing `;`, `$()`, and a space survives as a single argument.

---

## 🟠 P1-06 - `git_test_modified` interpolates commit SHAs into a shell unquoted

> **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **Attacker:** 🌐 P1 with P0-03 · **CWE-78**
>
> **Affected:** `bot-components/utils/Git_utils.ml:80`, `src/actions/pr_sync.ml:46,85`

### 💥 Impact

`Lwt_unix.system` runs the string through `/bin/sh`, and none of `base`, `head`, `pattern`
is quoted. Call sites pass raw commit SHAs from the webhook payload with no format check;
under P0-03 the attacker controls both, with no quote-balancing constraint and no space
restriction - a second, unconstrained path to host command execution.

### 🔬 Evidence

`bot-components/utils/Git_utils.ml:80`:

```ocaml
let command = f {|git diff %s...%s --name-only | grep "%s"|} base head pattern in
Lwt_unix.system command
```

`base.sha`/`head.sha` come from `commit_info_of_json` (`GitHub_subscriptions.ml:38-42`)
with no validation.

### 🛠️ Fix

Quote all three arguments, or replace the `git diff | grep` pipeline with
`git diff --name-only` via argv plus an OCaml-side pattern match. Validate SHAs against
`[0-9a-f]{7,40}` at the parsing boundary.

### 🧪 Regression test

`base = "a;id"` survives as a single argument; no extra process spawns.

---

## 🟡 P2 findings

## 🟡 P2-01 - Minimize, CI-minimize, and resume commands have no authorization

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 👤 P2 (🌐 via P0-03) · **CWE-862**
>
> **Affected:** `src/webhooks/github.ml:77,98,111`

`merge now`, `bench`, and `run CI` correctly gate on `get_team_membership`; the minimize
family does not. `handle_comment_created` runs it for any commenter, pushing an
attacker-provided script/target to `run-coq-bug-minimizer` and executing it in that repo's
Actions.

`src/webhooks/github.ml:77`:

```ocaml
match minimize_text_of_body body with
| Some (options, script) ->
    (fun () -> init_git_bare_repository ~bot_info >>= fun () ->
      Bot_components.Github_installations.action_as_github_app ~bot_info ~key
        ~app_id ~owner:comment_info.issue.issue.owner (fun ~bot_info ->
          Minimization.run_coq_minimizer ~bot_info ~script ... ) )
```

| Command | Team check | `install_id` required |
|---|---|---|
| `merge now` | `@rocq-prover/pushers` | Yes |
| `run CI` / `bench` | `@rocq-prover/contributors` | Yes |
| `minimize` / `ci minimize` / `resume` | None | No |

**Fix.** Apply the same `get_team_membership` gate used by `run CI`. Execution in Actions
is intentional (ACCEPTED-3); the gap is that nothing gates who may start it.
**Test.** A `minimize` comment from a non-member is declined.

---

## 🟡 P2-02 - Check re-run trusts `external_id` and retries GitLab as the bot

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 👤 P2 (signed re-request) · **CWE-20**
>
> **Affected:** `bot-components/utils/Minimize_parser.ml:179`, `bot-components/gitlab/GitLab_mutations.ml:5`

Unsigned re-runs are rejected (correct). Signed re-runs parse `external_id` and place
`url_part` verbatim into the API path. `gitlab_domain` is constrained to configured
instances; `url_part` is not bound to a bot-created job, giving a `POST .../retry` oracle
for any path the token can reach.

`bot-components/gitlab/GitLab_mutations.ml:5`:

```ocaml
let generic_retry ~bot_info ~gitlab_domain ~url_part =
  let uri = f "https://%s/api/v4/%s/retry" gitlab_domain url_part |> Uri.of_string in ...
```

**Fix.** Require `external_id` to match `projects/<int>/(jobs|pipelines)/<int>`; drop the
legacy single-field form.
**Test.** `parse_check_run_external_id "projects/1/jobs/2/../../../groups/1"` returns `None`.

---

## 🟡 P2-03 - Caller-supplied URLs are fetched with no allowlist (SSRF)

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 🌐 P1 and 👤 P2 · **CWE-918**
>
> **Affected:** `src/ci/minimization.ml:256`, `bot-components/utils/HTTP_utils.ml:168,206`

`download_cps` follows redirects recursively with no allowlist on scheme, host, port, or
address range, and no redirect cap. Reachable unauthenticated via `/resume-ci-minimization`
(`failing_urls`/`passing_urls`) and via a signed `@bot minimize [desc](url)`. Impact is
bounded: these paths send no `Authorization` header and `client_get` strips headers on
redirect (`HTTP_utils.ml:54`).

**Fix.** Allowlist `https` and the artifact hosts actually needed; resolve the host and
reject private, loopback, and link-local addresses before connecting; cap redirects.
**Test.** `fetch` of `http://127.0.0.1/` and `http://169.254.169.254/` is rejected.

---

## 🟡 P2-04 - GitLab pipeline variables are copied into public GitHub Checks

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 🌐 P1 with P1-01 · **CWE-200**
>
> **Affected:** `bot-components/ci/pipeline.ml:9`, `src/ci/job_status.ml:362`

`create_pipeline_summary` renders every `object_attributes.variables` entry into the Check
summary verbatim. Two risks: genuine GitLab variables holding credentials are published,
and under P1-01 an attacker injects arbitrary Markdown into a Check on a repo they do not
control.

`bot-components/ci/pipeline.ml:9`:

```ocaml
let variables =
  List.map pipeline_info.variables ~f:(fun (key, value) -> f "- %s: %s" key value)
  |> String.concat ~sep:"\n"
```

**Fix.** Publish only an explicit allowlist of variable names (e.g. `FULL_CI`,
`SKIP_DOCKER`), the only ones the bot reads.
**Test.** A pipeline event carrying an unlisted variable does not surface it in the Check.

---

## 🟡 P2-05 - Default-branch `coqbot.toml` retargets where the GitLab token pushes

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 👤 P2 as a repo admin · **CWE-20**
>
> **Affected:** `bot-components/github/GitHub_GitLab_sync.ml:84`

Anyone who installs the App on a repo they control, and who is not in `[mappings]`,
chooses `gl_domain` and `gl_repo` via `coqbot.toml`. The bot builds
`https://oauth2:TOKEN@<gl_domain>/<gl_repo>.git` and pushes there - disclosing the GitLab
token to an attacker host, and feeding P1-05 without needing P0-03. The code flags the gap
at `:148` (`TODO: generalize ... with enhanced security`).

**Fix.** Accept a discovered mapping only when `gl_domain` is a configured instance, and
require operator confirmation of new mappings.
**Test.** A `coqbot.toml` naming an unconfigured GitLab domain is rejected.

---

## 🟡 P2-06 - No body-size limit, no replay store, quadratic regexes

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 🌐 P1 · **CWE-400**
>
> **Affected:** `src/bot.ml:46`, `src/ci/minimization.ml:1377,1411`

`src/bot.ml:46` (`Cohttp_lwt.Body.to_string body`) buffers the whole body for every route
before any auth. The bot then runs backtracking `Str` regexes over it
(`"\\([^\n]+\\)\n\\([^\r]*\\)"`), which is quadratic on a large newline-free body and
stalls the single Lwt event loop. `X-GitHub-Delivery` is never read, so signed webhooks
replay freely, and `Lwt.async` side effects are uncapped.

**Fix.** Reject oversized bodies before parsing; authenticate before regexing; record
`X-GitHub-Delivery` in a bounded replay cache; bound in-flight `Lwt.async`.
**Test.** A body above the limit is rejected before any regex runs.

---

## 🟡 P2-07 - One GitLab webhook secret shared by all mapped projects

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 🛠️ P4 · **CWE-1188**
>
> **Affected:** `src/bot.ml:12`

Every mapped GitLab project uses the same secret value, readable by each project's
maintainers (`(* TODO: make webhook secret project-specific *)`). Once P1-01 is closed,
this becomes the primary forgery path: a maintainer of the least-trusted mapped project
can forge events for `coq/coq`.

**Fix.** Key the secret by GitLab project/instance and select it from the payload's
project identity before verification.
**Test.** A project's secret does not verify events for another project.

---

## 🟡 P2-08 - CI configuration gate checks the PR author, not the pusher

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 👤 P2 · **CWE-863**
>
> **Affected:** `src/actions/pr_sync.ml:55`

The gate stops untrusted contributors editing GitLab CI config, but evaluates
`pr_info.issue.user` (the PR author). If a contributors member opens a PR and a non-member
later pushes a commit editing `*gitlab*.yml`, the author check passes and CI runs on the
non-member's change. The `synchronize` payload's `sender.login` (the pusher) is not read.

`src/actions/pr_sync.ml:55`:

```ocaml
(* This is an approximation: we are checking who the PR author is and not who is pushing. *)
GitHub_queries.get_team_membership ~bot_info ~org:"rocq-prover" ~team:"contributors" ~user:pr_info.issue.user )
```

**Fix.** Evaluate membership for the event actor; treat author and actor as distinct.
**Test.** A non-member push editing CI config on a member-authored PR does not run CI.

---

## 🟡 P2-09 - Status JSON by concatenation; commit ref unvalidated in the URL path

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 🌐 P1 with P1-01 · **CWE-116**
>
> **Affected:** `bot-components/github/GitHub_mutations.ml:266`

`send_status_check` assembles the body by concatenation and interpolates `commit` into the
REST path. The JSON half is latent (its only caller derives `context` from an allowlisted
`doc_artifact_jobs`), but `commit` is `job_info.common_info.head_commit` from the GitLab
payload with no format check; under P1-01 an attacker steers the authenticated POST to
another path under `/repos/<owner>/<repo>/`.

`bot-components/github/GitHub_mutations.ml:266`:

```ocaml
let body = {|{"state": "|} ^ state ^ {|","target_url":"|} ^ url ^ ... in
let uri = "https://api.github.com/repos/" ^ repo_full_name ^ "/statuses/" ^ commit |> Uri.of_string
```

**Fix.** Build the body with `Yojson`; validate `commit` against `[0-9a-f]{7,40}` at the
parsing boundary.
**Test.** `send_status_check` with `commit = "abc/../../other"` is rejected.

---

## 🟡 P2-10 - Unauthenticated routes drive installation-token minting

> **Status:** `CONFIRMED` · **Tier:** 🟡 P2 · **Attacker:** 🌐 P1 · **CWE-770**
>
> **Affected:** `bot-components/github/GitHub_installations.ml:52`

Every request naming an uncached owner triggers a signed `GET /app/installations` call and
RSA signing. `owner` is attacker-chosen on the minimizer routes (P0-01) and unsigned
webhooks (P0-03), so a stream of distinct owner names drives unbounded App-level API calls
and asymmetric crypto - exhausting the App's API quota disables all bot functions.

**Fix.** Authenticate before resolving any installation; negatively cache unknown owners
with a short TTL; rate-limit the lookup path.
**Test.** Repeated unknown-owner requests are rate-limited / negatively cached.

---

## 🟢 P3 findings

**P3-01 - HMAC uses the SHA-1 header only** (`CONFIRMED`, CWE-328,
`GitHub_subscriptions.ml:253`). Reads `X-Hub-Signature` (HMAC-SHA1), constant-time via
`Eqaf.equal`. Not forgeable without the key, but if GitHub stops sending SHA-1 the check
falls into the `None` branch, which is not uniformly fail-closed under P0-03. **Fix:**
prefer `X-Hub-Signature-256`, SHA-1 as a transitional fallback.

**P3-02 - Stale-PR secret comparison is not constant-time** (`CONFIRMED`, CWE-208,
`src/webhooks/scheduled.ml:13`). `String.equal secret daily_schedule_secret`
short-circuits; the secret also travels in the body and replay is free. **Fix:**
`Eqaf.equal`, move to a header, add a timestamp window.

**P3-03 - GraphQL node IDs are unvalidated opaque strings** (`CONFIRMED`, CWE-20,
`GitHub_ID.ml`). `of_string` wraps any string with no evidence it names a bot-created node;
the minimizer callbacks do not validate, which is what makes P0-01's impersonation
possible. **Fix:** bind IDs to bot-created state at the callback boundary.

**P3-04 - Token-backed job traces are published to GitHub** (`CONFIRMED`, CWE-200,
`src/ci/job_status.ml:78`). On failure the bot reads `/jobs/:id/trace` with the GitLab
token and embeds an excerpt in the Check; under P1-01 the job ID is attacker-chosen and any
credential in the trace becomes public. **Fix:** scrub secret patterns; restrict trace
reads to authenticated projects.

**P3-05 - JWT `iat` has no clock-skew margin** (`CONFIRMED`, CWE-703,
`GitHub_app.ml:22`). `exp = iat + 550`; forward host clock skew makes token minting fail.
Availability only, fails closed. **Fix:** backdate `iat` by 60 seconds.

**P3-06 - `play_job` builds its JSON body by string concatenation** (`POTENTIAL`, CWE-116,
`GitLab_mutations.ml:39`). Not exploitable today (only caller passes a literal); same class
as P2-09. **Fix:** build with `Yojson`.

**P3-07 - `get_build_trace` ignores the HTTP status code** (`CONFIRMED`, CWE-754,
`GitLab_queries.ml:22`). A 401/403/404 body is returned as though it were the trace and
published on a Check; turns P1-01's forged job IDs into an error-body oracle. **Fix:**
check status, return `Error` on non-200.

**P3-08 - Attacker input raises uncaught exceptions in the request path** (`CONFIRMED`,
CWE-248, `GitHub_GitLab_sync.ml:58`). `github_repo_of_gitlab_project_path` `failwith`s on a
non-two-segment name (reachable via P1-01 + P1-02 in the synchronous scrutinee), and
`Toml.Parser.unsafe` raises on malformed `coqbot.toml`. **Fix:** return `Result` and
respond 400.

**P3-09 - Bench authorization is decided after the API work it guards** (`CONFIRMED`,
CWE-696, `src/utils/bench.ml:245`). The decision is correct and fail-closed and `play_job`
runs only for `Ok true`, but every commenter first causes two GraphQL queries, and the
`Error err` arm is matched before `Ok false`, so an unauthorized commenter with a
summary-parse failure receives internal error text. **Fix:** check membership first and
return early; keep authz messages distinct from operational errors.

---

## ⚪ Info

| ID | Observation | Detail |
|---|---|---|
| INFO-1 | Exception hook prints raw exception text | `src/bot.ml:73-78`; a library exception carrying a token URL is logged. Related to P1-04 |
| INFO-2 | TLS terminated outside the process | `Server.create` (`src/bot.ml:70`) binds plain TCP; normal for Heroku, but a direct public bind would put secrets on the wire |
| INFO-3 | Installation tokens in process memory | `GitHub_installations.ml:8`, ~40 min TTL; reading process memory is equivalent to holding those org tokens until expiry |
| INFO-4 | No secret-rotation runbook | Rotation for the App key, PAT, GitLab tokens, and three webhook secrets is not written down |
| INFO-5 | Live credentials in `.bot-env` | App ID, PAT, webhook secret, RSA key, two GitLab tokens. Mode `0600`, gitignored (`*.bot-env` / `.bot-env`), never committed (`git ls-files` confirms). Rotate anyway |
| INFO-6 | No HTTP method enforcement | `src/bot.ml:39-67` dispatches on path only; every route answers any verb. No auth consequence today, but widens the surface |
| INFO-7 | App private key PEM world-readable | `app-bot-demo.2025-10-31.private-key.pem` is mode `0664`; gitignored via `*.private-key.pem`, never committed. `chmod 600`, move out of the workspace, rotate |
| INFO-8 | No CORS/origin validation | `src/bot.ml:39-67` returns no CORS headers; once auth is added, origin checking prevents browser CSRF |

---

## ✅ Accepted risks

| ID | Risk | Why accepted | Residual control |
|---|---|---|---|
| ACCEPTED-1 | Untrusted PR heads are merged and force-pushed to GitLab as `pr-N` | This is the product (`pr_sync.ml`) | Operator-configured GitLab protected branches/variables (`README.md:47-50`); the bot cannot read those settings |
| ACCEPTED-2 | `@bot merge now` merges on one comment | Deliberate gates: not the author, in assignees, no `needs:*`, has `kind:*`, has a milestone, `APPROVED`, target `master`, not email-originated, member of `@rocq-prover/pushers` (`GitHub_automation.ml:10-108`) | Pusher account compromise is out of scope; keep the email-origin rejection |
| ACCEPTED-3 | The minimizer runs commenter-supplied Coq/shell scripts | Execution is on GitHub Actions in `run-coq-bug-minimizer`, not the bot host | Who may start it is P2-01 and is NOT accepted; host-side execution via P0-02 is NOT accepted |

---

## 🚫 What is not a vulnerability here

| Claim | Assessment |
|---|---|
| Rocq/Coq kernel soundness | Out of scope for this repository |
| GitHub/GitLab/Heroku platform security | Out of scope except where consumed by this bot |
| Account compromise of a user with bot repository access | Out of scope |
| HMAC-SHA1 being collision-weak | Not a forgery path without the key; the real issue is header choice (P3-01) |
| `Eqaf.equal` on the GitHub/GitLab secrets | Correct; constant-time - do not replace with `String.equal` |
| Rejecting a check re-run when `install_id` is absent | Correct; fail-closed - the model the other routes should follow |
| `get_team_membership` returning `Error` | Correct; every caller treats `Error` as denial (fails closed) |
| `Filename.quote` on git ref names | Correct; the gap is the unquoted URL and SHA arguments (P1-05, P1-06) |
| merge/bench/run-CI commands | Correctly authorized via team membership; only the minimize family is not (P2-01) |
| Local secret files (`.bot-env`, PEM) | Gitignored and never committed; hygiene items INFO-5/INFO-7, not a leak |
| Global `Str` match state across requests | No exploitable instance found; every `string_match` is followed by its `matched_group` reads with no intervening `Lwt` bind. Remains fragile |

---

## 📋 Security invariants

| # | Invariant | Status |
|---|---|---|
| I1 | Every privileged public endpoint rejects missing/invalid auth | 🔴 Fail (P0-01, P0-03, P1-01) |
| I2 | Security-check failures fail closed | 🔴 Fail (P0-03, P1-01) |
| I3 | Authentication never substitutes for authorization | 🟠 Partial (P2-01, P2-08; merge/bench/CI pass) |
| I4 | Attacker cannot independently select the credential's resource | 🔴 Fail (P0-01, P1-02, P2-02, P2-05) |
| I5 | No attacker value reaches a shell via interpolation | 🔴 Fail (P0-02, P1-05, P1-06) |
| I6 | Credentials never in URLs/argv/logs/artifacts | 🔴 Fail (P1-04) |
| I7 | Webhook events verified before privileged processing | 🔴 Fail (P0-03, P1-01) |
| I8 | Untrusted input does not become trusted CI config | 🔴 Fail (P0-04) |
| I9 | Untrusted images not run with privileges/secrets without a boundary | 🔴 Fail (P0-04) |
| I10 | Attacker URLs cannot redirect privileged operations | 🟡 Partial (P2-03; auth header stripped on redirect) |
| I11 | Callbacks correspond to server-side jobs | 🔴 Fail (P0-01, P3-03) |
| I12 | Every fixed vulnerability has a regression test | 🟠 To add with fixes |

---

## 🧪 Regression tests to add

Each test should fail against the current tree and pass after the fix.
`tests/test_webhook.ml` currently asserts the P0-03 behaviour as correct and must be
updated, not extended.

| Test | Asserts | Guards |
|---|---|---|
| `receive_github`, no `installation.id`, no signature | Returns `Error` | P0-03 |
| `receive_github`, valid `installation.id`, wrong signature | Returns `Error` | P0-03 |
| `receive_gitlab`, no `X-Gitlab-Token` | Returns `Error` | P1-01 |
| Minimizer route, no shared-secret header | Returns 401 | P0-01, P0-04 |
| Branch delete, benign branch name | Command exits 0 (unbalanced quote gone) | P0-02 |
| Branch delete, `branch_name = "';id"` | One literal argument; no extra process | P0-02 |
| `git_fetch`/`git_push`, `repo_url` with `;`, `$()`, space | Survives as one argument | P1-05 |
| `git_test_modified`, `base = "a;id"` | Survives as one argument | P1-06 |
| `parse_check_run_external_id "projects/1/jobs/2/../../../groups/1"` | Returns `None` | P2-02 |
| Startup with `GITLAB_WEBHOOK_SECRET` unset | Startup fails | P1-03 |
| `execute_cmd ~mask:[secret]` | Secret never on stdout, including on success | P1-04 |
| Attachment fetch of `http://127.0.0.1/`, `http://169.254.169.254/` | Rejected before connecting | P2-03 |
| `send_status_check`, `commit = "abc/../../other"` | Rejected at validation | P2-09 |
| Body above the size limit | Rejected before any regex | P2-06 |

---

## 🛠️ Remediation plan

```mermaid
flowchart LR
  S1["Phase 0 (Stop ship)<br/>Close unauthenticated RCE<br/>and fail-open auth"]
  S2["Phase 1<br/>Secret separation,<br/>authorization, allowlists"]
  S3["Phase 2/3<br/>Abuse resistance,<br/>encoding, hygiene"]
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

### 🔴 Phase 0 - Stop ship (before public disclosure; this document contains a working P0-02 recipe)

| # | Action | Closes | Location |
|---|---|---|---|
| 1 | Replace the branch-delete shell string with an argv call; move the PAT off the URL | P0-02, part of P1-04 | `src/ci/minimization.ml:1394` |
| 2 | Require a shared secret + server-side job state on all three minimizer routes | P0-01, P0-04, part of P2-03/P2-10 | `src/bot.ml:60`, `src/webhooks/minimizer.ml` |
| 3 | Verify `X-Hub-Signature-256` before parsing the body, unconditionally | P0-03, P3-01 | `GitHub_subscriptions.ml:243` |
| 4 | Return `Error` when `X-Gitlab-Token` is absent; delete the `signed` flag | P1-01 | `GitLab_subscriptions.ml:113` |
| 5 | Quote or vectorise `repo_url` in `git_fetch`/`git_push`, and all three args of `git_test_modified` | P1-05, P1-06 | `Git_utils.ml:44,50,80` |
| 6 | Rotate every credential in `.bot-env` and the PEM; `chmod 600` and move the PEM out of the tree | INFO-5, INFO-7 | `.bot-env`, `*.private-key.pem` |

### 🟠 Phase 1 - Privilege boundary (within one sprint)

| # | Action | Closes | Location |
|---|---|---|---|
| 7 | Require all three webhook secrets explicitly; fail startup if any is missing | P1-03 | `src/config/config.ml:70` |
| 8 | Apply `mask` inside `execute_cmd` before the print; adopt a git credential helper | P1-04 | `Git_utils.ml:19` |
| 9 | Error out when the GitLab mapping lookup misses | P1-02 | `GitHub_GitLab_sync.ml:48` |
| 10 | Gate `minimize`/`ci minimize`/`resume` on `@rocq-prover/contributors` | P2-01 | `src/webhooks/github.ml:77,98,111` |
| 11 | Constrain `external_id` to `projects/<int>/(jobs\|pipelines)/<int>`; drop the legacy form | P2-02 | `Minimize_parser.ml:179` |
| 12 | Allowlist the attachment fetch (https, host allowlist, reject private/link-local, cap redirects) | P2-03 | `minimization.ml:256`, `HTTP_utils.ml:168` |

### 🟡 Phase 2/3 - Hardening

| # | Action | Closes | Location |
|---|---|---|---|
| 13 | Body-size limit + auth-before-regex; `X-GitHub-Delivery` replay cache; cap async | P2-06 | `src/bot.ml:39-67` |
| 14 | Negatively cache unknown owners; rate-limit installation lookup | P2-10 | `GitHub_installations.ml:52` |
| 15 | Per-project GitLab webhook secrets | P2-07 | `src/bot.ml:12` |
| 16 | Allowlist pipeline variable names in Check summaries | P2-04 | `pipeline.ml:9` |
| 17 | Build all JSON with `Yojson`; validate `commit` against `[0-9a-f]{7,40}` | P2-09, P3-06 | `GitHub_mutations.ml:266`, `GitLab_mutations.ml:39` |
| 18 | Require a configured GitLab instance for discovered `coqbot.toml` mappings | P2-05 | `GitHub_GitLab_sync.ml:84` |
| 19 | Authorize on the event actor, not the PR author | P2-08 | `pr_sync.ml:55` |
| 20 | Move the membership check ahead of API work in bench; separate authz/error messages | P3-09 | `bench.ml:245` |
| 21 | Constant-time compare + header transport for the schedule secret | P3-02 | `scheduled.ml:13` |
| 22 | Check the HTTP status in `get_build_trace`; scrub traces before publishing | P3-07, P3-04 | `GitLab_queries.ml:22` |
| 23 | Replace `failwith`/`Toml.Parser.unsafe` with `Result` on attacker-reachable paths | P3-08 | `GitHub_GitLab_sync.ml:58,100,107` |
| 24 | Backdate JWT `iat` by 60 seconds | P3-05 | `GitHub_app.ml:23` |
| 25 | Enforce POST on all webhook routes; write the secret-rotation runbook | INFO-6, INFO-4 | `src/bot.ml`, `docs/` |

---

## 🎯 Control objectives and current state

| ID | Objective | State | Blocking findings |
|---|---|---|---|
| C1 | Every route authenticates, fail-closed | OPEN | P0-01, P0-03, P0-04, P1-01 |
| C2 | Human commands authorize the actor before acting | PARTIAL | P2-01, P2-08, P3-09 |
| C3 | Privileged credentials bound to a proven identity, never a caller-supplied field | OPEN | P0-01, P1-02, P2-02, P2-05, P3-03 |
| C4 | Distinct secrets per channel and per project | OPEN | P1-03, P2-07 |
| C5 | No credential appears in argv, a URL, or a log line | OPEN | P1-04, INFO-1 |
| C6 | External data never reaches a shell as a string | OPEN | P0-02, P1-05, P1-06 |
| C7 | Structured payloads built by an encoder, never concatenation | OPEN | P2-09, P3-06 |
| C8 | Bot output integrity: Checks/comments reflect real events | OPEN | P0-01, P0-03, P1-01, P2-04 |
| C9 | Abuse resistance: size limits, replay protection, rate limits | OPEN | P2-06, P2-10 |
| C10 | Outbound requests restricted to intended hosts | OPEN | P2-03 |
| C11 | Published content scrubbed of secrets | OPEN | P2-04, P3-04, P3-07 |
| C12 | Documented disclosure process and rotation runbook | PARTIAL | INFO-4 |

---

## ⚠️ Residual risk

After the recommended fixes, the following remain:

| Risk | Tier | Why it remains | Mitigation |
|---|---|---|---|
| Contributor scripts run in minimizer CI (ACCEPTED-3) | 🟡 | Intended feature | Isolated runner, no privileged secrets |
| Callback/webhook secrets exist | 🟡 | Required for auth | Per-endpoint secrets, rotation |
| PAT in memory | 🟢 | Needed for git ops | Keep off argv/logs; short-lived tokens |
| SSRF via DNS rebinding | 🟢 | Hard to fully prevent | Resolve-and-pin addresses |

---

## 📣 Vulnerability disclosure policy

| Item | Policy |
|---|---|
| Supported version | The `master` branch and the single deployed instance |
| Reporting channel | GitHub private security advisories (preferred), or a direct Zulip message to a maintainer in `CITATION.cff` |
| Do not | Open a public issue, or exploit the production instance |
| Include | Affected endpoint, source file and line, attacker impact, and a proof-of-concept request |
| Acknowledgement | 5 business days |
| Status update | 14 days |
| Fix (critical) | 30 days |
| Fix (other) | 90 days |
| Embargo | 90 days from the initial report |
| Credit | In the fix commit and changelog unless anonymity is requested |

### In scope

- Authentication/authorization bypass on any route, including the legacy aliases `/push`,
  `/pull_request`, `/job`, `/pipeline`.
- Making the bot comment, create/update Check Runs, delete branches, or merge PRs without a
  legitimate triggering event.
- Exposing or misusing any credential in the assets list.
- Shell injection or code execution on the bot host.
- Credential exposure via logs, process argv, or HTTP responses.
- Server-side request forgery from the bot host.
- Confused-deputy attacks that make the bot act for an attacker using its own credentials.

### Out of scope

- Rocq/Coq kernel soundness.
- GitHub/GitLab/Heroku platform security, except as consumed by this bot.
- Account compromise of a user with access to the bot's repositories.
- GitLab CI variable exposure on mirrored PR branches (ACCEPTED-1, an operator
  responsibility).
- Timing attacks requiring an impractical request volume against the running server.
- Issues in `rocq-community/run-coq-bug-minimizer` independent of this code.

### Known and already documented

Reports are welcome, especially with a new exploitation path, but the following are already
recorded here: P0-01 through P0-04, P1-01 through P1-06, and the shared-secret defaults in
P1-03 and P2-07.

---

## ✅ Final verdict

# 🟠 NOT SAFE UNTIL P0 FIXES ARE APPLIED

The architecture is salvageable, but the current revision must not run as a privileged
public deployment. An anonymous Internet client can obtain host command execution (two
independent paths), execute attacker-controlled code in trusted CI, and use the bot's
cross-org GitHub App privileges, because the minimizer callbacks are unauthenticated and
both webhook verifiers fail open. After Phase 0 the posture becomes substantially safer;
after Phase 0 + Phase 1 it can reach 🟢 reasonably secure for its intended open-source
use, with the documented residual risks.
