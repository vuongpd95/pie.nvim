local PiClient = {}
PiClient.__index = PiClient

function PiClient:new(session)
	local self = setmetatable({}, PiClient)
	self.session = session
	return self
end

function PiClient:get_session()
	return self.session
end

function PiClient:session_title()
	return "pi_sessions/" .. self:get_session():get_name() .. "_" .. self:get_session():get_harness_port() .. ".jsonl"
end

function PiClient:create_session()
	local title = self:session_title()
	return { id = self:get_session():get_work_dir() .. title }
end

function PiClient:find_session()
	return self:get_session():get_id()
end

function PiClient:teardown()
	-- noop
end

function PiClient:prompt_async(payload)
	local text = payload.parts[1].text
	local id = self:get_session():get_id()
	local cmd = string.format('pi --session %s --mode json "%s"', id, text)
	vim.fn.jobstart(cmd)
end

function PiClient:is_ready()
	return true
end

function PiClient:find_or_create_session()
	return self:create_session()
end

function PiClient:open_serve_cmd()
	return nil
end

function PiClient:attach_tui_cmd()
	return "pi --session " .. self:get_session():get_id()
end

return PiClient
