local Pie = require("pie.pie")

describe("Pie", function()
	local pie

	before_each(function()
		pie = Pie:new()
	end)

	describe("new", function()
		it("creates new instance with default values", function()
			assert.equals(0, #pie.sessions)
			assert.is_nil(pie.win)
			assert.is_nil(pie.current)
		end)
	end)

	describe("find_session", function()
		it("returns nil when session not found", function()
			local PieSession = require("pie.session")
			pie.sessions = {
				PieSession:new({ name = "foo", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test" }),
			}
			local result = pie:find_session("nonexistent")
			assert.is_nil(result)
		end)

		it("returns session when found", function()
			local PieSession = require("pie.session")
			pie.sessions = {
				PieSession:new({ name = "foo", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test" }),
				PieSession:new({ name = "bar", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test" }),
			}
			local result = pie:find_session("bar")
			assert.is_not_nil(result)
			assert.equals("bar", result:get_name())
		end)
	end)

	describe("get_win_pie_width", function()
		it("calculates width as 30% of columns", function()
			vim.o.columns = 100
			local width = pie:get_win_pie_width()
			assert.equals(30, width)
		end)

		it("floors the result", function()
			vim.o.columns = 101
			local width = pie:get_win_pie_width()
			assert.equals(30, width)
		end)
	end)

	describe("get_win_neotree_width", function()
		it("returns default width when neo-tree not loaded", function()
			local width = pie:get_win_neotree_width()
			assert.equals(40, width)
		end)
	end)

	describe("init", function()
		it("initializes sessions from opts.sessions", function()
			local opts = {
				sessions = {
					{ name = "test", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test", commander = true },
				},
			}
			pie:init(opts)
			assert.equals(1, #pie.sessions)
			assert.equals("test", pie.sessions[1]:get_name())
			assert.equals("/home/vuongpham/Desktop/pie.nvim/", pie.sessions[1]:get_dir())
		end)

		it("raises error when opts is nil", function()
			local ok, err = pcall(function()
				pie:setup(nil)
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)

		it("raises error when opts.sessions is nil", function()
			local ok, err = pcall(function()
				pie:setup({})
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)

		it("raises error when opts.sessions is empty", function()
			local ok, err = pcall(function()
				pie:setup({ sessions = {} })
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)
	end)

	describe("add_session", function()
		it("adds a session", function()
			pie:add_session({ name = "foo", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test" })
			assert.equals(1, #pie.sessions)
			assert.equals("foo", pie.sessions[1]:get_name())
		end)

		it("raises error when config is nil", function()
			local ok, err = pcall(function()
				pie:add_session(nil)
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)

		it("raises error when config.name is nil", function()
			local ok, err = pcall(function()
				pie:add_session({ dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test" })
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)

		it("raises error when config.dir is nil", function()
			local ok, err = pcall(function()
				pie:add_session({ name = "foo", work_dir = "/tmp/pie_test" })
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)

		it("raises error when config.work_dir is nil", function()
			local ok, err = pcall(function()
				pie:add_session({ name = "foo", dir = "/home/vuongpham/Desktop/pie.nvim" })
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)

		it("raises error when session name already exists", function()
			pie:add_session({ name = "foo", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test" })
			local ok, err = pcall(function()
				pie:add_session({ name = "foo", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test" })
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)

		it("raises error when session dir already exists", function()
			pie:add_session({ name = "foo", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test", commander = true })
			local ok, err = pcall(function()
				pie:add_session({ name = "bar", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test", commander = true })
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
		end)
	end)

	describe("switch", function()
		it("notifies error when session not found", function()
			local PieSession = require("pie.session")
			pie.sessions = {
				PieSession:new({ name = "foo", dir = "/home/vuongpham/Desktop/pie.nvim", work_dir = "/tmp/pie_test" }),
			}
			local notified = false
			vim.notify = function(msg, level)
				notified = true
				assert.equals("Pie: session 'nonexistent' not found", msg)
				assert.equals(vim.log.levels.ERROR, level)
			end
			pie:switch("nonexistent")
			assert.is_true(notified)
		end)
	end)
end)
