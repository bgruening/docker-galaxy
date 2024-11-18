#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import argparse

def generate_html_backbone(output_filepath, header, page_content):
    string = '<!doctype html>\n'
    string += '<html>\n'
    string += '  <head>\n'
    string += '    <meta charset=\"utf-8\">\n'
    string += '    <meta http-equiv=\"X-UA-Compatible\" content=\"chrome=1\">\n'
    string += '    <title>Galaxy Docker Image by bgruening</title>\n'
    string += '\n'
    string += '    <link rel=\"stylesheet\" href=\"css/landing_page.css\">\n'
    string += '    <meta name=\"viewport\" content=\"width=device-width\">\n'
    string += '    <!--[if lt IE 9]>\n'
    string += '    <script src=\"//html5shiv.googlecode.com/svn/trunk/html5.js\"></script>\n'
    string += '    <![endif]-->\n'
    string += '  </head>\n'
    string += '\n'
    string += '<body>\n'
    string += '  <div class=\"wrapper\">\n'
    string += '    <header>\n'
    string += '      <h1>Galaxy Docker Image</h1>\n'
    string += '      <p>Docker Images tracking the stable Galaxy releases</p>\n'
    string += '\n'
    string += '      ' + header + '\n'
    string += '\n'
    string += '      <p class=\"view\"><a href=\"https://github.com/bgruening/docker-galaxy-stable\">View the Project on GitHub <small>bgruening/docker-galaxy-stable</small></a></p>\n'
    string += '\n'
    string += '      <ul class=\"box\">\n'
    string += '        <li class=\"box\"><a href=\"https://github.com/bgruening/docker-galaxy-stable/zipball/master\">Download <strong>ZIP File</strong></a></li>\n'
    string += '        <li class=\"box\"><a href=\"https://github.com/bgruening/docker-galaxy-stable/tarball/master\">Download <strong>TAR Ball</strong></a></li>\n'
    string += '        <li class=\"box\"><a href=\"https://github.com/bgruening/docker-galaxy-stable\">View On <strong>GitHub</strong></a></li>\n'
    string += '      </ul>\n'
    string += '    </header>\n'
    string += '\n'
    string += '    <section>\n'
    string += '    ' + page_content + '\n'
    string += '\n'
    string += '    </section>\n'
    string += '\n'
    string += '    <footer>\n'
    string += '      <p>This project is maintained by <a href=\"https://github.com/bgruening\">bgruening</a></p>\n'
    string += '      <p><small>Hosted on GitHub Pages &mdash; Theme by <a href=\"https://github.com/orderedlist\">orderedlist</a></small></p>\n'
    string += '    </footer>\n'
    string += '    <script src=\"js/landing_page.js\"></script>\n'
    string += '  </div>\n'
    string += '</body>\n'
    string += '</html>\n'

    with open(output_filepath, "w") as output_file:
        output_file.write(string)

def extract_section_info(line):
    to_search = '<a name="user-content-'
    id_start = line.find(to_search) + len(to_search)
    id_stop = line.find('"> </a>')
    section_name = line[4:(id_start-len(to_search))]
    section_id = line[id_start:id_stop].lower()
    return section_id, section_name

def extract_html_structure(html_content_filepath):
    html_structure = {}
    section_id = "header"
    section_name = "Header"
    section_content = ""
    section_order = []
    section_subcontent = []
    with open(html_content_filepath, "r") as html_content:
        for line in html_content.readlines():
            if line.find("<h1>") != -1:
                html_structure[section_id] = {
                    "name": section_name,
                    "content": section_content,
                    "subcontent": section_subcontent
                }
                section_order.append(section_id)

                if line.find("<h1>Galaxy Docker Image</h1>") != -1:
                    section_id = "index"
                    section_name = "Global description"
                else:
                    section_id, section_name = extract_section_info(line)
                section_content = "<h1>" + section_name + "</h1>\n"

                if section_id == "index":
                    section_content += html_structure["header"]["content"]

                section_subcontent = []
            else:
                line = line.replace('<a href="#toc">[toc]</a>', "")
                line = line.replace('<span class="pl-cce">\\n</span>', "\\\n")
                section_content += line

                if line.find("<h2>") != -1:
                    subsection_id, subsection_name = extract_section_info(line)
                    section_subcontent.append({"name": subsection_name,
                        "id": subsection_id})

    return html_structure, section_order

def extract_header(html_structure, section_order):
    header = '  <p class="bold">Table of content</p>\n'
    header += "  <ul>\n"
    for section in section_order:
        if section == "header" or section.find("toc") != -1:
            continue
        header += '    <li><a href="' + section + '.html">'
        header += html_structure[section]["name"] + '</a>'

        #if len(html_structure[section]["subcontent"]) > 0:
        #    header += '\n    <ul>\n'
        #    for subsection in html_structure[section]["subcontent"]:
        #        header += '      <li><a href="' + section + '.html#' + subsection["id"] + '">'
        #        header += subsection["name"] + '</a></li>\n'

        header += '  </li>\n'
    header += "  </ul>\n"
    return header

def generate_html_files(html_structure, header, output_dir):
    for section in html_structure:
        if section == "header" or section.find("toc") != -1:
            continue
        generate_html_backbone(output_dir + "/" + section + ".html", header,
            html_structure[section]["content"])

def generate_html(args):
    html_structure, section_order = extract_html_structure(args.html_content)
    header = extract_header(html_structure, section_order)
    generate_html_files(html_structure, header, args.output_dir)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--html_content', required=True)
    parser.add_argument('--output_dir', required=True)
    args = parser.parse_args()

    generate_html(args)
