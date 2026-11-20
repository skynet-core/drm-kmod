/* SPDX-License-Identifier: BSD-2-Clause */
/* Build: cc render-smoke.c -o render-smoke $(pkg-config --cflags --libs egl glesv2 gbm) */
#include <sys/types.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <gbm.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

static void
check(int ok, const char *what)
{

	if (!ok) {
		fprintf(stderr, "FAIL: %s (EGL %#x, GL %#x)\n", what,
		    eglGetError(), glGetError());
		exit(1);
	}
}

static GLuint
shader(GLenum type, const char *source)
{
	GLuint result = glCreateShader(type);
	GLint compiled;

	glShaderSource(result, 1, &source, NULL);
	glCompileShader(result);
	glGetShaderiv(result, GL_COMPILE_STATUS, &compiled);
	check(compiled, "compile shader");
	return (result);
}

int
main(int argc, char **argv)
{
	const EGLint config_attrs[] = {
		EGL_SURFACE_TYPE, 0,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
		EGL_NONE
	};
	const EGLint context_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	const GLfloat vertices[] = { -1, -1, 3, -1, -1, 3 };
	PFNEGLGETPLATFORMDISPLAYEXTPROC get_display;
	struct gbm_device *gbm;
	EGLDisplay display;
	EGLContext context;
	EGLConfig config;
	EGLint count, major, minor;
	const char *renderer;
	unsigned char pixels[32 * 32 * 4];
	GLuint program, vertex, fragment, texture, framebuffer;
	GLint linked, color;
	int fd, frame;
	size_t i;

	fd = open(argc > 1 ? argv[1] : "/dev/dri/renderD128", O_RDWR);
	check(fd >= 0, "open guest render node");
	gbm = gbm_create_device(fd);
	check(gbm != NULL, "create GBM device");
	get_display = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
	    eglGetProcAddress("eglGetPlatformDisplayEXT");
	check(get_display != NULL, "EGL platform display extension");
	display = get_display(EGL_PLATFORM_GBM_KHR, gbm, NULL);
	check(display != EGL_NO_DISPLAY, "GBM EGL display");
	check(eglInitialize(display, &major, &minor), "initialize EGL");
	check(eglBindAPI(EGL_OPENGL_ES_API), "bind GLES API");
	check(eglChooseConfig(display, config_attrs, &config, 1, &count) &&
	    count == 1, "choose EGL config");
	context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attrs);
	check(context != EGL_NO_CONTEXT, "create GLES2 context");
	check(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context),
	    "make surfaceless context current");
	renderer = (const char *)glGetString(GL_RENDERER);
	check(renderer != NULL, "read GL renderer");
	printf("EGL %d.%d\nGL_VENDOR: %s\nGL_RENDERER: %s\nGL_VERSION: %s\n",
	    major, minor, glGetString(GL_VENDOR), renderer, glGetString(GL_VERSION));
	check(strstr(renderer, "virgl") != NULL &&
	    strstr(renderer, "llvmpipe") == NULL &&
	    strstr(renderer, "softpipe") == NULL &&
	    strstr(renderer, "Software") == NULL, "hardware virgl renderer");
	vertex = shader(GL_VERTEX_SHADER,
	    "attribute vec2 position; void main() { gl_Position = vec4(position, 0, 1); }");
	fragment = shader(GL_FRAGMENT_SHADER,
	    "precision mediump float; uniform vec4 color; void main() { gl_FragColor = color; }");
	program = glCreateProgram();
	glAttachShader(program, vertex);
	glAttachShader(program, fragment);
	glBindAttribLocation(program, 0, "position");
	glLinkProgram(program);
	glGetProgramiv(program, GL_LINK_STATUS, &linked);
	check(linked, "link shader program");
	glUseProgram(program);
	color = glGetUniformLocation(program, "color");
	check(color >= 0, "shader color uniform");
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, vertices);
	glEnableVertexAttribArray(0);
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 32, 32, 0, GL_RGBA,
	    GL_UNSIGNED_BYTE, NULL);
	glGenFramebuffers(1, &framebuffer);
	glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
	    texture, 0);
	check(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
	    "render target is complete");
	glViewport(0, 0, 32, 32);
	for (frame = 0; frame < 1000; frame++) {
		unsigned char red = frame % 2 ? 255 : 0;

		glClearColor(0, 0, 0, 1);
		glClear(GL_COLOR_BUFFER_BIT);
		glUniform4f(color, red / 255.0f, 1, 0, 1);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		glReadPixels(0, 0, 32, 32, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
		check(glGetError() == GL_NO_ERROR, "draw/readback");
		for (i = 0; i < sizeof(pixels); i += 4)
			check(pixels[i] == red && pixels[i + 1] == 255 &&
			    pixels[i + 2] == 0 && pixels[i + 3] == 255,
			    "GPU readback matches the submitted frame");
	}
	puts("PASS: 1000 alternating GPU frames with full pixel readback");
	glDeleteFramebuffers(1, &framebuffer);
	glDeleteTextures(1, &texture);
	glDeleteProgram(program);
	glDeleteShader(vertex);
	glDeleteShader(fragment);
	eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroyContext(display, context);
	eglTerminate(display);
	gbm_device_destroy(gbm);
	close(fd);
	return (0);
}
