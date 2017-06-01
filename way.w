\let\lheader\rheader
\datethis

@s int32_t int

@* Main program.

Here we discribe the complete set of steps necessary to communicate
with the display server to display the hello world window and accept
input from the pointer device, closing the application when clicked.

@c
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <wayland-client.h>

@<Header files@>;
@<Global...@>;
@<Struct...@>;

@<Set callback function for mouse click@>;

int main(void)
{
    struct wl_buffer *buffer;
    struct wl_surface *surface;
    struct wl_shm_pool *pool;
    struct pool_data *data_of_pool;
    struct pointer_data *data_of_pointer;
    struct wl_shell_surface *shell_surface;

    int image;

    @<Setup wayland@>;

    @<Open image file@>;

    @<Initialize memory pool from image@>;
    @<Create surface@>;
    buffer = hello_create_buffer(pool, WIDTH, HEIGHT);
    @<Bind buffer@>;
    @<Set cursor from pool@>;
    @<Set button callback@>;

    @<Main loop@>;

    fprintf(stderr, "Exiting sample wayland client...\n");

    @<Free cursor@>;
    @<Free buffer@>;
    @<Free surface@>;
    @<Free memory pool@>;
    close(image);
    @<Cleanup wayland@>;

    return EXIT_SUCCESS;
}

@ In this program we display an image as the main window and another for the cursor.
Their geometry is hardcoded. In a more general application, though, the values would
be dynamically calculated.

@<Global...@>=
static const unsigned WIDTH = 320;
static const unsigned HEIGHT = 200;
static const unsigned CURSOR_WIDTH = 100;
static const unsigned CURSOR_HEIGHT = 59;
static const int32_t CURSOR_HOT_SPOT_X = 10;
static const int32_t CURSOR_HOT_SPOT_Y = 35;

@ @<Global...@>=
static bool done = false;

@ This is the button callback. Whenever a button is clicked, we set the done
flag to true, which will allow us to leave the event loop in the |main| function.

@<Set callback function for mouse click@>=
void on_button(uint32_t button)
{
    done = true;
}

@ This image file contains the hardcoded images for this program, already in a raw format
for display: it's the pixel values for the main window, followed by the pixel values
for the cursor.

@<Open image file@>=
image = open("images.bin", O_RDWR);
if (image < 0) {
    perror("Error opening surface image");
    return EXIT_FAILURE;
}

@ This calls the main loop with the global |display| object. The main
loop exits when the done flag is true, either because of an error, or
because the button was clicked.

@<Main loop@>=
while (!done) {
    if (wl_display_dispatch(display) < 0) {
        perror("Main loop error");
        done = true;
    }
}

@* Protocol details.

@d min(a, b) ((a) < (b) ? (a) : (b))
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
struct wl_pointer *pointer;
struct wl_seat *seat;
struct wl_shell *shell;
struct wl_shm *shm;

static const struct wl_registry_listener registry_listener;
static const struct wl_pointer_listener pointer_listener;

@ The |display| object is the most important. It represents the connection
to the display server and is
used for sending requests and receiving events. It is used in the code for
running the main loop.

@<Global variables@>=
struct wl_display *display;

@ |wl_display_connect| connects to wayland server.

The server has control of a number of objects. In Wayland, these are quite
high-level, such as a DRM manager, a compositor, a text input manager and so on.
These objects are accessible through a {\sl registry}.

We begin the application by connecting to the display server and requesting a
collection of global objects from the server, filling in proxy variables representing them.

@<Setup wayland@>=
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

@ |wc_display_disconnect| disconnects from wayland server.

@<Cleanup wayland@>=
wl_pointer_destroy(pointer);
wl_seat_destroy(seat);
wl_shell_destroy(shell);
wl_shm_destroy(shm);
wl_compositor_destroy(compositor);
wl_display_disconnect(display);

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

@ A main design philosophy of wayland is efficiency when dealing with graphics. Wayland
accomplishes that by sharing memory areas between the client applications and the display
server, so that no copies are involved. The essential element that is shared between client
and server is called a shared memory pool, which is simply a memory area mmapped in both
client and servers. Inside a memory pool, a set of images can be appended as buffer objects
and all will be shared both by client and server.

In this program we |mmap| our hardcoded image file. In a typical application, however, an
empty memory pool would be created, for example, by creating a shared memory object with
|shm_open|, then gradually filled with dynamically constructed image buffers representing
the widgets. While writing this program, the author had to decide if he would create an
empty memory pool and allocate buffers inside it, which is more usual and simpler to
understand, or if he would use a less intuitive example of creating a pre built memory
pool. He decided to go with the less intuitive example for an important reason: if you
read the whole program, you'll notice that there's no memory copy operation anywhere. The
image file is open once, and |mmap|ped once. No extra copy is required. This was done to
make clear that a wayland application can have maximal efficiency if carefully implemented.

@<Initialize memory...@>=
struct stat stat;

if (fstat(image, &stat) != 0)
  pool = NULL;
