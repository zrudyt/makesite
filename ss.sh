#!/bin/sh

# shellcheck shell=dash

# ======================================================================
#  ss.sh - shell site : simple shell blogging front end for makesite
# ======================================================================
#  Copyright (c) 2023 zrudyt <zrudyt@ at hotmail dot com>
#  All rights reserved
# ----------------------------------------------------------------------
#  This script ...
#
#   TODO separate executable and content dirs
#   TODO combine params.json and .config into one single file
#
#   <!-- title: Insert post title here -->
#   <!-- tags: space delimited list of applicable tags -->
#
#   Pre-requisites:
#
#   - POSIX shell (sh, ash, dash, etc.) or better (bash, zsh, etc.)
#   - Python 3.8 or better to run makesite.py

#   Installation notes:
#
#     This script (ss.sh), makesite.py along with all related content,
#     layout and configuration files must be in the same directory tree.
# ----------------------------------------------------------------------------
#  The MIT License (MIT)
#
#  Permission is hereby granted, free of charge, to any person obtaining
#  a copy of this software and associated documentation files (the
#  "Software"), to deal in the Software without restriction, including
#  without limitation the rights to use, copy, modify, merge, publish,
#  distribute, sublicense, and/or sell copies of the Software, and to
#  permit persons to whom the Software is furnished to do so, subject to
#  the following conditions:
#
#  The above copyright notice and this permission notice shall be
#  included in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
#  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
#  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
#  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------------
#   U S E R   D E F I N E D   P A R A M E T E R S
# ----------------------------------------------------------------------------
# webserver parameters used in 'cmd_publish()' to be defined in '.config'
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_PATH=""
LOCAL_WWW=""

# ----------------------------------------------------------------------
#  G L O B A L   P A R A M E T E R S   A N D   V A R I A B L E S
# ----------------------------------------------------------------------
# parameters that shouldn't need to change, but can be overridden in '.config'
d_blog="content/blog"           # TODO make blog an optional command line parameter
d_drafts="drafts"               # must be outside 'content' dir
d_site="_site"                  # where makesite.py puts its generated site
post_template=".post"           # there should be a .md and a .html version

set -o nounset

redprint ()    { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }
greenprint ()  { printf "\033[1;32m%s\033[0m\n" "$*" >&2; }
yellowprint () { printf "\033[1;33m%s\033[0m\n" "$*" >&2; }
blueprint ()   { printf "\033[1;34m%s\033[0m\n" "$*" >&2; }
cyanprint ()   { printf "\033[1;36m%s\033[0m\n" "$*" >&2; }
ghostprint ()  { printf "\033[1;30m%s\033[0m\n" "$*" >&2; }

die () { redprint "ERROR: $1"; exit 1; }

# ----------------------------------------------------------------------------
#   fdfind -t f -c never -e md -e html . "$d_blog" "$d_drafts" if installed
get_all_posts () {
  find "$d_blog" "$d_drafts" -type f \( -iname "*\.md" -o -iname "*\.html" \) \
    | sed "s/^\.\///" | nl -s': ' -w4
}

# ----------------------------------------------------------------------------
get_post_by_id () {
  get_all_posts | sed -e "/^ *$1: /!d" -e "s/^.*: //"
}

# ----------------------------------------------------------------------------
# if $1 is all digits, then it's an ID, otherwise it's a file path
is_id () {
  test -z "$(echo "$1" | tr -d '0-9' || true)"
  return
}

# ----------------------------------------------------------------------------
extract_title_from_post () {
  token='<!-- title: '
  post="$1"
  is_id "$1" && post="$(get_post_by_id "$1")"
  t="$(grep -m1 "$token" "$post" 2> /dev/null | sed "s/$token\(.*\) -->/\\1/")"
  # sanitize string
  echo "$t" \
    | sed -e 's/[^A-Za-z0-9._-]/-/g' -e 's/-\+/-/g' -e 's/-$//' -e 's/^-//' \
    | tr '[:upper:]' '[:lower:]'
}    

# ----------------------------------------------------------------------------
#   $1 : $post - two possible formats
#                1. content/blog/2023-01/2023-01-01-dummy.md
#                2. drafts/2023-01-01-dummy.md
disposition () {
  # TODO check for filename collisions
  # TODO check for valid filename chars in tags
  ### subdir="$d_blog/$(date +%Y-%m)"
  post="$1"
  f="${post##*/}"        # filename: 2023-01-01-dummy.md'
  ### d="${post%/*}"         # directory: content/blog/2023-01 _or_ drafts

  do_loop=1
  while [ "$do_loop" -eq 1 ]; do
    do_loop=0
    printf "(P)ost or (S)ave draft or (D)elete draft: "
    read -r key
  
    case "$key" in
      p|P )
        d_subdir="$d_blog/$(echo "$f" | head -c7 -)"  # content/blog/2023-01
        [ -d "$d_subdir" ] || mkdir -p "$d_subdir"
        [ -f "$d_subdir/$f" ] || { mv -u "$post" "$d_subdir" || exit 1; }
        echo "$d_subdir/$f"
        ;;
      s|S )
        [ -f "$d_drafts/$f" ] || { mv -u "$post" "$d_drafts" || exit 1; }
        echo "$d_drafts/$f"
        ;;
      d|D )
        rm -i "$post" || exit 1
        ;;
      * )
        redprint "Illegal key: '$key' --> try again"
        do_loop=1
        ;;
    esac
  done
}

