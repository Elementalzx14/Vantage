#import "VantageEmulatorPlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#include "CoreHost.hpp"
#include <memory>

@implementation VantageEmulatorPlugin {
  NSObject<FlutterTextureRegistry>* _textures;
  int64_t _textureId;
  dispatch_queue_t _queue;
  dispatch_source_t _timer;
  std::unique_ptr<vantage::CoreHost> _core;
  NSLock* _pixelLock;
  CVPixelBufferRef _pixel;
  AVAudioEngine* _engine;
  AVAudioPlayerNode* _player;
  AVAudioFormat* _format;
  std::vector<int16_t> _samples;
  int _pendingAudio;
  NSUInteger _audioGeneration;
  bool _paused, _fast, _slow, _slowPhase, _interrupted;
  unsigned _frameCount;
  float _volume;
  NSDictionary<NSString*, NSString*>* _bundled;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  VantageEmulatorPlugin* plugin = [[self alloc] init];
  plugin->_textures = [registrar textures];
  plugin->_textureId = [plugin->_textures registerTexture:plugin];
  plugin->_queue = dispatch_queue_create("vantage.emulation", DISPATCH_QUEUE_SERIAL);
  plugin->_pixelLock = [[NSLock alloc] init];
  plugin->_core = std::make_unique<vantage::CoreHost>();
  plugin->_volume = 1;
  NSMutableDictionary* bundled = [NSMutableDictionary dictionary];
  for (NSString* core in @[@"fceumm", @"snes9x", @"gambatte", @"mgba"]) {
    NSString* binary = [[NSBundle mainBundle].privateFrameworksPath
      stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/%@", core, core]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:binary]) bundled[core] = binary;
  }
  plugin->_bundled = [bundled copy];
  FlutterMethodChannel* channel = [FlutterMethodChannel
    methodChannelWithName:@"com.retrostream.vantage/emulator" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:plugin channel:channel];
  [[NSNotificationCenter defaultCenter] addObserver:plugin selector:@selector(interruption:)
    name:AVAudioSessionInterruptionNotification object:nil];
}

- (CVPixelBufferRef)copyPixelBuffer {
  [_pixelLock lock];
  CVPixelBufferRef result = _pixel ? CVPixelBufferRetain(_pixel) : nullptr;
  [_pixelLock unlock];
  return result;
}

- (void)publishVideo:(const uint8_t*)bytes width:(unsigned)width height:(unsigned)height {
  CVPixelBufferRef next = nullptr;
  NSDictionary* attrs = @{(NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{},
                          (NSString*)kCVPixelBufferMetalCompatibilityKey: @YES};
  if (CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      (__bridge CFDictionaryRef)attrs, &next) != kCVReturnSuccess) return;
  CVPixelBufferLockBaseAddress(next, 0);
  auto* dst = static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(next));
  size_t stride = CVPixelBufferGetBytesPerRow(next);
  for (unsigned y = 0; y < height; ++y) std::memcpy(dst + y * stride, bytes + y * width * 4, width * 4);
  CVPixelBufferUnlockBaseAddress(next, 0);
  [_pixelLock lock];
  CVPixelBufferRef previous = _pixel;
  _pixel = next;
  [_pixelLock unlock];
  if (previous) CVPixelBufferRelease(previous);
  dispatch_async(dispatch_get_main_queue(), ^{ [self->_textures textureFrameAvailable:self->_textureId]; });
}

- (void)clearAudio {
  ++_audioGeneration;
  [_player stop];
  _pendingAudio = 0;
  _samples.clear();
}

- (void)setupAudio {
  [self clearAudio];
  [_engine stop];
  AVAudioSession* session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
  [session setPreferredIOBufferDuration:0.01 error:nil];
  NSError* error = nil;
  if (![session setActive:YES error:&error])
    throw std::runtime_error("Cannot activate game audio");
  _engine = [[AVAudioEngine alloc] init];
  _player = [[AVAudioPlayerNode alloc] init];
  _format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:_core->sampleRate channels:2];
  [_engine attachNode:_player];
  [_engine connect:_player to:_engine.mainMixerNode format:_format];
  _player.volume = _volume;
  if (![_engine startAndReturnError:&error]) throw std::runtime_error("Cannot start game audio");
  [_player play];
}

