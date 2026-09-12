const iosBundledCoreIds = {'fceumm', 'snes9x', 'gambatte', 'mgba'};

class CoreEntry {
  final String id;
  final String displayName;
  final List<String> extensions;
  final String system;
  final List<String>? platforms; 

  
  final String fileName; 
  final Map<String, String>? overrides;

  const CoreEntry({
    required this.id,
    required this.displayName,
    required this.extensions,
    required this.fileName,
    required this.system,
    this.platforms,
    this.overrides,
  });

  bool supports(String platform) {
    // iOS needs bundled, signed cores and its own native emulator backend.
    if (platform == 'ios') return iosBundledCoreIds.contains(id);
    if (platforms == null) return true;
    return platforms!.contains(platform);
  }

  static const _root = 'https://buildbot.libretro.com/nightly';

  String _getFileName(String platform) {
    if (overrides != null && overrides!.containsKey(platform)) {
      return overrides![platform]!;
    }

    return switch (platform) {
      'android' => fileName,
      'windows' => _desktopFileName('.dll'),
      'linux'   => _desktopFileName('.so'),
      'macos'   => _desktopFileName('.dylib'),
      _         => fileName,
    };
  }

  String downloadUrl({
    required String platform,
    String arch = 'x86_64',
  }) {
    if (platform == 'ios') {
      throw UnsupportedError('iOS cores must be bundled with the app.');
    }
    final file = _getFileName(platform);

    return switch (platform) {
      'android' => '$_root/android/latest/$arch/$file',
      'windows' => '$_root/windows/$arch/latest/$file',
      'linux'   => '$_root/linux/$arch/latest/$file',
      'macos'   => '$_root/apple/osx/latest/$file',
      _         => '$_root/android/latest/arm64-v8a/$file',
    };
  }

  String installedName(String platform) {
    final zipFile = _getFileName(platform);
    return zipFile.replaceAll('.zip', '');
  }

  String _desktopFileName(String ext) {
    final base = fileName
        .replaceAll('_android.so.zip', '')
        .replaceAll('.so.zip', '')
        .replaceAll('.dll.zip', '')
        .replaceAll('.dylib.zip', '');
    return '$base$ext.zip';
  }
}

