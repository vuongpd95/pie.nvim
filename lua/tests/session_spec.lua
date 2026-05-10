local PieSession = require("pie.session")

describe("PieSession", function()
	describe("new", function()
		it("creates session when dir is a git directory", function()
			local session = PieSession:new({
				name = "foo",
				cmd = "echo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				commander = true,
			})
			assert.equals("foo", session.name)
			assert.is_nil(session.bufnr)
			assert.equals("/home/vuongpham/Desktop/pie.nvim/", session.dir)
		end)
	end)

	describe("get_dir", function()
		it("returns dir as absolute path", function()
			local session = PieSession:new({
				name = "foo",
				cmd = "echo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				commander = true,
			})
			assert.equals("/home/vuongpham/Desktop/pie.nvim/", session:get_dir())
		end)
	end)

	describe("get_name", function()
		it("returns the name", function()
			local session = PieSession:new({
				name = "foo",
				cmd = "echo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				commander = true,
			})
			assert.equals("foo", session:get_name())
		end)
	end)

	describe("get_work_dir", function()
		it("returns the work_dir", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				commander = true,
			})
			assert.equals("/tmp/pie_session_test", session:get_work_dir())
		end)
	end)


end)
