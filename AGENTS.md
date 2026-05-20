# Repository Guidelines

## Project Structure & Module Organization

This repository is currently a clean starting point with no application source checked in yet. As the project grows, keep code organized by purpose:

- `src/` for application code and reusable modules.
- `tests/` for automated tests that mirror `src/` paths.
- `assets/` for static files such as images, fixtures, or seed data.
- `docs/` for design notes, runbooks, and contributor-facing documentation.

Avoid committing generated output, local state, or editor metadata. Keep temporary files outside the repository or in ignored paths.

## Build, Test, and Development Commands

No language-specific build system is present yet. Add commands to this section when a package manager, Makefile, or test runner is introduced. Until then, these Git commands are the main workflow:

- `git status` shows pending changes before and after edits.
- `git diff` reviews local modifications before committing.
- `git log --oneline` inspects recent commit history once commits exist.

When tooling is added, prefer a small documented command set such as `make test`, `npm test`, or `swift test` over ad hoc scripts.

## Coding Style & Naming Conventions

Follow the conventions of the language or framework added to the repository. Use consistent indentation, descriptive names, and small modules with clear responsibilities. Prefer lowercase, hyphenated directory names for project folders, for example `src/data-loader/`, unless the chosen ecosystem requires another pattern.

Do not introduce formatting tools silently. If a formatter or linter is adopted, document the command here and keep configuration files committed with the source.

## Testing Guidelines

Place tests under `tests/` and name them after the behavior or module they cover, for example `tests/data-loader.test.*`. Keep tests deterministic and avoid relying on local machine state. Every non-trivial feature or bug fix should include either an automated test or a short explanation of why automated coverage is not practical yet.

## Commit & Pull Request Guidelines

There is no established commit history yet. Use concise, imperative commit subjects such as `Add data import module` or `Fix cache invalidation`. Keep each commit focused on one logical change.

Pull requests should include a summary, validation steps, and any relevant screenshots or logs for user-facing behavior. Link issues when applicable and call out follow-up work explicitly.

## Security & Configuration Tips

Never commit secrets, API keys, local databases, or machine-specific configuration. Use example files such as `.env.example` to document required settings without exposing private values.
