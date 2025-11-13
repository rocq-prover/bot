# Generic Bot Architecture Design

## Overview

The bot is a **fully generic, configuration-driven system** where all repository-specific behavior is controlled through TOML configuration. **Rocq is just a configured instance**, not special code.

## Core Design Principles

1. **No Hardcoded Patterns**: All detection via configuration or APIs
2. **Configuration-Driven**: Repository features enabled via TOML, not code
3. **3-Tier Resolution**: Explicit TOML > API Auto-Detection > Generic Defaults
4. **Feature Flags**: Features enabled/disabled via configuration values

## Architecture Workflow

### Startup Flow

```mermaid
graph TD
    A[Bot Startup] --> B[Load TOML Config File]
    B --> C[Parse Bot-Level Config]
    C --> D[Create bot_info]
    D --> E[Parse Repository Configs]
    E --> F[Create repo_config_table]
    F --> G[Start Webhook Server]
    G --> H[Wait for Events]
    
    C --> C1[bot.name<br/>bot.email<br/>bot.api_timeout]
    C --> C2[github.app_id<br/>github.api_token]
    C --> C3[gitlab.* instances]
    
    E --> E1[repositories.* sections]
    E --> E2[Parse explicit configs]
    
    style D fill:#e1f5ff,stroke:#333,stroke-width:2px,font-weight:bold
    style F fill:#e1f5ff,stroke:#333,stroke-width:2px,font-weight:bold
```

### Webhook Event Processing Flow

```mermaid
graph TD
    A[Webhook Received] --> B{Event Type?}
    B -->|GitHub Push| C[Extract owner/repo]
    B -->|GitHub Comment| D[Extract owner/repo]
    B -->|GitLab Job/Pipeline| E[Map GitLab URL to GitHub]
    
    C --> F[Get Repo Config]
    D --> F
    E --> F
    
    F --> G{Config Found?}
    G -->|Yes| H[Resolve Config]
    G -->|No| I[Ignore Event]
    
    H --> J[3-Tier Resolution]
    J --> K[Execute Action]
    
    J --> J1[Explicit TOML]
    J --> J2[API Auto-Detection]
    J --> J3[Generic Defaults]
    
    K --> K1[Backport<br/>if project_number set]
    K --> K2[GitLab Mirror<br/>if gitlab_domain set]
    K --> K3[Minimization<br/>if minimizer_url set]
    K --> K4[Custom Job Status<br/>if custom_job_status=true]
    
    style H fill:#e1f5ff,stroke:#333,stroke-width:2px,font-weight:bold
    style J fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style K fill:#e8f5e9,stroke:#333,stroke-width:2px,font-weight:bold
```

### Configuration Resolution Flow

```mermaid
graph TD
    A[Webhook Event<br/>owner/repo] --> B[Get Explicit Config<br/>from TOML]
    B --> C{Explicit Config<br/>Complete?}
    
    C -->|Yes| D[Skip Auto-Detection]
    C -->|No| E[Check Cache]
    
    E --> F{Cached?}
    F -->|Yes| G[Use Cached Config]
    F -->|No| H[Run API Auto-Detection]
    
    H --> H1[Detect GitLab Domain]
    H --> H2[Detect Org/Team]
    H --> H3[Detect Labels]
    H --> H4[Cache Results]
    
    D --> I[Merge Configs]
    G --> I
    H4 --> I
    
    I --> J[Apply Defaults]
    J --> K[Final Resolved Config]
    
    I --> I1[Priority:<br/>Explicit > API > Defaults]
    
    style B fill:#e1f5ff,stroke:#333,stroke-width:2px,font-weight:bold
    style H fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style J fill:#e8f5e9,stroke:#333,stroke-width:2px,font-weight:bold
    style K fill:#f3e5f5,stroke:#333,stroke-width:2px,font-weight:bold
```

**Step-by-Step Explanation:**

1. **Webhook Event (owner/repo)**: A webhook arrives (push, comment, etc.) with owner and repo identifiers.

2. **Get Explicit Config from TOML**: Look up `repo_config_table` to find explicit configuration entry for this repository.

3. **Explicit Config Complete?**: Check if required fields (`gitlab_domain`, `org_name`) are present.
   - **Yes** -> Skip auto-detection (use explicit config)
   - **No** -> Proceed to auto-detection

4. **Check Cache** (if explicit config incomplete): Query in-memory cache for previous auto-detection result for this repository.

