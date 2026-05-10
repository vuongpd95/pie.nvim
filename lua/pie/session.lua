local PiClient = require("pie.pi")
local Git = require("pie.git")
local PieSession = {}
PieSession.__index = PieSession

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
	if log_file then
		cmd = cmd .. " > " .. vim.fn.shellescape(log_file) .. " 2>&1"
	end

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
	self.harness = "pi"
	self.task_port = self:randomize_port(1024, 65535)
	self.work_dir = vim.fn.fnamemodify(session_config.work_dir, ":p")
	self.commander = session_config.commander
	self.commander_session = session_config.commander_session
	self.working_status = session_config.working_status or "ready"
	self.setup = false
	self.run = false
	self.harness_initialized = false

	if self:is_worker_session() then
		local worktrees_dir = self.work_dir .. "worktrees"
		vim.fn.mkdir(worktrees_dir, "p")
		self.dir = vim.fn.fnamemodify(worktrees_dir .. "/" .. session_config.name .. "_" .. self.task_port, ":p")
	end

	if self:is_commander() then
		self.dir = vim.fn.fnamemodify(session_config.dir, ":p")
	end

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
	if self.harness == "pi" then
		return PiClient:new(self)
	end
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

function PieSession:open()
	self:run_setup_script()
	self:init_harness()
	self:run_run_script()
end

function PieSession:teardown()
	if self.harness == "pi" then
		vim.fn.delete(self.id)
	end

	if self:is_worker_session() then
		local commander_dir = self.commander_session:get_dir()
		local env = self:get_env()
		local task_branch = env.PIE_TASK_BRANCH
		Git.worktree_remove(commander_dir, task_branch, self.dir)
	end

	local env = self:get_env()
	local log_file = env.PIE_WORK_DIR .. "/teardown_" .. self:get_name() .. ".log"
	run_script(env, "teardown.sh", {
		log_file = log_file,
	})
end

function PieSession:get_env()
	if self:is_commander() then
		local pie_branch = Git.get_git_branch(self:get_dir())
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
		local pie_branch = Git.get_git_branch(commander_dir)
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

function PieSession:init_session_background()
	self:init_harness()
	self:run_setup_script()
end

function PieSession:init_harness()
	if self.harness_initialized then
		return
	end

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

		Git.worktree_remove(commander_dir, pie_task_branch, pie_task_dir)
		Git.worktree_add(commander_dir, pie_task_branch, pie_task_dir)
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

function PieSession:run_run_script()
	if self.run then
		return
	end

	local env = self:get_env()
	local pie_dir = env.PIE_DIR
	local log_file = env.PIE_WORK_DIR .. "/run_" .. self:get_name() .. ".log"

	if vim.fn.filereadable(pie_dir .. "/run.sh") == 1 then
		vim.notify("Running run.sh...")
		run_script(env, "run.sh", {
			log_file = log_file,
			on_exit = function()
				vim.schedule(function()
					vim.notify("Started application with run.sh")
				end)
			end,
		})
	end

	self.run = true
end

return PieSession
