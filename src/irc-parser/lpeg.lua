local lpeg = require'lpeg'

local rawset = rawset
local gsub = string.gsub
local find = string.find
local char = string.char

local V = lpeg.V
local P = lpeg.P
local R = lpeg.R
local C = lpeg.C
local S = lpeg.S
local Cg = lpeg.Cg
local Ct = lpeg.Ct
local Cf = lpeg.Cf
local Cc = lpeg.Cc
local Cmt = lpeg.Cmt

local STRICT = {}
local TWITCH   = {}
local LOOSE    = {}

local UPPER  = R('AZ')
local LOWER  = R('az')
local DIGIT  = R('09')
local LETTER = UPPER + LOWER
local DASH   = P'-'
local SPACE  = P' '
local CRLF   = P'\r\n'
local LF     = P'\n'
local HEXDIGIT = DIGIT + R('AF') + R('af')
local SPECIAL = S'[]\\`_^{|}'
local OCTET = P'1' * DIGIT * DIGIT
            + P'2' * (R'04'*DIGIT + P'5'*R'05')
            + DIGIT * DIGIT^-1
local IP4 = OCTET * P'.' * OCTET * P'.' * OCTET * P'.' * OCTET
local H16 = HEXDIGIT * HEXDIGIT^-3
local HG  = H16 * P':'
local LS32 = HG * H16 + IP4

local escapes = {}
for e=1,255 do
  escapes['\\' .. char(e)] = char(e)
end
escapes['\\\\'] = '\\'
escapes['\\:']  = ';'
escapes['\\s']  = ' '
escapes['\\r']  = '\r'
escapes['\\n']  = '\n'
escapes['\\']  = ''

local function unescape_tag_val(_,_,val)
  if #val == 0 then
    return true,false
  end
  if not find(val,'\\',1,true) then
    return true,val
  end
  val = gsub(val,'\\.?',escapes)
  return true, val
end

local strict_grammar = {
  'message',
  message =   (P'@' * Cg(V'tags','tags'))^-1
            * (P':' * Cg(Ct(V'source'),'source'))^-1
            * Cg(V'command','command')
            * (V'space' * Cg(Ct(V'params'),'params'))^0
            * (CRLF + LF + -P(1)),

  tags = Cf(Ct'' * (V'tag' * (P';' * V'tag')^0),rawset) * V'space',


  tag = Cg(C(V'tag_key') * ( (P'=' * V'tag_value') + Cc(false))),
  tag_key = P'+'^-1 * ( V'vendor' * P'/' )^-1 * (LETTER + DIGIT + DASH)^1,
  tag_value = Cmt(R('\001\009','\011\12','\014\031','\033\058','\060\255')^0 , unescape_tag_val),

  -- we create a distinct 'userhost' type,
  -- so that we can override it in the twitch
  -- grammar
  source = (Cg(V'host','host') * V'space') +
           (
             (Cg(V'nick','nick') *
             (P'!' * Cg(V'user','user'))^-1 *
             (P'@' * Cg(V'userhost','host'))^-1)
           * V'space'),

  userhost = V'host',

  command = (LETTER^1) + (DIGIT * DIGIT * DIGIT),

  params = (C(V'middle') * (V'space' * V'params')^0) + (':' * C(V'trailing')),
  middle = V'nospcrlfcl' * (P':' + V'nospcrlfcl')^0,
  trailing = (P':' + P' ' + V'nospcrlfcl')^0,

  vendor = V'host',
  host = V'hostaddr' + V'hostname',
  hostname = V'label' * (P'.' * V'label')^0,
  hostaddr = V'ip4addr' + V'ip6addr',
  ip4addr = IP4,
  -- we'll just take any combo of hex + colons
  ip6addr =        HG * HG * HG * HG * HG * HG * LS32
              + P'::' * HG * HG * HG * HG * HG * LS32
    + H16^-1  * P'::' * HG * HG * HG * HG * LS32
    + (HG * HG^-1 + P':') * P':' * HG * HG * HG * LS32
    + (HG * HG^-2 + P':') * P':' * HG * HG * LS32
    + (HG * HG^-3 + P':') * P':' * HG * LS32
    + (HG * HG^-4 + P':') * P':' * LS32
    + (HG * HG^-5 + P':') * P':' * H16
    + (HG * HG^-6 + P':') * P':',
  label = (LETTER + DIGIT) * (LETTER + DIGIT + DASH)^0 * (LETTER + DIGIT)^0,
  nick = (LETTER + SPECIAL) * (LETTER + DIGIT + SPECIAL + P'-')^0,
  user = R('\001\009','\011\012','\014\031','\033\063','\065\255')^1,

  space = SPACE^1,

  nonwhite   = R('\001\009','\011\012','\014\031','\033\255'),
  nospcrlfcl = R('\001\009','\011\012','\014\031','\033\057','\059\255'),
}

