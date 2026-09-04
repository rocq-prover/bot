# MASTER PROMPT — ROcq BOT SECURITY REVISIT, THREAT MODEL, VERIFICATION & SECURITY DOCUMENTATION

## 0. Mission

Perform a rigorous, evidence-driven security revisit of the **Rocq Prover bot** repository.

Treat the system as a:

> **Privileged, event-driven DevOps automation service integrating GitHub, GitLab, repositories, CI/CD, Docker/container execution, and shell commands.**

This is **not** merely a chatbot or generic web application.

The primary security question is:

> **Can an untrusted external actor cause the bot to perform a privileged action that the actor is not authorized to cause?**

Do not assume that existing security documentation, previous audits, comments, tests, or claimed fixes are correct.

The current source tree, configuration, tests, deployment configuration, and observed runtime behavior are the evidence.

---

# 1. Core Audit Principles

Follow these principles throughout the audit.

### 1.1 Evidence over claims

Never classify a vulnerability as fixed merely because:

- documentation says it was fixed;
- a commit message says it was fixed;
- a TODO was removed;
- code appears cleaner;
- a previous audit says it was fixed;
- a test exists but does not actually exercise the security property.

A finding is **Verified Fixed** only when the current implementation and appropriate tests/evidence demonstrate that the security property holds.

Use these statuses:

| Status | Meaning |
|---|---|
| `CONFIRMED` | Vulnerability is demonstrated in the current implementation |
| `LIKELY` | Strong evidence exists but exploitation could not be fully demonstrated |
| `POTENTIAL` | Security weakness exists but exploitability is uncertain |
| `NOT_REPRODUCED` | Previous claim could not be reproduced |
| `FIXED-VERIFIED` | Current implementation + evidence demonstrate the fix |
| `FIXED-UNVERIFIED` | Code appears fixed but verification is insufficient |
| `FALSE-POSITIVE` | Finding is not applicable after investigation |
| `UNKNOWN` | Insufficient evidence |

Never silently convert `UNKNOWN` into `SAFE`.

---

# 2. Repository Snapshot

Before making any changes:

1. Record the repository revision/commit.
2. Record the branch.
3. Record relevant modified/uncommitted files.
4. Record the audit date.
5. Record the tools and test commands used.
6. Identify the scope of the review.
7. Do not modify source code during the initial audit pass.

Clearly distinguish:

```text
Observed in current source
        ≠
Claimed by documentation
        ≠
Previously reported
        ≠
Verified fixed
```

If remediation is requested later, create a separate remediation phase.

---

# 3. System Classification

Explicitly classify the bot as:

**Privileged Event-Driven DevOps Automation**

Explain why this matters.

Identify the privileged capabilities available to the bot, including where applicable:

- GitHub App credentials
- GitHub installation tokens
- GitHub PATs
- GitLab API tokens
- repository read/write access
- pull-request manipulation
- issue/comment operations
- CI triggering
- workflow modification
- Docker/container execution
- shell command execution
- repository cloning/fetching/pushing
- artifact generation
- external HTTP requests
- publishing logs/traces/results
- credential-backed API operations

Determine which capabilities can be indirectly triggered by untrusted input.

---

# 4. Architecture Discovery

Before judging individual vulnerabilities, reconstruct the actual architecture.

Inspect:

- source tree
- HTTP server
- webhook handlers
- authentication code
- authorization code
- GitHub integration
- GitLab integration
- configuration
- credential loading
- subprocess execution
- Docker execution
- repository operations
- CI/workflow logic
- asynchronous/background jobs
- deployment manifests
- shell scripts
- tests
- CI configuration
- documentation
- dependency configuration

Do not rely on filenames alone.

Trace execution paths from entry point to privileged operation.

---

# 5. Required System Diagram

Produce a clear system-context diagram.

Use Mermaid where practical.

Show:

```text
External actors
      ↓
HTTP/Webhook entry points
      ↓
Authentication
      ↓
Authorization
      ↓
Identity/resource binding
      ↓
Bot business logic
      ↓
GitHub / GitLab / Git / Docker / Shell / HTTP
      ↓
Repositories / CI / Artifacts / Published output
```

Mark trust boundaries explicitly.

Use distinct visual labels for:

- untrusted input
- authenticated identity
- privileged credentials
- repository-controlled data
- bot-controlled data
- external services
- execution environments

