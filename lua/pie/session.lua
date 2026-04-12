local OpenCodeClient = require("pie.opencode")
local PiClient = require("pie.pi")
local PieSession = {}
PieSession.__index = PieSession

local function is_git_dir(dir)
	local git_dir = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel")
	return vim.v.shell_error == 0 and #git_dir > 0
end

local function get_git_branch(dir)
	local branch = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --abbrev-ref HEAD")
	if vim.v.shell_error == 0 and #branch > 0 then
		return branch[1]
	end
	return nil
end

local function git_worktree_remove(repo, worktree_branch, worktree_dir)
	local remove_worktree_cmd = "git -C "
		.. vim.fn.shellescape(repo)
		.. " worktree remove "
		.. vim.fn.shellescape(worktree_dir)
		.. " --force"
	local delete_branch_cmd = "git -C "
		.. vim.fn.shellescape(repo)
		.. " branch -D "
		.. vim.fn.shellescape(worktree_branch)
		.. " --force"
	vim.fn.system(remove_worktree_cmd)
	vim.fn.system(delete_branch_cmd)
end

local function git_worktree_add(repo, worktree_branch, worktree_dir)
	local add_worktree_cmd = "git -C "
		.. vim.fn.shellescape(repo)
		.. " worktree add "
		.. vim.fn.shellescape(worktree_dir)
		.. " -b "
		.. vim.fn.shellescape(worktree_branch)
	vim.fn.system(add_worktree_cmd)
end

local function is_port_busy(port)
	local handle = vim.uv.new_tcp()

	if handle == nil then
		error("PieSession: Unable to verify if a port is busy")
	end

	local ok = handle:bind("127.0.0.1", port)
	handle:close()
	return not ok
end

local function run_script(env, script_name, opts)
	opts = opts or {}
	local log_file = opts.log_file
	local on_exit = opts.on_exit

	local pie_dir = env.PIE_DIR
	local script_path = pie_dir .. "/" .. script_name

	if vim.fn.filereadable(script_path) ~= 1 then
		return
	end

	local env_str = ""
	for k, v in pairs(env) do
		env_str = env_str .. k .. "=" .. v .. " "
	end

	local cmd = env_str .. "bash " .. vim.fn.shellescape(script_path)
	-- if log_file then
	-- 	cmd = cmd .. " > " .. vim.fn.shellescape(log_file) .. " 2>&1"
	-- end

	vim.fn.jobstart(cmd, {
		detach = true,
		on_exit = on_exit and function(_, code)
			vim.schedule(function()
				on_exit(code)
			end)
		end or nil,
	})
end

local function get_random_port(min_port, max_port)
	return math.random(min_port, max_port)
end

function PieSession:randomize_port(min_port, max_port, excluded_ports)
	excluded_ports = excluded_ports or {}
	local excluded_set = {}
	for _, port in ipairs(excluded_ports) do
		excluded_set[port] = true
	end

	local max_attempts = 10
	for _ = 1, max_attempts do
		local port = get_random_port(min_port, max_port)
		if not excluded_set[port] and not is_port_busy(port) then
			return port
		end
	end
	error("Failed to find an available port after " .. max_attempts .. " attempts")
end

function PieSession:is_worker_session()
	return (not self.commander) and (self.commander_session ~= nil)
end

function PieSession:new(session_config)
	local self = setmetatable({}, PieSession)

	self.name = session_config.name
	self.harness = session_config.harness or "opencode"
	self.task_port = self:randomize_port(1024, 65535)
	self.work_dir = vim.fn.fnamemodify(session_config.work_dir, ":p")
	self.commander = session_config.commander
	self.bufnr = nil
	self.commander_session = session_config.commander_session
	self.working_status = session_config.working_status or "ready"
	self.setup = false
	self.harness_initialized = false
	self.team = session_config.team

	if self:is_worker_session() then
		local worktrees_dir = self.work_dir .. "worktrees"
		vim.fn.mkdir(worktrees_dir, "p")
		self.dir = vim.fn.fnamemodify(worktrees_dir .. "/" .. session_config.name .. "_" .. self.task_port, ":p")
	end

	if self:is_commander() then
		self.dir = vim.fn.fnamemodify(session_config.dir, ":p")
	end

	self.harness_port = self:randomize_port(1024, 65535, {
		self.task_port,
		7234, -- this is the buddy.nvim MCP server port
	})
	self.harness_client = self:create_harness_client()

	return self
end

function PieSession:get_id()
	return self.id
end

function PieSession:get_commander_session()
	if self:is_commander() then
		return self
	end

	if self:is_worker_session() then
		return self.commander_session
	end

	error("PieSession: Unexpected error happened. Session name = " .. self:get_name())