5. **Cached?**: Check if valid cached result exists (< 1 hour old).
   - **Yes** -> **Use Cached Config**: Return cached auto-detection result immediately, avoiding API calls. This improves performance and reduces rate limit usage.
   - **No** -> **Run API Auto-Detection**: Make GitHub/GitLab API calls to detect missing values.

6. **Run API Auto-Detection** (if not cached):
   - **Detect GitLab Domain**: Search all configured GitLab instances for matching project
   - **Detect Org/Team**: Query GitHub API for organization and team information
   - **Detect Labels**: Fetch repository labels from GitHub API
   - **Cache Results**: Store detected config with timestamp (TTL: 1 hour)

7. **Merge Configs**: Combine explicit TOML config, auto-detected (or cached) values, and defaults with priority: **Explicit > API/Cached > Defaults**.

8. **Apply Defaults**: Fill any remaining missing fields with generic defaults (e.g., `team_name = "maintainers"`).

9. **Final Resolved Config**: Complete configuration ready for use by bot features.

**What "Cached? Yes" Means:**
- A previous auto-detection result exists for this repository and is still valid (< 1 hour old)
- The cached config is returned immediately without making API calls
- This reduces API rate limit usage and improves response time

**Example Flow:**
- **First request** for `my-org/my-repo`: No cache -> API calls -> Cache result
- **Second request** within 1 hour: Cache hit -> Use cached result -> No API calls

### Feature Execution Flow

```mermaid
graph TD
    A[Resolved Config] --> B{Feature Checks}
    
    B --> C{github_project_number<br/>set?}
    C -->|Yes| D[Enable Backport]
    C -->|No| E[Skip Backport]
    
    B --> F{gitlab_domain<br/>set?}
    F -->|Yes| G[Enable GitLab Mirror]
    F -->|No| H[Skip Mirror]
    
    B --> I{minimizer_url<br/>set?}
    I -->|Yes| J[Enable Minimization]
    I -->|No| K[Skip Minimization]
    
    B --> L{jobs.custom_job_status<br/>= true?}
    L -->|Yes| M[Enable Custom Job Status]
    L -->|No| N[Use Default Job Status]
    
    B --> O{jobs.bench<br/>set?}
    O -->|Yes| P[Enable Bench Detection]
    O -->|No| Q[Skip Bench]
    
    D --> R[Execute Actions]
    G --> R
    J --> R
    M --> R
    P --> R
    
    style C fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style F fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style I fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style L fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style O fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style R fill:#e8f5e9,stroke:#333,stroke-width:2px,font-weight:bold
```

### Step-by-Step Setup Process

```mermaid
graph LR
    A[Add Repo to TOML] --> B[Minimal Config]
    B --> C[Bot Auto-Detects]
    C --> D[Defaults Applied]
    D --> E[Repo Works]
    
    E --> F{Need More Features?}
    F -->|Yes| G[Add Feature Config]
    F -->|No| H[Done]
    
    G --> I[Restart Bot]
    I --> E
    
    style B fill:#e1f5ff,stroke:#333,stroke-width:2px,font-weight:bold
    style C fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style D fill:#e8f5e9,stroke:#333,stroke-width:2px,font-weight:bold
    style E fill:#f3e5f5,stroke:#333,stroke-width:2px,font-weight:bold
```

## Real Application Flow Examples

### Example 1: Push Event (GitLab Mirror)

```mermaid
sequenceDiagram
    participant GH as GitHub
    participant Bot as Bot Server
    participant Config as Config Resolver
    participant GL as GitLab
    
    GH->>Bot: Push Event (rocq-prover/rocq)
    Bot->>Config: get_repo_config("rocq-prover", "rocq")
    Config->>Config: Check TOML
    Config-->>Bot: Config found (gitlab_domain=gitlab.inria.fr)
    Bot->>Bot: Check gitlab_domain is set
    Bot->>GL: Mirror branch to GitLab
    GL-->>Bot: Success
    Bot-->>GH: OK
```

**Code Flow:**
1. Webhook received -> `handle_push_event_for_repos`
2. `get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq"` -> Returns config
3. Check `config.gitlab_domain` -> `Some "gitlab.inria.fr"`
4. Execute `mirror_action` with config values
5. No hardcoded checks - works for any repo with `gitlab_domain` set

### Example 2: Comment Event (Minimization)

```mermaid
sequenceDiagram
    participant User as User
    participant GH as GitHub
    participant Bot as Bot Server
    participant Config as Config Resolver
    participant Minimizer as Minimizer Service
    
    User->>GH: Comment "@coqbot minimize ..."
    GH->>Bot: Comment Created Event
    Bot->>Config: get_repo_config(owner, repo)
    Config-->>Bot: Config (minimizer_url=Some url)
    Bot->>Bot: Parse minimize command
    Bot->>Bot: Check minimizer_url is Some
    Bot->>Minimizer: Run minimization
    Minimizer-->>Bot: Results
    Bot->>GH: Post results comment
```

