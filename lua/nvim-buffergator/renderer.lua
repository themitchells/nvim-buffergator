--- nvim-buffergator renderer
-- Builds the display lines and syntax highlights for the sidebar buffer.
-- Called by view.lua; reads entries from catalog (no I/O of its own).
--
-- Line format:
--   [NNN] CMG  display_name   parent/dir
--    ^^^  |||
--    |    ||+-- G  git working-tree status char (M A D R ? or space)
--    |    |+--- M  buffer-modified flag (+ or space)
--    |    +---- C  current (>) / alternate (#) / none (space)
--    +--------- buffer number, right-aligned in 3-digit field
--
-- Column layout (0-indexed):
--   0-4   [NNN]   → Comment highlight
--   5     space
--   6     C flag  → Statement (current) / Special (alternate)
--   7     M flag  → DiagnosticWarn (modified)
--   8     G flag  → git_hl table
--   9-10  "  "
--   11+   display_name  → NvimBuffergator{Buf,Git,Both}Dirty or Bold
--                          path prefix portion dimmed when path > 0
--   (path=0 only) padding + parent  → Comment

local M = {}

local catalog = require("nvim-buffergator.catalog")
local ns      = vim.api.nvim_create_namespace("nvim-buffergator")

--- Number of non-entry lines at the top of the sidebar (branch header).
local HEADER_LINES = 1
M.HEADER_LINES = HEADER_LINES

--- Byte column where display_name begins (sum of all prefix chars).
local PREFIX = 11

-- Git status character → highlight group for the G flag column.
local git_hl = {
  M = "DiagnosticWarn",   -- modified in working tree
  A = "DiagnosticInfo",   -- added / staged
  D = "DiagnosticError",  -- deleted
  R = "DiagnosticInfo",   -- renamed
  ["?"] = "Comment",      -- untracked
}

--- Define (or re-define) the three filename dirty-state highlight groups.
-- Called once at module load and again on ColorScheme so themes don't break.
local function def_name_hls()
  local warn = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn",  link = false })
  local info = vim.api.nvim_get_hl(0, { name = "DiagnosticInfo",  link = false })
  local err  = vim.api.nvim_get_hl(0, { name = "DiagnosticError", link = false })
  -- Buffer dirty (unsaved): lualine signals modification via a background
  -- colour change on LualineFilenameModifiedBold.  Use that bg as our fg
  -- so the sidebar matches the statusline exactly.  Falls back to
  -- DiagnosticWarn fg if lualine is not loaded or the group has no bg.
  local lualine_mod  = vim.api.nvim_get_hl(0, { name = "LualineFilenameModifiedBold", link = false })
  local buf_dirty_fg = (lualine_mod and lualine_mod.bg) and lualine_mod.bg or warn.fg
  vim.api.nvim_set_hl(0, "NvimBuffergatorBufDirty",  { fg = buf_dirty_fg, bold = true })
  -- Git dirty (working-tree change): cyan, no bold (secondary indicator)
  vim.api.nvim_set_hl(0, "NvimBuffergatorGitDirty",  { fg = info.fg })
  -- Both dirty: red + bold + underline — visually distinct from yellow
  -- even on themes where DiagnosticError and DiagnosticWarn look similar
  vim.api.nvim_set_hl(0, "NvimBuffergatorBothDirty", { fg = err.fg, bold = true, underline = true })
end
def_name_hls()
-- Re-run after every ColorScheme event, but deferred via vim.schedule so
-- we execute after all other ColorScheme handlers (including tinted.lua's
-- customize_highlights which defines LualineFilenameModifiedBold).
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function() vim.schedule(def_name_hls) end,
})

