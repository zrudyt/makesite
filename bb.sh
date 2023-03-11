#!/bin/sh

set -o nounset

rootdir=$(dirname "$0")
blogdir="$rootdir/content/blog"    # TODO make blog an optional command line parameter
post_template="$rootdir/.post"

die () { echo "ERROR: $1"; exit 1; }

show_usage () {
cat <<- EOF
	Usage: $(basename "$0") <command> [parameter 1] [parameter 2] [...] [parameter n]
	
	where <command> is:
	
	    post [-h]  --> default file type is Markdown, unless '-h' for HTML
	    list [pattern]
	    edit n
	    delete n
	    rebuild
	    publish
	    help
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
    if [ $# -eq 0 ]; then
        fmt="md"
    elif [ "$1" = '-h' ]; then
        fmt="html"
    else
        die "Invalid parameter to: $1"
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
do_list () {
    [ $# -eq 0 ] || die "expected 0 parameters (got $#)"

    posts=$(find "$blogdir" -type f \( -name "*\.md" -o -name "*\.html" \))
    if [ $# -eq 1 ]; then
        echo "$posts" | grep -n "$1"
    else
        echo "$posts" | grep -n "^"
    fi
}


# ----------------------------------------------------------------------------
do_edit () {
    [ $# -ne 1 ] && die "expected 1 parameter (got $#)"

    posts=$(find "$blogdir" -type f \( -name "*\.md" -o -name "*\.html" \))

    post=$(echo "$posts" | grep -n "^" | grep "^$1:" | sed "s/^$1://")
    "$EDITOR" "$post" || exit 1
}


# ----------------------------------------------------------------------------
do_delete () {
    [ $# -eq 0 ] && die "expected 1 or more parameters (got $#)"

    posts=$(find "$blogdir" -type f \( -name "*\.md" -o -name "*\.html" \))

    for del; do
        file=$(echo "$posts" | grep -n "^" | grep "^$del:" | sed "s/^$del://")
        rm -i "$file"
    done
}


# ----------------------------------------------------------------------------
do_rebuild () {
    ./makesite.py
}


# ----------------------------------------------------------------------------
do_publish () {
    true   # placeholder for future code
}


# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
[ $# -eq 0 ] && { show_usage; exit 2; }
[ -e ".config" ] && . ".config"

cmd="$1"
shift

case "$cmd" in
    post )    do_post "$@";;
    list )    do_list "$@";;
    edit )    do_edit "$@";;
    delete )  do_delete "$@";;
    rebuild ) do_rebuild "$@";;
    publish ) do_publish "$@";;
    help )    show_usage; exit 2;;
       * )    die "Illegal command: '$cmd'";;
esac
