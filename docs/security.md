# 🔐 Rocq Bot Security Audit

> Single source of truth for the security posture of this repository: threat model,
> confirmed findings with cited source evidence, remediation plan, and disclosure policy.

> [!IMPORTANT]
> **Audit basis:** This document reflects the verified state of the current source tree.
> Every finding cites `file:line` and quotes the deciding expression. Controls that are
> not yet implemented are not presented as implemented.

| Field | Value |
|---|---|
| Target | Rocq Prover Bot (`coqbot` / `rocqbot`) |
| Scope | `src/`, `bot-components/`, `*.sh`, `Dockerfile`, `release.Dockerfile`, `*.toml`, GitHub Actions workflows |
| Revision | `d0d80c0` |
| Branch | `security_audit` |
| Core question | Can an untrusted person cause a privileged operation they are not authorized to cause? |

### Severity Key

| Tier | Meaning |
|---|---|
| 🔴 P0 | Unauthenticated RCE, auth/authz bypass, credential theft, or abuse of privileged credentials |
| 🟠 P1 | Privileged effect reachable with one precondition or single secret leak |
| 🟡 P2 | Bounded impact: requires account/config, or has cost/integrity/leak impact |
| 🟢 P3 | Hardening gap or latent defect with no currently reachable exploit path |
| ⚪ Info | Operational or hygiene observation |
| ✅ Accepted | Documented design risk; residual control is intentional |

---

## 🚦 Executive Summary

The bot is an internet-facing HTTP server holding a GitHub App RSA private key, a GitHub PAT, and GitLab API tokens. Three of its routes (`/coq-bug-minimizer`, `/ci-minimization`, `/resume-ci-minimization`) have **no authentication at all**, and two more **fail open** when their auth header is absent (GitHub without `installation.id`, GitLab without the token).

From those openings an anonymous client reaches:
1. **Host command execution** (via unbalanced-quote string interpolation in git commands).
2. **Attacker-controlled Docker image / workflow injection** in trusted CI.
3. **Cross-org GitHub App privilege abuse** (confused deputy).

### Posture Verdict

# 🟠 NOT SAFE UNTIL P0 FIXES ARE APPLIED

**Security Score: 2 / 10**

* **Why:** Four independent P0 conditions, all reachable by anonymous attackers, plus systemic credential exposure in process argv and logs.
* **Key Remediation Required:** Authenticate all minimizer callbacks against server-side job state, make both webhook verifiers fail closed, and replace shell-string git invocations with argv calls that keep credentials off the command line.

---

## 🧱 Trust Boundaries & Authentication Flow

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
```

### Authentication Handling by Route

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
```

---

## 📊 Vulnerability Master Table