**Code Flow:**
1. Comment received -> `handle_comment_created`
2. `get_repo_config_opt` -> Returns config
3. Extract `config.minimizer_url`
4. If `Some url` -> Execute minimization
5. If `None` -> Return "feature not configured"
6. No hardcoded repository checks

### Example 3: Backport Feature

```mermaid
sequenceDiagram
    participant GH as GitHub
    participant Bot as Bot Server
    participant Config as Config Resolver
    participant Project as GitHub Project
    
    GH->>Bot: Push Event (rocq-prover/rocq)
    Bot->>Config: get_repo_config("rocq-prover", "rocq")
    Config-->>Bot: Config (github_project_number=Some 11)
    Bot->>Bot: Check project_number is Some
    Bot->>Project: Create backport card
    Project-->>Bot: Success
```

**Code Flow:**
1. Push event -> `handle_push_event_for_repos`
2. Config resolution -> `config.github_project_number = Some 11`
3. Backport action checks: `if Option.is_some config.github_project_number`
4. Creates project card using project number from config
5. Works for any repo with `github_project_number` set

## Configuration Priority Examples

### Example: minimizer_url Resolution

```mermaid
graph TD
    A[minimizer_url Request] --> B{TOML has<br/>minimizer_url?}
    B -->|Yes| C[Use TOML Value]
    B -->|No| D{Env Var<br/>BOT_MINIMIZER_URL?}
    D -->|Yes| E[Use Env Var]
    D -->|No| F[Use None]
    
    C --> G[Final: TOML Value]
    E --> G
    F --> G
    
    style C fill:#e8f5e9,stroke:#333,stroke-width:2px,font-weight:bold
    style E fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style F fill:#ffebee,stroke:#333,stroke-width:2px,font-weight:bold
    style G fill:#f3e5f5,stroke:#333,stroke-width:2px,font-weight:bold
```

**Priority Order:**
1. **TOML** `[repositories.rocq] minimizer_url = "https://toml-url.com"`  (Wins)
2. **Env Var** `BOT_MINIMIZER_URL=https://env-url.com` (if TOML not set)
3. **None** (if neither set)

## Test Architecture and Flow

### Test Helper Flow

```mermaid
graph TD
    A[Test Helper Functions] --> B[create_mock_bot_info]
    A --> C[create_real_bot_info]
    A --> D[create_test_config]
    A --> E[repo_config_testable]
    A --> F[check_raises_failure]
    
    B --> B1[Hardcoded Test Values<br/>No API Calls]
    C --> C1[From Environment Variables<br/>Real API Access]
    D --> D1[Create Repo_config.t<br/>For Testing]
    E --> E1[Alcotest Testable<br/>For Config Comparison]
    F --> F1[Verify Exception<br/>Error Handling]
    
    B1 --> G[Fast Unit Tests]
    C1 --> H[Integration Tests]
    D1 --> I[All Test Types]
    E1 --> I
    F1 --> J[Error Tests]
    
    style B fill:#e1f5ff,stroke:#333,stroke-width:2px,font-weight:bold
    style C fill:#fff4e1,stroke:#333,stroke-width:2px,font-weight:bold
    style D fill:#e8f5e9,stroke:#333,stroke-width:2px,font-weight:bold
```


### Test Logic Flow: Configuration Resolution Test

```mermaid
sequenceDiagram
    participant Test as Test Case
    participant Helper as Test Helpers
    participant Resolver as Config Resolver
    participant Default as Default Config
    participant Auto as Auto Detection
    
    Test->>Helper: create_mock_bot_info()
    Helper-->>Test: bot_info
    
    Test->>Test: Create explicit_config
    Test->>Resolver: resolve_repo_config(bot_info, explicit_config)
    
    Resolver->>Default: get_defaults(owner, repo)
    Default-->>Resolver: defaults
    
    Resolver->>Resolver: Check if auto-detection needed
    alt Missing Fields
        Resolver->>Auto: auto_detect_from_apis()
        Auto-->>Resolver: auto_detected
    else Complete Config
        Resolver->>Resolver: Skip auto-detection
    end
    
    Resolver->>Resolver: Merge: explicit > auto > defaults
    Resolver-->>Test: resolved_config
    
    Test->>Test: Assert resolved_config values
    Test->>Test: Verify priority order
```
