# PR Plan: Generic Bot Refactoring

## Summary

This branch introduces a major refactoring to make the bot generic and configurable, moving away from hardcoded repository-specific logic. The main changes include:

### New Features

1. **Configuration System**: A new TOML-based configuration system that allows repository-specific settings to be defined in a configuration file, with support for:
   - Explicit repository configurations
   - Auto-detection via GitHub/GitLab APIs
   - Default values from TOML
   - Priority-based merging (Explicit > API > Defaults)

2. **Auto-Detection**: The bot can now automatically detect repository settings by querying GitHub and GitLab APIs:
   - GitLab domain and project mapping
   - Organization and team information
   - Label names
   - Installation IDs (cached from webhooks)

3. **Caching**: Auto-detection results are cached to avoid rate limits and improve performance.

4. **Generic Bot**: Removed repository-specific (rocq) hardcoded logic, making the bot work for any repository with proper configuration.

5. **GraphQL Enhancements**: Added query functions with timeout support and extended GitHub/GitLab query capabilities.

6. **Code Organization**: Better separation of concerns with generic functions moved to `bot-components` and clearer module structure.

### Removed Features

1. **Legacy PAT Support**: Removed Personal Access Token (PAT) installation method. The bot now requires GitHub App installation only.

2. **Repository-Specific Code**: Removed hardcoded checks for specific repositories (rocq), replaced with config-based logic.

---

## PR Breakdown

### PR 1: Code Organization - Move Generic Functions to bot-components
**Purpose**: Establish foundation by moving reusable functions to shared components.

**Changes**:
- Move generic functions from `src/helpers` to `bot-components/Utils`
- Move generic functions from actions to `bot-components`
- Split `CI_utils` and add `Bench_utils` for benchmark-related functions
- Organize `src` into different modules

**Files**:
- `bot-components/Utils.ml`, `bot-components/Utils.mli`
- `bot-components/Bench_utils.ml`, `bot-components/Bench_utils.mli`
- `bot-components/CI_utils.ml`, `bot-components/CI_utils.mli`
- Various files in `src/actions/` and `src/ci/`
- `bot-components/dune`

**Dependencies**: None

**Testing**: Ensure existing tests still pass

---

### PR 2: GraphQL Query Enhancements with Timeout Support
**Purpose**: Add timeout support to GraphQL queries and extend query capabilities.

**Changes**:
- Add timeout parameter to GitHub query functions
- Implement GitHub query functions with timeout (`GitHub_queries.ml`)
- Add GitLab query functions (`GitLab_queries.ml`)
- Extend GitHub and GitLab GraphQL query capabilities
- Update `GitHub_GraphQL.ml` and `GitLab_GraphQL.ml`

**Files**:
- `bot-components/GitHub_queries.ml`, `bot-components/GitHub_queries.mli`
- `bot-components/GitLab_queries.ml`, `bot-components/GitLab_queries.mli`
- `bot-components/GitHub_GraphQL.ml`
- `bot-components/GitLab_GraphQL.ml`
- `bot-components/GitHub_types.mli`
- `bot-components/GitLab_types.mli`

**Dependencies**: PR 1 (if using moved utilities)

**Testing**: Add tests for query functions with timeout

---

### PR 3: Remove Legacy PAT Support
**Purpose**: Clean up legacy code by removing Personal Access Token support.

**Changes**:
- Remove `github.api_token` configuration option
- Remove PAT-related code from `Github_installations.ml`
- Remove unused `string_of_installation_tokens` function
- Update documentation to reflect PAT removal
- Update README.md to mention PAT is no longer supported

**Files**:
- `bot-components/Github_installations.ml`
- `coqbot-config.toml`
- `example-config.toml`
- `README.md`
- Various files that referenced PAT

**Dependencies**: None (can be done independently)

**Testing**: Update tests to remove PAT-related test cases

---

### PR 4: Configuration System - Core Repository Configuration
**Purpose**: Implement the foundation of the configuration system with TOML parsing.

**Changes**:
- Add `repo_config.ml` and `repo_config.mli` with repository configuration types
- Add `default.ml` and `default.mli` for default value handling
- Implement TOML parsing for repository configurations
- Add support for parsing CI config, labels, jobs, and documentation from TOML
- Add helper functions for config lookup and validation

**Files**:
- `src/config/repo_config.ml`, `src/config/repo_config.mli`
- `src/config/default.ml`, `src/config/default.mli`
- `src/config/config.ml`, `src/config/config.mli` (updates)
- `src/config/dune`
- `coqbot-config.toml`, `example-config.toml` (add default section)

**Dependencies**: None

**Testing**: Add unit tests for TOML parsing (`repo_config_test.ml`)

---

### PR 5: Configuration System - Auto-Detection and Caching
**Purpose**: Add API-based auto-detection with caching to reduce API calls.

