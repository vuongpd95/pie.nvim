if 1 ~= vim.fn.has("nvim-0.11") then
	error("pie.nvim requires at least nvim-0.11.")
	return
end

if vim.g.loaded_pie == 1 then
	return
end
vim.g.loaded_pie = 1
