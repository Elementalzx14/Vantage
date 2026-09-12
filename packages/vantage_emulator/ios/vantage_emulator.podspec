Pod::Spec.new do |s|
  s.name = 'vantage_emulator'
  s.version = '0.1.0'
  s.summary = 'Vantage iOS libretro host'
  s.description = 'Software video, audio, controls and save support for bundled libretro cores.'
  s.homepage = 'https://github.com/Elementalzx14/Vantage'
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = 'Vantage contributors'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,hpp,mm,cpp}'
  s.public_header_files = 'Classes/VantageEmulatorPlugin.h'
  s.dependency 'Flutter'
  s.frameworks = 'AVFoundation', 'CoreVideo', 'GameController'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17' }
end
