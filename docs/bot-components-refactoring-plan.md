# Bot Components Refactoring Plan

## Current Structure

The bot-components directory is now organized into the following structure:

```
bot-components/
├── Bot_components.ml          # Wrapper module re-exporting all modules
├── dune                       # Main dune build file
├── github/                    # GitHub-specific modules
│   ├── dune
│   ├── GitHub_app.ml/i
│   ├── GitHub_automation.ml/i
│   ├── GitHub_GitLab_sync.ml/i
│   ├── GitHub_GraphQL.ml
│   ├── GitHub_ID.ml/i
│   ├── GitHub_installations.ml/i
│   ├── GitHub_mutations.ml/i
│   ├── GitHub_queries.ml/i
│   ├── GitHub_subscriptions.ml/i
│   ├── GitHub_types.mli
│   └── github-schema.json
├── gitlab/                    # GitLab-specific modules
│   ├── dune
│   ├── GitLab_GraphQL.ml
│   ├── GitLab_mutations.ml/i
│   ├── GitLab_queries.ml/i
│   ├── GitLab_subscriptions.ml/i
│   ├── GitLab_types.mli
│   └── gitlab-schema.json
├── graphql/                   # GraphQL core infrastructure
│   ├── GraphQL_query.ml/i
├── utils/                     # General utility modules
│   ├── Utils.ml/i
│   ├── String_utils.ml/i
│   ├── HTTP_utils.ml/i
│   ├── Git_utils.ml/i
│   └── Minimize_parser.ml/i
├── ci/                        # CI utilities
│   ├── pipeline.ml/i         # Pipeline summary and error formatting
└── core/                      # Core types and bot info
    └── Bot_info.ml/i
```

### Module Organization Notes:
- **github/**: All GitHub API interaction modules, including GraphQL queries, mutations, subscriptions, and app management
- **gitlab/**: All GitLab API interaction modules
- **graphql/**: Core GraphQL query infrastructure shared by GitHub and GitLab
- **utils/**: General-purpose utility modules used across the codebase
- **ci/**: CI-related utilities (currently contains pipeline utilities, renamed from CI_utils)
- **core/**: Core bot information and configuration types

## Proposed Structure

```
bot-components/
├── github/              # GitHub-specific modules
│   ├── GitHub_app.ml/i
│   ├── GitHub_automation.ml/i
│   ├── GitHub_GitLab_sync.ml/i
│   ├── GitHub_GraphQL.ml
│   ├── GitHub_ID.ml/i
│   ├── Github_installations.ml/i
│   ├── GitHub_mutations.ml/i
│   ├── GitHub_queries.ml/i
│   ├── GitHub_subscriptions.ml/i
│   ├── GitHub_types.mli
│   └── github-schema.json
├── gitlab/              # GitLab-specific modules
│   ├── GitLab_GraphQL.ml
│   ├── GitLab_mutations.ml/i
│   ├── GitLab_queries.ml/i
│   ├── GitLab_subscriptions.ml/i
│   ├── GitLab_types.mli
│   └── gitlab-schema.json
├── graphql/             # GraphQL core infrastructure
│   └── GraphQL_query.ml/i
├── utils/               # General utility modules
│   ├── Utils.ml/i
│   ├── String_utils.ml/i
│   ├── HTTP_utils.ml/i
│   ├── Git_utils.ml/i
│   └── Minimize_parser.ml/i
├── ci/                  # CI and benchmark utilities
│   ├── CI_utils.ml/i
│   └── Bench_utils.ml/i
├── core/                # Core types and bot info
│   └── Bot_info.ml/i
└── dune                 # Main dune file (at root)
```

## Implementation Steps

### ✅ Step 1: Create directory structure
Created the new directories: `github/`, `gitlab/`, `graphql/`, `utils/`, `ci/`, `core/`

### ✅ Step 2: Move GitHub modules
Moved all GitHub-related files to `github/` subdirectory.

### ✅ Step 3: Move GitLab modules  
Moved all GitLab-related files to `gitlab/` subdirectory.

### ✅ Step 4: Move GraphQL core
Moved `GraphQL_query.ml/i` to `graphql/` subdirectory.

### ✅ Step 5: Move utility modules
Moved utility files to `utils/` subdirectory.

### ✅ Step 6: Move CI utilities
Moved `CI_utils.ml/i` and `Bench_utils.ml/i` to `ci/` subdirectory.

### ✅ Step 7: Move core modules
Moved `Bot_info.ml/i` to `core/` subdirectory.

### ✅ Step 8: Update dune file
Updated the `dune` file to:
- Added `(wrapped false)` to maintain flat module names
- Updated preprocessor paths for schema files to point to subdirectories
- Created separate `dune` files in `github/` and `gitlab/` for schema generation rules
- Removed explicit module specifications to allow Dune auto-discovery

### ✅ Step 9: Create wrapper module
Created `Bot_components.ml` at the root to re-export all modules. This is necessary because with `(wrapped false)` and subdirectories, Dune doesn't automatically create a `Bot_components` module that the code expects when using `open Bot_components`.

### ✅ Step 10: Verify module references
With the wrapper module, all `open Bot_components` statements continue to work, and submodules can be accessed as `Bot_components.Utils`, `Bot_components.Bot_info`, etc.

### ✅ Step 11: Build verification
Verified that the project builds successfully with the new structure. The "Unbound module Bot_components" errors are resolved.

## Implementation Complete ✅

The refactoring has been completed successfully. All files have been organized into logical subdirectories, and the build system has been updated to work with the new structure.

### Key Changes Made:
1. **Directory Structure**: Created 6 subdirectories (github, gitlab, graphql, utils, ci, core)
2. **Dune Configuration**: 
   - Added `(wrapped false)` to maintain backward compatibility with existing code
   - Updated schema file paths in preprocessor configuration
   - Created separate dune files in `github/` and `gitlab/` for schema generation
   - Removed explicit module specifications to allow Dune auto-discovery
3. **Module Names**: With `(wrapped false)`, all module names remain flat, so no changes were needed to `open` statements throughout the codebase

### Benefits:
- Better organization: Related modules are grouped together
- Easier navigation: Clear separation between GitHub, GitLab, utilities, etc.
- Maintained compatibility: All existing code continues to work without changes
- Scalability: Easier to add new modules in the appropriate directories