---

# 6. Data-Flow Diagram

Create a DFD showing:

- external input;
- authentication material;
- webhook payloads;
- repository identifiers;
- commit SHA values;
- branch names;
- URLs;
- Docker image names;
- pipeline variables;
- GitLab traces;
- GitHub API requests;
- GitLab API requests;
- secrets;
- generated commands;
- generated workflows;
- published content.

For every flow identify:

1. source;
2. destination;
3. trust level;
4. validation;
5. authentication;
6. authorization;
7. transformation;
8. privileged effect.

---

# 7. Entry-Point Inventory

Build a complete table.

| Endpoint/Event | Method | Authentication | Authorization | Input | Privileged Effect | Fail Closed? | Replay Protection | Rate/Size Limit |
|---|---|---|---|---|---|---|---|---|

Include:

- GitHub webhooks;
- GitLab webhooks;
- scheduled endpoints;
- minimization endpoints;
- CI endpoints;
- resume/retry endpoints;
- health/debug endpoints;
- internal callbacks;
- command/API endpoints;
- any aliases.

Do not assume an endpoint is internal merely because its name suggests it is.

---

# 8. Authentication Audit

For every entry point determine:

### Required properties

- Is authentication mandatory?
- Is absence of credentials rejected?
- Is malformed authentication rejected?
- Is invalid authentication rejected?
- Is verification performed before expensive work?
- Is verification performed before parsing attacker-controlled fields that influence security decisions?
- Is the correct cryptographic algorithm used?
- Is comparison constant-time where appropriate?
- Is the secret scoped to the correct integration/project?
- Can authentication silently fail open?
- Can exceptions bypass verification?
- Can headers be duplicated or ambiguously parsed?

For GitHub webhooks:

- prefer `X-Hub-Signature-256`;
- verify the raw request body;
- reject missing signatures;
- reject malformed signatures;
- reject invalid signatures;
- do not allow parsing failures to bypass verification.

For GitLab:

- reject missing webhook secrets;
- reject invalid secrets;
- ensure every relevant integration has explicit secret configuration;
- do not rely on a boolean such as `signed=true/false` unless it is enforced centrally.

---

# 9. Authorization Audit

Authentication is not authorization.

For every privileged operation determine:

```text
Who is calling?
        ↓
How was identity established?
        ↓
Is this identity authorized?
        ↓
For which repository/project?
        ↓
For which installation/account?
        ↓
For which operation?
        ↓
With which parameters?
```

Check:

- contributor/team membership;
- repository permissions;
- project permissions;
- installation ownership;
- event actor identity;
- pull-request author identity;
- organization membership;
- bot/admin privileges.

Pay special attention to cases where:

```text
event actor ≠ PR author
```

and where:

```text
caller-supplied installation/repository/account
```

selects a privileged credential.

---

# 10. Identity / Resource Binding

Treat this as a first-class security control.

Identify every privileged resource:

- GitHub installation;
- GitHub repository;
- GitLab project;
- GitLab instance;
- token;
- Docker image;
- workflow;
- branch;
- target repository;
- external URL.

For each determine whether the caller can influence the resource independently of the authenticated identity.

Look specifically for confused-deputy patterns:

```text
Attacker
  ↓
authenticated request
  ↓
attacker supplies resource ID
  ↓
bot selects privileged credential
  ↓
bot performs operation
```

A secure design should instead establish:

```text
authenticated identity
        ↓
authorized resource
        ↓
privileged credential
```

Do not trust caller-supplied identity/resource fields simply because the caller passed webhook authentication.

---

# 11. Command Execution Audit — P0

Perform an exhaustive audit of:

- `Sys.command`;
- `Unix.open_process*`;
- shell invocation;
- `/bin/sh`;
- `/bin/bash`;
- `docker`;
- `git`;
- `curl`;
- `wget`;
- dynamically constructed shell strings;
- shell scripts;
- command wrappers;
- subprocess helpers.

Search for:

```text
"$variable"
"$value"
sprintf(...)
Printf.sprintf(...)
String.concat(...)
```

being passed into shell commands.

Trace all attacker-controlled values into command execution, including:

- branch names;
- repository names;
- URLs;
- commit SHAs;
- PR titles;
- usernames;
- GitHub/GitLab fields;
- pipeline variables;
- Docker image names;
- file paths;
- patterns;
- comments;
- webhook payload fields.