| ID | Tier | Status | Vulnerability | Main Location | Attacker Impact |
|---|---|---|---|---|---|
| P0-01 | 🔴 | `CONFIRMED` | Minimizer callbacks have no authentication | `src/bot.ml:60` | Bot App privilege abuse; enables P0-02/P0-04 |
| P0-02 | 🔴 | `CONFIRMED` | Host RCE via unbalanced-quote shell injection | `src/ci/minimization.ml:1393` | Host command execution via branch deletion |
| P0-03 | 🔴 | `CONFIRMED` | GitHub webhook signature skipped without `installation.id` | `GitHub_subscriptions.ml:248` | Forge any GitHub webhook event |
| P0-04 | 🔴 | `CONFIRMED` | Unauth resume writes attacker-chosen Docker image / workflow | `src/ci/minimization.ml:1414` | Code execution with CI secrets in trusted repo |
| P1-01 | 🟠 | `CONFIRMED` | GitLab webhook accepted without a token (`signed` flag ignored) | `GitLab_subscriptions.ml:113` | Forge GitLab Job/Pipeline events |
| P1-02 | 🟠 | `CONFIRMED` | Unmapped GitLab path used directly as GitHub `owner/repo` | `GitHub_GitLab_sync.ml:48` | Confused deputy on unmapped repos |
| P1-03 | 🟠 | `CONFIRMED` | GitLab and schedule secrets default to GitHub secret | `src/config/config.ml:70` | Secret leak on one channel compromises all |
| P1-04 | 🟠 | `CONFIRMED` | Tokens printed in logs, git URLs, and process argv | `Git_utils.ml:19` | Credential disclosure via logs/ps |
| P1-05 | 🟠 | `CONFIRMED` | `git_fetch`/`git_push` interpolate remote URL unquoted | `Git_utils.ml:44` | Host command execution (via forged PR) |
| P1-06 | 🟠 | `CONFIRMED` | `git_test_modified` interpolates commit SHAs unquoted | `Git_utils.ml:80` | Host command execution (via forged SHA) |
| P2-01 | 🟡 | `CONFIRMED` | Minimize/CI-minimize/resume commands have no authorization | `src/webhooks/github.ml:77` | Unauthorized minimizer CI execution |
| P2-02 | 🟡 | `CONFIRMED` | Check re-run trusts `external_id` -> GitLab retry oracle | `Minimize_parser.ml:179` | GitLab retry on arbitrary path |
| P2-03 | 🟡 | `CONFIRMED` | Caller-supplied URLs fetched with no allowlist (SSRF) | `src/ci/minimization.ml:256` | Arbitrary outbound HTTP fetch |
| P2-04 | 🟡 | `CONFIRMED` | GitLab pipeline variables copied into public GitHub Checks | `pipeline.ml:9` | Credential / Markdown leak |
| P2-05 | 🟡 | `CONFIRMED` | Default-branch `coqbot.toml` retargets GitLab push | `GitHub_GitLab_sync.ml:84` | Disclose GitLab token to attacker host |
| P2-06 | 🟡 | `CONFIRMED` | No body-size limit, no replay store, quadratic regexes | `src/bot.ml:46` | Denial of Service / Lwt stall |
| P2-07 | 🟡 | `CONFIRMED` | One GitLab webhook secret shared by all mapped projects | `src/bot.ml:12` | Cross-project event forgery |
| P2-08 | 🟡 | `CONFIRMED` | CI-config gate checks PR author instead of pusher | `pr_sync.ml:55` | Authorization bypass for CI edits |
| P2-09 | 🟡 | `CONFIRMED` | Status JSON by concatenation; commit ref unvalidated | `GitHub_mutations.ml:266` | Path steering / injection |
| P2-10 | 🟡 | `CONFIRMED` | Unauthenticated routes drive installation-token minting | `GitHub_installations.ml:52` | GitHub API quota exhaustion |
| P3-01 | 🟢 | `CONFIRMED` | HMAC uses SHA-1 header only | `GitHub_subscriptions.ml:253` | Hardening gap |
| P3-02 | 🟢 | `CONFIRMED` | Stale-PR secret comparison not constant-time | `scheduled.ml:13` | Timing side-channel |
| P3-03 | 🟢 | `CONFIRMED` | GraphQL node IDs are unvalidated opaque strings | `GitHub_ID.ml` | Enables comment impersonation |
| P3-04 | 🟢 | `CONFIRMED` | Token-backed job traces published to GitHub | `job_status.ml:78` | Information leak in traces |
| P3-05 | 🟢 | `CONFIRMED` | JWT `iat` has no clock-skew margin | `GitHub_app.ml:22` | Token minting failure under clock skew |
| P3-06 | 🟢 | `POTENTIAL` | `play_job` builds JSON by concatenation | `GitLab_mutations.ml:39` | Latent injection |
| P3-07 | 🟢 | `CONFIRMED` | `get_build_trace` ignores HTTP status code | `GitLab_queries.ml:22` | Error body disclosure oracle |
| P3-08 | 🟢 | `CONFIRMED` | Attacker input raises uncaught exceptions | `GitHub_GitLab_sync.ml:58` | Availability / 500 error |
| P3-09 | 🟢 | `CONFIRMED` | Bench authorization evaluated after GraphQL API work | `bench.ml:245` | Ordering / internal message leak |

---

## 🔴 P0 Findings

### 🔴 P0-01 - Minimizer callbacks have no authentication

* **Status:** `CONFIRMED` · **Tier:** 🔴 P0 · **CWE-306**
* **Affected:** `src/bot.ml:60`, `src/webhooks/minimizer.ml:7`, `src/ci/minimization.ml:1376`

#### Impact
The three minimizer endpoints (`/coq-bug-minimizer`, `/ci-minimization`, `/resume-ci-minimization`) are dispatched without checking any secret, HMAC, or job token. Any anonymous client can drive every action reachable from them: posting comments as the GitHub App into any org where the bot is installed (confused deputy), deleting branches via string interpolation (P0-02), and triggering CI resumption with an attacker-chosen Docker image (P0-04).

