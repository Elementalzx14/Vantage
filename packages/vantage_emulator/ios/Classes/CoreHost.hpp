#pragma once
#include "libretro.h"
#include <dlfcn.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <functional>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

namespace vantage {
// All public methods and libretro callbacks run on one serial emulation queue.
// The Flutter texture consumer is synchronized separately by the iOS plugin.
class CoreHost {
 public:
  std::function<void(const uint8_t*, unsigned, unsigned)> video;
  std::function<void(const int16_t*, size_t)> audio;
  double fps = 60, sampleRate = 44100, aspectRatio = 4.0 / 3.0;
  std::array<uint16_t, 2> buttons{};
  int16_t analog[2][2][2]{};
  bool loaded() const { return loaded_; }

  void open(const std::string& library, const std::string& rom,
            const std::string& system) {
    close();
    if (active_ && active_ != this) throw std::runtime_error("Another core is active");
    active_ = this;
    system_ = system;
    romPath_ = rom;
    saveDir_ = rom.substr(0, rom.find_last_of('/'));
    try {
      handle_ = dlopen(library.c_str(), RTLD_NOW | RTLD_LOCAL);
      if (!handle_) throw std::runtime_error("Cannot load bundled core. Re-sign all embedded frameworks with the app.");
#define BIND(name) bind(name##_, #name)
      BIND(retro_init); BIND(retro_deinit); BIND(retro_api_version);
      BIND(retro_set_environment); BIND(retro_set_video_refresh);
      BIND(retro_set_audio_sample); BIND(retro_set_audio_sample_batch);
      BIND(retro_set_input_poll); BIND(retro_set_input_state);
      BIND(retro_set_controller_port_device); BIND(retro_get_system_info);
      BIND(retro_get_system_av_info); BIND(retro_load_game); BIND(retro_unload_game);
      BIND(retro_run); BIND(retro_reset); BIND(retro_serialize_size);
      BIND(retro_serialize); BIND(retro_unserialize);
      BIND(retro_get_memory_data); BIND(retro_get_memory_size);
#undef BIND
      if (retro_api_version_() != RETRO_API_VERSION) throw std::runtime_error("Unsupported core API");
      retro_set_environment_(environment);
      retro_set_video_refresh_(onVideo);
      retro_set_audio_sample_(onSample);
      retro_set_audio_sample_batch_(onAudio);
      retro_set_input_poll_([] {});
      retro_set_input_state_(onInput);
      retro_init_();
      initialized_ = true;
      retro_system_info info{};
      retro_get_system_info_(&info);
      retro_game_info game{};
      game.path = romPath_.c_str();
      if (!info.need_fullpath) {
        std::ifstream file(rom, std::ios::binary | std::ios::ate);
        if (!file || file.tellg() <= 0 || file.tellg() > 256 * 1024 * 1024)
          throw std::runtime_error("ROM is missing, empty or too large");
        rom_.resize(static_cast<size_t>(file.tellg()));
        file.seekg(0);
        if (!file.read(reinterpret_cast<char*>(rom_.data()), rom_.size()))
          throw std::runtime_error("Cannot read ROM");
        game.data = rom_.data(); game.size = rom_.size();
      }
      if (!retro_load_game_(&game)) throw std::runtime_error("Core could not open this ROM. Check format and required BIOS.");
      loaded_ = true;
      retro_set_controller_port_device_(0, RETRO_DEVICE_JOYPAD);
      retro_system_av_info av{};
      retro_get_system_av_info_(&av);
      fps = av.timing.fps; sampleRate = av.timing.sample_rate;
      if (!std::isfinite(fps) || fps < 1 || fps > 240 ||
          !std::isfinite(sampleRate) || sampleRate < 8000 || sampleRate > 192000)
        throw std::runtime_error("Invalid core timing");
      updateGeometry(av.geometry);
      readMemory(RETRO_MEMORY_SAVE_RAM, ".srm");
      readMemory(RETRO_MEMORY_RTC, ".rtc");
    } catch (...) { close(); throw; }
  }

