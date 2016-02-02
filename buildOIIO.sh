#!/bin/sh

#Options:
# NO_CLEAN=1 (optional): Do not fetch oiio if directory exists and does not remove build dir
# USE_XCODE=1 (optional): (OSX Only) Builds using xcodebuild. The binaries will be symlinked to the Xcode build directory
# and the actual headers will not be installed
# MKJOBS (optional): Number of threads for make
# USE_TAR=1 (optional): if set, this will use the selected OIIO_TAR, otherwise this will fallback on using git and the specified GIT_BRANCH
# OIIO_VERSION="X.Y.ZW" (optional): the version number of oiio release to use when USE_TAR=1. The archive must be on the remote server already
# GIT_BRANCH (optional): select git branch if using git
# CONFIG=(debug,release) (required)
# NO_TOOLS=1:(optional) do not build oiio tools
#Usage: MKJOBS=8 NO_TOOLS=1 USE_TAR=1 CONFIG=debug ./buildOIIO
#With Xcode: NO_CLEAN=1 USE_XCODE=1 CONFIG=debug sh buildOIIO.sh

set -x 
CWD=$(pwd)

DEFAULT_OIIO_VERSION=1.5.23

if [ -z "$OIIO_VERSION" ]; then
    OIIO_VERSION=$DEFAULT_OIIO_VERSION
fi

###### To be customized

#To be set if USE_TAR=1 is specified
OIIO_TAR=oiio-Release-$OIIO_VERSION.tar.gz

#Where to download OIIO_TAR when USE_TAR=1
REPO_URL=http://downloads.natron.fr/Third_Party_Sources/

#Where to install binaries
DST_DIR=/Users/alexandre/development/CustomBuilds
######

PATCH_DIR=$CWD/patches

OIIO_GIT=https://github.com/lgritz/oiio.git
DEFAULT_GIT_BRANCH=master


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



if [ -z "$NO_CLEAN" ]; then
    rm -rf oiio*
fi

if [ ! -d "oiio-src" ]; then
    if [ "$USE_TAR" != "1" ]; then
        echo "Using git repository $OIIO_GIT"
        git clone $OIIO_GIT oiio-src
    else
        echo "Using tar archive ${REPO_URL}${OIIO_TAR}"
        wget ${REPO_URL}${OIIO_TAR} || exit 1
        tar xf $OIIO_TAR || exit 1
        rm $OIIO_TAR || exit 1
        mv oiio-* oiio-src || exit 1
    fi
fi

cd oiio-src || exit 1

if [ -z "$NO_CLEAN" ]; then
    rm -rf build
fi

if [ "$USE_TAR" != "1" ]; then
    git checkout $GIT_BRANCH || exit 1
else
    if [[ "$OIIO_VERSION" = 1.5.* ]]; then
        patch -p1 -i $PATCH_DIR/oiio-1.5.22-exrthreads.patch || exit 1
    elif [[ "$OIIO_VERSION" = 1.6.* ]]; then
        patch -p1 -i $PATCH_DIR/oiio-sha1.patch || exit 1
        patch -p1 -i $PATCH_DIR/oiio-x86intrin.patch || exit 1
    fi
fi

if [ ! -d build ]; then
    mkdir build
    cd build
    cmake -DUSE_QT=0 -DBOOST_ROOT=/opt/Natron-1.0 -DUSE_TBB=0 -DUSE_PYTHON=0 -DUSE_FIELD3D=0 -DUSE_FFMPEG=0 -DUSE_OPENJPEG=0 -DUSE_OCIO=1 -DUSE_OPENCV=0 -DUSE_OPENSSL=0 -DUSE_FREETYPE=1 -DUSE_GIF=1 -DUSE_LIBRAW=1 -DSTOP_ON_WARNING=0 $CMAKE_OIIO_TOOLS -DCMAKE_INSTALL_PREFIX="" ${CMAKE_CONFIG} ${XCODE_EXTRA} .. || exit 1
else
    cd build || exit 1
fi

if [ "$USE_XCODE" = "1" ]; then
    INSTALL_DIR=$DST_DIR xcodebuild -project OpenImageIO.xcodeproj -target OpenImageIO -configuration=$BUILDTYPE || exit 1
(cd $DST_DIR/lib;rm libOpenImageIO*; ln -s $CWD/oiio-src/build/src/libOpenImageIO/Debug/libOpenImageIO* .;rm -rf $DST_DIR/include/OpenImageIO;cp -r $CWD/oiio-src/src/include/OpenImageIO $DST_DIR/include; cp $CWD/oiio-src/build/include/OpenImageIO/* $DST_DIR/include/OpenImageIO/;)
else
    make -j${MKJOBS} || exit 1
    make DESTDIR=$DST_DIR BUILD_TYPE=$BUILDTYPE install || exit 1
fi

cd $CWD
