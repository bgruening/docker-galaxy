Documentation
=============

The documentation is automatically generated when the main [`README.md`](../README.md) is changed on the `master` branch.

For information, this automatic generation uses the GitHub API (in [`bin/gfm2html`](bin/gfm2html)) and a [Python script](src/generate_html.py) to transform the markdown in the [`README.md`](../README.md) into the HTML files.
This generation is automatically launched by Travis-CI with [`bin/deploy_docs`](bin/deploy_docs) script.

So, if you see any error in the [online documentation](http://bgruening.github.io/docker-galaxy-stable), you can first check the [`README.md`](../README.md). If the error does not come from the [`README.md`](../README.md), you can either file an issue or check the [Python](src/generate_html.py) or the [bash](bin/gfm2html) scripts used to generate the HTML files.
