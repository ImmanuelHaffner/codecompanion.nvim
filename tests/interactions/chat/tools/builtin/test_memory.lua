local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua([[
        -- Setup test directory structure
        _G.TEST_CWD = vim.fn.tempname()
        _G.MEMORY_DIR = 'memories'
        _G.MEMORY_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.MEMORY_DIR)

        -- Create test directory structure
        vim.fn.mkdir(_G.MEMORY_DIR_ABSOLUTE, 'p')

        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        -- Change to the temporary directory
        vim.uv.chdir(_G.TEST_CWD)
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.fn.delete, _G.TEST_CWD, 'rf')
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["view"] = new_set()

T["view"]["can view empty directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_1",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories"
        })
      },
    }

    -- Execute the tool and capture result
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.expect_match(output.data, "Directory: /memories")
  h.expect_match(output.data, "%(empty%)")
end

T["view"]["can view directory with files"] = function()
  child.lua([[
    -- Create some test files
    local test_file_1 = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "test1.txt")
    local test_file_2 = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "test2.txt")
    vim.fn.writefile({"Hello"}, test_file_1)
    vim.fn.writefile({"World"}, test_file_2)

    local tool_call = {
      id = "test_call_2",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.expect_match(output.data, "Directory: /memories")
  h.expect_match(output.data, "test1%.txt")
  h.expect_match(output.data, "test2%.txt")
end

T["view"]["lists a directory two levels deep, skipping hidden items and node_modules"] = function()
  child.lua([[
    vim.fn.mkdir(vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "projects", "deep"), "p")
    vim.fn.mkdir(vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "node_modules"), "p")
    vim.fn.writefile({"Top"}, vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "top.txt"))
    vim.fn.writefile({"Nested"}, vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "projects", "nested.txt"))
    vim.fn.writefile({"Too deep"}, vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "projects", "deep", "buried.txt"))
    vim.fn.writefile({"Hidden"}, vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, ".hidden.txt"))
    vim.fn.writefile({"Vendored"}, vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "node_modules", "vendored.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "view", path = "/memories" })
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.expect_match(output.data, "top%.txt")
  h.expect_match(output.data, "projects/nested%.txt")
  h.eq(nil, output.data:find("buried%.txt"))
  h.eq(nil, output.data:find("hidden%.txt"))
  h.eq(nil, output.data:find("vendored%.txt"))
end

T["view"]["can view file content"] = function()
  child.lua([[
    -- Create a test file
    local test_file = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "test.txt")
    vim.fn.writefile({"Line 1", "Line 2", "Line 3"}, test_file)

    local tool_call = {
      id = "test_call_3",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories/test.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.eq(output.data, "Line 1\nLine 2\nLine 3\n")
end

T["view"]["truncates a file that is over the character limit"] = function()
  child.lua([[
    local lines = {}
    for i = 1, 2000 do
      lines[i] = string.rep("é", 20)
    end
    vim.fn.writefile(lines, vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "big.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "view", path = "/memories/big.txt" })

    local notice = _G.result.data:find("\n\n%[Truncated")
    _G.chars = vim.fn.strcharlen(_G.result.data:sub(1, notice - 1))
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.expect_match(output.data, "%[Truncated at 16000 characters")
  h.eq(16000, child.lua_get("_G.chars"))
end

T["view"]["can view file content with line range"] = function()
  child.lua([[
    -- Create a test file
    local test_file = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "test.txt")
    vim.fn.writefile({"Line 1", "Line 2", "Line 3", "Line 4", "Line 5"}, test_file)

    local tool_call = {
      id = "test_call_4",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories/test.txt",
          view_range = {2, 4}
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.eq(output.data, "Line 2\nLine 3\nLine 4")
end

T["view"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_5",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/etc/passwd"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories")
end

T["view"]["rejects directory traversal"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_6",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories/../etc/passwd"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the /memories directory")
end

T["view"]["handles non-existent path"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_7",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories/nonexistent.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "error")
  h.expect_match(output.data, "Path does not exist")
end

T["create"] = new_set()

T["create"]["can create a file"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_8",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/new_file.txt",
          file_text = "Hello, World!"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Created file: /memories/new_file.txt")

  -- Verify file was created
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new_file.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Hello, World!" })
end

T["create"]["can create a file with multiple lines"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_9",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/multi_line.txt",
          file_text = "Line 1\nLine 2\nLine 3"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file content
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multi_line.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["create"]["can create a file in a subdirectory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_10",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/subdir/nested_file.txt",
          file_text = "Nested content"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file was created in subdirectory
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "subdir", "nested_file.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Nested content" })
end

T["create"]["can overwrite an existing file"] = function()
  child.lua([[
    -- Create initial file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "existing.txt")
    vim.fn.writefile({"Old content"}, file_path)

    local tool_call = {
      id = "test_call_11",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/existing.txt",
          file_text = "New content"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file was overwritten
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "existing.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "New content" })
end

T["create"]["can create an empty file"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_12",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/empty.txt",
          file_text = ""
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify empty file exists
  local exists = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty.txt")
    return vim.uv.fs_stat(file_path) ~= nil
  ]])
  h.eq(exists, true)
end

T["create"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_13",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/tmp/evil.txt",
          file_text = "Should not be created"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories")
end

T["create"]["rejects directory traversal"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_14",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/../tmp/evil.txt",
          file_text = "Should not be created"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the /memories directory")
end

T["str_replace"] = new_set()

T["str_replace"]["can replace text in a file"] = function()
  child.lua([[
    -- Create a file with initial content
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "replace_test.txt")
    vim.fn.writefile({"Hello World", "This is a test"}, file_path)

    local tool_call = {
      id = "test_call_15",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/replace_test.txt",
          old_str = "Hello World",
          new_str = "Goodbye World"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Replaced text in file: /memories/replace_test.txt")

  -- Verify the replacement
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "replace_test.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Goodbye World", "This is a test" })
end

T["str_replace"]["replaces only first occurrence"] = function()
  child.lua([[
    -- Create a file with duplicate content
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "duplicate.txt")
    vim.fn.writefile({"foo bar foo", "foo baz"}, file_path)

    local tool_call = {
      id = "test_call_16",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/duplicate.txt",
          old_str = "foo",
          new_str = "bar"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify only first occurrence was replaced
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "duplicate.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "bar bar foo", "foo baz" })
end

T["str_replace"]["can replace multiline text"] = function()
  child.lua([[
    -- Create a file with multiline content
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multiline.txt")
    vim.fn.writefile({"Line 1", "Line 2", "Line 3"}, file_path)

    local tool_call = {
      id = "test_call_17",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/multiline.txt",
          old_str = "Line 2",
          new_str = "Modified Line 2"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multiline.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Modified Line 2", "Line 3" })
end

T["str_replace"]["handles special characters"] = function()
  child.lua([[
    -- Create a file with special characters
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "special.txt")
    vim.fn.writefile({"Test: $var = 100%"}, file_path)

    local tool_call = {
      id = "test_call_18",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/special.txt",
          old_str = "$var = 100%",
          new_str = "$var = 50%"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "special.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Test: $var = 50%" })
end

T["str_replace"]["fails when string not found"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "not_found.txt")
    vim.fn.writefile({"Hello World"}, file_path)

    local tool_call = {
      id = "test_call_19",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/not_found.txt",
          old_str = "Nonexistent String",
          new_str = "New String"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "String not found in file")
end

T["str_replace"]["fails when file does not exist"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_20",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/nonexistent.txt",
          old_str = "old",
          new_str = "new"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "File does not exist")
end

T["str_replace"]["fails when path is a directory"] = function()
  child.lua([[
    -- Create a subdirectory
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "subdir")
    vim.fn.mkdir(dir_path, "p")

    local tool_call = {
      id = "test_call_21",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/subdir",
          old_str = "old",
          new_str = "new"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Cannot perform str_replace on a directory")
end

T["str_replace"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_22",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/tmp/file.txt",
          old_str = "old",
          new_str = "new"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories")
end

T["insert"] = new_set()

T["insert"]["can insert text at beginning"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "insert_test.txt")
    vim.fn.writefile({"Line 2", "Line 3"}, file_path)

    local tool_call = {
      id = "test_call_23",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/insert_test.txt",
          insert_line = 1,
          insert_text = "Line 1"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Inserted text in file: /memories/insert_test.txt")

  -- Verify the insertion
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "insert_test.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["insert"]["can insert text in middle"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "middle.txt")
    vim.fn.writefile({"Line 1", "Line 3"}, file_path)

    local tool_call = {
      id = "test_call_24",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/middle.txt",
          insert_line = 2,
          insert_text = "Line 2"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "middle.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["insert"]["can insert text at end"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "end.txt")
    vim.fn.writefile({"Line 1", "Line 2"}, file_path)

    local tool_call = {
      id = "test_call_25",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/end.txt",
          insert_line = 3,
          insert_text = "Line 3"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "end.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["insert"]["can insert into empty file"] = function()
  child.lua([[
    -- Create empty file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty_insert.txt")
    vim.fn.writefile({}, file_path)

    local tool_call = {
      id = "test_call_26",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/empty_insert.txt",
          insert_line = 1,
          insert_text = "First line"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty_insert.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "First line" })
end

T["insert"]["can insert multiline text"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multiline_insert.txt")
    vim.fn.writefile({"Line 1"}, file_path)

    local tool_call = {
      id = "test_call_27",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/multiline_insert.txt",
          insert_line = 2,
          insert_text = "Line 2\nLine 3"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multiline_insert.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["insert"]["fails with invalid line number (too low)"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "invalid_low.txt")
    vim.fn.writefile({"Line 1"}, file_path)

    local tool_call = {
      id = "test_call_28",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/invalid_low.txt",
          insert_line = 0,
          insert_text = "Should fail"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Invalid line number")
end

T["insert"]["fails with invalid line number (too high)"] = function()
  child.lua([[
    -- Create a file with 2 lines
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "invalid_high.txt")
    vim.fn.writefile({"Line 1", "Line 2"}, file_path)

    local tool_call = {
      id = "test_call_29",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/invalid_high.txt",
          insert_line = 10,
          insert_text = "Should fail"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Invalid line number")
end

T["insert"]["fails when file does not exist"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_30",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/nonexistent.txt",
          insert_line = 1,
          insert_text = "Should fail"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "File does not exist")
end

T["insert"]["fails when path is a directory"] = function()
  child.lua([[
    -- Create a subdirectory
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "insert_dir")
    vim.fn.mkdir(dir_path, "p")

    local tool_call = {
      id = "test_call_31",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/insert_dir",
          insert_line = 1,
          insert_text = "Should fail"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Cannot perform insert on a directory")
end

T["insert"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_32",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/tmp/file.txt",
          insert_line = 1,
          insert_text = "Should fail"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories")
end

T["insert"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_32",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/tmp/file.txt",
          insert_line = 1,
          insert_text = "Should fail"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories")
end

T["delete"] = new_set()

T["delete"]["can delete a file"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "delete_me.txt")
    vim.fn.writefile({"Content to delete"}, file_path)

    local tool_call = {
      id = "test_call_33",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/delete_me.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Deleted: /memories/delete_me.txt")

  -- Verify file was deleted
  local exists = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "delete_me.txt")
    return vim.uv.fs_stat(file_path) ~= nil
  ]])
  h.eq(exists, false)
end

T["delete"]["can delete an empty directory"] = function()
  child.lua([[
    -- Create an empty directory
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty_dir")
    vim.fn.mkdir(dir_path, "p")

    local tool_call = {
      id = "test_call_34",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/empty_dir"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify directory was deleted
  local exists = child.lua([[
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty_dir")
    return vim.uv.fs_stat(dir_path) ~= nil
  ]])
  h.eq(exists, false)
end

T["delete"]["can delete a directory with files"] = function()
  child.lua([[
    -- Create a directory with files
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "dir_with_files")
    vim.fn.mkdir(dir_path, "p")
    vim.fn.writefile({"File 1"}, vim.fs.joinpath(dir_path, "file1.txt"))
    vim.fn.writefile({"File 2"}, vim.fs.joinpath(dir_path, "file2.txt"))

    local tool_call = {
      id = "test_call_35",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/dir_with_files"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify directory was deleted recursively
  local exists = child.lua([[
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "dir_with_files")
    return vim.uv.fs_stat(dir_path) ~= nil
  ]])
  h.eq(exists, false)
end

T["delete"]["can delete nested directories"] = function()
  child.lua([[
    -- Create nested directory structure
    local parent_dir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "parent")
    local child_dir = vim.fs.joinpath(parent_dir, "child")
    vim.fn.mkdir(child_dir, "p")
    vim.fn.writefile({"Nested file"}, vim.fs.joinpath(child_dir, "nested.txt"))

    local tool_call = {
      id = "test_call_36",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/parent"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify entire structure was deleted
  local exists = child.lua([[
    local parent_dir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "parent")
    return vim.uv.fs_stat(parent_dir) ~= nil
  ]])
  h.eq(exists, false)
end

T["delete"]["fails when file does not exist"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_37",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/nonexistent.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path does not exist")
end

T["delete"]["fails when trying to delete root memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_38",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Cannot delete the root directory")
end

T["delete"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_39",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/tmp/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories")
end

T["delete"]["rejects directory traversal"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_40",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/../tmp/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the /memories directory")
end

T["delete"]["rejects directory traversal"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_40",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/../tmp/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the /memories directory")
end

T["rename"] = new_set()

T["rename"]["can rename a file"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old_name.txt")
    vim.fn.writefile({"File content"}, file_path)

    local tool_call = {
      id = "test_call_41",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/old_name.txt",
          new_path = "/memories/new_name.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Renamed /memories/old_name.txt to /memories/new_name.txt")

  -- Verify old file doesn't exist
  local old_exists = child.lua([[
    local old_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old_name.txt")
    return vim.uv.fs_stat(old_path) ~= nil
  ]])
  h.eq(old_exists, false)

  -- Verify new file exists with same content
  local content = child.lua([[
    local new_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new_name.txt")
    return vim.fn.readfile(new_path)
  ]])
  h.eq(content, { "File content" })
end

T["rename"]["can rename a directory"] = function()
  child.lua([[
    -- Create a directory with a file
    local old_dir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old_dir")
    vim.fn.mkdir(old_dir, "p")
    vim.fn.writefile({"Content"}, vim.fs.joinpath(old_dir, "file.txt"))

    local tool_call = {
      id = "test_call_42",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/old_dir",
          new_path = "/memories/new_dir"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify old directory doesn't exist
  local old_exists = child.lua([[
    local old_dir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old_dir")
    return vim.uv.fs_stat(old_dir) ~= nil
  ]])
  h.eq(old_exists, false)

  -- Verify new directory exists with file
  local file_exists = child.lua([[
    local new_file = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new_dir", "file.txt")
    return vim.uv.fs_stat(new_file) ~= nil
  ]])
  h.eq(file_exists, true)
end

T["rename"]["can move file to subdirectory"] = function()
  child.lua([[
    -- Create a file and subdirectory
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    vim.fn.writefile({"Content"}, file_path)

    local subdir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "subdir")
    vim.fn.mkdir(subdir, "p")

    local tool_call = {
      id = "test_call_43",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/file.txt",
          new_path = "/memories/subdir/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file was moved
  local old_exists = child.lua([[
    local old_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    return vim.uv.fs_stat(old_path) ~= nil
  ]])
  h.eq(old_exists, false)

  local new_exists = child.lua([[
    local new_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "subdir", "file.txt")
    return vim.uv.fs_stat(new_path) ~= nil
  ]])
  h.eq(new_exists, true)
end

T["rename"]["creates parent directories if needed"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    vim.fn.writefile({"Content"}, file_path)

    local tool_call = {
      id = "test_call_44",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/file.txt",
          new_path = "/memories/new/nested/path/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file exists in new location
  local new_exists = child.lua([[
    local new_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new", "nested", "path", "file.txt")
    return vim.uv.fs_stat(new_path) ~= nil
  ]])
  h.eq(new_exists, true)
end

T["rename"]["fails when source does not exist"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_45",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/nonexistent.txt",
          new_path = "/memories/new.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Source path does not exist")
end

T["rename"]["fails when destination already exists"] = function()
  child.lua([[
    -- Create both files
    local old_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old.txt")
    local new_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new.txt")
    vim.fn.writefile({"Old"}, old_path)
    vim.fn.writefile({"New"}, new_path)

    local tool_call = {
      id = "test_call_46",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/old.txt",
          new_path = "/memories/new.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Destination path already exists")
end

T["rename"]["rejects old_path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_47",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/tmp/file.txt",
          new_path = "/memories/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories")
end

T["rename"]["rejects new_path outside memory directory"] = function()
  child.lua([[
    -- Create source file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    vim.fn.writefile({"Content"}, file_path)

    local tool_call = {
      id = "test_call_48",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/file.txt",
          new_path = "/tmp/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories")
end

T["rename"]["rejects directory traversal in old_path"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_49",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/../tmp/file.txt",
          new_path = "/memories/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the /memories directory")
end

T["rename"]["rejects directory traversal in new_path"] = function()
  child.lua([[
    -- Create source file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    vim.fn.writefile({"Content"}, file_path)

    local tool_call = {
      id = "test_call_50",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/file.txt",
          new_path = "/memories/../tmp/file.txt"
        })
      },
    }

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = builtin.cmds[1](builtin, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the /memories directory")
end

T["whitelist"] = new_set()

T["whitelist"]["can view a whitelisted directory"] = function()
  child.lua([[
    -- Create a whitelisted directory with a file
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")
    vim.fn.writefile({"Whitelisted content"}, vim.fs.joinpath(_G.WHITELIST_DIR, "notes.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } }
    local args = { command = "view", path = "/notes" }

    -- Simulate self.tool.opts by wrapping
    local self_mock = { tool = tool }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, args)
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "notes%.txt")

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["can view a file in a whitelisted directory"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")
    vim.fn.writefile({"Line 1", "Line 2"}, vim.fs.joinpath(_G.WHITELIST_DIR, "file.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, { command = "view", path = "/notes/file.txt" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "success")
  h.eq(output.data, "Line 1\nLine 2\n")

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["can create a file in a whitelisted directory"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, { command = "create", path = "/notes/new.txt", file_text = "New content" })
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    return vim.fn.readfile(vim.fs.joinpath(_G.WHITELIST_DIR, "new.txt"))
  ]])
  h.eq(content, { "New content" })

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["can str_replace in a whitelisted file"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")
    vim.fn.writefile({"Hello World"}, vim.fs.joinpath(_G.WHITELIST_DIR, "file.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, {
      command = "str_replace",
      path = "/notes/file.txt",
      old_str = "Hello World",
      new_str = "Goodbye World",
    })
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    return vim.fn.readfile(vim.fs.joinpath(_G.WHITELIST_DIR, "file.txt"))
  ]])
  h.eq(content, { "Goodbye World" })

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["can delete a file in a whitelisted directory"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")
    vim.fn.writefile({"Content"}, vim.fs.joinpath(_G.WHITELIST_DIR, "delete_me.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, { command = "delete", path = "/notes/delete_me.txt" })
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local exists = child.lua([[
    return vim.uv.fs_stat(vim.fs.joinpath(_G.WHITELIST_DIR, "delete_me.txt")) ~= nil
  ]])
  h.eq(exists, false)

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["cannot delete the whitelisted root directory"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, { command = "delete", path = "/notes" })
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Cannot delete the root directory")

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["rejects traversal out of whitelisted directory"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, { command = "view", path = "/notes/../etc/passwd" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the /notes directory")

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["rejects paths not matching any allowed prefix"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, { command = "view", path = "/etc/passwd" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of: /memories, /notes")

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["memories still works when whitelisted paths are set"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")

    -- Create a file in the memories directory
    vim.fn.writefile({"Memory content"}, vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "note.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, { command = "view", path = "/memories/note.txt" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "success")
  h.eq(output.data, "Memory content\n")

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["can rename within whitelisted directory"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")
    vim.fn.writefile({"Content"}, vim.fs.joinpath(_G.WHITELIST_DIR, "old.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, {
      command = "rename",
      old_path = "/notes/old.txt",
      new_path = "/notes/new.txt",
    })
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local old_exists = child.lua([[
    return vim.uv.fs_stat(vim.fs.joinpath(_G.WHITELIST_DIR, "old.txt")) ~= nil
  ]])
  h.eq(old_exists, false)

  local content = child.lua([[
    return vim.fn.readfile(vim.fs.joinpath(_G.WHITELIST_DIR, "new.txt"))
  ]])
  h.eq(content, { "Content" })

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["prefix without leading slash is normalized"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")
    vim.fn.writefile({"Content"}, vim.fs.joinpath(_G.WHITELIST_DIR, "file.txt"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    -- as = "notes" without leading slash
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    _G.result = builtin.cmds[1](self_mock, { command = "view", path = "/notes/file.txt" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "success")
  h.eq(output.data, "Content\n")

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["whitelist"]["prevents prefix collision with similar names"] = function()
  child.lua([[
    _G.WHITELIST_DIR = vim.fn.tempname()
    vim.fn.mkdir(_G.WHITELIST_DIR, "p")

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local self_mock = { tool = { opts = { whitelist = { { path = _G.WHITELIST_DIR, as = "/notes" } } } } }
    setmetatable(self_mock, { __index = builtin })

    -- "/notesbackup/file.txt" should NOT match the "/notes" prefix
    _G.result = builtin.cmds[1](self_mock, { command = "view", path = "/notesbackup/file.txt" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with one of")

  child.lua([[ pcall(vim.fn.delete, _G.WHITELIST_DIR, "rf") ]])
end

T["validation"] = new_set()

T["validation"]["returns error for missing path on view"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "view" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "requires a 'path' parameter")
end

T["validation"]["returns error for missing path on create"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "create", file_text = "content" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "requires a 'path' parameter")
end

T["validation"]["returns error for missing old_str on str_replace"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "str_replace", path = "/memories/file.txt" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "requires an 'old_str' parameter")
end

T["validation"]["returns error for missing insert_line on insert"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "insert", path = "/memories/file.txt", insert_text = "text" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "requires an 'insert_line' parameter")
end

T["validation"]["returns error for missing insert_text on insert"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "insert", path = "/memories/file.txt", insert_line = 1 })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "requires an 'insert_text' parameter")
end

T["validation"]["returns error for missing old_path on rename"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "rename", new_path = "/memories/new.txt" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "requires an 'old_path' parameter")
end

T["validation"]["returns error for missing new_path on rename"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "rename", old_path = "/memories/old.txt" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "requires a 'new_path' parameter")
end

T["validation"]["rejects null bytes in path"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    _G.result = builtin.cmds[1](builtin, { command = "view", path = "/memories/file\0.txt" })
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "invalid characters")
end

-- FORK(memory-cwd): the memory tool must follow a change of the working directory
T["cwd"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        _G.OTHER_CWD = vim.fn.tempname()
        vim.fn.mkdir(vim.fs.joinpath(_G.OTHER_CWD, "memories"), "p")
        vim.fn.writefile({ "in first" }, vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "first.md"))
        vim.fn.writefile({ "in other" }, vim.fs.joinpath(_G.OTHER_CWD, "memories", "other.md"))

        chat, tools = h.setup_chat_buffer({
          interactions = { chat = { tools = { memory = { opts = { require_approval_before = false } } } } },
        })
        chat.tool_registry:add("memory")

        -- The memory index the LLM is shown
        _G.memory_prompt = function()
          for _, message in ipairs(chat.messages) do
            if (message.content or ""):find("memory directory", 1, true) then
              return message.content
            end
          end
        end

        -- A request, which is when the chat fixes its memory root
        _G.request = function()
          h.send_to_llm(chat, "ok")
        end

        -- A memory call through the orchestrator, returning what the LLM gets back
        _G.call = function(args)
          local n = #chat.messages
          tools:execute(chat, {
            {
              id = "cwd_call_" .. n,
              type = "function",
              ["function"] = { name = "memory", arguments = vim.json.encode(args) },
            },
          })
          vim.wait(5000, function()
            return #chat.messages > n and chat.tool_orchestrator == nil
          end, 10)
          return chat.messages[#chat.messages].content
        end
        _G.view = function(path)
          return _G.call({ command = "view", path = path })
        end

        -- A memory command run directly for the chat, returning its status and data
        _G.run = function(args)
          local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
          return builtin.cmds[1]({ chat = chat }, args)
        end

        -- The chat's approval mode
        _G.mode = function(mode)
          -- The orchestrator keys approvals on the Tools object's buffer, which the harness sets to 1
          require("codecompanion.interactions.chat.tools.approvals"):set_mode(tools.bufnr, { mode = mode })
        end

        -- A rejection asks for a reason; answer it rather than block the headless child
        vim.ui.input = function(_, cb)
          cb("rejected by the spec")
        end

        -- Answer every approval prompt with the choice labelled `label`, recording the prompts in _G.prompts
        _G.answer = function(label)
          _G.prompts = {}
          require("codecompanion.interactions.chat.helpers.approval_prompt").request = function(_, opts)
            table.insert(_G.prompts, opts.prompt)
            for _, choice in ipairs(opts.choices) do
              if choice.label == label then
                return choice.callback()
              end
            end
          end
        end

        -- A directory below the chat's working directory, with memory of its own
        _G.SUB = vim.fs.joinpath(_G.TEST_CWD, "sub")
        vim.fn.mkdir(vim.fs.joinpath(_G.SUB, "memories"), "p")
        vim.fn.writefile({ "in sub" }, vim.fs.joinpath(_G.SUB, "memories", "sub.md"))

      ]])
    end,
    post_case = function()
      child.lua([[pcall(vim.fn.delete, _G.OTHER_CWD, "rf")]])
    end,
  },
})

T["cwd"]["the index lists the new working directory's memories"] = function()
  h.expect_contains("/memories/first.md", child.lua_get("_G.memory_prompt()"))

  child.lua([[
    vim.cmd.cd(_G.OTHER_CWD)
    _G.request()
  ]])

  local prompt = child.lua_get("_G.memory_prompt()")
  h.expect_contains("/memories/other.md", prompt)
  h.eq(prompt:find("/memories/first.md", 1, true), nil)
end

T["cwd"]["a call reaches the new working directory's memories"] = function()
  child.lua([[vim.cmd.cd(_G.OTHER_CWD)]])

  h.expect_contains("in other", child.lua_get([[_G.view("/memories/other.md")]]))
end

T["cwd"]["follows :cd with the chat shown"] = function()
  child.lua([[
    vim.cmd.cd(_G.OTHER_CWD)
    _G.request()
  ]])

  h.expect_contains("/memories/other.md", child.lua_get("_G.memory_prompt()"))
  h.expect_contains("in other", child.lua_get([[_G.view("/memories/other.md")]]))
end

T["cwd"]["follows :tcd in the chat's tab"] = function()
  child.lua([[
    vim.cmd.tcd(_G.OTHER_CWD)
    _G.request()
  ]])

  h.expect_contains("/memories/other.md", child.lua_get("_G.memory_prompt()"))
end

T["cwd"]["ignores :lcd in another window, and focus"] = function()
  child.lua([[
    vim.cmd("vsplit | enew")
    vim.cmd.lcd(_G.OTHER_CWD)
    _G.request()
  ]])

  h.expect_contains("/memories/first.md", child.lua_get("_G.memory_prompt()"))
  -- Focus is still in the window with the local cwd
  h.expect_contains("in first", child.lua_get([[_G.view("/memories/first.md")]]))
end

T["cwd"]["a hidden chat keeps the cwd of its last window"] = function()
  local has_window = child.lua([[
    _G.request()
    chat.ui:hide()
    vim.cmd.cd(_G.OTHER_CWD)
    _G.request()
    return require("codecompanion.utils.ui").buf_get_win(chat.bufnr) ~= nil
  ]])

  h.eq(false, has_window)
  h.expect_contains("/memories/first.md", child.lua_get("_G.memory_prompt()"))
end

T["cwd"]["a chat in another tab follows that tab"] = function()
  child.lua([[
    vim.cmd.tcd(_G.OTHER_CWD)
    vim.cmd.tabnew()
    vim.cmd.tcd(_G.TEST_CWD)
    _G.request()
  ]])

  h.expect_contains("/memories/other.md", child.lua_get("_G.memory_prompt()"))
end

T["cwd"]["the root stays fixed until the next request"] = function()
  child.lua([[
    _G.request()
    vim.cmd.cd(_G.OTHER_CWD)
  ]])

  h.expect_contains("in first", child.lua_get([[_G.view("/memories/first.md")]]))

  child.lua([[_G.request()]])
  h.expect_contains("in other", child.lua_get([[_G.view("/memories/other.md")]]))
end

T["cwd"]["the index names its directory"] = function()
  local res = child.lua([[
    _G.request()
    local listed = _G.memory_prompt()

    _G.EMPTY_CWD = vim.fn.tempname()
    vim.fn.mkdir(_G.EMPTY_CWD, "p")
    vim.cmd.cd(_G.EMPTY_CWD)
    _G.request()
    local empty = _G.memory_prompt()
    pcall(vim.fn.delete, _G.EMPTY_CWD, "rf")

    return {
      listed = listed,
      empty = empty,
      first = vim.fs.basename(_G.TEST_CWD) .. "/memories`",
      second = vim.fs.basename(_G.EMPTY_CWD) .. "/memories`",
    }
  ]])

  h.expect_contains("Below is everything in your memory directory `/memories` (`", res.listed)
  h.expect_contains(res.first, res.listed)
  h.expect_contains("Your memory directory `/memories` (`", res.empty)
  h.expect_contains(res.second .. ") is empty", res.empty)
end

T["cwd"]["a cwd below the working directory reaches its memory"] = function()
  local res = child.lua([[
    local viewed = _G.call({ command = "view", path = "/memories/sub.md", cwd = _G.SUB })
    local created = _G.call({ command = "create", path = "/memories/new.md", file_text = "new", cwd = _G.SUB })

    -- One without a memories directory yet gets one
    local fresh = vim.fs.joinpath(_G.TEST_CWD, "fresh")
    vim.fn.mkdir(fresh, "p")
    local fresh_created = _G.run({ command = "create", path = "/memories/a.md", file_text = "a", cwd = fresh })

    return {
      viewed = viewed,
      created = created,
      sub = vim.fn.fnamemodify(_G.SUB, ":~"),
      written = vim.fn.readfile(vim.fs.joinpath(_G.SUB, "memories", "new.md")),
      own = vim.uv.fs_stat(vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new.md")) ~= nil,
      fresh = fresh_created.status,
      fresh_written = vim.fn.readfile(vim.fs.joinpath(fresh, "memories", "a.md")),
    }
  ]])

  h.expect_contains("in sub", res.viewed)
  h.expect_contains('cwd="' .. res.sub .. '"', res.viewed)
  h.expect_contains("in `" .. res.sub .. "/memories`", res.created)
  h.eq({ "new" }, res.written)
  h.eq(false, res.own)
  h.eq("success", res.fresh)
  h.eq({ "a" }, res.fresh_written)
end

T["cwd"]["the chat's own working directory counts as omitted"] = function()
  local res = child.lua([[
    return {
      physical = _G.call({ command = "view", path = "/memories/first.md", cwd = vim.fn.getcwd() }),
      lexical = _G.run({ command = "view", path = "/memories/first.md", cwd = _G.TEST_CWD }),
      empty = _G.run({ command = "view", path = "/memories/first.md", cwd = "" }),
      null = _G.run({ command = "view", path = "/memories/first.md", cwd = vim.NIL }),
    }
  ]])

  h.expect_contains("in first", res.physical)
  h.eq(nil, res.physical:find('cwd="', 1, true))
  h.eq("in first\n", res.lexical.data)
  h.eq("in first\n", res.empty.data)
  h.eq("in first\n", res.null.data)
end

T["cwd"]["a bad cwd is an error, and nothing is created"] = function()
  local res = child.lua([[
    vim.fn.writefile({}, vim.fs.joinpath(_G.TEST_CWD, "file.txt"))
    local function create(cwd)
      return _G.run({ command = "create", path = "/memories/x.md", file_text = "x", cwd = cwd })
    end

    return {
      relative = create("sub"),
      missing = create(vim.fs.joinpath(_G.TEST_CWD, "nope")),
      file = create(vim.fs.joinpath(_G.TEST_CWD, "file.txt")),
      number = create(42),
      created = vim
        .iter({ "nope", "sub/memories/x.md", "memories/x.md" })
        :filter(function(p)
          return vim.uv.fs_stat(vim.fs.joinpath(_G.TEST_CWD, p)) ~= nil
        end)
        :totable(),
    }
  ]])

  h.eq("error", res.relative.status)
  h.expect_contains("cwd must be an absolute path: sub", res.relative.data)
  h.eq("error", res.missing.status)
  h.expect_contains("Directory does not exist", res.missing.data)
  h.eq("error", res.file.status)
  h.expect_contains("Not a directory", res.file.data)
  h.eq("error", res.number.status)
  h.expect_contains("cwd must be a string", res.number.data)
  h.eq({}, res.created)
end

T["cwd"]["a cwd outside the working directory is refused"] = function()
  local res = child.lua([[
    local function view(cwd)
      return _G.run({ command = "view", path = "/memories", cwd = cwd })
    end
    return {
      view(vim.fs.dirname(_G.TEST_CWD)),
      view(_G.OTHER_CWD),
      view(_G.SUB .. "/../.."),
    }
  ]])

  for _, output in ipairs(res) do
    h.eq("error", output.status)
    h.expect_contains("outside the chat's working directory", output.data)
  end
end

T["cwd"]["a cwd follows symlinks"] = function()
  local res = child.lua([[
    local other = vim.fs.joinpath(_G.OTHER_CWD, "memories")
    vim.uv.fs_symlink(_G.OTHER_CWD, vim.fs.joinpath(_G.TEST_CWD, "link"))
    vim.fn.mkdir(vim.fs.joinpath(_G.TEST_CWD, "sub2"), "p")
    vim.uv.fs_symlink(other, vim.fs.joinpath(_G.TEST_CWD, "sub2", "memories"))

    local link = _G.run({ command = "view", path = "/memories", cwd = vim.fs.joinpath(_G.TEST_CWD, "link") })
    local sub2 = _G.run({ command = "view", path = "/memories", cwd = vim.fs.joinpath(_G.TEST_CWD, "sub2") })

    -- The chat's own memories may still be a symlink, as long as no cwd is passed
    vim.fn.delete(_G.MEMORY_DIR_ABSOLUTE, "rf")
    vim.uv.fs_symlink(other, _G.MEMORY_DIR_ABSOLUTE)
    local own = _G.run({ command = "view", path = "/memories/other.md" })

    return { link = link, sub2 = sub2, own = own }
  ]])

  h.eq("error", res.link.status)
  h.expect_contains("outside the chat's working directory", res.link.data)
  h.eq("error", res.sub2.status)
  h.expect_contains("outside the chat's working directory", res.sub2.data)
  h.eq("in other\n", res.own.data)
end

T["cwd"]["a cwd expands ~"] = function()
  local output = child.lua([[
    vim.env.HOME = vim.fs.dirname(_G.TEST_CWD)
    local cwd = "~/" .. vim.fs.basename(_G.TEST_CWD) .. "/sub"
    return _G.run({ command = "view", path = "/memories/sub.md", cwd = cwd })
  ]])

  h.eq("in sub\n", output.data)
end

T["cwd"]["a cwd keeps traversal rejected"] = function()
  local output = child.lua([[
    return _G.run({ command = "view", path = "/memories/../sub.md", cwd = _G.SUB })
  ]])

  h.eq("error", output.status)
  h.expect_contains("Must reside within the /memories directory", output.data)
end

T["cwd"]["a cwd leaves the index alone"] = function()
  local prompt = child.lua([[
    _G.request()
    _G.call({ command = "create", path = "/memories/sub-new.md", file_text = "x", cwd = _G.SUB })
    return _G.memory_prompt()
  ]])

  h.expect_contains("/memories/first.md", prompt)
  h.eq(nil, prompt:find("sub-new.md", 1, true))
  h.eq(nil, prompt:find("sub.md", 1, true))
end

T["cwd"]["the approval prompt names the physical directory of a cwd"] = function()
  local res = child.lua([[
    local other = vim.fs.joinpath(_G.OTHER_CWD, "memories")
    vim.fn.mkdir(vim.fs.joinpath(_G.TEST_CWD, "sub2"), "p")
    vim.uv.fs_symlink(other, vim.fs.joinpath(_G.TEST_CWD, "sub2", "memories"))

    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local function prompt(args)
      return builtin.output.prompt({ args = args }, { tools = { chat = chat } })
    end

    return {
      sub = prompt({ command = "view", path = "/memories/sub.md", cwd = _G.SUB }),
      linked = prompt({ command = "delete", path = "/memories/x.md", cwd = vim.fs.joinpath(_G.TEST_CWD, "sub2") }),
      own = prompt({ command = "view", path = "/memories" }),
      sub_real = vim.fn.fnamemodify(vim.uv.fs_realpath(vim.fs.joinpath(_G.SUB, "memories")), ":~"),
      other_real = vim.fn.fnamemodify(vim.uv.fs_realpath(other), ":~"),
    }
  ]])

  h.eq("View /memories/sub.md in `" .. res.sub_real .. "`?", res.sub)
  h.eq("Delete /memories/x.md in `" .. res.other_real .. "`?", res.linked)
  h.eq("View /memories?", res.own)
end

T["cwd"]["an outside cwd asks, naming its physical directory"] = function()
  local res = child.lua([[
    _G.mode("ask")
    _G.answer("Accept")
    local outside = _G.call({ command = "view", path = "/memories/other.md", cwd = _G.OTHER_CWD })
    local inside = _G.call({ command = "view", path = "/memories/sub.md", cwd = _G.SUB })
    return {
      prompts = _G.prompts,
      outside = outside,
      inside = inside,
      real = vim.fn.fnamemodify(vim.uv.fs_realpath(vim.fs.joinpath(_G.OTHER_CWD, "memories")), ":~"),
    }
  ]])

  -- require_approval_before = false, yet the outside call asks; the inside one doesn't
  h.eq({ "View /memories/other.md in `" .. res.real .. "`?" }, res.prompts)
  h.expect_contains("in other", res.outside)
  h.expect_contains("in sub", res.inside)
end

T["cwd"]["Accept approves one outside call"] = function()
  local res = child.lua([[
    _G.mode("ask")
    _G.answer("Accept")
    local first = _G.call({ command = "view", path = "/memories/other.md", cwd = _G.OTHER_CWD })
    local second = _G.call({ command = "view", path = "/memories/other.md", cwd = _G.OTHER_CWD })
    return { prompts = #_G.prompts, first = first, second = second }
  ]])

  h.eq(2, res.prompts)
  h.expect_contains("in other", res.first)
  h.expect_contains("in other", res.second)
end

T["cwd"]["Always accept approves the whole outside directory"] = function()
  local res = child.lua([[
    _G.mode("ask")
    _G.answer("Always accept")
    local other = _G.OTHER_CWD
    _G.call({ command = "view", path = "/memories/other.md", cwd = other })
    _G.call({ command = "create", path = "/memories/new.md", file_text = "old", cwd = other })
    _G.call({ command = "str_replace", path = "/memories/new.md", old_str = "old", new_str = "new", cwd = other })
    local after_one_directory = #_G.prompts

    _G.THIRD_CWD = vim.fn.tempname()
    vim.fn.mkdir(vim.fs.joinpath(_G.THIRD_CWD, "memories"), "p")
    _G.call({ command = "view", path = "/memories", cwd = _G.THIRD_CWD })
    local after_another = #_G.prompts
    pcall(vim.fn.delete, _G.THIRD_CWD, "rf")

    local Approvals = require("codecompanion.interactions.chat.tools.approvals")
    return {
      after_one_directory = after_one_directory,
      after_another = after_another,
      written = vim.fn.readfile(vim.fs.joinpath(other, "memories", "new.md")),
      tool_approved = Approvals:is_approved(tools.bufnr, { tool_name = "memory" }),
    }
  ]])

  h.eq(1, res.after_one_directory)
  h.eq(2, res.after_another)
  h.eq({ "new" }, res.written)
  -- The directory was approved, not the tool
  h.eq(false, res.tool_approved)
end

T["cwd"]["auto mode asks the user about an outside cwd"] = function()
  local res = child.lua([[
    _G.mode("auto")
    _G.answer("Accept")
    local outside = _G.call({ command = "view", path = "/memories/other.md", cwd = _G.OTHER_CWD })
    local inside = _G.call({ command = "view", path = "/memories/sub.md", cwd = _G.SUB })
    return { prompts = #_G.prompts, outside = outside, inside = inside }
  ]])

  h.eq(1, res.prompts)
  h.expect_contains("in other", res.outside)
  h.expect_contains("in sub", res.inside)
end

T["cwd"]["yolo mode lets an outside cwd through"] = function()
  local res = child.lua([[
    _G.mode("yolo")
    _G.answer("Reject")
    local outside = _G.call({ command = "view", path = "/memories/other.md", cwd = _G.OTHER_CWD })
    return { prompts = #_G.prompts, outside = outside }
  ]])

  h.eq(0, res.prompts)
  h.expect_contains("in other", res.outside)
end

T["cwd"]["Reject keeps an outside call out"] = function()
  local res = child.lua([[
    _G.mode("ask")
    vim.ui.input = function(_, cb)
      cb("not that directory")
    end
    _G.answer("Reject")
    local output = _G.call({ command = "create", path = "/memories/rejected.md", file_text = "x", cwd = _G.OTHER_CWD })
    return {
      output = output,
      created = vim.uv.fs_stat(vim.fs.joinpath(_G.OTHER_CWD, "memories", "rejected.md")) ~= nil,
    }
  ]])

  h.expect_contains("not that directory", res.output)
  h.eq(false, res.created)
end

T["cwd"]["an outside cwd fails closed without the orchestrator's approval"] = function()
  local res = child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.memory")
    local args = { command = "view", path = "/memories/other.md", cwd = _G.OTHER_CWD }
    local real = vim.uv.fs_realpath(vim.fs.joinpath(_G.OTHER_CWD, "memories"))
    return {
      none = _G.run(args),
      other = builtin.cmds[1]({ chat = chat, tool = { granted_scope = "/elsewhere/memories" } }, args),
      granted = builtin.cmds[1]({ chat = chat, tool = { granted_scope = real } }, args),
    }
  ]])

  h.eq("error", res.none.status)
  h.expect_contains("which this caller did not obtain", res.none.data)
  h.eq("error", res.other.status)
  h.eq("in other\n", res.granted.data)
end

T["cwd"]["an approval check that throws asks, and approves nothing beyond the call"] = function()
  local res = child.lua([[
    require("codecompanion.interactions.chat.tools.builtin.memory").gates.forced_approval = function()
      error("boom")
    end
    _G.mode("ask")
    _G.answer("Always accept")
    local first = _G.call({ command = "view", path = "/memories/sub.md", cwd = _G.SUB })
    _G.call({ command = "view", path = "/memories/sub.md", cwd = _G.SUB })
    local prompts = vim.deepcopy(_G.prompts)

    -- With no scope recorded, an outside call still fails closed
    local outside = _G.call({ command = "view", path = "/memories/other.md", cwd = _G.OTHER_CWD })
    return { prompts = prompts, first = first, outside = outside }
  ]])

  h.eq(2, #res.prompts)
  h.expect_contains("approval check failed", res.prompts[1])
  h.expect_contains("boom", res.prompts[1])
  h.expect_contains("in sub", res.first)
  h.expect_contains("which this caller did not obtain", res.outside)
end
-- /FORK(memory-cwd)

return T
