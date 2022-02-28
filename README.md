# lua-irc-parser

[![codecov](https://codecov.io/gh/jprjr/lua-irc-parser/branch/main/graph/badge.svg?token=9wV63fuaVu)](https://codecov.io/gh/jprjr/lua-irc-parser)

An IRC parser in LPEG, with a pure-Lua fallback. Supports IRCv3 message tags.

## Synopsis

```lua
local parser = require('irc-parser').new()
local line = '@message-id=12345;some-content=hello\\sthere;empty-str=;empty :nick!user@example.com PRIVMSG #a-room ::-) Hi there!'
local parsed, pos = parser(line)

--[[
  parsed is a table:
  {
    tags = {
      empty = false,
      ["empty-str"] = false,
      ["message-id"] = "12345",
      ["some-content"] = "hello there"
    },
    source = {
      host = "example.com",
      nick = "nick",
      user = "user"
    },
    command = "PRIVMSG",
    params = { "#a-room", ":-) Hi there!" },
  }

  pos is the length of the string + 1, so in this case 115
]]
```

## Installation

### luarocks

Available on [luarocks](https://luarocks.org/modules/jprjr/irc-parser):

```bash
luarocks install irc-parser
```

### OPM

Available on [OPM](https://opm.openresty.org/package/jprjr/irc-parser/)

```bash
opm install jprjr/irc-parser
```

## Usage

By default, you can `require('irc-parser')`, and it will automatically
choose an appropriate backend.

It will first try to load the LPEG-based parser, and fall back
to the pure-Lua parser if LPEG is not available.

You can force a specific backend by requiring it: `require('irc-parser.fallback')`
for the Lua fallback, and `require('irc-parser.lpeg')` for the LPEG version.

You can then instantiate a parser with `.new()` (or just call the returned
module directly like `parser = require('irc-parser')()`.

There's three different parsers available:

* `LOOSE` - (the default), aims to be broadly-compatible.
* `STRICT` - follows the IRC RFCs as closely as possible.
* `TWITCH` - essentially `STRICT` with a few modifications for Twitch's IRC interface.

The default `LOOSE` parser should work on most IRC servers, including Twitch.

You can specify which parser you'd like in a few ways:

```lua

-- these are all equivalent:
local strict_parser = require('irc-parser')('strict')

local mod = require('irc-parser')
local strict_parser = mod.new(mod.STRICT)
```

The parser exposes a single method, `parser:parse(str, [pos])`. The parser itself
can also be called as a function, `parser(str, [pos])`.

It accepts a string argument, the string argument can be terminated with
a newline character, or a carriage return and newline, or nothing. It also
accepts an optional position argument, this should be a number indicating
where to start parsing.

If successful, it will return a parsed table, and the position for the
next parse (essentially the length of the line + 1). This position
argument is so you can have a string with multiple lines.

If not successful, it returns `nil`.

Here's an example of looping through a block of data using the
position argument and return value.

```
local parser = require('irc-parser').new()
-- we'll say that "raw.txt" is a raw IRC log file with multiple lines
local rawfile = io.open('raw.txt','rb')
local rawdata = rawfile:read('*a')
rawfile:close()

local parsed
local pos = 1

while pos < #rawdata do
  parsed, pos = parser:parse(rawdata,pos)
  if not parsed then
    break
  end
  -- do something with parsed
end
```

### Message Tags

When dealing with message tags, the specs allow for creating tags
with empty values, as well as missing values.

The specs state that clients must interpret empty tag values as
equivalent to missing tag values. Clients may convert from the
empty form to the missing form, but not the other way around.

Empty tags and missing tags are both represented with the
boolean `false`. This way, the tag still appears in the `tags`
table. If you simply test that the value is truthy, you know
it's a string with data.

## LICENSE

MIT (see file `LICENSE`).
