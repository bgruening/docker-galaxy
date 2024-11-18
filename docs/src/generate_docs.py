import os

import pycmarkgfm
from bs4 import BeautifulSoup


def extract_html_structure(html_content):
    html_structure = {}
    section_order = []
    section_id = "header"
    section_name = "Header"
    section_content = BeautifulSoup("", "html.parser")
    soup = BeautifulSoup(html_content, "html.parser")

    for section in [tag for tag in soup.children if isinstance(tag, str) is False]:
        if section.name == "h1":
            if section_id:
                html_structure[section_id] = {
                    "name": section_name,
                    "content": section_content,
                }
                section_order.append(section_id)

            if "Galaxy Docker Image" in section.text:
                section_id = "index"
                section_name = "Global description"
            else:
                anchor = section.find("a", {"name": True})
                section_id = (
                    anchor["name"].replace("user-content-", "").lower()
                    if anchor
                    else None
                )
                section_name = (
                    section.get_text(strip=True).replace("[toc]", "")
                    if anchor
                    else None
                )

            section_content = BeautifulSoup(f"<h1>{section_name}</h1>\n", "html.parser")
        else:
            if section.name == "a" and section.get("href") == "#toc":
                continue
            section_content.append(section)

    if section_id:
        html_structure[section_id] = {
            "name": section_name,
            "content": section_content,
        }
        section_order.append(section_id)

    header = BeautifulSoup(features="html.parser")
    header.append(header.new_tag("p", **{"class": "bold"}, string="Table of content"))
    ul_tag = header.new_tag("ul")
    header.append(ul_tag)
    for section in section_order:
        if section == "header" or "toc" in section:
            continue
        li_tag = header.new_tag("li")
        a_tag = header.new_tag("a", href=f"{section}.html")
        a_tag.string = html_structure[section]["name"]
        li_tag.append(a_tag)
        ul_tag.append(li_tag)

    for section in html_structure:
        if section == "header" or "toc" in section:
            continue
        output_filepath = os.path.join("docs", f"{section}.html")
        page_content = html_structure[section]["content"]
        soup = BeautifulSoup("<html></html>", "html.parser")
        html = soup.html

        head = soup.new_tag("head")
        html.append(head)

        meta_charset = soup.new_tag("meta", charset="utf-8")
        head.append(meta_charset)
        meta_compat = soup.new_tag(
            "meta", **{"http-equiv": "X-UA-Compatible", "content": "chrome=1"}
        )
        head.append(meta_compat)
        title = soup.new_tag("title")
        title.string = "Galaxy Docker Image by bgruening"
        head.append(title)
        link = soup.new_tag("link", rel="stylesheet", href="css/landing_page.css")
        head.append(link)

        body = soup.new_tag("body")
        html.append(body)

        wrapper = soup.new_tag("div", **{"class": "wrapper"})
        body.append(wrapper)

        header_tag = soup.new_tag("header")
        wrapper.append(header_tag)

        h1 = soup.new_tag("h1")
        h1.string = "Galaxy Docker Image"
        header_tag.append(h1)
        p = soup.new_tag("p")
        p.string = "Docker Images tracking the stable Galaxy releases"
        header_tag.append(p)
        header_tag.append(BeautifulSoup(str(header), "html.parser"))
        p_view = soup.new_tag("p", **{"class": "view"})
        a_view = soup.new_tag("a", href="https://github.com/bgruening/docker-galaxy")
        a_view.string = "View the Project on GitHub "
        small_view = soup.new_tag("small")
        small_view.string = "bgruening/docker-galaxy"
        a_view.append(small_view)
        p_view.append(a_view)
        header_tag.append(p_view)

        ul_box = soup.new_tag("ul", **{"class": "box"})
        li_zip = soup.new_tag("li", **{"class": "box"})
        a_zip = soup.new_tag(
            "a", href="https://github.com/bgruening/docker-galaxy/zipball/master"
        )
        a_zip.string = "Download "
        strong_zip = soup.new_tag("strong")
        strong_zip.string = "ZIP File"
        a_zip.append(strong_zip)
        li_zip.append(a_zip)
        ul_box.append(li_zip)

        li_tar = soup.new_tag("li", **{"class": "box"})
        a_tar = soup.new_tag(
            "a", href="https://github.com/bgruening/docker-galaxy/tarball/master"
        )
        a_tar.string = "Download "
        strong_tar = soup.new_tag("strong")
        strong_tar.string = "TAR Ball"
        a_tar.append(strong_tar)
        li_tar.append(a_tar)
        ul_box.append(li_tar)

        li_github = soup.new_tag("li", **{"class": "box"})
        a_github = soup.new_tag("a", href="https://github.com/bgruening/docker-galaxy")
        a_github.string = "View On "
        strong_github = soup.new_tag("strong")
        strong_github.string = "GitHub"
        a_github.append(strong_github)
        li_github.append(a_github)
        ul_box.append(li_github)

        header_tag.append(ul_box)

        section = soup.new_tag("section")
        section.append(page_content)
        wrapper.append(section)

        footer = soup.new_tag("footer")
        p1 = soup.new_tag("p")
        p1.append(
            BeautifulSoup(
                'This project is maintained by <a href="https://github.com/bgruening">bgruening</a>',
                "html.parser",
            )
        )
        footer.append(p1)
        p2 = soup.new_tag("p")
        p2.append(
            BeautifulSoup(
                '<small>Hosted on GitHub Pages &mdash; Theme by <a href="https://github.com/orderedlist">orderedlist</a></small>',
                "html.parser",
            )
        )
        footer.append(p2)
        wrapper.append(footer)

        script = soup.new_tag("script", src="js/landing_page.js")
        wrapper.append(script)

        with open(output_filepath, "w") as output_file:
            output_file.write(soup.prettify())


if __name__ == "__main__":
    with open("README.md", "r") as f:
        doc = f.read()
    html_content = pycmarkgfm.gfm_to_html(doc, options=pycmarkgfm.options.unsafe)
    extract_html_structure(html_content)