### Required security invariant

> **No attacker-controlled value may be interpolated into a shell command.**

Prefer:

```text
argv vector
+
explicit executable
+
validated arguments
```

over:

```text
shell string
```

---

# 12. Command-Injection Verification

For every potentially dangerous execution path, test security boundaries using harmless proof-of-concept values.

Examples:

```text
';id
";id
$(id)
`id`
&& id
|| id
; id
\n id
```

Also test special characters in:

- branch names;
- commit SHAs;
- URLs;
- repository names;
- patterns;
- Docker image names.

Do not stop after testing one injection point.

Trace the complete data path:

```text
HTTP/webhook
 → parser
 → validation
 → business logic
 → command builder
 → subprocess
```

---

# 13. Git / Repository Security

Audit all Git operations:

- clone;
- fetch;
- checkout;
- push;
- branch creation/deletion;
- remote configuration;
- credentials;
- URLs;
- refspecs;
- SHA handling;
- repository paths.

Verify:

- commit SHA values are strictly validated;
- branch names cannot become options;
- repository URLs cannot inject commands;
- credentials do not appear in command arguments;
- credentials do not appear in URLs;
- credentials do not appear in logs;
- remote URLs are controlled;
- pushes target the intended repository;
- attacker-controlled repository metadata cannot redirect privileged operations.

---

# 14. Docker / Container Security

Where Docker or container execution is used, determine:

- who controls the image;
- who selects the image;
- whether an attacker can supply the image;
- whether mutable tags are accepted;
- whether image digests are supported;
- whether privileged containers are possible;
- mounted directories;
- mounted credentials;
- Docker socket access;
- network access;
- host filesystem exposure;
- environment-variable exposure.

Special attention:

> An attacker-controlled Docker image is potentially equivalent to attacker-controlled code execution.

Determine whether an attacker can cause the bot to pull and execute an arbitrary image.

---

# 15. CI/CD and Workflow Integrity

Audit:

- workflow generation;
- workflow modification;
- pipeline variables;
- CI configuration;
- branch selection;
- target selection;
- Docker image selection;
- artifact publishing;
- CI triggering;
- reruns;
- resume operations.

Determine whether attacker-controlled input can:

- modify workflow YAML;
- inject workflow expressions;
- alter commands;
- choose privileged branches;
- choose privileged repositories;
- choose privileged images;
- inject environment variables;
- redirect artifacts;
- trigger privileged CI jobs.

Separate:

```text
trusted repository-controlled configuration
```

from:

```text
attacker-controlled event data
```

Do not allow the latter to silently become the former.

---

# 16. Webhook Security

For every webhook:

1. verify signature;
2. verify event type;
3. validate payload structure;
4. establish actor identity;
5. establish repository/project identity;
6. authorize the action;
7. validate security-sensitive fields;
8. enforce replay protection;
9. enforce size limits;
10. enforce resource limits.

Audit:

- missing signature;
- wrong signature;
- malformed signature;
- duplicate delivery;
- replayed delivery;
- stale delivery;
- duplicate event;
- conflicting event metadata;
- actor/repository mismatch.

Use GitHub delivery identifiers where available for replay detection.

---

# 17. SSRF Audit

Trace every attacker-controlled URL.

Identify:

- HTTP clients;
- redirects;
- DNS resolution;
- proxies;
- custom headers;
- URL parsers;
- Git remote URLs;
- GitLab instance URLs;
- callback URLs.

Protect against:

- localhost;
- loopback;
- private networks;
- link-local addresses;
- cloud metadata services;
- internal DNS;
- IPv6 equivalents;
- DNS rebinding;
- redirect-based bypasses.

Enforce destination policy:

```text
URL
 ↓
parse
 ↓
resolve
 ↓
validate destination
 ↓
connect
 ↓
revalidate redirect destination
```

Do not rely solely on hostname string matching.

---

# 18. Secret and Credential Security

Inventory every credential:

| Credential | Provider | Scope | Lifetime | Storage | Exposure Risk | Rotation |
|---|---|---|---|---|---|---|

Check:

- GitHub App private key;
- GitHub PAT;
- GitHub installation tokens;
- GitLab tokens;
- webhook secrets;
- schedule secrets;
- CI credentials;
- Docker credentials;
- environment variables.

