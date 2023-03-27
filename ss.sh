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
#   - Python 3.6 or better tu run makesite.py

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
post_template=".post"

set -o nounset

redprint ()    { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }
greenprint ()  { printf "\033[1;32m%s\033[0m\n" "$*" >&2; }
yellowprint () { printf "\033[1;33m%s\033[0m\n" "$*" >&2; }
blueprint ()   { printf "\033[1;34m%s\033[0m\n" "$*" >&2; }
cyanprint ()   { printf "\033[1;36m%s\033[0m\n" "$*" >&2; }
ghostprint ()  { printf "\033[1;30m%s\033[0m\n" "$*" >&2; }

die () { redprint "ERROR: $1"; exit 1; }

# ----------------------------------------------------------------------------
get_all_posts () {
    find "$d_blog" "$d_drafts" \
        -type f \( -name "*\.md" -o -name "*\.html" \) | sed "s/^\.\///"
}

# ----------------------------------------------------------------------------
get_post_by_id () {
    # TODO combine grep and sed
    post=$(get_all_posts | grep -n "." | grep "^$1:" | sed "s/^$1://")
    #post=$(get_all_posts | nl -s':' -w1 | grep "^$1:" | sed "s/^$1://")
    [ -z "$post" ] && die "Item $1 does not exist"  # TODO move to caller
    echo "$post"
}

