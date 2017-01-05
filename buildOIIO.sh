#!/bin/sh

# Options:
# OIIO_SRC= ... (optional): Can be specified to use a custom OIIO directory where the sources are. If empty this will fetch the git branch specified
# NO_CLEAN=1 (optional): Do not fetch oiio if directory exists and does not remove build dir
# USE_XCODE=1 (optional): (OSX Only) Builds using xcodebuild. The binaries will be symlinked to the Xcode build directory
# and the actual headers will not be installed
# MKJOBS (optional): Number of threads for make
# GIT_BRANCH (optional): select git branch or tag
# CONFIG=(debug,release) (required)
# NO_TOOLS=1:(optional) do not build oiio tools
# DST_DIR=... (required): Where to deploy the library
# OPENEXR_HOME=...(optional): path where the openexr library is deployed (the directory containing bin/ lib/ include/)
#
#
#Usage: MKJOBS=8 NO_TOOLS=1 GIT_BRANCH=tags/Release-1.6.17 CONFIG=debug DST_DIR=. ./buildOIIO
#With Xcode: NO_CLEAN=1 USE_XCODE=1 GIT_BRANCH=master CONFIG=debug DST_DIR=. ./buildOIIO.sh

set -x 
CWD=$(pwd)

DEFAULT_GIT_BRANCH=tags/Release-1.6.18

if [ -z "$OIIO_VERSION" ]; then
    OIIO_VERSION=$DEFAULT_OIIO_VERSION
fi

if [ -z "$DST_DIR" ]; then
    ###### To be customized
    DST_DIR=/Users/alexandre/development/CustomBuilds
    ######
fi

if [ ! -d "$DST_DIR" ]; then
    echo "$DST_DIR: Specified DST_DIR does not exist."
    exit 1
fi

PATCH_DIR=$CWD/patches

OIIO_GIT=https://github.com/lgritz/oiio.git


if [ "$CONFIG" = "debug" ]; then
    BUILDTYPE=Debug
	CMAKE_CONFIG="-DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_CONFIG_NAME=Debug"
	echo "Debug build"
elif [ "$CONFIG" = "release" ]; then
    BUILDTYPE=Release
    CMAKE_CONFIG="-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_CONFIG_NAME=Release"
else
    echo "You must specify build type (debug or release)"
    exit 1
fi

if [ "$NO_TOOLS" = "1" ]; then
    CMAKE_OIIO_TOOLS="-DOIIO_BUILD_TOOLS=0"
else
    CMAKE_OIIO_TOOLS="-DOIIO_BUILD_TOOLS=1"
fi

if [ -z "$GIT_BRANCH" ]; then
    GIT_BRANCH=$DEFAULT_GIT_BRANCH
fi

if [ "$USE_XCODE" = "1" ]; then
    XCODE_EXTRA="-G Xcode"
fi

if [ ! -z "$OPENEXR_HOME" ]; then
    OPENEXR_EXTRA="-DOPENEXR_HOME=${OPENEXR_HOME}"
fi


if [ -z "$OIIO_SRC" ]; then
    HAS_CUSTOM_SRC=0
    OIIO_SRC=oiio-src
    if [ -z "$NO_CLEAN" ]; then
        rm -rf oiio-src*
    fi

    if [ ! -d "oiio-src" ]; then
        echo "Using git repository $OIIO_GIT"
        git clone $OIIO_GIT oiio-src
    fi
else
    HAS_CUSTOM_SRC=1
fi

cd $OIIO_SRC || exit 1

if [ -z "$NO_CLEAN" ]; then
    rm -rf build
fi

OS=$(uname -s)
git checkout $GIT_BRANCH

if [ ! -d build ]; then

    FAIL=0
    if [ "$HAS_CUSTOM_SRC" == "0" ]; then

        if [[ "$GIT_BRANCH" = *-1.5.* ]]; then
            patches=$(find $PATCH_DIR/1.5 -type f)
        elif [[ "$GIT_BRANCH" = *-1.6.* ]]; then
            patches=$(find $PATCH_DIR/1.6 -type f)
        fi
        for p in $patches; do
            if [[ "$p" = *-mingw-* ]] && [ "$OS" != "MINGW64_NT-6.1" ]; then
                continue
            fi
            FAIL=$(patch -p1 -i $p)
        done
    fi
    mkdir build
    cd build
    cmake $OPENEXR_EXTRA -DUSE_QT=0 -DBOOST_ROOT=/opt/Natron-1.0 -DUSE_TBB=0 -DUSE_PYTHON=0 -DUSE_FIELD3D=0 -DUSE_FFMPEG=0 -DUSE_OPENJPEG=0 -DUSE_OCIO=1 -DUSE_OPENCV=0 -DUSE_OPENSSL=0 -DUSE_FREETYPE=1 -DUSE_GIF=1 -DUSE_LIBRAW=1 -DSTOP_ON_WARNING=0 $CMAKE_OIIO_TOOLS -DCMAKE_INSTALL_PREFIX="" ${CMAKE_CONFIG} ${XCODE_EXTRA} .. || FAIL=1
    if [ "$FAIL" = "1" ]; then
        rm -rf build
        exit 1
    fi
else
    cd build || exit 1
fi

if [ "$USE_XCODE" = "1" ]; then
    if [ ! -d "OpenImageIO.xcodeproj" ]; then
        cd ..
        rm -rf build
        exit 1
    fi
    INSTALL_DIR=$DST_DIR xcodebuild -project OpenImageIO.xcodeproj -target OpenImageIO -configuration=$BUILDTYPE || exit 1
(cd $DST_DIR/lib;rm libOpenImageIO*; ln -s $CWD/oiio-src/build/src/libOpenImageIO/Debug/libOpenImageIO* .;rm -rf $DST_DIR/include/OpenImageIO;cp -r $CWD/oiio-src/src/include/OpenImageIO $DST_DIR/include; cp $CWD/oiio-src/build/include/OpenImageIO/* $DST_DIR/include/OpenImageIO/;)
else
    make -j${MKJOBS} || exit 1
    make DESTDIR=$DST_DIR BUILD_TYPE=$BUILDTYPE install || exit 1
fi

cd $CWD
