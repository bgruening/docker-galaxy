#!/usr/bin/env python

"""
galaxy-dir-sync.py synchronises the content of a network directory (accessible by Galaxy) to a specific folder
of a Galaxy's Library.
The directory sub-structure is also replicated in the Galaxy Library's folder and all
files found in the synchronized directory are added in the Galaxy's Library using symbolic links.
Conversely, the script checks if all datasets available in the Library's folder are found in the network directory and
datasets with broken links are removed from the Galaxy library.
In addition, a unique .galaxy_ignore file can be placed in the synchronized directory (at the root) to list files
to be ignored by the synch'ing process. The file expects one pattern per line, each pattern will be matched against
the entire file or directory name. The wildcard char is * and measn 'anyting', all other characters are used as such
i.e. a '.' manes a dot not 'any letter'
By default, all files starting with a '.' are ignored (no matter if .galaxy_ignore file exists or contains a '.*').
To do this you will need your Galaxy API key, found by logging into Galaxy and
selecting the menu option User -> API Keys.
"""

import argparse
import datetime
import logging
import os
import pathlib
import re
import time
from sys import exit

import bioblend
import yaml
from bioblend import galaxy

logging.basicConfig()
logger = logging.getLogger(__name__)

# galaxy clips off the compression file extension e.g. .gz ; we also need to define the exact
# list of extensions that are removed by Galaxy when matching up dataset names
COMPRESSION_EXT_LIST = ['gz', 'zip', 'bz2']

# name of the file listing files / folders to ignore
GALAXY_IGNORE_FILE_NAME = ".galaxy_ignore"
GALAXY_INCLUDE_FILE_NAME = ".galaxy_include"


def check_galaxy_folder(gi, library_id, root_folder_galaxyname, root_folder_galaxyid, subdir, create_if_missing,
                        foldername2id, dry_run):
    """
    Checks if a folder exists else create it
    """
    fname_in_galaxy = root_folder_galaxyname + "/" + subdir

    if fname_in_galaxy not in foldername2id:
        _folders = gi.libraries.get_folders(library_id, name=fname_in_galaxy)
        logger.debug("Check if folder '%s' ('%s') exists in Galaxy.", subdir, fname_in_galaxy)
        if create_if_missing is True and len(_folders) == 0 and not dry_run:
            # to create the folder, we need to get the id of its parent folder
            _folder = gi.libraries.create_folder(
                library_id=library_id, folder_name=subdir, base_folder_id=root_folder_galaxyid)[0]
            foldername2id[fname_in_galaxy] = _folder['id']
            logger.debug(_folder)
            logger.info("Created Galaxy folder: '%s' ('%s', '%s')",
                        _folder['name'], _folder['id'], fname_in_galaxy)
        elif len(_folders) > 0:
            logger.debug("Galaxy folder exists.")
        else:
            logger.warning("Galaxy folder does NOT exists, but folder creation is disabled.")
    else:
        logger.debug("Galaxy folder '%s' ALREADY found is internal folder mapping.", fname_in_galaxy)


def found_in_dict(name, name2id_map, compression_tolerant=True):
    """
    checks if name is found as a key in name2id_map
    if compression_tolerant is True, also return True if any of
    name.<ext> (with <ext> is from COMPRESSION_EXT_LIST) is found as a key
    """
    if name in name2id_map:
        return True
    if compression_tolerant:
        for ext in COMPRESSION_EXT_LIST:
            if name.endswith(ext):
                _name = os.path.splitext(name)[0]  # remove one extension
                if _name in name2id_map:
                    return True
    return False


def should_ignore_file(path, filepattern_to_ignore, include_folders, root=""):
    p = root / pathlib.Path(path)
    name = p.name
    logger.debug("Check if file is to be ignored: '%s' from path '%s'", name, path)

    if include_folders:
        ignore = True
        for folder in include_folders:
            logger.debug("Check if %s is relative to %s, ignore otherwise", path, folder)
            if p.is_relative_to(folder):
                ignore = False
                logger.debug("%s is relative to %s", path, folder)
                break
        if ignore:
            logger.debug("Ignoring %s", path)
            return True

    for pat in filepattern_to_ignore:
        if re.match(pat, name):
            logger.debug("Ignoring: '%s' matches forbidden pattern '%s'.", path, pat.pattern)
            return True

    return False


