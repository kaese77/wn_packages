#!/bin/sh
#
# 2016 Alexander Couzens

# generate LEDE images

### inputs
# profile file
# package list
# an imagebuilder filename
# a target directory to save files

set -e

IB_DIR="$(dirname "$0")/ib/"
PROFILES=""
TARGET=
PKGLIST_DIR="$(dirname "$0")/packagelists"
DEST_DIR=
USECASES=
OPENWRT=

info() {
	echo "$@"
}

signal_handler() {
	# only remove directory when not in debug mode
	if [ -z "$DEBUG" ] ; then
		rm -Rf "$TEMP_DIR"
	else
		info "Not removing temp dir $TEMP_DIR"
	fi
}

error() {
	echo "$@" >&2
}

# DEST_DIR needs to be an absolute path, otherwise it got broken
# because the imagebuilder is two levels deeper.
to_absolute_path() {
	input="$1"
	if [ "$(echo "$1" | cut -c 1)" = "/" ] ; then
		# abs path already given
		echo $1
	else
		# we append the $pwd to it
		echo $(pwd)/$1
	fi
}

parse_pkg_list_file() {
	# parse a package list file
	# ignores all lines starting with a #
	# returns a space seperated list of the packages
	pkg_file="$1"

	grep -v '^\#' $pkg_file | tr -t '\n' ' '
}

usage() {
	echo "
$0 -i <IB_FILE> -t <target> -o <openwrt base version>

-i <dir> path to the extracted image builder
-t <target> target to build for
-d <dir> destination directory where to save the files
-l <dir> (optional) directory to the package lists
-u <list> usecase. seperate multiple usecases by a space
-e <dir> (optional) directory of files to directtly include into image
-o <openwrt> openwrt base version
"
}

while getopts "i:l:n:t:d:u:e:o:" option; do
	case "$option" in
		i)
			IB_FILE="$OPTARG"
			;;
		e)
			MBED_DIR="$OPTARG"
			;;
    t)
			TARGET="$OPTARG"
			;;
		d)
			DEST_DIR="$OPTARG"
			;;
		l)
			PKGLIST_DIR="$OPTARG"
			;;
		u)
			USECASES="$OPTARG"
			;;
		o)
			OPENWRT="$OPTARG"
			;;
		*)
			echo "Invalid argument '-$OPTARG'."
			usage
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

if [ ! -e "$IB_DIR" ] ; then
	error "IB_DIR does not exist $IB_DIR"
	exit 1
fi

if [ -z "$USECASES" ] ; then
	error "No usecase(s) given"
	exit 1
fi

if [ -z "$OPENWRT" ] ; then
	error "No openwrt base version given"
	exit 1
fi

if [ -z "$TARGET" ] ; then
	error "No target given"
	exit 1
fi


trap signal_handler 0 1 2 3 15

# get main- and subtarget name from TARGET
MAINTARGET="$(echo $TARGET|cut -d '_' -f 1)"
CUSTOMTARGET="$(echo $TARGET|cut -d '_' -f 2)"
SUBTARGET="$(echo $CUSTOMTARGET|cut -d '-' -f 1)"

if [ -z "$DEST_DIR" ]; then
  GIT=$(git describe --always --dirty --tags)
  DEST_DIR=$(dirname "$0")/firmwares/$GIT/$OPENWRT/$MAINTARGET/$CUSTOMTARGET
fi
echo $DEST_DIR
# sanitize dest_dir
DEST_DIR=$(to_absolute_path "$DEST_DIR")
info $DEST_DIR
failed_profiles=

# check if packagelist with suffix exist
if [ -e "profiles/${OPENWRT}/${TARGET}.profiles" ] ; then
	profiles="profiles/${OPENWRT}/${TARGET}.profiles"
else
	profiles="profiles/${TARGET}.profiles"
fi

while read model; do
	info "Building an image for $model"

	profile="$(echo $model | cut -d';' -f 1)"
	info "profile is $profile"
	model_packages="$(echo $model | cut -d';' -s -f 2)"
	info "we include these extra packages: $model_packages"

	# profiles can have a suffix. like 4mb devices get a smaller package list pro use case
	# UBNT:4MB -> profile "UBNT" suffix "4MB"
	suffix="$(echo $profile | cut -d':' -f 2)"
	profile="$(echo $profile | cut -d':' -f 1)"

	for usecase in $USECASES ; do
		package_list=""
		packages=""
		img_params=""

		# check if packagelist with suffix exist
		if [ -e "${PKGLIST_DIR}/${OPENWRT}/${usecase}_${suffix}.txt" ] ; then
			package_list="${OPENWRT}/${usecase}_${suffix}"
		elif [ -e "${PKGLIST_DIR}/${OPENWRT}/${usecase}.txt" ] ; then
			package_list="${OPENWRT}/${usecase}"
		elif [ -e "${PKGLIST_DIR}/${usecase}_${suffix}.txt" ] ; then
			package_list="${usecase}_${suffix}"
		else
			package_list="${usecase}"
		fi

		if [ -e "${PKGLIST_DIR}/${package_list}.txt" ]; then
			info "Building usecase $usecase"
		else
			error "usecase $usecase not defined"
			exit 1
		fi

		info "Using package list $package_list"

		packages=$(parse_pkg_list_file "${PKGLIST_DIR}/${package_list}.txt")
		packages="${packages} ${model_packages}"

		if [ -z "${packages}" ] ; then
			info "skipping this usecase, as package list is empty"
			continue
		fi

		hookfile=$(to_absolute_path "${PKGLIST_DIR}/${package_list}.sh")
		if [ -f "$hookfile" ]; then
			info "Using a post inst hook."
			img_params="$img_params CUSTOM_POSTINST_SCRIPT=$hookfile"
		fi

		if [ -n "$MBED_DIR" ]; then
			mbed_dir=$(to_absolute_path "${MBED_DIR}")
			info "embedding files from $mbed_dir."
			if [ $(ls $mbed_dir | wc -l) -gt 0 ]; then
				img_params="$img_params FILES=$mbed_dir"
			fi
		fi

		# ensure BIN_DIR is valid
    base_target_dir=$(basename ${package_list})
		mkdir -p "${DEST_DIR}/${base_target_dir}"

		make -C "${IB_DIR}/" image "PROFILE=$profile" "PACKAGES=$packages" "BIN_DIR=${DEST_DIR}/${base_target_dir}" $img_params || failed_profiles="${profile}; ${failed_profiles}" 

	done
done < $profiles

if [ -n "$failed_profiles" ]; then
	echo "We weren't able to build the following profiles for : ${failed_profiles}." >> ${DEST_DIR}/${base_target_dir}/failedprofiles.txt
fi
