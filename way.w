@ @c
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <wayland-client.h>

@<Header files@>;
@<Struct...@>;

static const unsigned WIDTH = 320;
static const unsigned HEIGHT = 200;
static const unsigned CURSOR_WIDTH = 100;
static const unsigned CURSOR_HEIGHT = 59;
static const int32_t CURSOR_HOT_SPOT_X = 10;
static const int32_t CURSOR_HOT_SPOT_Y = 35;

static bool done = false;

void on_button(uint32_t button)
{
    done = true;
}

int main(void)
{
    struct wl_buffer *buffer;
    struct wl_shm_pool *pool;
    struct wl_shell_surface *surface;
    int image;

    hello_setup_wayland();

    image = open("images.bin", O_RDWR);

    if (image < 0) {
        perror("Error opening surface image");
        return EXIT_FAILURE;
    }

    pool = hello_create_memory_pool(image);
    surface = hello_create_surface();
    buffer = hello_create_buffer(pool, WIDTH, HEIGHT);
    hello_bind_buffer(buffer, surface);
    hello_set_cursor_from_pool(pool, CURSOR_WIDTH,
        CURSOR_HEIGHT, CURSOR_HOT_SPOT_X, CURSOR_HOT_SPOT_Y);
    hello_set_button_callback(surface, on_button);

    while (!done) {
        if (wl_display_dispatch(display) < 0) {
            perror("Main loop error");
            done = true;
        }
    }

    fprintf(stderr, "Exiting sample wayland client...\n");

    hello_free_cursor();
    hello_free_buffer(buffer);
    hello_free_surface(surface);
    hello_free_memory_pool(pool);
    close(image);
    hello_cleanup_wayland();

    return EXIT_SUCCESS;
}

@ @d min(a, b) ((a) < (b) ? (a) : (b))
@d max(a, b) ((a) > (b) ? (a) : (b))

@<Head...@>=
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>

@ @<Struct...@>=
typedef uint32_t pixel;
struct wl_compositor *compositor;
struct wl_display *display;
struct wl_pointer *pointer;
struct wl_seat *seat;
struct wl_shell *shell;
struct wl_shm *shm;

static const struct wl_registry_listener registry_listener;
static const struct wl_pointer_listener pointer_listener;

@ @<Head...@>=
void hello_setup_wayland(void);
@ @c
void hello_setup_wayland(void)
{
    struct wl_registry *registry;

    display = wl_display_connect(NULL);
    if (display == NULL) {
        perror("Error opening display");
        exit(EXIT_FAILURE);
    }

    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener,
        NULL);
    wl_display_roundtrip(display);
    wl_registry_destroy(registry);
}

@ @<Head...@>=
void hello_cleanup_wayland(void);
@ @c
void hello_cleanup_wayland(void)
{
    wl_pointer_destroy(pointer);
    wl_seat_destroy(seat);
    wl_shell_destroy(shell);
    wl_shm_destroy(shm);
    wl_compositor_destroy(compositor);
    wl_display_disconnect(display);
}

@ @<Head...@>=
static void registry_global(void *data,
    struct wl_registry *registry, uint32_t name,
    const char *interface, uint32_t version);
@ @c
static void registry_global(void *data,
    struct wl_registry *registry, uint32_t name,
    const char *interface, uint32_t version)
{
    if (strcmp(interface, wl_compositor_interface.name) == 0)
        compositor = wl_registry_bind(registry, name,
            &wl_compositor_interface, min(version, 4));
    else if (strcmp(interface, wl_shm_interface.name) == 0)
        shm = wl_registry_bind(registry, name,
            &wl_shm_interface, min(version, 1));
    else if (strcmp(interface, wl_shell_interface.name) == 0)
        shell = wl_registry_bind(registry, name,
            &wl_shell_interface, min(version, 1));
    else if (strcmp(interface, wl_seat_interface.name) == 0) {
        seat = wl_registry_bind(registry, name,
            &wl_seat_interface, min(version, 2));
        pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(pointer, &pointer_listener,
            NULL);
    }
}

@ @<Struct...@>=
static void registry_global_remove(void *a,
    struct wl_registry *b, uint32_t c) { }

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove
};

struct pool_data {
    int fd;
    pixel *memory;
    unsigned capacity;
    unsigned size;
};

@ @<Head...@>=
struct wl_shm_pool *hello_create_memory_pool(int file);
@ @c
struct wl_shm_pool *hello_create_memory_pool(int file)
{
    struct pool_data *data;
    struct wl_shm_pool *pool;
    struct stat stat;

