--- nvim-buffergator keymaps
-- Sets up all buffer-local keymaps for the sidebar buffer.
-- Called once per sidebar open (buffer is wiped on close, so keymaps
-- are registered fresh each time).
--
-- open_buf() handles the close_on_select option and targets prev_win
-- (the last focused editing window) for all open operations.

local M = {}

local config   = require("nvim-buffergator.config")
local renderer = require("nvim-buffergator.renderer")

local HEADER = renderer.HEADER_LINES

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Open bufnr in the previous editing window using the given command.
-- If close_on_select is true, the sidebar is closed first so the window
-- layout settles before the buffer is loaded.
-- @param bufnr integer  The buffer to open.
-- @param cmd   string   "edit" | "vsplit" | "split" | "tabedit"
local function open_buf(bufnr, cmd)
  local view = require("nvim-buffergator.view")

  if config.options.close_on_select then
    view.close()
  end

  local target = view.get_prev_win()
  if not target then return end

  vim.api.nvim_set_current_win(target)

  if cmd == "edit" then
    vim.api.nvim_set_current_buf(bufnr)
  elseif cmd == "vsplit" then
    vim.cmd("vsplit")
    vim.api.nvim_set_current_buf(bufnr)
  elseif cmd == "split" then
    vim.cmd("split")
    vim.api.nvim_set_current_buf(bufnr)
  elseif cmd == "tabedit" then
    -- Open in a new tab using the filename so no orphan buffer is created.
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      vim.cmd("tabedit " .. vim.fn.fnameescape(name))
    else
      vim.cmd("tabnew")
      vim.api.nvim_set_current_buf(bufnr)
    end
  end
end

--- Return the bufnr of the entry under the cursor, or nil if on the header.
-- Accounts for the header lines at the top of the sidebar.
local function current_bufnr()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local idx  = line - HEADER
  if idx < 1 then return nil end
  local entries = require("nvim-buffergator.catalog").get_buffers()
  local e = entries[idx]
  return e and e.bufnr or nil
end

--- Delete or wipe the buffer under the cursor, then refresh the sidebar.
-- @param wipe boolean  true → :bwipeout, false → :bdelete
local function delete_buf(wipe)
  local view = require("nvim-buffergator.view")
  local b    = current_bufnr()
  if not b then return end
  local cmd = wipe and "bwipeout" or "bdelete"
  local ok, err = pcall(vim.cmd, cmd .. " " .. b)
  if not ok then
    vim.notify("nvim-buffergator: " .. err, vim.log.levels.WARN)
  end
  view.refresh()
end

--- Register a normal-mode keymap in the sidebar buffer.
-- @param bufnr integer
-- @param keys  string|string[]  One or more key strings.
-- @param fn    function
-- @param desc  string
local function map(bufnr, keys, fn, desc)
  if type(keys) == "string" then keys = { keys } end
  for _, k in ipairs(keys) do
    vim.keymap.set("n", k, fn, { buffer = bufnr, noremap = true, silent = true, desc = desc })
  end
end

--- Format a key value (string or list) for display in the help window.
local function fmt_key(k)
  if type(k) == "table" then return table.concat(k, " / ") end
  return k ~= false and tostring(k) or "(disabled)"
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

