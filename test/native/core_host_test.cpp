#include "CoreHost.hpp"
#include <cassert>
#include <filesystem>
#include <iostream>

int main(int argc, char** argv) {
  assert(argc == 4);
  uint8_t pixel[4]{};
  vantage::CoreHost::convertPixel(0xF800, RETRO_PIXEL_FORMAT_RGB565, pixel);
  assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 255 && pixel[3] == 255);
  vantage::CoreHost::convertPixel(0x03E0, RETRO_PIXEL_FORMAT_0RGB1555, pixel);
  assert(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0);
  vantage::CoreHost::convertPixel(0x00123456, RETRO_PIXEL_FORMAT_XRGB8888, pixel);
  assert(pixel[0] == 0x56 && pixel[1] == 0x34 && pixel[2] == 0x12);
  vantage::CoreHost host;
  size_t videos = 0, audioFrames = 0;
  uint64_t hash = 0;
  host.video = [&](const uint8_t* data, unsigned w, unsigned h) {
    assert(w > 0 && h > 0); ++videos;
    hash = 1469598103934665603ULL;
    for (size_t i = 0; i < static_cast<size_t>(w) * h * 4; ++i) hash = (hash ^ data[i]) * 1099511628211ULL;
  };
  host.audio = [&](const int16_t*, size_t n) { audioFrames += n; };
  host.open(argv[1], argv[2], argv[3]);
  for (int i = 0; i < 120; ++i) host.run();
  assert(videos > 100 && audioFrames > 1000);
  auto blue = hash;
  host.buttons[0] = 1u << RETRO_DEVICE_ID_JOYPAD_A;
  for (int i = 0; i < 20; ++i) host.run();
  assert(hash != blue); // Button input must visibly change the generated game.
  auto state = host.saveState();
  assert(!state.empty());
  host.clearInput();
  for (int i = 0; i < 20; ++i) host.run();
  assert(hash == blue);
  assert(host.loadState(state.data(), state.size()));
  host.buttons[0] = 1u << RETRO_DEVICE_ID_JOYPAD_A;
  for (int i = 0; i < 20; ++i) host.run();
  assert(hash != blue);
  host.flushMemory();
  host.close();
  assert(!host.loaded());
  assert(std::filesystem::file_size(std::string(argv[2]) + ".srm") > 0);
  host.open(argv[1], argv[2], argv[3]);
  host.run(); host.reset(); host.close();
  bool rejected = false;
  try { host.open("/not-a-core", argv[2], argv[3]); } catch (...) { rejected = true; }
  assert(rejected && !host.loaded());
  std::cout << "Native core smoke test passed: pixels, audio, input, states, SRAM, reset and reload\n";
}
