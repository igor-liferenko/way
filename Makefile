all:
	@echo NoOp

way: way.c
	clang -o $@ $< -lwayland-client
