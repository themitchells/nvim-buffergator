local M = {}

local config = require("nvim-buffergator.config")

local function is_valid(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
end

-- ── Git caches ────────────────────────────────────────────────────────────────

-- dir → repo-root (or false).  Persistent for the lifetime of the session:
-- a directory's git root never changes at runtime.
local dir_root_cache = {}

-- Last-known git data.  get_buffers() / get_git_branch() read from here;
-- refresh_git_async() writes to here after each async run.
local git_cache = {
  statuses = {},   -- abs_path → status char
  branch   = nil,  -- string or nil
}

function M.get_git_branch()
  return git_cache.branch
end

function M.update_git_cache(statuses, branch)
  git_cache.statuses = statuses
  git_cache.branch   = branch
end

-- ── Async git refresh ─────────────────────────────────────────────────────────
--
-- Runs all git operations in the background.  When complete, calls
-- on_done() on the main thread.  on_done receives no arguments; callers
-- should read git_cache afterwards.
--
-- Strategy:
--   1. Collect all valid buffer directories (fast, no I/O).
--   2. For dirs already in dir_root_cache: use cached root immediately.
--   3. For uncached dirs: fire parallel async `git rev-parse` jobs.
--   4. Once all roots are known, fire parallel async `git status` jobs
--      (one per unique repo) plus one `git rev-parse --abbrev-ref HEAD`.
--   5. Merge results into git_cache, call on_done via vim.schedule.
--
-- Falls back to synchronous vim.fn.system on Neovim < 0.10 (no vim.system).

local function parse_status_output(root, text, out)
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    if #line >= 4 then
      local xy   = line:sub(1, 2)
      local path = line:sub(4):gsub("%s+$", "")
      path = path:match("^.* %-> (.+)$") or path
      local abs  = root .. "/" .. path
      local s    = xy:sub(2, 2)
      if s == " " then s = xy:sub(1, 1) end
      out[abs] = s
    end
  end
end

function M.refresh_git_async(on_done)
  -- Collect unique dirs from all valid buffers
  local dirs = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        dirs[vim.fn.fnamemodify(name, ":h")] = true
      end
    end
  end

  -- Partition dirs into cached and uncached
  local roots    = {}    -- root → true  (known already)
  local uncached = {}    -- dirs needing git rev-parse
  for dir in pairs(dirs) do
    local r = dir_root_cache[dir]
    if r ~= nil then
      if r then roots[r] = true end
    else
      uncached[#uncached + 1] = dir
    end
  end

  -- Phase 2: run status + branch once all roots are known
  local function run_status_phase()
    local root_list = vim.tbl_keys(roots)
    local statuses  = {}
    local branch    = nil
    local pending   = #root_list + 1  -- +1 for branch job

    local function finish()
      pending = pending - 1
      if pending == 0 then
        vim.schedule(function()
          git_cache.statuses = statuses
          git_cache.branch   = branch
          on_done()
        end)
      end
    end

    if vim.system then
      -- branch
      vim.system({"git", "rev-parse", "--abbrev-ref", "HEAD"}, {text = true},
        function(r)
          if r.code == 0 then
            local b = r.stdout:gsub("%s+$", "")
            if b ~= "" and b ~= "HEAD" then branch = b end
          end
          finish()
        end)

      -- per-repo status (all in parallel)
      for _, root in ipairs(root_list) do
        vim.system({"git", "-C", root, "status", "--porcelain"}, {text = true},
          function(r)
            if r.code == 0 then
              parse_status_output(root, r.stdout, statuses)
            end
            finish()
          end)
      end
    else
      -- Synchronous fallback (Neovim < 0.10)
      local b = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null"):gsub("%s+$", "")
      if vim.v.shell_error == 0 and b ~= "" and b ~= "HEAD" then branch = b end

      for _, root in ipairs(root_list) do
        local lines = vim.fn.systemlist(
          "git -C " .. vim.fn.shellescape(root) .. " status --porcelain 2>/dev/null"
        )
        if vim.v.shell_error == 0 then
          parse_status_output(root, table.concat(lines, "\n"), statuses)
        end
      end

      -- schedule so callers always get async behaviour even in fallback
      vim.schedule(function()
        git_cache.statuses = statuses
        git_cache.branch   = branch
        on_done()
      end)
    end
  end

  -- Phase 1: resolve uncached dirs
  if #uncached == 0 then
    run_status_phase()
    return
  end

  if vim.system then
    local pending = #uncached
    for _, dir in ipairs(uncached) do
      vim.system({"git", "-C", dir, "rev-parse", "--show-toplevel"}, {text = true},
        function(r)
          local root = false
          if r.code == 0 then
            local t = r.stdout:gsub("%s+$", "")
            if t ~= "" then root = t end
          end
          vim.schedule(function()
            dir_root_cache[dir] = root
            if root then roots[root] = true end
            pending = pending - 1
            if pending == 0 then run_status_phase() end
          end)
        end)
    end
  else
    -- Synchronous fallback for dir resolution
    for _, dir in ipairs(uncached) do
      local root = vim.fn.system(
        "git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null"
      ):gsub("%s+$", "")
      local r = (vim.v.shell_error == 0 and root ~= "") and root or false
      dir_root_cache[dir] = r
      if r then roots[r] = true end
    end
    run_status_phase()
  end
end

-- ── Buffer list (no git I/O — reads from git_cache) ──────────────────────────

local function make_entry(bufnr, current, alternate)
  local name     = vim.api.nvim_buf_get_name(bufnr)
  local basename = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"

  local display_name, parent
  local path_opt = config.options.path or 0

  if name == "" then
    display_name = "[No Name]"
    parent       = ""
  elseif path_opt == 1 then
    display_name = vim.fn.fnamemodify(name, ":~:.")
    parent       = ""
  elseif path_opt == 2 then
    display_name = name
    parent       = ""
  elseif path_opt == 3 then
    display_name = vim.fn.fnamemodify(name, ":~")
    parent       = ""
  else
    display_name = basename
    parent       = vim.fn.fnamemodify(name, ":h:~:.")
    if parent == "." then parent = "" end
  end

  return {
    bufnr        = bufnr,
    name         = name,
    basename     = basename,
    display_name = display_name,
    parent       = parent,
    modified     = vim.bo[bufnr].modified,
    current      = (bufnr == current),
    alternate    = (bufnr == alternate),
    git_status   = (name ~= "" and git_cache.statuses[name]) or " ",
  }
end

local sorters = {
  filepath = function(a, b) return a.name < b.name end,
  bufnum   = function(a, b) return a.bufnr < b.bufnr end,
  basename = function(a, b)
    if a.basename ~= b.basename then return a.basename < b.basename end
    return a.name < b.name
  end,
}

function M.get_buffers(context_win)
  local current, alternate
  if context_win and vim.api.nvim_win_is_valid(context_win) then
    current   = vim.api.nvim_win_get_buf(context_win)
    alternate = vim.api.nvim_win_call(context_win, function()
      return vim.fn.bufnr("#")
    end)
  else
    current   = vim.api.nvim_get_current_buf()
    alternate = vim.fn.bufnr("#")
  end

  local entries = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_valid(bufnr) then
      entries[#entries + 1] = make_entry(bufnr, current, alternate)
    end
  end

  local sort_fn = sorters[config.options.sort] or sorters.filepath
  table.sort(entries, sort_fn)
  return entries
end

return M
