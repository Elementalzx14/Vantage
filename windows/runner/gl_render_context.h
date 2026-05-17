#ifndef GL_RENDER_CONTEXT_H_
#define GL_RENDER_CONTEXT_H_

#include <windows.h>
#include <GL/gl.h>
#include <cstdint>
#include <cstdio>
#include <chrono>
#include <string>

// GL extension function types needed for modern context and FBO support
typedef ptrdiff_t GLintptr;
typedef ptrdiff_t GLsizeiptr;
typedef struct __GLsync *GLsync;
typedef uint64_t GLuint64;

typedef HGLRC (WINAPI *PFNWGLCREATECONTEXTATTRIBSARBPROC)(HDC hDC, HGLRC hShareContext, const int *attribList);
typedef BOOL (WINAPI *PFNWGLCHOOSEPIXELFORMATARBPROC)(HDC hdc, const int *piAttribILis, const FLOAT *pfAttribFList, UINT nMaxFormats, int *piFormats, UINT *nNumFormats);

typedef void (APIENTRY *PFNGLGENFRAMEBUFFERSPROC)(GLsizei n, GLuint *framebuffers);
typedef void (APIENTRY *PFNGLBINDFRAMEBUFFERPROC)(GLenum target, GLuint framebuffer);
typedef void (APIENTRY *PFNGLFRAMEBUFFERTEXTURE2DPROC)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
typedef void (APIENTRY *PFNGLGENRENDERBUFFERSPROC)(GLsizei n, GLuint *renderbuffers);
typedef void (APIENTRY *PFNGLBINDRENDERBUFFERPROC)(GLenum target, GLuint renderbuffer);
typedef void (APIENTRY *PFNGLRENDERBUFFERSTORAGEPROC)(GLenum target, GLenum internalformat, GLsizei width, GLsizei height);
typedef void (APIENTRY *PFNGLFRAMEBUFFERRENDERBUFFERPROC)(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer);
typedef GLenum (APIENTRY *PFNGLCHECKFRAMEBUFFERSTATUSPROC)(GLenum target);
typedef void (APIENTRY *PFNGLDELETEFRAMEBUFFERSPROC)(GLsizei n, const GLuint *framebuffers);
typedef void (APIENTRY *PFNGLDELETERENDERBUFFERSPROC)(GLsizei n, const GLuint *renderbuffers);

typedef void (APIENTRY *PFNGLGENBUFFERSPROC)(GLsizei n, GLuint *buffers);
typedef void (APIENTRY *PFNGLBINDBUFFERPROC)(GLenum target, GLuint buffer);
typedef void (APIENTRY *PFNGLBUFFERDATAPROC)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
typedef void* (APIENTRY *PFNGLMAPBUFFERRANGEPROC)(GLenum target, GLintptr offset, GLsizeiptr length, GLbitfield access);
typedef GLboolean (APIENTRY *PFNGLUNMAPBUFFERPROC)(GLenum target);
typedef GLsync (APIENTRY *PFNGLFENCESYNCPROC)(GLenum condition, GLbitfield flags);
typedef void (APIENTRY *PFNGLWAITSYNCPROC)(GLsync sync, GLbitfield flags, GLuint64 timeout);
typedef GLenum (APIENTRY *PFNGLCLIENTWAITSYNCPROC)(GLsync sync, GLbitfield flags, GLuint64 timeout);
typedef void (APIENTRY *PFNGLDELETESYNCPROC)(GLsync sync);
typedef void (APIENTRY *PFNGLDELETEBUFFERSPROC)(GLsizei n, const GLuint *buffers);

#define WGL_CONTEXT_MAJOR_VERSION_ARB           0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB           0x2092
#define WGL_CONTEXT_PROFILE_MASK_ARB            0x9126
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB        0x00000001
#define WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB 0x00000002

