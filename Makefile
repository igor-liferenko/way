ifeq ($(MAKECMDGOALS),)
all:
	@echo NoOp
else
way: way.c
	clang -o $@ $< -lwayland-client
endif
