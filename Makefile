all:
	gcc -o surface surface.c -lwayland-client
	gcc -o damage damage.c -lwayland-client
	gcc -o wayland-input wayland-input.c -lwayland-client -lwayland-egl -lEGL -lGL -lxkbcommon
	gcc -o wayland-shm wayland-shm.c -lwayland-client