// GL constants not in base gl.h
#ifndef GL_FRAMEBUFFER
#define GL_FRAMEBUFFER 0x8D40
#endif
#ifndef GL_RENDERBUFFER
#define GL_RENDERBUFFER 0x8D41
#endif
#ifndef GL_COLOR_ATTACHMENT0
#define GL_COLOR_ATTACHMENT0 0x8CE0
#endif
#ifndef GL_DEPTH_ATTACHMENT
#define GL_DEPTH_ATTACHMENT 0x8D00
#endif
#ifndef GL_DEPTH_COMPONENT24
#define GL_DEPTH_COMPONENT24 0x81A6
#endif
#ifndef GL_FRAMEBUFFER_COMPLETE
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#endif
#ifndef GL_BGRA
#define GL_BGRA 0x80E1
#endif
#ifndef GL_RGBA8
#define GL_RGBA8 0x8058
#endif
#ifndef GL_PIXEL_PACK_BUFFER
#define GL_PIXEL_PACK_BUFFER 0x88EB
#endif
#ifndef GL_STREAM_READ
#define GL_STREAM_READ 0x88E1
#endif
#ifndef GL_MAP_READ_BIT
#define GL_MAP_READ_BIT 0x0001
#endif
#ifndef GL_SYNC_GPU_COMMANDS_COMPLETE
#define GL_SYNC_GPU_COMMANDS_COMPLETE 0x9117
#endif
#ifndef GL_ALREADY_SIGNALED
#define GL_ALREADY_SIGNALED 0x9119
#endif
#ifndef GL_CONDITION_SATISFIED
#define GL_CONDITION_SATISFIED 0x911C
#endif

class GLRenderContext {
public:
    GLRenderContext() = default;
    ~GLRenderContext() { Destroy(); }

    bool Init(unsigned width, unsigned height) {
        if (initialized_) Destroy();

        // 1. Create a dummy window and context to load extensions
        WNDCLASSA wc = {};
        wc.lpfnWndProc = DefWindowProcA;
        wc.hInstance = GetModuleHandle(NULL);
        wc.lpszClassName = "VantageGLDummy";
        RegisterClassA(&wc);

        HWND dummy_hwnd = CreateWindowExA(0, wc.lpszClassName, "Dummy", 0, 0, 0, 1, 1, NULL, NULL, wc.hInstance, NULL);
        HDC dummy_hdc = GetDC(dummy_hwnd);

        PIXELFORMATDESCRIPTOR pfd = { sizeof(pfd), 1 };
        pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
        pfd.iPixelType = PFD_TYPE_RGBA;
        pfd.cColorBits = 32;
        SetPixelFormat(dummy_hdc, ChoosePixelFormat(dummy_hdc, &pfd), &pfd);

        HGLRC dummy_hglrc = wglCreateContext(dummy_hdc);
        wglMakeCurrent(dummy_hdc, dummy_hglrc);

        auto wglCreateContextAttribsARB = (PFNWGLCREATECONTEXTATTRIBSARBPROC)wglGetProcAddress("wglCreateContextAttribsARB");
        
        // 2. Load basic FBO functions while we have a context
        glGenFramebuffers = (PFNGLGENFRAMEBUFFERSPROC)wglGetProcAddress("glGenFramebuffers");
        glBindFramebuffer = (PFNGLBINDFRAMEBUFFERPROC)wglGetProcAddress("glBindFramebuffer");
        glFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC)wglGetProcAddress("glFramebufferTexture2D");
        glGenRenderbuffers = (PFNGLGENRENDERBUFFERSPROC)wglGetProcAddress("glGenRenderbuffers");
        glBindRenderbuffer = (PFNGLBINDRENDERBUFFERPROC)wglGetProcAddress("glBindRenderbuffer");
        glRenderbufferStorage = (PFNGLRENDERBUFFERSTORAGEPROC)wglGetProcAddress("glRenderbufferStorage");
        glFramebufferRenderbuffer = (PFNGLFRAMEBUFFERRENDERBUFFERPROC)wglGetProcAddress("glFramebufferRenderbuffer");
        glCheckFramebufferStatus = (PFNGLCHECKFRAMEBUFFERSTATUSPROC)wglGetProcAddress("glCheckFramebufferStatus");
        glDeleteFramebuffers = (PFNGLDELETEFRAMEBUFFERSPROC)wglGetProcAddress("glDeleteFramebuffers");
        glDeleteRenderbuffers = (PFNGLDELETERENDERBUFFERSPROC)wglGetProcAddress("glDeleteRenderbuffers");

