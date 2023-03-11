#!/bin/sh

set -o nounset

rootdir=$(dirname "$0")
blogdir="$rootdir/content/blog"    # TODO make blog an optional command line parameter
post_template="$rootdir/.post"

show_usage () {
cat <<- EOF
	Usage: $(basename "$0") <command> [parameter 1] [parameter 2] [...] [parameter n]
	
	where <command> is:
	
	    post [-h]  --> default file type is Markdown, unless '-h' for HTML
	    edit title --> title is either filename, filename.md, or filename.html
	    list
	    rebuild
EOF
}


# ----------------------------------------------------------------------------
#   <!-- title: Insert post title here -->
#   <!-- tags: space delimited list of applicable tags -->
#   
#   Markdown text starts here
# ----------------------------------------------------------------------------
#   <!-- title: Hello world -->
#   <!-- tags: test -->
#   
#   Hello world!
# ----------------------------------------------------------------------------
do_post () {
    if [ $# -eq 1 ]; then
        fmt="md"
    elif [ "$2" = '-h' ]; then
        fmt="html"
    else
        { echo "ERROR: Invalid parameter to post: $2"; exit 1; }
    fi

    subdir="$blogdir/$(date +%Y-%m)"
    slug=$(date +%Y-%m-%d)

    tmpfile="$(mktemp -u -t "post.XXXXXX").$fmt"
    [ -d "$subdir" ] || mkdir -p "$subdir"

    cp "$post_template.$fmt" "$tmpfile" || exit 1
    "$EDITOR" "$tmpfile" || exit 1
    filename=$(grep -m1 '<!-- title: ' "$tmpfile" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e "s/<!-- title: \(.*\) -->/\\1/" -e "s/ /-/g")
    mv "$tmpfile" "$subdir/$slug-$filename.$fmt" || exit 1
    ./makesite.py
}


# ----------------------------------------------------------------------------
do_edit () {
    [ $# -eq 2 ] || { echo "PANIC: 'edit' requires 1 parameter"; exit 2; }
}


# ----------------------------------------------------------------------------
do_list () {
    [ $# -eq 1 ] || { echo "PANIC: 'list' requires 0 parameters"; exit 2; }
}


# ----------------------------------------------------------------------------
do_publish () {
    if [ $# -eq 2 ]; then
        loc="md"
    elif [ "$2" = '-h' ]; then
        fmt="html"
    else
        { echo "ERROR: Invalid parameter to post: $2"; exit 1; }
    fi
}


# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
[ $# -eq 0 ] && { echo "Not enough parameters"; show_usage; exit 2; }
[ -e ".config" ] && . ".config"

cmd="$1"

case "$1" in
    post )    do_post "$@";;
    edit )    do_edit "$@";;
    list )    do_list "$@";;
    publish ) do_publish "$@";;
    help )    show_usage; exit 2;;
       * )    echo "Illegal command '$1'"; show_usage; exit 2;;
esac
