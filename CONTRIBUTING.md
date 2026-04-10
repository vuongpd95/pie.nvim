# Contributing to pie.nvim

The project is new, written in a week and might never find people interest. Therefore, if you want to contribute but find it hard to start, open a GitHub issue and I'll help.

## Reporting issues

- Open a GitHub issue with clear reproduction steps.
- Include your Neovim version (`:version`) and relevant plugin configuration.
- If possible, include logs or a minimal setup that reproduces the problem.
- Give the issue description to your opencode LLM abd ask it use the `pie_debugging` tool to inspect your runtime environment variables.

## Development setup

1. Clone the repository.
2. Ensure dependencies are available:
   - Neovim
   - `git`
   - `wget`
   - `opencode`
3. Run tests:

```bash
./test.sh
```

## Code style

- Follow existing Lua style and naming conventions in the repository.
- Keep changes scoped and focused.

## Pull requests

- Describe the problem and why the change is needed.
- Summarize key implementation decisions.
- Mention any user-visible behavior changes.
- Run `./test.sh` before opening the PR.

## Commit messages

Use short, descriptive commit messages that match existing history, for example:

- `fix: handle worker teardown edge case`
- `feat: add team status command`

## License

By contributing, you agree that your contributions are licensed under GPL-3.0.
