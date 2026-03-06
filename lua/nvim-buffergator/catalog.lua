--- nvim-buffergator catalog
-- Responsible for:
--   • Maintaining the git data cache (statuses, branch) populated asynchronously.
--   • Maintaining the MRU timestamp table updated on every BufEnter.
--   • Building the sorted buffer entry list used by the renderer.
--
-- get_buffers() performs zero I/O — it reads from in-memory caches only,
-- so it is safe to call on every render without blocking.
-- refresh_git_async() runs all git operations in parallel background jobs and
-- updates the caches when complete.

local M = {}

local config = require("nvim-buffergator.config")

--- Return true if bufnr is a real, user-visible buffer worth listing.
local function is_valid(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
end

-- ── Git caches ────────────────────────────────────────────────────────────────

-- Persistent map: directory path → git repo root (string) or false (not in repo).
-- Never cleared at runtime — a directory's repo root cannot change without
-- restarting Neovim.
local dir_root_cache = {}

-- Last-known git data written by refresh_git_async().
-- get_buffers() and get_git_branch() read from here; no git I/O involved.
local git_cache = {
  statuses = {},  -- abs_path → single-char status (M, A, D, R, ?, …)
  branch   = nil, -- current branch name or nil (detached HEAD / non-repo)
}

--- Return the last-known git branch for cwd, or nil.
function M.get_git_branch()
  return git_cache.branch
end

-- ── Async git refresh ─────────────────────────────────────────────────────────
--
-- Phase 1 — repo root discovery:
--   For each valid buffer's directory, resolve its git repo root.
--   Cached dirs hit dir_root_cache instantly; uncached dirs fire parallel
--   `git rev-parse --show-toplevel` jobs (vim.system) or synchronous calls
--   on Neovim < 0.10.
--
-- Phase 2 — status + branch:
--   Once all repo roots are known, fire one `git status --porcelain` per
--   unique repo and one `git rev-parse --abbrev-ref HEAD` for the branch,
--   all in parallel.  When the last job completes, git_cache is updated
--   and on_done() is called on the main thread.

--- Parse `git status --porcelain` output into the out table (abs_path → char).
local function parse_status_output(root, text, out)
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    if #line >= 4 then
      local xy   = line:sub(1, 2)
      local path = line:sub(4):gsub("%s+$", "")
      -- Renames are reported as "old -> new"; take the destination.
      path = path:match("^.* %-> (.+)$") or path
      local abs = root .. "/" .. path
      -- Prefer working-tree status (col 2); fall back to index (col 1).
      local s = xy:sub(2, 2)
      if s == " " then s = xy:sub(1, 1) end
      out[abs] = s
    end
  end
end

--- Refresh git data asynchronously.
-- Collects all valid buffer directories, resolves their repo roots (using
-- dir_root_cache to avoid redundant git calls), then runs git status and
-- git branch in parallel.  Calls on_done() with no arguments when complete;
-- callers should call get_git_branch() / get_buffers() afterwards to read
-- the updated data.
-- @param on_done function  Called on the main thread when all jobs finish.
function M.refresh_git_async(on_done)
  -- Collect unique parent directories of all valid buffers.
  local dirs = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        dirs[vim.fn.fnamemodify(name, ":h")] = true
      end
    end
  end

  -- Split into dirs with a known root (cache hit) and dirs that need a
  -- git rev-parse call (cache miss).
  local roots    = {}   -- root → true
  local uncached = {}   -- dirs needing resolution
  for dir in pairs(dirs) do
    local r = dir_root_cache[dir]
    if r ~= nil then
      if r then roots[r] = true end
    else
      uncached[#uncached + 1] = dir
    end
  end

  -- Phase 2: fire git status + branch jobs for all known roots.
  local function run_status_phase()
    local root_list = vim.tbl_keys(roots)
    local statuses  = {}
    local branch    = nil
    local pending   = #root_list + 1  -- +1 accounts for the branch job

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
      vim.system({"git", "rev-parse", "--abbrev-ref", "HEAD"}, {text = true},
        function(r)
          if r.code == 0 then
            local b = r.stdout:gsub("%s+$", "")
            if b ~= "" and b ~= "HEAD" then branch = b end
          end
          finish()
        end)

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
      -- Synchronous fallback for Neovim < 0.10 (no vim.system).
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

      -- Always deliver results asynchronously so callers behave consistently.
      vim.schedule(function()
        git_cache.statuses = statuses
        git_cache.branch   = branch
        on_done()
      end)
    end
  end

  -- Phase 1: resolve uncached dirs, then proceed to phase 2.
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
    -- Synchronous fallback: resolve all dirs then run phase 2.
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

-- ── MRU tracking ─────────────────────────────────────────────────────────────

-- Map from bufnr → vim.uv.hrtime() of the last BufEnter event.
-- Populated by record_mru() called from the BufEnter autocmd in init.lua.
local mru_times = {}

--- Record that bufnr was just entered (used by the mru sort mode).
-- @param bufnr integer
function M.record_mru(bufnr)
  mru_times[bufnr] = vim.uv.hrtime()
end

-- ── Buffer entries ────────────────────────────────────────────────────────────

--- Build a single entry table for bufnr.
-- display_name is derived from config.options.path; parent is only
-- non-empty for path=0 (filename-only mode, parent shown off-screen).
-- @param bufnr    integer
-- @param current  integer  bufnr of the current buffer in the context window
-- @param alternate integer  bufnr of the alternate buffer in the context window
-- @return table
local function make_entry(bufnr, current, alternate)
  local name     = vim.api.nvim_buf_get_name(bufnr)
  local basename = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"

  local display_name, parent
  local path_opt = config.options.path or 0

  if name == "" then
    display_name = "[No Name]"
    parent       = ""
  elseif path_opt == 1 then
    display_name = vim.fn.fnamemodify(name, ":~:.")  -- relative to ~ then cwd
    parent       = ""
  elseif path_opt == 2 then
    display_name = name                              -- absolute path
    parent       = ""
  elseif path_opt == 3 then
    display_name = vim.fn.fnamemodify(name, ":~")   -- tilde-abbreviated
    parent       = ""
  elseif path_opt == 4 then
    -- Immediate parent directory + filename: "plugins/buffergator.lua"
    local parent_dir = vim.fn.fnamemodify(name, ":h:t")
    display_name = parent_dir ~= "" and (parent_dir .. "/" .. basename) or basename
    parent       = ""
  else  -- path_opt == 0
    display_name = basename
    parent       = vim.fn.fnamemodify(name, ":h:~:.")
    if parent == "." then parent = "" end
  end

  return {
    bufnr        = bufnr,
    name         = name,         -- absolute path (used for sorting and git lookup)
    basename     = basename,     -- filename tail (used for highlight offset calc)
    display_name = display_name, -- what is actually rendered
    parent       = parent,       -- non-empty only in path=0 mode
    modified     = vim.bo[bufnr].modified,
    current      = (bufnr == current),
    alternate    = (bufnr == alternate),
    git_status   = (name ~= "" and git_cache.statuses[name]) or " ",
  }
end

-- Sort comparators keyed by config.options.sort.
-- All use entry.name (absolute path) as a tiebreaker so the order is
-- deterministic regardless of which path display mode is active.
local sorters = {
  filepath = function(a, b) return a.name < b.name end,
  bufnum   = function(a, b) return a.bufnr < b.bufnr end,
  basename = function(a, b)
    if a.basename ~= b.basename then return a.basename < b.basename end
    return a.name < b.name
  end,
  mru = function(a, b)
    local ta = mru_times[a.bufnr] or 0
    local tb = mru_times[b.bufnr] or 0
    if ta ~= tb then return ta > tb end  -- most recent first
    return a.name < b.name
  end,
}

--- Ordered list of valid sort mode names, used by the cycle_sort keymap.
M.sort_modes = { "filepath", "bufnum", "basename", "mru" }

--- Return the sorted list of buffer entry tables.
-- Reads entirely from memory (no git I/O).  Resolves current/alternate
-- buffer flags against context_win so they are correct even when called
-- while the sidebar window is active.
-- @param context_win integer|nil  The user's working window handle.
-- @return table[]  Array of entry tables; see make_entry for field docs.
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
