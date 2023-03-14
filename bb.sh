#!/bin/sh

# ----------------------------------------------------------------------------
#   <!-- title: Insert post title here -->
#   <!-- tags: space delimited list of applicable tags -->
#   
#   Markdown text starts here
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
#   U S E R   D E F I N E D   P A R A M E T E R S
# ----------------------------------------------------------------------------

# webserver parameters used in 'do_publish()' to be defined in '.config'
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_PATH=""
LOCAL_WWW=""

# parameters that shouldn't need to change, but can be overridden in '.config'
d_blog="content/blog"           # TODO make blog an optional command line parameter
d_drafts="drafts"               # must be outside 'content' dir
d_site="_site"                  # where makesite.py puts its generated site
post_template=".post"

set -o nounset


# ----------------------------------------------------------------------------
redprint ()    { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }
greenprint ()  { printf "\033[1;32m%s\033[0m\n" "$*" >&2; }
yellowprint () { printf "\033[1;33m%s\033[0m\n" "$*" >&2; }
blueprint ()   { printf "\033[1;34m%s\033[0m\n" "$*" >&2; }
cyanprint ()   { printf "\033[1;36m%s\033[0m\n" "$*" >&2; }
ghostprint ()  { printf "\033[1;30m%s\033[0m\n" "$*" >&2; }

die () { redprint "ERROR: $1"; exit 1; }


# ----------------------------------------------------------------------------
show_usage () {
pgm=$(basename "$0") 
cat <<- EOF
	Usage:

	    "$pgm" post [-h]  --> file type is Markdown, unless '-h' for HTML
	    "$pgm" list [string_in_filename]
	    "$pgm" search [pattern]
	    "$pgm" tag [pattern]
	    "$pgm" edit n
	    "$pgm" rename n
	    "$pgm" delete n [n1] [n2] [...]
	    "$pgm" makesite
	    "$pgm" publish
	    "$pgm" help
EOF
}


# ----------------------------------------------------------------------------
get_posts () {
    find "$d_blog" "$d_drafts" \
        -type f \( -name "*\.md" -o -name "*\.html" \) | sed "s/\.\///"
}


# ----------------------------------------------------------------------------
get_filename_from_title () {
    [ $# -eq 1 ] || die "'get_filename_from_title' expected 1 parameter, but got $#"
    s=$(grep -m1 '<!-- title: ' "$1" | sed -e "s/<!-- title: \(.*\) -->/\\1/")
    # sanitize filename
    echo "$s" | sed -e 's/[^A-Za-z0-9._-]/-/g' -e 's/-\+/-/g' \
        tr '[:upper:]' '[:lower:]' 
}


# ----------------------------------------------------------------------------
do_post () {
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
    filename=$(get_filename_from_title "$tmpfile")
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
do_list () {
    [ $# -lt 2 ] || die "'list' expected 0 or 1 parameter, but got $#"

    [ $# -eq 1 ] && string="$1" || string='^'
    get_posts | grep -n "$string"
}


# ----------------------------------------------------------------------------
do_search () {
    [ $# -eq 1 ] || die "'search' expected 1 parameter, but got $#"

    find "$d_blog" "$d_drafts" \
        -type f \( -name "*\.md" -o -name "*\.html" \) \
        -exec grep -H "$1" "{}" \; \
        | grep -n '^'
}


# ----------------------------------------------------------------------------
do_tag () {
    [ $# -eq 1 ] || die "'tag' expected 1 parameter, but got $#"

    find "$d_blog" "$d_drafts" \
        -type f \( -name "*\.md" -o -name "*\.html" \) \
        -exec grep -Hn "$1" "{}" \;
}


# ----------------------------------------------------------------------------
do_edit () {
    [ $# -ne 1 ] && die "'edit' expected 1 parameter, but got $#"

    post=$(get_posts | grep -n "^" | grep "^$1:" | sed "s/^$1://")
    [ -z "$post" ] && die "Item $1 does not exist"

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
do_rename () {
    [ $# -ne 1 ] && die "'rename' expected 1 parameter, but got $#"

    post=$(get_posts | grep -n "^" | grep "^$1:" | sed "s/^$1://")
    [ -z "$post" ] && die "Item $1 does not exist"
    die "TODO: rename command not implemented yet"
    # get filename from title
}


# ----------------------------------------------------------------------------
do_delete () {
    [ $# -eq 0 ] && die "'delete' expected 1 or more parameters, but got $#"

    for i; do
        file=$(get_posts | grep -n "^" | grep "^$i:" | sed "s/^$i://")
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
do_publish () {
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
#
# ----------------------------------------------------------------------------
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
    post )     do_post "$@";;
    list )     do_list "$@";;
    search )   do_search "$@";;
    edit )     do_edit "$@";;
    rename )   do_rename "$@";;
    delete )   do_delete "$@";;
    makesite ) ./makesite.py;;
    publish )  do_publish "$@";;
    help )     show_usage; exit 2;;
       * )     die "Illegal command: '$cmd'";;
esac
