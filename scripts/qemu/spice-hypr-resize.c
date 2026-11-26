/* Follow a single virtio display in a FreeBSD Hyprland session. */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include <xf86drmMode.h>
#include <spice/vd_agent.h>
#include <sys/endian.h>
#include <math.h>

extern char **environ;

static int
connect_socket(int type, const char *path)
{
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	int fd = socket(AF_UNIX, type | SOCK_CLOEXEC, 0);
	if (fd == -1)
		err(1, "socket");
	if (strlcpy(addr.sun_path, path, sizeof(addr.sun_path)) >= sizeof(addr.sun_path))
		errx(1, "socket path too long");
	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == -1)
		err(1, "%s", path);
	return fd;
}

static void
apply_preferred(int fd, double scale)
{
	static unsigned previous_width, previous_height;
	drmModeRes *res = drmModeGetResources(fd);
	if (res == NULL)
		return;
	drmModeConnector *conn = res->count_connectors == 1 ?
	    drmModeGetConnector(fd, res->connectors[0]) : NULL;
	drmModeFreeResources(res);
	if (conn == NULL)
		return;

	for (int i = 0; i < conn->count_modes; i++) {
		const drmModeModeInfo *mode = &conn->modes[i];
		if (conn->connection != DRM_MODE_CONNECTED ||
		    conn->connector_type != DRM_MODE_CONNECTOR_VIRTUAL ||
		    !(mode->type & DRM_MODE_TYPE_PREFERRED))
			continue;
		unsigned w = mode->hdisplay, h = mode->vdisplay;
		if (previous_width == w && previous_height == h)
			break;

		char rule[192];
		snprintf(rule, sizeof(rule),
		    "hl.monitor({output='Virtual-%u',mode='%ux%u',"
		    "position='auto',scale=%g})",
		    conn->connector_type_id, w, h, scale);
		char *args[] = { "hyprctl", "eval", rule, NULL };
		pid_t pid;
		int rc = posix_spawnp(&pid, "hyprctl", NULL, NULL, args, environ);
		if (rc != 0) {
			warnx("hyprctl: %s", strerror(rc));
			break;
		}
		int status;
		pid_t child;
		do {
			child = waitpid(pid, &status, 0);
		} while (child < 0 && errno == EINTR);
		if (child == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0) {
			previous_width = w;
			previous_height = h;
		}
		break;
	}
	drmModeFreeConnector(conn);
}

/* QEMU handles monitor configuration. The client still negotiates the
 * agent capabilities on the serial channel when it first connects. */
static void
announce(int port)
{
	uint8_t msg[sizeof(VDIChunkHeader) + sizeof(VDAgentMessage) + 8] = {0};
	le32enc(msg, VDP_CLIENT_PORT);
	le32enc(msg + 4, sizeof(msg) - sizeof(VDIChunkHeader));
	uint8_t *header = msg + sizeof(VDIChunkHeader);
	le32enc(header, VD_AGENT_PROTOCOL);
	le32enc(header + 4, VD_AGENT_ANNOUNCE_CAPABILITIES);
	le32enc(header + 16, 8);
	le32enc(header + sizeof(VDAgentMessage) + 4,
	    (1U << VD_AGENT_CAP_MONITORS_CONFIG) | (1U << VD_AGENT_CAP_FILE_XFER_DISABLED));
	size_t offset = 0;
	while (offset < sizeof(msg)) {
		ssize_t n = write(port, msg + offset, sizeof(msg) - offset);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			err(1, "SPICE write");
		offset += n;
	}
}

static void
read_exact(int fd, void *buf, size_t length)
{
	for (uint8_t *next = buf; length > 0;) {
		ssize_t n = read(fd, next, length);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			errx(1, "SPICE port closed");
		next += n;
		length -= n;
	}
}

