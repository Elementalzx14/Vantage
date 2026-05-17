#include "libretro_core.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <cstring>
#include <chrono>
#include <algorithm>
#include <map>
#include <sstream>


// Sentinel value cores pass to retro_video_refresh when HW rendering is active
#ifndef RETRO_HW_FRAME_BUFFER_VALID
#define RETRO_HW_FRAME_BUFFER_VALID ((const void*)-1)
#endif

// Some versions of libretro.h miss this constant
#ifndef RETRO_ENVIRONMENT_GET_CPU_FEATURES
#define RETRO_ENVIRONMENT_GET_CPU_FEATURES (28 | 0x10000) // 0x10000 = RETRO_ENVIRONMENT_EXPERIMENTAL
#endif

#define CONVERT_RGB565_TO_RGBA8888(pixel) \
    (0xFF000000 | (((pixel) & 0x001F) << 19) | (((pixel) & 0x07E0) << 5) | (((pixel) & 0xF800) >> 8))

#define CONVERT_XRGB8888_TO_RGBA8888(pixel) \
    (0xFF000000 | (((pixel) & 0xFF) << 16) | ((pixel) & 0xFF00) | (((pixel) & 0xFF0000) >> 16))

#define CONVERT_0RGB1555_TO_RGBA8888(pixel) \
    (0xFF000000 | (((pixel) & 0x001F) << 19) | (((pixel) & 0x03E0) << 6) | (((pixel) & 0x7C00) >> 9))

LibretroCore* LibretroCore::instance_ = nullptr;

#include <windows.h>
#include <chrono>

static void LogMessage(const std::string& msg) {
    OutputDebugStringA(("[Vantage-Core] " + msg + "\n").c_str());
    
    // Attempt to log to a file in the temp directory as a fallback
    char temp_path[MAX_PATH];
    if (GetTempPathA(MAX_PATH, temp_path)) {
        std::string log_path = std::string(temp_path) + "\\vantage_emu.log";
        std::ofstream log_file(log_path, std::ios::app);
        if (log_file.is_open()) {
            auto now_clock = std::chrono::system_clock::now();
            auto now_time = std::chrono::system_clock::to_time_t(now_clock);
            char timestamp[26];
            ctime_s(timestamp, sizeof(timestamp), &now_time);
            timestamp[24] = '\0'; // Remove newline
            log_file << "[" << timestamp << "] " << msg << std::endl;
            log_file.flush();
        }
    }
}

// Static GL callbacks for libretro HW rendering
uintptr_t LibretroCore::gl_get_framebuffer_cb() {
    // Return our FBO with proper color+depth attachments.
    // The core's glsm calls get_current_framebuffer() during context_reset
    // to set up its internal GL state tracking. It queries GL_COLOR_ATTACHMENT0
    // on this FBO, which FAILS on FBO 0 (default framebuffer) because the
    // default FB uses GL_BACK, not GL_COLOR_ATTACHMENT0.
    if (instance_ && instance_->gl_context_.IsInitialized()) {
        return instance_->gl_context_.GetFBO();
    }
    return 0;
}

retro_proc_address_t LibretroCore::gl_get_proc_address_cb(const char *sym) {
    return (retro_proc_address_t)GLRenderContext::GetGLProcAddress(sym);
}

LibretroCore::LibretroCore() {
    instance_ = this;
    
    // Initialize all function pointers to nullptr
    retro_init = nullptr;
    retro_deinit = nullptr;
    retro_api_version = nullptr;
    retro_get_system_info = nullptr;
    retro_get_system_av_info = nullptr;
    retro_set_environment = nullptr;
    retro_set_video_refresh = nullptr;
    retro_set_audio_sample = nullptr;
    retro_set_audio_sample_batch = nullptr;
    retro_set_input_poll = nullptr;
    retro_set_input_state = nullptr;
    retro_load_game = nullptr;
    retro_unload_game = nullptr;
    retro_reset = nullptr;
    retro_run = nullptr;
    retro_serialize_size = nullptr;
    retro_serialize = nullptr;
    retro_unserialize = nullptr;
}

LibretroCore::~LibretroCore() {
    Unload();
    instance_ = nullptr;
}

bool LibretroCore::LoadSymbol(const char* name, void** func) {
#ifdef _WIN32
    *func = (void*)GetProcAddress(dylib_, name);
#else
    *func = dlsym(dylib_, name);
#endif
    return *func != nullptr;
}