  void run() { if (loaded_) retro_run_(); }
  void reset() { if (loaded_) retro_reset_(); }
  void clearInput() { buttons.fill(0); std::memset(analog, 0, sizeof(analog)); }
  std::vector<uint8_t> saveState() {
    if (!loaded_) return {};
    size_t size = retro_serialize_size_();
    if (!size || size > 64 * 1024 * 1024) return {};
    std::vector<uint8_t> state(size);
    if (!retro_serialize_(state.data(), size)) return {};
    return state;
  }
  bool loadState(const uint8_t* data, size_t size) {
    return loaded_ && size && size <= 64 * 1024 * 1024 && retro_unserialize_(data, size);
  }
  void flushMemory() {
    if (!loaded_) return;
    writeMemory(RETRO_MEMORY_SAVE_RAM, ".srm");
    writeMemory(RETRO_MEMORY_RTC, ".rtc");
  }
  void close() {
    if (loaded_) { flushMemory(); retro_unload_game_(); loaded_ = false; }
    if (initialized_) { retro_deinit_(); initialized_ = false; }
    if (handle_) { dlclose(handle_); handle_ = nullptr; }
    if (active_ == this) active_ = nullptr;
    rom_.clear(); pixels_.clear(); options_.clear(); clearInput();
    pixelFormat_ = RETRO_PIXEL_FORMAT_0RGB1555;
  }
  ~CoreHost() { close(); }

  static void convertPixel(uint32_t value, retro_pixel_format format, uint8_t* out) {
    unsigned r, g, b;
    if (format == RETRO_PIXEL_FORMAT_XRGB8888) {
      r = (value >> 16) & 255; g = (value >> 8) & 255; b = value & 255;
    } else if (format == RETRO_PIXEL_FORMAT_RGB565) {
      r = (value >> 11) & 31; g = (value >> 5) & 63; b = value & 31;
      r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2);
    } else {
      r = (value >> 10) & 31; g = (value >> 5) & 31; b = value & 31;
      r = (r << 3) | (r >> 2); g = (g << 3) | (g >> 2); b = (b << 3) | (b >> 2);
    }
    out[0] = b; out[1] = g; out[2] = r; out[3] = 255;
  }