Verify:

- least privilege;
- short lifetime where possible;
- no secrets in repository;
- no secrets in command-line arguments;
- no secrets in URLs;
- no secrets in logs;
- no secrets in generated artifacts;
- no secrets in published traces;
- appropriate filesystem permissions;
- credential rotation procedure.

Prefer short-lived GitHub App installation tokens over long-lived PATs where architecture permits.

---

# 19. Secret Exposure / Exfiltration

Search for credentials flowing into:

```text
argv
URLs
logs
exceptions
Git traces
GitLab traces
GitHub comments
PR comments
CI artifacts
Docker environment
generated files
published reports
```

Pay particular attention to token-backed build traces.

Determine whether secrets could be published to a public repository, issue, PR, or external service.

---

# 20. JSON / Serialization Security

Do not construct security-sensitive JSON by string concatenation.

Audit:

- GitHub API payloads;
- GitLab API payloads;
- workflow JSON;
- CI variables;
- external API requests.

Prefer structured encoders such as the project's JSON library.

Validate:

- strings;
- numbers;
- booleans;
- arrays;
- objects;
- URLs;
- commit SHAs;
- identifiers.

---

# 21. Resource Exhaustion / Abuse Resistance

For every public endpoint determine:

- body-size limit;
- request timeout;
- connection timeout;
- response limit;
- queue limit;
- concurrency limit;
- subprocess limit;
- Docker execution limit;
- API retry limit;
- installation-token minting limit;
- GitHub/GitLab API rate limiting;
- replay handling.

Look for unauthenticated paths capable of causing expensive work.

Security property:

> Authentication and cheap validation should occur before expensive privileged work whenever possible.

---

# 22. Error Handling

Audit:

- `failwith`;
- uncaught exceptions;
- unsafe parsers;
- stack traces;
- raw API responses;
- credential-bearing error messages;
- HTTP status handling.

Verify external failures cannot:

- bypass authorization;
- bypass authentication;
- leave partially completed privileged actions;
- expose credentials;
- cause fail-open behavior.

Prefer explicit error/result handling for security-sensitive operations.

---

# 23. Outbound API Security

For GitHub and GitLab API calls determine:

- credential used;
- scope;
- resource being accessed;
- authorization relationship;
- HTTP method;
- status-code validation;
- retries;
- timeout;
- response size;
- redirect behavior.

Never assume an HTTP request succeeded merely because a response was returned.

---

# 24. Supply-Chain Security

Treat supply-chain security as **first-class**, but keep standards proportional to the actual repository.

Audit:

- dependencies;
- GitHub Actions;
- GitLab CI;
- Docker images;
- build inputs;
- generated workflows;
- release artifacts;
- artifact publishing;
- mutable tags;
- third-party scripts;
- external downloads.

Where applicable evaluate:

- dependency pinning;
- SBOM;
- provenance;
- artifact signing;
- trusted build environments;
- SLSA-relevant controls;
- OpenSSF Scorecard.

Do not claim SLSA/compliance merely because a control is desirable.

Map only standards that are genuinely applicable.

---

# 25. Security Standards Mapping

Use standards as **reference frameworks**, not as a checkbox exercise.

Where relevant map findings to:

- OWASP ASVS 5.x;
- OWASP API Security Top 10;
- CWE;
- CVSS 4.0;
- NIST SSDF;
- OpenSSF Scorecard;
- SLSA.

For each mapping explain:

```text
Finding
 → security property
 → relevant standard
 → evidence
```

Do not invent compliance claims.

---

# 26. Threat Model

Identify:

### External attackers

- anonymous internet users;
- malicious webhook senders;
- compromised GitHub/GitLab accounts;
- malicious repository contributors;
- malicious PR authors;
- malicious maintainers;
- compromised dependencies;
- malicious CI contributors.

### Trusted-but-dangerous inputs

- repository metadata;
- branch names;
- commit messages;
- PR titles;
- CI variables;
- GitLab job output;
- repository configuration.

### High-value assets

- GitHub App private key;
- GitHub PAT;
- GitHub installation tokens;
- GitLab tokens;
- repositories;
- CI infrastructure;
- Docker host;
- workflow definitions;
- published artifacts;
- bot identity.

---

# 27. Attack-Path Analysis