else {
  data_of_pool = malloc(sizeof(struct pool_data));
  if (data_of_pool == NULL)
      pool = NULL;
  else {
    data_of_pool->capacity = stat.st_size;
    data_of_pool->size = 0;
    data_of_pool->fd = image;

    data_of_pool->memory = mmap(0, data_of_pool->capacity,
        PROT_READ, MAP_SHARED, data_of_pool->fd, 0);

    if (data_of_pool->memory == MAP_FAILED) {
      free(data_of_pool);
      pool = NULL;
    }
    else {
      pool = wl_shm_create_pool(shm, data_of_pool->fd, data_of_pool->capacity);

      if (pool == NULL) {
          munmap(data_of_pool->memory, data_of_pool->capacity);
          free(data_of_pool);
          pool = NULL;
      }
      else
        wl_shm_pool_set_user_data(pool, data_of_pool);
    }
  }
}

@ @<Free memory pool@>=
data_of_pool = wl_shm_pool_get_user_data(pool);
wl_shm_pool_destroy(pool);
munmap(data_of_pool->memory, data_of_pool->capacity);
free(data_of_pool);

@ @<Struct...@>=
static const uint32_t PIXEL_FORMAT_ID = WL_SHM_FORMAT_ARGB8888;

@ The buffer object has the contents of a surface. Buffers are created inside of a
memory pool (they are memory pool slices), so that they are shared by the client and
the server. In our example, we do not create an empty buffer, instead we rely on the
fact that the memory pool was previously filled with data and just pass the image
dimensions as a parameter.

@<Head...@>=
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

@ @<Free buffer@>=
wl_buffer_destroy(buffer);

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

@ Objects representing visible elements are called surfaces. Surfaces are rectangular
areas, having position and size. Surface contents are filled by using buffer objects.
During the lifetime of a surface, a couple of buffers will be attached as the surface
contents and the server will be requested to redraw the surfaces. In this program, the
surface object is of type |wl_shell_surface|, which is used for creating top level windows.

@<Create surface@>=
surface = wl_compositor_create_surface(compositor);
if (surface == NULL) shell_surface = NULL;
else {
  shell_surface = wl_shell_get_shell_surface(shell, surface);

  if (shell_surface == NULL)
    wl_surface_destroy(surface);
  else {
    wl_shell_surface_add_listener(shell_surface,
        &shell_surface_listener, 0);
    wl_shell_surface_set_toplevel(shell_surface);
    wl_shell_surface_set_user_data(shell_surface, surface);
    wl_surface_set_user_data(surface, NULL);
  }
}

@ @<Free surface@>=
surface = wl_shell_surface_get_user_data(shell_surface);
wl_shell_surface_destroy(shell_surface);
wl_surface_destroy(surface);

@ To make the buffer visible we need to bind buffer data to a surface, that is, we
set the surface contents to the buffer data. The bind operation also commits the
surface to the server. In wayland there's an idea of surface ownership: either the client
owns the surface, so that it can be drawn (and the server keeps an old copy of it), or
the server owns the surface, when the client can't change it because the server is
drawing it on the screen. For transfering the ownership to the server, there's the
commit request and for sending the ownership back to the client, the server sends a
release event. In a generic application, the surface will be moved back and forth, but
in this program it's enough to commit only once, as part of the bind operation.

@<Bind buffer@>=
surface = wl_shell_surface_get_user_data(shell_surface);
wl_surface_attach(surface, buffer, 0, 0);
wl_surface_commit(surface);

@ Set up a callback: associate a surface click with the |on_button| callback.

@<Set button callback@>=
surface = wl_shell_surface_get_user_data(shell_surface);
wl_surface_set_user_data(surface, on_button);

@ @<Structures@>=
struct pointer_data {
    struct wl_surface *surface;
    struct wl_buffer *buffer;
    int32_t hot_spot_x;
    int32_t hot_spot_y;
    struct wl_surface *target_surface;
};

@ After setting up the main window, we configure the cursor. This configuration is required:
the client must configure the cursor. Here we set the cursor to be the preset contents
of the memory pool (implicitly right after the main window buffer). The helper module
then creates a surface and a buffer for the cursor. I had to decide if I would hide the
cursor configuration in the helper module or if I would explicitly add a high level step
for it. I dedided to go with the second one to show the division of roles in wayland: the
client is given a large control over what and how to draw.

@<Set cursor from pool@>=
data_of_pointer = malloc(sizeof(struct pointer_data));

if (data_of_pointer == NULL)
  fprintf(stderr,"Unable to allocate cursor\n");
else {
  data_of_pointer->hot_spot_x = CURSOR_HOT_SPOT_X;
  data_of_pointer->hot_spot_y = CURSOR_HOT_SPOT_Y;
  data_of_pointer->surface = wl_compositor_create_surface(compositor);

  if (data_of_pointer->surface == NULL) {
    free(data_of_pointer);
    fprintf(stderr,"Unable to allocate cursor\n");    
  }
  else {
    data_of_pointer->buffer = hello_create_buffer(pool, CURSOR_WIDTH, CURSOR_HEIGHT);

    if (data_of_pointer->buffer == NULL) {
      wl_surface_destroy(data_of_pointer->surface);
      free(data_of_pointer);
      fprintf(stderr, "Unable to allocate cursor\n");
    }
    else
      wl_pointer_set_user_data(pointer, data_of_pointer);
  }
}

@ @<Free cursor@>=
data_of_pointer = wl_pointer_get_user_data(pointer);
wl_buffer_destroy(data_of_pointer->buffer);
wl_surface_destroy(data_of_pointer->surface);
free(data_of_pointer);
wl_pointer_set_user_data(pointer, NULL);

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

@* Index.