**Changes**:
- Add `auto_detection.ml` and `auto_detection.mli` for API-based detection
- Add `cache.ml` and `cache.mli` for caching auto-detection results
- Implement GitLab domain auto-detection
- Implement organization and team auto-detection
- Implement label auto-detection (optional, non-blocking)
- Add caching with TTL (1 hour)

**Files**:
- `src/config/auto_detection.ml`, `src/config/auto_detection.mli`
- `src/config/cache.ml`, `src/config/cache.mli`
- `bot-components/GitLab_queries.ml` (if not in PR 2)

**Dependencies**: PR 2 (GitHub/GitLab queries), PR 4 (repo_config types)

**Testing**: Add tests for auto-detection (`auto_detection_test.ml`, `cache_test.ml`)

---

### PR 6: Configuration System - Config Resolver with Priority Merging
**Purpose**: Implement the config resolution logic that merges explicit, auto-detected, and default values.

**Changes**:
- Add `config_resolver.ml` and `config_resolver.mli`
- Implement priority-based merging (Explicit > API > TOML Defaults)
- Add logic to determine when auto-detection is needed
- Integrate with auto-detection and cache modules

**Files**:
- `src/config/config_resolver.ml`, `src/config/config_resolver.mli`
- `src/config/config.ml` (updates to use resolver)

**Dependencies**: PR 4, PR 5

**Testing**: Add tests for config resolution (`config_resolver_test.ml`, `config_timeout_test.ml`)

---

### PR 7: Make Bot Generic - Merge job_status_rocq into job_status
**Purpose**: Remove repository-specific code by making job status handling generic.

**Changes**:
- Merge `job_status_rocq.ml` functionality into `job_status.ml`
- Remove rocq-specific naming from functions
- Make job status functions generic
- Update all callers to use generic functions

**Files**:
- `src/ci/job_status.ml`, `src/ci/job_status.mli`
- `src/ci/job_status_rocq.ml`, `src/ci/job_status_rocq.mli` (deleted)
- `src/ci/dune`
- Files that call job_status functions

**Dependencies**: None (can be done independently)

**Testing**: Add tests for generic job status (`job_status_custom_test.ml`)

---

### PR 8: Integration - Replace Hardcoded Values in Webhooks
**Purpose**: Replace hardcoded repository checks in webhook handlers with config-based logic.

**Changes**:
- Update `webhooks/github.ml` to use repo_config instead of hardcoded checks
- Add installation ID caching from webhooks
- Update `webhooks/gitlab.ml` if needed
- Update `webhooks/scheduled.ml` if needed

**Files**:
- `src/webhooks/github.ml`, `src/webhooks/github.mli`
- `src/webhooks/gitlab.ml`, `src/webhooks/gitlab.mli`
- `src/webhooks/scheduled.ml`, `src/webhooks/scheduled.mli`
- `src/bot.ml` (updates to pass config)

**Dependencies**: PR 4, PR 6

**Testing**: Update webhook tests, add tests for installation ID caching

---

### PR 9: Integration - Replace Hardcoded Values in Actions (Part 1)
**Purpose**: Replace hardcoded repository checks in action handlers (backport and job).

**Changes**:
- Update `actions/backport.ml` to use repo_config
- Update `actions/job.ml` to use repo_config
- Remove hardcoded repository checks

**Files**:
- `src/actions/backport.ml`, `src/actions/backport.mli`
- `src/actions/job.ml`, `src/actions/job.mli`

**Dependencies**: PR 4, PR 6

**Testing**: Update action tests

---

### PR 10: Integration - Replace Hardcoded Values in Actions (Part 2)
**Purpose**: Replace hardcoded repository checks in pr_sync action.

**Changes**:
- Update `actions/pr_sync.ml` to use repo_config
- Remove hardcoded repository checks

**Files**:
- `src/actions/pr_sync.ml`, `src/actions/pr_sync.mli`

**Dependencies**: PR 4, PR 6

**Testing**: Update pr_sync tests

---

### PR 11: Integration - Replace Hardcoded Values in CI and Utils
**Purpose**: Replace hardcoded repository checks in CI documentation and bench utils.

**Changes**:
- Update `ci/documentation.ml` to use repo_config
- Update `utils/bench.ml` to use repo_config
- Remove hardcoded repository checks
- Add fallback to original hardcoded values for backward compatibility (if needed)

**Files**:
- `src/ci/documentation.ml`, `src/ci/documentation.mli`
- `src/utils/bench.ml`, `src/utils/bench.mli`
- `src/utils/coq.ml` (if needed)
- `src/utils/dune`

**Dependencies**: PR 4, PR 6

**Testing**: Update CI and bench tests

---

### PR 12: Testing Infrastructure and Test Helpers
**Purpose**: Set up testing infrastructure and consolidate test helpers.

**Changes**:
- Merge test helpers into `test_helpers.ml`
- Add Alcotest setup
- Organize test files into proper directories
- Move `test_webhook.ml` to `tests/components/`
- Add `test_bot_info.ml` in `tests/components/`