#### Evidence
`src/bot.ml:60` routes the paths directly without authentication parameters:
```ocaml
| "/coq-bug-minimizer" | "/ci-minimization" | "/resume-ci-minimization" ->
    Minimizer.handle_minimizer_webhook ~bot_info ~key ~app_id ~endpoint:path ~body
```
In `src/ci/minimization.ml:1380`, fields are split from the unauthenticated payload line and trusted:
```ocaml
match Str.split (Str.regexp " ") stamp with
| [id; author; repo_name; branch_name; owner; _repo; _] -> ...
```
* `owner`: `action_as_github_app ~owner` mints a token for that org (`GitHub_installations.ml:52`).
* `id`: Bot posts comments on that GraphQL thread ID as the GitHub App.
* `repo_name` & `branch_name`: Passed directly to PAT-authenticated `git push --delete`.

#### Fix
Generate an opaque job ID when starting minimization, store `{job_id -> owner, repo, branch, thread}` server-side, and require callbacks to present the `job_id` plus a secret token verified with `Eqaf.equal`. Derive repository parameters strictly from stored state.

---

### 🔴 P0-02 - Host RCE via unbalanced-quote shell injection

* **Status:** `CONFIRMED` · **Tier:** 🔴 P0 · **CWE-78**
* **Affected:** `src/ci/minimization.ml:1393`, `bot-components/utils/Git_utils.ml:20`

#### Impact
Upon receiving a minimizer callback, the bot deletes the temporary branch using a shell command constructed via string formatting. The branch name is preceded by a single quote `'` that is **never closed**. Because `repo_name` and `branch_name` come from the unauthenticated payload, an attacker supplying a balancing single quote and shell metacharacters achieves arbitrary command execution on the bot host.

#### Evidence
`src/ci/minimization.ml:1393`:
```ocaml
Git_utils.execute_cmd
  (f "git push https://%s:%s@github.com/%s.git --delete '%s"
     bot_info.github_name
     (Bot_info.github_pat bot_info)
     repo_name branch_name )
```
`bot-components/utils/Git_utils.ml:20` executes the string via `/bin/sh`:
```ocaml
let process = Lwt_process.open_process_full (Lwt_process.shell command) in
```
Because `Str.split (Str.regexp " ")` disallows spaces, space-free payloads using `${IFS}` execute commands (e.g. `';echo${IFS}RCE-PROOF`). Under normal operation, this line yields a syntax error in `sh`, meaning branch deletion has always failed for legitimate branches and only "succeeds" when an attacker balances the quote.

#### Fix
Use `Lwt_process.exec` with an argument array (`argv`) rather than shell string interpolation. Pass credentials via git `http.extraHeader` or a credential helper instead of embedding secrets in command strings.

---

### 🔴 P0-03 - GitHub webhook signature skipped when `installation.id` is absent

* **Status:** `CONFIRMED` · **Tier:** 🔴 P0 · **CWE-347**
* **Affected:** `bot-components/github/GitHub_subscriptions.ml:248`, `tests/test_webhook.ml:134`

#### Impact
Signature verification is executed only within a block guarded by reading `installation.id`. When a JSON payload omits `"installation"` (or contains a malformed field), the exception handler catches `Json_error` / `Type_error` and returns `Ok None`—bypassing HMAC verification entirely while still dispatching the event to `github_event`. An anonymous attacker can forge arbitrary GitHub events (pushes, PRs, comments).

#### Evidence
`bot-components/github/GitHub_subscriptions.ml:248`:
```ocaml
( try
    let install_id = json |> member "installation" |> member "id" |> to_int in
    match Header.get headers "X-Hub-Signature" with
    | Some signature -> ... if Eqaf.equal signature expected then Ok (Some install_id) ...
    | None -> Error "Webhook comes from a GitHub App, but it is not signed."
  with Yojson.Json_error _ | Type_error _ -> Ok None )
>>= fun install_id -> ... github_event ~event json ...
```
`tests/test_webhook.ml:134-162` explicitly tests and validates that webhooks without `installation.id` pass without a signature. Unsigned events reaching `github_event` include:
* `PullRequestUpdated` (`github.ml:277`): Triggers `git_fetch` on attacker URLs (P1-05/P1-06).
* `IssueOpened` / `CommentCreated` (`github.ml:335,358`): Triggers minimizer actions and bot comments.

#### Fix
Verify HMAC signature (`X-Hub-Signature-256`) over the raw request body unconditionally before parsing any JSON fields. Return `Error` if the signature is missing or invalid.

