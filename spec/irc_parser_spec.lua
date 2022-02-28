describe('irc-parser module #version', function()
  it('should report a version', function()
    local p = require('irc-parser')
    assert.is_string(p._VERSION)
  end)
end)

local function generate_backend_test(b)
  describe('irc-parser: #' .. b .. ' backend',function()
    local irc_parser = require('irc-parser.' .. b)

    it('should have keys representing the #core parser types', function()
      assert.is_table(irc_parser.LOOSE)
      assert.is_table(irc_parser.TWITCH)
      assert.is_table(irc_parser.STRICT)
    end)

    it('#core should be callable without arguments', function()
      local parser = irc_parser()
      local mt = debug.getmetatable(parser)
      assert.are_equals(mt.__name,'irc-parser.loose')
    end)

    it('#core should be callable with string arguments', function()
      for _,t in ipairs({'loose','strict','twitch'}) do
        local parser = irc_parser(t)
        local mt = debug.getmetatable(parser)
        assert.are_equals(mt.__name,'irc-parser.' .. t)
      end
    end)

    it('#core should be callable with numeric arguments', function()
      for i,t in ipairs({'loose','strict','twitch'}) do
        local parser = irc_parser(i)
        local mt = debug.getmetatable(parser)
        assert.are_equals(mt.__name,'irc-parser.' .. t)
      end
    end)

    it('#core should be callable with table arguments', function()
      for _,t in ipairs({'loose','strict','twitch'}) do
        local key = t:upper()
        local parser = irc_parser(irc_parser[key])
        local mt = debug.getmetatable(parser)
        assert.are_equals(mt.__name,'irc-parser.' .. t)
      end
    end)

    it('#core should return nil on an invalid type', function()
      assert.is_nil(irc_parser('INVALID'))
    end)

    describe('#core function new', function()
      it('should be callable without arguments', function()
        local parser = irc_parser.new()
        local mt = debug.getmetatable(parser)
        assert.are_equals(mt.__name,'irc-parser.loose')
      end)

      it('should be callable with string arguments', function()
        for _,t in ipairs({'loose','strict','twitch'}) do
          local parser = irc_parser.new(t)
          local mt = debug.getmetatable(parser)
          assert.are_equals(mt.__name,'irc-parser.' .. t)
        end
      end)

      it('should be callable with numeric arguments', function()
        for i,t in ipairs({'loose','strict','twitch'}) do
          local parser = irc_parser.new(i)
          local mt = debug.getmetatable(parser)
          assert.are_equals(mt.__name,'irc-parser.' .. t)
        end
      end)

      it('should be callable with table arguments', function()
        for _,t in ipairs({'loose','strict','twitch'}) do
          local key = t:upper()
          local parser = irc_parser.new(irc_parser[key])
          local mt = debug.getmetatable(parser)
          assert.are_equals(mt.__name,'irc-parser.' .. t)
        end
      end)

      it('#core should return nil on an invalid type', function()
        assert.is_nil(irc_parser.new('INVALID'))
      end)

    end)

    describe('#strict parser', function()
      local parser = irc_parser.new('strict')

      it('should only accept a #source with valid hostnames/ips', function()
        assert.is_nil(parser:parse(':nick!user@not_a_hostname PRIVMSG'))
        assert.is_nil(parser:parse(':nick!user@not/a/hostname PRIVMSG'))
        assert.is_nil(parser:parse(':nick!user@256.0.0.1 PRIVMSG'))
        assert.is_same(parser:parse(':nick!user@127.0.0.1 PRIVMSG'), {
          command = 'PRIVMSG',
          source = {
            nick = 'nick',
            user = 'user',
            host = '127.0.0.1',
          }
        })
        assert.is_same(parser:parse(':nick!user@::1 PRIVMSG'), {
          command = 'PRIVMSG',
          source = {
            nick = 'nick',
            user = 'user',
            host = '::1',
          }
        })
        assert.is_same(parser:parse(':nick!user@0:0:0:0:0:0:0:1 PRIVMSG'), {
          command = 'PRIVMSG',
          source = {
            nick = 'nick',
            user = 'user',
            host = '0:0:0:0:0:0:0:1',
          }
        })
        assert.is_same(parser:parse(':nick!user@example.com PRIVMSG'), {
          command = 'PRIVMSG',
          source = {
            nick = 'nick',
            user = 'user',
            host = 'example.com',
          }
        })
      end)

      it('should accept valid #nickames', function()
        assert.is_not_nil(parser:parse(':nick@hostname PRIVMSG'))
        assert.is_not_nil(parser:parse(':n0@hostname PRIVMSG'))
        assert.is_not_nil(parser:parse(':n@hostname PRIVMSG'))
        assert.is_not_nil(parser:parse(':{per-son}@hostname PRIVMSG'))
      end)

      it('should reject invalid #nickames', function()
        -- can't start with a digit or hyphen
        assert.is_nil(parser:parse(':0nick@hostname PRIVMSG'))
        assert.is_nil(parser:parse(':-nick@hostname PRIVMSG'))
        -- can't be empty
        assert.is_nil(parser:parse(':@hostname PRIVMSG'))
      end)

      it('should reject #tags with non-hostname vendors', function()
        assert.is_nil(parser:parse('@not_a_domain/a=something PRIVMSG'))
      end)
    end)

    describe('#loose parser', function()
      local parser = irc_parser.new('loose')

      it('should accept anything for the #hostname field', function()
        assert.is_same(parser:parse(':nick!user@\001text/` PRIVMSG'),
          {
            command = 'PRIVMSG',
            source = {
              nick = 'nick',
              user = 'user',
              host = '\001text/`',
            }
          }
        )
      end)

      it('should accept an invalid #nickame', function()
        -- allow any character
        assert.is_same(parser:parse(':\001nick@hostname PRIVMSG'), {
          command = 'PRIVMSG',
          source = {
            nick = '\001nick',
            host = 'hostname',
          }
        })
        assert.is_same(parser:parse(':-nick@hostname PRIVMSG'), {
          command = 'PRIVMSG',
          source = {
            nick = '-nick',
            host = 'hostname',
          }
        })
        -- can't be empty
        assert.is_nil(parser:parse(':@hostname PRIVMSG'))
      end)

      it('should accept #tags with non-hostname vendors', function()
        assert.is_same(parser:parse('@not_a_domain/a=something PRIVMSG'), {
          tags = {
            ['not_a_domain/a'] = 'something',
          },
          command = 'PRIVMSG',
        })
      end)

    end)

    describe('twitch parser', function()
      local parser = irc_parser.new('twitch')

      it('should reject nicks/users/hosts that are not valid twitch usernames', function()
        assert.is_nil(parser:parse(':_invalid!valid@valid.tmi.twitch.tv PRIVMSG'))
        assert.is_nil(parser:parse(':valid!_invalid@valid.tmi.twitch.tv PRIVMSG'))
        assert.is_nil(parser:parse(':valid!valid@_invalid.tmi.twitch.tv PRIVMSG'))
        assert.is_nil(parser:parse(':inval{}id!valid@valid.tmi.twitch.tv PRIVMSG'))
        assert.is_nil(parser:parse(':valid!inva{}lid@valid.tmi.twitch.tv PRIVMSG'))
        assert.is_nil(parser:parse(':valid!valid@inval{}id.tmi.twitch.tv PRIVMSG'))
      end)

      it('should accept nicks/users that are valid twitch usernames, but invalid IRC nicks', function()
        assert.is_same(parser:parse(':1234!5678@1234.tmi.twitch.tv PRIVMSG'), {
          command = 'PRIVMSG',
          source = {
            nick = '1234',
            user = '5678',
            host = '1234.tmi.twitch.tv',
          }
        })
      end)
    end)

    describe('all parsers', function()
      for _,t in ipairs({'loose','twitch','strict'}) do
        describe(t .. ' parser', function()
          local parser = irc_parser.new(t)
          it('should reject empty and whitespace-only strings', function()
            assert.is_nil(parser:parse(''))
            assert.is_nil(parser:parse(' '))
            assert.is_nil(parser:parse('     '))
            assert.is_nil(parser:parse('\r'))
            assert.is_nil(parser:parse('\r\n'))
            assert.is_nil(parser:parse('\n'))
            assert.is_nil(parser:parse(' \n '))
          end)

          it('should reject #tags after the beginning of a message', function()
            assert.is_nil(parser:parse(' @tag=1; 001'))
          end)

          it('should reject source after the beginning of a message', function()
            assert.is_nil(parser:parse(' :127.0.0.1 001'))
          end)

          it('should reject #tags without a command', function()
            assert.is_nil(parser:parse('@tag=1 '))
            assert.is_nil(parser:parse('@tag=1'))
            assert.is_nil(parser:parse('@tag=1 \r\n'))
            assert.is_nil(parser:parse('@tag=1 \n'))
            assert.is_nil(parser:parse('@tag=1\r\n'))
            assert.is_nil(parser:parse('@tag=1\n'))
          end)

          it('should reject #source without a command', function()
            assert.is_nil(parser:parse(':127.0.0.1 '))
            assert.is_nil(parser:parse(':127.0.0.1'))
            assert.is_nil(parser:parse(':127.0.0.1 \r\n'))
            assert.is_nil(parser:parse(':127.0.0.1 \n'))
            assert.is_nil(parser:parse(':127.0.0.1\r\n'))
            assert.is_nil(parser:parse(':127.0.0.1\n'))
          end)

          it('should accept shortname #source', function()
            assert.is_same(parser:parse(':localhost 001'),{
              command = '001',
              source = {
                host = 'localhost',
              },
            })
          end)

          it('should accept ipv4 #source', function()
            assert.is_same(parser:parse(':127.0.0.1 001'),{
              command = '001',
              source = {
                host = '127.0.0.1',
              },
            })
          end)

          it('should accept ipv6 #source', function()
            assert.is_same(parser:parse(':::1 001'),{
              command = '001',
              source = {
                host = '::1',
              },
            })
            assert.is_same(parser:parse(':0:0:0:0:0:0:0:1 001'),{
              command = '001',
              source = {
                host = '0:0:0:0:0:0:0:1',
              },
            })
            assert.is_same(parser:parse(':2001:db8:122:344::192.0.2.33 001'), {
              command = '001',
              source = {
                host = '2001:db8:122:344::192.0.2.33',
              },
            })
          end)

          it('should accept nicks with ipv6 #source', function()
            assert.is_same(parser:parse(':nick@::1 001'),{
              command = '001',
              source = {
                host = '::1',
                nick = 'nick',
              },
            })
            assert.is_same(parser:parse(':nick@0:0:0:0:0:0:0:1 001'),{
              command = '001',
              source = {
                host = '0:0:0:0:0:0:0:1',
                nick = 'nick',
              },
            })
            assert.is_same(parser:parse(':nick@2001:db8:122:344::192.0.2.33 001'), {
              command = '001',
              source = {
                host = '2001:db8:122:344::192.0.2.33',
                nick = 'nick',
              },
            })
          end)

          it('should accept numerics', function()
            local res = {
              command = '001'
            }
            assert.is_same(parser:parse('001'),res)
            assert.is_same(parser:parse('001\n'),res)
            assert.is_same(parser:parse('001\r\n'),res)
          end)

          it('should accept a command', function()
            local res = {
              command = 'PRIVMSG',
            }
            assert.is_same(parser:parse('PRIVMSG'),res)
            assert.is_same(parser:parse('PRIVMSG\n'),res)
            assert.is_same(parser:parse('PRIVMSG\r\n'),res)
          end)

          it('should reject a space after a command', function()
            assert.is_nil(parser:parse('PRIVMSG '))
          end)

          it('should accept a mixed-case command', function()
            local tbl = parser:parse('PrIvMsG')
            assert.is_same(tbl, {
              command = 'PrIvMsG',
            })
          end)

          it('should reject a mixed letter/digit command', function()
            assert.is_nil(parser:parse('001PRIVMSG'))
            assert.is_nil(parser:parse('PRIVMSG001'))
          end)

          it('should reject invalid-length numerics', function()
            assert.is_nil(parser:parse('0'))
            assert.is_nil(parser:parse('00'))
            assert.is_nil(parser:parse('0000'))
          end)

          it('should accept middle parameters', function()
            assert.is_same(parser:parse('PRIVMSG #room'),
              {
                command = 'PRIVMSG',
                params = { '#room' },
              }
            )

            assert.is_same(parser:parse('PRIVMSG #:room'),
              {
                command = 'PRIVMSG',
                params = { '#:room' },
              }
            )

            assert.is_same(parser:parse('PRIVMSG #room:'),
              {
                command = 'PRIVMSG',
                params = { '#room:' },
              }
            )
          end)

          it('should accept trailing parameters', function()
            assert.is_same(parser:parse('PRIVMSG #room ::) hello there! :-)'),
              {
                command = 'PRIVMSG',
                params = { '#room', ':) hello there! :-)' },
              }
            )
          end)

          it('should accept zero-length trailing parameters', function()
            local res = {
              command = 'PRIVMSG',
              params = { '#room', '' },
            }

            assert.is_same(parser:parse('PRIVMSG #room :'), res)
            assert.is_same(parser:parse('PRIVMSG #room :\n'), res)
            assert.is_same(parser:parse('PRIVMSG #room :\r\n'), res)
          end)

          it('should accept reject trailing spaces after parameters', function()
            assert.is_nil(parser:parse('PRIVMSG '))
            assert.is_nil(parser:parse('PRIVMSG #some-room '))
          end)

          it('should consume the entire string, including trailing crlf', function()
            local str = 'PRIVMSG #room ::) hello there! :-)'
            local lf = str .. '\n'
            local crlf = str .. '\r\n'

            assert.is_equal(#str+1,select(2,parser:parse(str)))
            assert.is_equal(#lf+1,select(2,parser:parse(lf)))
            assert.is_equal(#crlf+1,select(2,parser:parse(crlf)))
          end)

          it('should only retain the last instance of #tags', function()
            local res = {
              tags = {
                ['a'] = 'final',
                ['b'] = false,
              },
              command = 'PRIVMSG',
            }
            local str = '@a=1;b=2;a;a=final;b PRIVMSG'
            assert.is_same(res,parser:parse(str))
          end)

          it('should escape #tags including invalid escapes', function()
            local res = {
              tags = {
                ['a'] = ':-) Hi there;\r\n\\s',
              },
              command = 'PRIVMSG',
            }
            local str = '@a=:\\-)\\sHi\\sthere\\:\\r\\n\\\\s\\ PRIVMSG'
            assert.is_same(res,parser:parse(str))
          end)

          it('should accept client #tags with the client prefix', function()
            local res = {
              tags = {
                ['+a'] = 'hello',
              },
              command = 'PRIVMSG',
            }
            assert.is_same(res,parser:parse('@+a=hello PRIVMSG'))
          end)

          it('should accept vendor #tags', function()
            assert.is_same(parser:parse('@a/b=hello PRIVMSG'), {
              tags = {
                ['a/b'] = 'hello',
              },
              command = 'PRIVMSG',
            })
            assert.is_same(parser:parse('@example.com/b-2=hello PRIVMSG'), {
              tags = {
                ['example.com/b-2'] = 'hello',
              },
              command = 'PRIVMSG',
            })
            assert.is_same(parser:parse('@+127.0.0.1/b-2=hello PRIVMSG'), {
              tags = {
                ['+127.0.0.1/b-2'] = 'hello',
              },
              command = 'PRIVMSG',
            })
            assert.is_same(parser:parse('@::1/b-2=hello PRIVMSG'), {
              tags = {
                ['::1/b-2'] = 'hello',
              },
              command = 'PRIVMSG',
            })
            assert.is_same(parser:parse('@+::1/b-2=hello PRIVMSG'), {
              tags = {
                ['+::1/b-2'] = 'hello',
              },
              command = 'PRIVMSG',
            })
          end)

          it('should convert empty #tags values to false', function()
            local res = {
              tags = {
                ['a'] = false,
                ['b'] = 'something',
              },
              command = 'PRIVMSG',
            }
            local str = '@b=something;a= PRIVMSG'
            assert.is_same(res,parser:parse(str))
            str = '@a=;b=something PRIVMSG'
            assert.is_same(res,parser:parse(str))
          end)

          it('should handle 1-character #tags', function()
            local res = {
              tags = {
                ['a'] = false,
                ['b'] = 'something',
                ['c'] = '0',
                ['d'] = '1',
              },
              command = 'PRIVMSG',
            }
            local str = '@b=something;a=;c=0;d=1 PRIVMSG'
            assert.is_same(res,parser:parse(str))
          end)

          it('should handle #tags with = in the value', function()
            local res = {
              tags = {
                ['a'] = false,
                ['b'] = 'something',
                ['url'] = 'http://example.com?q=true',
                ['d'] = '1',
              },
              command = 'PRIVMSG',
            }
            local str = '@b=something;a=;url=http://example.com?q=true;d=1 PRIVMSG'
            assert.is_same(res,parser:parse(str))
          end)

          it('should convert missing #tags values to false', function()
            local res = {
              tags = {
                ['a'] = false,
                ['b'] = 'something',
              },
              command = 'PRIVMSG',
            }
            local str = '@b=something;a PRIVMSG'
            assert.is_same(res,parser:parse(str))
            str = '@a;b=something PRIVMSG'
            assert.is_same(res,parser:parse(str))
          end)

          it('should reject #tags that end on semicolon', function()
            assert.is_nil(parser:parse('@a=;b=something; PRIVMSG'))
            assert.is_nil(parser:parse('@b=something;a=; PRIVMSG'))
          end)

          it('should reject #tags with only a client prefix as key', function()
            assert.is_nil(parser:parse('@+=1 PRIVMSG'))
          end)

          it('should reject #tags with an empty vendor', function()
            assert.is_nil(parser:parse('@/a=1 PRIVMSG'))
            assert.is_nil(parser:parse('@+/a=1 PRIVMSG'))
          end)

        end)
      end
    end)
  end)
end

generate_backend_test('fallback')
local ok = pcall(require,'irc-parser.lpeg')
if ok then
  generate_backend_test('lpeg')
end
