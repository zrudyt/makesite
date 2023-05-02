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
get_json_param () {
  if [ -e "params.json" ]; then
    match="$(grep "\"$1\": " "params.json" 2> /dev/null)"
    match="${match#*: \"}"
    match="${match%\"*}"
  else
    match=""
  fi
  printf "%s" "$match"
}

# ----------------------------------------------------------------------------
#   U S E R   D E F I N E D   P A R A M E T E R S   A N D   V A R I A B L E S
# ----------------------------------------------------------------------------
# webserver parameters for cmd_publish() to be defined in 'params.json'
REMOTE_USER="$(get_json_param "remote_user")"
REMOTE_HOST="$(get_json_param "remote_host")"
REMOTE_PATH="$(get_json_param "remote_path")"

# these are used by makesite.py, and used in this script only for (V)iew post
SITE_URL="$(get_json_param "site_url")"
BASE_PATH="$(get_json_param "base_path")"

BLOG="${BLOG:-"blog"}"    # env var to access other blogs like BLOG=news ss.sh

post_template=".post"           # there should be a .md and a .html version

# parameters that shouldn't need to change unless makesite.py changes
d_blog="content/$BLOG"
d_drafts="drafts"               # must be outside 'content' dir
d_site="_site"                  # where makesite.py puts its generated site

set -o nounset

# ----------------------------------------------------------------------------
#   U T I L I T Y   F U N C T I O N S
# ----------------------------------------------------------------------------
redprint ()    { printf "\033[1;31m%s\033[0m\n" "$1" >&2; }
greenprint ()  { printf "\033[0;32m%s\033[0m\n" "$1" >&2; }
yellowprint () { printf "\033[0;33m%s\033[0m\n" "$1" >&2; }
blueprint ()   { printf "\033[0;34m%s\033[0m\n" "$1" >&2; }
cyanprint ()   { printf "\033[0;36m%s\033[0m\n" "$1" >&2; }
ghostprint ()  { printf "\033[0;30m%s\033[0m\n" "$1" >&2; }
promptlite ()  { printf "\033[0;32m%s: \033[0m"   "$1" >&2; }  # no \n at EOL
prompt ()      { printf "\033[1;32m%s: \033[0m"   "$1" >&2; }  # no \n at EOL

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
  test -z "$(printf "%s" "$1" | tr -d '[:digit:]' || true)"
}

# ----------------------------------------------------------------------------
extract_title_from_post () {
  token='<!-- title: '
  is_id "$1" && post="$(get_post_by_id "$1")"
  t="$(grep -m1 "$token" "$1" 2> /dev/null | sed "s/$token\(.*\) -->/\\1/")"
  # sanitize string
  printf "%s" "$t" \
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
  bad_chars=$(printf "%s" "$tags" | tr -d 'A-Za-z0-9_\-\ ')
  test -n "$bad_chars"
  return $?
}

# ----------------------------------------------------------------------------
edit_and_validate () {
  valid="false"
  while [ "$valid" = "false" ]; do
    "$EDITOR" "$1" || exit 1
    if has_invalid_tags "$1"; then
      printf "%s" "$1"; redprint " <-- has invalid tag(s)"
      printf "    Tags: %s\n" "$tags"
      promptlite "Hit any key to re-edit file or Ctrl-C to abort"
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
  post="$1"

  f="${post##*/}"        # f: 2023-01-01-title.md'
  do_loop="true"
  while [ "$do_loop" = "true" ]; do
    do_loop="false"
    ps="(P)ost, (E)dit, save (D)raft, (R)emove"
    [ "${post%/*}" = "$d_drafts" ] || ps="$ps, (V)iew in browser"
    prompt "$ps"
    read -r key
    case "$key" in
      p|P )
        d_subdir="$d_blog/$(echo "$f" | head -c7 -)"  # content/blog/2023-01
        [ -d "$d_subdir" ] || mkdir -p "$d_subdir"
        [ -f "$d_subdir/$f" ] || { mv -i -u "$post" "$d_subdir" || exit 1; }
        echo "$d_subdir/$f"
        cmd_rebuild
        ;;
      e|E )
        edit_and_validate "$post"
        do_loop="true"
        ;;
      v|V )                              # View in broswer
        if [ "${post%/*}" = "$d_drafts" ]; then
          redprint "Illegal key: '$key' --> try again"
        else
          [ -n "$BASE_PATH" ] && SITE_URL="$SITE_URL/$BASE_PATH"
          url="$SITE_URL/$BLOG"
          # TODO use sed
          url="$url/$(echo "$f" | head -c7 -)/$(echo "$f" | tail -c+12 -)"
          echo "${url%.*}"
          cmd_rebuild
          "$BROWSER" "${url%.*}"
        fi
        do_loop="true"
        ;;
      d|D )                              # save as Draft
        [ -f "$d_drafts/$f" ] || { mv -i -u "$post" "$d_drafts" || exit 1; }
        echo "$d_drafts/$f"
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
  printf "%s" "Rebulding ... "
  cmd_rebuild # > /dev/null 2>&1
  printf "%s\n" "Done."
}