end

function PieSession:create_harness_client()
	if self.harness == "opencode" then
		return OpenCodeClient:new(self)
	end

	if self.harness == "pi" then
		return PiClient:new(self)
	end
end

function PieSession:get_harness_tool_names()
	if self.team == false then
		return {}
	end

	local buddy = require("pie.buddy")
	local tool_names = {}

	for _, tool in ipairs(buddy.tools or {}) do
		if self:is_commander() or tool.for_worker == true then
			table.insert(tool_names, tool.name)
		end
	end

	return tool_names
end

function PieSession:get_harness_port()
	return self.harness_port
end

function PieSession:ensure_harness_session(on_ready)
	-- The case in which iit's not necessary to init the coding agent server
	if self:get_harness_client():open_serve_cmd() == nil then
		if not self.id then
			self.id = self:get_harness_client():find_or_create_session().id
		end

		on_ready()
		return
	end

	-- id & job
	-- ~id & job
	-- id & ~job
	-- ~id & ~job
	if self.id and self:get_harness_bootstrap_job() then
		on_ready()
		return
	end

	if not self.id and self:get_harness_bootstrap_job() then
		self.id = self:get_harness_client():find_or_create_session().id

		on_ready()
		return
	end

	-- IS COMMANDER BUT THE HARNESS SERVER IS NOT RUNNING

	if self.timer then
		self.timer:stop()
		self.timer:close()
		self.timer = nil
	end

	local start_cmd = self:get_harness_client():open_serve_cmd()
	self.harness_bootstrap_job = vim.fn.jobstart(start_cmd)

	self.timer = vim.uv.new_timer()

	if self.timer == nil then
		error("Timer is nil, unable to start PieSession")
	end

	self.timer:start(
		0,
		1000,
		vim.schedule_wrap(function()
			if not self:get_harness_client():is_ready() then
				vim.notify("Waiting for " .. self.harness .. " at " .. self:get_harness_port() .. "...")
				return
			end

			self.timer:stop()
			self.timer:close()
			self.timer = nil

			if not self.id then
				self.id = self:get_harness_client():find_or_create_session().id
			end

			on_ready()
		end)
	)
end

function PieSession:get_harness_client()
	return self.harness_client
end

function PieSession:get_harness_bootstrap_job()
	return self.harness_bootstrap_job
end

function PieSession:set_harness_bootstrap_job(v)
	self.harness_bootstrap_job = v
end

function PieSession:get_dir()
	return self.dir
end

function PieSession:get_name()
	return self.name
end

function PieSession:get_work_dir()
	return self.work_dir
end

function PieSession:get_working_status()
	return self.working_status
end

function PieSession:set_working_status(status)
	if status ~= "ready" and status ~= "working" then
		error("PieSession: invalid working_status '" .. tostring(status) .. "'")
	end

	self.working_status = status
end

function PieSession:is_commander()
	return self.commander == true
end

function PieSession:get_role()
	if self:is_commander() then
		return "commander"
	end

	if self:is_worker_session() then
		return "worker"
	end

	error("PieSession: Unexpected error happened. Session name = " .. self:get_name())
end

function PieSession:get_bufnr()
	return self.bufnr
end

function PieSession:set_bufnr(bufnr)
	self.bufnr = bufnr
end

function PieSession:is_valid()
	if not self.bufnr then
		return false
	end
	return vim.api.nvim_buf_is_valid(self.bufnr)
end

function PieSession:open(win)
	if self:is_valid() then
		vim.api.nvim_win_set_buf(win, self.bufnr)
		return
	end

	self:run_setup_script()
	self:ensure_harness_session(function()
		self:init_harness()
		vim.cmd("terminal " .. self:get_harness_client():attach_tui_cmd())

		vim.api.nvim_set_current_win(win)
		local bufnr = vim.api.nvim_get_current_buf()
		self:set_bufnr(bufnr)

		vim.bo[bufnr].bufhidden = "hide"
		vim.bo[bufnr].buflisted = false
		vim.bo[bufnr].filetype = "pie"

		local mapopts = { silent = true }
		vim.api.nvim_buf_set_keymap(bufnr, "t", "<C-h>", [[<C-\><C-n><C-w>h]], mapopts)
		vim.api.nvim_buf_set_keymap(bufnr, "t", "<C-j>", [[<C-\><C-n><C-w>j]], mapopts)
		vim.api.nvim_buf_set_keymap(bufnr, "t", "<C-k>", [[<C-\><C-n><C-w>k]], mapopts)
		vim.api.nvim_buf_set_keymap(bufnr, "t", "<C-l>", [[<C-\><C-n><C-w>l]], mapopts)
	end)
