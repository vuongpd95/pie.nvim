local OpencodeClient = {}
OpencodeClient.__index = OpencodeClient

function OpencodeClient:new(session)
	local self = setmetatable({}, OpencodeClient)
	self.session = session
	return self
end

function OpencodeClient:session_title()
	return self:get_session():get_name() .. " PORT = " .. self:get_session():get_harness_port()
end

function OpencodeClient:get_session()
	return self.session
end

function OpencodeClient:get_base_url()
	return "http://localhost:" .. self:get_session():get_harness_port()
end

function OpencodeClient:_request(method, endpoint, body, raise_error)
	local cmd = string.format('wget -q -O - --method=%s --header="Content-Type: application/json"', method)
	if body then
		cmd = cmd .. " --body-data=" .. vim.fn.shellescape(vim.fn.json_encode(body))
	end
	cmd = cmd .. " " .. vim.fn.shellescape(self.base_url .. endpoint)

	local result = vim.fn.system(cmd)
	local ok, decoded = pcall(vim.fn.json_decode, result)

	if not ok then
		if raise_error then
			error(
				"Error calling OpenCode at port = " .. self:get_session():get_harness_port() .. ", result = " .. result
			)
		end
		return {}
	end

	return decoded
end

function OpencodeClient:_request_no_content(method, endpoint, body, expected_status, raise_error)
	local cmd = string.format('wget -q -S -O /dev/null --method=%s --header="Content-Type: application/json"', method)
	if body then
		cmd = cmd .. " --body-data=" .. vim.fn.shellescape(vim.fn.json_encode(body))
	end
	cmd = cmd .. " " .. vim.fn.shellescape(self.base_url .. endpoint) .. " 2>&1"

	local result = vim.fn.system(cmd)
	local status
	for code in result:gmatch("HTTP/%S+%s+(%d%d%d)") do
		status = tonumber(code)
	end

	if status ~= expected_status then
		if raise_error then
			error(
				"Error calling OpenCode at port = "
					.. self:get_session():get_harness_port()
					.. ", endpoint = "
					.. endpoint
					.. ", expected status = "
					.. expected_status
					.. ", actual status = "
					.. tostring(status)
			)
		end
		return false
	end

	return true
end

function OpencodeClient:create_session()
	return self:_request("POST", "/session", { title = self:session_title() }, true)
end

function OpencodeClient:find_session()
	return self:_request("GET", "/session/" .. self:get_session():get_id(), nil, true)
end

function OpencodeClient:prompt_async(payload)
	return self:_request_no_content(
		"POST",
		"/session/" .. self:get_session():get_id() .. "/prompt_async",
		{ parts = payload.parts },
		204,
		true
	)
end

function OpencodeClient:is_ready()
	return self:_request("GET", "/global/health", nil, false).healthy or false
end

function OpencodeClient:find_or_create_session()
	local id = self:get_session():get_id()

	if id then
		local session = self:find_session()
		if session then
			return session
		end
	end

	return self:create_session()
end

function OpencodeClient:teardown()
	local container_name = "opencode_" .. self:get_session():get_harness_port()
	vim.cmd("docker rm " .. container_name)
end

function OpencodeClient:open_serve_cmd()
	if not self:get_session():get_dir() then
		error("dir is required for open_serve_cmd")
	end

	local container_name = "opencode_" .. self:get_session():get_harness_port()
	local config_mount = vim.fn.expand("~") .. "/.config/opencode/opencode.json"
	local auth_mount = vim.fn.expand("~") .. "/.local/share/opencode/auth.json"

	local cmd = string.format(
		[[docker run -d --name %s \
    --user opencode:opencode \
    -v %s:/home/user/.config/opencode/opencode.json \
    -v %s:/home/user/.local/share/opencode/auth.json \
    -v %s:/home/user/work %s serve --hostname 127.0.0.1 --port %s"]],
		container_name,
		vim.fn.shellescape(config_mount),
		vim.fn.shellescape(auth_mount),
		vim.fn.shellescape(self:get_session():get_dir()),
		"opencode-local",
		self:get_session():get_harness_port()
	)

	error(cmd)

	return cmd
end

function OpencodeClient:attach_tui_cmd()
	if self:get_session():get_id() then
		error("session id is required")
	end

	return "opencode attach http://127.0.0.1:"
		.. self:get_session():get_harness_port()
		.. " -s "
		.. self:get_session():get_id()
		.. " --dir "
		.. self:get_session():get_dir()
end

return OpencodeClient