# ----------------------------------------------------------------------------
cmd_edit () {
  [ $# -eq 1 ] || die "'edit' expected 1 parameter, but got $#"

  post="$1"
  is_id "$1" && post="$(get_post_by_id "$1")"
  [ -n "$post" ] || die "Post $1 does not exist"

  edit_and_validate "$post"

  d_orig="${post%/*}"                     # drafts  *OR* content/blog/subdir
  f_post="${post##*/}"  # 2023-01-01-title.md  *OR* .2023-01-01-newpost.md.XXXX
  if [ -z "${f_post##.*}" ]; then         # .2023-01-01-newpost.md.XXXX
    f_post="${f_post#.}"                  # 2023-01-01-newpost.md.XXXX
    f_post="${f_post%.*}"                 # 2023-01-01-newpost.md
  fi

  slug="$(printf "%s" "$f_post" | head -c10 -)"  # 2023-01-01
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
  [ -n "$posts" ] && { printf "%s" "$posts" | xargs -n1 -o rm -i; }
}

# ----------------------------------------------------------------------------
cmd_rebuild () {
  [ $# -eq 0 ] || die "'publish' expected 0 parameters, but got $#"

  get_all_posts | while read -r line; do
    post="${line#*: }"               # content/blog/2023-03/2023-03-12-post.md
    [ -z "$post" ] && die "Post '$post' does not exist"

    has_invalid_tags "$post" \
      && { printf "%s" "$line"; yellowprint " <-- has invalid tag(s)"; continue; }

    postfile="${post##*/}"                              # 2023-03-12-post.md
    oldtitle="$(printf "%s" "${postfile%.*}" | cut -b12-)"     # post
    newtitle="$(extract_title_from_post "$post")"
    if [ "$oldtitle" != "$newtitle" ]; then
      postdir="${post%/*}"                              # content/blog/2023-03
      ext="${post##*.}"                                 # md
      slug="$(printf "%s" "$postfile" | cut -b1-10)"           # 2023-03-12
      mv -i -u "$post" "${postdir}/${slug}-${newtitle}.${ext}" || exit 1
    fi
  done

  ./makesite.py  > /dev/null
  # generates local site in _site directory, which is where we point our local
  # webserver to. If the local webserver root is somewhere else, then use
  # rsync (Note: wasteful since we now have 2 copies of the site)
  # [ -z "$LOCAL_WWW" ] && die "Set 'LOCAL_WWW=' in 'params.json'"
  # rsync --delete -rtzvcl "$d_site/" "${LOCAL_WWW}/${d_site}"  # -ravc
  # Two other alternatives are (1) _site is a symbolic link, or (2) change
  # makesite.py to output directly into the local webserver root directory
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

  [ -z "$REMOTE_USER" ] && die "Set 'REMOTE_USER=' in 'params.json'"
  [ -z "$REMOTE_HOST" ] && die "Set 'REMOTE_HOST=' in 'params.json'"
  [ -z "$REMOTE_PATH" ] && die "Set 'REMOTE_PATH=' in 'params.json'"

  cmd_rebuild
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
	    "$pgm" rebuild
	    "$pgm" test <n>
	    "$pgm" help
EOF
}

# ----------------------------------------------------------------------------
do_sanity_cheques () {
  # TODO no message if defaulteditor or defaultbrowser
  # TODO check for SS_EDITOR and SS_BROWSER
  if [ -z "$EDITOR" ]; then
    EDITOR="vi"
    yellowprint "\$EDITOR not set - assuming 'vi'"
    yellowprint "Add next line to 'params.json' to set your editor (ex. nano)"
    cyanprint "    EDITOR='nano'\n"
    prompt "Hit [Enter] to continue"
    read -r key
  fi

  if [ -z "$BROWSER" ]; then
    BROWSER="defaultbrowser"
    yellowprint "\$BROWSER not set - assuming 'defaultbrowser'"
    yellowprint "Add next line to 'params.json' to set your browser (ex. firefox)"
    cyanprint "    BROWSER='firefox'\n"
    prompt "Hit [Enter] to continue"
    read -r key
  fi
}

# ----------------------------------------------------------------------------
main () {
  [ $# -eq 0 ] && { show_usage; exit 2; }
  do_sanity_cheques
  cmd="$1"
  shift

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