---

### 🔴 P0-04 - Unauthenticated resume writes attacker-chosen workflow image

* **Status:** `CONFIRMED` · **Tier:** 🔴 P0 · **CWE-306 / Supply Chain**
* **Affected:** `src/ci/minimization.ml:1414`, `run_ci_minimization.sh:56,78`

#### Impact
The `/resume-ci-minimization` route parses `docker_image` from the request body and forwards it to `run_ci_minimization.sh`, which uses `sed` to splice the image string into `.github/workflows/main.yml` and pushes the branch to `rocq-community/run-coq-bug-minimizer`. An attacker can specify a malicious container image or inject raw YAML lines via single quotes and newlines, executing arbitrary code with repository secrets in GitHub Actions.

#### Evidence
`src/ci/minimization.ml:1424,1447` extracts `docker_image` unvalidated.
`run_ci_minimization.sh:56`:
```bash
sed -i 's~^\(\s*\)[^:\s]*custom_image:.*$~\1custom_image: '"'${docker_image}'~" .github/workflows/main.yml
```
`run_ci_minimization.sh:78`:
```bash
git push --set-upstream "https://$bot_name:$token@github.com/$repo_name.git" "$branch_name"
```

#### Fix
Derive `docker_image` exclusively from validated server-side job state, enforce an allowlist of container registries and pinned SHA256 digests, and perform YAML updates using a structured parser rather than `sed` string splicing.

---

## 🟠 P1 Findings

### 🟠 P1-01 - GitLab webhooks accepted without a token (`signed` flag ignored)

* **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **CWE-306**
* **Affected:** `bot-components/gitlab/GitLab_subscriptions.ml:113`, `src/webhooks/gitlab.ml:19,30`

#### Impact
When `X-Gitlab-Token` is missing, `receive_gitlab` returns `Ok (false, event)` instead of an error. The handlers in `src/webhooks/gitlab.ml` pattern-match `Ok (_, JobEvent ...)` and `Ok (_, PipelineEvent ...)`, completely ignoring the `signed` boolean. Anonymous clients can forge GitLab job/pipeline webhooks, generating false GitHub Check status runs or triggering automated minimization.

#### Evidence
`GitLab_subscriptions.ml:113`:
```ocaml
( match Header.get headers "X-Gitlab-Token" with
  | Some header_secret ->
      if Eqaf.equal secret header_secret then return true
      else Error "Webhook password mismatch."
  | None -> return false )
```
`src/webhooks/gitlab.ml:19` discards the flag:
```ocaml
| Ok (_, JobEvent ({common_info= {http_repo_url}} as job_info)) -> ...
```

#### Fix
Return `Error "Missing X-Gitlab-Token"` when the header is absent. Remove the `signed` boolean wrapper so only verified events are returned in `Ok`.

---

### 🟠 P1-02 - Unmapped GitLab path used directly as GitHub `owner/repo`

* **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **CWE-20**
* **Affected:** `bot-components/github/GitHub_GitLab_sync.ml:48`

#### Impact
When mapping a GitLab project path to GitHub, a lookup miss in `gitlab_mapping` falls back to returning the raw GitLab project path string. A forged GitLab job event with `repository.homepage` set to an unmapped repository causes the bot to mint installation tokens and post Checks to arbitrary GitHub repos where the bot app is installed.

#### Evidence
`GitHub_GitLab_sync.ml:48`:
```ocaml
let github_full_name =
  match Hashtbl.find gitlab_mapping full_name_with_domain with
  | Some value -> value
  | None ->
      Stdio.printf "Warning: No correspondence found for GitLab repository %s.\n" full_name_with_domain ;
      gitlab_repo_full_name
```

#### Fix
Return an `Error` result on lookup miss. Refuse to process webhooks for unmapped repositories.

---

### 🟠 P1-03 - GitLab and schedule secrets default to GitHub webhook secret

* **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **CWE-1188**
* **Affected:** `src/config/config.ml:70,79`

#### Impact
`gitlab_webhook_secret` and `daily_schedule_secret` fall back to `github_webhook_secret` when their environment variables are not set. Sharing one secret across multiple trust domains allows an attacker holding or capturing one secret to forge events across all three channels.

