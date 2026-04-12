# pie.nvim

![pie.nvim](pie.nvim.png)

`pie.nvim` is a Neovim plugin similar to conductor.build but with a twist. It not only can manage terminal buffers, git worktrees, and OpenCode harness sessions so you can switch context quickly with `:Pie`, it also can organize your coding agent fleet into commander & workers and give them the tools to work together!

Each session in your `pie.nvim` configurations `opts.sessions` represents a commander session of a repository. Creating a worker in this commander's team means setting up its own worktree & development environment. You can instruct the commander to create workers for you. The name of your commander & worker should be unique. Try "tom".

This project is new, please read all the WARNING & CAVEATS in the docs (or ask your LLM to read it for you).

## Table of Contents

- [Getting Started](#getting-started)
- [Usage](#usage)
- [Customization](#customization)
- [Commands](#commands)
- [Team Tools](#team-tools)
- [API](#api)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Getting Started

### Requirements

- Neovim (with Lua support)
- `opencode`
- `wget`
- `git` (required for worker worktree flow)
- [`arismoko/buddy.nvim`](https://github.com/arismoko/buddy.nvim) (Thanks arismoko! This plugin would not be possible without your MCP server running inside nvim)

### The plugin runs on my machine

If behavior differs on your machine, compare against this environment first and include your versions in issues.

| Component | Version on author machine |
| --- | --- |
| Arch Linux | rolling (`/etc/os-release`: `BUILD_ID=rolling`) |
| Neovim | `v0.11.6` |
| Neovim LuaJIT | `2.1.1772619647` |
| OpenCode CLI | `1.2.27` |
| GNU Wget | `1.25.0` |
| Git | `2.53.0` |
| `buddy.nvim` | `cc79e1b` (`2026-03-12`, `fix: skip config dir paths in tool discovery`) |

Why `wget`? Because I haven't built the HTTP client for my plugin yet!

### Installation

I have only tested with `lazy.nvim`. Put this in your `~/.config/nvim/lua/plugins/pie.lua`

```lua
return {
  "vuongpd95/pie.nvim",
  dependencies = {
    "arismoko/buddy.nvim",
  },
  opts = {
    team = true,
    sessions = {
      {
        name = "name-of-one-of-your-repo",
        dir = "~/Desktop/path-to/one-of-your-repo",
        work_dir = "~/Desktop/path-to-any-dir-of-your-machine/but-not-inside-your-repo-please",
        harness = "opencode",
      },
    },
  },
}
```

In the same folder, create `~/.config/nvim/lua/plugins/nvim-buddy.lua`

```lua
return {
  "arismoko/buddy.nvim",
  dependencies = {
    "nvim-mini/mini.nvim",
    "nvim-neotest/nvim-nio",
  },
  lazy = false,
  config = function()
    require("buddy").setup({
      auto_start = true,
      port = 7234,
      auth = false,
      tools = {
        disabled = {
          -- Disable buddy.nvim ability to control your nvim
          -- Comment the following lines if that's not waht you want
          "buffer",
          "edit",
          "command",
          "navigation",
          "search",
          "grep",
          "diagnostics",
          "window",
          "tab",
          "fold",
          "visual",
          "macro",
          "register",
          "status",
          "init",
        },
      },
    })
  end,
}
```

As `lazy.vim` uses `neo-tree.nvim`, we need to enable neo-tree's `follow_current_file` so `pie.nvim` session swap can work. Create `~/.config/nvim/lua/plugins/neo-tree.lua`

```lua
return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    filesystem = {
      follow_current_file = {
        enabled = true,
      },
    },
  },
}
```

And finally, configure `opencode`, edit `~/.config/opencode/opencode.json` to add this key

```json
{
  "mcp": {
    "pie": {
      "type": "remote",
      "url": "http://127.0.0.1:7234/sse"
    }
  }
}
```

## Usage

Switch to a configured session:

```vim
:Pie name-of-one-of-your-configured-sessions
```

Open the team status view for the current team:

```vim
:PieS
```

Example keymaps:

```lua
vim.keymap.set("n", "<leader>pp", "<cmd>Pie pie<CR>", { desc = "Open pie session" })
vim.keymap.set("n", "<leader>ps", "<cmd>PieS<CR>", { desc = "Pie team status" })
```

In the `:PieS` floating window:

- `gd`: switch to the selected session
- `D`: destroy selected worker session. WARNING: unstaged / staged / committed changes in the worktree and the worktree branch are all destroyed. Your commander has this `destroy_workers` ability too. If you quit `nvim`, it will also destroy all worktrees! Please make sure to not left any work in progress in the worktree.
- `q` / `<Esc>`: close status window

## Customization

### Setup structure

```lua
require("pie").setup({
  team = true,
  sessions = {
    {
      name = "name-of-one-of-your-repo",
      dir = "~/Desktop/path-to/one-of-your-repo",
      work_dir = "~/Desktop/path-to-any-dir-of-your-machine/but-not-inside-your-repo-please",
      harness = "opencode",
    },
  },
})
```

### Global options

| Key | Type | Required | Description |
| --- | --- | --- | --- |
| `team` | boolean | no | Enable team mode (default: `true`). Set to `false` to disable team coordination tools for this session |

### Session options

| Key | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | string | yes | Unique session name used by `:Pie` and team prompts |
| `dir` | string | yes | Commander repository directory |
| `work_dir` | string | yes | Parent directory for worker worktrees |
| `harness` | string | no | Harness provider (defaults to `opencode`). Only `opencode` is supported at the moment |

### Optional setup/teardown scripts

If a `setup.sh` file exists in the commander repo root, `pie.nvim` runs it in the background when a session starts.

If a `teardown.sh` file exists in the commander repo root, `pie.nvim` runs it during teardown. Teardown happens when you delete a worker session or do `wqa!` to close nvim.

There will be log files of these scripts stored in your configured `work_dir`.

These scripts receive environment variables such as:

| Variable | Description |
| --- | --- |
| `PIE_DIR` | Commander repository directory |
| `PIE_BRANCH` | Commander current git branch name, not necessary `main` or `master` |
| `PIE_WORK_DIR` | Shared work directory used for worker worktrees |
| `PIE_TASK_PORT` | An available, random port is choosen for your script to use if needed |
| `PIE_TASK_NAME` | Task/session name for the current runner. If you create a worker named "tom", this will be `tom_${PIE_TASK_PORT}`  |
| `PIE_TASK_BRANCH` | Task branch name (worker-specific branch for worker sessions). e.g. `main_${PIE_TASK_PORT}` |
| `PIE_TASK_DIR` | Directory of the current task session. e.g. `${opts.sessions[0].work_dir}/worktrees/tom_${PIE_TASK_PORT}` |

## Commands

| Command | Description |
| --- | --- |
| `:Pie {session}` | Switch to a commander or worker session terminal |
| `:PieS` | Show commander/worker status for current team |
| `:PieC {commander}/{worker}` | Create a worker for a commander (with tab completion, type commander name then press Tab to complete with slash) |
| `:PieD {commander}/{worker}` | Destroy a worker for a commander (with tab completion) |

## Team Tools

When a session is running in team mode, the agent running in OpenCode harness can use team coordination tools (for example `profile`, `create_workers`, `send_message`, `update_working_status`).

See [`docs/team-tools.md`](docs/team-tools.md) for the current tool list and intended usage.

CAVEATS:

- In opencode, if you do a `/new` command in the session created by this plugin, this plugin will no longer know which session it should send message to therefore breaking everything (Sorry!)

- I haven't tested extensively how the agent team members interact with each other, merely gave them the basic tools (Sorry!). I am building other projects using this plugin and improve the plugin as I go.

## API

`pie.nvim` is currently configured through `require("pie").setup(opts)`.

Important runtime methods are implemented in `lua/pie/pie.lua` and `lua/pie/session.lua`.

## Testing

Run plugin tests with:

```bash
./test.sh
```

This runs Plenary tests in `lua/tests` using `scripts/minimal_init.vim`.

The test suite is almost useless, just submit your PR, I will help manual testing & adding tests. I'd be overjoy if you can help me improving the test suite.

## Contributing

Issues and pull requests are welcome. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

GPL-2.0. See [`LICENSE.md`](LICENSE.md).