local twitch_grammar = {}
local loose_grammar = {}
for k,v in pairs(strict_grammar) do
  twitch_grammar[k] = v
  loose_grammar[k] = v
end

-- since twitch puts the username in the first part
-- of the host, allow the first part to be a twitch
-- username
twitch_grammar.userhost       = (V'twitchusername' * P'.' * V'host') + V'host'
twitch_grammar.nick           = V'twitchusername'
twitch_grammar.user           = V'twitchusername'
twitch_grammar.twitchusername = (LETTER + DIGIT) * (LETTER + DIGIT + P'_')^0

-- a lot of IRC servers let users "cloak" their IP/hostname
-- and includes characters not allowed in DNS, like:
-- :nick!~user@user/nick/etc
-- so we override the userhost to just allow anything besides CR, LF, Space
loose_grammar.userhost = V'nonwhite'^1

-- let the loose grammar accept invalid-ish IRC nicks
loose_grammar.nick = (LETTER + DIGIT + SPECIAL + P'-')^1

local strict_parser = Ct(P(strict_grammar)) * lpeg.Cp()
--local strict_parser = Ct(P(require('pegdebug').trace(strict_grammar))) * lpeg.Cp()
local twitch_parser = Ct(P(twitch_grammar)) * lpeg.Cp()
local loose_parser = Ct(P(loose_grammar)) * lpeg.Cp()

local Strict = {
  parser = strict_parser,
  parse = function(self,str,init)
    init = init or 1
    return self.parser:match(str,init)
  end,
}

local Twitch = {
  parser = twitch_parser,
  parse = Strict.parse,
}

local Loose = {
  parser = loose_parser,
  parse = Strict.parse,
}

local Strict__mt = {
  __index = Strict,
  __name  = 'irc-parser.strict',
  __call  = Strict.parse,
}

local Twitch__mt = {
  __index = Twitch,
  __name  = 'irc-parser.twitch',
  __call  = Twitch.parse,
}

local Loose__mt = {
  __index = Loose,
  __name  = 'irc-parser.loose',
  __call  = Loose.parse,
}

local typ_map = {
  [1] = Loose__mt,
  [2] = Twitch__mt,
  [3] = Strict__mt,
  ['loose'] = Loose__mt,
  [LOOSE] = Loose__mt,
  ['strict'] = Strict__mt,
  [STRICT] = Strict__mt,
  ['twitch'] = Twitch__mt,
  [TWITCH] = Twitch__mt,
}

local function new(typ)
  if not typ then
    typ = LOOSE
  end

  typ = typ_map[typ]
  if not typ then
    return nil,'invalid type specified'
  end

  return setmetatable({},typ)
end

local module = setmetatable({
  new    = new,
  STRICT = STRICT,
  TWITCH = TWITCH,
  LOOSE  = LOOSE,
}, {
  __call = function(_,typ)
    return new(typ)
  end,
})

return module
