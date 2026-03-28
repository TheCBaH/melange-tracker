default:
	opam exec -- dune build

clean:
	opam exec -- dune $@

format:
	opam exec -- dune fmt

utop:
	opam exec -- dune utop

.PHONY: default clean format utop
