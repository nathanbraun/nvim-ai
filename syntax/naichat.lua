-- syntax/naichat.lua
-- Syntax highlighting for naichat filetype

-- Define syntax groups
vim.cmd([[
  syntax match naichatUser ">>> user"
  syntax match naichatAssistant "<<< assistant"
  syntax match naichatSystem ">>> system"
  syntax match naichatInclude ">>> include"
  highlight default link naichatInclude Special

  " Add these new syntax rules:
  " Highlight file paths in include blocks
  syntax match naichatFilePath "^==> .\+\..\+ <=="
  highlight default link naichatFilePath Title

  " Highlight the empty user prompt after include
  syntax region naichatIncludeText start=/^>>> include\_s\+/ end=/^\(>>>\|<<<\)/ contains=naichatInclude,naichatFilePath
  highlight default link naichatIncludeText Normal

  " YAML header
  syntax region naichatYamlHeader start=/\%^---/ end=/^---/ contains=naichatYamlKey,naichatYamlValue
  syntax match naichatYamlKey /^\s*\zs\w\+\ze:/ contained
  syntax match naichatYamlValue /:\s*\zs.*/ contained

  " Code blocks
  syntax region naichatCodeBlock start=/```\w*/ end=/```/ contains=naichatCodeBlockLang
  syntax match naichatCodeBlockLang /```\zs\w*/ contained

  highlight default link naichatUser Comment
  highlight default link naichatAssistant Identifier
  highlight default link naichatSystem Statement
  highlight default link naichatYamlHeader PreProc
  highlight default link naichatYamlKey Type
  highlight default link naichatYamlValue String
  highlight default link naichatCodeBlock String
  highlight default link naichatCodeBlockLang Type
]])
