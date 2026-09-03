-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function(args)
    local bufnr = args.buf

    -- Define buffer-local command to toggle SnipRun auto-run
    vim.api.nvim_buf_create_user_command(bufnr, "SnipRunAuto", function()
      vim.b[bufnr].sniprun_autorun = not vim.b[bufnr].sniprun_autorun
      if vim.b[bufnr].sniprun_autorun then
        vim.notify("SnipRun Auto-Run activated", vim.log.levels.INFO)
      else
        vim.notify("SnipRun Auto-Run deactivated", vim.log.levels.INFO)
      end
    end, {})

    -- Keymaps
    vim.keymap.set("n", "<leader>cr", "<cmd>%SnipRun<cr>", { buffer = bufnr, desc = "Run python file via SnipRun" })
    vim.keymap.set("v", "<leader>cr", "<cmd>SnipRun<cr>", { buffer = bufnr, desc = "Run selected python snippet via SnipRun" })
    vim.keymap.set("n", "<leader>cc", "<cmd>SnipClose<cr>", { buffer = bufnr, desc = "Close SnipRun info" })
    vim.keymap.set("n", "<leader>cR", "<cmd>SnipReset<cr>", { buffer = bufnr, desc = "Reset SnipRun" })
    vim.keymap.set("n", "<leader>ct", "<cmd>SnipRunAuto<cr>", { buffer = bufnr, desc = "Toggle SnipRun Auto-Run" })

    -- Autocmd on InsertLeave to check and run if no syntax errors
    vim.api.nvim_create_autocmd("InsertLeave", {
      buffer = bufnr,
      callback = function()
        if vim.b[bufnr].sniprun_autorun then
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          local content = table.concat(lines, "\n")
          if content:gsub("%s+", "") == "" then
            return
          end
          vim.fn.system("python3 -c 'import sys, ast; ast.parse(sys.stdin.read())'", content)
          if vim.v.shell_error == 0 then
            vim.cmd("%SnipRun")
          end
        end
      end,
    })
  end,
})

