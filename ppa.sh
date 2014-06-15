#!/bin/bash

gpgkey="BC0B0D65"
ppaname="cernekee/ppa"

builddir=tmp.debian
pkg=openconnect

set -ex

function build_one
{
	arg="$1"

	rm -rf $builddir
	mkdir $builddir
	pushd $builddir

	cp ../$tarball "${pkg}_${ver}.orig.tar.gz"
	mkdir "$pkg-$ver"
	cd "$pkg-$ver"
	tar --strip 1 -zxf ../../$tarball
	cp -a ../../debian .
	if [ "$nosign" = "0" ]; then
		debuild "$arg"
	else
		debuild "$arg" -us -uc
	fi
	cd ..
	lintian -IE --pedantic *.changes | tee -a ../lintian.txt || true
	popd
}

#
# MAIN
#

if [ ! -d debian ]; then
	echo "This must be run from the $pkg top level dir"
	exit 1
fi

script=/etc/vpnc/vpnc-script
if [ -e /usr/share/vpnc-scripts/vpnc-script ]; then
	script=/usr/share/vpnc-scripts/vpnc-script
fi

rm -f ${pkg}-*.tar.gz
bash autogen.sh
./configure --with-vpnc-script=$script
fakeroot make dist DISTHOOK=0

tarball=$(ls -1 ${pkg}-*.tar.gz 2> /dev/null || true)
if [ -z "$tarball" -o ! -e "$tarball" ]; then
	echo "missing release tarball"
	exit 1
fi

# The tarball is named after the previous release, but we want our package
# to use version ($oldver + 0.01) so it replaces the old package.
# In Debian versioning: foo-5.99 < foo-6.00~(anything) < foo-6.00
oldver=${tarball#*-}
oldver=${oldver%%.tar.gz}
ver=$((${oldver/./} + 1))
ver=${ver:0:1}.${ver:1}

if gpg --list-secret-keys $gpgkey >& /dev/null; then
	nosign=0
else
	nosign=1
fi

rm -f lintian.txt ${pkg}*.deb
touch lintian.txt

dist=$(lsb_release -si)
if [ "$dist" = "Ubuntu" ]; then
	pushd debian
	git checkout -f changelog control
	if ! dpkg -l vpnc-scripts >& /dev/null; then
		sed -i -e 's/vpnc-scripts/vpnc/g' control
	fi
	popd

	codename=$(lsb_release -sc)

	today=$(date +%Y%m%d%H%M%S)
	ver="${ver}~${today}"
	uver="${ver}-1ubuntu1"

	dch --newversion "${uver}~${codename}" \
		--distribution $codename \
		--force-bad-version \
		"New PPA build."
fi

build_one ""
cp $builddir/*.deb .
echo "------------" >> lintian.txt
build_one "-S"

set +ex

echo "--------"
echo "lintian:"
echo "--------"
cat lintian.txt
echo "--------"

if [ -n "$uver" -a "$nosign" = "0" ]; then
	echo ""
	echo "UPLOAD COMMAND:"
	echo ""
	echo "    dput ppa:$ppaname tmp.debian/*_source.changes"
	echo ""
fi

exit 0