#### Evidence
`src/config/config.ml:70`:
```ocaml
let gitlab_webhook_secret toml_data =
  match subkey_value toml_data "gitlab" "webhook_secret" with
  | None -> Option.value ~default:(github_webhook_secret toml_data) (Sys.getenv "GITLAB_WEBHOOK_SECRET")
  | Some secret -> secret
```

#### Fix
Require `GITLAB_WEBHOOK_SECRET` and `DAILY_SCHEDULE_SECRET` to be specified explicitly. Fail startup if any required secret is missing.

---

### 🟠 P1-04 - Tokens printed in command logs, git URLs, and process argv

* **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **CWE-532**
* **Affected:** `Git_utils.ml:19`, `src/ci/minimization.ml:1394`, `coq_bug_minimizer.sh:39`, `run_ci_minimization.sh:78`

#### Impact
`Git_utils.execute_cmd` logs the full command string via `Lwt_io.printf "Executing command: %s\n"` *before* running the process. The `~mask` parameter is applied only inside `report_status` when a command fails. Cleartext PATs and OAuth tokens embedded in git URLs are emitted to standard stdout/logs and visible in process `argv` via `ps`.

#### Evidence
`Git_utils.ml:19`:
```ocaml
let execute_cmd ?(mask = []) command =
  Lwt_io.printf "Executing command: %s\n" command
  >>= fun () ->
  let process = Lwt_process.open_process_full (Lwt_process.shell command) in
```

#### Fix
Apply secret masking to command strings *before* printing to logs. Pass authentication tokens via environment variables or git credential helpers rather than CLI arguments or URL strings.

---

### 🟠 P1-05 - `git_fetch` and `git_push` interpolate remote URLs unquoted

* **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **CWE-78**
* **Affected:** `bot-components/utils/Git_utils.ml:44,50`

#### Impact
In `git_fetch` and `git_push`, reference names are quoted using `Filename.quote`, but `remote_ref.repo_url` is interpolated directly into shell strings without quoting. An attacker controlling `repo.html_url` in a PR payload (reachable via P0-03) can execute arbitrary host shell commands.

#### Evidence
`Git_utils.ml:44`:
```ocaml
let git_fetch ?(force = true) remote_ref local_branch_name =
  f "git fetch --quiet -fu %s %s%s:%s" remote_ref.repo_url
    (if force then "+" else "")
    (Stdlib.Filename.quote remote_ref.name)
    (Stdlib.Filename.quote local_branch_name)
```

#### Fix
Pass arguments as an un-interpolated `argv` list to `Lwt_process.exec`. Quote `repo_url` and add `--` separators before refspec arguments.

---

### 🟠 P1-06 - `git_test_modified` interpolates commit SHAs unquoted

* **Status:** `CONFIRMED` · **Tier:** 🟠 P1 · **CWE-78**
* **Affected:** `bot-components/utils/Git_utils.ml:80`, `src/actions/pr_sync.ml:46`

#### Impact
`git_test_modified` constructs a shell pipeline `git diff %s...%s --name-only | grep "%s"` and executes it via `Lwt_unix.system`. None of the parameters (`base`, `head`, `pattern`) are quoted or sanitized. Under P0-03, untrusted commit SHAs from webhook payloads reach this function, enabling shell command injection.

#### Evidence
`Git_utils.ml:80`:
```ocaml
let command = f {|git diff %s...%s --name-only | grep "%s"|} base head pattern in
Lwt_unix.system command
```

#### Fix
Validate commit SHAs against `^[0-9a-f]{7,40}$` at JSON parsing boundaries. Perform file diff checks programmatically in OCaml rather than invoking shell pipelines.

---

## 🟡 P2 Findings

