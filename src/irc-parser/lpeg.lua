local lpeg = require'lpeg'

local rawset = rawset
local gsub = string.gsub
local find = string.find

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
local OCTET = DIGIT * DIGIT^-2
local VALID_OCTET = P'1' * DIGIT * DIGIT
            + P'2' * (R'04'*DIGIT + P'5'*R'05')
            + DIGIT * DIGIT^-1
local IP4 = VALID_OCTET * P'.' * VALID_OCTET * P'.' * VALID_OCTET * P'.' * VALID_OCTET
local H16 = HEXDIGIT * HEXDIGIT^-3
local HG  = H16 * P':'
local LS32 = HG * H16 + IP4

local escapes = setmetatable({}, {
  __index = function(_,k)
    return k
  end,
})
escapes['\\'] = '\\'
escapes[':']  = ';'
escapes['s']  = ' '
escapes['r']  = '\r'
escapes['n']  = '\n'

local function create_unescape_tag_val(replacement)
  return function(_,_,val)
    if #val == 0 then
      return true, replacement
    end
    if not find(val,'\\',1,true) then
      return true,val
    end
    val = gsub(val,'\\(.?)',escapes)
    return true, val
  end
end

local function create_base_grammar(params)
  if not params then params = {} end
  local empty_replacement = false
  local missing_replacement = false

  if params.empty_tag_replacement ~= nil then
    empty_replacement = params.empty_tag_replacement
  end

  if params.missing_tag_replacement ~= nil then
    missing_replacement = params.missing_tag_replacement
  end

  if params.remove_empty_tags then
    empty_replacement = nil
  end

  if params.remove_missing_tags then
    missing_replacement = nil
  end

  local grammar = {
    'message',
    message =   (P'@' * Cg(V'tags','tags'))^-1
              * (P':' * Cg(Ct(V'source'),'source'))^-1
              * Cg(V'command','command')
              * (V'space' * Cg(Ct(V'params'),'params'))^0
              * (CRLF + LF + -P(1)),

    tags = Cf(Ct'' * (V'tag' * (P';' * V'tag')^0),rawset) * V'space',

    tag = Cg(C(V'tag_key') * ( (P'=' * V'tag_value') + V'tag_missing')),
    tag_key = P'+'^-1 * ( V'tag_vendor' * P'/' )^-1 * V'tag_name',
    tag_vendor = V'host',
    tag_name = (LETTER + DIGIT + DASH)^1,
    tag_value = Cmt(V'tag_raw_value', create_unescape_tag_val(empty_replacement)),
    tag_raw_value = R('\001\009','\011\12','\014\031','\033\058','\060\255')^0,
    tag_missing = Cc(missing_replacement),

    -- we create a distinct 'userhost' type,
    -- so that we can override it
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

    host = V'hostaddr' + (V'hostname' - (OCTET * '.' * OCTET * '.' * OCTET * '.' * OCTET)),
    hostname = V'label' * (P'.' * V'label')^0,
    hostaddr = V'ip4addr' + V'ip6addr',
    ip4addr = IP4,
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

  return grammar
end

local strict_grammar = {}
local twitch_grammar = {
  userhost       = (V'twitchusername' * P'.' * V'host') + V'host',
  nick           = V'twitchusername',
  user           = V'twitchusername',
  twitchusername = (LETTER + DIGIT) * (LETTER + DIGIT + P'_')^0,
}

local loose_grammar = {
  -- a lot of IRC servers let users "cloak" their IP/hostname
  -- and includes characters not allowed in DNS, like:
  -- :nick!~user@user/nick/etc
  -- so we override the userhost to just allow anything besides CR, LF, Space
  userhost = V'nonwhite'^1,

  -- let the loose grammar accept anything for a nick, besides !@
  nick =  R('\001\009','\011\012','\014\031','\034\063','\065\255')^1,

  -- tag vendor, don't check for actual hostnames and ip addresses
  tag_vendor = (R('\001\009','\011\012','\014\031','\033\046','\048\058','\062\255') + P('\060'))^1,

  -- tag name, allow anything besides =;' '
  tag_name = (R('\001\009','\011\012','\014\031','\033\046','\048\058','\062\255') + P('\060'))^1,
}

local Strict = {
  grammar = strict_grammar,
  parse = function(self,str,init)
    init = init or 1
    local msg, pos = self.parser:match(str,init)
    return msg, pos
  end,
}

local Twitch = {
  grammar = twitch_grammar,
  parse = Strict.parse,
}

local Loose = {
  grammar = loose_grammar,
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
  [2] = Strict__mt,
  [3] = Twitch__mt,
  ['loose'] = Loose__mt,
  [LOOSE] = Loose__mt,
  ['strict'] = Strict__mt,
  [STRICT] = Strict__mt,
  ['twitch'] = Twitch__mt,
  [TWITCH] = Twitch__mt,
}

local function new(typ,params)
  if not typ then
    typ = LOOSE
  end

  if type(typ) == 'string' then
    typ = typ:lower()
  end

  typ = typ_map[typ]
  if not typ then
    return nil,'invalid type specified'
  end

  local self = setmetatable({},typ)
  local grammar = create_base_grammar(params)
  for k,v in pairs(self.grammar) do
    grammar[k] = v
  end
  self.grammar = grammar
  self.parser = Ct(P(self.grammar)) * lpeg.Cp()
  return self
end

local module = setmetatable({
  new    = new,
  STRICT = STRICT,
  TWITCH = TWITCH,
  LOOSE  = LOOSE,
}, {
  __call = function(_,typ,params)
    return new(typ,params)
  end,
})

return module
