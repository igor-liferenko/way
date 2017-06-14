\let\lheader\rheader
\datethis

@s int32_t int

@* Main program.

Here we discribe the complete set of steps necessary to communicate
with the display server to display the hello world window.

@c
@<Header files@>;
@<Predeclarations of procedures@>;
@<Struct...@>;
@<Global...@>;

@ @<Global...@>=
struct wl_buffer *buffer;
struct wl_surface *surface;
struct wl_shell_surface *shell_surface;
struct wl_shm_pool *pool;
void *shm_data;

@ @c
@<Functions for shared memory@>;

int main(void)
{
    @<Setup wayland@>;
    @<Open image file@>;
    @<Initialize memory pool from image@>;
    @<Create surface@>;
    @<Bind buffer@>;

    @<Draw first image@>;
    sleep(5);
    @<Draw second image@>;
    sleep(5);

    @<Free buffer@>;
    @<Free surface@>;
    @<Free memory pool@>;
    close(image);
    @<Cleanup wayland@>;

    return EXIT_SUCCESS;
}

@ In this program we display an image as the main window.
Its geometry is hardcoded.

@<Global...@>=
static const unsigned WIDTH = 320;
static const unsigned HEIGHT = 200;

@ This image file contains the hardcoded images for this program, already in a raw format
for display: it's the pixel values for the main window.

@<Open image file@>=
int image;
image = open("images.bin", O_RDWR);
if (image < 0) {
    perror("Error opening surface image");
    return EXIT_FAILURE;
}

@ This calls the main loop with the global |display| object. The main
loop exits when the done flag is true, either because of an error, or
because the button was clicked.

@<Draw first image@>=
if (wl_display_dispatch(display) < 0)
    fprintf(stderr, "draw one error\n");

@ @<Draw second image@>=
if (wl_display_dispatch(display) < 0)
    fprintf(stderr, "draw two error\n");

@* Protocol details.

@d min(a, b) ((a) < (b) ? (a) : (b))
@d max(a, b) ((a) > (b) ? (a) : (b))

@ @<Struct...@>=
typedef uint32_t pixel_t;
struct wl_compositor *compositor;
struct wl_shell *shell;
struct wl_shm *shm;

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
wl_registry_add_listener(registry, &registry_listener, NULL);
wl_display_roundtrip(display);
wl_registry_destroy(registry);

@ |wc_display_disconnect| disconnects from wayland server.

@<Cleanup wayland@>=
wl_shell_destroy(shell);
wl_shm_destroy(shm);
wl_compositor_destroy(compositor);
wl_display_disconnect(display);

@ @<Predecl...@>=
void registry_global(void *data,
    struct wl_registry *registry, uint32_t name,
    const char *interface, uint32_t version);

@ @c
void registry_global(void *data,
    struct wl_registry *registry, uint32_t id,
    const char *interface, uint32_t version)
{
    if (strcmp(interface, "wl_compositor") == 0) {
        compositor = wl_registry_bind(registry, 
				      id, 
				      &wl_compositor_interface, 
				      1);
    } else if (strcmp(interface, "wl_shell") == 0) {
        shell = wl_registry_bind(registry, id,
                                 &wl_shell_interface, 1);
    } else if (strcmp(interface, "wl_shm") == 0) {
        shm = wl_registry_bind(registry, id,
                                 &wl_shm_interface, 1);
	wl_shm_add_listener(shm, &shm_listener, NULL);
    }
}

@ @<Struct...@>=
static void registry_global_remove(void *a,
    struct wl_registry *b, uint32_t c) { }

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove
};

struct wl_shm_listener shm_listener = {
	shm_format
};

struct pool_data {
    int fd;
    pixel_t *memory;
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
    int size = WIDTH*HEIGHT*sizeof(pixel_t);
    int fd;
    struct wl_buffer *buff;

    fd = os_create_anonymous_file(size);
    if (fd < 0) {
	fprintf(stderr, "creating a buffer file for %d B failed: %m\n",
		size);
	exit(1);
    }
    
    shm_data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (shm_data == MAP_FAILED) {
	fprintf(stderr, "mmap failed: %m\n");
	close(fd);
	exit(1);
    }