def synchronize(gi, library, folder, root_dir, foldername2id, filename2id, filepattern_to_ignore, include_folders,
                dry_run):
    """
    :param gi: the galaxy instance to talk to the API
    :param library: the galaxy library to use, as a dict
    :param folder: the galaxy folder
    :param root_dir: absolute path to the dir to sync with galaxy
    :param foldername2id: a dict of existing folder name and their associated id
    :param filename2id: a dict of existing file name and their associated id
    :param filepattern_to_ignore: list of patterns to ignore
    :param include_folders: list of folders to explicitly consider - ignore others
    :param dry_run: boolean
    :return:
    """
    # list the content of the galaxy library's folder
    for cur_root, subdirs, files in os.walk(root_dir):
        # should we ignore this folder overall ?
        # cur_root is a path, get the last name
        if not root_dir == cur_root and should_ignore_file(cur_root, filepattern_to_ignore, include_folders):
            continue

        # this should always already exists in galaxy at this point
        root_folder_galaxyname = cur_root.replace(root_dir, folder['name'])
        # if root_dir was /path/to/root/
        # and cur_root is now  /path/to/root/fastq/blah
        # then root_folder_galaxyname should be  '/<foldername>'+/fastq/blah' so the replace directly matches the galaxy folder name
        # Lets now get its ID, to create new sub-folders if needed

        # let check we have a starting '/'
        if not root_folder_galaxyname.startswith('/'):
            root_folder_galaxyname = '/' + root_folder_galaxyname

        root_folder_galaxyid = None
        if root_folder_galaxyname not in foldername2id:
            logger.debug("Internal folder name mapping does not contain key '%s' although it should at this point.",
                         root_folder_galaxyname)
            res = gi.libraries.get_folders(library['id'], name=root_folder_galaxyname)
            if len(res) > 0:
                root_folder_galaxyid = res[0]['id']
            elif not dry_run:
                logger.error("Galaxy folder '%s' not found in library '%s' ('%s') while it should exist at this point.",
                             root_folder_galaxyname, library['name'], library['id'])
                exit(1)
        else:
            root_folder_galaxyid = foldername2id[root_folder_galaxyname]

        logger.info("Current root is '%s' => Galaxy folder name is '%s'.", cur_root, root_folder_galaxyname)
        # for each sub dir, check if a folder exists in the library, else create it
        for subdir in subdirs:
            # subdir is just a dir name ie not a path
            if subdir.startswith(".") or should_ignore_file(subdir, filepattern_to_ignore, include_folders,
                                                            root=cur_root):
                subdirs.remove(subdir)
                continue
            check_galaxy_folder(gi, library['id'], root_folder_galaxyname, root_folder_galaxyid, subdir, True,
                                foldername2id, dry_run)

            # for each file, sym link it if not present
        file_paths = []
        for filename in files:
            if filename.startswith(".") or should_ignore_file(filename, filepattern_to_ignore, include_folders,
                                                              root=cur_root):
                logger.debug("Ignoring file '%s'.", filename)
                continue

            file_path = os.path.join(cur_root, filename)  # absolute path on disk
            galaxy_filename = root_folder_galaxyname + '/' + filename
            logger.debug("Galaxy filename: '%s'", galaxy_filename)
            galaxy_filename = galaxy_filename.replace('//', '/')
            logger.debug("Should file '%s' be added? Checking '%s'...", filename, galaxy_filename)
            if found_in_dict(galaxy_filename, filename2id, True):
                logger.debug("File already internally mapped.")
                continue
            logger.debug("=> YES")
            file_paths.append(file_path)

        if len(file_paths) > 0:
            logger.debug("Linking '%i' files:\n - %s", len(file_paths), '\n - '.join(file_paths))
            linked_files = []
            if not dry_run:
                # we will upload files one by one, slower, but if one fails the others are not affected. i.e.
                # galaxy will put them all in the same error state :(
                for _file_path in file_paths:
                    linked_files.extend(gi.libraries.upload_from_galaxy_filesystem(
                        library['id'],
                        filesystem_paths=_file_path,
                        link_data_only='link_to_files',
                        folder_id=root_folder_galaxyid,
                        file_type='auto'
                    ))

            for _f in linked_files:
                filename2id[_f['name']] = _f['id']
                logger.info("New file uploaded '%s' with id '%s'", _f['name'], _f['id'])