bool LibretroCore::LoadCore(const std::string& core_path) {
    LogMessage("--- CORE LOAD START ---");
    LogMessage("Core path: " + core_path);
    
#ifdef _WIN32
    int len = MultiByteToWideChar(CP_UTF8, 0, core_path.c_str(), -1, NULL, 0);
    wchar_t* w_core_path = new wchar_t[len];
    MultiByteToWideChar(CP_UTF8, 0, core_path.c_str(), -1, w_core_path, len);
    dylib_ = LoadLibraryW(w_core_path);
    delete[] w_core_path;
#else
    dylib_ = dlopen(core_path.c_str(), RTLD_LAZY);
#endif

    if (!dylib_) {
        LogMessage("CRITICAL: Failed to load core library file");
        return false;
    }

    #define LOAD_SYM(name) do { if (!LoadSymbol(#name, (void**)&name)) { LogMessage("MISSING SYMBOL: " #name); return false; } } while(0)
    
    LOAD_SYM(retro_init);
    LOAD_SYM(retro_deinit);
    LOAD_SYM(retro_api_version);
    LOAD_SYM(retro_get_system_info);
    LOAD_SYM(retro_get_system_av_info);
    LOAD_SYM(retro_set_environment);
    LOAD_SYM(retro_set_video_refresh);
    LOAD_SYM(retro_set_audio_sample);
    LOAD_SYM(retro_set_audio_sample_batch);
    LOAD_SYM(retro_set_input_poll);
    LOAD_SYM(retro_set_input_state);
    LOAD_SYM(retro_load_game);
    LOAD_SYM(retro_unload_game);
    LOAD_SYM(retro_reset);
    LOAD_SYM(retro_run);
    LOAD_SYM(retro_serialize_size);
    LOAD_SYM(retro_serialize);
    LOAD_SYM(retro_unserialize);
    
    LogMessage("All required symbols found. Core API version: " + std::to_string(retro_api_version()));

    retro_set_environment(retro_environment_cb);
    
    // Ensure system and save directories exist
    if (!system_path_.empty()) {
        CreateDirectoryA(system_path_.c_str(), NULL);
        std::string save_dir = system_path_ + "\\saves";
        CreateDirectoryA(save_dir.c_str(), NULL);
    }

    LogMessage("Calling retro_init...");
    retro_init();
    LogMessage("retro_init completed successfully");

    retro_set_video_refresh(retro_video_refresh_cb);
    retro_set_audio_sample(retro_audio_sample_cb);
    retro_set_audio_sample_batch(retro_audio_sample_batch_cb);
    retro_set_input_poll(retro_input_poll_cb);
    retro_set_input_state(retro_input_state_cb);

    return true;
}

bool LibretroCore::LoadGame(const std::string& rom_path_in) {
    LogMessage("--- GAME LOAD START ---");
    LogMessage("Input ROM path: " + rom_path_in);
    
    std::string rom_path = rom_path_in;
    // We only replace slashes for internal reading, some cores might want the original path in game_info
    std::string standardized_rom_path = rom_path;
    std::replace(standardized_rom_path.begin(), standardized_rom_path.end(), '\\', '/');
    LogMessage("Standardized ROM path: " + standardized_rom_path);

    retro_system_info sys_info = {0};
    retro_get_system_info(&sys_info);
    
    LogMessage("System Info: Library=" + std::string(sys_info.library_name ? sys_info.library_name : "N/A") + 
               " Version=" + std::string(sys_info.library_version ? sys_info.library_version : "N/A"));
    LogMessage("Core need_fullpath: " + std::string(sys_info.need_fullpath ? "YES" : "NO"));

    retro_game_info game_info = {0};
    game_info.path = rom_path.c_str(); // Use original path here
    game_info.meta = "";

    std::vector<char> buffer;
    if (!sys_info.need_fullpath) {
        LogMessage("Action: Reading ROM into memory buffer");
        std::ifstream file(standardized_rom_path, std::ios::binary | std::ios::ate);
        if (!file.is_open()) {
            LogMessage("ERROR: Could not open ROM file for reading");
            return false;
        }

        std::streamsize size = file.tellg();
        file.seekg(0, std::ios::beg);

        buffer.resize(size);
        if (!file.read(buffer.data(), size)) {
            LogMessage("ERROR: Failed to read ROM data into buffer");
            return false;
        }
        game_info.data = buffer.data();
        game_info.size = (size_t)size;
        LogMessage("ROM successfully buffered. Size: " + std::to_string(size) + " bytes");
    } else {
        LogMessage("Action: Passing ROM path only (fullpath mode)");
        game_info.data = nullptr;
        game_info.size = 0;
    }
    
    LogMessage("Calling retro_load_game...");
    bool result = retro_load_game(&game_info);
    
    if (!result) {
        LogMessage("FAILURE: retro_load_game returned false");
        return false;
    }
    
    LogMessage("SUCCESS: Game loaded into core");
    game_loaded_ = true;

    retro_system_av_info av_info;
    retro_get_system_av_info(&av_info);

    LogMessage("AV Info: SampleRate=" + std::to_string(av_info.timing.sample_rate) + 
               " FPS=" + std::to_string(av_info.timing.fps) +
               " BaseRes=" + std::to_string(av_info.geometry.base_width) + "x" + std::to_string(av_info.geometry.base_height));

    sample_rate_ = av_info.timing.sample_rate;
    video_width_ = av_info.geometry.base_width;
    video_height_ = av_info.geometry.base_height;
    video_pitch_ = video_width_ * 4; 
    
    if (av_info.geometry.aspect_ratio > 0.0) {
        aspect_ratio_ = av_info.geometry.aspect_ratio;
    } else {
        aspect_ratio_ = (double)video_width_ / video_height_;
    }

    video_buffer_.resize(video_pitch_ * video_height_);

    // Initialize OpenGL context for hardware-rendered cores
    if (hw_render_enabled_) {
        LogMessage("Initializing OpenGL context for HW rendering...");
        if (gl_context_.Init(video_width_, video_height_)) {
            // Release GL context from main thread immediately.
            // context_reset and retro_run will both happen on the worker thread.
            wglMakeCurrent(NULL, NULL);
            LogMessage("GL context created and released from main thread (ready for worker thread)");
        } else {
            LogMessage("ERROR: Failed to initialize OpenGL context");
            hw_render_enabled_ = false;
        }
    }

    LogMessage("Core initialized and ready to run");
    
    return true;
}