Construct concrete attack chains.

At minimum investigate:

### Attack Path A — Webhook authentication bypass

```text
Internet
 → webhook
 → missing/invalid authentication
 → privileged handler
 → privileged operation
```

### Attack Path B — Command injection

```text
Attacker-controlled field
 → parser
 → command construction
 → shell
 → bot host execution
```

### Attack Path C — Confused deputy

```text
Attacker
 → authenticated request
 → attacker-controlled resource identifier
 → privileged credential selection
 → privileged API operation
```

### Attack Path D — CI/supply-chain compromise

```text
Attacker-controlled input
 → workflow/image/configuration
 → privileged CI
 → credential-bearing environment
 → repository/artifact compromise
```

### Attack Path E — SSRF

```text
Attacker-controlled URL
 → bot HTTP client
 → internal destination
 → privileged/internal service
```

### Attack Path F — Credential exfiltration

```text
Secret
 → command/API/trace/log/artifact
 → attacker-visible location
```

For every path determine:

- prerequisites;
- exploitability;
- impact;
- evidence;
- mitigation;
- regression test.

---

# 28. Security Invariants

Define explicit invariants that must remain true.

At minimum:

```text
I1. Every privileged external entry point authenticates and fails closed.

I2. Authentication does not imply authorization.

I3. Every privileged operation authorizes the authenticated actor.

I4. Privileged credentials are never selected solely from caller-controlled identifiers.

I5. No attacker-controlled value is interpolated into a shell command.

I6. Repository, project, installation, and identity relationships are explicitly validated.

I7. Webhook signatures are verified before privileged processing.

I8. Missing authentication material is an error.

I9. Secrets never appear in argv, URLs, logs, traces, or public output.

I10. Attacker-controlled URLs cannot reach restricted network destinations.

I11. Attacker-controlled input cannot arbitrarily modify trusted CI/workflow configuration.

I12. Security-sensitive failures fail closed.

I13. Expensive privileged work is protected against unauthenticated abuse.

I14. Security fixes have regression tests.

I15. Security documentation reflects verified implementation state.
```

---

# 29. Risk Classification

Use:

### P0 — Critical / Stop-Ship

Examples:

- RCE;
- authentication bypass;
- authorization bypass;
- credential theft;
- arbitrary privileged repository modification;
- arbitrary privileged workflow execution;
- arbitrary trusted Docker image execution;
- exploitable privileged SSRF;
- major confused-deputy vulnerability.

### P1 — High

Examples:

- significant privilege escalation;
- sensitive information disclosure;
- meaningful resource exhaustion;
- weak resource authorization;
- replay enabling privileged actions;
- significant CI integrity weakness.

### P2 — Medium

Examples:

- defense-in-depth weaknesses;
- insufficient validation;
- weak error handling;
- incomplete rate limiting;
- non-critical secret handling weaknesses.

### P3 — Low

Examples:

- hardening opportunities;
- documentation gaps;
- maintainability improvements with limited security impact.

---

# 30. Stop-Ship Rules

The bot must **not** be described as production-secure while any exploitable P0 condition remains.

In particular:

```text
Critical/RCE                     → STOP
Authentication bypass            → STOP
Authorization bypass             → STOP
Command injection                → STOP
Credential exposure              → STOP
Arbitrary workflow modification  → STOP
Arbitrary privileged image       → STOP
Meaningful privileged SSRF       → STOP
Major confused deputy             → STOP
```

Do not downgrade a vulnerability merely because exploitation requires a GitHub/GitLab account unless that account requirement is itself a strong authorization boundary.

---

# 31. Regression Test Requirements

For every confirmed or high-confidence vulnerability, create a regression test.

At minimum test:

### Authentication

- missing GitHub signature;
- invalid GitHub signature;
- invalid SHA-256 signature;
- missing GitLab token;
- invalid GitLab token;
- missing minimizer secret;
- wrong minimizer secret.

### Injection

- `';id`;
- `$(id)`;
- backticks;
- `&&`;
- `||`;
- newline injection;
- special repository URL;
- special branch;
- invalid SHA;
- special pattern;
- malicious Docker image identifier.

Tests must prove that attacker-controlled data remains data.

---

# 32. Negative Security Tests

Explicitly include tests proving rejection.

Examples:

