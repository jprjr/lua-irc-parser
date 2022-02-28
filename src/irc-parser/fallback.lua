local byte = string.byte
local sub = string.sub

local char = string.char
local find = string.find
local gsub = string.gsub

local STRICT = {}
local TWITCH   = {}
local LOOSE    = {}

local Strict = {}
local Twitch = {}
local Loose = {}

Strict.escapes = setmetatable({}, {
  __index = function(_,k)
    return k
  end,
})
Strict.escapes['\\'] = '\\'
Strict.escapes[':']  = ';'
Strict.escapes['s']  = ' '
Strict.escapes['r']  = '\r'
Strict.escapes['n']  = '\n'

function Strict:unescape_tag_val(val)
  if not find(val,'\\',1,true) then
    return val
  end
  val = gsub(val,'\\(.?)',self.escapes)
  return val
end

function Strict.is_digit(_,t)
  return t >= 48 and t <= 57
end

function Strict.is_upper(_,t)
  return t >= 65 and t <= 90
end

function Strict.is_lower(_,t)
  return t >= 97 and t <= 122
end

function Strict:is_hex(t)
  return self:is_digit(t)
    or (t >= 65 and t <= 70)
    or (t >= 97 and t <= 102)
end

function Strict.is_nonwhite(_,t)
  return
       (t >= 1 and t <= 9)
    or (t >= 11 and t <= 12)
    or (t >= 14 and t <= 31)
    or (t >= 33 and t <= 255)
end


function Strict:is_letter(t)
  return self:is_upper(t) or self:is_lower(t)
end

function Strict.is_crlf(_,t)
  return t == 10 or t == 13
end

function Strict.is_spccrlf(_,t)
  return t == 32 or t == 10 or t == 13
end

function Strict.is_middlechar(_,t)
  return
       (t >= 1 and t <= 9)
    or (t >= 11 and t <= 12)
    or (t >= 14 and t <= 31)
    or (t >= 33 and t <= 57)
    or (t >= 59 and t <= 255)
end

function Strict:is_nickchar(t,pos)
  if self:is_letter(t) or self:is_special(t) then
    return true
  elseif self:is_digit(t) or t == 45 then
    if pos == 1 then
      return false
    end
    return true
  end
  return false
end

function Strict.is_userchar(_,t)
  return
       (t >= 1 and t <= 9)
    or (t >= 11 and t <= 12)
    or (t >= 14 and t <= 31)
    or (t >= 33 and t <= 63)
    or (t >= 65 and t <= 255)
end

