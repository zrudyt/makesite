#!/usr/bin/env python

# The MIT License (MIT)
#
# Copyright (c) 2022-2023 zrudyt zrudyt@hotmail.com>
# All rights reserved
#
# This software is a derivative of the original makesite.py
# The license text of the original makesite.py is included below.
#
# Copyright (c) 2018 Sunaina Pai
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


"""Make static website/blog with Python."""


import os
import shutil
import re
import glob
import sys
import json
import datetime
from pathlib import Path


def fread(filename):
    """Read file and close the file."""
    with open(filename, 'r') as f:
        return f.read()


def fwrite(filename, text):
    """Write content to file and close the file."""
    basedir = os.path.dirname(filename)
    if not os.path.isdir(basedir):
        os.makedirs(basedir)

    with open(filename, 'w') as f:
        f.write(text)


def err(msg, *args):
    """Log message with specified arguments."""
    sys.stderr.write("ERROR: " + msg.format(*args) + '\n')


def log(msg, *args):
    """Log message with specified arguments."""
    print(msg.format(*args))


def truncate(text, words=25):
    """Remove tags and truncate text to the specified number of words."""
    return ' '.join(re.sub('(?s)<.*?>', ' ', text).split()[:words])


def read_headers(text):
    """Parse headers in text and yield (key, value, end-index) tuples."""
    for match in re.finditer(r'\s*<!--\s*(.+?)\s*:\s*(.+?)\s*-->\s*|.+', text):
        if not match.group(1):
            break
        yield match.group(1), match.group(2), match.end()


def rfc_2822_format(date_str):
    """Convert yyyy-mm-dd date string to RFC 2822 format date string."""
    d = datetime.datetime.strptime(date_str, '%Y-%m-%d')
    return d.strftime('%a, %d %b %Y %H:%M:%S +0000')


def read_content(filename):
    """Read content and metadata from file into a dictionary."""
    # only process HTML and Markdown files
    if not filename.endswith(('.html', '.md')) or os.path.isdir(filename):
        return None

    # Read file content.
    text = fread(filename)

    # Read metadata and save it in a dictionary.
    date_slug = os.path.basename(filename).split('.')[0]
    match = re.search(r'^(?:(\d\d\d\d-\d\d-\d\d)-)?(.+)$', date_slug)
    yy_mm_dd = match.group(1) or '1970-01-01'
    content = {
        'date': yy_mm_dd,
        'subdir': f'{yy_mm_dd[:7]}',
        'slug': match.group(2)
    }

    # Read headers.
    end = 0
    for key, val, end in read_headers(text):
        content[key] = val

    # Separate content from headers.
    text = text[end:]

    # Convert Markdown content to HTML.
    if filename.endswith(('.md')):
        try:
            if _test == 'ImportError':
                raise ImportError('Error forced by test')
            import commonmark
            text = commonmark.commonmark(text)
        except ImportError as e:
            err('WARNING: Cannot render Markdown in {}: {}', filename, str(e))

    # Update the dictionary with content and RFC 2822 date.
    content.update({
        'content': text,
        'rfc_2822_date': rfc_2822_format(content['date'])
    })

    return content


def render(template, **params):
    """Replace placeholders in template with values from params."""
    return re.sub(r'{{\s*([^}\s]+)\s*}}',
                  lambda match:
                  str(params.get(match.group(1), match.group(0))), template)


def make_pages(src, dst, layout, **params):
    """Generate pages from page content."""
    items = []

    for src_path in glob.glob(src, recursive=True):
        content = read_content(src_path)
        if not content:
            continue

        page_params = dict(params, **content)

        # Populate placeholders in content if content-rendering is enabled.
        if page_params.get('render') == 'yes':
            rendered_content = render(page_params['content'], **page_params)
            page_params['content'] = rendered_content
            content['content'] = rendered_content

        items.append(content)

        dst_path = render(dst, **page_params)
        page_params['tags_html'] = process_tags(src_path, dst_path,
                                                **page_params)
        output = render(layout, **page_params)

        log('Rendering {} => {} ...', src_path, dst_path)
        fwrite(dst_path, output)

    return sorted(items, key=lambda x: x['date'], reverse=True)


def process_tags(src_path, dst_path, **params):
    dpp = Path(dst_path).parts
    if len(dpp) < 4 or 'tags' not in params:
        return ""
    tags_html = '<p>Tags:'
    for t in params.get('tags').split(' '):
        if t not in params['alltags']:
            params['alltags'][t] = {}
        tagfile_web = f"/{dpp[1]}/tag_{t}.html"
        tagfile_local = f"{dpp[0]}/{tagfile_web}"
        params['alltags'][t]['url'] = tagfile_local
        tags_html += f'&nbsp;&nbsp;<a href="{tagfile_web}">{t}</a>'
        params['alltags'][t][dst_path] = params['title']
    tags_html += '</p>'
    return tags_html


