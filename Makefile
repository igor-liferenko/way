WAYLAND=`pkg-config wayland-client --cflags --libs`
CFLAGS?=-std=c11 -Wall -Werror -O3 -fvisibility=hidden

way: way.c images.bin
	gcc -o $@ $< $(WAYLAND) -lrt
