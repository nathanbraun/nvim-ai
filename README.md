# nvim-ai
LLM chats as text files inside Neovim.

## Features
- Chat with any LLM inside any text file.
- Persistant. Save conversations as text files. Pick them up later and continue
  chatting. View, edit and regenerate conversation history.
- Works with OpenRouter, OpenAI or locally with Ollama.
- Add local files, text from websites or YouTube video transcripts (requires
  Dumpling API key).
- Configurable provider, model, temperature and system prompt.
- No language dependencies, written in Lua.
- Asyncronous.
- Auto topic/title detection.

## Prerequisites
You'll need an OpenRouter (recommended) or OpenAI API key. *Or* an instance of
Ollama running on your computer.

You can get an OpenRouter key here:

[https://openrouter.ai/](https://openrouter.ai/)

## Installation

Using lazy.nvim:
```lua
{
    'nathanbraun/nvim-ai',
    dependencies = {
        'nvim-telescope/telescope.nvim', -- Optional, for model selection
    },
    config = function()
        require('nai').setup({
            -- Your configuration here (see Configuration section)
        })
    end
}
```

Using packer.nvim:
```lua
use {
    'nathanbraun/nvim-ai',
    requires = {
        'nvim-telescope/telescope.nvim', -- Optional, for model selection
    },
    config = function()
        require('nai').setup({
            -- Your configuration here (see Configuration section)
        })
    end
}
```

After installing the plugin and getting your API key, open up Neovim and run:

```
:NAISetKey openrouter
```

It'll ask you for your API key. Paste it in. By default this will be saved at:

`/Users/nathanbraun/.config/nvim-ai/credentials.json`

## Quickstart
### Your first conversation
By default, nvim-ai is enabled on markdown (`*.md`) and vimwiki (`*.wiki`)
files. Most commands are prefixed with `<leader>a`.

So open up an empty markdown file and press `<leader>au`. This will insert a
*user* prompt (alternatively you can just type out the `>>> user` -- it works
the same).

Type your message for the LLM below it and press `<leader>c`.

```
>>> user
Briefly tell me about Neovim.
```

If all is working well you should see a spinner and a note about generating the
reponse/model info. When it's ready it'll insert the response (under an `>>>
assistant` block) followed by another user prompt for you to follow up.

![First Conversation](images/first-convo.jpg)

Try following up under the next `>>> user` prompt ("What year was it
released?") and press `<leader>c` again to continue the conversation.

#### Saving, Closing, Re-Opening
This is a normal markdown file, and can be saved, closed etc. When you re-open
it you can continue chatting under additional `>>> user` blocks.

### Creating a new conversation
It can be cumbersome to deal with file and conversation management, and
`nvim-ai` can take care of that for you.

In Neovim, press `<leader>ai`.

By default (it's configurable) this creates a markdown file
`~/nvim-ai-notes/XXXX.md` where `XXXX` is a random string. The file starts off
with a YAML header and ready user prompt:

```markdown
---
title: Untitled
date: YYYY-MM-DD
tags: [ai]
---

>>> user
```

Try typing in a message ("Briefly tell me about YAML").

If your note is "Untitled" the first time the LLM responds it'll automatically
fill it in for you (for me for this query Claude picked "Introduction to YAML
Basics"). This is all text -- and it won't change existing titles -- so feel
free to modify.

The is exactly the same as before -- it's still a normal markdown file and you
can save, close, pick up where you left off etc.

The benefits to chatting in dedicated files with `<leader>ai`:

1. Not having to think about where to store your markdown files and what to title or name them.
2. Putting them all in one spot makes it easier to view previous conversations.

### View previous conversations

To view past conversations run `:NAIBrowse`, which is mapped to `<leader>ao`
(for *open*) by default.

This will open up a Telescope picker with the extracted *titles* (from the
YAML) of all your conversations in the `~/nvim-ai-notes` directory.

## Referencing local text files and web content

### >>> reference 
You can include other text files in the chat using the `reference` command.
Note this can be very helpful for coding, e.g.:

```markdown
>>> user
I'm working on a small data analyis project in Python here:

>>> reference
/Users/nathanbraun/code/github.com/nathanbraun/techtools-fruit-example/fruit-code.py

Do you have any ideas for improving this?

```

### >>> snapshot 
Reference will add the current file to the chat every time

## Configuration
nvim-ai can be configured with the setup function (defaults below):

```lua
require('nai').setup({
    credentials = {
        file_path = "~/.config/nvim-ai/credentials.json",
    },
    active_filetypes = {
      patterns = { "*.md", "*.markdown", "*.wiki" },
      autodetect = true,
      enable_overlay = true,
      enable_folding = true,
    },
    default_system_prompt = "You are a general assistant.",
    active_provider = "openrouter",
    mappings = {
        enabled = true,
        intercept_ctrl_c = true,
        chat = {
            continue = "<Leader>c",
            new = "<Leader>ai",
            cancel = "<Leader>ax",
        },
        expand = {
            blocks = "<Leader>ae",
        },
        insert = {
            user_message = "<Leader>au",
            scrape = "<Leader>ad",
            web = "<Leader>aw",
            youtube = "<Leader>ay",
            reference = "<Leader>ar",
            snapshot = "<Leader>as",
            crawl = "<Leader>ac",
        },
        settings = {
            select_model = "<Leader>am",
            toggle_provider = "<Leader>ap",
        }
    },
    providers = {
        openai = {
            name = "OpenAI",
            description = "OpenAI API (GPT models)",
            model = "gpt-4o",
            temperature = 0.7,
            max_tokens = 10000,
            endpoint = "https://api.openai.com/v1/chat/completions",
        },
        openrouter = {
            name = "OpenRouter",
            description = "OpenRouter API (Multiple providers)",
            model = "anthropic/claude-3.7-sonnet",
            temperature = 0.7,
            max_tokens = 10000,
            endpoint = "https://openrouter.ai/api/v1/chat/completions",
            models = {
                "anthropic/claude-3.7-sonnet",
                "google/gemini-2.0-flash-001",
                "openai/gpt-4o",
                "openai/gpt-4o-mini",
                "perplexity/r1-1776",
            },
        },
        ollama = {
          name = "Ollama",
          description = "Local models via Ollama",
          model = "llama3.2:latest",
          temperature = 0.7,
          max_tokens = 4000,
          endpoint = "http://localhost:11434/api/chat",
          models = {
            "llama3.2:latest",
          },
        },
    },
    chat_files = {
        directory = vim.fn.expand("~/nvim-ai-notes"),
        format = "{id}.md",
        auto_save = false,
        id_length = 4,
        use_timestamp = false,
        auto_title = true,
        header = {
            enabled = true,
            template = [[---
title: {title}
date: {date}
tags: [ai]
---]],
        },
    },
    expand_placeholders = false,
    highlights = {
        user = { fg = "#88AAFF", bold = true },
        assistant = { fg = "#AAFFAA", bold = true },
        system = { fg = "#FFAA88", bold = true },
        special_block = { fg = "#AAAAFF", bold = true },
        error_block = { fg = "#FF8888", bold = true },
        content_start = { fg = "#AAAAAA", italic = true },
        placeholder = { fg = "#FFCC66", bold = true },
    },
    aliases = {
        translate = {
            system = "You are an interpreter. Translate any further text/user messages you receive to Spanish.",
            user_prefix = "",
            config = {
                model = "openai/gpt-4o-mini",
                temperature = 0.1,
            }
        },
        refactor = {
            system = "You are a coding expert. Refactor the provided code to improve readability, efficiency, and adherence to best practices. Explain your key improvements.",
            user_prefix = "Refactor the following code:",
        },
    },
    format_response = {
        enabled = true,
        exclude_code_blocks = true,
        wrap_width = 80
    },
    debug = {
        enabled = false,
        auto_title = false,
    },
})
```
