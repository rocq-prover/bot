# Bot Logging Guide

## Running the Bot with Logs

When you run the bot using `run-bot.sh`, all logs are printed to **stdout** and **stderr**. The bot uses `Lwt_io.printf`, `Lwt_io.printl`, and `Stdio.printf` for logging.

### Basic Usage

```bash
./run-bot.sh
```

This will show all logs in your terminal. To save logs to a file:

```bash
./run-bot.sh 2>&1 | tee bot.log
```

Or redirect to a file:

```bash
./run-bot.sh > bot.log 2>&1
```

## Key Log Messages to Watch For

### 1. **GitHub Push Events** (Commits/Pushes)

When the bot processes push events, you'll see:

```
Processing push event for rocq-prover/rocq.
Initializing repository...
Bare repository initialized.
Merge and backport commit messages:
Push to main/master branch, analyzing merge commits.
PR #123 was merged.
Backporting to v8.18 was requested.
```

**Location**: `src/webhooks/github.ml` and `src/actions/backport.ml`

### 2. **PR Comments** (Bot Posting Comments)

When the bot posts comments on PRs, you'll see:

```
Posted a new comment: https://github.com/rocq-prover/rocq/pull/123#issuecomment-...
```

**For successful comment posting**, look for:
- `Posted a new comment: <url>` - Success message (from `Utils.report_on_posting_comment`)
- `Error while posting a comment: <error>` - Failure message

**Other comment-related logs**:
```
Pushing a status check...
Authorized user: pushing to GitLab.
Pull request rocq-prover/rocq#123 was (re)opened / synchronized: (force-)pushing to GitLab.
```

**Location**: `src/actions/pr_sync.ml`, `src/utils/helpers.ml`, `bot-components/Utils.ml`

### 3. **Status Checks** (CI Job Updates)

When the bot updates GitHub status checks:

```
Pushing a status check...
Job is allowed to fail.
Failed job 12345 of project 67890.
Failure reason: script failure
Actual failure.
```

**Location**: `src/ci/job_status.ml`, `src/actions/job.ml`

### 4. **Backport Actions**

When backporting PRs:

```
Merge and backport commit messages:
PR #123 was merged.
Backporting to v8.18 was requested.
Pull request rocq-prover/rocq#123 found in project 11. Updating its fields.
PR #456 was backported.
```

**Location**: `src/actions/backport.ml`

### 5. **GitLab Mirroring**

When syncing GitHub to GitLab:

```
Initializing repository...
Bare repository initialized.
Executing command: git fetch --quiet -fu ...
Processing push event on rocq-prover/rocq repository: mirroring branch on GitLab.
```

**Location**: `src/webhooks/github.ml`, `bot-components/Git_utils.ml`

## Filtering Logs

### View Only GitHub Actions

```bash
./run-bot.sh 2>&1 | grep -E "(PR #|Processing push|Pushing|Comment|Backport)"
```

### View Only Errors

```bash
./run-bot.sh 2>&1 | grep -i error
```

### View Specific Repository

```bash
./run-bot.sh 2>&1 | grep "rocq-prover/rocq"
```

### View Real-time Logs with Timestamps

```bash
./run-bot.sh 2>&1 | while IFS= read -r line; do echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done
```

## Important Log Functions

The bot uses these logging functions:

1. **`Lwt_io.printf`** - Async printf (most common)
2. **`Lwt_io.printl`** - Async print with newline
3. **`Lwt_io.printlf`** - Async printf with newline and flush
4. **`Stdio.printf`** - Synchronous printf (used in some places)
5. **`Utils.report_on_posting_comment`** - Reports when comments are posted

## Example: Monitoring Bot Activity

To monitor the bot in real-time and see all GitHub actions:

```bash
# Terminal 1: Run bot with filtered logs
./run-bot.sh 2>&1 | grep -E "(Processing|PR #|Pushing|Comment|Backport|Error)" --color=always

# Terminal 2: Watch full logs
tail -f bot.log
```

## Configuration Loading Logs

When the bot starts, you should see configuration being loaded (if auto-detection runs):

```
Running auto-detection for owner/repo
Skipping auto-detection for rocq-prover/rocq (explicit config present)
```

**Location**: `src/config/config_resolver.ml`, `src/config/auto_detection.ml`

## Troubleshooting

### No Logs Appearing?

1. Check if the bot is actually running: `ps aux | grep bot.exe`
2. Check if webhooks are being received (look for "Request received" messages)
3. Verify the bot has proper credentials and can access GitHub/GitLab APIs

### Too Many Logs?

Use filtering (see above) or adjust log levels by modifying the source code.

## Log File Locations

If running in production (e.g., Heroku), logs are typically available via:
- Heroku: `heroku logs --tail --app your-app-name`
- Docker: Check container logs: `docker logs <container-id>`
- Systemd: `journalctl -u bot-service -f`