- (void)playAudio {
  size_t frames = _samples.size() / 2;
  if (!frames || _pendingAudio >= 6 || _fast || _slow || _interrupted) { _samples.clear(); return; }
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_format frameCapacity:(AVAudioFrameCount)frames];
  buffer.frameLength = (AVAudioFrameCount)frames;
  for (size_t i = 0; i < frames; ++i) {
    buffer.floatChannelData[0][i] = _samples[i * 2] / 32768.0f;
    buffer.floatChannelData[1][i] = _samples[i * 2 + 1] / 32768.0f;
  }
  _samples.clear();
  ++_pendingAudio;
  NSUInteger generation = _audioGeneration;
  __weak VantageEmulatorPlugin* weakSelf = self;
  [_player scheduleBuffer:buffer completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
    completionHandler:^(AVAudioPlayerNodeCompletionCallbackType type) {
      VantageEmulatorPlugin* strong = weakSelf;
      if (!strong) return;
      dispatch_async(strong->_queue, ^{
        if (generation == strong->_audioGeneration) --strong->_pendingAudio;
      });
    }];
}

- (void)tick {
  if (!_core->loaded() || _paused || _interrupted) return;
  // Flutter's gamepads plugin, touch and keyboard send input through the channel.
  if (_slow) { _slowPhase = !_slowPhase; if (_slowPhase) return; }
  int frames = _fast ? 3 : 1;
  for (int i = 0; i < frames; ++i) _core->run();
  [self playAudio];
  if (++_frameCount >= static_cast<unsigned>(_core->fps * 30)) {
    _core->flushMemory(); _frameCount = 0;
  }
}

- (void)startTimer {
  if (_timer) dispatch_source_cancel(_timer);
  _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
  uint64_t interval = (uint64_t)(NSEC_PER_SEC / _core->fps);
  dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, interval), interval, interval / 20);
  __weak VantageEmulatorPlugin* weakSelf = self;
  dispatch_source_set_event_handler(_timer, ^{ [weakSelf tick]; });
  dispatch_resume(_timer);
}

- (void)stop {
  if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
  _core->close();
  [self clearAudio];
  [_engine stop];
  [_pixelLock lock];
  if (_pixel) { CVPixelBufferRelease(_pixel); _pixel = nullptr; }
  [_pixelLock unlock];
  _paused = _fast = _slow = _slowPhase = _interrupted = false;
  _frameCount = 0;
}

