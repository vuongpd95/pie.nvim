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

function PiClient:teardown()
	-- noop
end

return PiClient