```text
missing authentication → 401/403
invalid authentication → 401/403
unauthorized actor → rejected
unauthorized repository → rejected
unknown installation → rejected
invalid SHA → rejected
private SSRF destination → rejected
metadata IP → rejected
oversized body → rejected
replayed webhook → rejected
malicious shell input → treated as literal data
```

Do not test only successful paths.

---

# 33. Documentation Architecture

Generate documentation that is easy to understand visually.

Use the following structure:

```text
docs/security/
├── README.md
├── architecture.md
├── threat-model.md
├── data-flow.md
├── authentication.md
├── authorization.md
├── credentials.md
├── command-execution.md
├── webhook-security.md
├── ci-cd-security.md
├── supply-chain.md
├── findings.md
├── remediation.md
├── verification.md
└── incident-response.md
```

If the repository maintainers prefer a single `security.md`, preserve that file but organize it into equivalent sections.

Do not create unnecessary documents solely to increase document count.

---

# 34. Required Visuals

Use diagrams only when they clarify security architecture.

Required:

### 1. System Context

Who communicates with the bot?

### 2. Trust Boundary

Where does trust change?

### 3. Data Flow

How does untrusted data reach privileged operations?

### 4. Credential Flow

Where are credentials created, stored, used, and exposed?

### 5. Authentication / Authorization Flow

```text
Request
 ↓
Authenticate
 ↓
Identify actor
 ↓
Authorize actor
 ↓
Authorize resource
 ↓
Validate parameters
 ↓
Perform privileged operation
```

### 6. Attack Flow

Show the most important confirmed vulnerabilities.

### 7. Remediated Architecture

Show how the corrected architecture differs from the vulnerable one.

---

# 35. Documentation Icon Vocabulary

Use a consistent icon vocabulary.

```text
👤 Human actor
🤖 Bot
🌐 Internet
🔐 Authentication
🛡️ Authorization
🔑 Secret/Credential
📦 Repository
⚙️ CI/CD
🐳 Container
💻 Host execution
💾 Data store
🔗 External service
⚠️ Risk
🚨 Critical finding
✅ Verified control
❌ Failed control
🧪 Security test
```

Do not use icons as decoration where they obscure meaning.

---

# 36. Security Control Matrix

Create:

| Control | Security Property | Implementation | Evidence | Test | Status | Risk if Missing |
|---|---|---|---|---|---|---|

Example:

| Control | Security Property | Status |
|---|---|---|
| GitHub signature verification | Webhook authenticity | Verified / Failed |
| GitLab secret validation | Webhook authenticity | Verified / Failed |
| Actor authorization | Privilege control | Verified / Failed |
| Shell-free subprocess execution | Command injection prevention | Verified / Failed |
| Resource binding | Confused-deputy prevention | Verified / Failed |
| SSRF destination policy | Network isolation | Verified / Failed |

---

# 37. Finding Template

Every finding must contain:

```text
ID
Title
Severity
Status
Affected component
Affected function/file
Attack surface
Security property violated
Threat actor
Preconditions
Technical explanation
Attack path
Evidence
Reproduction
Impact
Likelihood
CVSS 4.0
CWE
Relevant OWASP/standard mapping
Recommended remediation
Regression test
Verification evidence
Residual risk
```

Do not inflate severity without evidence.

---

# 38. Before / After Analysis

For every major vulnerability provide:

```text
BEFORE

Untrusted input
      ↓
Weak/missing control
      ↓
Privileged operation


AFTER

Untrusted input
      ↓
Authentication
      ↓
Authorization
      ↓
Resource binding
      ↓
Validation
      ↓
Safe execution
      ↓
Privileged operation
```

Explain the security property that changed.

---

# 39. Remediation Strategy

Prioritize architecture-level fixes.

Prefer:

```text
Remove dangerous primitive
```

over:

```text
Add another escaping layer
```

Examples:

```text
shell string
→ argv API

long-lived PAT
→ short-lived installation token

optional authentication
→ mandatory authentication

caller-selected credential
→ server-side identity/resource mapping

string JSON
→ structured JSON encoder

unrestricted URL
→ destination allowlist/policy

documentation claim
→ executable regression test
```

---

# 40. Independent Verification

If remediation is performed, perform a **separate verification pass**.

Do not assume:

```text
I recommended fix
→ I implemented fix
→ fix is correct
```

Instead:

