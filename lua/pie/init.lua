local Pie = require("pie.pie")

local M = Pie:new()

M.setup = function(opts)
	return Pie.init(M, opts)
end

return M
