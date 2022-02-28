.PHONY: release github-release test coverage
.SUFFIXES:

LUA = lua
PACKAGE = irc-parser
VERSION = $(shell LUA_PATH='src/?.lua' $(LUA) -e 'print(require("irc-parser")._VERSION)')
COVERAGE = default
BUSTED_ARGS =

echo:
	echo $(VERSION)

test:
	exec busted

coverage:
	mkdir -p coverage/$(COVERAGE)
	busted -c --lua="$(LUA)" $(BUSTED_ARGS)
	luacov -r gcovr
	gcovr --exclude 'spec/*' --html-details coverage/$(COVERAGE)/index.html --add-tracefile luacov.report.out
	gcovr --exclude 'spec/*' --xml coverage/$(COVERAGE)/index.xml --add-tracefile luacov.report.out

release:
	rm -rf dist/$(PACKAGE)-$(VERSION)
	rm -rf dist/$(PACKAGE)-$(VERSION).tar.gz
	rm -rf dist/$(PACKAGE)-$(VERSION).tar.xz
	mkdir -p dist/$(PACKAGE)-$(VERSION)/
	rsync -a src dist/$(PACKAGE)-$(VERSION)/
	rsync -a spec dist/$(PACKAGE)-$(VERSION)/
	rsync -a README.md dist/$(PACKAGE)-$(VERSION)/README.md
	rsync -a LICENSE dist/$(PACKAGE)-$(VERSION)/LICENSE
	sed 's/@VERSION@/$(VERSION)/g' < $(PACKAGE)-template.rockspec > dist/$(PACKAGE)-$(VERSION)/$(PACKAGE)-$(VERSION)-1.rockspec
	sed 's/@VERSION@/$(VERSION)/g' < dist.ini > dist/$(PACKAGE)-$(VERSION)/dist.ini
	tar -C dist -cvf dist/$(PACKAGE)-$(VERSION).tar $(PACKAGE)-$(VERSION)
	gzip -k dist/$(PACKAGE)-$(VERSION).tar
	xz dist/$(PACKAGE)-$(VERSION).tar

github-release:
	source $(HOME)/.github-token && github-release release \
	  --user jprjr \
	  --repo lua-$(PACKAGE) \
	  --tag v$(VERSION)
	source $(HOME)/.github-token && github-release upload \
	  --user jprjr \
	  --repo lua-$(PACKAGE) \
	  --tag v$(VERSION) \
	  --name $(PACKAGE)-$(VERSION).tar.gz \
	  --file dist/$(PACKAGE)-$(VERSION).tar.gz
	source $(HOME)/.github-token && github-release upload \
	  --user jprjr \
	  --repo lua-$(PACKAGE) \
	  --tag v$(VERSION) \
	  --name $(PACKAGE)-$(VERSION).tar.xz \
	  --file dist/$(PACKAGE)-$(VERSION).tar.xz