```text
Original finding
      ↓
Remediation
      ↓
Fresh source review
      ↓
Regression test
      ↓
Negative test
      ↓
Attack-path retest
      ↓
Independent verification
```

Look specifically for:

- incomplete fixes;
- alternate attack paths;
- bypasses;
- inconsistent endpoint behavior;
- regressions;
- security checks applied after privileged work;
- fixes that only protect one code path.

---

# 41. Final Security Gates

Report four gates.

## Gate 0 — Unsafe

Any exploitable P0 remains.

Result:

> **NOT SAFE FOR PRODUCTION**

## Gate 1 — Secure Baseline

Require:

- P0 = 0;
- exploitable P1 = 0 for critical paths;
- authentication bypass = 0;
- authorization bypass = 0;
- command injection = 0;
- credential exposure = 0;
- arbitrary privileged workflow/image execution = 0.

## Gate 2 — Hardened

Additionally require:

- replay protection;
- rate/resource limits;
- SSRF defenses;
- secret rotation;
- security regression tests;
- resource binding;
- dependency/security scanning;
- appropriate supply-chain controls.

## Gate 3 — Assured

Additionally require, where appropriate:

- independent security review;
- SAST;
- SCA;
- secret scanning;
- OpenSSF Scorecard;
- supply-chain review;
- provenance/signing;
- incident-response readiness.

Do not claim certification or formal compliance unless an appropriate assessment has actually occurred.

---

# 42. Final Security Dashboard

Produce a concise dashboard:

| Area | Status | Critical Findings | High | Medium | Evidence |
|---|---|---:|---:|---:|---|
| Authentication | 🟢/🟡/🔴 | | | | |
| Authorization | | | | | |
| Resource Binding | | | | | |
| Webhooks | | | | | |
| Command Execution | | | | | |
| Git Operations | | | | | |
| Docker | | | | | |
| CI/CD | | | | | |
| Credentials | | | | | |
| SSRF | | | | | |
| API Security | | | | | |
| Supply Chain | | | | | |
| Abuse Resistance | | | | | |
| Error Handling | | | | | |
| Testing | | | | | |

---

# 43. Final Verdict

The final report must answer these questions explicitly:

### A. Is the bot currently safe to deploy?

Answer:

```text
YES
NO
CONDITIONAL
UNKNOWN
```

### B. What are the remaining exploitable attack paths?

List them.

### C. What privileged capabilities remain exposed?

List them.

### D. Which controls are verified?

List evidence.

### E. Which controls are only claimed?

List them.

### F. What must be fixed before production?

Give an ordered list.

### G. What can be deferred?

Give an ordered list.

### H. What residual risk remains after remediation?

Explain it.

### I. How confident are you?

Use:

```text
HIGH
MEDIUM
LOW
```

and explain why.

---

# 44. Important Distinction in Security Claims

Do not use vague claims such as:

> “The bot is secure.”

Prefer evidence-based claims such as:

> “The reviewed revision contains no verified P0 vulnerabilities in the assessed scope.”

or:

> “The bot satisfies the defined production security baseline for authentication, authorization, command execution, credential handling, and webhook verification.”

Only claim “industry standard,” “compliant,” or equivalent when the relevant standard has actually been assessed against its requirements.

---

# 45. Machine-Readable Summary

At the end produce a compact machine-readable summary containing:

```text
repository_revision
audit_date
scope
overall_status
confidence
p0_count
p1_count
p2_count
p3_count
confirmed_findings
verified_fixed_findings
unverified_findings
open_security_gates
security_invariants
required_preproduction_actions
deferred_hardening_actions
standards_reviewed
tests_executed
tests_failed
```

Do not fabricate fields for which evidence is unavailable.

---

# 46. Audit Output Order

Produce the final documentation in this order:

1. Executive Summary
2. Security Verdict
3. Architecture
4. System Context Diagram
5. Data-Flow Diagram
6. Trust Boundaries
7. Assets
8. Entry Points
9. Authentication
10. Authorization
11. Identity / Resource Binding
12. Command Execution
13. Git Security
14. Docker Security
15. CI/CD Security
16. Webhook Security
17. SSRF
18. Credential Security
19. API / Serialization Security
20. Abuse Resistance
21. Error Handling
22. Supply Chain
23. Threat Model
24. Attack Paths
25. Findings
26. Security Control Matrix
27. Regression Tests
28. Remediation Plan
29. Verification Results
30. Security Gates
31. Residual Risk
32. Incident / Disclosure Requirements
33. Machine-Readable Summary

