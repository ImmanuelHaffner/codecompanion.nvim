local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        -- The test config ships tool folds disabled
        h.setup_plugin(vim.tbl_deep_extend('force', require('tests.config'), {
          interactions = { chat = { tools = { opts = { folds = { enabled = true } } } } },
        }))
        folds = require('codecompanion.interactions.chat.ui.folds')

        -- A buffer with enough lines to fold, displayed nowhere
        function _G.scratch()
          local bufnr = vim.api.nvim_create_buf(false, true)
          local lines = {}
          for i = 1, 12 do
            lines[i] = 'line ' .. i
          end
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
          return bufnr
        end

        function _G.display(bufnr)
          vim.cmd('tabnew')
          local winnr = vim.api.nvim_get_current_win()
          vim.api.nvim_win_set_buf(winnr, bufnr)
          return winnr
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Folds"] = new_set()

T["Folds"]["a fold requested while the buffer has no window is deferred"] = function()
  local result = child.lua_get([[(function()
    local bufnr = _G.scratch()

    folds:create_tool_fold(bufnr, 1, 5, 'Tool output')
    local queued = folds.pending[bufnr] and folds.pending[bufnr][1]

    folds:setup(_G.display(bufnr))

    return {
      queued = queued,
      drained = folds.pending[bufnr] == nil,
      foldlevel = vim.fn.foldlevel(3),
      foldclosed = vim.fn.foldclosed(3),
    }
  end)()]])

  h.eq(5, result.queued)
  h.eq(true, result.drained)
  h.eq(1, result.foldlevel)
  h.eq(2, result.foldclosed)
end

T["Folds"]["a fold requested while the buffer is displayed is created at once"] = function()
  local result = child.lua_get([[(function()
    local bufnr = _G.scratch()
    folds:setup(_G.display(bufnr))

    folds:create_tool_fold(bufnr, 1, 5, 'Tool output')

    return {
      pending = folds.pending[bufnr] == nil,
      foldlevel = vim.fn.foldlevel(3),
      foldclosed = vim.fn.foldclosed(3),
    }
  end)()]])

  h.eq(true, result.pending)
  h.eq(1, result.foldlevel)
  h.eq(2, result.foldclosed)
end

T["Folds"]["a region requested repeatedly while hidden is queued once"] = function()
  local queued = child.lua_get([[(function()
    local bufnr = _G.scratch()
    for _ = 1, 3 do
      folds:create_tool_fold(bufnr, 1, 5, 'Tool output')
    end
    return vim.tbl_count(folds.pending[bufnr])
  end)()]])

  h.eq(1, queued)
end

T["Folds"]["cleanup drops deferred folds"] = function()
  local result = child.lua_get([[(function()
    local bufnr = _G.scratch()
    folds:create_tool_fold(bufnr, 1, 5, 'Tool output')
    local queued = folds.pending[bufnr] ~= nil

    folds:cleanup(bufnr)

    return { queued = queued, drained = folds.pending[bufnr] == nil }
  end)()]])

  h.eq(true, result.queued)
  h.eq(true, result.drained)
end

return T
