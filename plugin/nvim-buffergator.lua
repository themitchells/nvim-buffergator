-- Plugin entry point: registers user commands
-- setup() is called by the user from their config

vim.api.nvim_create_user_command("BuffergatorOpen", function()
  require("nvim-buffergator").open()
end, { desc = "Open nvim-buffergator sidebar" })

vim.api.nvim_create_user_command("BuffergatorClose", function()
  require("nvim-buffergator").close()
end, { desc = "Close nvim-buffergator sidebar" })

vim.api.nvim_create_user_command("BuffergatorToggle", function()
  require("nvim-buffergator").toggle()
end, { desc = "Toggle nvim-buffergator sidebar" })

vim.api.nvim_create_user_command("BuffergatorPath", function(opts)
  local n = tonumber(opts.args)
  if not n or not vim.tbl_contains({0, 1, 2, 3}, n) then
    vim.notify("BuffergatorPath: expected 0, 1, 2, or 3", vim.log.levels.ERROR)
    return
  end
  require("nvim-buffergator.config").options.path = n
  require("nvim-buffergator.view").refresh()
end, { nargs = 1, desc = "Set nvim-buffergator path display mode (0-3)" })
