way: way.c
	$(CC) -o $@ $< -lwayland-client
