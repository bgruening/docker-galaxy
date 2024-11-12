#!/usr/bin/env python3

import argparse
import io
import pathlib
import re
import shutil
from typing import Reversible, TextIO, List, Set, Mapping
import urllib3
import zipfile

import yaml

def tool_key(tool: dict, revision: str = None) -> str:
    if revision is None:
        key = '-'.join([tool['name'], tool['owner'], tool['tool_shed_url']])
    else:
        key = '-'.join([tool['name'], tool['owner'], tool['tool_shed_url'], revision])
    return key

def load_extra_tools(tools_file: TextIO, known_tools: Set[str], tools: Mapping[str, dict]):
    """load_extra_tools:
        tools_file - Open file referring to a Galaxy tools.yaml format file with tools to add
        known_tools - set of known tools - is modified in place
        tools - list of tools - is modified in place
    """
    data = yaml.load(tools_file, Loader=yaml.CLoader)
    for tool in data['tools']:
        for revision in tool['revisions']:
            known_tools.add(tool_key(tool, revision))
        tools[tool_key(tool)] = tool

def fetch_and_store_workflow(url: str, http: urllib3.PoolManager,
                             workflow_dir: str, known_tools: Set[str], tools: Mapping[str, dict]):
    version_re = re.compile(r'.*(\d+\.\d+\.\d+).jar')
    version_match = version_re.match(url)
    if version_match is not None:
        version_number = version_match.group(1)
    else:
        version_number = 'UNKNOWN'

    response = http.request('GET', url)
    if response.status == 200:
        workflow_filename = url.split('/')[-1]
        print('fetching', workflow_filename)
        open(workflow_dir + '/' + workflow_filename, 'wb').write(response.data)
        content = zipfile.ZipFile(io.BytesIO(response.data))
        for path_string in content.namelist():
            if ('/' + version_number + '/tools.yaml') in path_string:
                with content.open(path_string) as yaml_file:
                    data = yaml.load(yaml_file, Loader=yaml.CLoader)
                    for tool in data['tools']:
                        revisions_to_keep = []
                        for revision in tool['revisions']:
                            key = tool_key(tool, revision)
                            if key not in known_tools:
                                revisions_to_keep.append(revision)
                                known_tools.add(key)
                        if len(revisions_to_keep) > 0:
                            tool['revisions'] = revisions_to_keep
                            this_tool_key = tool_key(tool)
                            if this_tool_key in tools:
                                tools[this_tool_key]['revisions'].extend(revisions_to_keep)
                            else:
                                tools[this_tool_key] = tool
                            

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Set up environment for IRIDA and Galaxy deployment')
    parser.add_argument('--remove_old_workflows', action='store_true', default=False,
                        help='Delete old workflows from the workflow dir')
    parser.add_argument('--extra_tools_file', type=argparse.FileType(),
                        help='A Galaxy tools.yaml format file with tools to add in addition to the ones listed in the workflow jar files')
    parser.add_argument('--workflow_dir', default='docker-svc/irida/workflows', help='Location to store downloaded workflow jar files')
    parser.add_argument('--galaxy_tools_path', default='docker-svc/galaxy/galaxy-tools.yml',
                        help='File to store list of tools to install on Galaxy server')
    parser.add_argument('workflow_file', type=argparse.FileType(),
                        help='File listing workflow URLs, one per line')
    args = parser.parse_args()


    workflow_output_path = pathlib.Path(args.workflow_dir)
    if workflow_output_path.exists():
        if not workflow_output_path.is_dir():
            exit(f"Workflow output path ({workflow_output_path}) exists but it is not a directory")
        elif args.remove_old_workflows:
            shutil.rmtree(args.workflow_dir)
            workflow_output_path.mkdir()
    elif not workflow_output_path.exists():
        workflow_output_path.mkdir()

    known_tools = set()
    tools = {}
    if args.extra_tools_file is not None:
        load_extra_tools(args.extra_tools_file, known_tools, tools)

    workflow_urls = []
    for line in args.workflow_file:
        line = line.strip()
        if line != '' and not line.startswith('#'):
            workflow_urls.append(line.strip())

    http = urllib3.PoolManager()
    for url in workflow_urls:
        fetch_and_store_workflow(url, http, args.workflow_dir, known_tools, tools)

    header = {'install_tool_dependencies': True, 'install_repository_dependencies': True, 'install_resolver_dependencies': False}

    tool_config = header
    tool_list = []
    for key in tools:
        tool_list.append(tools[key])
    tool_config['tools'] = tool_list
    yaml.dump(tool_config, open(args.galaxy_tools_path, 'w'), Dumper=yaml.CDumper)
