# Segue — see CLAUDE.md for the rules and the vault plan for the milestones.
#
#   make build       debug build of all products
#   make test        run the SegueCore tests
#   make bundle      build/Segue.app, release, ad-hoc signed (UNIVERSAL=1 for both arches)
#   make install     bundle, then copy to ~/Applications/Segue.app
#   make cold-start  measure launch → first window (budget 200 ms)
#   make run         bundle, then open the app
#   make clean

CODESIGN_IDENTITY ?= -
UNIVERSAL ?= 0
BUILD_NUMBER ?= 1
INSTALL_DIR ?= $(HOME)/Applications

export CODESIGN_IDENTITY UNIVERSAL BUILD_NUMBER

.PHONY: build test bundle install cold-start run clean

build:
	swift build

test:
	swift test

bundle:
	scripts/bundle.sh

install: bundle
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/Segue.app"
	cp -R build/Segue.app "$(INSTALL_DIR)/Segue.app"
	@echo "Installed $(INSTALL_DIR)/Segue.app"

cold-start: bundle
	scripts/cold-start.sh

run: bundle
	open build/Segue.app

clean:
	rm -rf .build build dist