def clean_galaxy_folder(gi, library, folder, root_dir, dry_run):
    logger.info("Cleaning galaxy folder, with root_dir '%s'...", root_dir)
    # List library content and remove galaxy content that is not found on disk
    for _content in gi.libraries.show_library(library['id'], True):
        if not _content['name'].startswith(folder['name']):
            continue

            # does this exist on disk ?
        _name = _content['name'].replace(folder['name'], '', 1)
        if _name.startswith('/'):  # as it should
            _name = _name.replace('/', '', 1)  # replace first only

        path_to_check = os.path.join(root_dir, _name)
        if _content['type'] == 'folder' and not os.path.exists(path_to_check):
            logger.info("Folder '%s' is NOT found on disk. Deleting...", path_to_check)
            if not dry_run:
                obj = gi.folders.delete_folder(_content['id'])
                logger.debug(obj)
        elif not os.path.exists(path_to_check):
            trash = True
            # TODO: we need to be compression tolerant before deleting  ???
            for ext in COMPRESSION_EXT_LIST:
                if not ext.startswith("."):
                    ext = '.' + ext
                if os.path.exists(path_to_check + ext):
                    trash = False
                    logger.debug("File '%s' is found on disk with extension '%s'", path_to_check, ext)
                    break
            if trash:
                logger.info("File '%s' is NOT found on disk (nor with any of '%s' extensions). Deleting...",
                            path_to_check, ', '.join(COMPRESSION_EXT_LIST))
                if not dry_run:
                    obj = gi.libraries.delete_library_dataset(library['id'], _content['id'])
                    logger.debug(obj)
        else:
            logger.debug("Path '%s' is found on disk", path_to_check)


def main():
    root_dir = os.path.abspath(args.dir)
    # connect to Galaxy
    gi = galaxy.GalaxyInstance(url=args.url, key=args.apikey)

    # Get the Library
    _libraries = gi.libraries.get_libraries(name=args.library)
    if len(_libraries) == 0:
        msg = "Galaxy Library '%s' does not exist (or you don't have permissions on it)" % args.library
        raise argparse.ArgumentTypeError(msg)
    gal_lib = _libraries[0]

    # Get the library's folder ; folder names starts with a /
    _folders = gi.libraries.get_folders(gal_lib['id'], name="/" + args.folder)
    if len(_folders) == 0:
        _folders = gi.libraries.create_folder(library_id=gal_lib['id'], folder_name=args.folder, base_folder_id=None)
    folder = _folders[0]

    dry_run = False
    if args.dryrun:
        dry_run = args.dryrun

    # Run loop
    while True:
        # check if a .galaxy_ignore file exists. do this on every loop to check for updates
        filepatterns_to_ignore = get_filepatterns_to_ignore(root_dir)
        # also check if there is a .galaxy_include file that list sub folders to sync - others are ignored
        include_folders = get_include_folders(root_dir)
        if include_folders:
            logger.info("Only the folders: '%s' will be considered.", ", ".join(map(str, include_folders)))

        # clean up: loop over the current Galaxy folder content and checks files/folders exist on network
        if args.clean:
            clean_galaxy_folder(gi, gal_lib, folder, root_dir, dry_run)

        # List library content and extract file and folder dict
        filename2id = dict()
        foldername2id = dict()
        logger.debug("Fetching existing entries in library '%s' ('%s')", args.library, gal_lib['id'])
        for _content in gi.libraries.show_library(gal_lib['id'], True):
            if not _content['name'].startswith(folder['name']):
                continue
            _name = _content['name']
            # this is content of the root folder, extract all file and folders in separate dict
            if _content['type'] == 'folder':
                logger.debug("Folder name mapping: '%s' -> '%s'", _name, _content['id'])
                foldername2id[_name] = _content['id']
            else:
                logger.debug("File name mapping: '%s' -> '%s'", _name, _content['id'])
                filename2id[_name] = _content['id']

        # add content
        try:
            synchronize(gi, gal_lib, folder, root_dir, foldername2id, filename2id, filepatterns_to_ignore,
                        include_folders, dry_run)
        except bioblend.ConnectionError as e:
            # try again if in daemon mode or at least just log the error
            logger.exception(e)
            pass

        # loop or end
        if args.daemon is not None and args.daemon is True:
            logger.info("'%s' - Now sleeping for %i seconds before next loop.", datetime.datetime.now(), args.stime)
            time.sleep(args.stime)
        else:
            break


def get_include_folders(root_dir):
    folders = []
    if os.path.exists(os.path.join(root_dir, GALAXY_INCLUDE_FILE_NAME)):
        with open(os.path.join(root_dir, GALAXY_INCLUDE_FILE_NAME)) as fh:
            for item in fh:
                item = item.strip()
                p = pathlib.Path(item)
                if p.is_absolute():
                    logger.critical("Folders set in %s need to be relative to the root dir. Exiting.", GALAXY_INCLUDE_FILE_NAME)
                    exit(1)
                folders.append(root_dir / p)
    return folders