    if (fstat(file, &stat) != 0)
        return NULL;

    data = malloc(sizeof(struct pool_data));

    if (data == NULL)
        return NULL;

    data->capacity = stat.st_size;
    data->size = 0;
    data->fd = file;

    data->memory = mmap(0, data->capacity,
        PROT_READ, MAP_SHARED, data->fd, 0);

    if (data->memory == MAP_FAILED)
        goto cleanup_alloc;

    pool = wl_shm_create_pool(shm, data->fd, data->capacity);

    if (pool == NULL)
        goto cleanup_mmap;

    wl_shm_pool_set_user_data(pool, data);

    return pool;

cleanup_mmap:
    munmap(data->memory, data->capacity);
cleanup_alloc:
    free(data);
    return NULL;
}

@ @<Head...@>=
void hello_free_memory_pool(struct wl_shm_pool *pool);
@ @c
void hello_free_memory_pool(struct wl_shm_pool *pool)
{
    struct pool_data *data;

    data = wl_shm_pool_get_user_data(pool);
    wl_shm_pool_destroy(pool);
    munmap(data->memory, data->capacity);
    free(data);
}

@ @<Struct...@>=
static const uint32_t PIXEL_FORMAT_ID = WL_SHM_FORMAT_ARGB8888;

@ @<Head...@>=
struct wl_buffer *hello_create_buffer(struct wl_shm_pool *pool,
    unsigned width, unsigned height);
@ @c
struct wl_buffer *hello_create_buffer(struct wl_shm_pool *pool,
    unsigned width, unsigned height)
{
    struct pool_data *pool_data;
    struct wl_buffer *buffer;

    pool_data = wl_shm_pool_get_user_data(pool);
    buffer = wl_shm_pool_create_buffer(pool,
        pool_data->size, width, height,
        width*sizeof(pixel), PIXEL_FORMAT_ID);

    if (buffer == NULL)
        return NULL;

    pool_data->size += width*height*sizeof(pixel);

    return buffer;
}

@ @<Head...@>=
void hello_free_buffer(struct wl_buffer *buffer);
@ @c
void hello_free_buffer(struct wl_buffer *buffer)
{
    wl_buffer_destroy(buffer);
}

@ @<Head...@>=
static void shell_surface_ping(void *data,
    struct wl_shell_surface *shell_surface, uint32_t serial);
@ @c
static void shell_surface_ping(void *data,
    struct wl_shell_surface *shell_surface, uint32_t serial)
{
    wl_shell_surface_pong(shell_surface, serial);
}

@ @<Head...@>=
static void shell_surface_configure(void *data,
    struct wl_shell_surface *shell_surface,
    uint32_t edges, int32_t width, int32_t height) { }

@ @<Struct...@>=
static const struct wl_shell_surface_listener
    shell_surface_listener = {
    .ping = shell_surface_ping,
    .configure = shell_surface_configure,
};

@ @<Head...@>=
struct wl_shell_surface *hello_create_surface(void);
@ @c
struct wl_shell_surface *hello_create_surface(void)
{
    struct wl_surface *surface;
    struct wl_shell_surface *shell_surface;

    surface = wl_compositor_create_surface(compositor);

    if (surface == NULL)
        return NULL;

    shell_surface = wl_shell_get_shell_surface(shell, surface);

    if (shell_surface == NULL) {
        wl_surface_destroy(surface);
        return NULL;
    }

    wl_shell_surface_add_listener(shell_surface,
        &shell_surface_listener, 0);
    wl_shell_surface_set_toplevel(shell_surface);
    wl_shell_surface_set_user_data(shell_surface, surface);
    wl_surface_set_user_data(surface, NULL);

    return shell_surface;
}

@ @<Head...@>=
void hello_free_surface(struct wl_shell_surface *shell_surface);
@ @c
void hello_free_surface(struct wl_shell_surface *shell_surface)
{
    struct wl_surface *surface;

    surface = wl_shell_surface_get_user_data(shell_surface);
    wl_shell_surface_destroy(shell_surface);
    wl_surface_destroy(surface);
}

@ @<Head...@>=
void hello_bind_buffer(struct wl_buffer *buffer,
    struct wl_shell_surface *shell_surface);
@ @c
void hello_bind_buffer(struct wl_buffer *buffer,
    struct wl_shell_surface *shell_surface)
{
    struct wl_surface *surface;

