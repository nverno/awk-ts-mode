SHELL = /bin/bash

TSDIR   ?= $(CURDIR)/tree-sitter-awk
TESTDIR ?= $(TSDIR)/examples

all:
	@

dev: $(TSDIR)
$(TSDIR):
	@git clone --depth=1 https://github.com/Beaglefoot/tree-sitter-awk
	@echo *NOTE* npm build can take a while
	cd $(TSDIR) &&                                         \
		npm --loglevel=info --progress=true install && \
		npm run generate

.PHONY: parse-%
parse-%:
	cd $(TSDIR) && npx tree-sitter parse $(TESTDIR)/$(subst parse-,,$@)
