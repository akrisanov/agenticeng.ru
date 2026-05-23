ZOLA_VERSION := 0.22.1
ZOLA         := zola

.PHONY: build serve check clean install-zola

## build: generate the static site into ./public
build:
	$(ZOLA) build

## serve: start a local dev server with live-reload (http://127.0.0.1:1111)
serve:
	$(ZOLA) serve

## check: validate config, templates and links
check:
	$(ZOLA) check

## clean: remove the generated ./public directory
clean:
	rm -rf public

## install-zola: install Zola via Homebrew (macOS)
install-zola:
	brew install zola

## help: show this help message
help:
	@grep -E '^## ' Makefile | sed 's/## //'
