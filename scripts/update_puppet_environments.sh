#!/bin/bash
# Update puppet environments
#
# In order to acheive atomic replacement of puppet environments directory
# we use the techniques described here:
#
# http://axialcorps.com/2013/07/03/atomically-replacing-files-and-directories/
#
# In practise, this means that /etc/puppet/environments is a symlink
#
# Also uses GNU parallel to run multiple instances of librarian-puppet in
# parallel which speeds up execution considerably.

# make sure fail on errors
set -euf -o pipefail

# simple function to print a message to stderr and exit
error () {
  echo "$1" 1>&2
  exit 1
}

# make sure $HOME is set because librarian barfs if it isn't
# lib/librarian/environment.rb
# In this function:
#     def default_home
#       File.expand_path(ENV["HOME"] || Etc.getpwnam(Etc.getlogin).dir)
#     end
[[ -v HOME ]] || export HOME=/tmp

# list of required commands
# Any command can be over-ridden by setting the appropriate environment variable
# the script checks each command is available before running
BASENAME=${BASENAME_CMD:-basename}
CHMOD=${CHMOD_CMD:-chmod}
DIRNAME=${DIRNAME_CMD:-dirname}
LIBRARIAN_PUPPET=${LIBRARIAN_PUPPET_CMD:-librarian-puppet}
LN=${LN_CMD:-ln}
MKDIR=${MKDIR_CMD:-mkdir}
MKTEMP=${MKTEMP_CMD:-mktemp}
MV=${MV_CMD:-mv}
PARALLEL=${PARALLEL_CMD:-parallel}
PUPPET=${PUPPET_CMD:-puppet}
R10K=${R10K_CMD:-r10k}
RM=${RM_CMD:-rm}
CACHE_DIR=${CACHE_DIR:-/var/tmp/librarian-puppet/cache}

# make sure required commands are present
CMDS=(
  "$BASENAME"
  "$CHMOD"
  "$DIRNAME"
  "$LIBRARIAN_PUPPET"
  "$LN"
  "$MKDIR"
  "$MKTEMP"
  "$MV"
  "$PARALLEL"
  "$PUPPET"
  "$R10K"
)
for cmd in "${CMDS[@]}" ; do
  type -P "$cmd" &>/dev/null || error "Error: $cmd not found"
done

# the name of the dir in which each new deployment is created
# created in the puppet conf dir
REAL_ENV_DIR_NAME=${ENV_DIR_NAME:-envs}

# Get the configured puppet environment path
ENV_PATH=$("$PUPPET" config print environmentpath)
[[ -z "$ENV_PATH" ]] && error 'Could not discover puppet environment path'

# Get the puppet config dir
CONF_DIR=$("$PUPPET" config print confdir)
[[ -z "$CONF_DIR" ]] && error 'Could not discover puppet config dir'

# if the environmentpath exists, make sure it's a symlink, otherwise delete it
if [[ -e "$ENV_PATH" ]] ; then
  [[ -L "$ENV_PATH" ]] || "$RM" -rf "$ENV_PATH"
fi

# make sure a Puppetfile exists in the puppet config dir
[[ -f "${CONF_DIR}/Puppetfile" ]] || error "Puppetfile not found in '$CONF_DIR'"

# get the directory name of the environment path
ENV_DIR_NAME=$("$BASENAME" "$ENV_PATH")

# get the parent directory of the environment path
ENV_PATH_PARENT=$("$DIRNAME" "$ENV_PATH")

# this is the dir in which we create the environments
REAL_ENV_PATH="${ENV_PATH_PARENT}/${REAL_ENV_DIR_NAME}"
"$MKDIR" -p "$REAL_ENV_PATH"

# create the cache dir
"$MKDIR" -p "$CACHE_DIR"

# create a new dir to hold the environments
NEW_ENV_DIR=$("$MKTEMP" --directory --tmpdir="$REAL_ENV_PATH" "${ENV_DIR_NAME}.$(date -Isec).XXX")
"$CHMOD" 0755 "$NEW_ENV_DIR"

# Get the basename of the new dir
NEW_ENV_DIR_NAME=$("$BASENAME" "$NEW_ENV_DIR")

# pull down the environments defined in the top-level Puppetfile
cd "$CONF_DIR"
PUPPETFILE_DIR="${REAL_ENV_DIR_NAME}/${NEW_ENV_DIR_NAME}" "$R10K" puppetfile install

# pull down all the modules in each environment
"$PARALLEL" --no-notice "\
  pushd '{}' > /dev/null && \
  LIBRARIAN_PUPPET_PATH=modules LIBRARIAN_PUPPET_TMP='$CACHE_DIR' '$LIBRARIAN_PUPPET' install --no-use-v1-api --strip-dot-git && \
  \"$RM\" -rf .tmp && \
  popd > /dev/null \
" < <(find "$NEW_ENV_DIR" -maxdepth 1 -mindepth 1 -type d)

# create a symlink pointing to the new env
"$LN" -sf "$NEW_ENV_DIR" "${REAL_ENV_PATH}/${ENV_DIR_NAME}"

# Move the symlink to the correct location
"$MV" "${REAL_ENV_PATH}/${ENV_DIR_NAME}" "$ENV_PATH_PARENT"