const coreCatalog = <CoreEntry>[
  
  CoreEntry(id: 'fceumm',     displayName: 'FCEUmm',           extensions: ['nes','fds','unf','unif'],          fileName: 'fceumm_libretro_android.so.zip', system: 'NES'),
  CoreEntry(id: 'nestopia',   displayName: 'Nestopia UE',       extensions: ['nes','fds','unf','unif'],          fileName: 'nestopia_libretro_android.so.zip', system: 'NES'),
  CoreEntry(id: 'mesen',      displayName: 'Mesen',             extensions: ['nes','fds','unf','unif','nsf'],    fileName: 'mesen_libretro_android.so.zip', system: 'NES'),
  
  CoreEntry(id: 'snes9x',     displayName: 'Snes9x',           extensions: ['sfc','smc','fig','bs','st','swc'], fileName: 'snes9x_libretro_android.so.zip', system: 'SNES'),
  CoreEntry(id: 'snes9x2010', displayName: 'Snes9x 2010',      extensions: ['sfc','smc','fig','bs','st','swc'], fileName: 'snes9x2010_libretro_android.so.zip', system: 'SNES'),
  CoreEntry(id: 'bsnes',      displayName: 'bsnes',            extensions: ['sfc','smc'],                      fileName: 'bsnes_libretro_android.so.zip', system: 'SNES'),
  
  CoreEntry(
    id: 'mupen64plus_next', 
    displayName: 'Mupen64Plus Next', 
    extensions: ['n64','v64','z64','u1','ndd'], 
    fileName: 'mupen64plus_next_libretro_android.so.zip', 
    overrides: {
      'windows': 'mupen64plus_next_libretro.dll.zip',
      'linux':   'mupen64plus_next_libretro.so.zip',
      'macos':   'mupen64plus_next_libretro.dylib.zip',
    },
    platforms: ['windows', 'linux', 'macos'], 
    system: 'Nintendo 64'
  ),
  CoreEntry(id: 'mupen64plus_next_gles3', displayName: 'Mupen64Plus Next GLES3', extensions: ['n64','v64','z64','u1','ndd'], fileName: 'mupen64plus_next_gles3_libretro_android.so.zip', platforms: ['android'], system: 'Nintendo 64'),
  CoreEntry(id: 'mupen64plus_next_gles2', displayName: 'Mupen64Plus Next GLES2', extensions: ['n64','v64','z64','u1','ndd'], fileName: 'mupen64plus_next_gles2_libretro_android.so.zip', platforms: ['android'], system: 'Nintendo 64'),
  CoreEntry(id: 'parallel_n64', displayName: 'ParaLLEl N64',           extensions: ['n64','v64','z64','u1','ndd'],     fileName: 'parallel_n64_libretro_android.so.zip', system: 'Nintendo 64'),
  
  CoreEntry(id: 'dolphin',    displayName: 'Dolphin',    extensions: ['gcm','iso','wbfs','ciso','gcz','elf','dol','rvz'], fileName: 'dolphin_libretro_android.so.zip', system: 'GameCube / Wii'),
  
  CoreEntry(id: 'gambatte',   displayName: 'Gambatte',         extensions: ['gb','gbc','dmg'],                 fileName: 'gambatte_libretro_android.so.zip', system: 'Game Boy / Color'),
  CoreEntry(id: 'sameboy',    displayName: 'SameBoy',          extensions: ['gb','gbc','dmg'],                 fileName: 'sameboy_libretro_android.so.zip', system: 'Game Boy / Color'),
  CoreEntry(id: 'gearboy',    displayName: 'Gearboy',           extensions: ['gb','gbc','dmg','sgb'],           fileName: 'gearboy_libretro_android.so.zip', system: 'Game Boy / Color'),
  
  CoreEntry(id: 'mgba',       displayName: 'mGBA',             extensions: ['gba','agb','mb'],                 fileName: 'mgba_libretro_android.so.zip', system: 'Game Boy Advance'),
  CoreEntry(id: 'vba_next',   displayName: 'VBA Next',         extensions: ['gba','agb','mb'],                 fileName: 'vba_next_libretro_android.so.zip', system: 'Game Boy Advance'),
  
  CoreEntry(id: 'desmume',    displayName: 'DeSmuME',           extensions: ['nds','bin'],                      fileName: 'desmume_libretro_android.so.zip', system: 'Nintendo DS'),
  CoreEntry(id: 'melonds',    displayName: 'melonDS',           extensions: ['nds','bin'],                      fileName: 'melonds_libretro_android.so.zip', system: 'Nintendo DS'),
  CoreEntry(id: 'melondsds',  displayName: 'melonDS DS',        extensions: ['nds','bin'],                      fileName: 'melondsds_libretro_android.so.zip', system: 'Nintendo DS'),
  
  CoreEntry(id: 'citra',      displayName: 'Citra',              extensions: ['3ds','3dsx','cci','cxi','elf'],   fileName: 'citra_libretro_android.so.zip', system: 'Nintendo 3DS'),
  
  CoreEntry(id: 'genesis_plus_gx', displayName: 'Genesis Plus GX', extensions: ['md','gen','smd','sg','sms','gg','68k','chd','cue','iso','scd','32x'], fileName: 'genesis_plus_gx_libretro_android.so.zip', system: 'Genesis / SMS / GG'),
  CoreEntry(id: 'picodrive',  displayName: 'PicoDrive',        extensions: ['bin','gen','smd','md','32x','cue','iso','sms','68k'], fileName: 'picodrive_libretro_android.so.zip', system: 'Genesis / 32X / CD'),
  
  CoreEntry(id: 'mednafen_saturn', displayName: 'Mednafen Saturn', extensions: ['bin','cue','iso','mdf','chd','toc','m3u'], fileName: 'mednafen_saturn_libretro_android.so.zip', system: 'Sega Saturn'),
  CoreEntry(id: 'yabasanshiro', displayName: 'YabaSanshiro',   extensions: ['bin','cue','iso','mdf','chd'],    fileName: 'yabasanshiro_libretro_android.so.zip', system: 'Sega Saturn'),
  
  CoreEntry(id: 'flycast',    displayName: 'Flycast',          extensions: ['chd','cdi','iso','elf','cue','gdi','lst','bin','dat','zip','7z'], fileName: 'flycast_libretro_android.so.zip', system: 'Dreamcast'),

  CoreEntry(id: 'pcsx_rearmed', displayName: 'PCSX ReARMed',     extensions: ['bin','cue','img','mdf','pbp','toc','cbn','m3u','ccd','chd','iso'], fileName: 'pcsx_rearmed_libretro_android.so.zip', system: 'PlayStation'),
  CoreEntry(id: 'mednafen_psx', displayName: 'Mednafen PSX',     extensions: ['bin','cue','img','mdf','pbp','toc','cbn','m3u','ccd','chd'], fileName: 'mednafen_psx_libretro_android.so.zip', system: 'PlayStation'),
  CoreEntry(id: 'swanstation', displayName: 'SwanStation',       extensions: ['bin','cue','img','mdf','pbp','toc','cbn','m3u','ccd','chd','iso'], fileName: 'swanstation_libretro_android.so.zip', system: 'PlayStation'),
  
  CoreEntry(id: 'play',       displayName: 'Play!',        extensions: ['iso','elf','bin','cso'],          fileName: 'play_libretro_android.so.zip', system: 'PlayStation 2'),
  CoreEntry(id: 'ppsspp',     displayName: 'PPSSPP',            extensions: ['iso','cso','pbp','elf','prx'],    fileName: 'ppsspp_libretro_android.so.zip', system: 'PSP'),

  CoreEntry(id: 'fbneo',      displayName: 'FinalBurn Neo',     extensions: ['zip','7z'], fileName: 'fbneo_libretro_android.so.zip', system: 'Arcade'),
  CoreEntry(id: 'mame2003_plus', displayName: 'MAME 2003-Plus', extensions: ['zip'], fileName: 'mame2003_plus_libretro_android.so.zip', system: 'Arcade'),
  CoreEntry(id: 'mame2010',   displayName: 'MAME 2010',        extensions: ['zip'], fileName: 'mame2010_libretro_android.so.zip', system: 'Arcade'),

  CoreEntry(id: 'stella',     displayName: 'Stella',           extensions: ['a26','bin','rom'],                fileName: 'stella_libretro_android.so.zip', system: 'Atari 2600'),
  CoreEntry(id: 'prosystem',  displayName: 'ProSystem',        extensions: ['a78','bin'],                      fileName: 'prosystem_libretro_android.so.zip', system: 'Atari 7800'),
  CoreEntry(id: 'atari800',   displayName: 'Atari 800',         extensions: ['atr','xfd','atx','cas','bin','rom'], fileName: 'atari800_libretro_android.so.zip', system: 'Atari 8-bit'),
  CoreEntry(id: 'handy',      displayName: 'Handy',             extensions: ['lnx','o'],                        fileName: 'handy_libretro_android.so.zip', system: 'Atari Lynx'),

  CoreEntry(id: 'dosbox_pure', displayName: 'DOSBox Pure',      extensions: ['dos','exe','com','bat','conf','zip'], fileName: 'dosbox_pure_libretro_android.so.zip', system: 'DOS'),
  CoreEntry(id: 'vice_x64sc', displayName: 'VICE x64sc',        extensions: ['d64','d71','d80','d81','g64','t64','tap','prg','p00','crt','bin','zip'], fileName: 'vice_x64sc_libretro_android.so.zip', system: 'Commodore 64'),
  CoreEntry(id: 'puae',       displayName: 'PUAE (Amiga)',      extensions: ['adf','adz','dms','fdi','ipf','hdf','hvc','rp9','uae','m3u','zip'], fileName: 'puae_libretro_android.so.zip', system: 'Amiga'),
  CoreEntry(id: 'bluemsx',    displayName: 'blueMSX',           extensions: ['rom','mx1','mx2','col','dsk','cas','sc'], fileName: 'bluemsx_libretro_android.so.zip', system: 'MSX'),
  CoreEntry(id: 'fuse',       displayName: 'Fuse',              extensions: ['tzx','tap','z80','sna','dsk','trd','scl','szx','zip'], fileName: 'fuse_libretro_android.so.zip', system: 'ZX Spectrum'),

  CoreEntry(id: 'mednafen_pce_fast', displayName: 'Mednafen PCE Fast', extensions: ['pce','tg16','cue','ccd','chd','sgx'], fileName: 'mednafen_pce_fast_libretro_android.so.zip', system: 'TurboGrafx-16'),
  CoreEntry(id: 'mednafen_ngp', displayName: 'Mednafen NGP',    extensions: ['ngp','ngc','ngpc','npc'],         fileName: 'mednafen_ngp_libretro_android.so.zip', system: 'Neo Geo Pocket'),
  CoreEntry(id: 'mednafen_wswan', displayName: 'Mednafen WonderSwan', extensions: ['ws','wsc','pc2'],               fileName: 'mednafen_wswan_libretro_android.so.zip', system: 'WonderSwan'),
  CoreEntry(id: 'mednafen_vb', displayName: 'Mednafen VB',      extensions: ['vb'],                             fileName: 'mednafen_vb_libretro_android.so.zip', system: 'Virtual Boy'),
  CoreEntry(id: 'pokemini',   displayName: 'PokeMini',          extensions: ['min'],                            fileName: 'pokemini_libretro_android.so.zip', system: 'Pokemon Mini'),

  CoreEntry(id: 'scummvm',    displayName: 'ScummVM',          extensions: ['scummvm'],                        fileName: 'scummvm_libretro_android.so.zip', system: 'Engines'),
  CoreEntry(id: 'easyrpg',    displayName: 'EasyRPG',          extensions: ['ldb'],                            fileName: 'easyrpg_libretro_android.so.zip', system: 'Engines'),
  CoreEntry(id: 'prboom',     displayName: 'PrBoom (Doom)',    extensions: ['wad','iwad','pwad'],              fileName: 'prboom_libretro_android.so.zip', system: 'Engines'),
  
  CoreEntry(id: 'tic80',      displayName: 'TIC-80',           extensions: ['tic'],                            fileName: 'tic80_libretro_android.so.zip', system: 'Fantasy Consoles'),
  CoreEntry(id: 'retro8',     displayName: 'Retro8 (PICO-8)',   extensions: ['p8','png'],                       fileName: 'retro8_libretro_android.so.zip', system: 'Fantasy Consoles'),
];



String? resolveCore(String romPath, Set<String> installedCores) {
  final ext = romPath.split('.').last.toLowerCase();
  for (final entry in coreCatalog) {
    if (entry.extensions.contains(ext) && installedCores.contains(entry.id)) {
      return entry.id;
    }
  }
  return null;
}

