#!/bin/sh
# *nix auto-audit
# Written by Peter Pilarski for EMUSec competitions
version="1.2"

usage() {
	echo "*nix auto-audit v$version

-c <cci.sh>
	Specify location of cci.sh to install GCC and make for LSAT.
	Default: /root/cci.sh
-d <directory>
	Set working root directory. Will be created if it doesn't exist.
	Default: /root/EMUSEC
-l
	Only run Lynis.
-L
	Only run LSAT.
-p
	Pentest mode. Runs as an unprivileged user, giving Lynis --pentest.
	Working directory defaults to /tmp/EMUSEC.
-h
	For when you miss reading this
"
}

parseOpts() {
	while getopts :hHlLpPc:C:d:D: opt; do
		case $opt in
			c|C)# Cruise-control installer
				cci="$(readlink -f "$OPTARG")"
				;;
			d|D)# Set working DIR
				rootDIR="$OPTARG"
				;;
			l)# Lynis
				noLSAT=1
				;;
			L)# LSAT
				noLynis=1
				;;
			p|P)# Pentest
				if [ "$(whoami)" = "root" ]; then
					echo "Error: Pentest mode should be run as an unprivileged user."
					exit 1
				fi
				if [ "$(uname)" = "FreeBSD" ]; then
					echo "Error: Pentest mode won't work on freeBSD, requires root ownership."
					echo "Maybe it's misconfigured... try anyway? (Y/y)"
					read tryanyway
					if [ "$tryanyway" != "y" ] && [ "$tryanyway" != "Y" ]; then
						exit 1
					fi
				fi
				pentest=1
				[ "$rootDIR" ] || rootDIR="/tmp/EMUSEC"
				;;
			h|H)# Help
				usage
				exit 0
				;;
			\?)# Unknown/invalid
				echo "Invalid option: -$OPTARG"
				usage
				exit 1
				;;
			:)# Missing arg
				echo "An argument must be specified for -$OPTARG"
				usage
				exit 1
				;;
		esac
	done
}

installBuild() {
	if [ "$(which make 2>/dev/null)" ] && [ "$(which gcc 2>/dev/null)" ]; then
		return
	fi
	if [ "$(whoami)" != "root" ]; then
		echo "Error: Build tools (make, gcc) missing. Need root to install them."
		exit 1
	fi
	echo "Installing build tools..."
	echo "gcc
make" > "${rootDIR}/build_tools.tmp"
	[ -e "$cci" ] && "$cci" -y -f "${rootDIR}/build_tools.tmp" >/dev/null 2>&1
	rm -f "${rootDIR}/build_tools.tmp"
}

lynisAudit() {
	if [ ! -e "${rootDIR}/lynis" ]; then
		echo "Downloading Lynis..."
		cd "$rootDIR"
		if [ -e "$(which wget 2>/dev/null)" ]; then
			wget -q --no-check-certificate http://cisofy.com/files/lynis-2.1.1.tar.gz
		elif [ -e "$(which curl 2>/dev/null)" ]; then
			curl -s -L http://cisofy.com/files/lynis-2.1.1.tar.gz -o ./lynis-2.1.1.tar.gz
		else
			echo "Error: Neither wget nor curl are available."
			return 1
		fi
		tar xzf ./lynis-2.1.1.tar.gz
		rm ./lynis-2.1.1.tar.gz
	fi
	if [ ! -e "${rootDIR}/lynis/lynis" ]; then
		printf "Lynis not found.\nRemove ${rootDIR}/lynis to download again.\n"
		return 1
	fi
	cd "${rootDIR}/lynis/" # lynis needs to be executed from its dir
	if [ $pentest ]; then
		echo "Running Lynis in pentest mode"
		echo "\n" | ./lynis -Q --pentest --tests-category "accounting authentication boot_services containers crypto databases file_integrity file_permissions filesystems firewalls hardening homedirs insecure_services kernel kernel_hardening ldap logging mac_frameworks mail_messaging malware memory_processes nameservices networking php scheduling shells snmp solaris squid ssh storage storage_nfs time tooling webservers" > ${rootDIR}/audit/lynis.out 2>/dev/null
	else
		echo "Running Lynis..."
		./lynis -Q --tests-category "accounting authentication boot_services containers crypto databases file_integrity file_permissions filesystems firewalls hardening homedirs insecure_services kernel kernel_hardening ldap logging mac_frameworks mail_messaging malware memory_processes nameservices networking php scheduling shells snmp solaris squid ssh storage storage_nfs time tooling webservers" audit system > ${rootDIR}/audit/lynis.out 2>/dev/null
	fi
	printf "Finished. Check ${rootDIR}/audit/lynis.out\n\n"
}
lsatAudit() {
	if [ ! "$(uname -a | grep -i linux)" ]; then
		echo "LSAT won't work here."
		return 1
	fi
	if [ ! -e "${rootDIR}/lsat-0.9.8.2" ]; then
		installBuild
		cd "$rootDIR"
		echo "Downloading LSAT..."
		if [ -e "$(which wget 2>/dev/null)" ]; then
			wget -q --no-check-certificate http://usat.sourceforge.net/code/lsat-0.9.8.2.tgz
		elif [ -e "$(which curl 2>/dev/null)" ]; then
			curl -s -L http://usat.sourceforge.net/code/lsat-0.9.8.2.tgz -o ./lsat-0.9.8.2.tgz
		else
			echo "Error: Neither wget nor curl are available."
			return 1
		fi
		echo "Compiling LSAT..."
		tar xzf ./lsat-0.9.8.2.tgz
		rm ./lsat-0.9.8.2.tgz
		cd "${rootDIR}/lsat-0.9.8.2"
		# Patch LSAT. Encountered a bug that doesn't test excludes properly.
		sed -i '106s/35/37/' "${rootDIR}/lsat-0.9.8.2/lsatmain.c"
		./configure > /dev/null 2>&1
		make -s 2> /dev/null
		# Exclude unnecessary time consuming tasks
		echo "pkgupdate md5 modules" > ./exclude
	fi
	if [ ! -e "${rootDIR}/lsat-0.9.8.2/lsat" ]; then
		printf "Failed to compile LSAT.\nRemove ${rootDIR}/lsat-0.9.8.2 to try again.\n"
		return 1
	fi
	echo "Running LSAT..."
	"${rootDIR}/lsat-0.9.8.2/lsat" -s -x "${rootDIR}/lsat-0.9.8.2/exclude" > /dev/null 2>&1
	cp "${rootDIR}/lsat-0.9.8.2/lsat.out" "${rootDIR}/audit/lsat.out"
	printf "Finished. Check ${rootDIR}/audit/lsat.out\n\n"
}

parseOpts "$@"
[ "$rootDIR" ] || rootDIR="/root/EMUSEC"
[ "$cci" ] || cci="/root/cci.sh"
if [ "$(whoami)" != "root" ] && [ ! $pentest ]; then 
	echo "This script needs to be run as root."
	exit 1
fi
[ -e "${rootDIR}/audit" ] || mkdir -p "${rootDIR}/audit"
rootDIR="$(readlink -f "$rootDIR")"
[ "$noLynis" ] || lynisAudit
[ "$noLSAT" ] || lsatAudit
