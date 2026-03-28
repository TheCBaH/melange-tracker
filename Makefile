default:
	opam exec -- dune build

clean:
	opam exec -- dune $@

format:
	opam exec -- dune fmt

utop:
	opam exec -- dune utop

# Tracker CLI
tracker = opam exec -- dune exec tracker/bin/main.exe --

tracker-status:
	$(tracker) status

tracker-queue:
	$(tracker) queue

tracker-report:
	$(tracker) report

tracker-verify:
	$(tracker) verify

tracker-scan:
	$(tracker) scan

# Melange build verification
melange-setup:
	git submodule update --init --recursive --depth 1
	cd melange && git remote add upstream https://github.com/rescript-lang/rescript.git || true
	cd melange && git fetch upstream

melange-build:
	cd melange && opam exec -- dune build

melange-test:
	cd melange && opam exec -- dune runtest

opam-install-test:
	opam install . --deps-only --with-test --yes

.PHONY: default clean format utop
.PHONY: tracker-status tracker-queue tracker-report tracker-verify tracker-scan
.PHONY: melange-setup melange-build melange-test opam-install-test