void LibretroCore::Unload() {
    LogMessage("Unload started");
    StopThread();

    // Cleanup GL context before unloading core
    if (hw_render_enabled_) {
        gl_context_.MakeCurrent();
        if (hw_render_cb_.context_destroy) {
            hw_render_cb_.context_destroy();
        }
        gl_context_.Destroy();
        hw_render_enabled_ = false;
        hw_render_cb_ = {};
    }

    if (game_loaded_ && retro_unload_game) {
        retro_unload_game();
        game_loaded_ = false;
    }
    if (retro_deinit) retro_deinit();
    if (dylib_) {
#ifdef _WIN32
        FreeLibrary(dylib_);
#else
        dlclose(dylib_);
#endif
        dylib_ = nullptr;
    }

    // Clear all function pointers to prevent dangling pointer crashes
    retro_init = nullptr;
    retro_deinit = nullptr;
    retro_api_version = nullptr;
    retro_get_system_info = nullptr;
    retro_get_system_av_info = nullptr;
    retro_set_environment = nullptr;
    retro_set_video_refresh = nullptr;
    retro_set_audio_sample = nullptr;
    retro_set_audio_sample_batch = nullptr;
    retro_set_input_poll = nullptr;
    retro_set_input_state = nullptr;
    retro_load_game = nullptr;
    retro_unload_game = nullptr;
    retro_reset = nullptr;
    retro_run = nullptr;
    retro_serialize_size = nullptr;
    retro_serialize = nullptr;
    retro_unserialize = nullptr;

    LogMessage("Unload finished");
}

void LibretroCore::Reset() {
    if (dylib_ && retro_reset) {
        retro_reset();
    }
}

std::vector<uint8_t> LibretroCore::SaveState() {
    if (!dylib_ || !retro_serialize_size || !retro_serialize) return {};
    
    size_t size = retro_serialize_size();
    if (size == 0) return {};
    
    std::vector<uint8_t> buffer(size);
    if (retro_serialize(buffer.data(), size)) {
        return buffer;
    }
    return {};
}

bool LibretroCore::LoadState(const std::vector<uint8_t>& state) {
    if (!dylib_ || !retro_unserialize || state.empty()) return false;
    bool success = retro_unserialize(state.data(), state.size());
    if (success) {
        ClearAudioBuffer(); 
    }
    return success;
}

void LibretroCore::RunFrame() {
    if (dylib_) {
        if (slow_motion_) {
            slow_motion_count_++;
            if (slow_motion_count_ % 2 != 0) return; 
        }

        retro_run();
        
        if (fast_forward_) {
            retro_run();
            retro_run();
        }
    }
}