        // Load PBO and Sync functions
        glGenBuffers = (PFNGLGENBUFFERSPROC)wglGetProcAddress("glGenBuffers");
        glBindBuffer = (PFNGLBINDBUFFERPROC)wglGetProcAddress("glBindBuffer");
        glBufferData = (PFNGLBUFFERDATAPROC)wglGetProcAddress("glBufferData");
        glMapBufferRange = (PFNGLMAPBUFFERRANGEPROC)wglGetProcAddress("glMapBufferRange");
        glUnmapBuffer = (PFNGLUNMAPBUFFERPROC)wglGetProcAddress("glUnmapBuffer");
        glDeleteBuffers = (PFNGLDELETEBUFFERSPROC)wglGetProcAddress("glDeleteBuffers");
        glFenceSync = (PFNGLFENCESYNCPROC)wglGetProcAddress("glFenceSync");
        glWaitSync = (PFNGLWAITSYNCPROC)wglGetProcAddress("glWaitSync");
        glClientWaitSync = (PFNGLCLIENTWAITSYNCPROC)wglGetProcAddress("glClientWaitSync");
        glDeleteSync = (PFNGLDELETESYNCPROC)wglGetProcAddress("glDeleteSync");

        wglMakeCurrent(NULL, NULL);
        wglDeleteContext(dummy_hglrc);
        ReleaseDC(dummy_hwnd, dummy_hdc);
        DestroyWindow(dummy_hwnd);

        // 3. Create the real hidden window
        WNDCLASSA wc_real = {};
        wc_real.lpfnWndProc = DefWindowProcA;
        wc_real.hInstance = GetModuleHandle(NULL);
        wc_real.lpszClassName = "VantageGLHidden";
        RegisterClassA(&wc_real);

        hwnd_ = CreateWindowExA(0, wc_real.lpszClassName, "GL", 0, 0, 0, width, height, NULL, NULL, wc_real.hInstance, NULL);
        hdc_ = GetDC(hwnd_);

        SetPixelFormat(hdc_, ChoosePixelFormat(hdc_, &pfd), &pfd);

        if (wglCreateContextAttribsARB) {
            int attribs[] = {
                WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
                WGL_CONTEXT_MINOR_VERSION_ARB, 3,
                WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB,
                0
            };
            hglrc_ = wglCreateContextAttribsARB(hdc_, NULL, attribs);
        } else {
            hglrc_ = wglCreateContext(hdc_);
        }

        if (!hglrc_) {
            LogGL("Failed to create HGLRC");
            return false;
        }

        wglMakeCurrent(hdc_, hglrc_);

        // 4. Create FBO
        fbo_width_ = width;
        fbo_height_ = height;

        glGenFramebuffers(1, &fbo_);
        glBindFramebuffer(GL_FRAMEBUFFER, fbo_);

        glGenTextures(1, &fbo_texture_);
        glBindTexture(GL_TEXTURE_2D, fbo_texture_);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fbo_texture_, 0);

        GLuint rbo;
        glGenRenderbuffers(1, &rbo);
        glBindRenderbuffer(GL_RENDERBUFFER, rbo);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, rbo);
        fbo_depth_ = rbo;

        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
            LogGL("FBO incomplete");
            return false;
        }

        // 5. Create PBOs for asynchronous readback
        glGenBuffers(2, pbos_);
        for (int i = 0; i < 2; i++) {
            glBindBuffer(GL_PIXEL_PACK_BUFFER, pbos_[i]);
            glBufferData(GL_PIXEL_PACK_BUFFER, width * height * 4, NULL, GL_STREAM_READ);
        }
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);

        initialized_ = true;
        LogGL("GL Context initialized. FBO=" + std::to_string(fbo_));
        return true;
    }

    void Destroy() {
        if (!initialized_) return;
        MakeCurrent();
        if (fbo_) glDeleteFramebuffers(1, &fbo_);
        if (fbo_texture_) glDeleteTextures(1, &fbo_texture_);
        if (fbo_depth_) glDeleteRenderbuffers(1, &fbo_depth_);
        if (pbos_[0]) glDeleteBuffers(2, pbos_);
        if (fences_[0]) glDeleteSync(fences_[0]);
        if (fences_[1]) glDeleteSync(fences_[1]);
        if (hglrc_) wglDeleteContext(hglrc_);
        if (hwnd_ && hdc_) ReleaseDC(hwnd_, hdc_);
        if (hwnd_) DestroyWindow(hwnd_);
        initialized_ = false;
        hglrc_ = NULL;
        hdc_ = NULL;
        hwnd_ = NULL;
        fbo_ = 0;
        fbo_texture_ = 0;
        fbo_depth_ = 0;
        pbos_[0] = pbos_[1] = 0;
        fences_[0] = fences_[1] = NULL;
    }

    void MakeCurrent() {
        if (hdc_ && hglrc_) wglMakeCurrent(hdc_, hglrc_);
    }

    // Triggers an asynchronous readback into the specified PBO index
    void TriggerReadback(int index, unsigned width, unsigned height) {
        if (!initialized_) return;
        glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, pbos_[index]);
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        
        if (fences_[index]) glDeleteSync(fences_[index]);
        fences_[index] = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
        
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    }

    // Maps a previously triggered readback and copies data to dst
    bool MapAndCopy(int index, uint8_t* dst, unsigned width, unsigned height) {
        if (!initialized_ || !fences_[index]) return false;

        // Wait for GPU to finish writing to the PBO. 
        // 0 timeout means we just check if it's already done.
        GLenum res = glClientWaitSync(fences_[index], 0, 0);
        if (res != GL_ALREADY_SIGNALED && res != GL_CONDITION_SATISFIED) {
            return false; // Still busy
        }

        glBindBuffer(GL_PIXEL_PACK_BUFFER, pbos_[index]);
        void* ptr = glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, width * height * 4, GL_MAP_READ_BIT);
        if (ptr) {
            memcpy(dst, ptr, width * height * 4);
            glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
        }
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        
        glDeleteSync(fences_[index]);
        fences_[index] = NULL;
        return true;
    }

    void ReadPixels(uint8_t* dst, unsigned width, unsigned height) {
        if (!initialized_) return;
        glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, dst);
    }

    GLuint GetFBO() const { return fbo_; }
    bool IsInitialized() const { return initialized_; }

    static void* GetGLProcAddress(const char* name) {
        void* p = (void*)wglGetProcAddress(name);
        if (p == 0 || (p == (void*)0x1) || (p == (void*)0x2) || (p == (void*)0x3) || (p == (void*)-1)) {
            static HMODULE opengl32 = LoadLibraryA("opengl32.dll");
            if (opengl32) {
                p = (void*)GetProcAddress(opengl32, name);
            }
        }
        return p;
    }

