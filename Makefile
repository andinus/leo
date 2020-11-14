# Install to /usr/local unless otherwise specified, such as `make
# PREFIX=/app`.
PREFIX?=/usr/local

INSTALL?=install
INSTALL_PROGRAM=$(INSTALL) -Dm 755
INSTALL_DATA=$(INSTALL) -Dm 644

bindir=$(DESTDIR)$(PREFIX)/bin
sharedir=$(DESTDIR)$(PREFIX)/share

help:
	@echo "targets:"
	@awk -F '#' '/^[a-zA-Z0-9_-]+:.*?#/ { print $0 }' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)#\(.*\)/  \1|-\3/p' \
	| column -t  -s '|'

install: leo.pl leo.1 # system install
	$(INSTALL_PROGRAM) leo.pl $(bindir)/leo
	$(INSTALL_DATA) leo.1 $(sharedir)/man/man1/leo.1

uninstall: # system uninstall
	rm -f $(bindir)/leo
	rm -f $(sharedir)/man/man1/leo.1

.PHONY: install uninstall help
