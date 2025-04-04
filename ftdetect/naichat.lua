vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  pattern = "*.naichat",
  callback = function()
    -- Set filetype to naichat
    vim.bo.filetype = "naichat"

    -- Ensure concealing is enabled
    vim.wo.conceallevel = 2
    vim.wo.concealcursor = "nc"
  end,
})
