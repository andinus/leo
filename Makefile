# Install to /usr/local unless otherwise specified, such as `make
# PREFIX=/app`.
PREFIX?=/usr/local

INSTALL?=install
INSTALL_PROGRAM=$(INSTALL) -Dm 755
INSTALL_DATA=$(INSTALL) -Dm 644

bindir=$(DESTDIR)$(PREFIX)/bin
sharedir=$(DESTDIR)$(PREFIX)/share

# OpenBSD doesn't index /usr/local/share/man by default so
# /usr/local/man will be used.
platform_id != uname -s
mandir != if [ $(platform_id) = OpenBSD ]; then \
    echo $(DESTDIR)$(PREFIX)/man; \
else \
    echo $(DESTDIR)$(PREFIX)/share/man; \
fi

help:
	@echo "targets:"
	@awk -F '#' '/^[a-zA-Z0-9_-]+:.*?#/ { print $0 }' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)#\(.*\)/  \1|-\3/p' \
	| column -t  -s '|'

install: leo.pl leo.1 share/leo.conf README # system install
	$(INSTALL_PROGRAM) leo.pl $(bindir)/leo

	$(INSTALL_DATA) leo.1 $(mandir)/man1/leo.1
	$(INSTALL_DATA) share/leo.conf $(sharedir)/leo/leo.conf
	$(INSTALL_DATA) README $(sharedir)/doc/leo/README


uninstall: # system uninstall
	rm -f $(bindir)/leo
	rm -f $(mandir)/man1/leo.1
	rm -fr $(sharedir)/leo/
	rm -fr $(sharedir)/doc/leo/

.PHONY: install uninstall help
