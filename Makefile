.PHONY: test lint clean

EMACS ?= emacs

# Detect straight.el build directory (Doom Emacs)
EMACS_VERSION := $(shell $(EMACS) --batch --eval '(princ emacs-version)' 2>/dev/null)
STRAIGHT_DIR ?= $(HOME)/.emacs.d/.local/straight/build-$(EMACS_VERSION)

# If cask is available, use it; otherwise use straight.el load paths
CASK := $(shell command -v cask 2>/dev/null)

ifdef CASK
  EMACS_CMD = $(CASK) exec $(EMACS)
  CASK_LOAD =
else ifneq ($(wildcard $(STRAIGHT_DIR)/buttercup),)
  EMACS_CMD = $(EMACS)
  CASK_LOAD = -L $(STRAIGHT_DIR)/buttercup \
	-L $(STRAIGHT_DIR)/org-roam \
	-L $(STRAIGHT_DIR)/emacsql \
	-L $(STRAIGHT_DIR)/emacsql-sqlite \
	-L $(STRAIGHT_DIR)/magit-section \
	-L $(STRAIGHT_DIR)/dash \
	-L $(STRAIGHT_DIR)/s \
	-L $(STRAIGHT_DIR)/f \
	-L $(STRAIGHT_DIR)/compat \
	-L $(STRAIGHT_DIR)/org \
	-L $(STRAIGHT_DIR)/transient \
	-L $(STRAIGHT_DIR)/with-editor \
	-L $(STRAIGHT_DIR)/llama \
	-L $(STRAIGHT_DIR)/cond-let
else
  $(error No test runner found. Install Cask or ensure straight.el packages are built)
endif

test:
	$(EMACS_CMD) --batch -L . -L test $(CASK_LOAD) \
		-l buttercup \
		-l test-helper \
		-l test-endless-org-roam-compat \
		-l test-endless-org-roam \
		-l test-endless-org-roam-registry \
		-l test-endless-org-roam-link \
		-l test-endless-org-roam-transport \
		-l test-endless-org-roam-search \
		-f buttercup-run

lint:
	$(EMACS_CMD) --batch -L . $(CASK_LOAD) \
		--eval '(setq byte-compile-error-on-warn t)' \
		-f batch-byte-compile \
		endless-org-roam.el \
		endless-org-roam-registry.el \
		endless-org-roam-link.el \
		endless-org-roam-search.el \
		endless-org-roam-transport.el \
		endless-org-roam-compat.el

clean:
	rm -rf .cask/ *.elc