--- Build one display line and its highlight ranges for a buffer entry.
-- @param entry       table   Entry from catalog.get_buffers().
-- @param max_display integer Maximum display_name length across all entries
--                            (used to align the parent column in path=0 mode).
-- @return string, table  The line string and a list of {group, start, end} triples.
local function build_line(entry, max_display)
  local num_str  = string.format("[%3d]", entry.bufnr)
  local cur_flag = entry.current  and ">" or (entry.alternate and "#" or " ")
  local mod_flag = entry.modified and "+" or " "
  local git_flag = (entry.git_status ~= " ") and entry.git_status or " "

  local display_name = entry.display_name
  local parent       = entry.parent

  local line = num_str .. " " .. cur_flag .. mod_flag .. git_flag .. "  " .. display_name

  -- In path=0 mode, pad display_name to a fixed column so all parent
  -- directories align.  Parent is "" for path>0 so this block is skipped.
  local parent_start
  if parent ~= "" then
    local parent_col = PREFIX + max_display + 2
    local pad = parent_col - #line
    line = line .. string.rep(" ", math.max(pad, 2))
    parent_start = #line
    line = line .. parent
  end

  -- ── Highlights ──────────────────────────────────────────────────────────────

  local hl = {}

  -- [NNN] buffer number: dimmed
  hl[#hl+1] = { "Comment", 0, 5 }

  -- Current / alternate indicator
  if entry.current then
    hl[#hl+1] = { "Statement", 6, 7 }
  elseif entry.alternate then
    hl[#hl+1] = { "Special", 6, 7 }
  end

  -- Buffer-modified flag
  if entry.modified then
    hl[#hl+1] = { "DiagnosticWarn", 7, 8 }
  end

  -- Git status character
  local ghl = git_hl[entry.git_status]
  if ghl then
    hl[#hl+1] = { ghl, 8, 9 }
  end

  -- Filename colour: reflects the combination of buffer-dirty and git-dirty.
  local buf_dirty = entry.modified
  local git_dirty = entry.git_status ~= " "
  local name_hl
  if buf_dirty and git_dirty then
    name_hl = "NvimBuffergatorBothDirty"
  elseif buf_dirty then
    name_hl = "NvimBuffergatorBufDirty"
  elseif git_dirty then
    name_hl = "NvimBuffergatorGitDirty"
  else
    name_hl = "Bold"
  end

  -- For path > 0, dim the directory prefix and colour only the basename tail.
  local basename    = entry.basename
  local name_offset = #display_name - #basename
  if name_offset > 0 and display_name:sub(name_offset + 1) == basename then
    hl[#hl+1] = { "Comment", PREFIX, PREFIX + name_offset }
    hl[#hl+1] = { name_hl,   PREFIX + name_offset, PREFIX + #display_name }
  else
    hl[#hl+1] = { name_hl, PREFIX, PREFIX + #display_name }
  end

  -- Parent directory (path=0 only): dimmed
  if parent_start then
    hl[#hl+1] = { "Comment", parent_start, parent_start + #parent }
  end

  return line, hl
end

--- Render the sidebar buffer and return the ideal window width.
-- Writes the header line plus one line per buffer entry, then applies
-- all highlights.  Caller is responsible for resizing the window.
-- @param sidebar_bufnr integer  The sidebar's scratch buffer handle.
-- @param context_win   integer|nil  The user's working window (for current/alt flags).
-- @return integer, table[]  max_width, entries
function M.render(sidebar_bufnr, context_win)
  -- Re-derive highlight colours on every render.  This is cheap (a handful
  -- of API calls) and guarantees we always pick up LualineFilenameModifiedBold
  -- regardless of when lualine/tinted defined it relative to our module load.
  def_name_hls()

  local branch  = catalog.get_git_branch()
  local entries = catalog.get_buffers(context_win)

  -- Determine the widest display_name so all entries can be padded uniformly.
  local max_display = 12  -- minimum column width
  for _, e in ipairs(entries) do
    if #e.display_name > max_display then max_display = #e.display_name end
  end

  -- Build lines and highlight tables.
  local header = branch and ("  @ " .. branch) or "  [no git]"
  local lines  = { header }
  local all_hl = { { { "Title", 0, -1 } } }  -- header → Title highlight

  for _, entry in ipairs(entries) do
    local line, hl = build_line(entry, max_display)
    lines[#lines+1]   = line
    all_hl[#all_hl+1] = hl
  end

  vim.bo[sidebar_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_bufnr, 0, -1, false, lines)
  vim.bo[sidebar_bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(sidebar_bufnr, ns, 0, -1)
  for row, hl in ipairs(all_hl) do
    for _, h in ipairs(hl) do
      vim.api.nvim_buf_add_highlight(sidebar_bufnr, ns, h[1], row - 1, h[2], h[3])
    end
  end

  -- Width is sized to show filenames only.  Parent always starts at
  -- PREFIX + max_display + 2, so stopping at PREFIX + max_display + 1
  -- keeps it one column off-screen.
  local max_width = PREFIX + max_display + 1

  return max_width, entries
end

return M