local function gen_isspecial(str)
  local values = {}
  for i=1,#str do
    values[#values + 1] = byte(str,i)
  end
  return function(_,t)
    for i=1,#values do
      if t == values[i] then return true end
    end
    return false
  end
end

Strict.is_special = gen_isspecial('[]\\`_^{|}')

function Strict:looks_ip4(str,init,max)
  local i = init
  local t
  local octets = 0
  local octet = 0
  local dflag = false
  local valid = true -- unset if we get an octet outside of 0-255

  while i<= max do
    t = byte(str,i)
    if t == 46 then
      if i == init then return false, false end
      if dflag then return false, false end
      if octet > 255 then valid = false end
      octet = 0
      octets = octets + 1
      dflag = true
    elseif not self:is_digit(t) then
      return false, false
    else
      octet = octet * 10
      octet = octet + (t - 48)
      dflag = false
    end
    i = i + 1
  end

  if dflag then return false, false end
  octet = octet * 10
  octet = octet + (t - 48)
  if octet > 255 then valid = false end
  octets = octets + 1

  return octets == 4, valid
end

function Strict:parse_trailing(str,init,max)
  local i = init
  local t

  while i <= max do
    t = byte(str,i)
    if self:is_middlechar(t) or t == 58 or t == 32 then
      i = i + 1
    else
      return init, i-1
    end
  end

  return init, max

end

function Strict:parse_middle(str,init,max)
  local i = init
  local t

  while i <= max do
    t = byte(str,i)
    if i == init then
      if not self:is_middlechar(t) then
        return nil
      end
    elseif self:is_spccrlf(t) then
      return init, i-1
    elseif not (t== 58 or self:is_middlechar(t)) then
      return nil
    end
    i = i + 1
  end

  return init, max
end

function Strict:parse_params(str,init,max)
  local t
  local i = init
  local params = {}
  local s,e

  while i <= max do
    t = byte(str,i)
    if t == 58 then
      s,e = self:parse_trailing(str,i+1,max)
      if not s then
        return nil
      end
      params[#params + 1] = { s, e }
      return params, e + 1
    elseif self:is_middlechar(t) then
      s,e = self:parse_middle(str,i,max)
      if not s then
        return nil
      end
      params[#params + 1] = { s, e }
      i = e + 1
      if i > max then
        return params, i
      end

      if self:is_crlf(byte(str,i)) then
        return params, i
      end

      if byte(str,i) ~= 32 then
        return nil
      end

      while i <= max and byte(str,i) == 32 do
        i = i + 1
      end

      if i > max then
        return nil
      end
      if self:is_crlf(byte(str,i)) then
        return nil
      end
    end
  end
end

function Strict:parse_command_string(str,init,max)
  local t
  local i = init + 1 -- parse_command already verified the first character

  while i <= max do
    t = byte(str,i)
    if self:is_spccrlf(t) then
      return init, i-1
    elseif self:is_digit(t) then
      return nil
    end
    i = i + 1
  end

  return init,max
end

function Strict:parse_command_numeric(str,init,max)
  local t
  local i = init + 1 -- parse_command already verified the first character
  local tot = 1

  while i <= max and tot <= 3 do
    t = byte(str,i)
    if self:is_spccrlf(t) then
      return init, i-1
    elseif not self:is_digit(t) then
      return nil
    end
    tot = tot + 1
    i = i + 1
  end

  if tot == 3 then
    return init,max
  end

  return nil
end

function Strict:parse_command(str,init,max)
  local t

  if init > max then return nil end
  t = byte(str,init)
  if self:is_spccrlf(t) then return nil end
  if self:is_letter(t) then
    return self:parse_command_string(str,init,max)
  elseif self:is_digit(t) then
    return self:parse_command_numeric(str,init,max)
  end
  return nil
end

function Strict:parse_ip4addr(str,init,max)
  local i = init
  local t
  local looks, valid

  while i <= max do
    t = byte(str,i)
    if self:is_digit(t) or t == 46 then
      i = i + 1
    else -- we may be seeing an ip4 address as part of a tag
      if i == init then return nil end
      looks, valid = self:looks_ip4(str,init,i-1)
      if not (looks and valid) then return nil end
      return init, i - 1
    end
  end

  looks, valid = self:looks_ip4(str,init,max)
  if not (looks and valid) then return nil end

  return init, max
end

function Strict:parse_ip6addr(str,init,max)
  local i = init
  local t

  while i <= max do
    t = byte(str,i)
    if self:is_hex(t) or t == 46 or t == 58 then
      i = i + 1
    else -- we may be seeing an ip6 address as part of a tag
      if i == init then return nil end
      if self:looks_ip4(str,init,i-1) then return nil end
      return init, i - 1
    end
  end

  if self:looks_ip4(str,init,max) then return nil end
  return init, max
end

function Strict:parse_hostlabel(str,init,max)
  local i = init
  local t

  while i <= max do
    t = byte(str,i)
    if self:is_digit(t) or self:is_letter(t) then
      i = i + 1
    elseif t == 45 then
      if i == init then
        return nil
      end
      i = i + 1
    else
      if i == init then
        return nil
      end
      return init, i-1
    end
  end

  if t == 45 then -- we ended on a hyphen
    return nil
  end

  return init, max
end

function Strict:parse_hostname(str,init,max)
  local i = init
  local t, s, e, m

  while i <= max do
    s, e = self:parse_hostlabel(str,i,max)
    if not s then
      if i == init then -- never saw a valid host label
        return nil
      end
      break -- we saw at least one valid hostlabel
    end
    m = e

    i = e + 1
    if i > max then
      break
    end
    t = byte(str,i)
    if t ~= 46 then
      if self:looks_ip4(str,init,i-1) then return nil end
      return init, i-1
    end
    m = i
    i = i + 1
  end

  -- make sure this doesn't also match an IP4 address
  if self:looks_ip4(str,init,m) then return nil end

  return init, m
end


function Strict:parse_host(str,init,max)
  local s, e
  s, e = self:parse_hostname(str,init,max)
  if not s then
    s, e = self:parse_ip4addr(str,init,max)
  end
  if not s then
    s, e = self:parse_ip6addr(str,init,max)
  end

  return s,e
end

function Strict:parse_sourcehost(str,init,max)
  local s, e

  for _,m in ipairs({'parse_hostname','parse_ip4addr','parse_ip6addr'}) do
    s, e = self[m](self,str,init,max)
    if s then
      if e + 1 > max then
        return nil
      end
      if byte(str,e+1) == 32 then
        return s,e
      end
    end
  end
  return nil
end

Strict.parse_userhost = Strict.parse_sourcehost

function Strict:parse_nick(str,init,max)
  local t
  local i = init

  while i <= max do
    t = byte(str,i)
    if self:is_nickchar(t,i-init+1) then
      i = i + 1
    else
      if i == init then
        return nil
      end
      return init, i-1
    end
  end
  return init,max
end

function Strict:parse_user(str,init,max)
  local t
  local i = init

  while i <= max do
    t = byte(str,i)
    if self:is_userchar(t,i-init+1) then
      i = i + 1
    else
      if i == init then
        return nil
      end
      return init, i-1
    end
  end
  return init,max
end

function Strict:parse_source(str,init,max)
  local i, t
  local s, e = self:parse_sourcehost(str,init,max)
  local source = {}
  if s then
    i = e + 1
    if i > max then return nil end
    if byte(str,i) == 32 then
      source.host = sub(str,s,e)
      return source, i+1
    end
  end

  s, e = self:parse_nick(str,init,max)
  if not s then return nil end
  source.nick = sub(str,s,e)
  i = e + 1
  if i > max then return nil end

  t = byte(str,i)
  if t == 33 then -- '!'
    if i+1 > max then return nil end
    s, e = self:parse_user(str,i+1,max)
    if not s then return nil end
    source.user = sub(str,s,e)
    i = e + 1
    if i > max then return nil end
  end

  t = byte(str,i)
  if t == 64 then -- '@'
    if i+1 > max then return nil end
    s, e = self:parse_userhost(str,i+1,max)
    if not s then
      return nil
    end
    source.host = sub(str,s,e)
    i = e + 1
    if i > max then return nil end
  end

  t = byte(str,i)
  if t ~= 32 then
    return nil
  end

  return source, i+1
end

function Strict.parse_tag_value(_,str,init,max)
  local i = init
  local t

  while i <= max do
    t = byte(str,i)
    if   t == 0
      or t == 10
      or t == 13
      or t == 32
      or t == 59 then
      return init, i-1
    else
      i = i + 1
    end
  end
  return nil
end

function Strict:parse_tag_name(str,init,max)
  local i, t
  i = init
  while i <= max do
    t = byte(str,i)
    if self:is_letter(t) or self:is_digit(t) or t == 45 then
      i = i + 1
    else
      if i == init then
        return nil
      end
      return init, i-1
    end
  end
  return nil
end

function Strict:parse_tag_vendor(str,init,max)
  local _, e

  _, e = self:parse_host(str,init,max)
  if not e then return nil end
  e = e + 1
  if e > max then return nil end
  if byte(str,e) ~= 47 then return nil end
  return init, e
end

function Strict:parse_tag_key(str,init,max)
  local i,t
  local s,e

  i = init
  t = byte(str,i)
  if t == 43 then -- '+'
    i = i + 1
    if i > max then
      return nil
    end
  end

  t = byte(str,i)
  if t == 32 or t == 47 or t == 59 or t == 61 then -- space, slash, semicolon, equals
    return nil
  end

  s, e = self:parse_tag_vendor(str,i,max)
  if s then
    i = e + 1
  end

  s, e = self:parse_tag_name(str,i,max)
  if s then
    return init, e
  end

  return nil
end

function Strict:parse_tags(str,init,max)
  local i,t
  local key_s,key_e,key
  local val_s,val_e
  local tags = {}

  i = init
  while i <= max do
    key_s,key_e = self:parse_tag_key(str,i,max)
    if not key_s then
      return nil
    end
    key = sub(str,key_s,key_e)
    i = key_e + 1
    t = byte(str,i)
    if t == 32 then
      tags[key] = false
      return tags, i
    elseif t == 59 then
      tags[key] = false
      i = i + 1
    elseif t == 61 then
      i = i + 1
      if i > max then
        return nil
      end
      val_s,val_e = self:parse_tag_value(str,i,max)
      if not val_s then
        return nil
      end
      if val_s > val_e then -- empty string
        tags[key] = false
      else
        tags[key] = self:unescape_tag_val(sub(str,val_s,val_e))
      end
      i = val_e + 1
      t = byte(str,i)
      if t == 32 then
        return tags, i
      elseif t ~= 59 then
        return nil
      end
      i = i + 1
    else
      return nil
    end
  end
  return nil
end

function Strict:parse_message(str,init,max)
  local i = init
  local t, s, e
  local params

  local message = {}

  t = byte(str,i)
  if t == 64 then
    i = i + 1
    if i > max then
      return nil
    end
    message.tags, i = self:parse_tags(str,i,max)
    if not message.tags then
      return nil
    end
    if i > max then return nil end
    while i <= max and byte(str,i) == 32  do
      i = i + 1
    end
    if i > max then
      return nil
    end
  end

  t = byte(str,i)
  if t == 58 then
    i = i + 1
    if i > max then
      return nil
    end
    message.source, i = self:parse_source(str,i,max)
    if not message.source then
      return nil
    end

    while i <= max and byte(str,i) == 32  do
      i = i + 1
    end
    if i > max then
      return nil
    end
  end

  s, e = self:parse_command(str,i,max)

  if not s then
    return nil
  end

  message.command = sub(str,s,e)

  i = e + 1

  if i > max then
    return message, i
  end

  t = byte(str,i)
  if t == 13 then -- CR
    i = i + 1
    if i > max then
      return nil
    end
    t = byte(str,i)
  end

  if t == 10 then -- LF
    return message, i+1
  end

  if byte(str,i) ~= 32 then
    return nil
  end
  i = i + 1

  while i <= max and byte(str,i) == 32 do
    i = i + 1
  end

  params = self:parse_params(str,i,max)
  if not params then
    return nil
  end

  message.params = {}
  for pi,p in ipairs(params) do
    message.params[pi] = sub(str,p[1],p[2])
    i = p[2]
  end
  i = i + 1
  if i > max then
    return message, i
  end

  t = byte(str,i)
  if t == 13 then -- CR
    i = i + 1
    if i > max then
      return nil
    end
    t = byte(str,i)
  end

  if t == 10 then -- LF
    i = i + 1
  end

  return message, i
end

function Loose:parse_userhost(str,init,max)
  local i = init

  while i <= max do
    if self:is_nonwhite(byte(str,i)) then
      i = i + 1
    else
      if i == init then
        return nil
      end
      return init, i-1
    end
  end
  return init, max
end

function Loose.is_nickchar(_,t)
  if
       t == 0
    or t == 10
    or t == 13
    or t == 32
    or t == 33
    or t == 64
    then return false end
  return true
end

-- just read until we see a slash and return true or space and return false
function Loose.parse_tag_vendor(_,str,init,max)
  local i, t
  i = init
  while i <= max do
    t = byte(str,i)
    if t == 32 or t == 59 or t == 61 then -- space, semicolon, equals
      return nil
    elseif t == 47 then
      break
    end
    i = i + 1
  end
  if i == init or i > max then return nil end
  return init, i
end

-- just read until we see a space or equals
function Loose.parse_tag_name(_,str,init,max)
  local i, t
  i = init
  while i <= max do
    t = byte(str,i)
    if t == 32 or t == 59 or t == 61 then -- space, semicolon, equals
      break
    end
    i = i + 1
  end
  if i == init or i > max then return nil end
  return init, i-1
end

function Twitch:is_nickchar(t,pos)
  if self:is_letter(t) or self:is_digit(t) then
    return true
  elseif t == 95 then
    if pos == 1 then
      return false
    end
    return true
  end
  return false
end

Twitch.is_userchar = Twitch.is_nickchar

function Twitch:parse_userhost(str,init,max)
  local s, e, _
  local i, t

  s, e = self:parse_user(str,init,max)

  if not s then
    return Strict.parse_userhost(self,str,init,max)
  end

  i = e + 1
  if i > max then return nil end
  t = byte(str,i)
  if t ~= 46 then
    return Strict.parse_userhost(self,str,init,max)
  end
  i = i + 1
  if i > max then return nil end
  _, e = Strict.parse_userhost(self,str,i,max)
  if not e then
    return nil
  end
  return init, e
end

function Strict:parse(str,init)
  init = init or 1
  return self:parse_message(str,init,#str)
end

for k,v in pairs(Strict) do
  if not Twitch[k] then Twitch[k] = v end
  if not Loose[k] then Loose[k] = v end
end

local Strict__mt = {
  __index = Strict,
  __name  = 'irc-parser.strict',
  __call = Strict.parse
}

local Twitch__mt = {
  __index = Twitch,
  __name  = 'irc-parser.twitch',
  __call  = Twitch.parse,
}

local Loose__mt = {
  __index = Loose,
  __name  = 'irc-parser.loose',
  __call  = Loose.parse
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

local function new(typ)
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
