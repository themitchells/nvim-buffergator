local M = {}

local catalog = require("nvim-buffergator.catalog")

-- Highlight namespace (created once)
local ns = vim.api.nvim_create_namespace("nvim-buffergator")

-- Build a single display line and its highlight ranges
-- Format: [ 42] >+  filename.lua          lua/plugins
local function build_line(entry)
  local num_str    = string.format("[%3d]", entry.bufnr)

  local cur_flag  = entry.current   and ">" or (entry.alternate and "#" or " ")
  local mod_flag  = entry.modified  and "+" or " "
  local flags     = cur_flag .. mod_flag .. "  "          -- 4 chars

  local basename  = entry.basename
  local parent    = entry.parent

  local name_col  = 7                                     -- after "[NNN] "
  local line      = num_str .. " " .. flags .. basename

  -- Pad basename to a fixed width before parent
  local pad_to = 28
  local pad = pad_to - #line
  if pad > 0 then
    line = line .. string.rep(" ", pad)
  else
    line = line .. "  "
  end

  local parent_start = #line
  if parent ~= "" then
    line = line .. parent
  end

  -- Highlight ranges: {hl_group, col_start, col_end}
  local highlights = {}

  -- Buffer number: dimmed
  highlights[#highlights + 1] = { "Comment", 0, 5 }

  -- Current marker
  if entry.current then
    highlights[#highlights + 1] = { "Statement", 6, 7 }
  elseif entry.alternate then
    highlights[#highlights + 1] = { "Special", 6, 7 }
  end

  -- Modified marker
  if entry.modified then
    highlights[#highlights + 1] = { "DiagnosticWarn", 7, 8 }
  end

  -- Filename: bold
  highlights[#highlights + 1] = { "Bold", name_col, name_col + #basename }

  -- Parent dir: dimmed
  if parent ~= "" then
    highlights[#highlights + 1] = { "Comment", parent_start, parent_start + #parent }
  end

  return line, highlights
end

-- Render entries into sidebar buffer; returns max line width
function M.render(sidebar_bufnr)
  local entries = catalog.get_buffers()
  local lines   = {}
  local all_hl  = {}

  for i, entry in ipairs(entries) do
    local line, hls = build_line(entry)
    lines[i]   = line
    all_hl[i]  = hls
  end

  vim.bo[sidebar_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_bufnr, 0, -1, false, lines)
  vim.bo[sidebar_bufnr].modifiable = false

  -- Clear old highlights and apply new ones
  vim.api.nvim_buf_clear_namespace(sidebar_bufnr, ns, 0, -1)
  for row, hls in ipairs(all_hl) do
    for _, hl in ipairs(hls) do
      vim.api.nvim_buf_add_highlight(sidebar_bufnr, ns, hl[1], row - 1, hl[2], hl[3])
    end
  end

  -- Return max line width for auto-resize
  local max_width = 0
  for _, l in ipairs(lines) do
    if #l > max_width then max_width = #l end
  end
  return max_width, entries
end

-- Map from display row (1-based) back to bufnr
function M.bufnr_at_line(line_nr)
  local entries = catalog.get_buffers()
  local e = entries[line_nr]
  return e and e.bufnr or nil
end

return M
