#!/bin/sh

# shellcheck shell=dash

# ============================================================================
#  ss.sh - shell site : simple shell blogging front end for makesite
# ============================================================================
#  Copyright (c) 2023 zrudyt <zrudyt@ at hotmail dot com>
#  All rights reserved
# ----------------------------------------------------------------------------
#  This script ...
#
#   TODO separate executable and content dirs
#   TODO combine params.json and .config into one single file
#
#   Pre-requisites:
#
#   - POSIX shell (sh, ash, dash, etc.)
#   - Python 3.8 or better to run makesite.py

#   Installation notes:
#
#     This script (ss.sh), makesite.py along with all related content,
#     layout and configuration files must be in the same directory tree.
# ----------------------------------------------------------------------------
#  The MIT License (MIT)
#
#  Permission is hereby granted, free of charge, to any person obtaining a
#  copy of this software and associated documentation files (the "Software"),
#  to deal in the Software without restriction, including without limitation
#  the rights to use, copy, modify, merge, publish, distribute, sublicense,
#  and/or sell copies of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be
#  included in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
#  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
#  DEALINGS IN THE SOFTWARE.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
#   U S E R   D E F I N E D   P A R A M E T E R S
# ----------------------------------------------------------------------------
# webserver parameters used in 'cmd_publish()' to be defined in '.config'
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_PATH=""

BLOG="${BLOG:-"blog"}"          # can access other blogs like BLOG=news ss.sh

# ----------------------------------------------------------------------------
#  G L O B A L   P A R A M E T E R S   A N D   V A R I A B L E S
# ----------------------------------------------------------------------------
# parameters that shouldn't need to change, but can be overridden in '.config'
d_blog="content/$BLOG"
d_drafts="drafts"               # must be outside 'content' dir
d_site="_site"                  # where makesite.py puts its generated site
post_template=".post"           # there should be a .md and a .html version

set -o nounset

redprint ()    { printf "\033[1;31m%s\033[0m\n" "$1" >&2; }
greenprint ()  { printf "\033[0;32m%s\033[0m\n" "$1" >&2; }
yellowprint () { printf "\033[0;33m%s\033[0m\n" "$1" >&2; }
blueprint ()   { printf "\033[0;34m%s\033[0m\n" "$1" >&2; }
cyanprint ()   { printf "\033[0;36m%s\033[0m\n" "$1" >&2; }
ghostprint ()  { printf "\033[0;30m%s\033[0m\n" "$1" >&2; }
promptlite ()  { printf "\033[0;32m%s\033[0m"   "$1" >&2; }  # no \n at EOL
prompt ()      { printf "\033[1;32m%s\033[0m"   "$1" >&2; }  # no \n at EOL

die () { redprint "ERROR: $1"; exit 1; }

# ----------------------------------------------------------------------------
#   fdfind -t f -c never -e md -e html . "$d_blog" "$d_drafts" if installed
# ----------------------------------------------------------------------------
get_all_posts () {
  find "$d_blog" "$d_drafts" -type f \( -iname "*\.md" -o -iname "*\.html" \) \
    | sort \
    | sed "s/^\.\///" \
    | nl -s': ' -w4
}

# ----------------------------------------------------------------------------
get_post_by_id () {
  get_all_posts | sed -e "/^ *$1: /!d" -e "s/^.*: //"
}

# ----------------------------------------------------------------------------
#   if $1 is all digits, then it's an ID, otherwise it's a file path
# ----------------------------------------------------------------------------
is_id () {
  test -z "$(echo "$1" | tr -d '[:digit;]' || true)"
}

# ----------------------------------------------------------------------------
extract_title_from_post () {
  token='<!-- title: '
  is_id "$1" && post="$(get_post_by_id "$1")"
  t="$(grep -m1 "$token" "$1" 2> /dev/null | sed "s/$token\(.*\) -->/\\1/")"
  # sanitize string
  echo "$t" \
    | sed -e 's/[^A-Za-z0-9_-]/-/g' -e 's/-\+/-/g' -e 's/-$//' -e 's/^-//' \
    | tr '[:upper:]' '[:lower:]'
}

# ----------------------------------------------------------------------------
#   function checks for tags with illegal characters because makesite.py
#   creates index file for each tag --> don't want invalid chars in filenames
#
#   $1 : $post
# ----------------------------------------------------------------------------
has_invalid_tags () {
  # delete all valid characters from string, leaving only characters
  # that we don't want to use in filenames
  tags="$(sed -n "s/<!-- tags: \+\(.*\) -->/\\1/p" "$1")"
  bad_chars=$(echo "$tags" | tr -d 'A-Za-z0-9_\-\ ')
  test -n "$bad_chars"
  return $?
}