    pool = wl_shm_create_pool(shm, fd, size);

@ @<Free memory pool@>=
//munmap(memory, capacity);

@ @<Struct...@>=
static const uint32_t PIXEL_FORMAT_ID = WL_SHM_FORMAT_ARGB8888;

@ The buffer object has the contents of a surface. Buffers are created inside of a
memory pool (they are memory pool slices), so that they are shared by the client and
the server. In our example, we do not create an empty buffer, instead we rely on the
fact that the memory pool was previously filled with data and just pass the image
dimensions as a parameter.

@ @<Free buffer@>=
//wl_buffer_destroy(buffer);

@ Objects representing visible elements are called surfaces. Surfaces are rectangular
areas, having position and size. Surface contents are filled by using buffer objects.
During the lifetime of a surface, a couple of buffers will be attached as the surface
contents and the server will be requested to redraw the surfaces. In this program, the
surface object is of type |wl_shell_surface|, which is used for creating top level windows.

@<Create surface@>=
surface = wl_compositor_create_surface(compositor);
shell_surface = wl_shell_get_shell_surface(shell, surface);

    /*|wl_shell_surface_set_user_data(shell_surface, surface);|*/
    /*|wl_surface_set_user_data(surface, NULL);|*/

@ @<Free surface@>=
//wl_shell_surface_destroy(shell_surface);
//wl_surface_destroy(surface);

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
buffer = wl_shm_pool_create_buffer(pool,
  0, WIDTH, HEIGHT,
  WIDTH*sizeof(pixel_t), WL_SHM_FORMAT_ARGB8888);
//wl_shm_pool_destroy(pool);

/*|surface = wl_shell_surface_get_user_data(shell_surface);|*/

wl_shell_surface_set_toplevel(shell_surface);

wl_surface_attach(surface, buffer, 0, 0);
wl_surface_commit(surface);

@ {\tt\catcode`_11 https://jan.newmarch.name/Wayland/SharedMemory/#heading_toc_j_2}

@<Functions for shared memory@>=
static int
set_cloexec_or_close(int fd)
{
        long flags;

        if (fd == -1)
                return -1;

        flags = fcntl(fd, F_GETFD);
        if (flags == -1)
                goto err;

        if (fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == -1)
                goto err;

        return fd;

err:
        close(fd);
        return -1;
}

static int
create_tmpfile_cloexec(char *tmpname)
{
        int fd;

#ifdef HAVE_MKOSTEMP
        fd = mkostemp(tmpname, O_CLOEXEC);
        if (fd >= 0)
                unlink(tmpname);
#else
        fd = mkstemp(tmpname);
        if (fd >= 0) {
                fd = set_cloexec_or_close(fd);
                unlink(tmpname);
        }
#endif

        return fd;
}

/*
 * Create a new, unique, anonymous file of the given size, and
 * return the file descriptor for it. The file descriptor is set
 * CLOEXEC. The file is immediately suitable for mmap()'ing
 * the given size at offset zero.
 *
 * The file should not have a permanent backing store like a disk,
 * but may have if XDG_RUNTIME_DIR is not properly implemented in OS.
 *
 * The file name is deleted from the file system.
 *
 * The file is suitable for buffer sharing between processes by
 * transmitting the file descriptor over Unix sockets using the
 * SCM_RIGHTS methods.
 */
int
os_create_anonymous_file(off_t size)
{
        static const char template[] = "/weston-shared-XXXXXX";
        const char *path;
        char *name;
        int fd;

        path = getenv("XDG_RUNTIME_DIR");
        if (!path) {
                errno = ENOENT;
                return -1;
        }

        name = malloc(strlen(path) + sizeof(template));
        if (!name)
                return -1;
        strcpy(name, path);
        strcat(name, template);

        fd = create_tmpfile_cloexec(name);

        free(name);

        if (fd < 0)
                return -1;

        if (ftruncate(fd, size) < 0) {
                close(fd);
                return -1;
        }

        return fd;
}

@ @<Predecl...@>=
void
shm_format(void *data, struct wl_shm *wl_shm, uint32_t format);
@ @c
void
shm_format(void *data, struct wl_shm *wl_shm, uint32_t format)
{
    //struct display *d = data;

    //	d->formats |= (1 << format);
/*|    fprintf(stderr, "Format %d\n", format); |*/
}

@ @<Head...@>=
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <wayland-client.h>
#include <errno.h>

@* Index.