 private:
  inline static CoreHost* active_ = nullptr;
  void* handle_ = nullptr;
  bool loaded_ = false, initialized_ = false;
  std::string system_, romPath_, saveDir_;
  std::vector<uint8_t> rom_, pixels_;
  std::map<std::string, std::string> options_;
  retro_pixel_format pixelFormat_ = RETRO_PIXEL_FORMAT_0RGB1555;
#define FN(name) decltype(&::name) name##_ = nullptr
  FN(retro_init); FN(retro_deinit); FN(retro_api_version);
  FN(retro_set_environment); FN(retro_set_video_refresh);
  FN(retro_set_audio_sample); FN(retro_set_audio_sample_batch);
  FN(retro_set_input_poll); FN(retro_set_input_state);
  FN(retro_set_controller_port_device); FN(retro_get_system_info);
  FN(retro_get_system_av_info); FN(retro_load_game); FN(retro_unload_game);
  FN(retro_run); FN(retro_reset); FN(retro_serialize_size);
  FN(retro_serialize); FN(retro_unserialize);
  FN(retro_get_memory_data); FN(retro_get_memory_size);
#undef FN
  template<class T> void bind(T& fn, const char* name) {
    fn = reinterpret_cast<T>(dlsym(handle_, name));
    if (!fn) throw std::runtime_error(std::string("Missing core function: ") + name);
  }
  void updateGeometry(const retro_game_geometry& g) {
    if (g.base_height) aspectRatio = g.aspect_ratio > 0
      ? g.aspect_ratio : static_cast<double>(g.base_width) / g.base_height;
  }
  void readMemory(unsigned type, const char* suffix) {
    size_t size = retro_get_memory_size_(type);
    void* data = retro_get_memory_data_(type);
    if (!data || !size) return;
    std::ifstream file(romPath_ + suffix, std::ios::binary | std::ios::ate);
    if (file && static_cast<size_t>(file.tellg()) == size) {
      file.seekg(0); file.read(static_cast<char*>(data), size);
    }
  }
  void writeMemory(unsigned type, const char* suffix) {
    size_t size = retro_get_memory_size_(type);
    void* data = retro_get_memory_data_(type);
    if (!data || !size || size > 64 * 1024 * 1024) return;
    std::string path = romPath_ + suffix, temp = path + ".tmp";
    std::ofstream file(temp, std::ios::binary | std::ios::trunc);
    file.write(static_cast<const char*>(data), size); file.close();
    if (file) std::rename(temp.c_str(), path.c_str());
  }
  static void onVideo(const void* data, unsigned width, unsigned height, size_t pitch) {
    auto* self = active_;
    if (!self || !data || data == RETRO_HW_FRAME_BUFFER_VALID || !width || !height ||
        width > 4096 || height > 4096) return;
    size_t bytes = self->pixelFormat_ == RETRO_PIXEL_FORMAT_XRGB8888 ? 4 : 2;
    if (pitch < width * bytes) return;
    self->pixels_.resize(static_cast<size_t>(width) * height * 4);
    for (unsigned y = 0; y < height; ++y) {
      const auto* row = static_cast<const uint8_t*>(data) + y * pitch;
      for (unsigned x = 0; x < width; ++x) {
        uint32_t pixel = 0; std::memcpy(&pixel, row + x * bytes, bytes);
        convertPixel(pixel, self->pixelFormat_, &self->pixels_[(y * width + x) * 4]);
      }
    }
    if (self->video) self->video(self->pixels_.data(), width, height);
  }
  static size_t onAudio(const int16_t* data, size_t frames) {
    if (active_ && active_->audio) active_->audio(data, frames);
    return frames;
  }
  static void onSample(int16_t l, int16_t r) { int16_t data[]{l,r}; onAudio(data, 1); }
  static int16_t onInput(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (!active_ || port >= 2) return 0;
    if (device == RETRO_DEVICE_JOYPAD) {
      if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return active_->buttons[port];
      return id < 16 && (active_->buttons[port] & (1u << id)) ? 1 : 0;
    }
    if (device == RETRO_DEVICE_ANALOG && index < 2 && id < 2)
      return active_->analog[port][index][id];
    return 0;
  }
  static bool environment(unsigned cmd, void* data) {
    auto* self = active_;
    if (!self) return false;
    switch (cmd) {
      case RETRO_ENVIRONMENT_GET_CAN_DUPE: *static_cast<bool*>(data) = true; return true;
      case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        auto f = *static_cast<retro_pixel_format*>(data);
        if (f != RETRO_PIXEL_FORMAT_XRGB8888 && f != RETRO_PIXEL_FORMAT_RGB565 &&
            f != RETRO_PIXEL_FORMAT_0RGB1555) return false;
        self->pixelFormat_ = f; return true;
      }
      case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        *static_cast<const char**>(data) = self->system_.c_str(); return true;
      case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *static_cast<const char**>(data) = self->saveDir_.c_str(); return true;
      case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
        *static_cast<unsigned*>(data) = 0; return true;
      case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: *static_cast<bool*>(data) = false; return true;
      case RETRO_ENVIRONMENT_SET_VARIABLES: {
        for (auto* v = static_cast<retro_variable*>(data); v && v->key; ++v) {
          std::string values = v->value ? v->value : "";
          auto split = values.find(';');
          if (split == std::string::npos) continue;
          auto start = values.find_first_not_of(' ', split + 1);
          if (start == std::string::npos) continue;
          self->options_[v->key] = values.substr(start, values.find('|', start) - start);
        }
        return true;
      }
      case RETRO_ENVIRONMENT_GET_VARIABLE: {
        auto* v = static_cast<retro_variable*>(data);
        auto it = self->options_.find(v->key ? v->key : "");
        v->value = it == self->options_.end() ? nullptr : it->second.c_str();
        return v->value != nullptr;
      }
      case RETRO_ENVIRONMENT_SET_GEOMETRY:
        self->updateGeometry(*static_cast<retro_game_geometry*>(data)); return true;
      case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS: return true;
      case RETRO_ENVIRONMENT_GET_LANGUAGE: *static_cast<unsigned*>(data) = RETRO_LANGUAGE_ENGLISH; return true;
      case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
      case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
      case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME: return true;
      default: return false;
    }
  }
};
} // namespace vantage
