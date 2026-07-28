# Meeting Notes - 24-1

## Heroku Setup

- Create a new account in the web
- Papertrail for logs (14 days)
- Alerts that contain errors but are false positives

### Settings

- Reveal config vars: with secrets
- The own key API to deploy to test the bot, to merge it on the master git of the bot

### Git Settings

- Secrets and variable at API key and email of Heroku (setup on API settings)
- Deploy the bot by using the fork of it before doing it on the real branch
- Fork of the git to test before deploy on the master
- Workflow file deploy file in the `.github`
- Build the docker image locally

## GitHub Apps in Git Settings

- `rocq-prover`
- In apps: permissions and events
- Redeliver to check if the bug has been fixed
- To build maybe the dashboard
- Delivery IDs to check the logs

### GitHub APP Dashboard

- To look more history logs
- **TODO**: Advanced --> git logs (to make the dashboard maybe to get the logs whenever we want)
- The suspend of the...

**TODO**: The dashboard of the installation of the bot. To know who is installing the bot so that we would know...

## Run-Coq-Minimizer

- GitHub actions in this repos
- The bot will push a new branch in the GitHub account of the bot

### Can we push as a GitHub app?

- Disable push by default
- Add cobot-ci parameters
- Or move to change to use the GitHub account instead

The `github_pat` keeps reason.

- `github_pat`: none strong
- `github_install_token`: string

If in some cases we can use the GitHub PAT, if it exists if not then fail.

**Needs**: Rebase label needs to be kept.

Add auto by the bot, using some of GitHub API, REST API (of GitHub in the beginning), GitHub does not check (it creates by bot).

To make it more configurable.

To link to the documentations for the documentation changes for the doc...

## Mirroring

The `webhook_github`: `mirror_action`: hard code for a specific.

Security reason for this: if `mirror_action` configures (it will push to the config that it does not belong to the user). `.toml`

**==>** Before doing the mirror bot check on the main branch, check on the config on GitHub, match the one in GitLab, GitHub > GitLab.

- Mirror action on GitHub > Git
- Check the config on GitLab to see if it is the same with the one in GitHub

## Security Audit

- Try to have general audit (for security of the bot), to improve the current security of the bot.
- The HTTPS for instance, there are several events that does not sign

## Webhook Configuration

### GitLab Webhooks

- For `webhook_gitlab` does not need to sign any event
- GitLab webhooks: secret token (to sign the GitLab pipeline)
- To find the way so that the bot knows the secret token of all the GitLab ???

### Security Concerns

- Some hack account can pretend to make the bot makes the fall request is not green but makes it greens and harm the repos

## TOML Configuration

- Default sections can be config on the repos (can be done in the toml)
