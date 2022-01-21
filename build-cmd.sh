#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

OPENJPEG_SOURCE_DIR="openjpeg"
OPENJPEG_VERSION="$(awk '/OPENJPEG_VERSION/ { print $3 }' \
                        "$OPENJPEG_SOURCE_DIR/src/lib/openjp2/openjpeg.h" | \
                    tr -d '"')"

# check autobuild is around or fail
if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$AUTOBUILD" source_environment > "$source_environment_tempfile"
set +x
. "$source_environment_tempfile"
set -x

build=${AUTOBUILD_BUILD_ID:=0}
echo "${OPENJPEG_VERSION}.${build}" > "${stage}/VERSION.txt"

pushd "$OPENJPEG_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            cmake.exe . -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_CMAKE_PLAT" -DCMAKE_INSTALL_PREFIX=$stage -DCMAKE_C_FLAGS="$LL_BUILD_RELEASE" -DCMAKE_SHARED_LINKER_FLAGS_RELEASE="/DEBUG /OPT:REF /OPT:ICF"

            build_sln "OPENJPEG.sln" "Release|$AUTOBUILD_WIN_VSPLATFORM" "openjp2"
            mkdir -p "$stage/lib/release"
            cp bin/Release/openjp2{.dll,.lib,.pdb} "$stage/lib/release"

            build_sln "OPENJPEG.sln" "Debug|$AUTOBUILD_WIN_VSPLATFORM" "openjp2"
            mkdir -p "$stage/lib/debug"
            cp bin/Debug/openjp2{.dll,.lib,.pdb} "$stage/lib/debug"			

            mkdir -p "$stage/include/openjpeg"
            cp src/lib/openjp2/openjpeg.h "$stage/include/openjpeg/"
            cp src/lib/openjp2/opj_config.h "$stage/include/openjpeg/"
            cp src/lib/openjp2/opj_stdint.h "$stage/include/openjpeg/"
        ;;

        darwin*)
            cmake . -GXcode -D'CMAKE_OSX_ARCHITECTURES:STRING=$AUTOBUILD_CONFIGURE_ARCH' \
                    -D'BUILD_SHARED_LIBS:bool=off' -D'BUILD_CODEC:bool=off' \
                    -DCMAKE_INSTALL_PREFIX=$stage -DCMAKE_C_FLAGS="$LL_BUILD_RELEASE"
            xcodebuild -configuration Release -target openjp2 -project openjpeg.xcodeproj
            xcodebuild -configuration Release -target install -project openjpeg.xcodeproj
            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/include/openjpeg"
            # As of openjpeg 2.0, build products are now installed into
            # directories with version-stamped names. The actual pathname can
            # be found in install_manifest.txt.
            # For backwards compatibility, rename libopenjp2.a to libopenjpeg.a.
            mv -v "$(grep '/libopenjp2.a$' install_manifest.txt)" "$stage/lib/release/libopenjpeg.a"
            mv -v "$(grep '/openjpeg.h$' install_manifest.txt)" "$stage/include/openjpeg/"
            mv -v "$(grep '/opj_config.h$' install_manifest.txt)" "$stage/include/openjpeg/"
            mv -v "$(grep '/opj_stdint.h$' install_manifest.txt)" "$stage/include/openjpeg/"
        ;;

        linux*)
            # Force 4.6
            export CC=gcc-4.6
            export CXX=g++-4.6

            # Inhibit '--sysroot' nonsense
            export CPPFLAGS=""

            cmake -G"Unix Makefiles" \
                -DCMAKE_INSTALL_PREFIX="$stage" \
                -DBUILD_SHARED_LIBS:bool=off \
                -DCMAKE_INSTALL_DEBUG_LIBRARIES=1 \
                -DCMAKE_C_FLAGS="$LL_BUILD_RELEASE" .
            # From 1.4.0:
            # CFLAGS="-m32" CPPFLAGS="-m32" LDFLAGS="-m32" ./configure --target=i686-linux-gnu --prefix="$stage" --enable-png=no --enable-lcms1=no --enable-lcms2=no --enable-tiff=no
            make
            make install
            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                echo "No unit tests yet"
            fi

            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/include/openjpeg"
            # As of openjpeg 2.0, build products are now installed into
            # directories with version-stamped names. The actual pathname can
            # be found in install_manifest.txt.
            # For backwards compatibility, rename libopenjp2.a to libopenjpeg.a.
            mv -v "$(grep '/libopenjp2.a$' install_manifest.txt)" "$stage/lib/release/libopenjpeg.a"
            mv -v "$(grep '/openjpeg.h$' install_manifest.txt)" "$stage/include/openjpeg/"
            mv -v "$(grep '/opj_config.h$' install_manifest.txt)" "$stage/include/openjpeg/"
            mv -v "$(grep '/opj_stdint.h$' install_manifest.txt)" "$stage/include/openjpeg/"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE "$stage/LICENSES/openjpeg.txt"
popd
