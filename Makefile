PREFIX ?= ~/.local/bin

# When run as root, install the splash system-wide to /etc/profile.d so it
# runs for every interactive login.
UID := $(shell id -u)

.PHONY: install install-user install-system

ifeq ($(UID),0)
install: install-system
else
install: install-user
endif

install-user:
	mkdir -p $(PREFIX)
	cp scripts/bodhi-splash $(PREFIX)/bodhi-splash
	chmod +x $(PREFIX)/bodhi-splash

install-system:
	install -m 0644 scripts/bodhi-splash /etc/profile.d/bodhi-splash.sh
