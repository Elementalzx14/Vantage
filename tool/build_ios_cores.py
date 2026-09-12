"""Build pinned iOS cores from source; never download executable cores at runtime."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'build/ios-cores'
MANIFEST = json.loads((ROOT / 'tool/ios_cores.json').read_text())


def run(args, cwd=ROOT):
    subprocess.run([str(a) for a in args], cwd=cwd, check=True)


def output(args, cwd=ROOT):
    return subprocess.check_output([str(a) for a in args], cwd=cwd, text=True).strip()


def source(core):
    src = OUT / 'src' / core['id']
    if not src.exists():
        src.mkdir(parents=True)
        run(['git', 'init', '-q'], src)
        run(['git', 'remote', 'add', 'origin', core['url']], src)
        run(['git', 'fetch', '--depth=1', 'origin', core['commit']], src)
        run(['git', 'checkout', '--detach', 'FETCH_HEAD'], src)
    assert output(['git', 'rev-parse', 'HEAD'], src) == core['commit']
    return src


def main():
    if sys.platform != 'darwin':
        raise SystemExit('Run this build on macOS with Xcode.')
    sdk = output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'])
    cc = f'xcrun --sdk iphoneos clang -arch arm64 -isysroot {sdk} -miphoneos-version-min=13.0'
    cxx = cc.replace('clang ', 'clang++ ')
    jobs = str(min(os.cpu_count() or 2, 6))
    for sub in ('Frameworks', 'CoreLicenses', 'Sources'):
        (OUT / sub).mkdir(parents=True, exist_ok=True)
    for core in MANIFEST:
        name = core['id']
        print(f'::group::Build {name}', flush=True)
        src = source(core)
        build = src / core['directory']
        if 'makefile' in core:
            run(['make', '-j' + jobs, '-f', core['makefile'], 'platform=ios-arm64',
                 f'IOSSDK={sdk}', f'CC={cc}', f'CXX={cxx}',
                 'MINVERSION=-miphoneos-version-min=13.0'], build)
            binary = build / f'{name}_libretro_ios.dylib'
        else:
            build = OUT / 'cmake' / name
            run(['cmake', '-S', src, '-B', build, '-DCMAKE_SYSTEM_NAME=iOS',
                 '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_SYSROOT=iphoneos',
                 '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0', '-DCMAKE_BUILD_TYPE=Release',
                 # Function probes must link; static archives falsely report missing
                 # functions (such as popcount32) as available on iOS.
                 '-DCMAKE_TRY_COMPILE_TARGET_TYPE=EXECUTABLE',
                 '-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO',
                 '-DBUILD_LIBRETRO=ON', '-DBUILD_QT=OFF', '-DBUILD_SDL=OFF',
                 '-DBUILD_GL=OFF', '-DBUILD_GLES2=OFF', '-DBUILD_GLES3=OFF',
                 '-DBUILD_SHARED=OFF', '-DBUILD_STATIC=OFF', '-DBUILD_LTO=OFF',
                 '-DUSE_FFMPEG=OFF', '-DUSE_PNG=OFF', '-DUSE_LIBZIP=OFF',
                 '-DUSE_MINIZIP=OFF', '-DUSE_SQLITE3=OFF', '-DUSE_LZMA=OFF',
                 '-DUSE_ELF=OFF', '-DUSE_LUA=OFF', '-DUSE_JSON_C=OFF',
                 '-DUSE_FREETYPE=OFF', '-DUSE_DISCORD_RPC=OFF', '-DENABLE_SCRIPTING=OFF'])
            run(['cmake', '--build', build, '--target', 'mgba_libretro', '--parallel', jobs])
            binary = build / 'mgba_libretro.dylib'
        framework = OUT / 'Frameworks' / f'{name}.framework'
        framework.mkdir(exist_ok=True)
        destination = framework / name
        shutil.copy2(binary, destination)
        run(['xcrun', 'lipo', destination, '-verify_arch', 'arm64'])
        run(['xcrun', 'install_name_tool', '-id', f'@rpath/{name}.framework/{name}', destination])
        with (framework / 'Info.plist').open('wb') as file:
            plistlib.dump({'CFBundleExecutable': name, 'CFBundleIdentifier': f'com.retrostream.core.{name}',
                          'CFBundleName': name, 'CFBundlePackageType': 'FMWK',
                          'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1',
                          'CFBundleSupportedPlatforms': ['iPhoneOS'], 'MinimumOSVersion': '13.0'}, file)
        # Sign the complete framework for inspection; Signulous replaces this signature.
        run(['codesign', '--force', '--sign', '-', framework])
        run(['codesign', '--verify', '--strict', framework])
        # Include source identity, top-level license, and source archives for every core.
        license_text = f"{name}\nSource: {core['url']}\nRevision: {core['commit']}\n\n"
        license_text += (src / core['license']).read_text(errors='replace')
        (OUT / 'CoreLicenses' / f'{name}.txt').write_text(license_text)
        run(['git', 'archive', '--format=tar.gz', f'--prefix={name}/',
             '-o', OUT / 'Sources' / f'{name}-{core["commit"]}.tar.gz', 'HEAD'], src)
        print('::endgroup::', flush=True)
    shutil.copy2(ROOT / 'tool/ios_cores.json', OUT / 'Sources/ios_cores.json')
    # Also provide the host and exact build scripts beside the core sources.
    run(['git', 'archive', '--format=tar.gz', '--prefix=Vantage/',
         '-o', OUT / 'Sources/Vantage-host-source.tar.gz', 'HEAD'])


if __name__ == '__main__':
    main()