--- Attach all buffer-local keymaps to bufnr.
-- @param bufnr integer  The sidebar scratch buffer handle.
function M.setup(bufnr)
  local km   = config.options.keymaps
  local view = require("nvim-buffergator.view")

  map(bufnr, km.open, function()
    local b = current_bufnr(); if b then open_buf(b, "edit") end
  end, "Open buffer in previous window")

  map(bufnr, km.open_vsplit, function()
    local b = current_bufnr(); if b then open_buf(b, "vsplit") end
  end, "Open buffer in vertical split")

  map(bufnr, km.open_split, function()
    local b = current_bufnr(); if b then open_buf(b, "split") end
  end, "Open buffer in horizontal split")

  map(bufnr, km.open_tab, function()
    local b = current_bufnr(); if b then open_buf(b, "tabedit") end
  end, "Open buffer in new tab")

  -- Mouse open: double-click by default; set mouse_open=false to disable.
  if km.mouse_open then
    vim.keymap.set("n", km.mouse_open, function()
      local b = current_bufnr(); if b then open_buf(b, "edit") end
    end, { buffer = bufnr, noremap = true, silent = true, desc = "Mouse: open buffer" })
  end

  map(bufnr, km.delete, function() delete_buf(false) end, "Delete buffer (:bdelete)")
  map(bufnr, km.wipe,   function() delete_buf(true)  end, "Wipe buffer (:bwipeout)")
  map(bufnr, km.close,  function() view.close() end,      "Close sidebar")

  map(bufnr, km.next, function()
    local win  = view.get_win()
    if not win then return end
    local cur  = vim.api.nvim_win_get_cursor(win)
    local last = vim.api.nvim_buf_line_count(bufnr)
    if cur[1] < last then
      vim.api.nvim_win_set_cursor(win, { cur[1] + 1, 0 })
    end
  end, "Move to next entry")

  map(bufnr, km.prev, function()
    local win  = view.get_win()
    if not win then return end
    local cur  = vim.api.nvim_win_get_cursor(win)
    if cur[1] > HEADER + 1 then
      vim.api.nvim_win_set_cursor(win, { cur[1] - 1, 0 })
    end
  end, "Move to previous entry")

  map(bufnr, km.refresh, function() view.refresh() end, "Refresh buffer list")

  -- Cycle through sort modes in order, notify the new mode.
  map(bufnr, km.cycle_sort, function()
    local catalog = require("nvim-buffergator.catalog")
    local modes   = catalog.sort_modes
    local cur     = config.options.sort
    local idx     = 1
    for i, s in ipairs(modes) do
      if s == cur then idx = i; break end
    end
    config.options.sort = modes[(idx % #modes) + 1]
    view.refresh()
    vim.notify("nvim-buffergator sort: " .. config.options.sort, vim.log.levels.INFO)
  end, "Cycle sort mode")

  -- Floating help window: derived from current config so user-overridden
  -- keys are shown correctly.
  map(bufnr, km.help, function()
    local lines = {
      "  nvim-buffergator keymaps",
      "  " .. string.rep("─", 32),
      string.format("  %-18s Open buffer",           fmt_key(km.open)),
      string.format("  %-18s Open in vsplit",         fmt_key(km.open_vsplit)),
      string.format("  %-18s Open in split",          fmt_key(km.open_split)),
      string.format("  %-18s Open in tab",            fmt_key(km.open_tab)),
      string.format("  %-18s Delete buffer",          fmt_key(km.delete)),
      string.format("  %-18s Wipe buffer",            fmt_key(km.wipe)),
      string.format("  %-18s Close sidebar",          fmt_key(km.close)),
      string.format("  %-18s Next entry",             fmt_key(km.next)),
      string.format("  %-18s Previous entry",         fmt_key(km.prev)),
      string.format("  %-18s Cycle sort mode",        fmt_key(km.cycle_sort)),
      string.format("  %-18s Refresh",                fmt_key(km.refresh)),
      string.format("  %-18s This help",              fmt_key(km.help)),
    }
    local width  = 40
    local height = #lines
    local row    = math.floor((vim.o.lines   - height) / 2)
    local col    = math.floor((vim.o.columns - width)  / 2)
    local hbuf   = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, lines)
    vim.bo[hbuf].modifiable = false
    local hwin = vim.api.nvim_open_win(hbuf, false, {
      relative = "editor",
      row      = row,
      col      = col,
      width    = width,
      height   = height,
      style    = "minimal",
      border   = "rounded",
    })
    -- Close the help float when the cursor moves or focus leaves the sidebar.
    vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave" }, {
      buffer   = bufnr,
      once     = true,
      callback = function()
        if vim.api.nvim_win_is_valid(hwin) then
          vim.api.nvim_win_close(hwin, true)
        end
      end,
    })
  end, "Show keymap reference")
end

return M