void LibretroCore::ThreadLoop() {
    LogMessage("Core thread loop started");
    using namespace std::chrono;
    
    // Acquisition of GL context on this worker thread.
    // This MUST be on the same thread as retro_run.
    if (hw_render_enabled_ && gl_context_.IsInitialized()) {
        gl_context_.MakeCurrent();
        LogMessage("GL context acquired on worker thread");
        
        // Initial viewport setup
        glViewport(0, 0, video_width_, video_height_);
        
        if (hw_render_cb_.context_reset) {
            LogMessage("Calling core context_reset...");
            hw_render_cb_.context_reset();
            LogMessage("context_reset completed");
        }
    }

    int frame_count = 0;
    while (thread_running_) {
        auto start = high_resolution_clock::now();
        if (!is_paused_) {
            if (frame_count == 0) LogMessage("Executing first retro_run()...");
            
            // NAKED execution of retro_run.
            retro_run();

            if (frame_count == 0) LogMessage("First retro_run() completed successfully");

            // For HW-rendered cores, use double-buffered asynchronous readback
            if (hw_render_enabled_ && gl_context_.IsInitialized()) {
                // 1. Map and copy data from the PREVIOUS frame's PBO (if ready)
                int prev_index = (pbo_index_ + 1) % 2;
                
                std::lock_guard<std::mutex> lock(video_mutex_);
                size_t needed = (size_t)video_width_ * video_height_ * 4;
                if (video_buffer_.size() < needed) {
                    video_buffer_.resize(needed);
                }

                if (gl_context_.MapAndCopy(prev_index, video_buffer_.data(), video_width_, video_height_)) {
                    // GL renders bottom-up, we need top-down — flip vertically
                    size_t row_bytes = (size_t)video_width_ * 4;
                    std::vector<uint8_t> row(row_bytes);
                    for (unsigned y = 0; y < video_height_ / 2; y++) {
                        uint8_t* top = video_buffer_.data() + y * row_bytes;
                        uint8_t* bot = video_buffer_.data() + (video_height_ - 1 - y) * row_bytes;
                        memcpy(row.data(), top, row_bytes);
                        memcpy(top, bot, row_bytes);
                        memcpy(bot, row.data(), row_bytes);
                    }

                    if (frame_available_cb_) frame_available_cb_();
                }

                // 2. Trigger readback for the CURRENT frame into the current PBO
                gl_context_.TriggerReadback(pbo_index_, video_width_, video_height_);
                
                // 3. Cycle PBO index
                pbo_index_ = (pbo_index_ + 1) % 2;
            }
            frame_count++;
        }
        auto elapsed = high_resolution_clock::now() - start;
        
        auto sleep_time = milliseconds(16) - duration_cast<milliseconds>(elapsed);
        if (sleep_time.count() > 0) {
            std::this_thread::sleep_for(sleep_time);
        } else {
            std::this_thread::yield();
        }
    }
}

void LibretroCore::StartThread() {
    if (!thread_running_) {
        thread_running_ = true;
        is_paused_ = false;
        run_thread_ = std::thread(&LibretroCore::ThreadLoop, this);
    }
}

void LibretroCore::StopThread() {
    LogMessage("StopThread requested");
    if (thread_running_) {
        thread_running_ = false;
        LogMessage("Waiting for core thread to join...");
        if (run_thread_.joinable()) {
            run_thread_.join();
        }
        LogMessage("Core thread joined");
    }
}

void LibretroCore::Pause() {
    is_paused_ = true;
}

void LibretroCore::Resume() {
    is_paused_ = false;
}

void LibretroCore::UpdateInputState(unsigned port, unsigned id, bool pressed) {
    if (port < 2 && id < 16) {
        input_state_[port][id] = pressed;
    }
}

void LibretroCore::UpdateAnalogState(unsigned port, unsigned index, unsigned id, int16_t value) {
    if (port < 2 && index < 2 && id < 2) {
        analog_state_[port][index][id] = value;
    }
}





static void retro_log_printf_cb(enum retro_log_level level, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[4096];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    std::string level_str;
    switch (level) {
        case RETRO_LOG_DEBUG: level_str = "DEBUG"; break;
        case RETRO_LOG_INFO:  level_str = "INFO";  break;
        case RETRO_LOG_WARN:  level_str = "WARN";  break;
        case RETRO_LOG_ERROR: level_str = "ERROR"; break;
        default: level_str = "LOG"; break;
    }
    
    LogMessage(level_str + ": " + buf);
}

