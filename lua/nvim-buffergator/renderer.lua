local M = {}

local catalog = require("nvim-buffergator.catalog")
local ns      = vim.api.nvim_create_namespace("nvim-buffergator")

-- Number of non-entry lines at the top (branch header + blank separator)
M.HEADER_LINES = 2

-- Prefix layout: [NNN] CMG  <basename>   <parent>
--   [NNN] = 5  space = 1  C = 1  M = 1  G = 1  "  " = 2  → basename at col 10
local PREFIX = 10   -- 0-indexed col where basename starts

-- Git status -> highlight group
local git_hl = {
  M = "DiagnosticWarn",
  A = "DiagnosticInfo",
  D = "DiagnosticError",
  R = "DiagnosticInfo",
  ["?"] = "Comment",
}

local function build_line(entry, name_col_width)
  local num_str  = string.format("[%3d]", entry.bufnr)
  local cur_flag = entry.current  and ">" or (entry.alternate and "#" or " ")
  local mod_flag = entry.modified and "+" or " "
  local git_flag = (entry.git_status ~= " ") and entry.git_status or " "

  local basename = entry.basename
  local parent   = entry.parent

  -- Build fixed-layout line
  local line = num_str .. " " .. cur_flag .. mod_flag .. git_flag .. "  " .. basename

  -- Pad basename field to name_col_width so parent dirs align
  local pad = (PREFIX + name_col_width + 2) - #line
  if pad > 0 then
    line = line .. string.rep(" ", pad)
  else
    line = line .. "  "
  end

  local parent_col = #line
  if parent ~= "" then
    line = line .. parent
  end

  -- Highlights: {group, col_start, col_end}  (0-indexed byte cols)
  local hl = {}
  hl[#hl+1] = { "Comment", 0, 5 }                           -- [NNN]

  if entry.current then
    hl[#hl+1] = { "Statement", 6, 7 }
  elseif entry.alternate then
    hl[#hl+1] = { "Special", 6, 7 }
  end

  if entry.modified then
    hl[#hl+1] = { "DiagnosticWarn", 7, 8 }
  end

  local ghl = git_hl[entry.git_status]
  if ghl then
    hl[#hl+1] = { ghl, 8, 9 }
  end

  hl[#hl+1] = { "Bold", PREFIX, PREFIX + #basename }         -- filename

  if parent ~= "" then
    hl[#hl+1] = { "Comment", parent_col, parent_col + #parent }
  end

  return line, hl
end

-- Render into sidebar buffer; returns max display width
function M.render(sidebar_bufnr)
  local branch  = catalog.get_git_branch()
  local entries = catalog.get_buffers()

  -- Calculate max basename length for column alignment
  local max_name = 12  -- minimum
  for _, e in ipairs(entries) do
    if #e.basename > max_name then max_name = #e.basename end
  end

  -- Header lines
  local header = branch
    and ("  \u{e0a0} " .. branch)    -- nerd-font branch icon, falls back gracefully
    or  "  [no git]"
  local lines  = { header, "" }
  local all_hl = { {}, {} }

  for _, entry in ipairs(entries) do
    local line, hl = build_line(entry, max_name)
    lines[#lines+1]   = line
    all_hl[#all_hl+1] = hl
  end

  vim.bo[sidebar_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_bufnr, 0, -1, false, lines)
  vim.bo[sidebar_bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(sidebar_bufnr, ns, 0, -1)
  -- Header highlight
  vim.api.nvim_buf_add_highlight(sidebar_bufnr, ns, "Title", 0, 0, -1)

  for row, hl in ipairs(all_hl) do
    for _, h in ipairs(hl) do
      vim.api.nvim_buf_add_highlight(sidebar_bufnr, ns, h[1], row - 1, h[2], h[3])
    end
  end

  local max_width = 0
  for _, l in ipairs(lines) do
    if #l > max_width then max_width = #l end
  end
  return max_width
end

return M
