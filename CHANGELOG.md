# 2.3.2 (2025-05-15)
Fixes
- don't wrap snapshotted markdown
- removed ignore block for now since it wasn't working right

# 2.3.1 (2025-05-09)
Fixes
- fix no such mapping error

# 2.3.0 (2025-05-06)
Features
- Added new `ignore` block. Any prompt/block within it will get treated as full
  text.

Fixes
- `tree` prompt works better (allows for multiple commands or directories).

# 2.2.0 (2025-04-30)
Features
- add new tree block that will expand full, tree like directory structure given
  some path

# 2.1.1 (2025-04-25)
Features
- Added persistent, "pepper" key to hashing algorithms to prevent users from
  simply hashing the text they want + updating the signature.
- Introduced versioned signatures in order to potentially use different hash
  algorithms in the future.

# 2.1.0 (2025-04-25)
Features
- Added ability to "sign"/verify chats. How it works:
  - If enabled (in config or by running `:NAISIgnedChat`, the message/response
    from the LLM is hashed and added to the chat.
  - Immediately (and again when you enter `:NAIVerify` this hash is compared to
    the buffer to check whether there have been any changes.
  - When buffer is edited at all, verification indicator disappears. Type
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

