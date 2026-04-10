local PiClient = {}
PiClient.__index = PiClient

function PiClient:new(port)
	local self = setmetatable({}, PiClient)
	self.port = port
	return self
end

function PiClient:session_title(name)
	return "pi_sessions/" .. name .. "_" .. self.port .. ".jsonl"
end

function PiClient:create_session(payload)
	return { id = payload.work_dir .. payload.title }
end

function PiClient:find_session(id)
	return id
end

function PiClient:prompt_async(id, payload)
	local text = payload.parts[1].text
	local cmd = string.format('pi --session %s --mode json "%s"', id, text)
	vim.fn.jobstart(cmd)
end

function PiClient:is_ready()
	return true
end

function PiClient:find_or_create_session(payload)
	return self:create_session(payload)
end

function PiClient:open_serve_cmd()
	return nil
end

function PiClient:attach_tui_cmd(id, dir)
	return "pi --session " .. id
end

return PiClient