end

function PieSession:teardown()
	if self.timer then
		self.timer:stop()
		self.timer:close()
		self.timer = nil
	end

	if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
		local chan = vim.bo[self.bufnr].channel
		if chan then
			vim.api.nvim_chan_send(chan, vim.keycode("<C-c>"))
			self:get_harness_client():teardown()
		end
	end

	if self.harness_bootstrap_job then
		vim.fn.jobstop(self.harness_bootstrap_job)
		self:set_harness_bootstrap_job(nil)
	end

	if self.harness == "pi" then
		vim.fn.delete(self.id)
	end

	if self:is_worker_session() then
		local commander_dir = self.commander_session:get_dir()
		local env = self:get_env()
		local task_branch = env.PIE_TASK_BRANCH
		git_worktree_remove(commander_dir, task_branch, self.dir)
	end

	local env = self:get_env()
	local log_file = env.PIE_WORK_DIR .. "/teardown_" .. self:get_name() .. ".log"
	run_script(env, "teardown.sh", {
		log_file = log_file,
	})
end

function PieSession:get_env()
	if self:is_commander() then
		local pie_branch = get_git_branch(self:get_dir())
		return {
			PIE_DIR = self.dir,
			PIE_BRANCH = pie_branch,
			PIE_WORK_DIR = self.work_dir,
			PIE_TASK_BRANCH = pie_branch,
			PIE_TASK_NAME = self.name,
			PIE_TASK_DIR = self.dir,
			PIE_TASK_PORT = self.task_port,
		}
	end

	if self:is_worker_session() then
		local commander_dir = self.commander_session:get_dir()
		local pie_branch = get_git_branch(commander_dir)
		return {
			PIE_DIR = commander_dir,
			PIE_BRANCH = pie_branch,
			PIE_WORK_DIR = self.work_dir,
			PIE_TASK_BRANCH = pie_branch .. "_" .. self.task_port,
			PIE_TASK_NAME = self.name .. "_" .. self.task_port,
			PIE_TASK_DIR = self.dir,
			PIE_TASK_PORT = self.task_port,
		}
	end
end

function PieSession:in_a_team()
	local commander_session = self:get_commander_session()

	if commander_session == nil then
		return false
	end

	return is_git_dir(commander_session:get_dir())
end

function PieSession:init_session_background()
	self:ensure_harness_session(function()
		self:init_harness()
		self:run_setup_script()
	end)
end

function PieSession:init_harness()
	if self.harness_initialized or self.team == false then
		return
	end

	if not self.id then
		error("PieSession: call ensure_harness_session first")
	end

	local role = self:get_role()
	local tool_names = self:get_harness_tool_names()

	local prompt

	if self:in_a_team() then
		prompt = table.concat({
			'Your name is "' .. self:get_name() .. '".',
			"You are working in a team of commander and workers to help me with my jobs.",
			"You are a " .. role .. " of the team.",
			"You should call the tool `profile` to get to know your personal details within the team.",
			"You should use the tool `update_working_status` before you start and after finishing a job assigned to you by me or by the commander.",
			"As a " .. role .. ", you have access to these tools: " .. table.concat(tool_names, ", ") .. ".",
		}, "\n")
	else
		prompt = table.concat({
			'Your name is "' .. self:get_name() .. '".',
			"You are not working in a team of commander and workers.",
			"Hence, you shouldn't use these tools: " .. table.concat(tool_names, ", ") .. ".",
			"Let me know that if I want the team mode, the commander working dir should be a git repository.",
		}, "\n")
	end

	self:get_harness_client():prompt_async({
		parts = {
			{ type = "text", text = prompt },
		},
	})

	self.harness_initialized = true
end

function PieSession:run_setup_script()
	if self.setup then
		return
	end

	local env = self:get_env()

	if self:is_worker_session() then
		local commander_dir = self.commander_session:get_dir()
		local pie_task_branch = env.PIE_TASK_BRANCH
		local pie_task_dir = env.PIE_TASK_DIR

		git_worktree_remove(commander_dir, pie_task_branch, pie_task_dir)
		git_worktree_add(commander_dir, pie_task_branch, pie_task_dir)
	end

	local pie_dir = env.PIE_DIR
	local log_file = env.PIE_WORK_DIR .. "/setup_" .. self:get_name() .. ".log"

	if vim.fn.filereadable(pie_dir .. "/setup.sh") == 1 then
		vim.notify("Running setup.sh...")
		run_script(env, "setup.sh", {
			log_file = log_file,
			on_exit = function()
				vim.schedule(function()
					vim.notify("Initialization with setup.sh finished")
				end)
			end,
		})
	end

	self.setup = true
end

return PieSession
