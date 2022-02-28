local ok, mod

ok, mod = pcall(require,'irc-parser.lpeg')
if not ok then
  mod = require'irc-parser.fallback'
end

mod._VERSION = '1.2.0'

return mod
