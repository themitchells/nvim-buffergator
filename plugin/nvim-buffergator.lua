-- nvim-buffergator plugin entry point
-- Registers all user-facing :Buffergator* commands.
-- setup() must be called separately from the user's config to initialise
-- options and keymaps before any command is invoked.

vim.api.nvim_create_user_command("BuffergatorOpen", function()
  require("nvim-buffergator").open()
end, { desc = "Open the nvim-buffergator sidebar" })

vim.api.nvim_create_user_command("BuffergatorClose", function()
  require("nvim-buffergator").close()
end, { desc = "Close the nvim-buffergator sidebar" })

vim.api.nvim_create_user_command("BuffergatorToggle", function()
  require("nvim-buffergator").toggle()
end, { desc = "Toggle the nvim-buffergator sidebar" })

-- :BuffergatorPath {0|1|2|3}
-- Change the filename display mode at runtime without editing the config.
-- Useful for testing; persist the choice by setting path= in setup().
--   0  filename only  (parent shown off-screen to the right)
--   1  relative path
--   2  absolute path
--   3  tilde-relative
vim.api.nvim_create_user_command("BuffergatorPath", function(opts)
  local n = tonumber(opts.args)
  if not n or not vim.tbl_contains({0, 1, 2, 3}, n) then
    vim.notify("BuffergatorPath: expected 0, 1, 2, or 3", vim.log.levels.ERROR)
    return
  end
  require("nvim-buffergator.config").options.path = n
  require("nvim-buffergator.view").refresh()
end, { nargs = 1, desc = "Set nvim-buffergator path display mode (0-3)" })

-- :BuffergatorSort {filepath|bufnum|basename|mru}
-- Change the sort mode at runtime.
vim.api.nvim_create_user_command("BuffergatorSort", function(opts)
  local mode    = opts.args
  local catalog = require("nvim-buffergator.catalog")
  if not vim.tbl_contains(catalog.sort_modes, mode) then
    vim.notify(
      "BuffergatorSort: expected one of: " .. table.concat(catalog.sort_modes, ", "),
      vim.log.levels.ERROR)
    return
  end
  require("nvim-buffergator.config").options.sort = mode
  require("nvim-buffergator.view").refresh()
end, {
  nargs    = 1,
  complete = function()
    return require("nvim-buffergator.catalog").sort_modes
  end,
  desc = "Set nvim-buffergator sort mode (filepath|bufnum|basename|mru)",
})
