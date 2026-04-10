local OpencodeClient = {}
OpencodeClient.__index = OpencodeClient

function OpencodeClient:new(port)
	local self = setmetatable({}, OpencodeClient)
	self.port = port
	self.base_url = "http://localhost:" .. port
	return self
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
			error("Error calling OpenCode at port = " .. self.port .. ", result = " .. result)
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
					.. self.port
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

function OpencodeClient:create_session(payload)
	return self:_request("POST", "/session", { title = payload.title }, true)
end

function OpencodeClient:find_session(id)
	return self:_request("GET", "/session/" .. id, nil, true)
end

function OpencodeClient:prompt_async(id, payload)
	return self:_request_no_content("POST", "/session/" .. id .. "/prompt_async", { parts = payload.parts }, 204, true)
end

function OpencodeClient:is_ready()
	return self:_request("GET", "/global/health", nil, false).healthy or false
end

function OpencodeClient:find_or_create_session(payload)
	local id = payload.id
	local title = payload.title

	if id then
		local session = self:find_session(id)
		if session then
			return session
		end
	end

	return self:create_session({ title = title })
end

function OpencodeClient:open_serve_cmd()
	return "opencode serve --hostname 127.0.0.1 --port " .. self.port
end

function OpencodeClient:attach_tui_cmd(id, dir)
	if not id then
		error("session id is required")
	end

	return "opencode attach http://127.0.0.1:" .. self.port .. " -s " .. id .. " --dir " .. dir
end

return OpencodeClient