* **P2-01 - Minimizer commands lack team authorization** (`src/webhooks/github.ml:77`): `merge now` and `bench` check `@rocq-prover` team membership, but `minimize` runs for any GitHub commenter. **Fix:** Enforce `get_team_membership` check on minimizer commands.
* **P2-02 - Check re-run trusts unvalidated `external_id`** (`Minimize_parser.ml:179`): Signed check re-requests use `external_id` directly in GitLab API retry endpoints (`GitLab_mutations.ml:5`). **Fix:** Validate `external_id` against `^projects/\d+/(jobs|pipelines)/\d+$`.
* **P2-03 - Caller-supplied URLs fetched without allowlist (SSRF)** (`src/ci/minimization.ml:256`): `download_cps` fetches arbitrary HTTP/HTTPS URLs with no IP address range validation. **Fix:** Restrict downloads to HTTPS, block private/loopback IP ranges (127.0.0.1, 169.254.169.254), and cap redirects.
* **P2-04 - Pipeline variables reflected in GitHub Checks** (`pipeline.ml:9`): `create_pipeline_summary` prints all GitLab pipeline variables to public Check Run summaries. **Fix:** Filter variables through a strict allowlist (`FULL_CI`, `SKIP_DOCKER`).
* **P2-05 - Default branch `coqbot.toml` retargets GitLab push** (`GitHub_GitLab_sync.ml:84`): Repositories installing the app can override `gl_domain` and `gl_repo` to receive mirrored pushes containing GitLab tokens. **Fix:** Reject unconfigured GitLab domains.
* **P2-06 - Missing request body size limits** (`src/bot.ml:46`): `Cohttp_lwt.Body.to_string` buffers entire payloads before checking auth, allowing large payloads to stall the single-threaded Lwt event loop. **Fix:** Enforce a maximum body size limit (e.g. 1MB) prior to buffering.
* **P2-07 - Shared GitLab webhook secret across all projects** (`src/bot.ml:12`): All mapped GitLab projects share one webhook secret. Maintainers of one mapped project can forge webhooks for others. **Fix:** Key secrets by GitLab project ID.
* **P2-08 - CI-config gate checks PR author instead of pusher** (`pr_sync.ml:55`): When CI configuration files are edited, the bot verifies the PR author's team membership instead of the commit pusher (`sender.login`). **Fix:** Verify team membership for the pusher.
* **P2-09 - Status JSON built by string concatenation** (`GitHub_mutations.ml:266`): Status payloads format JSON strings manually, leaving `commit` unvalidated in the API URI. **Fix:** Validate commit SHAs and build JSON using `Yojson`.
* **P2-10 - Unauthenticated routes trigger App token minting** (`GitHub_installations.ml:52`): Requesting unauthenticated routes with arbitrary `owner` parameters causes the bot to execute GitHub API calls to fetch installation IDs. **Fix:** Authenticate requests before resolving installation IDs.

---

## 🟢 P3 & Hygiene Findings

* **P3-01 - HMAC uses SHA-1 header only** (`GitHub_subscriptions.ml:253`): Reads `X-Hub-Signature` (SHA-1) instead of `X-Hub-Signature-256`. **Fix:** Upgrade to SHA-256.
* **P3-02 - Non-constant-time schedule secret comparison** (`scheduled.ml:13`): `String.equal` short-circuits. **Fix:** Use `Eqaf.equal`.
* **P3-03 - Unvalidated GraphQL node IDs** (`GitHub_ID.ml`): Node IDs are wrapped strings without state validation. **Fix:** Validate node IDs against server-side state.
* **P3-04 - CI job traces published to public GitHub Checks** (`job_status.ml:78`): Raw job logs embedded in checks may leak tokens. **Fix:** Scrub sensitive patterns from published traces.
* **P3-05 - JWT `iat` has no clock-skew margin** (`GitHub_app.ml:22`): `exp = iat + 550` fails under clock drift. **Fix:** Backdate `iat` by 60s.
* **P3-06 - `play_job` JSON concatenation** (`GitLab_mutations.ml:39`): Latent string concatenation in JSON body. **Fix:** Use `Yojson`.
* **P3-07 - `get_build_trace` ignores HTTP status codes** (`GitLab_queries.ml:22`): Returns 40x error bodies as trace text. **Fix:** Check status code for 200 OK.
* **P3-08 - Uncaught exceptions on malformed input** (`GitHub_GitLab_sync.ml:58`): `failwith` and `Toml.Parser.unsafe` raise unhandled exceptions. **Fix:** Handle exceptions and return `Result.error`.
* **P3-09 - Bench auth evaluated after API queries** (`bench.ml:245`): Performs GraphQL lookups before checking team membership. **Fix:** Check membership first.

---

## ⚪ Operational Hygiene (Info)

