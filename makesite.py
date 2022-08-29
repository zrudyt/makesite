#!/usr/bin/env python

# The MIT License (MIT)
#
# Copyright (c) 2022 zrudyt <starbase.area51@gmail.com>
# All rights reserved
#
# This software is a derivative of the original makesite.py.
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


def log(msg, *args):
    """Log message with specified arguments."""
    sys.stderr.write(msg.format(*args) + '\n')


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
        'subdir': f'{yy_mm_dd[:4]}/{yy_mm_dd[5:7]}',
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
            log('WARNING: Cannot render Markdown in {}: {}', filename, str(e))

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
        output = render(layout, **page_params)

        if 'tags' in content:
            p = Path(dst_path).parts
            add_to_alltags(p, **page_params)

        log('Rendering {} => {} ...', src_path, dst_path)
        fwrite(dst_path, output)

    return sorted(items, key=lambda x: x['date'], reverse=True)


def add_to_alltags(tagdir, **params):
    # t = re.sub(r"(\S+)", r'<a href="/tag_\1.html">\1</a> ', val)
    # content['tags_html'] = f'<p class="tags">Tags: {t}</p>'
    for t in params['tags'].split(' '):
        if len(tagdir) < 2:
            break
        tagfile = f"{tagdir[0]}/{tagdir[1]}/tag_{t}.html"
        if t not in params['alltags']:
            params['alltags'][t] = []
        l = [ tagfile, params['title'] ]
        params['alltags'][t].append(l)
    return


def make_list(posts, dst, list_layout, item_layout, **params):
    """Generate list page for a blog."""
    items = []
    for post in posts:
        item_params = dict(params, **post)
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
            if tag in post:
                posts_by_tag.append(post)
        make_list(posts_by_tag, dst_by_tag, list_layout, item_layout, **params)


def make_xrefs(alltags):
    for tag in alltags:
        outfile = f"content/tag_{tag}.md"
        s = ""
        for fileinfo in alltags[tag]:
            s += f"* [{fileinfo[1]}]({fileinfo[0]})\n"
        fwrite(outfile, s)
    return


def main():
    # Create a new _site directory from scratch.
    if os.path.isdir('_site'):
        shutil.rmtree('_site')
    shutil.copytree('static', '_site')

    # Default parameters.
    params = {
        'base_path': '',
        'subtitle': 'Lorem Ipsum',
        'author': 'Admin',
        'site_url': 'http://localhost:8000',
        'blogs': {
            1: {'name': 'Blog', 'dir': 'blog'},
            2: {'name': 'News', 'dir': 'news'}
        },
        'current_year': datetime.datetime.now().year,
        'alltags': {}
    }

    # If params.json exists, load it.
    if os.path.isfile('params.json'):
        params.update(json.loads(fread('params.json')))

    # Load layouts.
    page_layout = fread('layout/page.html')
    post_layout = fread('layout/post.html')
    list_layout = fread('layout/list.html')
    item_layout = fread('layout/item.html')
    feed_xml = fread('layout/feed.xml')
    item_xml = fread('layout/item.xml')

    # Combine layouts to form final layouts.
    post_layout = render(page_layout, content=post_layout)
    list_layout = render(page_layout, content=list_layout)

    # Create site pages.
    make_pages('content/_index.html', '_site/index.html',
               page_layout, **params)
    make_pages('content/[!_]*.html', '_site/{{ slug }}/index.html',
               page_layout, **params)

    # loop through each blog defined in params
    for key, blog in params['blogs'].items():

        # Check if source content directory exists
        if not os.path.isdir(f"content/{blog['dir']}"):
            log("WARNING: directory does not exist: content/{}", blog['dir'])

        # Create blog
        blog_posts = make_pages(f"content/{blog['dir']}/**/*",
                                f"_site/{blog['dir']}/"
                                + "{{ subdir }}/{{ slug }}/index.html",
                                post_layout, blog=blog['dir'], **params)

        # Create blog list page
        make_list(blog_posts, f"_site/{blog['dir']}/index.html",
                  list_layout, item_layout,
                  blog=blog['dir'], title=blog['name'], **params)

        # Create blog list page for each tag
        make_list_by_tag(blog_posts, f"_site/{blog['dir']}/",
                  list_layout, item_layout,
                  blog=blog['dir'], title=blog['name'], **params)

        # Create RSS feed
        make_list(blog_posts, f"_site/{blog['dir']}/rss.xml",
                  feed_xml, item_xml,
                  blog=blog['dir'], title=blog['name'], **params)

    # make_xrefs(params['alltags'])
    # make_pages('content/tag_*.md', '_site/{{ slug }}.html',
    #            page_layout, **params)

    print(params['alltags'])
# Test parameter to be set temporarily by unit tests.
_test = None


if __name__ == '__main__':
    main()