bool LibretroCore::retro_environment_cb(unsigned cmd, void *data) {
    if (!instance_) return false;

    LogMessage("ENV CALL [ID: " + std::to_string(cmd) + "]");

    switch (cmd) {
        case RETRO_ENVIRONMENT_SET_ROTATION: return true;
        case RETRO_ENVIRONMENT_GET_OVERSCAN: return true;
        case RETRO_ENVIRONMENT_SET_MESSAGE: {
             if (data) {
                const struct retro_message *msg = (const struct retro_message *)data;
                if (msg->msg) LogMessage("ENV: CORE MESSAGE: " + std::string(msg->msg));
             }
             return true;
        }
        case RETRO_ENVIRONMENT_SHUTDOWN: return true;
        case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL: return true;
        case RETRO_ENVIRONMENT_SET_VARIABLES: {
            // Parse core's variable definitions and extract the FIRST option as the default.
            // Format: "Description; option1|option2|option3"
            if (data) {
                const struct retro_variable *vars = (const struct retro_variable *)data;
                while (vars && vars->key) {
                    std::string key(vars->key);
                    if (vars->value) {
                        std::string desc(vars->value);
                        size_t semi = desc.find(';');
                        if (semi != std::string::npos && semi + 1 < desc.size()) {
                            std::string options_str = desc.substr(semi + 1);
                            // Trim leading whitespace
                            size_t start = options_str.find_first_not_of(" \t");
                            if (start != std::string::npos) {
                                options_str = options_str.substr(start);
                            }
                            // First option (before first '|') is the default
                            size_t pipe = options_str.find('|');
                            std::string default_val = (pipe != std::string::npos)
                                ? options_str.substr(0, pipe)
                                : options_str;
                            instance_->variable_defaults_[key] = default_val;
                            LogMessage("ENV: PARSED DEFAULT [" + key + "] = " + default_val);
                        }
                    }
                    vars++;
                }
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
            return true;

        // --- Core Options v0 API (used by Mupen64Plus-Next) ---
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS: {
            // Parse retro_core_option_definition array to extract defaults
            if (data) {
                const struct retro_core_option_definition *opts = 
                    (const struct retro_core_option_definition *)data;
                while (opts && opts->key) {
                    std::string key(opts->key);
                    std::string default_val;
                    if (opts->default_value) {
                        default_val = opts->default_value;
                    } else if (opts->values[0].value) {
                        default_val = opts->values[0].value;
                    }
                    if (!default_val.empty()) {
                        instance_->variable_defaults_[key] = default_val;
                        LogMessage("ENV: CORE_OPT DEFAULT [" + key + "] = " + default_val);
                    }
                    opts++;
                }
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
            // Parse the US (English) definitions from the intl struct
            if (data) {
                const struct retro_core_options_intl *intl = 
                    (const struct retro_core_options_intl *)data;
                if (intl->us) {
                    const struct retro_core_option_definition *opts = intl->us;
                    while (opts && opts->key) {
                        std::string key(opts->key);
                        std::string default_val;
                        if (opts->default_value) {
                            default_val = opts->default_value;
                        } else if (opts->values[0].value) {
                            default_val = opts->values[0].value;
                        }
                        if (!default_val.empty()) {
                            instance_->variable_defaults_[key] = default_val;
                            LogMessage("ENV: CORE_OPT_INTL DEFAULT [" + key + "] = " + default_val);
                        }
                        opts++;
                    }
                }
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
        case 8388611: { // RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION_PRIVATE
            if (data) *(unsigned*)data = 2; // Report Version 2 support
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
            // Parse retro_core_options_v2 to extract defaults
            if (data) {
                const struct retro_core_options_v2 *opts = 
                    (const struct retro_core_options_v2 *)data;
                if (opts->definitions) {
                    const struct retro_core_option_v2_definition *def = opts->definitions;
                    while (def && def->key) {
                        std::string key(def->key);
                        if (def->default_value) {
                            instance_->variable_defaults_[key] = def->default_value;
                            LogMessage("ENV: CORE_OPT_V2 DEFAULT [" + key + "] = " + def->default_value);
                        }
                        def++;
                    }
                }
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
            if (data) {
                const struct retro_core_options_v2_intl *intl = 
                    (const struct retro_core_options_v2_intl *)data;
                if (intl->us && intl->us->definitions) {
                    const struct retro_core_option_v2_definition *def = intl->us->definitions;
                    while (def && def->key) {
                        std::string key(def->key);
                        if (def->default_value) {
                            instance_->variable_defaults_[key] = def->default_value;
                            LogMessage("ENV: CORE_OPT_V2_INTL DEFAULT [" + key + "] = " + def->default_value);
                        }
                        def++;
                    }
                }
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
            return true;
        case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION:
            if (data) *(unsigned*)data = 1;
            return true;
        case RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION:
            if (data) *(unsigned*)data = 1;
            return true;
        case RETRO_ENVIRONMENT_GET_INPUT_MAX_USERS:
            if (data) *(unsigned*)data = 1;
            return true;
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
            if (data) {
                struct retro_log_callback *cb = (struct retro_log_callback *)data;
                cb->log = retro_log_printf_cb;
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_CPU_FEATURES: {
            if (data) {
                uint64_t features = 0;
                #ifdef _M_X64
                features |= RETRO_SIMD_SSE | RETRO_SIMD_SSE2 | RETRO_SIMD_SSE3;
                #endif
                *(uint64_t*)data = features;
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_PERF_INTERFACE: {
            if (data) {
                struct retro_perf_callback *cb = (struct retro_perf_callback *)data;
                cb->get_time_usec = []() -> retro_time_t { return (retro_time_t)0; };
                cb->get_cpu_features = []() -> uint64_t { return (uint64_t)0; };
                cb->get_perf_counter = []() -> retro_perf_tick_t { return (retro_perf_tick_t)0; };
                cb->perf_register = [](struct retro_perf_counter*) {};
                cb->perf_start = [](struct retro_perf_counter*) {};
                cb->perf_stop = [](struct retro_perf_counter*) {};
                cb->perf_log = []() {};
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE: {
            if (data) {
                struct retro_rumble_interface *iface = (struct retro_rumble_interface *)data;
                iface->set_rumble_state = [](unsigned port, enum retro_rumble_effect effect, uint16_t strength) -> bool { return false; };
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_AUDIO_CALLBACK: {
            if (data) instance_->audio_cb_ = *(const struct retro_audio_callback*)data;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK: {
            if (data) instance_->frame_time_cb_ = *(const struct retro_frame_time_callback*)data;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VFS_INTERFACE: {
            // Minimal VFS implementation using standard C library calls.
            // Some cores require this to load internal configuration files.
            static struct retro_vfs_interface vfs = {
                // get_path
                [](struct retro_vfs_file_handle* stream) -> const char* { return nullptr; },
                // open
                [](const char* path, unsigned mode, unsigned hints) -> struct retro_vfs_file_handle* {
                    if (!path || !*path) return nullptr;
                    const char* mode_str = (mode == RETRO_VFS_FILE_ACCESS_READ) ? "rb" : "wb";
                    FILE* f = nullptr;
                    fopen_s(&f, path, mode_str);
                    return (struct retro_vfs_file_handle*)f;
                },
                // close
                [](struct retro_vfs_file_handle* stream) -> int {
                    if (!stream) return -1;
                    return fclose((FILE*)stream);
                },
                // size
                [](struct retro_vfs_file_handle* stream) -> int64_t {
                    if (!stream) return 0;
                    FILE* f = (FILE*)stream;
                    long cur = ftell(f);
                    fseek(f, 0, SEEK_END);
                    long size = ftell(f);
                    fseek(f, cur, SEEK_SET);
                    return size;
                },
                // tell
                [](struct retro_vfs_file_handle* stream) -> int64_t {
                    if (!stream) return -1;
                    return ftell((FILE*)stream);
                },
                // seek
                [](struct retro_vfs_file_handle* stream, int64_t offset, int seek_position) -> int64_t {
                    if (!stream) return -1;
                    int whence = SEEK_SET;
                    if (seek_position == RETRO_VFS_SEEK_POSITION_CURRENT) whence = SEEK_CUR;
                    else if (seek_position == RETRO_VFS_SEEK_POSITION_END) whence = SEEK_END;
                    return fseek((FILE*)stream, (long)offset, whence);
                },
                // read
                [](struct retro_vfs_file_handle* stream, void* s, uint64_t len) -> int64_t {
                    if (!stream || !s) return -1;
                    return fread(s, 1, (size_t)len, (FILE*)stream);
                },
                // write
                [](struct retro_vfs_file_handle* stream, const void* s, uint64_t len) -> int64_t {
                    if (!stream || !s) return -1;
                    return fwrite(s, 1, (size_t)len, (FILE*)stream);
                },
                // flush
                [](struct retro_vfs_file_handle* stream) -> int {
                    if (!stream) return -1;
                    return fflush((FILE*)stream);
                },
                // remove
                [](const char* path) -> int { return remove(path); },
                // rename
                [](const char* old_path, const char* new_path) -> int { return rename(old_path, new_path); }
            };
            if (data) {
                struct retro_vfs_interface_info* info = (struct retro_vfs_interface_info*)data;
                if (info->required_interface_version <= 1) {
                    info->iface = &vfs;
                    return true;
                }
            }
            return false;
        }
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY: {
            if (data) {
                if (!instance_->system_path_.empty()) {
                    std::string path = instance_->system_path_;
                    std::replace(path.begin(), path.end(), '/', '\\');
                    *(const char**)data = instance_->system_path_.c_str();
                    LogMessage("ENV: GET_DIR -> " + path);
                } else {
                    *(const char**)data = ".";
                }
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            const retro_pixel_format *fmt = (retro_pixel_format *)data;
            instance_->pixel_format_ = *fmt;
            LogMessage("ENV: SET_PIXEL_FORMAT -> " + std::to_string(*fmt));
            return true;
        }
        case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
            if (data) *(bool*)data = true;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            if (data) {
                struct retro_variable *var = (struct retro_variable *)data;
                if (var->key) {
                    std::string key(var->key);
                    const char* val = NULL;
                    
                    // --- ParaLLEl N64 Software Rendering Overrides ---
                    // Variable names MUST match exactly what the core registers in SET_VARIABLES.
                    if (key == "parallel-n64-gfxplugin") val = "angrylion";
                    else if (key == "parallel-n64-rspplugin") val = "cxd4";
                    else if (key == "parallel-n64-parallel-rdp") val = "disabled";
                    else if (key == "parallel-n64-angrylion-multithread") val = "all threads";
                    else if (key == "parallel-n64-disable_expmem") val = "enabled";
                    else if (key == "parallel-n64-cpucore") val = "dynamic_recompiler";
                    else if (key == "parallel-n64-audio-buffer-size") val = "2048";
                    else if (key == "parallel-n64-screensize") val = "640x480";
                    
                    // --- Mupen64Plus-Next Overrides ---
                    // Force GLideN64 (OpenGL) renderer since we provide an OpenGL context.
                    // The Vulkan build defaults to ParaLLEl RDP which would crash.
                    else if (key == "mupen64plus-rdp-plugin") val = "gliden64";
                    else if (key == "mupen64plus-rsp-plugin") val = "hle";
                    else if (key == "mupen64plus-cpucore") val = "dynamic_recompiler";
                    else if (key == "mupen64plus-43screensize") val = "640x480";
                    else if (key == "mupen64plus-aspect") val = "4:3";
                    else if (key == "mupen64plus-ForceDisableExtraMem") val = "False";
                    else if (key == "mupen64plus-Framerate") val = "Original";
                    
                    if (val) {
                        var->value = val;
                        LogMessage("ENV: GET_VARIABLE [" + key + "] -> " + val + " (Forced)");
                        return true;
                    }

                    // --- Use parsed defaults from SET_VARIABLES ---
                    auto it = instance_->variable_defaults_.find(key);
                    if (it != instance_->variable_defaults_.end()) {
                        var->value = it->second.c_str();
                        LogMessage("ENV: GET_VARIABLE [" + key + "] -> " + it->second + " (Parsed Default)");
                        return true;
                    }
                    
                    LogMessage("ENV: GET_VARIABLE [" + key + "] -> NULL (Unknown)");
                }
                var->value = NULL;
            }
            return false;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
            if (data) *(bool*)data = false;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME: return true;
        case RETRO_ENVIRONMENT_SET_HW_RENDER: {
            if (data) {
                auto *hw = (retro_hw_render_callback*)data;
                const char* ctx_name = "unknown";
                switch (hw->context_type) {
                    case RETRO_HW_CONTEXT_OPENGL: ctx_name = "OpenGL 2.x"; break;
                    case RETRO_HW_CONTEXT_OPENGLES2: ctx_name = "OpenGL ES 2.0"; break;
                    case RETRO_HW_CONTEXT_OPENGL_CORE: ctx_name = "OpenGL Core"; break;
                    case RETRO_HW_CONTEXT_OPENGLES3: ctx_name = "OpenGL ES 3.0"; break;
                    case RETRO_HW_CONTEXT_OPENGLES_VERSION: ctx_name = "OpenGL ES Version"; break;
                    case RETRO_HW_CONTEXT_VULKAN: ctx_name = "Vulkan"; break;
                    default: break;
                }
                LogMessage("ENV: SET_HW_RENDER requested context: " + std::string(ctx_name));

                // Accept any OpenGL variant
                if (hw->context_type != RETRO_HW_CONTEXT_VULKAN) {
                    hw->get_current_framebuffer = gl_get_framebuffer_cb;
                    hw->get_proc_address = gl_get_proc_address_cb;
                    instance_->hw_render_cb_ = *hw;
                    instance_->hw_render_enabled_ = true;
                    LogMessage("ENV: SET_HW_RENDER ACCEPTED");
                    return true;
                }
                LogMessage("ENV: SET_HW_RENDER REJECTED (Vulkan not supported)");
            }
            return false; 
        }
        case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE: {
            if (data) {
                instance_->hw_render_negotiation_ = *(const struct retro_hw_render_context_negotiation_interface*)data;
                LogMessage("ENV: SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE ACCEPTED");
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_LANGUAGE: {
            if (data) *(unsigned*)data = RETRO_LANGUAGE_ENGLISH;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_GEOMETRY: {
            if (data) {
                struct retro_game_geometry *geom = (struct retro_game_geometry *)data;
                LogMessage("ENV: SET_GEOMETRY -> " + std::to_string(geom->base_width) + "x" + std::to_string(geom->base_height));
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_INPUT_DEVICE_CAPABILITIES: {
            if (data) *(uint64_t*)data = (1 << RETRO_DEVICE_JOYPAD) | (1 << RETRO_DEVICE_ANALOG);
            return true;
        }
        case RETRO_ENVIRONMENT_GET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_SUPPORT: {
            if (data) *(bool*)data = true;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE: {
            if (data) *(int*)data = 3; // Both audio and video enabled
            return true;
        }
        default:
            return false;
    }
}

void LibretroCore::retro_video_refresh_cb(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (!instance_ || !data) return;

    // When HW rendering is active, the core passes RETRO_HW_FRAME_BUFFER_VALID
    // (which is (void*)-1) instead of actual pixel data. The frame was already
    // rendered to the GL framebuffer; we read it back via glReadPixels in the
    // thread loop. Do NOT try to memcpy from this sentinel value!
    if (instance_->hw_render_enabled_ && data == RETRO_HW_FRAME_BUFFER_VALID) {
        // Update dimensions if they changed
        if (width != instance_->video_width_ || height != instance_->video_height_) {
            std::lock_guard<std::mutex> lock(instance_->video_mutex_);
            instance_->video_width_ = width;
            instance_->video_height_ = height;
            instance_->video_pitch_ = width * 4;
            instance_->video_buffer_.resize(instance_->video_pitch_ * height);
        }
        if (instance_->frame_available_cb_) {
            instance_->frame_available_cb_();
        }
        return;
    }

    std::lock_guard<std::mutex> lock(instance_->video_mutex_);

    
    if (width != instance_->video_width_ || height != instance_->video_height_) {
        instance_->video_width_ = width;
        instance_->video_height_ = height;
        instance_->video_pitch_ = width * 4;
        instance_->video_buffer_.resize(instance_->video_pitch_ * height);
    }

    uint8_t* dest = instance_->video_buffer_.data();

    
    
    
    for (unsigned y = 0; y < height; y++) {
        const uint8_t* src_row = (const uint8_t*)data + (y * pitch);
        uint32_t* dest_row = (uint32_t*)(dest + (y * instance_->video_pitch_));
        
        for (unsigned x = 0; x < width; x++) {
            if (instance_->pixel_format_ == RETRO_PIXEL_FORMAT_RGB565) {
                uint16_t pixel = *((uint16_t*)(src_row + (x * 2)));
                dest_row[x] = CONVERT_RGB565_TO_RGBA8888(pixel);
            } else if (instance_->pixel_format_ == RETRO_PIXEL_FORMAT_XRGB8888) {
                uint32_t pixel = *((uint32_t*)(src_row + (x * 4)));
                dest_row[x] = CONVERT_XRGB8888_TO_RGBA8888(pixel);
            } else {
                uint16_t pixel = *((uint16_t*)(src_row + (x * 2)));
                dest_row[x] = CONVERT_0RGB1555_TO_RGBA8888(pixel);
            }
        }
    }
    
    if (instance_->frame_available_cb_) {
        instance_->frame_available_cb_();
    }
}

void LibretroCore::retro_audio_sample_cb(int16_t left, int16_t right) {
    if (!instance_) return;
    std::lock_guard<std::mutex> lock(instance_->audio_mutex_);
    instance_->audio_buffer_.push_back(left);
    instance_->audio_buffer_.push_back(right);
}

size_t LibretroCore::retro_audio_sample_batch_cb(const int16_t *data, size_t frames) {
    if (!instance_ || !data) return 0;
    std::lock_guard<std::mutex> lock(instance_->audio_mutex_);
    instance_->audio_buffer_.insert(instance_->audio_buffer_.end(), data, data + frames * 2);
    return frames;
}

void LibretroCore::retro_input_poll_cb() {}

int16_t LibretroCore::retro_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (!instance_) return 0;
    
    if (device == RETRO_DEVICE_JOYPAD && port < 2 && id < 16) {
        return instance_->input_state_[port][id] ? 1 : 0;
    }
    
    if (device == RETRO_DEVICE_ANALOG && port < 2 && index < 2 && id < 2) {
        return instance_->analog_state_[port][index][id];
    }
    
    return 0;
}

