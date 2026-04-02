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

--- Return the entry table under the cursor, or nil if on the header.
local function current_entry()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local idx  = line - HEADER
  if idx < 1 then return nil end
  local entries = require("nvim-buffergator.catalog").get_buffers()
  return entries[idx]
end

--- Return the bufnr of the entry under the cursor, or nil if on the header.
-- Accounts for the header lines at the top of the sidebar.
local function current_bufnr()
  local e = current_entry()
  return e and e.bufnr or nil
end

--- Rename/move the file of the buffer under the cursor.
local function rename_buf()
  local view = require("nvim-buffergator.view")
  local e    = current_entry()
  if not e then return end

  local bufnr    = e.bufnr
  local old_path = vim.api.nvim_buf_get_name(bufnr)
  if old_path == "" then
    vim.notify("nvim-buffergator: buffer has no file name", vim.log.levels.WARN)
    return
  end

  vim.ui.input({
    prompt     = "Rename to: ",
    default    = old_path,
    completion = "file",
  }, function(new_path)
    if not new_path or new_path == "" or new_path == old_path then return end

    new_path = vim.fn.expand(new_path)

    if vim.fn.filereadable(new_path) == 1 then
      vim.notify("nvim-buffergator: destination already exists: " .. new_path, vim.log.levels.ERROR)
      return
    end

    -- Create parent directories as needed
    local new_dir = vim.fn.fnamemodify(new_path, ":h")
    if vim.fn.isdirectory(new_dir) == 0 then
      vim.fn.mkdir(new_dir, "p")
    end

    local old_undo   = vim.o.undofile and vim.fn.undofile(old_path) or nil
    local new_undo   = vim.o.undofile and vim.fn.undofile(new_path) or nil
    local old_exists = vim.fn.filereadable(old_path) == 1

    if old_exists then
      if vim.bo[bufnr].modified then
        local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd("write") end)
        if not ok then
          vim.notify("nvim-buffergator: could not save buffer: " .. tostring(err), vim.log.levels.ERROR)
          return
        end
      end
      if vim.fn.rename(old_path, new_path) ~= 0 then
        vim.notify("nvim-buffergator: failed to move file on disk", vim.log.levels.ERROR)
        return
      end
    end

    vim.api.nvim_buf_set_name(bufnr, new_path)

    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd("silent write!") end)
      if not ok then
        vim.notify("nvim-buffergator: could not write to new path: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
    else
      -- Buffer is listed but not loaded; file already on disk at new_path — just clear state
      vim.bo[bufnr].modified = false
    end

    if vim.fn.fnamemodify(old_path, ":e") ~= vim.fn.fnamemodify(new_path, ":e") then
      vim.api.nvim_buf_call(bufnr, function() vim.cmd("filetype detect") end)
    end

    if old_undo and new_undo and vim.fn.filereadable(old_undo) == 1 then
      local undo_dir = vim.fn.fnamemodify(new_undo, ":h")
      if vim.fn.isdirectory(undo_dir) == 0 then vim.fn.mkdir(undo_dir, "p") end
      vim.fn.rename(old_undo, new_undo)
    end

    vim.notify(string.format("Renamed: %s → %s",
      vim.fn.fnamemodify(old_path, ":~:."),
      vim.fn.fnamemodify(new_path, ":~:.")), vim.log.levels.INFO)

    vim.schedule(function() view.refresh() end)
  end)
end

--- Delete or wipe the buffer under the cursor, then refresh the sidebar.
-- Any window currently showing the buffer is switched to another buffer
-- first so splits are preserved (mirrors :Bd / buf_close behaviour).
-- @param wipe boolean  true → :bwipeout, false → :bdelete
local function delete_buf(wipe)
  local view = require("nvim-buffergator.view")
  local b    = current_bufnr()
  if not b then return end

  -- Find a replacement: prefer alternate buffer, then any other listed buffer.
  local function replacement()
    local alt = vim.fn.bufnr('#')
    if alt ~= -1 and alt ~= b and vim.fn.buflisted(alt) == 1 then
      return alt
    end
    for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
      if info.bufnr ~= b then return info.bufnr end
    end
  end

  -- Switch every non-sidebar window showing this buffer before deleting.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= view.get_win() and vim.api.nvim_win_get_buf(win) == b then
      local repl = replacement()
      vim.api.nvim_win_set_buf(win, repl or vim.api.nvim_create_buf(true, false))
    end
  end

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

  -- Override gg to land on the first entry, skipping the branch header line.
  map(bufnr, "gg", function()
    local win = view.get_win()
    if win then vim.api.nvim_win_set_cursor(win, { HEADER + 1, 0 }) end
  end, "Go to first buffer entry")

  map(bufnr, km.rename, rename_buf,                        "Rename/move buffer file")
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

  -- Always show the full path of the entry under the cursor in the cmdline.
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer   = bufnr,
    callback = function()
      local e = current_entry()
      if e and e.name ~= "" then
        local full  = vim.fn.fnamemodify(e.name, ":~")
        local base  = vim.fn.fnamemodify(full, ":t")
        local root  = require("nvim-buffergator.catalog").get_git_root(e.name)
        local chunks

        if root then
          local root_abbrev = vim.fn.fnamemodify(root, ":~")
          if vim.startswith(full, root_abbrev .. "/") then
            -- Split into: prefix-before-root / root-name / in-repo-dir / filename
            local root_parent = vim.fn.fnamemodify(root_abbrev, ":h")
            local root_name   = vim.fn.fnamemodify(root_abbrev, ":t")
            local after_root  = full:sub(#root_abbrev + 2)  -- strip "root/"
            local rel_dir     = vim.fn.fnamemodify(after_root, ":h")
            local prefix      = (root_parent ~= "." and root_parent ~= "") and (root_parent .. "/") or ""
            local rel_suffix  = (rel_dir ~= "." and rel_dir ~= "") and ("/" .. rel_dir .. "/") or "/"
            chunks = {
              { prefix,                "Comment"                },
              { root_name,             "Directory"              },
              { rel_suffix,            "Comment"                },
              { base,                  "NvimBuffergatorFilename" },
            }
          end
        end

        if not chunks then
          -- Fallback: no git root known yet — dim the directory, highlight filename
          local dir = vim.fn.fnamemodify(full, ":h")
          if dir == "." or dir == "" then
            chunks = { { base, "NvimBuffergatorFilename" } }
          else
            chunks = {
              { dir .. "/", "Comment"                },
              { base,       "NvimBuffergatorFilename" },
            }
          end
        end

        vim.api.nvim_echo(chunks, false, {})
      else
        vim.api.nvim_echo({}, false, {})
      end
    end,
  })

  -- Clear the path from the cmdline when focus leaves the sidebar.
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer   = bufnr,
    once     = false,
    callback = function() vim.api.nvim_echo({}, false, {}) end,
  })

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
      string.format("  %-18s Rename/move buffer",      fmt_key(km.rename)),
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
