#!/bin/bash

# Script to do Dgraph release. This script would output the built binaries in
# $TMP.  This script should NOT be responsible for doing any testing, or
# uploading to any server.  The sole task of this script is to build the
# binaries and prepare them such that any human or script can then pick these up
# and use them as they deem fit.

# Don't use standard GOPATH. Create a new one.
GOPATH="/tmp/go"
rm -Rf $GOPATH
mkdir $GOPATH

TAG=$1

# DO NOT change the /tmp/build directory, because Dockerfile also picks up binaries from there.
TMP="/tmp/build"
rm -Rf $TMP
mkdir $TMP

if [ -z "$TAG" ]; then
  echo "Must specify which tag to build for."
  exit 1
fi
echo "Building Dgraph for tag: $TAG"

# Stop on first failure.
set -e
set -o xtrace

# Check for existence of strip tool.
type strip
type shasum

ratel_release="github.com/dgraph-io/ratel/server.ratelVersion"
release="github.com/dgraph-io/dgraph/x.dgraphVersion"
branch="github.com/dgraph-io/dgraph/x.gitBranch"
commitSHA1="github.com/dgraph-io/dgraph/x.lastCommitSHA"
commitTime="github.com/dgraph-io/dgraph/x.lastCommitTime"

echo "Using Go version"
go version

go get -u github.com/jteeuwen/go-bindata/...
go get -d -u golang.org/x/net/context
go get -d google.golang.org/grpc
go get -u github.com/prometheus/client_golang/prometheus
go get -u github.com/dgraph-io/dgo
# go get github.com/stretchr/testify/require
go get -u github.com/karalabe/xgo

pushd $GOPATH/src/google.golang.org/grpc
  git checkout v1.13.0
popd

basedir=$GOPATH/src/github.com/dgraph-io
# Clone Dgraph repo.
pushd $basedir
  git clone git@github.com:dgraph-io/dgraph.git
popd

pushd $basedir/dgraph
  git pull
  git checkout $TAG
  # HEAD here points to whatever is checked out.
  lastCommitSHA1=$(git rev-parse --short HEAD);
  gitBranch=$(git rev-parse --abbrev-ref HEAD)
  lastCommitTime=$(git log -1 --format=%ci)
  release_version=$(git describe --abbrev=0);
popd

# Clone ratel repo.
pushd $basedir
  git clone git@github.com:dgraph-io/ratel.git
popd

pushd $basedir/ratel
  git pull
  source ~/.nvm/nvm.sh
  nvm install --lts
  ./scripts/build.prod.sh
popd

# Build Windows.
pushd $basedir/dgraph/dgraph
	xgo --targets=windows/amd64 -ldflags \
  "-X $release=$release_version -X $branch=$gitBranch -X $commitSHA1=$lastCommitSHA1 -X '$commitTime=$lastCommitTime'" .
  mkdir $TMP/windows
  mv dgraph-windows-4.0-amd64.exe $TMP/windows/dgraph.exe
popd

pushd $basedir/ratel
	xgo --targets=windows/amd64 -ldflags "-X $ratel_release=$release_version" .
	mv ratel-windows-4.0-amd64.exe $TMP/windows/dgraph-ratel.exe
popd

# Build Darwin.
pushd $basedir/dgraph/dgraph
	xgo --targets=darwin-10.9/amd64 -ldflags \
  "-X $release=$release_version -X $branch=$gitBranch -X $commitSHA1=$lastCommitSHA1 -X '$commitTime=$lastCommitTime'" .
  mkdir $TMP/darwin
  mv dgraph-darwin-10.9-amd64 $TMP/darwin/dgraph
popd

pushd $basedir/ratel
	xgo --targets=darwin-10.9/amd64 -ldflags "-X $ratel_release=$release_version" .
	mv ratel-darwin-10.9-amd64 $TMP/darwin/dgraph-ratel
popd

# Build Linux.
pushd $basedir/dgraph/dgraph
	xgo --targets=linux/amd64 -ldflags \
    "-X $release=$release_version -X $branch=$gitBranch -X $commitSHA1=$lastCommitSHA1 -X '$commitTime=$lastCommitTime'" .
  strip -x dgraph-linux-amd64
  mkdir $TMP/linux
  mv dgraph-linux-amd64 $TMP/linux/dgraph
popd

pushd $basedir/ratel
	xgo --targets=linux/amd64 -ldflags "-X $ratel_release=$release_version" .
  strip -x ratel-linux-amd64
	mv ratel-linux-amd64 $TMP/linux/dgraph-ratel
popd

createSum () {
  os=$1
  echo "Creating checksum for $os"
  pushd $TMP/$os
    csum=$(shasum -a 256 dgraph | awk '{print $1}')
    echo $csum /usr/local/bin/dgraph >> ../dgraph-checksum-$os-amd64.sha256
    csum=$(shasum -a 256 dgraph-ratel | awk '{print $1}')
    echo $csum /usr/local/bin/dgraph-ratel >> ../dgraph-checksum-$os-amd64.sha256
  popd
}

createSum darwin
createSum linux

# Create Docker image.
cp $basedir/dgraph/contrib/Dockerfile $TMP
pushd $TMP
  docker build -t dgraph/dgraph:$TAG .
popd
rm $TMP/Dockerfile

# Create the tars and delete the binaries.
createTar () {
  os=$1
  echo "Creating tar for $os"
  pushd $TMP/$os
    tar -zcvf ../dgraph-$os-amd64.tar.gz *
  popd
  rm -Rf $TMP/$os
}

createTar windows
createTar darwin
createTar linux

echo "Release $TAG is ready."
docker run -it dgraph/dgraph:v1.0.6 dgraph
ls -alh $TMP
