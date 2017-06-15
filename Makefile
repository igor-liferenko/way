way: way.c
	gcc -o $@ $< `pkg-config wayland-client --cflags --libs`