    surface = wl_shell_surface_get_user_data(shell_surface);
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_commit(surface);
}

@ @<Head...@>=
void hello_set_button_callback(
    struct wl_shell_surface *shell_surface,
    void (*callback)(uint32_t));
@ @c
void hello_set_button_callback(
    struct wl_shell_surface *shell_surface,
    void (*callback)(uint32_t))
{
    struct wl_surface* surface;

    surface = wl_shell_surface_get_user_data(shell_surface);
    wl_surface_set_user_data(surface, callback);
}

@ @<Structures@>=
struct pointer_data {
    struct wl_surface *surface;
    struct wl_buffer *buffer;
    int32_t hot_spot_x;
    int32_t hot_spot_y;
    struct wl_surface *target_surface;
};

@ @<Head...@>=
void hello_set_cursor_from_pool(struct wl_shm_pool *pool,
    unsigned width, unsigned height,
    int32_t hot_spot_x, int32_t hot_spot_y);
@ @c
void hello_set_cursor_from_pool(struct wl_shm_pool *pool,
    unsigned width, unsigned height,
    int32_t hot_spot_x, int32_t hot_spot_y)
{
    struct pointer_data *data;

    data = malloc(sizeof(struct pointer_data));

    if (data == NULL)
        goto error;

    data->hot_spot_x = hot_spot_x;
    data->hot_spot_y = hot_spot_y;
    data->surface = wl_compositor_create_surface(compositor);

    if (data->surface == NULL)
        goto cleanup_alloc;

    data->buffer = hello_create_buffer(pool, width, height);

    if (data->buffer == NULL)
        goto cleanup_surface;

    wl_pointer_set_user_data(pointer, data);

    return;

cleanup_surface:
    wl_surface_destroy(data->surface);
cleanup_alloc:
    free(data);
error:
    perror("Unable to allocate cursor");
}

@ @<Head...@>=
void hello_free_cursor(void);
@ @c
void hello_free_cursor(void)
{
    struct pointer_data *data;

    data = wl_pointer_get_user_data(pointer);
    wl_buffer_destroy(data->buffer);
    wl_surface_destroy(data->surface);
    free(data);
    wl_pointer_set_user_data(pointer, NULL);
}

@ @<Head...@>=
static void pointer_enter(void *data,
    struct wl_pointer *wl_pointer,
    uint32_t serial, struct wl_surface *surface,
    wl_fixed_t surface_x, wl_fixed_t surface_y);
@ @c
static void pointer_enter(void *data,
    struct wl_pointer *wl_pointer,
    uint32_t serial, struct wl_surface *surface,
    wl_fixed_t surface_x, wl_fixed_t surface_y)
{
    struct pointer_data *pointer_data;

    pointer_data = wl_pointer_get_user_data(wl_pointer);
    pointer_data->target_surface = surface;
    wl_surface_attach(pointer_data->surface,
        pointer_data->buffer, 0, 0);
    wl_surface_commit(pointer_data->surface);
    wl_pointer_set_cursor(wl_pointer, serial,
        pointer_data->surface, pointer_data->hot_spot_x,
        pointer_data->hot_spot_y);
}

@ @<Head...@>=
static void pointer_leave(void *data,
    struct wl_pointer *wl_pointer, uint32_t serial,
    struct wl_surface *wl_surface) { }

static void pointer_motion(void *data,
    struct wl_pointer *wl_pointer, uint32_t time,
    wl_fixed_t surface_x, wl_fixed_t surface_y) { }

@ @<Head...@>=
static void pointer_button(void *data,
    struct wl_pointer *wl_pointer, uint32_t serial,
    uint32_t time, uint32_t button, uint32_t state);
@ @c
static void pointer_button(void *data,
    struct wl_pointer *wl_pointer, uint32_t serial,
    uint32_t time, uint32_t button, uint32_t state)
{
    struct pointer_data *pointer_data;
    void (*callback)(uint32_t);

    pointer_data = wl_pointer_get_user_data(wl_pointer);
    callback = wl_surface_get_user_data(
        pointer_data->target_surface);
    if (callback != NULL)
        callback(button);
}

@ @<Head...@>=
static void pointer_axis(void *data,
    struct wl_pointer *wl_pointer, uint32_t time,
    uint32_t axis, wl_fixed_t value) { }

@ @<Struct...@>=
static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter,
    .leave = pointer_leave,
    .motion = pointer_motion,
    .button = pointer_button,
    .axis = pointer_axis
};
