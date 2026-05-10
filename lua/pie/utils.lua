local Utils = {}

function Utils.is_port_busy(port)
	local handle = vim.uv.new_tcp()

	if handle == nil then
		error("Utils: Unable to verify if a port is busy")
	end

	local ok = handle:bind("127.0.0.1", port)
	handle:close()
	return not ok
end

function Utils.run_script(env, script_name, opts)
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

function Utils.get_random_port(min_port, max_port)
	return math.random(min_port, max_port)
end

function Utils.randomize_port(min_port, max_port, excluded_ports)
	excluded_ports = excluded_ports or {}
	local excluded_set = {}
	for _, port in ipairs(excluded_ports) do
		excluded_set[port] = true
	end

	local max_attempts = 10
	for _ = 1, max_attempts do
		local port = Utils.get_random_port(min_port, max_port)
		if not excluded_set[port] and not Utils.is_port_busy(port) then
			return port
		end
	end
	error("Failed to find an available port after " .. max_attempts .. " attempts")
end

return Utils