# ----------------------------------------------------------------------------
rebuild_indexes () {
  redprint "rebuild_indexes(): Not implemented yet!"
}

# ----------------------------------------------------------------------------
cmd_newpost () {
  [ $# -lt 2 ] || die "'new' expected 0 or 1 parameter, but got $#"
  # shell-check complains about the && followed by ||, but if we
  # change 'die' to 'echo' it doesn't complain so I'm leaving it
  fmt="md"
  if [ $# -eq 1 ]; then
    [ "$1" = '-h' ] && fmt="html" || die "Invalid parameter: $1"
  fi

  tmpfile="$(mktemp -u -t "post.XXXXXX").$fmt"
  cp "$post_template.$fmt" "$tmpfile" || exit 1

  "$EDITOR" "$tmpfile" || exit 1

  title="$(extract_title_from_post "$tmpfile")"
  slug="$(date +%Y-%m-%d)"
  slugfile="${slug}-${title}.${fmt}"
  mv "$tmpfile" "$d_drafts/$slugfile"   # TODO check for collisions

  disposition "$d_drafts/$slugfile"
}

# ----------------------------------------------------------------------------
cmd_edit () {
  [ $# -eq 1 ] || die "'edit' expected 1 parameter, but got $#"

  post="$(get_post_by_id "$1")"
  [ -n "$post" ] || die "Post $1 does not exist"

  "$EDITOR" "$post" || exit 1

  f="${post##*/}"        # filename: 2023-01-01-dummy.md'
  slug="$(echo "$f" | head -c10 -)"  # 2023-01-01
  fmt="${post##*.}"
  title="$(extract_title_from_post "$post")"
  newpost="${d_drafts}/${slug}-${title}.${fmt}"
  [ -f "$newpost" ] || { mv -u "$post" "$newpost" || exit 1; }

  disposition "$newpost"
}

# ----------------------------------------------------------------------------
cmd_list () {
  [ $# -lt 2 ] || die "'list' expected 0 or 1 parameter, but got $#"

  if [ $# -eq 1 ]; then
    get_all_posts | grep -i "$1"
  else
    get_all_posts
  fi  
}

# ----------------------------------------------------------------------------
cmd_search () {
  [ $# -eq 1 ] || die "'search' expected 1 parameter, but got $#"

  get_all_posts | while read -r line; do
    id="${line%%:*}"
    post="${line#*: }"
    match="$(grep "$1" "$post" | sed "s/^/   /")"
    if [ -n "$match" ]; then
      greenprint "    ${id}: ${post}"
      printf "%s\n" "$match"
    fi
  done
}

# ----------------------------------------------------------------------------
cmd_tags () {
  [ $# -eq 1 ] || die "'tag' expected 1 parameter, but got $#"

  get_all_posts | while read -r line; do
    id="${line%%:*}"
    post="${line#*: }"
    match="$(grep "<!-- tags:.* $1 .*-->" "$post" | sed "s/^/       /")"
    [ -n "$match" ] && printf "%4d: %s:\n" "$id" "$post"
  done
}

# ----------------------------------------------------------------------------
cmd_rename () {
  [ $# -eq 0 ] || die "'rename' expected 0 parameters, but got $#"

  get_all_posts | while read -r line; do
    post="${line#*: }"            # content/blog/2023-03/2023-03-12-a-post.md
    [ -z "$post" ] && die "Post $1 does not exist"

    # you can do this all in sed but it's ugly and hard to tweak leter on
    postfile="${post##*/}"                    # 2023-03-12-a-post.md
    postdir="${post%/*}"                      # content/blog/2023-03
    ext="${post##*.}"                         # md
    slug="$(echo "$postfile" | cut -b1-10)"   # 2023-03-12
    newtitle="$(extract_title_from_post "$post")"

    mv -u "$post" "${postdir}/${slug}-${newtitle}.${ext}" || exit 1
  done
}

# ----------------------------------------------------------------------------
cmd_delete () {
  [ $# -gt 0 ] || die "'delete' expected 1 or more parameters, but got $#"

  posts="$(for id; do get_post_by_id "$id"; done)"
  echo "$posts" | xargs -n1 -o rm -i
}

# ----------------------------------------------------------------------------
# -r recursive -t preserve modification time -z compress
# -v verbose   -u skip newer files at dest   --exclude=dir or file to exclude
# -e execute   -c checksum comparison        -l copy symlinks as symlinks
#
# publish to remote web server
#
# rsync --delete -rltzvuc -e "ssh -p 22" LOCAL/ REMOTE_USER@REMOTE_HOST:REMOTE_PATH
###replace REMOTE_USER, REMOTE_HOST, REMOTE_PATH, and change port if not 22. ex:
#note, REMOTEPATH is relative to wherever ssh has logged in.

#ex:
# rsync --delete -rltzvuc -e "ssh -p 22" $PATH1/ mrperson@guardedhost.com:${PATH1}
#...assumes that login is above 'www'. For omnis.com "../bkhome.org/" has to be prepended.
#...some hosts have "public_html" instead of "www", so you will need to modify
#   this script to change $PATH1 on the end of above example.

# publish to local web server by rsyncing _site files to local folder
# no ssh needed
# rsync --delete -rtzvcl "_site/" "$LOCAL_WWW"  # -ravc
# ----------------------------------------------------------------------------
cmd_publish () {
  [ $# -lt 2 ] || die "'publish' expected 0 or 1 parameter, but got $#"

  if [ $# -eq 0 ]; then
    [ -z "$REMOTE_USER" ] && die "Set 'REMOTE_USER=' in '.config'"
    [ -z "$REMOTE_HOST" ] && die "Set 'REMOTE_HOST=' in '.config'"
    [ -z "$REMOTE_PATH" ] && die "Set 'REMOTE_PATH=' in '.config'"
    rsync --delete -rtzvcl "$d_site/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/${d_site}"
        elif [ "$1" = "local" ]; then
          [ -z "$LOCAL_WWW" ] && die "Set 'LOCAL_WWW=' in '.config'"
          rsync --delete -rtzvcl "$d_site/" "${LOCAL_WWW}/{$d_site}"  # -ravc
        else
          die "Invalid parameter: $1"
  fi
}

# ----------------------------------------------------------------------------
show_usage () {
pgm="$(basename "$0")"
cat <<- EOF
	Usage:

	    "$pgm" new [-h]  --> type is Markdown, unless '-h' for HTML
	    "$pgm" edit <n>
	    "$pgm" delete <n> [n1] [n2] [...]
	    "$pgm" rename      [rename all posts with title from inside each]
	    "$pgm" list <string_in_filename>          [case insensitive]
	    "$pgm" search <pattern_inside_files>      [case sensitive]
	    "$pgm" tags <pattern>                     [case sensitive]
	    "$pgm" makesite
	    "$pgm" publish
	    "$pgm" test <n>
	    "$pgm" help
EOF
}

# ----------------------------------------------------------------------------
run_tests () {
  [ $# -eq 1 ] && id="$1" || id="1"
  echo; redprint "INTERNAL FUNCTIONS"
  echo ; echo "---- get_all_posts ----"
  get_all_posts
  echo ; echo "---- get_post_by_id $id ----"
  p="$(get_post_by_id "$id")"
  echo ">>>$p<<<"
  echo ; echo "---- extract_title_from_post $id ----"
  t="$(extract_title_from_post "$id")"
  echo ">>>$t<<<"
  echo ; echo "---- extract_title_from_post '$p' ----"
  t="$(extract_title_from_post "$p")"
  echo ">>>$t<<<"
  echo ; echo "---- sanitize_string '$t' ----"
  s="$(sanitize_string "$t")"
  echo ">>>$s<<<"

  echo; redprint "TOP LEVEL FUNCTIONS"
  echo ; echo "---- list  NetBSD ----"
  cmd_list "NetBSD"
  echo ; echo "---- search  NetBSD ----"
  cmd_search "NetBSD"
  echo ; echo "---- tags  NetBSD ----"
  cmd_tags "NetBSD"
}

# ----------------------------------------------------------------------------
main () {
  # sanity cheques
  [ $# -eq 0 ] && { show_usage; exit 2; }
  cmd="$1"
  shift

  if [ -z "$EDITOR" ]; then
    EDITOR="vi"
    yellowprint "\$EDITOR not set - assuming vi"
    yellowprint "Add next line to '.config' to define your editor (ex. nano)"
    cyanprint "    EDITOR='nano'\n"
    printf "Hit [Enter] to continue"
    read -r key
  fi

  [ -f ".config" ] && . "./.config"
  [ -d "$d_drafts" ] || mkdir -p "$d_drafts"

  case "$cmd" in
    new )      cmd_newpost "$@";;
    edit )     cmd_edit "$@";;
    delete )   cmd_delete "$@";;
    rename )   cmd_rename "$@";;
    list )     cmd_list "$@";;
    search )   cmd_search "$@";;
    tags)      cmd_tags "$@";;
    makesite ) rebuild_indexes; ./makesite.py;;
    publish )  cmd_publish "$@";;
    test )     run_tests "$@";;
    help )     show_usage; exit 2;;
    * )     die "Illegal command: '$cmd'";;
  esac
}

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
main "$@"