def make_list(posts, dst, list_layout, item_layout, **params):
    """Generate list page for a blog."""
    items = []
    subdir = ""
    for post in posts:
        item_params = dict(params, **post)
        if re.search(r"allposts.html", dst):
            if item_params['subdir'] != subdir:
                subdir = item_params['subdir']
                date = datetime.datetime.strptime(subdir, '%Y-%m')
                formatted_date = date.strftime('%B %Y')
                subdir_html = f"<h3>{formatted_date}</h3><br>"
            else:
                subdir_html = ""
            item = subdir_html + render(item_layout, **item_params)
        else:
            item_params['summary'] = truncate(post['content'])
            item = render(item_layout, **item_params)
        items.append(item)

    params['content'] = ''.join(items)
    dst_path = render(dst, **params)
    output = render(list_layout, **params)

    log('Rendering list => {} ...', dst_path)
    fwrite(dst_path, output)


def make_list_by_tag(posts, dst, list_layout, item_layout, **params):
    """Generate list page for a single tag."""
    for tag in params['alltags']:
        posts_by_tag = []
        dst_by_tag = f"{dst}/tag_{tag}.html"
        for post in posts:
            if post.get('tags') and tag in post.get('tags').split(' '):
                posts_by_tag.append(post)
        make_list(posts_by_tag, dst_by_tag, list_layout, item_layout,
                  title=f"Posts tagged as '{tag}'", **params)


def make_list_alltags(blogdir, dst, layout, **params):
    """Generate list page for all tags."""
    d = params['alltags']
    html = "<!-- title: All tags -->\n<h1>All tags</h1>\n<p>\n  <ul>\n"
    for tag in d:
        n = len(d[tag]) - 1
        nstr = f"{n} posts" if n > 1 else "1 post"
        tagurl = f"/{blogdir}/tag_{tag}.html"
        html += f'    <li><a href="{tagurl}">{tag}</a> : {nstr}\n'
    html += "  </ul>\n</p>"
    fwrite(dst, html)
    make_pages(f"_site/{blogdir}/alltags.html",
               f"_site/{blogdir}/alltags.html", layout, **params)
    return


def main(argv):
    rootdir = argv[1] if len(argv) == 2 else "."
    try:
        os.chdir(rootdir)
        if (
                not os.path.isdir('content') or not os.path.isdir('layout') or
                not os.path.isdir('static') or not os.path.isdir('_site')
                ):
            err(f"Root directory '{rootdir}' not a makesite layout")
            sys.exit(1)
    except FileNotFoundError:
        err(f"Root directory '{rootdir}' does not exist")
        sys.exit(1)

    # Create a new _site directory from scratch
    if os.path.isdir('_site'):
        shutil.rmtree('_site')
    shutil.copytree('static', '_site')

    # Default parameters
    params = {
        'base_path': '',
        'subtitle': 'Lorem Ipsum',
        'author': 'Admin',
        'site_url': 'http://localhost:8000',
        'blogs': {
            1: {'name': 'Blog', 'dir': 'blog'},
            2: {'name': 'News', 'dir': 'news'}
        },
        'current_year': datetime.datetime.now().year
    }

    # If params.json exists, load it
    if os.path.isfile('params.json'):
        params.update(json.loads(fread('params.json')))

    # Load layouts
    page_layout = fread('layout/page.html')
    post_layout = fread('layout/post.html')
    list_layout = fread('layout/list.html')
    item_layout = fread('layout/item.html')
    allposts_layout = fread('layout/allposts.html')
    feed_xml = fread('layout/feed.xml')
    item_xml = fread('layout/item.xml')

    # Combine layouts to form final layouts
    post_layout = render(page_layout, content=post_layout)
    list_layout = render(page_layout, content=list_layout)

    # Create site pages
    make_pages('content/_index.html', '_site/index.html',
               page_layout, **params)
    make_pages('content/[!_]*.html', '_site/{{ slug }}/index.html',
               page_layout, **params)

    # loop through each blog defined in params
    for key, blog in params['blogs'].items():

        params['alltags'] = {}

        # Check if source content directory exists
        if not os.path.isdir(f"content/{blog['dir']}"):
            err(f"WARNING: directory does not exist: content/", blog['dir'])

        # Create blog
        blog_posts = make_pages(f"content/{blog['dir']}/**/*",
                                f"_site/{blog['dir']}/"
                                + "{{ subdir }}/{{ slug }}/index.html",
                                post_layout, blog=blog['dir'], **params)

        # Create blog list page
        make_list(blog_posts, f"_site/{blog['dir']}/index.html",
                  list_layout, item_layout,
                  blog=blog['dir'], title=blog['name'], **params)

        make_list(blog_posts, f"_site/{blog['dir']}/allposts.html",
                  list_layout, allposts_layout,
                  blog=blog['dir'], title="All Posts", **params)

        # Create blog list page for each tag
        make_list_by_tag(blog_posts, f"_site/{blog['dir']}/",
                         list_layout, item_layout,
                         blog=blog['dir'], **params)

        # Create page with consolidated list of all tags
        make_list_alltags(blog['dir'], f"_site/{blog['dir']}/alltags.html",
                          page_layout, **params)

        # Create RSS feed
        make_list(blog_posts, f"_site/{blog['dir']}/rss.xml",
                  feed_xml, item_xml,
                  blog=blog['dir'], title=blog['name'], **params)


# Test parameter to be set temporarily by unit tests
_test = None


if __name__ == '__main__':
    main(sys.argv)
