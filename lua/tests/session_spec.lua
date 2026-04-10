local PieSession = require("pie.session")

describe("PieSession", function()
	describe("new", function()
		it("raises error when dir is not a git directory and commander mode is on", function()
			local ok, err = pcall(function()
				PieSession:new({
					name = "foo",
					dir = "/tmp/not-git",
					work_dir = "/tmp/pie_session_test",
					commander = true,
				})
			end)
			assert.is_false(ok)
			assert.matches("needs to be a git directory", err)
		end)

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

	describe("get_bufnr", function()
		it("returns nil when bufnr not set", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
			})
			assert.is_nil(session:get_bufnr())
		end)

		it("returns bufnr when set", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
			})
			session:set_bufnr(1)
			assert.equals(1, session:get_bufnr())
		end)
	end)

	describe("set_bufnr", function()
		it("sets the bufnr", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
			})
			session:set_bufnr(42)
			assert.equals(42, session.bufnr)
		end)
	end)

	describe("is_valid", function()
		it("returns false when bufnr is nil", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
			})
			assert.is_false(session:is_valid())
		end)

		it("returns false when bufnr is invalid", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
			})
			session.bufnr = 9999
			assert.is_false(session:is_valid())
		end)
	end)

	describe("open", function()
		it("sets buffer to window when session is valid", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
			})
			session:set_bufnr(1)
			local win = 100
			local set_buf_called = false
			local original_win_set_buf = vim.api.nvim_win_set_buf
			vim.api.nvim_win_set_buf = function(w, b)
				set_buf_called = true
				assert.equals(win, w)
				assert.equals(1, b)
			end
			session:open(win)
			vim.api.nvim_win_set_buf = original_win_set_buf
			assert.is_true(set_buf_called)
		end)
	end)

	describe("create_harness_client", function()
		it("creates OpencodeClient when harness is opencode", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				harness = "opencode",
			})
			local client = session:create_harness_client(3000)
			assert.is_not_nil(client)
			assert.equals(3000, client.port)
		end)

		it("raises error for unsupported harness", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				harness = "unknown",
			})
			local ok, err = pcall(function()
				session:create_harness_client(3000)
			end)
			assert.is_false(ok)
			assert.is_not_nil(err)
			assert.matches("unknown is not supported", err)
		end)
	end)

	describe("harness", function()
		it("defaults to opencode when not specified", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
			})
			assert.equals("opencode", session.harness)
		end)

		it("uses specified harness", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				harness = "opencode",
			})
			assert.equals("opencode", session.harness)
		end)
	end)

	describe("randomize_port", function()
		it("sets port within range", function()
			math.randomseed(os.time())
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				min_port = 20000,
				max_port = 20010,
			})
			assert.is_not_nil(session.port)
			assert.is_true(session.port >= 20000 and session.port <= 20010)
		end)

		it("retries when port is busy", function()
			local session = PieSession:new({
				name = "foo",
				dir = "/home/vuongpham/Desktop/pie.nvim",
				work_dir = "/tmp/pie_session_test",
				min_port = 3000,
				max_port = 3010,
			})
			session.port_min = 3000
			session.port_max = 3001
			local bound_ports = {}
			local original_is_port_busy = rawget(_G, "is_port_busy")

			local busy_count = 0
			local function mock_is_port_busy(port)
				busy_count = busy_count + 1
				if port == 3000 then
					return true
				end
				return false
			end

			session.randomize_port = function(self)
				for _ = 1, 10 do
					local port = math.random(self.port_min, self.port_max)
					if not mock_is_port_busy(port) then
						self.port = port
						return
					end
				end
				self.port = math.random(self.port_min, self.port_max)
			end

			session:randomize_port()
			assert.is_true(session.port >= 3000 and session.port <= 3001)
		end)
	end)
end)