| ID | Finding | Recommendation |
|---|---|---|
| INFO-1 | Exception handler logs raw exception strings (`src/bot.ml:73`) | Scrub secret patterns from exception strings. |
| INFO-2 | TLS terminated by reverse proxy/Heroku router (`src/bot.ml:70`) | Ensure server is bound only to local loopback interface. |
| INFO-3 | Installation tokens stored in process memory (`GitHub_installations.ml:8`) | Scope token lifetime tightly. |
| INFO-4 | Missing secret-rotation documentation | Write clear secret-rotation runbook. |
| INFO-5 | Credentials present in local `.bot-env` file | File is gitignored (`0600` permissions); rotate credentials if exposed. |
| INFO-6 | HTTP routes ignore request method (`src/bot.ml:39`) | Enforce `POST` method on webhook callback endpoints. |
| INFO-7 | App private key file permissions (`*.private-key.pem`) | File is gitignored; ensure file mode `0600` and keep outside workspace. |
| INFO-8 | Missing CORS headers | Add explicit origin checking for browser requests. |

---

## ✅ Accepted Design Risks

| ID | Risk | Reason Accepted | Compensating Control |
|---|---|---|---|
| ACCEPTED-1 | Untrusted PR commits pushed to GitLab `pr-N` branches | Core functionality of PR CI synchronization. | Operator-configured GitLab protected branches and secret masks. |
| ACCEPTED-2 | `@bot merge now` merges on a single comment | Intended workflow automation. | Strict eligibility checks: assignees, approvals, labels, pushers team. |
| ACCEPTED-3 | Minimizer runs user-supplied scripts in CI | Intended feature of Coq bug minimization. | Runs in isolated GitHub Actions environment (`run-coq-bug-minimizer`). |

---

## 🛠️ Remediation Plan

```mermaid
flowchart LR
  S1["Phase 0 (Stop ship)<br/>Close unauthenticated RCE<br/>and fail-open auth"]
  S2["Phase 1<br/>Secret separation,<br/>authorization, allowlists"]
  S3["Phase 2/3<br/>Abuse resistance,<br/>encoding, hygiene"]

  S1 --> S2 --> S3

  classDef transport fill:#ffe0b2,stroke:#ef6c00,color:#e65100
  classDef wiring fill:#b2dfdb,stroke:#00796b,color:#004d40
  classDef question fill:#fff9c4,stroke:#f9a825,color:#5d4037

  class S1 transport
  class S2 wiring
  class S3 question
```

### Phase 0 - Immediate Fixes (Stop Ship)

1. **Replace git shell strings with argv calls**: Move PAT off URL string in `src/ci/minimization.ml:1394` (P0-02, P1-04).
2. **Authenticate minimizer routes**: Require secret token + server-side job lookup in `src/bot.ml:60` and `src/webhooks/minimizer.ml` (P0-01, P0-04).
3. **Fail-closed GitHub HMAC check**: Verify `X-Hub-Signature-256` unconditionally before JSON parsing in `GitHub_subscriptions.ml:243` (P0-03).
4. **Fail-closed GitLab token check**: Return `Error` when `X-Gitlab-Token` is missing in `GitLab_subscriptions.ml:113` (P1-01).
5. **Sanitize git arguments**: Quote/vectorize URLs and commit SHAs in `Git_utils.ml:44,50,80` (P1-05, P1-06).

### Phase 1 - Privilege Boundaries

1. **Enforce explicit secrets**: Require `GITLAB_WEBHOOK_SECRET` and `DAILY_SCHEDULE_SECRET` explicitly in `src/config/config.ml:70` (P1-03).
2. **Mask logs**: Mask secrets in `Git_utils.execute_cmd` before logging (P1-04).
3. **Reject unmapped repos**: Return error on GitLab mapping lookup miss in `GitHub_GitLab_sync.ml:48` (P1-02).
4. **Authorize minimizer commands**: Gate `minimize` on contributor team membership in `src/webhooks/github.ml:77` (P2-01).
5. **Validate external IDs**: Constrain `external_id` regex in `Minimize_parser.ml:179` (P2-02).
6. **Restrict URL fetching**: Enforce HTTPS, block private IP ranges, cap redirects in `HTTP_utils.ml:168` (P2-03).

### Phase 2/3 - Hardening & Hygiene

1. **Enforce request size limits**: Cap request body sizes before buffering in `src/bot.ml:39` (P2-06).
2. **Rate-limit installation lookups**: Cache unknown owners in `GitHub_installations.ml:52` (P2-10).
3. **Per-project GitLab secrets**: Key webhook secrets by project ID in `src/bot.ml:12` (P2-07).
4. **Structured JSON construction**: Replace string concatenation with `Yojson` in `GitHub_mutations.ml:266` (P2-09, P3-06).
5. **Verify pusher identity**: Gate CI edits on commit pusher membership in `pr_sync.ml:55` (P2-08).
