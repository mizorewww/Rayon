# Rayon build entry. Run `make` for the list of targets.

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

CONFIGURATION ?= Debug
# Build products stay out of the source tree's top level; .build/ is ignored.
DERIVED_DATA ?= $(CURDIR)/.build/DerivedData
export DERIVED_DATA_PATH := $(DERIVED_DATA)

WORKSPACE := App.xcworkspace
TEST_PACKAGES := $(patsubst %/Tests,%,$(wildcard Foundation/*/Tests))
RESOLVED_PACKAGES := $(patsubst %/Package.resolved,%,$(wildcard Foundation/*/Package.resolved))

.PHONY: help build build-macos build-ios test test-telemetry-server resolve scan-license sync-libraries check-localization sync-localization clean

help:
	@echo "build         Build the Mac and iOS apps"
	@echo "build-macos   Build the Mac app, signed with your Apple Development certificate or ad hoc"
	@echo "build-ios     Build the iOS app for the simulator, signed ad hoc so the keychain works"
	@echo "test          Run the Swift package tests: $(notdir $(TEST_PACKAGES))"
	@echo "test-telemetry-server  Typecheck and test the telemetry Worker in Server/Telemetry (needs bun)"
	@echo "resolve       Resolve the workspace's and the packages' dependencies"
	@echo "scan-license  List the resolved dependencies; fail on any missing from Resources/LICENSE,"
	@echo "              or when Resources/Libraries.json is out of date with it"
	@echo "sync-libraries  Write Resources/Libraries.json, the About pages' libraries, from Resources/LICENSE"
	@echo "check-localization  Fail on keys missing from a String Catalog, stale keys, missing translations"
	@echo "                    and format mismatches; the build in DERIVED_DATA says which keys the code uses"
	@echo "sync-localization   Add the keys the code uses to the String Catalogs, drop stale ones (after make build)"
	@echo "clean         Remove .build/ here and in every package"
	@echo
	@echo "CONFIGURATION=Debug|Release (default Debug), DERIVED_DATA=<dir> (default .build/DerivedData)"
	@echo "Install and release: Workflow/Scripts/install.sh, release.sh, testflight.sh"

build: build-macos build-ios

build-macos:
	bash Workflow/Scripts/build-macos.sh $(CONFIGURATION)

# Signed ad hoc, not unsigned: without its entitlements the app has no
# application-identifier and the keychain refuses to save any secret.
build-ios:
	xcodebuild -quiet \
		-workspace $(WORKSPACE) \
		-scheme Rayon \
		-configuration $(CONFIGURATION) \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath "$(DERIVED_DATA)" \
		COMPILER_INDEX_STORE_ENABLE=NO \
		CODE_SIGN_IDENTITY=- \
		build

test:
	for package in $(TEST_PACKAGES); do \
		echo "==> $$package"; \
		swift test --package-path "$$package" || exit 1; \
	done

# Not part of `test`: it needs bun and downloads wrangler and workerd.
test-telemetry-server:
	cd Server/Telemetry && bun install --frozen-lockfile && bun run typecheck && bun run test

resolve:
	xcodebuild -resolvePackageDependencies -workspace $(WORKSPACE) -scheme Rayon
	for package in $(RESOLVED_PACKAGES); do swift package --package-path "$$package" resolve || exit 1; done

scan-license:
	bash Workflow/Scripts/scan-license.sh

sync-libraries:
	/usr/bin/python3 Workflow/Scripts/libraries.py sync

check-localization:
	/usr/bin/python3 Workflow/Scripts/localization.py check

sync-localization:
	/usr/bin/python3 Workflow/Scripts/localization.py sync

clean:
	rm -rf .build Foundation/*/.build
