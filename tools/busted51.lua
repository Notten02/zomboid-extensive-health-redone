-- Starts busted under the Lua 5.1 interpreter (Arch's `busted` CLI runs on Lua 5.4).
-- Needs the Lua 5.1 busted modules, e.g. `pacman -S lua51-busted`.
require("busted.runner")({ standalone = false })