private:
    static void LogGL(const std::string& msg) {
        OutputDebugStringA(("[Vantage-GL] " + msg + "\n").c_str());
    }

    HWND hwnd_ = NULL;
    HDC hdc_ = NULL;
    HGLRC hglrc_ = NULL;
    GLuint fbo_ = 0;
    GLuint fbo_texture_ = 0;
    GLuint fbo_depth_ = 0;
    unsigned fbo_width_ = 0;
    unsigned fbo_height_ = 0;
    bool initialized_ = false;

    GLuint pbos_[2] = {0, 0};
    GLsync fences_[2] = {NULL, NULL};

    // Function pointers
    PFNGLGENFRAMEBUFFERSPROC glGenFramebuffers = nullptr;
    PFNGLBINDFRAMEBUFFERPROC glBindFramebuffer = nullptr;
    PFNGLFRAMEBUFFERTEXTURE2DPROC glFramebufferTexture2D = nullptr;
    PFNGLGENRENDERBUFFERSPROC glGenRenderbuffers = nullptr;
    PFNGLBINDRENDERBUFFERPROC glBindRenderbuffer = nullptr;
    PFNGLRENDERBUFFERSTORAGEPROC glRenderbufferStorage = nullptr;
    PFNGLFRAMEBUFFERRENDERBUFFERPROC glFramebufferRenderbuffer = nullptr;
    PFNGLCHECKFRAMEBUFFERSTATUSPROC glCheckFramebufferStatus = nullptr;
    PFNGLDELETEFRAMEBUFFERSPROC glDeleteFramebuffers = nullptr;
    PFNGLDELETERENDERBUFFERSPROC glDeleteRenderbuffers = nullptr;

    PFNGLGENBUFFERSPROC glGenBuffers = nullptr;
    PFNGLBINDBUFFERPROC glBindBuffer = nullptr;
    PFNGLBUFFERDATAPROC glBufferData = nullptr;
    PFNGLMAPBUFFERRANGEPROC glMapBufferRange = nullptr;
    PFNGLUNMAPBUFFERPROC glUnmapBuffer = nullptr;
    PFNGLDELETEBUFFERSPROC glDeleteBuffers = nullptr;
    PFNGLFENCESYNCPROC glFenceSync = nullptr;
    PFNGLWAITSYNCPROC glWaitSync = nullptr;
    PFNGLCLIENTWAITSYNCPROC glClientWaitSync = nullptr;
    PFNGLDELETESYNCPROC glDeleteSync = nullptr;
};


#endif
