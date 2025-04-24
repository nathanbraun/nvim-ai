# 2.1.0 (2025-04-24)
Features
- Added ability to "sign"/verify chats. How it works:
  - If enabled (in config or by running `:NAISIgnedChat`, the message/response
    from the LLM is hashed and added to the chat.
  - Immediately (and again when you enter `:NAIVerify` this hash is compared to
    the buffer to check whether there have been any changes.
  - When buffer is edited at all, verification indicator dissapears. Type
    `:NAIVerify` to recheck the file.
  - When comparing, ignores other signatures and blank lines.

# 2.0.3 (2025-04-24)
Fixes
- Issue where Google models weren't getting full conversation history

# 2.0.2 (2025-04-18)
- use snacks as default file browser (if installed, then telescope or fzf)

# 2.0.1 (2025-04-18)
Fixes
- issue with folding

# 2.0.0 (2025-04-17)
Features
- add google as a provider
- model picker no longer provider based, :NAIModel lets you choose any model,
  not just current provider
- use snacks as default picker (if installed, then telescope or fzf)
- tweaked config 

# 1.0.0 (2025-04-17)
Features
- working version
- added changelog

