# `.github/prompts/` (PHOSPHENE)

Prompt templates used by GitHub Actions workflows when creating issues or summoning agents.

## Files

- **`domain_delegation_prompt.md`**: parameterized issue-body template used for domain delegation.

## Usage

Workflows load these templates and replace placeholders (e.g. `{{DOMAIN_TAG}}`, `{{DOMAIN_SCRIPTS_PATH}}`) before creating an issue.

