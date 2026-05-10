local Git = {}

function Git.is_git_dir(dir)
	local git_dir = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel")
	return vim.v.shell_error == 0 and #git_dir > 0
end

function Git.get_git_branch(dir)
	local branch = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --abbrev-ref HEAD")
	if vim.v.shell_error == 0 and #branch > 0 then
		return branch[1]
	end
	return nil
end

function Git.worktree_remove(repo, worktree_branch, worktree_dir)
	local remove_worktree_cmd = "git -C "
		.. vim.fn.shellescape(repo)
		.. " worktree remove "
		.. vim.fn.shellescape(worktree_dir)
		.. " --force"
	local delete_branch_cmd = "git -C "
		.. vim.fn.shellescape(repo)
		.. " branch -D "
		.. vim.fn.shellescape(worktree_branch)
		.. " --force"
	vim.fn.system(remove_worktree_cmd)
	vim.fn.system(delete_branch_cmd)
end

function Git.worktree_add(repo, worktree_branch, worktree_dir)
	local add_worktree_cmd = "git -C "
		.. vim.fn.shellescape(repo)
		.. " worktree add "
		.. vim.fn.shellescape(worktree_dir)
		.. " -b "
		.. vim.fn.shellescape(worktree_branch)
	vim.fn.system(add_worktree_cmd)
end

return Git
