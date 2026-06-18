.PHONY: run run-dry build tidy clean test

run:
	go run ./cmd/tui

# Like `run` but won't actually send /exit or any keys to tmux.
# Use this to exercise the UI without disturbing live Claude sessions.
run-dry:
	go run ./cmd/tui --dry-run

build:
	go build -o necromancer-tui ./cmd/tui

tidy:
	go mod tidy

test:
	go test ./...

clean:
	rm -f necromancer-tui
