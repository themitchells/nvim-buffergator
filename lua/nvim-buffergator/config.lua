local M = {}

M.defaults = {
  width = 30,
  min_width = 20,
  max_width = 60,
  sort = "filepath", -- "filepath" | "bufnum" | "basename" | "mru"
  auto_resize = true,
  keymaps = {
    open = { "<CR>", "o" },
    open_vsplit = { "s", "<C-v>" },
    open_split = { "i", "<C-s>" },
    open_tab = { "t", "<C-t>" },
    delete = "d",
    wipe = "D",
    close = { "q", "<Esc>" },
    next = "<C-n>",
    prev = "<C-p>",
    refresh = "R",
  },
  global_keymaps = {
    toggle = "<Leader>b",
    close = "<Leader>B",
  },
}

M.options = {}

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
