local function build_workers_schema()
	return {
		type = "object",
		properties = {
			worker_names = {
				type = "array",
				items = { type = "string" },
				description = "Array of worker names",
			},
			your_name = {
				type = "string",
				description = "Your name, so we can know your role",
			},
		},
		required = { "worker_names", "your_name" },
	}
end

local function build_send_message_schema()
	return {
		type = "object",
		properties = {
			your_name = {
				type = "string",
				description = "Your name",
			},
			send_to = {
				type = "string",
				description = "The name of the team member you want to message",
			},
			message = {
				type = "string",
				description = "The message to send",
			},
		},
		required = { "your_name", "send_to", "message" },
	}
end

local function format_worker(session)
	return {
		name = session:get_name(),
		dir = session:get_dir(),
		role = session:get_role(),
		working_status = session:get_working_status(),
	}
end

local function build_profile_schema()
	return {
		type = "object",
		properties = {
			your_name = {
				type = "string",
				description = "Your name",
			},
		},
		required = { "your_name" },
	}
end

return {
	tools = {
		{
			name = "send_message",
			for_worker = true,
			description = [[
        Use when:
        - You want to send a message to your team member
        - You want to give command to your worker as a commander
        Guides:
        - Explicitly state in your message if you want a response
      ]],
			input_schema = build_send_message_schema(),
			run = function(args)
				local your_name = args.your_name
				local send_to = args.send_to
				local pie = require("pie")

				local sender_session = pie:find_session(your_name)
				if not sender_session then
					return "Send message rejected: your profile can not be found"
				end

				if not sender_session:in_a_team() then
					return "Send message rejected: you are not in a team"
				end

				if args.message == "" then
					return "Send message rejected: message can not be empty"
				end

				local recipient_session = pie:find_session(send_to)
				if not recipient_session then
					return "Send message rejected: recipient profile can not be found"
				end

				local sender_commander = sender_session:get_commander_session()
				local recipient_commander = recipient_session:get_commander_session()
				if
					not sender_commander
					or not recipient_commander
					or sender_commander:get_name() ~= recipient_commander:get_name()
				then
					return "Send message rejected: recipient is not in your team"
				end

				if recipient_session:get_name() == sender_session:get_name() then
					return "Send message rejected: sender and recipient can not be the same"
				end

				recipient_session:ensure_harness_session(function()
					recipient_session:get_harness_client():prompt_async(recipient_session.id, {
						parts = {
							{
								type = "text",
								text = 'Message from "' .. sender_session:get_name() .. '":\n' .. args.message,
							},
						},
					})
				end)

				return {
					from = sender_session:get_name(),
					sent_to = recipient_session:get_name(),
					message = args.message,
				}
			end,
		},
		{
			name = "create_workers",
			description = [[
        Use when
        - I ask for help setting up workers to do jobs
      ]],
			input_schema = build_workers_schema(),
			run = function(args)
				local your_name = args.your_name
				local pie = require("pie")

				local session = pie:find_session(your_name)
				if not session or not session:is_commander() or not session:in_a_team() then
					return "Worker creation rejected: you are either not in a team or not a commander"
				end

				local sessions = pie:find_or_create_worker_sessions({
					commander_session = session,
					worker_names = args.worker_names,
				})

				local workers = {}
				for _, worker_session in ipairs(sessions) do
					table.insert(workers, format_worker(worker_session))
				end

				return workers
			end,
		},
		{
			name = "find_workers",
			for_worker = true,
			description = [[
        Use when:
        - You need to check whether workers already exist by name
        - You need worker directories to review their code changes
      ]],
			input_schema = build_workers_schema(),
			run = function(args)
				local your_name = args.your_name
				local pie = require("pie")

				local session = pie:find_session(your_name)

				if not session then
					return "Find workers rejected: You are likely not in any team"
				end

				local commander_session

				if session:is_commander() then
					commander_session = session
				else
					commander_session = session:get_commander_session()
				end

				if not commander_session then
					return "Find workers rejected: Something is wrong, you don't have a commander"
				end

				local workers = {}
				for _, worker_name in ipairs(args.worker_names) do
					local worker_session = pie:find_worker_session(commander_session, worker_name)
					if worker_session then
						table.insert(workers, format_worker(worker_session))
					end
				end

				return workers
			end,
		},
		{
			name = "destroy_workers",
			description = [[
        Use when:
        - You want to destroy a set of workers by name
      ]],
			input_schema = build_workers_schema(),
			run = function(args)
				local your_name = args.your_name
				local pie = require("pie")

				local session = pie:find_session(your_name)

				if not session then
					return "Find workers rejected: You are likely not in any team"
				end

				if not session:is_commander() then
					return "Worker destroy rejected: only commanders can destroy workers"
				end

				local workers = {}
				for _, worker_name in ipairs(args.worker_names) do
					local worker_session = pie:destroy_worker_session(session, worker_name)
					if worker_session then
						table.insert(workers, format_worker(worker_session))
					end
				end

				return workers
			end,
		},
		{
			name = "profile",
			for_worker = true,
			description = [[
        Use to:
				- Learn whether you are a commander or a worker
				- Your current working directory (your working bound)
			  ]],
			input_schema = build_profile_schema(),
			run = function(args)
				local your_name = args.your_name
				local pie = require("pie")

				local session = pie:find_session(your_name)

				if not session then
					return "Profile query rejected: Your profile can not be found"
				end

				return format_worker(session)
			end,
		},
		{
			name = "team_members",
			for_worker = true,
			description = [[
        Use when:
        - You want to get all team members in your team
      ]],
			input_schema = build_profile_schema(),
			run = function(args)
				local your_name = args.your_name
				local pie = require("pie")

				local session = pie:find_session(your_name)
				if not session then
					return "Team members query rejected: Your profile can not be found"
				end

				if not session:in_a_team() then
					return "Team members query rejected: you are not in a team"
				end

				local commander_session = session:get_commander_session()
				local members = {}

				table.insert(members, format_worker(commander_session))

				for _, s in ipairs(pie.sessions or {}) do
					if
						s:is_worker_session()
						and s:get_commander_session() ~= nil
						and s:get_commander_session():get_name() == commander_session:get_name()
					then
						table.insert(members, format_worker(s))
					end
				end

				return members
			end,
		},
		{
			name = "update_working_status",
			for_worker = true,
			description = [[
        Who use:
        - REQUIRED to use by both commander & worker
        Use when:
        - Before you start to perform some works
        - After you have finished performing the work
      ]],
			input_schema = {
				type = "object",
				properties = {
					your_name = {
						type = "string",
						description = "Your name",
					},
					status = {
						type = "string",
						enum = { "working", "ready" },
						description = "The desired working status. Possible values: working, ready",
					},
				},
				required = { "your_name", "status" },
			},
			run = function(args)
				local your_name = args.your_name
				local pie = require("pie")

				local session = pie:find_session(your_name)

				if not session then
					return "Update working status rejected: Your profile can not be found"
				end

				local allowed_statuses = {
					working = true,
					ready = true,
				}

				if not allowed_statuses[args.status] then
					return "Update working status rejected: invalid status '"
						.. tostring(args.status)
						.. "'. Possible statuses: working, ready"
				end

				session:set_working_status(args.status)

				if args.status == "ready" then
					vim.notify(session:get_name() .. ": ready to work")
				end

				return format_worker(session)
			end,
		},
	},
}