# ----------------------------------------------------------------------------
rebuild_all () {
  get_all_posts | while read -r line; do
    post="${line#*: }"               # content/blog/2023-03/2023-03-12-post.md
    [ -z "$post" ] && die "Post '$post' does not exist"

    has_invalid_tags "$post" \
      && { echo -n "$line"; yellowprint " <-- has invalid tag(s)"; continue; }

    postfile="${post##*/}"                              # 2023-03-12-post.md
    oldtitle="$(echo "${postfile%.*}" | cut -b12-)"     # post
    newtitle="$(extract_title_from_post "$post")"
    if [ "$oldtitle" != "$newtitle" ]; then
      postdir="${post%/*}"                              # content/blog/2023-03
      ext="${post##*.}"                                 # md
      slug="$(echo "$postfile" | cut -b1-10)"           # 2023-03-12
      mv -i -u "$post" "${postdir}/${slug}-${newtitle}.${ext}" || exit 1
    fi
  done
}

# ----------------------------------------------------------------------------
edit_and_validate () {
  valid="false"
  while [ "$valid" = "false" ]; do
    "$EDITOR" "$1" || exit 1
    if has_invalid_tags "$1"; then
      echo -n "$1"; yellowprint " <-- has invalid tag(s)"
      echo "    Tags: $tags"
      promptlite "Hit any key to re-edit file: "
      read -r key
    else
      valid="true"
    fi
  done
}

# ----------------------------------------------------------------------------
#   Usage: do_actions <post>
#     $post : three possible formats
#             1. content/blog/2023-01/2023-01-01-title.md
#             2. drafts/2023-01-01-title.md
#             3. drafts/.2023-01-01-title.md.XXXX
#   NO RECURSION ALLOWED - this function must not call cmd_edit() because
#   we're already in cmd_edit()
# ----------------------------------------------------------------------------
do_actions () {
  # TODO (V)iew in browser
  key=""
  [ $# -eq 2 ] && { key="$1"; shift; }
  post="$1"

  f="${post##*/}"        # filename: 2023-01-01-title.md'
  do_loop="true"
  while [ "$do_loop" = "true" ]; do
    do_loop="false"
    if [ -z "$key" ]; then
      prompt "(P)ost, (E)dit, save as (D)raft, (L)eave in existing dir, or (R)emove file: "
      read -r key
    fi
    case "$key" in
      p|P )
        d_subdir="$d_blog/$(echo "$f" | head -c7 -)"  # content/blog/2023-01
        [ -d "$d_subdir" ] || mkdir -p "$d_subdir"
        [ -f "$d_subdir/$f" ] || { mv -i -u "$post" "$d_subdir" || exit 1; }
        echo "$d_subdir/$f"
        ;;
      e|E )
        return 1
        ;;
      d|D )
        [ -f "$d_drafts/$f" ] || { mv -i -u "$post" "$d_drafts" || exit 1; }
        echo "$d_drafts/$f"
        ;;
      l|L )
        echo "$post"
        ;;
      r|R )
        rm -i "$post" || exit 1
        ;;
      * )
        redprint "Illegal key: '$key' --> try again"
        do_loop="true"
        ;;
    esac
  done
  echo -n "Rebulding ... "
  cmd_makesite > /dev/null 2>&1
  echo "Done."
}