def get_filepatterns_to_ignore(root_dir):
    patterns = []
    if os.path.exists(os.path.join(root_dir, GALAXY_IGNORE_FILE_NAME)):
        with open(os.path.join(root_dir, GALAXY_IGNORE_FILE_NAME)) as fh:
            for item in fh:
                item = item.strip()
                if not item:
                    continue
                p = "^" + re.escape(item).replace("\\*", ".*") + "$"  # the pattern should match the whole name
                logger.info("Files matching pattern '%s' will be ignored.", p)
                patterns.append(re.compile(p))
    return patterns


# Parse args and launch main()
if __name__ == '__main__':

    parser = argparse.ArgumentParser(description="Synchronizes network directory with a Galaxy Library's folder.")
    parser.add_argument("-u", "--url", required=False,
                        help="URL of the Galaxy to connect. Can be ommitted if a `~/.parsec.yml` is present.")
    parser.add_argument("-k", "--apikey", required=False,
                        help="Galaxy API key for the account to read. Can be ommitted if a `~/.parsec.yml` is present.")
    parser.add_argument("-l", "--library", required=True,
                        help="Name of the Galaxy Library. It should be already existing and you should have write "
                             "permissions on it.")
    parser.add_argument("-f", "--folder", required=True,
                        help="Name of the folder to be used in the specified Galaxy Library. Will be created if not "
                             "existing.")
    parser.add_argument("-d", "--dir", required=True,
                        help="Path to the network directory to be synch'ed in Galaxy (with symbolic links). "
                             "This must be accessible from the galaxy server file system.")
    parser.add_argument("-c", "--clean", required=False, action='store_true',
                        help="Checks that datasets found under the provided galaxy folder are still valid "
                             "(i.e. map to an actual file) and delete datasets with broken links.")
    parser.add_argument("--daemon", action='store_true',
                        help="Starts in daemon mode, see --stime")
    parser.add_argument("-s", "--stime", type=int,
                        help="Time to sleep between two loops, in seconds. Default is 300 i.e. 5 minutes.", default=300)
    parser.add_argument("-v", "--verbose", choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
                        help="The verbose level", default='DEBUG')
    parser.add_argument("--dryrun", action='store_true',
                        help="Perform dry run i.e. do not delete, add or upload files in galaxy and only print what "
                             "would be done. Usually useful with --verbose DEBUG")

    args = parser.parse_args()
    logger.setLevel(getattr(logging, args.verbose))

    # attempt to read from ~/.parsec.yml if api key was not given
    CONFIG_FILE_PATH = "~/.parsec.yml"
    if not args.apikey or not args.url:
        try:
            with open(os.path.expanduser(CONFIG_FILE_PATH)) as f:
                conf = yaml.load(f)
        except:
            msg = "No config file (%s) found in your environment. You must provide the Galaxy URL and API key on the " \
                  "command line or install parsec first." % (CONFIG_FILE_PATH)
            raise argparse.ArgumentTypeError(msg)

        # do we have an entry for the given url
        default_conf_key = None
        for k in conf:
            if k == "__default":
                default_conf_key = conf[k]
            elif args.url and conf[k]['url'] == args.url:
                # this is the Key to use
                args.apikey = conf[k]['key']
                logger.debug("Configuration file %s used, got url: %s, key: %s", CONFIG_FILE_PATH, args.url,
                             args.apikey)

        if not args.url:
            # use defaults
            args.url = conf[default_conf_key]['url']
            args.apikey = conf[default_conf_key]['key']
            logger.debug("Will use default URL and API from config file: ( %s, %s)", args.url, args.apikey)

            # at this point we should have an API key, if not fail
        if not args.apikey:
            msg = "No Galaxy API key could be resolved for %s " % args.url
            raise argparse.ArgumentTypeError(msg)
    else:
        logger.debug("Will use user-provided arguments: got url: %s, key: %s", args.url, args.apikey)

    # Check the directory
    if not os.path.exists(args.dir):
        msg = "Directory %s does not exist" % args.dir
        raise argparse.ArgumentTypeError(msg)

    if args.dryrun:
        logger.info("DRY MODE: no actual folder and file creation will occur in galaxy")
    else:
        logger.warning("REAL! MODE: folder and file creation will occur in galaxy")

    main()

    logger.info("Done. End of script.\n")
