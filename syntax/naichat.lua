-- syntax/naichat.lua
-- Syntax highlighting for naichat filetype

vim.cmd([[
  " Message markers
  syntax match naichatUser "^>>> user"
  syntax match naichatAssistant "^<<< assistant"
  syntax match naichatSystem "^>>> system"

  " Special block markers
  syntax match naichatInclude "^>>> include"
  syntax match naichatSnapshot "^>>> snapshot\( \[.*\]\)\?"
  syntax match naichatWeb "^>>> web"

  " Timestamps and metadata
  syntax match naichatTimestamp "\[.\{10,19\}\]" contained containedin=naichatSnapshot

  " Content headers
  syntax match naichatFilePath "^==> .\+\..\+ <=="
  syntax match naichatWebSource "^==> Web: .\+ <=="

  " URLs in web blocks
  syntax match naichatUrl "https\?://[a-zA-Z0-9\-\.\/\?\%\&\=\+\_\#\:]\+"

  " Content regions
  syntax region naichatIncludeText start=/^>>> include\_s\+/ end=/^\(>>>\|<<<\)/ contains=naichatInclude,naichatFilePath
  syntax region naichatWebText start=/^>>> web\_s\+/ end=/^\(>>>\|<<<\)/ contains=naichatWeb,naichatUrl,naichatWebSource
  syntax region naichatSnapshotText start=/^>>> snapshot\_s\+/ end=/^\(>>>\|<<<\)/ contains=naichatSnapshot,naichatTimestamp,naichatFilePath

  " YAML header
  syntax region naichatYamlHeader start=/\%^---/ end=/^---/ contains=naichatYamlKey,naichatYamlValue
  syntax match naichatYamlKey /^\s*\zs\w\+\ze:/ contained
  syntax match naichatYamlValue /:\s*\zs.*/ contained

  " Code blocks - improved to work better with nested code and matching
  syntax region naichatCodeBlock start=/^```\(\w\+\)\?$/ end=/^```$/ contains=naichatCodeBlockLang keepend
  syntax match naichatCodeBlockLang /^```\zs\w\+/ contained

  " Basic markdown elements
  syntax match naichatHeading "^#\{1,6\}\s.\+$"
  syntax match naichatListItem "^\s*[-*+]\s.\+$"
  syntax match naichatNumberedItem "^\s*\d\+\.\s.\+$"
  syntax region naichatBold start=/\*\*/ end=/\*\*/
  syntax region naichatItalic start=/\*/ end=/\*/
  syntax region naichatItalic start=/_/ end=/_/

  " Color assignments
  highlight default link naichatUser Comment
  highlight default link naichatAssistant Identifier
  highlight default link naichatSystem Statement

  highlight default link naichatInclude Special
  highlight default link naichatSnapshot Special
  highlight default link naichatWeb Special

  highlight default link naichatTimestamp Number
  highlight default link naichatUrl Underlined
  highlight default link naichatFilePath Title
  highlight default link naichatWebSource Title

  highlight default link naichatYamlHeader PreProc
  highlight default link naichatYamlKey Type
  highlight default link naichatYamlValue String

  highlight default link naichatCodeBlock String
  highlight default link naichatCodeBlockLang Type

  highlight default link naichatHeading Title
  highlight default link naichatListItem Normal
  highlight default link naichatNumberedItem Normal
  highlight default link naichatBold Bold
  highlight default link naichatItalic Italic

  " Special block markers
  syntax match naichatScrape "^>>> scrape"
  syntax match naichatScraping "^>>> scraping"
  syntax match naichatScraped "^>>> scraped\(\s\+\[.*\]\)\?"
  syntax match naichatScrapeError "^>>> scrape-error"

  " Snapshot markers
  syntax match naichatSnapshot "^>>> snapshot"
  syntax match naichatSnapshotting "^>>> snapshotting"
  syntax match naichatSnapshotted "^>>> snapshotted\(\s\+\[.*\]\)\?"

  " Color assignments
  highlight default link naichatScrape Special
  highlight default link naichatScraping Special
  highlight default link naichatScraped Special
  highlight default link naichatScrapeError Error

  highlight default link naichatSnapshot Special
  highlight default link naichatSnapshotting Special
  highlight default link naichatSnapshotted Special
]])
