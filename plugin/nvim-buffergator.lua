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
