# Team Tools

`pie.nvim` exposes team coordination tools to the harness session through `lua/pie/buddy.lua`.

## Commander tools

- `send_message`
- `create_workers`
- `find_workers`
- `destroy_workers`
- `profile`
- `team_members`
- `update_working_status`

## Worker tools

- `send_message`
- `find_workers`
- `profile`
- `team_members`
- `update_working_status`

## Tool intent

| Tool | Purpose |
| --- | --- |
| `send_message` | Send a direct message to another team member |
| `create_workers` | Create worker sessions for the commander's team |
| `find_workers` | Resolve existing workers and their directories |
| `destroy_workers` | Tear down worker sessions (commander only) |
| `profile` | Return current member role, directory, and status |
| `team_members` | List all members in the current team |
| `update_working_status` | Set status to `working` or `ready` |

## Notes

- Team mode is available when the commander session directory is a git repository.
- Worker sessions are tied to a commander and isolated in git worktrees.