Keep the executive summary concise. Put technical evidence deeper in the document.

---

# 47. Audit Quality Rules

Before finalizing, verify:

- [ ] Every public endpoint was identified.
- [ ] Every privileged operation was identified.
- [ ] Every credential was inventoried.
- [ ] Every credential-consuming operation was traced.
- [ ] Every shell execution path was inspected.
- [ ] Every attacker-controlled command argument was traced.
- [ ] Every webhook authentication path was tested.
- [ ] Authentication and authorization were evaluated separately.
- [ ] Resource/identity binding was evaluated.
- [ ] GitHub/GitLab permissions were reviewed.
- [ ] Docker/image selection was reviewed.
- [ ] CI/workflow mutation was reviewed.
- [ ] SSRF paths were reviewed.
- [ ] Replay was considered.
- [ ] Resource exhaustion was considered.
- [ ] Secret leakage paths were reviewed.
- [ ] Error handling was reviewed.
- [ ] Supply-chain implications were reviewed.
- [ ] Security invariants were defined.
- [ ] Critical findings have regression tests.
- [ ] Negative tests exist.
- [ ] Fixes were independently verified.
- [ ] Documentation reflects evidence rather than claims.
- [ ] No unsupported compliance claim was made.

---

# 48. Absolute Rules

1. **Do not trust `security.md` merely because it exists.**
2. **Do not trust previous audit results without re-verification.**
3. **Do not equate authentication with authorization.**
4. **Do not trust caller-controlled identity/resource selectors.**
5. **Do not interpolate attacker-controlled data into shell commands.**
6. **Do not allow missing authentication to become a successful request.**
7. **Do not treat security-sensitive exceptions as harmless.**
8. **Do not treat an attacker-controlled Docker image as harmless input.**
9. **Do not treat CI configuration as ordinary data when it can execute code.**
10. **Do not expose secrets through URLs, argv, logs, traces, artifacts, or public output.**
11. **Do not claim a vulnerability is fixed without evidence.**
12. **Do not downgrade a vulnerability simply because exploitation is inconvenient.**
13. **Do not create compliance paperwork that does not improve the security decision.**
14. **Prioritize exploitable security properties over documentation completeness.**
15. **Prefer architectural controls over fragile escaping or filtering.**
16. **Keep supply-chain security in scope wherever the bot can influence code, builds, images, workflows, or artifacts.**
17. **A successful security audit must demonstrate security properties, not merely produce a long report.**

---

# 49. Execution Strategy

Execute the work in distinct phases.

### Phase 1 — Read-only security revisit

No code changes.

Determine:

- actual architecture;
- actual attack surface;
- current vulnerabilities;
- whether previous findings still exist;
- whether previous fixes are actually effective.

### Phase 2 — Remediation

Only after Phase 1:

- fix P0/P1 findings;
- add regression tests;
- improve architecture;
- update security controls.

### Phase 3 — Independent verification

Treat the remediation as untrusted.

Repeat:

- source review;
- attack-path analysis;
- negative testing;
- regression testing;
- authorization review;
- command-execution review;
- credential-flow review.

### Phase 4 — Documentation

Only after verification:

- update security documentation;
- update diagrams;
- update control matrix;
- update risk register;
- record verified status;
- document residual risk.

The final documentation must describe the **verified state of the repository**, not the intended state.

---

# 50. Primary Success Criterion

The audit succeeds only if it can answer, with evidence:

> **“Can an untrusted actor cause this privileged bot to perform an action that the actor should not be able to cause?”**

For every meaningful path, demonstrate either:

```text
UNTRUSTED INPUT
      ↓
AUTHENTICATED
      ↓
AUTHORIZED
      ↓
RESOURCE-BOUND
      ↓
VALIDATED
      ↓
SAFE EXECUTION
      ↓
PRIVILEGED ACTION
```

or identify precisely where that chain breaks.

The most important output is therefore **not the number of pages, diagrams, or standards mapped**.

The most important output is:

> **A defensible, evidence-backed determination of whether the bot's privileged capabilities can be abused by an untrusted actor, together with verified remediation and regression evidence.**