# ----------------------------------------------------------------------------
extract_title_from_post () {
    [ $# -eq 1 ] || die "'extract_title_from_post' expected 1 parameter, but got $#"
    title=$(grep -m1 '<!-- title: ' "$1" | sed -e "s/<!-- title: \(.*\) -->/\\1/")
    [ -z "$title" ] && die "Post $1 does not have a title"  # TODO move to caller
    echo "$title"
}

# ----------------------------------------------------------------------------
sanitize_string () {
    [ $# -eq 1 ] || die "'sanitize_string' expected 1 parameter, but got $#"
    echo "$1" | sed -e 's/[^A-Za-z0-9._-]/-/g' -e 's/-\+/-/g' \
        | tr '[:upper:]' '[:lower:]'
}

# ----------------------------------------------------------------------------
# TODO split edit and post
cmd_post () {
    if [ $# -eq 0 ]; then
        fmt="md"
    elif [ "$1" = '-h' ]; then
        fmt="html"
    else
        die "Invalid parameter: $1"
    fi

    subdir="$d_blog/$(date +%Y-%m)"
    slug=$(date +%Y-%m-%d)

    tmpfile="$(mktemp -u -t "post.XXXXXX").$fmt"
    [ -d "$subdir" ] || mkdir -p "$subdir"

    cp "$post_template.$fmt" "$tmpfile" || exit 1
    "$EDITOR" "$tmpfile" || exit 1
    filename=$(sanitize_string "$tmpfile")
    post="${slug}-${filename}.${fmt}"

    printf "(P)ost or (D)raft or (A)bort: "
    read -r key

    if [ "$key" = 'p' ]; then
        mv "$tmpfile" "$subdir/$post" || exit 1
        echo "$subdir/$post"
    elif [ "$key" = 'd' ]; then
        mv "$tmpfile" "$d_drafts/$post" || exit 1
        echo "$d_drafts/$post"
    elif [ "$key" = 'a' ]; then
        rm -i "$tmpfile" || exit 1
    else
        echo "Invalid response - post saved as '$tmpfile'"
    fi
}

# ----------------------------------------------------------------------------
cmd_list () {
    [ $# -lt 2 ] || die "'list' expected 0 or 1 parameter, but got $#"

    [ $# -eq 1 ] && string="$1" || string='.'
    get_all_posts | grep -n "$string"
}

# ----------------------------------------------------------------------------
cmd_search () {
    [ $# -eq 1 ] || die "'search' expected 1 parameter, but got $#"

    find "$d_blog" "$d_drafts" \
        -type f \( -name "*\.md" -o -name "*\.html" \) \
        -exec grep -H "$1" "{}" \; \
        | grep -n '^'
}

# ----------------------------------------------------------------------------
cmd_tags () {
    [ $# -eq 1 ] || die "'tag' expected 1 parameter, but got $#"

    find "$d_blog" "$d_drafts" \
        -type f \( -name "*\.md" -o -name "*\.html" \) \
        -exec grep -Hn "$1" "{}" \;
}

# ----------------------------------------------------------------------------
cmd_edit () {
    [ $# -ne 1 ] && die "'edit' expected 1 parameter, but got $#"

    post="$(get_post_by_id "$1")"
    "$EDITOR" "$post" || exit 1

    d_post=$(readlink -f $(dirname "$post"))
    d_drafts=$(readlink -f "$d_drafts")
    printf "(P)ost or (D)raft: "
    read -r key

    valid=0
    while [ "$valid" -eq 0 ]; do
        if [ "$key" = 'p' ]; then
            echo "file://$(readlink -f "$subdir/$post")"
            valid=1
        elif [ "$key" = 'd' ]; then
            [ "$d_post" != "$d_drafts" ] && { mv "$post" "$d_drafts" || exit 1; }
            echo "file://$(readlink -f "$post")"
            valid=1
        else
            echo "Invalid response - try again"
        fi
    done
}

# ----------------------------------------------------------------------------
cmd_rename () {
    [ $# -ne 2 ] && die "'rename' expected 2 parameters, but got $#"

    post="$(get_post_by_id "$1")"  # content/blog/2023-03/2023-03-12-a-post.md

    # you can do this all in sed but it's ugly and hard to tweak leter on
    postfile="${post##*/}"                    # 2023-03-12-a-post.md
    postdir="${post%/*}"                      # content/blog/2023-03
    ext="${post##*.}"                         # md
    slug="$(echo "$postfile" | cut -b1-10)"   # 2023-03-12
    # title="$(echo "$postfile" | cut -b12-)"   # a-post.md
    # title="${title%.*}"                       # a-post
    newtitle="$(sanitize_string "$2")"
    echo "mv"
    echo "    $post"
    echo "    ${postdir}/${slug}-${newtitle}.${ext}"
    exit 1
  }

# ----------------------------------------------------------------------------
cmd_delete () {
    [ $# -eq 0 ] && die "'delete' expected 1 or more parameters, but got $#"

    for i; do
        file=$(get_all_posts | grep -n "." | grep "^$i:" | sed "s/^$i://")
        [ -n "$file" ] && { rm -i "$file" || exit 1; }
    done
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

	    "$pgm" post [-h]  --> file type is Markdown, unless '-h' for HTML
	    "$pgm" list [string_in_filename]
	    "$pgm" search [pattern]
	    "$pgm" tags [pattern]
	    "$pgm" edit n
	    "$pgm" rename n
	    "$pgm" delete n [n1] [n2] [...]
	    "$pgm" makesite
	    "$pgm" publish
	    "$pgm" help
EOF
}

# ----------------------------------------------------------------------------
main () {
    d_root="$(dirname "$0")"
    cd "$d_root" || exit 1
    [ -f ".config" ] && . "./.config"
    [ -d "$d_drafts" ] || mkdir -p "$d_drafts"

    # sanity cheques
    [ $# -eq 0 ] && { show_usage; exit 2; }
    if [ -z "$EDITOR" ]; then
        EDITOR="vi"
        yellowprint "\$EDITOR not set - assuming vi"
        yellowprint "Add next line to '.config' to define your editor (ex. nano)"
        cyanprint "    EDITOR='nano'\n"
        printf "Hit [Enter] to continue"
        read -r key
    fi

    cmd="$1"
    shift

    case "$cmd" in
        post )     cmd_post "$@";;
        list )     cmd_list "$@";;
        search )   cmd_search "$@";;
        tags)      cmd_tags "$@";;
        edit )     cmd_edit "$@";;
        rename )   cmd_rename "$@";;
        delete )   cmd_delete "$@";;
        makesite ) ./makesite.py;;
        publish )  cmd_publish "$@";;
        help )     show_usage; exit 2;;
           * )     die "Illegal command: '$cmd'";;
    esac
}

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
main "$@"