- (void)interruption:(NSNotification*)note {
  BOOL began = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan;
  dispatch_async(_queue, ^{
    self->_interrupted = began;
    if (began) { self->_core->clearInput(); self->_core->flushMemory(); [self clearAudio]; }
    else if (self->_core->loaded() && !self->_paused) {
      try { [self setupAudio]; } catch (...) { self->_interrupted = true; }
    }
  });
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"getBundledCores"]) { result(_bundled); return; }
  if ([call.method isEqualToString:@"getCoreLicenses"]) {
    NSMutableDictionary* licenses = [NSMutableDictionary dictionary];
    for (NSString* key in _bundled) {
      NSString* path = [[NSBundle mainBundle] pathForResource:key ofType:@"txt" inDirectory:@"CoreLicenses"];
      licenses[key] = path ? ([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"") : @"";
    }
    result(licenses); return;
  }
  dispatch_async(_queue, ^{
    FlutterResult reply = ^(id value) { dispatch_async(dispatch_get_main_queue(), ^{ result(value); }); };
    NSDictionary* args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
    NSString* method = call.method;
    try {
      if ([method isEqualToString:@"launch"]) {
        [self stop];
        NSString* path = args[@"corePath"], *rom = args[@"romPath"], *system = args[@"systemPath"];
        if (![path isKindOfClass:NSString.class] || ![self->_bundled.allValues containsObject:path] ||
            ![rom isKindOfClass:NSString.class] || ![system isKindOfClass:NSString.class])
          throw std::runtime_error("Invalid bundled core or game path");
        __weak VantageEmulatorPlugin* weakSelf = self;
        self->_core->video = [weakSelf](const uint8_t* b, unsigned w, unsigned h) {
          [weakSelf publishVideo:b width:w height:h];
        };
        self->_core->audio = [weakSelf](const int16_t* b, size_t n) {
          VantageEmulatorPlugin* strong = weakSelf;
          if (strong && b && n <= 192000 && strong->_samples.size() + n * 2 <= 384000)
            strong->_samples.insert(strong->_samples.end(), b, b + n * 2);
        };
        self->_core->open(path.UTF8String, rom.UTF8String, system.UTF8String);
        [self setupAudio];
        [self startTimer];
        reply(@(self->_textureId));
      } else if ([method isEqualToString:@"stop"]) { [self stop]; reply(nil);
      } else if ([method isEqualToString:@"pause"]) {
        self->_paused = true; self->_core->clearInput(); self->_core->flushMemory(); [self clearAudio]; reply(nil);
      } else if ([method isEqualToString:@"resume"]) {
        if (self->_core->loaded() && !self->_interrupted) [self setupAudio];
        self->_paused = false; reply(nil);
      } else if ([method isEqualToString:@"reset"]) { self->_core->reset(); [self clearAudio]; [self->_player play]; reply(nil);
      } else if ([method isEqualToString:@"getAspectRatio"]) { reply(@(self->_core->aspectRatio));
      } else if ([method isEqualToString:@"saveState"]) {
        auto bytes = self->_core->saveState();
        if (bytes.empty()) throw std::runtime_error("This core could not save its state");
        self->_core->flushMemory();
        reply([FlutterStandardTypedData typedDataWithBytes:[NSData dataWithBytes:bytes.data() length:bytes.size()]]);
      } else if ([method isEqualToString:@"loadState"]) {
        id value = args[@"state"];
        NSData* bytes = [value isKindOfClass:FlutterStandardTypedData.class] ? [value data] : nil;
        bool ok = bytes && self->_core->loadState(static_cast<const uint8_t*>(bytes.bytes), bytes.length);
        [self clearAudio]; if (!self->_paused) [self->_player play]; reply(@(ok));
      } else if ([method isEqualToString:@"keyDown"] || [method isEqualToString:@"keyUp"]) {
        int key = [args[@"keyCode"] intValue];
        if (key >= 0 && key < 16) {
          if ([method isEqualToString:@"keyDown"]) self->_core->buttons[0] |= 1u << key;
          else self->_core->buttons[0] &= ~(1u << key);
        }
        reply(nil);
      } else if ([method isEqualToString:@"setAnalog"]) {
        int index = [args[@"index"] intValue], axis = [args[@"id"] intValue];
        if (index >= 0 && index < 2 && axis >= 0 && axis < 2)
          self->_core->analog[0][index][axis] = std::clamp([args[@"value"] intValue], -32767, 32767);
        reply(nil);
      } else if ([method isEqualToString:@"setVolume"]) {
        self->_volume = std::clamp([call.arguments floatValue], 0.0f, 1.0f);
        self->_player.volume = self->_volume; reply(nil);
      } else if ([method isEqualToString:@"setFastForward"] || [method isEqualToString:@"setSlowMotion"]) {
        if ([method isEqualToString:@"setFastForward"]) self->_fast = [call.arguments boolValue];
        else self->_slow = [call.arguments boolValue];
        reply(nil);
      } else if ([method isEqualToString:@"resetMappingMode"]) { self->_core->clearInput(); reply(nil);
      } else { reply(FlutterMethodNotImplemented); }
    } catch (const std::exception& error) {
      if ([method isEqualToString:@"launch"]) [self stop];
      reply([FlutterError errorWithCode:@"IOS_EMULATOR" message:[NSString stringWithUTF8String:error.what()] details:nil]);
    }
  });
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  dispatch_sync(_queue, ^{ [self stop]; });
  [_textures unregisterTexture:_textureId];
}
@end
