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

        -- A width the user could have chosen, which a rebuilt window would not keep
        vim.api.nvim_win_set_width(_G.second.ui.winnr, 42)
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Registry"] = new_set()

T["Registry"]["cycling hands the window over and keeps its size"] = function()
  local before = child.lua_get([[{
    winnr = _G.second.ui.winnr,
    windows = #vim.api.nvim_list_wins(),
  }]])

  child.lua([[registry.move(_G.second.bufnr, 1)]])

  local after = child.lua_get([[{
    winnr = _G.first.ui.winnr,
    width = vim.api.nvim_win_get_width(_G.first.ui.winnr),
    windows = #vim.api.nvim_list_wins(),
    bufnr = vim.api.nvim_win_get_buf(_G.first.ui.winnr),
  }]])

  h.eq(before.winnr, after.winnr)
  h.eq(before.windows, after.windows)
  h.eq(42, after.width)
  h.eq(child.lua_get("_G.first.bufnr"), after.bufnr)
end

T["Registry"]["the interaction that gave up its window stops claiming it"] = function()
  child.lua([[registry.move(_G.second.bufnr, 1)]])

  h.eq(vim.NIL, child.lua_get("_G.second.ui.winnr"))
  h.eq(false, child.lua_get("_G.second.ui:is_visible()"))
  h.eq(true, child.lua_get("_G.first.ui:is_visible()"))
end

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

T["Registry"]["window options are applied to a chat shown for the first time"] = function()
  local winnr = child.lua_get("_G.second.ui.winnr")

  local result = child.lua_get([[(function()
    -- A buffer that has never been displayed in the window falls back to the
    -- global option values, so make the global the opposite of the chat window's
    vim.go.wrap = false
    _G.third = require('codecompanion.interactions.chat').new({
      buffer_context = { bufnr = 1, filetype = 'lua' },
      adapter = 'test_adapter',
      hidden = true,
    })

    registry.move(_G.second.bufnr, 1)

    return {
      visible = _G.third.ui:is_visible(),
      winnr = _G.third.ui.winnr,
      wrap = vim.api.nvim_get_option_value('wrap', { win = _G.third.ui.winnr, scope = 'local' }),
      foldmethod = vim.api.nvim_get_option_value('foldmethod', { win = _G.third.ui.winnr, scope = 'local' }),
    }
  end)()]])

  h.eq(true, result.visible)
  h.eq(winnr, result.winnr)
  h.eq(true, result.wrap)
  h.eq("manual", result.foldmethod)
end

T["Registry"]["falls back to a new window when the layouts differ"] = function()
  local result = child.lua_get([[(function()
    _G.first.ui.window_opts = { layout = 'float' }
    local handed_over = _G.second.ui.winnr

    registry.move(_G.second.bufnr, 1)

    return {
      relative = vim.api.nvim_win_get_config(_G.first.ui.winnr).relative,
      reused = _G.first.ui.winnr == handed_over,
      second_visible = _G.second.ui:is_visible(),
    }
  end)()]])

  h.eq("editor", result.relative)
  h.eq(false, result.reused)
  h.eq(false, result.second_visible)
end

return T
