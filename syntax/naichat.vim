" syntax/naichat.vim
" Syntax highlighting for naichat filetype that properly integrates with VimWiki

" Quit if syntax file is already loaded
if v:version < 600
  syntax clear
elseif exists('b:current_syntax')
  finish
endif

" Set up VimWiki variables if they don't exist
if !exists('g:vimwiki_global_vars')
  let g:vimwiki_global_vars = {}
endif

if !exists('g:vimwiki_wikilocal_vars')
  let g:vimwiki_wikilocal_vars = []
endif

if !exists('g:vimwiki_syntaxlocal_vars')
  let g:vimwiki_syntaxlocal_vars = {}
endif

" Set up markdown syntax as the default for our integration
if !exists('g:vimwiki_syntaxlocal_vars["markdown"]')
  let g:vimwiki_syntaxlocal_vars["markdown"] = {}
  let g:vimwiki_syntaxlocal_vars["markdown"]['nested'] = ''
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface'] = {}
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface']['bold'] = [['\*\*', '\*\*']]
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface']['italic'] = [['\*', '\*']]
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface']['underline'] = []
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface']['del'] = []
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface']['sup'] = []
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface']['sub'] = []
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface']['code'] = []
  let g:vimwiki_syntaxlocal_vars["markdown"]['typeface']['bold_italic'] = []
endif

" Load VimWiki's syntax highlighter functions
runtime! autoload/vimwiki/u.vim

" Load VimWiki's highlighting for typefaces
let b:vimwiki_syntax_conceal = exists('+conceallevel') ? ' conceal' : ''
let b:vimwiki_syntax_concealends = has('conceal') ? ' concealends' : ''

" Get the typeface definitions and create highlighting
let s:typeface_dic = g:vimwiki_syntaxlocal_vars["markdown"]['typeface']

" Call VimWiki's function to set up typeface highlighting
call vimwiki#u#hi_typeface(s:typeface_dic)

" Define our custom chat-specific elements
syntax match naichatUser "^>>> user" 
syntax match naichatAssistant "^<<< assistant"
syntax match naichatSystem "^>>> system"

" Special block markers
syntax match naichatSpecialBlock "^>>> \(include\|web\|scrape\|scraping\|scraped\|snapshot\|snapshotting\|snapshotted\|youtube\|transcribing\|transcript\)"
syntax match naichatErrorBlock "^>>> \(scrape-error\|youtube-error\)"

" Content markers
syntax match naichatContentStart "^<<< content"

" Define our custom color definitions
highlight default naichatUser ctermfg=blue guifg=#5EAFFF
highlight default naichatAssistant ctermfg=green guifg=#5FD75F 
highlight default naichatSystem ctermfg=magenta guifg=#AF87FF

highlight default naichatSpecialBlock ctermfg=cyan guifg=#00AFFF
highlight default naichatErrorBlock ctermfg=red guifg=#FF5F5F  
highlight default naichatContentStart ctermfg=yellow guifg=#FFFF5F

" Make sure we have proper links to VimWiki highlighting
hi def link VimwikiBold Statement
hi def link VimwikiItalic Type

" Add header syntax (Markdown style)
for s:i in range(1,6)
  execute 'syntax match naichatHeader'.s:i.' /^#\{'.s:i.'}\s\+.*$/'
endfor

" Link header highlighting to VimWiki's header groups if available
" or define our own if not
if exists('*vimwiki#u#hi_typeface')
  " If VimWiki is available, link to its header groups
  for s:i in range(1,6)
    execute 'hi def link naichatHeader'.s:i.' VimwikiHeader'.s:i
  endfor
else
  " Define our own header highlighting if VimWiki is not available
  for s:i in range(1,6)
    " Different colors for different header levels
    " You can adjust these colors to your preference
    let s:fg_colors = ['#FF5F87', '#5FAFFF', '#AFFF5F', '#FF5F5F', '#5FAFD7', '#8787FF']
    execute 'hi naichatHeader'.s:i.' term=bold cterm=bold gui=bold ctermfg='.s:i.' guifg='.s:fg_colors[s:i-1]
  endfor
