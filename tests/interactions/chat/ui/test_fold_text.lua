local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        h.setup_plugin(vim.tbl_deep_extend('force', require('tests.config'), {
          interactions = { chat = { tools = { opts = { folds = { enabled = true } } } } },
        }))
        folds = require('codecompanion.interactions.chat.ui.folds')

        -- A displayed chat buffer whose rows 2-5 are folded, with `summary` as the fold's summary
        function _G.fold_text(summary)
          local bufnr = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'a', 'b', 'c', 'd', 'e', 'f' })
          vim.bo[bufnr].filetype = 'codecompanion'
          vim.cmd('tabnew')
          local winnr = vim.api.nvim_get_current_win()
          vim.api.nvim_win_set_buf(winnr, bufnr)
          folds:setup(winnr)
          vim.cmd('2,5fold')
          folds.fold_summaries[bufnr] = { [1] = summary }
          return vim.fn.foldtextresult(2)
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["fold_text"] = new_set()

T["fold_text"]["renders a summary's own chunks"] = function()
  local text = child.lua_get([[_G.fold_text({
    type = 'tool',
    content = 'ignored',
    chunks = function()
      return { { '* ', 'Comment' }, { 'live state', 'Normal' } }
    end,
  })]])
  h.eq("* live state", text)
end

T["fold_text"]["falls back to the summary's content when its chunks fail"] = function()
  local text = child.lua_get([[_G.fold_text({
    type = 'reasoning',
    content = 'the content',
    chunks = function()
      error('boom')
    end,
  })]])
  h.eq("the content", text)
end

return T
