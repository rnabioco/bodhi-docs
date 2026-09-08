PREFIX ?= ~/.local/bin
# man finds ~/.local/share/man automatically when ~/.local/bin is on PATH.
MANDIR ?= ~/.local/share/man/man1

# When run as root, install system-wide: the scripts to /usr/local/bin, their
# man pages to /usr/local/share/man, and the splash to /etc/profile.d so it
# runs for every interactive login.
#
# sinteractive is NOT installed from here. It lives in rnabioco/sinteractive
# and is installed from that checkout (`make install`, or `sudo make nodes`
# to fan the binary out to the compute nodes).
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
	cp scripts/quota_check $(PREFIX)/quota_check
	chmod +x $(PREFIX)/quota_check
	mkdir -p $(MANDIR)
	cp man/quota_check.1 $(MANDIR)/quota_check.1

install-system:
	install -m 0644 scripts/bodhi-splash /etc/profile.d/bodhi-splash.sh
	install -m 0755 scripts/quota_check /usr/local/bin/quota_check
	install -D -m 0644 man/quota_check.1 /usr/local/share/man/man1/quota_check.1

# ---------------------------------------------------------------------------
# quota_check on the compute nodes.
#
# The script queries the storage daemons over TCP and needs nothing but bash
# and coreutils, so it runs anywhere on the cluster — but /usr/local is
# node-local (root fs, not shared), so the file itself has to be put on each
# node. `make quota-nodes` does that; `make quota-nodes-check` reports what
# each node actually has, which is the only way a half-finished fan-out
# becomes visible.
#
# The hard quotas are a separate problem: they live in /etc/quota_current.txt,
# which the admins regenerate on the head node only. Without it a compute node
# can still report usage, but the "Hard Quota" and "% Used" columns read "-".
# `make publish-quota-file` copies it to /cluster/share, an NFS mount every
# node already has, which is the second path quota_check looks in. Run it
# from the same cron job that regenerates the file, or the compute nodes will
# quietly report against a stale limit.
#
# Renamed into place rather than written over, for the same reason tmux-push
# does it: a copy may be executing on the node right now, and truncating a
# running script in place is how you get a half-read one.
# ---------------------------------------------------------------------------
QUOTA_FILE       ?= /etc/quota_current.txt
QUOTA_SHARED_DIR ?= /cluster/share

.PHONY: install-quota-check quota-nodes quota-nodes-check publish-quota-file

# Just this script and its man page, without the splash.
install-quota-check:
	mkdir -p $(PREFIX) $(MANDIR)
	install -m 0755 scripts/quota_check $(PREFIX)/quota_check
	install -m 0644 man/quota_check.1 $(MANDIR)/quota_check.1
	@echo "installed quota_check to $(PREFIX)"

quota-nodes: require-root
	@for n in $(NODES); do \
	  printf '==> %s: ' "$$n"; \
	  scp -q scripts/quota_check man/quota_check.1 $(SSH_USER)@$$n:/tmp/ \
	    && ssh $(SSH_USER)@$$n \
	      'install -m 0755 /tmp/quota_check /usr/local/bin/quota_check.new \
	       && mv /usr/local/bin/quota_check.new /usr/local/bin/quota_check \
	       && install -D -m 0644 /tmp/quota_check.1 \
	            /usr/local/share/man/man1/quota_check.1 \
	       && rm -f /tmp/quota_check /tmp/quota_check.1 \
	       && /usr/local/bin/quota_check --version' \
	    || echo "FAILED"; \
	done

# Read-only and unprivileged, so anyone can run it at any time.
quota-nodes-check:
	@for n in $(NODES); do \
	  printf '%-12s ' "$$n"; \
	  ssh -o BatchMode=yes -o ConnectTimeout=5 $$n ' \
	    v=$$(quota_check --version 2>/dev/null) || v="quota_check missing"; \
	    q=none; \
	    for f in /etc/quota_current.txt $(QUOTA_SHARED_DIR)/quota_current.txt; do \
	      [ -r "$$f" ] && { q=$$f; break; }; \
	    done; \
	    echo "$$v  quotas=$$q"' 2>/dev/null \
	    || echo "unreachable"; \
	done