static void
read_agent_chunk(int port)
{
	VDIChunkHeader chunk;
	uint8_t data[VD_AGENT_MAX_DATA_SIZE];
	read_exact(port, &chunk, sizeof(chunk));
	size_t len = le32toh(chunk.size);
	if (len > sizeof(data))
		errx(1, "oversized SPICE chunk");
	read_exact(port, data, len);
	if (le32toh(chunk.port) != VDP_CLIENT_PORT)
		return;

	/* Agent messages may span several chunks. Retain only the header and
	 * first payload word (the capabilities request flag). */
	static uint8_t prefix[sizeof(VDAgentMessage) + 4];
	static uint64_t offset, total;
	for (size_t i = 0; i < len; i++) {
		if (offset < sizeof(prefix))
			prefix[offset] = data[i];
		offset++;
		if (offset == sizeof(VDAgentMessage)) {
			if (le32dec(prefix) != VD_AGENT_PROTOCOL)
				errx(1, "invalid SPICE message");
			total = offset + le32dec(prefix + 16);
		}
		if (offset == sizeof(prefix) &&
		    le32dec(prefix + 4) == VD_AGENT_ANNOUNCE_CAPABILITIES &&
		    le32dec(prefix + sizeof(VDAgentMessage)) != 0)
			announce(port);
		if (offset == total)
			offset = total = 0;
	}
}

int
main(int argc, char **argv)
{
	const char *runtime = getenv("XDG_RUNTIME_DIR");
	const char *display = getenv("WAYLAND_DISPLAY");
	char *end;
	double scale = argc == 2 ? strtod(argv[1], &end) : 0;
	if (!isfinite(scale) || scale <= 0 || *end != '\0')
		errx(1, "usage: %s positive-output-scale", argv[0]);
	if (!runtime || !display || !getenv("HYPRLAND_INSTANCE_SIGNATURE"))
		errx(1, "start inside Hyprland");
	char session[sizeof(((struct sockaddr_un *)0)->sun_path)];
	int len = *display == '/' ? snprintf(session, sizeof(session), "%s", display) :
	    snprintf(session, sizeof(session), "%s/%s", runtime, display);
	if (len < 0 || (size_t)len >= sizeof(session))
		errx(1, "Wayland socket path too long");

	struct pollfd fds[3];
	fds[0] = (struct pollfd){ .fd = connect_socket(SOCK_STREAM, session), .events = POLLIN };
	fds[1] = (struct pollfd){ .fd = connect_socket(SOCK_SEQPACKET,
	    "/var/run/devd.seqpacket.pipe"), .events = POLLIN };
	int drm = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (drm < 0)
		err(1, "/dev/dri/card0");

	/* Opening the agent port enables spice-gtk's monitor negotiation.
	 * QEMU consumes the monitor messages and updates the virtio GPU EDID. */
	int port = open("/dev/vtcon/com.redhat.spice.0", O_RDWR | O_NOCTTY |
	    O_NONBLOCK | O_CLOEXEC | O_EXLOCK);
	if (port < 0)
		err(1, "SPICE port");
	struct termios term;
	if (tcgetattr(port, &term) == -1)
		err(1, "tcgetattr");
	cfmakeraw(&term);
	if (tcsetattr(port, TCSANOW, &term) == -1)
		err(1, "tcsetattr");
	if (fcntl(port, F_SETFL, 0) == -1)
		err(1, "SPICE port flags");
	announce(port);
	fds[2] = (struct pollfd){ .fd = port, .events = POLLIN };

	apply_preferred(drm, scale);
	int retries = 0;
	for (;;) {
		int ready = poll(fds, 3, retries ? 350 : -1);
		if (ready == 0) {
			/* The DRM master may refresh the cached mode list after devd
			 * has already delivered the event to this process. */
			apply_preferred(drm, scale);
			retries--;
			continue;
		}
		if (ready < 0) {
			if (errno == EINTR)
				continue;
			err(1, "poll");
		}
		/* A passive Wayland connection closes when this session ends. */
		if (fds[0].revents)
			break;
		if ((fds[1].revents | fds[2].revents) & (POLLERR | POLLHUP | POLLNVAL))
			break;
		char data[4096];
		if (fds[2].revents & POLLIN)
			read_agent_chunk(port);
		if (fds[1].revents & POLLIN) {
			ssize_t n = recv(fds[1].fd, data, sizeof(data) - 1, 0);
			if (n <= 0)
				break;
			data[n] = '\0';
			if (strstr(data, "!system=DRM subsystem=CONNECTOR type=HOTPLUG ") &&
			    strstr(data, "cdev=dri/card0") != NULL)
				retries = 4;
		}
	}
	return 0;
}
