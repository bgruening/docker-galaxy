Documentation
=============

The documentation is automatically generated when the main [`README.md`](../README.md) is changed on the `main` branch.

For information, this automatic generation uses a [Python script](src/generate_docs.py) to transform the markdown in the `README.md` into the HTML files.
This generation is automatically launched by a [GitHub Action Workflow](https://github.com/bgruening/docker-galaxy/actions/workflows/update-site.yml).

So, if you see any error in the [online documentation](http://bgruening.github.io/docker-galaxy), you can first check the `README.md`. If the error does not come from the `README.md`, you can either file an issue or check the [Python](src/generate_docs.py) script used to generate the HTML files.
