PREFIX  ?= /usr/local
MANDIR  ?= $(PREFIX)/share/man

.PHONY: install-man uninstall-man

install-man:
	install -d $(DESTDIR)$(MANDIR)/man1
	install -m 644 man/man1/*.1 $(DESTDIR)$(MANDIR)/man1/

uninstall-man:
	rm -f $(DESTDIR)$(MANDIR)/man1/memory-usage-report-kvm.1
	rm -f $(DESTDIR)$(MANDIR)/man1/memory-usage-report-esxi.1
	rm -f $(DESTDIR)$(MANDIR)/man1/create-ssl-csr.1
	rm -f $(DESTDIR)$(MANDIR)/man1/guacamole-reset-user-otp.1