publish-quota-file:
	@test -r $(QUOTA_FILE) || { \
	  echo "error: $(QUOTA_FILE) not readable — run this on the head node"; exit 1; }
	install -d -m 0755 $(QUOTA_SHARED_DIR)
	install -m 0644 $(QUOTA_FILE) $(QUOTA_SHARED_DIR)/quota_current.txt.new
	mv $(QUOTA_SHARED_DIR)/quota_current.txt.new $(QUOTA_SHARED_DIR)/quota_current.txt
	@echo "published $(QUOTA_FILE) -> $(QUOTA_SHARED_DIR)/quota_current.txt"

# ---------------------------------------------------------------------------
# tmux — build the latest release from source and install to $(TMUX_PREFIX).
#
# NOTE: sinteractive no longer needs this. Since 1.0 it has zellij compiled
# into the binary and runs nothing else on the node. These targets remain for
# users who run tmux themselves; /usr/local is node-local (root fs, not
# shared), so a build has to be fanned out with `make tmux-push` to be
# available cluster-wide.
#
# Bump the version here (or `make tmux TMUX_VERSION=3.8`) — see the release
# list at https://github.com/tmux/tmux/wiki
# ---------------------------------------------------------------------------
TMUX_VERSION     ?= 3.7b
TMUX_PREFIX      ?= /usr/local
TMUX_URL          = https://github.com/tmux/tmux/releases/download/$(TMUX_VERSION)/tmux-$(TMUX_VERSION).tar.gz
TMUX_BUILD_DIR   ?= /tmp/tmux-build-$(TMUX_VERSION)
CONFIGURE_FLAGS  ?=

# Compute nodes to push the built binary to (this head/login node builds it).
# Defaults to every node Slurm knows about; override with `make tmux-push NODES="compute00 compute01"`.
NODES            ?= $(shell sinfo -hN -o '%N' 2>/dev/null | sort -u)
SSH_USER         ?= root

.PHONY: tmux-deps tmux tmux-push tmux-all require-root

# Targets that install system-wide or push to other nodes need root.
require-root:
	@test "$(UID)" = "0" || { echo "error: $(MAKECMDGOALS) must be run as root"; exit 1; }

# Build dependencies (RHEL/Rocky 9). Run once per node that compiles tmux.
tmux-deps: require-root
	dnf install -y gcc make bison libevent-devel ncurses-devel

# Download, configure, build, and install into $(TMUX_PREFIX).
tmux: require-root
	@test -f /usr/include/event2/event.h || { \
	  echo "libevent-devel headers missing — run 'make tmux-deps' first"; exit 1; }
	rm -rf $(TMUX_BUILD_DIR) && mkdir -p $(TMUX_BUILD_DIR)
	curl -LfsS $(TMUX_URL) | tar xz -C $(TMUX_BUILD_DIR) --strip-components=1
	cd $(TMUX_BUILD_DIR) && ./configure --prefix=$(TMUX_PREFIX) $(CONFIGURE_FLAGS)
	$(MAKE) -C $(TMUX_BUILD_DIR) -j$(shell nproc)
	$(MAKE) -C $(TMUX_BUILD_DIR) install
	rm -rf $(TMUX_BUILD_DIR)
	@$(TMUX_PREFIX)/bin/tmux -V

# Fan the freshly built binary out to the compute nodes. Copies to a temp name
# and renames into place so running tmux servers aren't disturbed
# ("text file busy" / clobbering a live server's inode).
tmux-push: require-root
	@test -x $(TMUX_PREFIX)/bin/tmux || { echo "build first: make tmux"; exit 1; }
	@for n in $(NODES); do \
	  printf '==> %s: ' "$$n"; \
	  scp -q $(TMUX_PREFIX)/bin/tmux $(SSH_USER)@$$n:$(TMUX_PREFIX)/bin/tmux.new \
	    && ssh $(SSH_USER)@$$n \
	      'install -m 0755 $(TMUX_PREFIX)/bin/tmux.new $(TMUX_PREFIX)/bin/tmux \
	       && rm -f $(TMUX_PREFIX)/bin/tmux.new && $(TMUX_PREFIX)/bin/tmux -V' \
	    || echo "FAILED"; \
	done

# Build here, then push to every compute node.
tmux-all: tmux tmux-push
