-- entrypoint
if vim.g.loaded_ntop then
  return
end
vim.g.loaded_ntop = true

require("ntop").setup()