**Files**:
- `tests/test_helpers.ml`
- `tests/components/test_webhook.ml` (moved)
- `tests/components/test_bot_info.ml`
- `tests/dune` (updates)

**Dependencies**: None (can be done early)

**Testing**: Ensure all tests use the new helpers

---

### PR 13: Configuration System Tests
**Purpose**: Add comprehensive tests for the configuration system.

**Changes**:
- Add tests for repo_config parsing (`repo_config_test.ml`)
- Add tests for error cases (`repo_config_error_test.ml`)
- Add property-based tests (`repo_config_property_test.ml`)
- Add integration tests (`repo_config_integration_test.ml`)
- Add tests for default config (`default_config_test.ml`)
- Add test configuration files

**Files**:
- `tests/config/repo_config_test.ml`
- `tests/config/repo_config_error_test.ml`
- `tests/config/repo_config_property_test.ml`
- `tests/config/repo_config_integration_test.ml`
- `tests/config/default_config_test.ml`
- `tests/config/test-config.toml`
- `tests/config/test-default-config.toml`
- `tests/dune` (updates)

**Dependencies**: PR 4, PR 5, PR 6, PR 12

**Testing**: All new tests should pass

---

### PR 14: Integration and Demo Tests
**Purpose**: Add integration tests to demonstrate how the bot works with the new configuration system.

**Changes**:
- Add integration tests (`integration_test.ml`)
- Add demo tests (`generic_bot_demo_test.ml`)
- Add edge case tests (`refactored_code_edge_cases_test.ml`)
- Test minimizer URL configuration with env var and TOML

**Files**:
- `tests/integration/integration_test.ml`
- `tests/integration/generic_bot_demo_test.ml`
- `tests/integration/refactored_code_edge_cases_test.ml`
- `tests/dune` (updates)

**Dependencies**: PR 8, PR 9, PR 10, PR 11 (all integration PRs)

**Testing**: All integration tests should pass

---

### PR 15: Make Minimizer URL Configurable
**Purpose**: Allow minimizer URL to be configured via both environment variable and TOML.

**Changes**:
- Make minimizer_url configurable in TOML
- Support environment variable `BOT_MINIMIZER_URL`
- Update `ci/minimization.ml` to use config
- Update default config handling

**Files**:
- `src/config/default.ml` (updates)
- `src/ci/minimization.ml`
- `coqbot-config.toml`, `example-config.toml`

**Dependencies**: PR 4, PR 6

**Testing**: Add tests for minimizer URL configuration

---

### PR 16: GraphQL Schema Updates
**Purpose**: Update GraphQL schemas to match latest API changes.

**Changes**:
- Update `github-schema.json` with latest schema
- Update `gitlab-schema.json` with latest schema
- Regenerate types if needed

**Files**:
- `bot-components/github-schema.json`
- `bot-components/gitlab-schema.json`

**Dependencies**: PR 2 (if schema changes are related to new queries)

**Testing**: Ensure all GraphQL queries still work

---

### PR 17: Final Cleanup and Polish
**Purpose**: Fix any remaining issues, remove duplicate code, and finalize the refactoring.

**Changes**:
- Remove duplicate test files
- Fix any compilation errors
- Simplify comments
- Remove TODO comments that are no longer relevant
- Update `coqbot-config.toml` to use TOML defaults instead of `default.ml`
- Fix any test failures
- Format code consistently

**Files**:
- Various files with cleanup
- `src/config/default.ml` (finalize default value handling)
- Remove `tests/test_config.ml`, `tests/test_pat_usage.ml` if still present

**Dependencies**: All previous PRs

**Testing**: All tests should pass

---

## PR Dependency Graph

```
PR 1 (Code Organization)
  └─> PR 2 (GraphQL Queries) [optional dependency]

PR 2 (GraphQL Queries)
  └─> PR 5 (Auto-Detection)

PR 4 (Core Config)
  └─> PR 5 (Auto-Detection)
  └─> PR 6 (Config Resolver)

PR 5 (Auto-Detection)
  └─> PR 6 (Config Resolver)

PR 6 (Config Resolver)
  └─> PR 8 (Webhooks Integration)
  └─> PR 9 (Actions Part 1)
  └─> PR 10 (Actions Part 2)
  └─> PR 11 (CI/Utils Integration)
  └─> PR 15 (Minimizer URL)

PR 12 (Test Infrastructure)
  └─> PR 13 (Config Tests)

PR 8, 9, 10, 11 (All Integration PRs)
  └─> PR 14 (Integration Tests)

All PRs
  └─> PR 17 (Final Cleanup)
```

## Notes

- PR 3 (Remove PAT) can be done independently and early
- PR 7 (Generic job_status) can be done independently
- PR 12 (Test Infrastructure) should be done early to support other test PRs
- Integration PRs (8-11) can be done in parallel once PR 6 is merged
- PR 16 (Schema Updates) can be done at any time but should be tested with PR 2
- Each PR should be small enough for one person to review comfortably
- Tests should be added alongside features, not as separate PRs (except for comprehensive test suites)
