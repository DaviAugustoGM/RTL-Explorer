APPDIR ?= $(HOME)/.local/share/rtl-explorer
BINDIR ?= $(HOME)/.local/bin
DESKTOPDIR ?= $(HOME)/.local/share/applications
DEPENDENCY_MODE ?= user

.NOTPARALLEL:
.PHONY: install install-system install-files dependencies check run uninstall uninstall-system

# User-local installation. No sudo or system package manager is used.
install: install-files dependencies check
	@echo "RTL Explorer installed in $(APPDIR)"
	@case ":$$PATH:" in *:"$(BINDIR)":*) ;; *) \
		echo "Add $(BINDIR) to PATH, or start with $(BINDIR)/rtl-explorer" ;; esac

install-system:
	@test "$$(id -u)" = 0 || (echo "Use: sudo make install-system" >&2; exit 1)
	$(MAKE) install APPDIR=/opt/rtl-explorer BINDIR=/usr/local/bin \
		DESKTOPDIR=/usr/local/share/applications DEPENDENCY_MODE=system

install-files:
	@test -n "$(APPDIR)" -a "$(APPDIR)" != / || (echo "Unsafe APPDIR: $(APPDIR)" >&2; exit 1)
	install -d "$(APPDIR)" "$(BINDIR)" "$(DESKTOPDIR)"
	cp -a src assets sample scripts "$(APPDIR)/"
	cp -a README.md EXPLICACAO_PROJETO.md INSTALL.md packaging/THIRD_PARTY.md "$(APPDIR)/"
	install -m 0755 packaging/linux/rtl-explorer "$(APPDIR)/rtl-explorer"
	ln -sfn "$(APPDIR)/rtl-explorer" "$(BINDIR)/rtl-explorer"
	sed 's|/opt/rtl-explorer|$(APPDIR)|g' packaging/linux/rtl-explorer.desktop > "$(DESKTOPDIR)/rtl-explorer.desktop"
	chmod 0644 "$(DESKTOPDIR)/rtl-explorer.desktop"

dependencies:
	sh packaging/linux/install-dependencies.sh "$(APPDIR)" "$(DEPENDENCY_MODE)"

check:
	@if test -x "$(APPDIR)/runtime/bin/tclsh"; then \
		TCLSH="$(APPDIR)/runtime/bin/tclsh"; \
	elif test -x "$(APPDIR)/runtime/bin/tclsh8.6"; then \
		TCLSH="$(APPDIR)/runtime/bin/tclsh8.6"; \
	elif command -v tclsh >/dev/null 2>&1; then \
		TCLSH=tclsh; \
	else \
		echo "Tcl was not found after installation." >&2; exit 1; \
	fi; \
	RTL_EXPLORER_TOOLS="$(APPDIR)/tools" "$$TCLSH" "$(APPDIR)/scripts/check-toolchain.tcl"

run:
	@if test -x "$(APPDIR)/rtl-explorer"; then "$(APPDIR)/rtl-explorer"; else wish src/main.tcl; fi

uninstall:
	@test -n "$(APPDIR)" -a "$(APPDIR)" != / || (echo "Unsafe APPDIR: $(APPDIR)" >&2; exit 1)
	rm -f "$(BINDIR)/rtl-explorer" "$(DESKTOPDIR)/rtl-explorer.desktop"
	rm -rf -- "$(APPDIR)"

uninstall-system:
	@test "$$(id -u)" = 0 || (echo "Use: sudo make uninstall-system" >&2; exit 1)
	$(MAKE) uninstall APPDIR=/opt/rtl-explorer BINDIR=/usr/local/bin \
		DESKTOPDIR=/usr/local/share/applications
