local Utils = require("pie.utils")
local Pie = {}
Pie.__index = Pie

function Pie:new()
	local self = setmetatable({}, Pie)
	self.sessions = {}
	self.win = nil
	self.current = nil
	return self
end

function Pie:find_session(name)
	for _, s in ipairs(self.sessions) do
		if s:get_name() == name then
			return s
		end
	end
	return nil
end

function Pie:get_status_list()
	local cwd = vim.fn.getcwd()
	local current_session = self:find_session_by_dir(cwd)

	if not current_session then
		return {}
	end

	local commander_session = current_session:get_commander_session()
	if not commander_session then
		return {}
	end

	local list = {}
	for _, s in ipairs(self.sessions) do
		local s_commander = s:get_commander_session()
		if s_commander and s_commander:get_name() == commander_session:get_name() then
			table.insert(list, s)
		end
	end

	table.sort(list, function(a, b)
		if a:is_commander() and not b:is_commander() then
			return true
		end
		if not a:is_commander() and b:is_commander() then
			return false
		end
		return a:get_name() < b:get_name()
	end)

	return list
end

function Pie:show_status()
	local sessions = self:get_status_list()

	if #sessions == 0 then
		vim.notify("No sessions found for current directory", vim.log.levels.WARN)
		return
	end

	local role_width = 10
	local name_width = 20
	local status_width = 10

	local build_lines = function()
		local lines = {}
		table.insert(
			lines,
			string.format(
				"%-" .. role_width .. "s %-" .. name_width .. "s %-" .. status_width .. "s",
				"Role",
				"Name",
				"Status"
			)
		)

		for _, s in ipairs(sessions) do
			local role = s:get_role()
			local name = s:get_name()
			local status = s:get_working_status()
			local status_str = status == "working" and "working" or "ready"

			table.insert(
				lines,
				string.format(
					"%-" .. role_width .. "s %-" .. name_width .. "s %-" .. status_width .. "s",
					role,
					name,
					status_str
				)
			)
		end

		return lines
	end

	local lines = build_lines()

	local width = 60
	local height = #lines + 2

	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local opts = {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
	}

	local win = vim.api.nvim_open_win(buf, true, opts)

	vim.api.nvim_win_set_option(win, "cursorline", false)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_win_set_option(win, "winhighlight", "Normal:NormalFloat")

	local role_w = role_width + 1
	local name_w = name_width + 1

	local render = function()
		local next_lines = build_lines()
		vim.api.nvim_buf_set_option(buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, next_lines)
		vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
		for i, s in ipairs(sessions) do
			local status = s:get_working_status()
			local line_idx = i
			local status_start = role_w + name_w
			if status == "working" then
				vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticError", line_idx, status_start, -1)
			else
				vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticHint", line_idx, status_start, -1)
			end
		end
		vim.api.nvim_buf_set_option(buf, "modifiable", false)
	end

	local auto_close = function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	vim.defer_fn(auto_close, 10000)

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set("n", "<Enter>", function()
		local cursor_line = vim.fn.line(".")
		if cursor_line <= 1 then
			return
		end
		local session_idx = cursor_line - 1
		local session = sessions[session_idx]
		if session then
			vim.api.nvim_win_close(win, true)
			self:switch(session:get_name())
		end
	end, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set("n", "D", function()
		local cursor_line = vim.fn.line(".")
		if cursor_line <= 1 then
			return
		end

		local session_idx = cursor_line - 1
		local session = sessions[session_idx]
		if not session then
			return
		end

		if session:is_commander() then
			vim.notify("Cannot delete commander session. Use wqa! to teardown.", vim.log.levels.ERROR)
			return
		end

		local commander_session = session:get_commander_session()
		local worker_name = session:get_name()
		local deleting_current = self.current == worker_name

		if deleting_current then
			self:switch(commander_session:get_name())
		end

		local deleted_session = self:destroy_worker_session(commander_session, worker_name)
		if not deleted_session then
			vim.notify("Failed to teardown worker session '" .. worker_name .. "'.", vim.log.levels.ERROR)
			return
		end

		table.remove(sessions, session_idx)
		render()

		if deleting_current then
			vim.notify("Switched to commander and tore down worker session '" .. worker_name .. "'.")
		else
			vim.notify("Tore down worker session '" .. worker_name .. "'.")
		end
	end, { buffer = buf, noremap = true, silent = true })

	render()
end

function Pie:find_session_by_dir(dir)
	for _, s in ipairs(self.sessions) do
		if Utils.safe_compare(s:get_dir(), dir) then
			return s
		end
	end
	return nil
end

function Pie:find_worker_session(commander_session, worker_name)
	for _, s in ipairs(self.sessions) do
		if
			s:get_name() == worker_name
			and s:is_worker_session()
			and s:get_commander_session() ~= nil
			and s:get_commander_session():get_name() == commander_session:get_name()
		then
			return s
		end
	end
	return nil
end

function Pie:destroy_worker_session(commander_session, worker_name)
	local worker_session = self:find_worker_session(commander_session, worker_name)
	if not worker_session then
		return nil
	end

	worker_session:teardown()

	for i, session in ipairs(self.sessions) do
		if session == worker_session then
			table.remove(self.sessions, i)
			break
		end
	end

	return worker_session
end

function Pie:switch(session_name)
	local session = self:find_session(session_name)
	if not session then
		local msg = "Pie: session '" .. session_name .. "' not found"
		vim.notify(msg, vim.log.levels.ERROR)
		return
	end

	Utils.change_dir(session:get_dir())
	session:open()

	self.current = session_name
end

function Pie:add_session(config)
	if not config or not config.name then
		error("PieSession: name is required")
	end

	if not config.dir then
		error("PieSession: dir is required")
	end

	if not config.work_dir then
		error("PieSession: work_dir is required")
	end

	local absolute_dir = vim.fn.fnamemodify(config.dir, ":p")

	local existing_by_name = self:find_session(config.name)
	if existing_by_name then
		error("PieSession: session '" .. config.name .. "' already exists")
	end

	local existing_by_dir = self:find_session_by_dir(absolute_dir)
	if existing_by_dir then
		error("PieSession: dir '" .. absolute_dir .. "' already exists")
	end

	local PieSession = require("pie.session")
	config.commander = true
	table.insert(self.sessions, PieSession:new(config))
end

function Pie:init(opts)
	if vim.fn.executable("wget") ~= 1 then
		error("Pie: wget is required but was not found in PATH")
	end

	if not opts or not opts.sessions or #opts.sessions == 0 then
		error("Pie: opts.sessions is required and must not be empty")
	end

	for _, config in ipairs(opts.sessions) do
		self:add_session(config)
	end

	vim.api.nvim_create_user_command("PieS", function(args)
		self:show_status()
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("Pie", function(args)
		self:switch(args.args)
	end, {
		nargs = 1,
		complete = function()
			local names = {}
			for _, s in ipairs(self.sessions) do
				table.insert(names, s:get_name())
			end
			return names
		end,
	})

	vim.api.nvim_create_user_command("PieC", function(args)
		local argv = vim.split(args.args, "/")
		if #argv ~= 2 then
			vim.notify("Usage: PieC <commander_name>/<worker_name>", vim.log.levels.ERROR)
			return
		end
		local commander_name = argv[1]
		local worker_name = argv[2]

		local commander_session = self:find_session(commander_name)
		if not commander_session then
			vim.notify("Commander not found: " .. commander_name, vim.log.levels.ERROR)
			return
		end
		if not commander_session:is_commander() then
			vim.notify("Not a commander session: " .. commander_name, vim.log.levels.ERROR)
			return
		end

		local sessions = self:find_or_create_worker_sessions({
			commander_session = commander_session,
			worker_names = { worker_name },
		})
		if #sessions > 0 then
			vim.notify("Created worker: " .. worker_name .. " for commander: " .. commander_name)
		end
	end, {
		nargs = 1,
		complete = function(arg_lead)
			local parts = vim.split(arg_lead, "/")
			if #parts == 1 then
				local names = {}
				for _, s in ipairs(self.sessions) do
					if s:is_commander() then
						table.insert(names, s:get_name() .. "/")
					end
				end
				return names
			elseif #parts == 2 then
				return {}
			end
		end,
	})

	vim.api.nvim_create_user_command("PieD", function(args)
		local argv = vim.split(args.args, "/")
		if #argv ~= 2 then
			vim.notify("Usage: PieD <commander_name>/<worker_name>", vim.log.levels.ERROR)
			return
		end
		local commander_name = argv[1]
		local worker_name = argv[2]

		local commander_session = self:find_session(commander_name)
		if not commander_session then
			vim.notify("Commander not found: " .. commander_name, vim.log.levels.ERROR)
			return
		end

		local worker_session = self:destroy_worker_session(commander_session, worker_name)
		if worker_session then
			vim.notify("Destroyed worker: " .. worker_name .. " for commander: " .. commander_name)
		else
			vim.notify("Worker not found: " .. worker_name, vim.log.levels.ERROR)
		end
	end, {
		nargs = 1,
		complete = function(arg_lead)
			local parts = vim.split(arg_lead, "/")
			if #parts == 1 then
				local names = {}
				for _, s in ipairs(self.sessions) do
					if s:is_commander() then
						table.insert(names, s:get_name() .. "/")
					end
				end
				return names
			elseif #parts == 2 then
				local commander_name = parts[1]
				local commander_session = self:find_session(commander_name)
				if commander_session then
					local names = {}
					for _, s in ipairs(self.sessions) do
						if s:is_worker_session() then
							local comm = s:get_commander_session()
							if comm and comm:get_name() == commander_name then
								table.insert(names, s:get_name())
							end
						end
					end
					return names
				end
			end
			return {}
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			for _, session in ipairs(self.sessions) do
				session:teardown()
			end
		end,
	})
end

function Pie:find_or_create_worker_sessions(config)
	local commander_session = config.commander_session
	local worker_names = config.worker_names

	local created_sessions = {}

	for _, worker_name in ipairs(worker_names) do
		local existing_session = self:find_worker_session(commander_session, worker_name)
		if existing_session then
			table.insert(created_sessions, existing_session)
			existing_session:init_session_background()
			goto continue
		end

		local new_config = {
			name = worker_name,
			work_dir = commander_session:get_work_dir(),
			commander = false,
			commander_session = commander_session,
		}

		local PieSession = require("pie.session")
		local new_session = PieSession:new(new_config)
		table.insert(self.sessions, new_session)
		table.insert(created_sessions, new_session)
		new_session:init_session_background()

		::continue::
	end

	return created_sessions
end

return Pie
