local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        registry = require('codecompanion.interactions.shared.registry')

        -- Two chats, of which only the second one stays visible
        _G.first = h.setup_chat_buffer(require('tests.config'))
        _G.second = require('codecompanion.interactions.chat').new({
          buffer_context = { bufnr = 1, filetype = 'lua' },
          adapter = 'test_adapter',
        })
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Registry"] = new_set()

T["Registry"]["a window-local cwd survives a round trip"] = function()
  local before = child.lua_get([[(function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.api.nvim_win_call(_G.second.ui.winnr, function()
      vim.cmd('lcd ' .. dir)
    end)
    return vim.api.nvim_win_call(_G.second.ui.winnr, function()
      return vim.fn.getcwd()
    end)
  end)()]])

  local after = child.lua_get([[(function()
    registry.move(_G.second.bufnr, 1)
    registry.move(_G.first.bufnr, 1)
    return vim.api.nvim_win_call(_G.second.ui.winnr, function()
      return vim.fn.getcwd()
    end)
  end)()]])

  h.eq(before, after)
end

T["Registry"]["hiding the chat that gave up its window leaves the next chat visible"] = function()
  local result = child.lua_get([[(function()
    registry.move(_G.second.bufnr, 1)
    _G.second.ui:hide()
    return { first = _G.first.ui:is_visible(), second = _G.second.ui:is_visible() }
  end)()]])

  h.eq({ first = true, second = false }, result)
end

return T
