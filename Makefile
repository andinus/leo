# Install to /usr/local unless otherwise specified, such as `make
# PREFIX=/app`.
PREFIX?=/usr/local

INSTALL?=install
INSTALL_PROGRAM=$(INSTALL) -Dm 755
INSTALL_DATA=install -Dm 644

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

install: leo.raku share/leo.1 share/leo.toml README README.org # system install
	$(INSTALL_PROGRAM) leo.raku $(bindir)/leo

	$(INSTALL_DATA) share/leo.1 $(mandir)/man1/leo.1
	$(INSTALL_DATA) share/leo.toml $(sharedir)/leo/leo.toml

	$(INSTALL_DATA) README $(sharedir)/doc/leo/README
	$(INSTALL_DATA) README.org $(sharedir)/doc/leo/README.org

uninstall: # system uninstall
	rm -f $(bindir)/leo
	rm -f $(mandir)/man1/leo.1
	rm -fr $(sharedir)/leo/
	rm -fr $(sharedir)/doc/leo/

.PHONY: install uninstall help
