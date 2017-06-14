WAYLAND=`pkg-config wayland-client --cflags --libs`
CFLAGS?=-std=c11 -Wall -Werror -O3 -fvisibility=hidden

way: way.c images.bin
	gcc -o $@ $< $(WAYLAND) -lrt

images.bin: images/convert.py images/window.png images/window2.png
	images/convert.py
	mv window.bin images.bin