endif

" Code blocks with language-specific highlighting
" Match the starting and ending fences with the language identifier
syntax region naichatCodeBlockDelimiter start=/^```\s*/ end=/$/
syntax region naichatCodeBlockDelimiter start=/^\s*```$/ end=/^$/he=e-1 

" Define a list of supported languages
let s:supported_languages = [
    \ 'python', 'py', 'python3',
    \ 'javascript', 'js',
    \ 'typescript', 'ts',
    \ 'html', 'css',
    \ 'json', 'yaml', 'yml',
    \ 'bash', 'sh',
    \ 'sql',
    \ 'lua',
    \ 'vim', 'vimscript',
    \ 'c', 'cpp', 'rust',
    \ 'go',
    \ 'ruby', 'rb',
    \ 'java',
    \ 'php',
    \ 'markdown', 'md',
    \ 'text'
    \ ]

" Create syntax regions for each supported language
for s:language in s:supported_languages
    " Define the region from the opening fence with language to the closing fence
    execute 'syntax region naichatCodeBlock'.toupper(s:language)
        \ 'start=/^```\s*'.s:language.'\s*$/rs=e+1'
        \ 'end=/^```$/re=s-1'
        \ 'contains=@'.toupper(s:language).'Group'
        \ 'keepend'
        
    " Include the appropriate syntax file if it exists
    if s:language ==# 'python' || s:language ==# 'py' || s:language ==# 'python3'
        syntax include @PYTHONGroup syntax/python.vim
    elseif s:language ==# 'javascript' || s:language ==# 'js'
        syntax include @JAVASCRIPTGroup syntax/javascript.vim
    elseif s:language ==# 'typescript' || s:language ==# 'ts'
        syntax include @TYPESCRIPTGroup syntax/typescript.vim
    elseif s:language ==# 'html'
        syntax include @HTMLGroup syntax/html.vim
    elseif s:language ==# 'css'
        syntax include @CSSGroup syntax/css.vim
    elseif s:language ==# 'json'
        syntax include @JSONGroup syntax/json.vim
    elseif s:language ==# 'yaml' || s:language ==# 'yml'
        syntax include @YAMLGroup syntax/yaml.vim
    elseif s:language ==# 'bash' || s:language ==# 'sh'
        syntax include @BASHGroup syntax/sh.vim
    elseif s:language ==# 'sql'
        syntax include @SQLGroup syntax/sql.vim
    elseif s:language ==# 'lua'
        syntax include @LUAGroup syntax/lua.vim
    elseif s:language ==# 'vim' || s:language ==# 'vimscript'
        syntax include @VIMGroup syntax/vim.vim
    elseif s:language ==# 'c'
        syntax include @CGroup syntax/c.vim
    elseif s:language ==# 'cpp'
        syntax include @CPPGroup syntax/cpp.vim
    elseif s:language ==# 'rust'
        syntax include @RUSTGroup syntax/rust.vim
    elseif s:language ==# 'go'
        syntax include @GOGroup syntax/go.vim
    elseif s:language ==# 'ruby' || s:language ==# 'rb'
        syntax include @RUBYGroup syntax/ruby.vim
    elseif s:language ==# 'java'
        syntax include @JAVAGroup syntax/java.vim
    elseif s:language ==# 'php'
        syntax include @PHPGroup syntax/php.vim
    elseif s:language ==# 'markdown' || s:language ==# 'md'
        syntax include @MARKDOWNGroup syntax/markdown.vim
    elseif s:language ==# 'text'
        " Plain text doesn't need special highlighting
    endif
endfor

" Handle code blocks with no language specified
syntax region naichatCodeBlockNoLang
    \ start=/^```\s*$/rs=e+1
    \ end=/^```$/re=s-1
    \ keepend

" Highlight definitions for code blocks and delimiters
highlight default link naichatCodeBlockDelimiter Comment
highlight default link naichatCodeBlockNoLang Normal



" Set the conceallevel and cursor
setlocal conceallevel=2
setlocal concealcursor=nc

" Register the filetype
let b:current_syntax="naichat"