# ----------------------------------------------------------------------------
cmd_edit () {
  [ $# -eq 1 ] || die "'edit' expected 1 parameter, but got $#"

  post="$1"
  is_id "$1" && post="$(get_post_by_id "$1")"
  [ -n "$post" ] || die "Post $1 does not exist"

  edit_and_validate "$post"

  d_orig="${post%/*}"   # drafts  *OR* content/blog/subdir
  f_post="${post##*/}"  # 2023-01-01-title.md  *OR* .2023-01-01-newpost.md.XXXX
  if [ -z "${f_post##.*}" ]; then  # .2023-01-01-newpost.md.XXXX
    f_post="${f_post#.}"           # 2023-01-01-newpost.md.XXXX
    f_post="${f_post%.*}"          # 2023-01-01-newpost.md
  fi

  slug="$(echo "$f_post" | head -c10 -)"  # 2023-01-01
  fmt="${f_post##*.}"
  title="$(extract_title_from_post "$post")"
  newpost="${d_orig}/${slug}-${title}.${fmt}"
  # the following line just renames the file - it doesn't *move* it
  [ -f "$newpost" ] || { mv -i -u "$post" "$newpost" || exit 1; }

  do_actions "$newpost"
}

# ----------------------------------------------------------------------------
cmd_newpost () {
  [ $# -lt 2 ] || die "'new' expected 0 or 1 parameter, but got $#"
  fmt="md"
  if [ $# -eq 1 ]; then
    # shell-check complains about the && followed by ||, but if we
    # change 'die' to 'echo' it doesn't complain so I'm leaving it
    [ "$1" = '-h' ] && fmt="html" || die "Invalid parameter: $1"
  fi

  slug="$(date +%Y-%m-%d)"
  tmpfile="$(mktemp -p "$d_drafts" -t ".${slug}-newpost.${fmt}.XXXX")"
  cp "$post_template.$fmt" "$tmpfile" || exit 1

  cmd_edit "$tmpfile"
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
cmd_delete () {
  [ $# -gt 0 ] || die "'delete' expected 1 or more parameters, but got $#"

  posts="$(for id; do get_post_by_id "$id"; done)"
  [ -n "$posts" ] && { echo "$posts" | xargs -n1 -o rm -i; }
}

# ----------------------------------------------------------------------------
cmd_rebuild () {
  [ $# -eq 0 ] || die "'publish' expected 0 parameters, but got $#"

  rebuild_all
  ./makesite.py 2> /dev/null  # this program uses STDERR for routine output 2> /dev/null  # this program uses STDERR for routine output
  # [ -z "$LOCAL_WWW" ] && die "Set 'LOCAL_WWW=' in '.config'"
  # rsync --delete -rtzvcl "$d_site/" "${LOCAL_WWW}/${d_site}"  # -ravc
}

# ----------------------------------------------------------------------------
# publish to remote web server
# note, REMOTEPATH is relative to wherever ssh has logged in.
# rsync --delete -rltzvuc LOCAL/ REMOTE_USER@REMOTE_HOST:REMOTE_PATH
#
# publish to local web server by rsyncing _site files to local WWW root
# rsync --delete -rtzvcl "_site/" "$LOCAL_WWW"  # -ravc
# ----------------------------------------------------------------------------
cmd_publish () {
  [ $# -eq 0 ] || die "'publish' expected 0 parameters, but got $#"

  [ -z "$REMOTE_USER" ] && die "Set 'REMOTE_USER=' in '.config'"
  [ -z "$REMOTE_HOST" ] && die "Set 'REMOTE_HOST=' in '.config'"
  [ -z "$REMOTE_PATH" ] && die "Set 'REMOTE_PATH=' in '.config'"

  cmd_makesite
  rsync --delete -rltzvc "$d_site/" \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/${d_site}"
}

# ----------------------------------------------------------------------------
show_usage () {
pgm="$(basename "$0")"
cat <<- EOF
	Usage:

	    "$pgm" new [-h]  --> type is Markdown, unless '-h' for HTML
	    "$pgm" edit <n>
	    "$pgm" delete <n> [n1] [n2] [...]
	    "$pgm" list <string_in_filename>          [case insensitive]
	    "$pgm" search <pattern_inside_files>      [case sensitive]
	    "$pgm" tags <pattern>                     [case sensitive]
	    "$pgm" publish
	    "$pgm" rebuild                    [check titles vs filenames and regen]
	    "$pgm" test <n>
	    "$pgm" help
EOF
}

# ----------------------------------------------------------------------------
do_sanity_cheques () {
  # TODO no message if defaulteditor or defaultbrowser
  if [ -z "$EDITOR" ]; then
    EDITOR="vi"
    yellowprint "\$EDITOR not set - assuming 'vi'"
    yellowprint "Add next line to '.config' to set your editor (ex. nano)"
    cyanprint "    EDITOR='nano'\n"
    prompt "Hit [Enter] to continue "
    read -r key
  fi

  if [ -z "$BROWSER" ]; then
    BROWSER="defaultbrowser"
    yellowprint "\$BROWSER not set - assuming 'defaultbrowser'"
    yellowprint "Add next line to '.config' to set your browser (ex. firefox)"
    cyanprint "    BROWSER='firefox'\n"
    prompt "Hit [Enter] to continue "
    read -r key
  fi
}

# ----------------------------------------------------------------------------
main () {
  [ $# -eq 0 ] && { show_usage; exit 2; }
  do_sanity_cheques
  cmd="$1"
  shift

  [ -f ".config" ] && . "./.config"
  [ -d "$d_drafts" ] || mkdir -p "$d_drafts"

  case "$cmd" in
    new )      cmd_newpost "$@";;
    edit )     cmd_edit "$@";;
    delete )   cmd_delete "$@";;
    list )     cmd_list "$@";;
    search )   cmd_search "$@";;
    tags)      cmd_tags "$@";;
    publish )  cmd_publish "$@";;
    rebuild )  cmd_rebuild "$@";;
    help )     show_usage; exit 2;;
    * )     die "Illegal command: '$cmd'";;
  esac
}

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
main "$@"
