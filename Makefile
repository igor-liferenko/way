all:
	gcc -o surface surface.c -lwayland-client
	gcc -o damage damage.c -lwayland-client
