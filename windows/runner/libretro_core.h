#ifndef LIBRETRO_CORE_H_
#define LIBRETRO_CORE_H_

#include <string>
#include <vector>
#include <mutex>
#include <thread>
#include <atomic>
#include <map>
#include <functional>
#include "libretro.h"
#include "gl_render_context.h"


#ifdef _WIN32
#include <windows.h>
typedef HMODULE DylibHandle;
#else
#include <dlfcn.h>
typedef void* DylibHandle;
#endif

class LibretroCore {
public:
    LibretroCore();
    ~LibretroCore();

    bool LoadCore(const std::string& core_path);
    bool LoadGame(const std::string& rom_path);
    void Unload();
    void Reset();

    void SetSystemPath(const std::string& path) { system_path_ = path; }

    std::vector<uint8_t> SaveState();
    bool LoadState(const std::vector<uint8_t>& state);

    void RunFrame();

    void SetFastForward(bool enabled) { fast_forward_ = enabled; }
    void SetSlowMotion(bool enabled) { slow_motion_ = enabled; }

    
    void StartThread();
    void StopThread();
    void Pause();
    void Resume();

    
    const uint8_t* GetVideoBuffer() const { return video_buffer_.data(); }
    size_t GetVideoBufferSize() const { return video_buffer_.size(); }
    unsigned GetVideoWidth() const { return video_width_; }
    unsigned GetVideoHeight() const { return video_height_; }
    size_t GetVideoPitch() const { return video_pitch_; }
    double GetAspectRatio() const { return aspect_ratio_; }
    
    std::mutex& GetVideoMutex() { return video_mutex_; }
    void SetFrameAvailableCallback(std::function<void()> cb) { frame_available_cb_ = cb; }

    void UpdateInputState(unsigned port, unsigned id, bool pressed);
    void UpdateAnalogState(unsigned port, unsigned index, unsigned id, int16_t value);

    
    double GetSampleRate() const { return sample_rate_; }
    const std::vector<int16_t>& GetAudioBuffer() const { return audio_buffer_; }
    std::vector<int16_t>& GetAudioBufferMutable() { return audio_buffer_; }
    std::mutex& GetAudioMutex() { return audio_mutex_; }
    void ClearAudioBuffer() { std::lock_guard<std::mutex> lock(audio_mutex_); audio_buffer_.clear(); }

    
    static void retro_video_refresh_cb(const void *data, unsigned width, unsigned height, size_t pitch);
    static void retro_audio_sample_cb(int16_t left, int16_t right);
    static size_t retro_audio_sample_batch_cb(const int16_t *data, size_t frames);
    static void retro_input_poll_cb();
    static int16_t retro_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id);
    static bool retro_environment_cb(unsigned cmd, void *data);

    static LibretroCore* GetInstance() { return instance_; }

private:
    static LibretroCore* instance_;

    DylibHandle dylib_ = nullptr;

    
    void (*retro_init)(void);
    void (*retro_deinit)(void);
    unsigned (*retro_api_version)(void);
    void (*retro_get_system_info)(struct retro_system_info *info);
    void (*retro_get_system_av_info)(struct retro_system_av_info *info);
    void (*retro_set_environment)(retro_environment_t);
    void (*retro_set_video_refresh)(retro_video_refresh_t);
    void (*retro_set_audio_sample)(retro_audio_sample_t);
    void (*retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*retro_set_input_poll)(retro_input_poll_t);
    void (*retro_set_input_state)(retro_input_state_t);
    bool (*retro_load_game)(const struct retro_game_info *game);
    void (*retro_unload_game)(void);
    void (*retro_reset)(void);
    void (*retro_run)(void);

    size_t (*retro_serialize_size)(void);
    bool (*retro_serialize)(void *data, size_t size);
    bool (*retro_unserialize)(const void *data, size_t size);

    bool LoadSymbol(const char* name, void** func);

    
    std::vector<uint8_t> video_buffer_;
    unsigned video_width_ = 0;
    unsigned video_height_ = 0;
    size_t video_pitch_ = 0;
    std::mutex video_mutex_;



    
    std::thread run_thread_;
    std::atomic<bool> thread_running_{false};
    std::atomic<bool> is_paused_{false};
    std::atomic<bool> fast_forward_{false};
    std::atomic<bool> slow_motion_{false};
    int slow_motion_count_ = 0;

    std::function<void()> frame_available_cb_;
    bool input_state_[2][16] = {false};
    int16_t analog_state_[2][2][2] = {0}; 

    
    std::vector<int16_t> audio_buffer_;
    std::mutex audio_mutex_;
    double sample_rate_ = 44100.0;

    void ThreadLoop();

    bool game_loaded_ = false;

    // Graphics context
    GLRenderContext gl_context_;
    bool hw_render_enabled_ = false;
    struct retro_hw_render_callback hw_render_cb_ = {0};
    struct retro_hw_render_context_negotiation_interface hw_render_negotiation_ = {0};
    int pbo_index_ = 0;

    static uintptr_t gl_get_framebuffer_cb();
    static retro_proc_address_t gl_get_proc_address_cb(const char *sym);

    // Callbacks from core
    struct retro_audio_callback audio_cb_ = {0};
    struct retro_frame_time_callback frame_time_cb_ = {0};
    struct retro_vfs_interface vfs_interface_ = {0};

    std::string system_path_;
    std::map<std::string, std::string> variable_defaults_;
    retro_pixel_format pixel_format_ = RETRO_PIXEL_FORMAT_0RGB1555;

private:
    double aspect_ratio_ = 4.0 / 3.0; 
};

#endif
