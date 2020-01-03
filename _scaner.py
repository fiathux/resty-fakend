# project auto scaner
# IMPORTANT: this script required python 3.5 or upper
# Fiathux Su
# 2019-10-18

import sys
import time
import hashlib
import os
import re
import pathlib
from functools import reduce
from collections import namedtuple

# project file update file
_scan_files_record = ".SCAN_FILES.keep"

# global support{{{
# common error output {{{
def common_error(*args):
    # default error output
    def default_err():
        print("Error!")
        return True
    # custom error lines
    def multi_err(info):
        if not info:
            return False
        print(str(info[0]))
        if len(info) > 0:
            for s in info[1:]:
                print("    %s" % str(s))
        return True
    # custom error lines in an exception object
    def exception_err(info):
        if len(info) != 1 or isinstance(info[0], Exception):
            return multi_err(info[0].args)
        return False
    # dispatching
    exception_err(args) or multi_err(args) or default_err()
    sys.exit()
#}}}

# common warning output
def common_warn(s):
    print("WARNING: %s" % str(s))

class ConfigError(Exception):pass
class ScanError(Exception):pass
class ScanExistsError(ScanError):
    def __str__(me):
        return "file \"%s\" already exists" % me.args[0]

# parse defined{{{
# variable line parse
VARB_PARSE = re.compile("".join([
        "\\.([a-zA-Z0-9_-]+)",
        "\s*=\s*(.*)",
    ]))
VARB_CNT_PARSE = re.compile("".join([
        "^((?P<qtov>[\"])(",
        "([^\"]|\\\")*"
        ")(?P=qtov)|[^\"].*)$",
    ]))

# path line parse
LN_PARSE = re.compile("".join([
        "^(?P<qtok>[\"]?)(",
            "([a-zA-Z0-9_\\-]+(\\.[a-zA-Z0-9_\\-]+)*)",
            "(/([a-zA-Z0-9_\\-]+(\\.[a-zA-Z0-9_\\-]+)*))*",
        ")(?P=qtok)",
        "\s*=\s*(.*)",
        ]))
LN_SUB_PARSE = re.compile("".join([
        "^((?P<qtov>[\"]?)(",
            "(@?[a-zA-Z0-9_\\-\\*]+(\\.[a-zA-Z0-9_\\-\\*]+)*)",
            "(;(@?[a-zA-Z0-9_\\-\\*]+(\\.[a-zA-Z0-9_\\-\\*]+)*))*",
        ")(?P=qtov))$"
    ])) 

# parse plugins method
PNAME = re.compile("^p([0-9]?)_([a-zA-Z_]*)$").match
# parse available path name for scaner
PAVAIL_PATH = re.compile("^[a-zA-Z0-9_\\-][a-zA-Z0-9_\\-\\.]*$").match
# parse sub-project name
SUBPROJ_NAME = re.compile("^[a-zA-Z0-9](\\.?[a-zA-Z0-9_\\-]+)*").match

# compile wildcard
def p_wildcard(s):
    return re.compile(
            "^" +
            "([a-zA-Z0-9_\\-\\.]*?)".join(
                map(lambda i:i.replace(".","\\.") ,s.split("*"))) +
            "$"
            ).match

# common file scaner
def common_file_scaner(basepath, exp, depth=0):
    express = re.compile("^%s$" % (
            "(.+?)".join(map(lambda s: s.replace(".", "\\."), exp.split("*")))
            )).match
    bpath = pathlib.Path(basepath)
    def iterpath(pathobj, dep):
        for subobj in pathobj.iterdir():
            if subobj.is_file() and express(str(subobj.relative_to(bpath))):
                yield subobj
            elif subobj.is_dir() and (depth == 0 or dep < depth):
                yield from iterpath(subobj, dep + 1)
    return iterpath(bpath, 0)
#}}}

# source item
SourceItem = namedtuple("SourceItem", ("t", "layer", "identity", "param"))

# environment object {{{
class EnvObject(object):
    #
    def __init__(me):
        # config parse field
        me.debug_path = "debug" # sandbox
        me.dist_path = "dist"   # build distance path
        me.temp_path = "temp"   # temporary
        me.container = None     # container path name
        me._scan_layer = {      # layer scan list
            "base":[],
            "debug":[],
        }
        me.scan_dir = []        # all sub-directories who will scan
        me._preproc = []        # pre-process list
        me.sources = []         # all source obejcts
        me.additfiles = []      # all other depend files
        me.base_container = None    # base container build path
        me._var = {}            # script environment variables

    # add a scaner task
    # task data format is : (task_type, task_detail)
    # task_type may set following values:
    #   var: a variable task, in this case detail is a tuple of key-value pair
    #   preproc: a pre-process task, in this case detail is a preproc tuple
    #   dir: a directory scan task, n this case detail is a scaner function too
    # the preproc tuple format like:
    #   (prority, preproc function)
    #   preproc function prototype seem like:
    #       func() -> <iterateable> -> (layer, base_path, detail_path)
    # the scaner function prototype seem like:
    #   func(basepath) -> <iterateable> -> (base_path, detail_path)
    def add_task(me, task):
        t, d = task
        if t == "var":
            me[d[0]] = d[1]
        elif t == "preproc":
            me._preproc.append(d)
        elif t == "dir":
            me.scan_dir.append(d)
        else:
            raise Exception("unavailable task name")

    # pre-process function iterator
    def preproc_iter(me):
        reorder = list(me._preproc)
        reorder.sort(key = lambda p:p[0])
        for o, p in reorder:
            yield p

    # add source file or directory that been found
    def add_sources(me, itm):
        me.sources.append(itm)

    # add addit depend files
    def add_additdepend(me, itm):
        me.additfiles.append(itm)

    def dump_source(me):
        # format source list to strings
        def fmt_src(src_list):
            tmpsources = list(
                map(lambda s: (
                    s.t, s.layer, s.identity,
                    ", ".join((str(si) for si in s.param)),
                    ),  src_list))
            tmpsources.sort(key = lambda s: s[:3])
            return "\n".join((" || ".join(s) for s in tmpsources))
        #
        layers = me.layer_names()
        layers.sort()
        headln = ("Scanner report file\nBasic:\n"+
        "    DEBUG PATH = %s\n"+
        "    DIST PATH = %s\n"+
        "    TEMP PATH = %s\n"+
        "    CONTAINER AT = %s\n"+
        "    BASE = %s\n"+
        "    LAYERS = %s\n") % (
                me.debug_path,
                me.dist_path,
                me.temp_path,
                me.container or "",
                str(me.base_container or ""),
                ", ".join(layers),
            )
        
        return "%s\nALL SOURCES:\n%s\n\nALL ADDIT:\n%s" % (
                headln, fmt_src(me.sources), fmt_src(me.additfiles))

    # scan layer operations{{{
    # add scan layer
    def add_layer(me, name):
        if name in me._scan_layer:
            raise ScanError("custom layer \"%s\" already exist" % name)
        me._scan_layer[name] = []

    # enmu scan layers name
    def layer_names(me):
        return list(me._scan_layer.keys())

    # get scan layer files
    def layer(me, name):
        return me._scan_layer[name]

    # add source directory to specify layer
    def add_layer_dir(me, name, dpath):
        return me._scan_layer[name].append(dpath)
    #}}}

    # envronment variable operations{{{
    # read environment variable
    def __getitem__(me, name):
        if name in me._var:
            return me._var[name]
        return None
    
    # check environment variable exists
    def __contains__(me, name):
        return name in me._var

    # write environment variable
    def __setitem__(me, name, value):
        me._var[name] = value
    #}}}
#}}}

# global environment
PENV = EnvObject()

# a simple config file implement {{{
class LiteConfig(object):
    PARSE_EXP = re.compile("^([a-zA-Z0-9_\\-\\$]+)\s*=\s*(.*)$")

    def __init__(me, filepath):
        me.__cnt = {}
        fp = pathlib.Path(filepath)
        me.filename = filepath.name
        if not fp.is_file():
            raise ScanError("file not found - %s" % filepath)
        with fp.open("r") as f:
            me._parse(f.read().split("\n"))

    # parse item
    def _item_parse(me, lns):
        mch = me.PARSE_EXP.match(lns[0])
        if not mch:
            raise Exception("invalid configure expression")
        key = mch.group(1)
        def vals():
            val = mch.group(2)
            ln_more = lns[1:]
            if ln_more:
                if val:
                    return [val] + ln_more
                if len(ln_more) > 1:
                    return ln_more
                return ln_more[0]
            return val
        me.__cnt[key] = vals()

    # parse lines
    def _parse(me, lines):
        #
        index = 0       # line index
        indent = None   # indent prefix
        current = 0     # current line parse
        mtln = None
        # create scan error exceptions object
        def create_error(idx, *arg):
            if arg:
                title = arg[0]
                subarg = arg[1:]
            else:
                title = "-"
                subarg = tuple()
            return ScanError("[at line %d] %s" % (idx, title), *subarg)
        # try parse lines
        def try_parse(lns):
            try:
                me._item_parse(mtln)
            except Exception as e:
                raise create_error(current, *e.args)
        # scan
        for ln in map(lambda s:s.rstrip(), lines):
            index = index + 1
            ln_eff = ln.strip()
            if not ln_eff or ln_eff[0] == "#":
                continue
            if ln[0] == " " or ln[0] == "\t":
                if not mtln:
                    raise create_error(index, "Invalid text indent")
                if not indent:
                    indent = ln[:len(ln) - len(ln_eff)]
                elif indent != ln[:len(ln) - len(ln_eff)]:
                    raise create_error(index, "Invalid sub-text indent")
                mtln.append(ln_eff)
            elif mtln:
                try_parse(mtln)
                current = index
                mtln = [ln_eff]
                indent = None
            else:
                current = index
                mtln = [ln_eff]
        if mtln:
            try_parse(mtln)

    # check content is empty
    def isempty(me):
        return not me.__cnt

    # check key
    def __contains__(me, name):
        return name in me.__cnt

    # get config item
    def __getitem__(me, name):
        return me.__cnt[name]

    # string serialize for source
    def __str__(me):
        cnt = ";;".join(
                ("%s = %s" % (k,"\n".join(v)) for k, v in me.__cnt.items()))
        cnthash = hashlib.sha256(cnt.encode("utf-8"))
        return "liteconfig file %s - %s" % (me.filename, cnthash.hexdigest())

    # repr config content
    def __repr__(me):
        return repr(me.__cnt)
#}}}

# make file generator {{{
class MakefileSupport(object):
    # keep file of synchonrization
    CommonKeepFile = ".keep"
    KeepFileDir = ".keeplist"
    SyncKeepFile = "CONTAINER_SYNC"
    SyncDirKeepFile = "DIR_SYNC"

    # source generate progress:
    #   env_sources -> ScannerItem -> MkSource{ MkItem... }
    # make file items {{{
    # source sanner items object
    ScannerItem = namedtuple("ScannerItem", (
        "layer", "overlap", "target", "depends",
        "builders", "phony", "comment"))

    # file items object
    class MkItem(object):
        def __init__(me, sitm):
            me.builder_index = 0
            me.layer = sitm.layer
            me.target = sitm.target
            me.phony = sitm.phony
            me.comment = []
            me.overlaps = {}
            me.depends = []         # general depends
            me.builders = []        # general builders
            me.depends_ovl = {}     # overlapped depends
            me.builders_ovl = {}    # overlapped builders
            me.builders_term = []   # terminal builders
            me._add_builder(sitm.overlap or None, sitm.builders)
            me._add_depend(sitm.overlap or None, sitm.depends)
            if sitm.overlap:
                me.overlaps[sitm.overlap] = sitm
            if sitm.comment:
                if type(sitm.comment) == list:
                    me.comment.extend(sitm.comment)
                else:
                    me.comment.append(sitm.comment)

        # create builder arrange item
        def _builder(me, cmdlmbd, index = None):
            if index is None:
                index = me.builder_index
                me.builder_index = me.builder_index + 1
            return (index, cmdlmbd)

        # add a builder
        def _add_builder(me, overlap, builder):
            if overlap is None:
                me.builders.append(me._builder(builder))
            else:
                if overlap in me.builders_ovl:
                    idx, _ = me.builders_ovl[overlap]
                    me.builders_ovl[overlap] = me._builder(builder, idx)
                else:
                    me.builders_ovl[overlap] = me._builder(builder)
        # add a depend object
        def _add_depend(me, overlap, depend):
            if overlap is None:
                me.depends.append(depend)
            else:
                me.depends_ovl[overlap] = depend

        # append depends and builders with item overlap check
        def append(me, sitm):
            ovl = sitm.overlap or None
            if ovl and ovl in me.overlaps:
                olditm = me.overlaps[ovl]
                if olditm.layer != "base" or sitm.layer == "base":
                    raise ScanExistsError(sitm)
            # append or replace item
            if sitm.comment and (not ovl or ovl not in me.overlaps):
                me.comment.append(sitm.comment)
            if ovl:
                me.overlaps[ovl] = sitm
            me._add_depend(ovl, sitm.depends)
            me._add_builder(ovl, sitm.builders)

        # add terminal builder
        def term_builder(me, builders):
            me.builders_term.append(builders)

        # create depends iterator
        def depends_iter(me, dist_path, temp_path):
            for i in me.depends:
                if i:
                    for j in i(dist_path, temp_path):
                        yield j
            for i in me.depends_ovl.values():
                if i:
                    for j in i(dist_path, temp_path):
                        yield j

        # create builders iterator
        def builders_iter(me, dist_path, temp_path):
            def unorder_iter():
                for i in me.builders:
                    yield i
                for i in me.builders_ovl.values():
                    yield i
            orderbuilder = list(unorder_iter())
            orderbuilder.sort(key = lambda i: i[0])
            for _, b in orderbuilder:
                if b:
                    yield from b(dist_path, temp_path)
            for b in me.builders_term:
                if b:
                    yield from b(dist_path, temp_path)

        # generate makefile distance item
        def makeitems(me, dist_path, temp_path,
                deco_depend = lambda i: i, # decorator of depend iteratable
                deco_cmd = lambda i: i, # decorator of commoand iteratable
                ):
            targ = "%s: %s" % (
                    dist_path.joinpath(me.target), 
                    " ".join(deco_depend((
                        str(d) for d in \
                                me.depends_iter(dist_path, temp_path)))),
                )
            cmd = "\n\t".join(deco_cmd(me.builders_iter(dist_path, temp_path)))
            if cmd:
                return targ + "\n\t" + cmd
            return targ

    # directory generate makefile object
    class MkDirItem(object):
        def __init__(me, layer):
            me.__layer = layer
            me._depends = []
            me._dir = {}

        # add directory
        def add(me, layer, distdir):
            if distdir in me._dir and \
                    (me._dir[distdir] != "base" or layer == "base"):
                raise ScanExistsError(distdir)
            me._dir[distdir] = layer

        # add a depend target
        def add_depend(me, depend):
            me._depends.append(depend)

        # get depends iterator
        def get_depends(me):
            return (d for d in me._depends)

        # create directories distance
        def __call__(me, decorate=None):
            tree = {}
            for i in me._dir.keys():
                swtree = tree
                for p in pathlib.Path(i).parts:
                    if p not in swtree:
                        swtree[p] = {}
                    swtree = swtree[p]
            #
            def dirtree_iter(tr, path=[]):
                for k, n in tr.items():
                    if n:
                        yield from dirtree_iter(n, path + [k])
                    else:
                        yield pathlib.Path().joinpath(*path).joinpath(k)
            if decorate:
                return list(map(decorate, dirtree_iter(tree)))
            return list(dirtree_iter(tree))

    # source generate for makefile
    class MkSource(object):
        def __init__(me, layer):
            me.__layer = layer  # distance layer
            me.__targets = {}   # target reference
            me.__dirs = MakefileSupport.MkDirItem(me.__layer)

        # check target exists
        def __contains__(me, name):
            return name in me.__targets

        # set scanner item
        def add(me, value):
            if value.target in me.__targets:
                existobj = me.__targets[value.target]
                if existobj.layer != "base":
                    raise ScanExistsError(value.target)
                if value.layer == "base": # skip
                    return
            me.__targets[value.target] = MakefileSupport.MkItem(value)

        # add depend directory
        def add_dir(me, layer, path):
            me.__dirs.add(layer, path)

        # create directories maker
        def _mk_dir(me):
            def makedir_cmd(dpath, tmppath):
                for c in me.__dirs(
                        lambda s: lambda d: "mkdir -p %s" % d.joinpath(s)):
                    yield c(dpath)
                keeplist_dir = dpath.joinpath(MakefileSupport.KeepFileDir)
                yield "mkdir -p %s" % keeplist_dir
                yield "echo last sync at `date`>%s" % \
                    keeplist_dir.joinpath(MakefileSupport.SyncDirKeepFile)
            
            return MakefileSupport.MkItem(MakefileSupport.ScannerItem(
                me.__layer,
                None,
                os.path.join(MakefileSupport.KeepFileDir,
                    MakefileSupport.SyncDirKeepFile),
                lambda d, tmp: (_scan_files_record,),
                makedir_cmd,
                False,
                None,
                ))

        # get scanner item
        def __getitem__(me, name):
            return me.__targets[name]

        # create or merge specify target depends and builder
        def stacking(me, itm):
            if itm.target in  me.__targets:
                me.__targets[itm.target].append(itm)
            else:
                me.__targets[itm.target] = MakefileSupport.MkItem(itm)

        # begin iterate all item
        def __iter__(me):
            yield me._mk_dir()
            yield from (v for v in me.__targets.values())

        # get a iterator that enmu all targets
        def targets_iter(me):
            yield MakefileSupport.SyncDirKeepFile
            yield from (k for k in me.__targets.keys)

        # return layer
        def get_layer(me):
            return me.__layer
    #}}}
    
    #
    def __init__(me, env):
        me.__env = env
        # generate objects
        me.dist = {layer:me.MkSource(layer) for layer in \
                filter(lambda s: s != "base", env.layer_names())}
        me.default = me._mk_default(env)    # default make target
        me.common = []                      # common targets
        me.temptrg = []                     # temporary target
        me.additclean = []                  # addit clean list
        me.layerpath = me._layer_path(env)  # layers path reference
        me._source_import(env)
        # append container target
        for l, p in me.layerpath.items():
            me.add_common(me._mk_cnttarget(l, p.joinpath(env.dist_path)),
                    "container %s" % l)
        # append special target
        me.add_common(me._mk_distdir(env.temp_path), "temp directory")
        me.add_common(me._mk_clean(env.debug_path), "clean debug path")
        me.add_common(me._mk_renew(env.debug_path), "renew debug path")
        me.add_common(me._mk_fullclean(env, me.additclean), "full clean")
        if "pre_build" in env:
            me.add_common(me._mk_prebuild(env["pre_build"]),
                    "pre-build operations")
            me.enable_prebuild = True
        else:
            me.enable_prebuild = False
        me.add_common(me._mk_help(list(me._iter_phony())), "help")

    # generate makefile text iter
    def __iter__(me):
        # template directory
        tmp_dir = pathlib.Path(me.__env.temp_path)
        # debug directory
        debug_dir = pathlib.Path(me.__env.debug_path)
        # current directory
        cwdir = pathlib.Path("./")
        # generate all layer path
        layer_dir = {l: d.joinpath(me.__env.dist_path) for l, d in \
                me.layerpath.items()}
        # debug source objects
        debug_src = list(me.dist["debug"])
        # process container sync target
        def container_sync(layer, dpath, tmppath):
            def export(target):
                exp_depend = []
                def depends(d): # export target list
                    exp_depend.extend(list(d))
                    return ("$(ALL_%s_TARGET)" % layer.upper(), )
                def builder(b): # append keep file build
                    yield from b
                    yield "echo last sync at `date`>%s" % \
                            dpath.joinpath(me.KeepFileDir).joinpath(
                                    me.SyncKeepFile)
                # 
                tscr = target.makeitems(dpath, tmppath, depends, builder)
                return (tscr, exp_depend)
            return export
        # export container source
        def container_make(src, dpath, tmppath):
            all_depends = []
            scripts = []
            for s in src:
                # container target
                if s.target == os.path.join(me.KeepFileDir, me.SyncKeepFile):
                    scr, dp = container_sync(
                            src.get_layer(), dpath, tmppath)(s)
                    if dp:
                        all_depends.extend(dp)
                    scripts.append(scr)
                    #all_depends.append(dpath.joinpath(me.KeepFileDir).joinpath(
                    #    me.SyncKeepFile))
                else: # addit targets
                    scripts.append(s.makeitems(dpath, tmppath))
                    if s.phony:
                        all_depends.append(s.target)
                    else:
                        all_depends.append(dpath.joinpath(s.target))
            return (all_depends, scripts)
        # container source objects
        cnt_srcs = {l:container_make(me.dist[l], d, tmp_dir)\
                for l, d in layer_dir.items()}
        # targets variable
        def targets_var(layer, files):
            target_list = list(map(lambda s:str(s), files))
            if me.enable_prebuild:
                target_list = ["_prebuild_"] + target_list
            if not target_list:
                return ""
            # force include temporary direcroty
            target_list.append(str(tmp_dir.joinpath(me.CommonKeepFile)))
            return "# %s targets\nALL_%s_TARGET=%s" % \
                    (layer, layer.upper(), "\\\n    ".join(target_list))
        # output head
        yield "\n".join((
            "# Contianer deploy and debugging automation script",
            "# This file create by _scaner.py",
            "# create at %s" % time.strftime(
                "%h %d, %Y %H:%M:%S UTC",time.gmtime()),
        ))
        
        yield targets_var("debug",
                map(lambda s: str(debug_dir.joinpath(s.target)), debug_src))
        for l, v in cnt_srcs.items():
            yield targets_var(l, v[0])
        # default
        yield "# debug build operation\n" + \
                me.default.makeitems(debug_dir, tmp_dir)
        # all debug build targets
        for d in debug_src:
            yield d.makeitems(debug_dir, tmp_dir)
        # container files
        for l, d in cnt_srcs.items():
            yield "# [%s] coantainer's files" % l
            for s in d[1]:
                yield s
        # temporary subject
        def temp_target(tmp, tdir):
            if tdir:
                dist_dir = tdir(tmp_dir)
            else:
                dist_dir = cwdir
            return tmp.makeitems(dist_dir, tmp_dir)
        if me.temptrg:
            yield "# sub-projects and temp subject"
            for tmp, tdir in me.temptrg:
                yield temp_target(tmp, tdir)
        # manually build targets
        yield "#\n" + \
                me._mk_phony().makeitems(cwdir, tmp_dir)
        # 
        for d, cmt in me.common:
            yield ("# %s\n" % cmt) + d.makeitems(cwdir, tmp_dir)

    # add common item
    def add_common(me, itm, comment):
        me.common.append((itm, comment))

    # add temprory item
    def add_temp(me, itm, tdir):
        me.temptrg.append((itm, tdir))

    # get layers path
    def _layer_path(me, env):
        if not env.container:
            return {}
        p_layer = list(filter(
            lambda s: s != "base" and s != "debug", env.layer_names()))
        if not p_layer:
            return {}
        cntpath = pathlib.Path(env.container)
        return {l:cntpath.joinpath(l) for l in p_layer}

    # import sources
    def _source_import(me, env):
        for src in env.sources:
            src_parse = "src_" + src.t
            if hasattr(me, src_parse):
                getattr(me, src_parse)(env, src)

    # iterater phony distance
    def _iter_phony(me):
        for d in me.dist.values():
            for itm in d:
                if itm.phony:
                    yield itm
        for itm in me.common:
            if itm[0].phony:
                yield itm[0]

    # create phony target
    def _mk_phony(me):
        all_p = tuple((i.target for i in me._iter_phony()))
        return me.MkItem(me.ScannerItem(
                None, None, ".PHONY",
                lambda d, tmp: all_p,
                None,
                False,
                None,
            ))

    # default distance
    @classmethod
    def _mk_default(c, env):
        def builder(d, tmp):
            if "build_debug" in env:
                if type(env["build_debug"]) == list:
                    yield from env["build_debug"]
                else:
                    yield env["build_debug"]
            yield "echo last sync at `date`>%s" % \
                    d.joinpath(c.KeepFileDir).joinpath(c.SyncKeepFile)
        #dist = pathlib.Path(env.debug_path).joinpath(c.SyncKeepFile)
        return c.MkItem(c.ScannerItem(
                None, None,
                os.path.join(c.KeepFileDir, c.SyncKeepFile),
                lambda d, tmp: (
                    "$(ALL_DEBUG_TARGET)",
                ),
                builder,
                False,
                None,
            ))

    # prebuild target
    @classmethod
    def _mk_prebuild(c, cmd):
        if type(cmd) == list:
            cmd = tuple(cmd)
        else:
            cmd = (cmd, )
        return c.MkItem(c.ScannerItem(
                None, None, "_prebuild_",
                None,
                lambda d, tmp: cmd,
                True,
                None,
            ))

    # make container target
    @classmethod
    def _mk_cnttarget(c, layer, path):
        return c.MkItem(c.ScannerItem(
                None, None, layer,
                lambda d, tmp: (path.joinpath(
                    c.KeepFileDir).joinpath(c.SyncKeepFile),),
                None,
                True,
                "container %s" % layer,
            ))

    # create "clean" distance
    @classmethod
    def _mk_clean(c, path):
        return c.MkItem(c.ScannerItem(
                None, None, "clean",
                None,
                lambda d, tmp: (
                    "rm -rf %s/*" % d.joinpath(path),
                    "rm -rf %s" % d.joinpath(path).joinpath(c.KeepFileDir),
                ),
                True,
                "clean debug",
            ))

    # create "renew" distance
    @classmethod
    def _mk_renew(c, path):
        return c.MkItem(c.ScannerItem(
            None, None, "renew",
            lambda d, tmp: (
                "clean", str(d.joinpath(path).joinpath(c.KeepFileDir).joinpath(
                    c.SyncKeepFile))),
            None,
            True,
            "clean and renew debug files",
        ))

    # full clean distance
    def _mk_fullclean(me, env, addcln):
        def cmd_gen(d, tmp):
            cmd = [
                "rm -rf %s" % d.joinpath(env.debug_path),
                "rm -rf %s" % d.joinpath(env.temp_path),
            ]
            if env.container:
                for l in me.layerpath:
                    cmd.append("rm -rf %s" % \
                            d.joinpath(env.container).joinpath(l).\
                            joinpath(env.dist_path))
            # addit project clean commands
            for ac in addcln:
                for c in ac(d, tmp):
                    cmd.append(c)
            return cmd
        return me.MkItem(me.ScannerItem(
            None, None, "fullclean",
            None,
            cmd_gen,
            True,
            "clean all distance",
        ))

    # create temp directory build prolicy
    @classmethod
    def _mk_distdir(c, path):
        temp_trg = str(pathlib.Path(path).joinpath(c.CommonKeepFile))
        return c.MkItem(c.ScannerItem(
                None, None, temp_trg,
                lambda d, tmp: (_scan_files_record,),
                lambda d, tmp: (
                    "mkdir -p %s" % d.joinpath(path),
                    "echo last sync at `date`>%s" % \
                            d.joinpath(temp_trg),
                    ),
                False,
                None,
            ))

    # create help text
    @classmethod
    def _mk_help(c, allphony):
        # filter phony iterator
        def phony_iter():
            for p in allphony:
                comments = list(filter(lambda s:s, p.comment))
                if not comments:
                    continue
                yield "@echo \"    %s\\t %s\"" % (p.target, comments[0])
                if comments[1:]:
                    sp = " ".ljust(len(p.target))
                    for cmt in comments[1:]:
                        yield "@echo \"    %s\\t %s\"" % (sp, cmt)
        # base help
        cmd = [
            "@echo \"\"",
            "@echo usage: make [target]",
            "@echo if target not exist. " +
                "the debug target will execute by default",
            "@echo \"\"",
        ]
        targetcmd = list(phony_iter())
        if targetcmd:
            cmd.append("@echo following targets are been supported")
            cmd.extend(targetcmd)
            cmd.append("@echo \"\"")
        return c.MkItem(c.ScannerItem( # temp dir
                None, None, "help",
                None,
                lambda d, tmp: cmd,
                True,
                None,
            ))

    # process source object
    def src_source(me, env, itm):
        debugpath = pathlib.Path(env.debug_path)
        subj, basepath, path = itm.param
        # convert debug file target
        def debug_file():
            return me.ScannerItem(
                    itm.layer, None, itm.identity,
                    lambda d, tmp: [str(path)],
                    lambda d, tmp: ["cp -p %s %s" % (
                        path, d.joinpath(itm.identity))],
                    False,
                    None,
                )
        # convert container file target
        def specific_file(layer):
            return me.ScannerItem(
                    itm.layer, itm.identity,
                    os.path.join(me.KeepFileDir, me.SyncKeepFile),
                    lambda d, tmp: [str(path)],
                    lambda d, tmp: ["cp -p %s %s" % (
                        path, d.joinpath(itm.identity))],
                    False,
                    None,
                )
        # append a directory to makefile
        def append_dir():
            if itm.layer == "base":
                for ss in me.dist.keys():
                    me.dist[ss].add_dir(itm.layer, itm.identity)
            elif itm.layer in me.dist:
                me.dist[itm.layer].add_dir(itm.layer, itm.identity)
        # append a file to makefile
        def append_file():
            if itm.layer == "debug" or itm.layer == "base":
                me.dist["debug"].add(debug_file()) # debug file builder
                if itm.layer == "debug":
                    return
            #container file builder
            if itm.layer == "base": 
                for ss in me.layerpath.keys():
                    me.dist[ss].stacking(specific_file(ss))
            elif itm.layer in me.dist:
                me.dist[itm.layer].stacking(specific_file(itm.layer))
        #
        if subj == "directory": # directory
            append_dir()
        elif subj == "file": # file
            append_file()


    # process prepare object
    def src_prepare(me, env, itm):
        # append a directory to makefile
        def append_dir(path):
            if itm.layer == "base":
                for ss in me.dist.keys():
                    me.dist[ss].add_dir(itm.layer, path)
            elif itm.layer in me.dist:
                me.dist[itm.layer].add_dir(itm.layer, path)
        #
        subj = itm.param[0]
        if subj == "directory": # directory
            append_dir(str(itm.param[1]))

    # process download packages object
    def src_dlpackage(me, env, itm):
        projname = itm.identity
        projconf = itm.param[0]
        projpath = itm.param[1]
        sp = DLPackageMake(projpath, projname, projconf)
        # convert sub-project item
        def convitem(packnode):
            return me.ScannerItem(
                sp.layer,
                None,
                packnode[0],
                packnode[2],
                packnode[1],
                False,
                None,
            )
        # makefile script
        install = sp.target_install
        me.add_temp(me.MkItem(convitem(sp.target_pack)), sp.gettemp)
        if sp.target_build:
            me.add_temp(me.MkItem(convitem(sp.target_build)), sp.gettemp)
        if sp.layer == "base":
            for ss in me.dist.keys():
                me.dist[ss].add(convitem(sp.target_install))
        else:
            me.dist[sp.layer].add(convitem(sp.target_install))

    # 
    def src_subproj(me, env, itm):
        projname = itm.identity
        projobj = itm.param[0]
        build_dist = "%s/subproj_%s.keep" % (me.KeepFileDir, projname)
        distitem = me.ScannerItem(
                itm.layer, None,
                build_dist,
                lambda d,tmp: list(
                    map(lambda s: str(s), projobj.depend_iter())),
                lambda d, tmp: list(projobj.build_iter(d, build_dist)),
                False,
                None,
                )
        if itm.layer == "base":
            for ss in me.dist.keys():
                me.dist[ss].add(distitem)
        else:
            me.dist[itm.layer].add(distitem)
        if projobj.support_clean():
            me.additclean.append(lambda d, tmp: projobj.clean_iter())
    #}}}

# download package parse and makefile support{{{
class DLPackageMake(object):
    # package URL parse
    PackParse = re.compile("^((http|https|ftp|ssh)://)?(([^/]+/)*?)"+\
            "([a-zA-Z0-9][a-zA-Z0-9\\.\\-_]+?)"+
            "(\\.(" +
            "|".join((
                "git", "zip", "tar\\.gz", "tar\\.bz2",
                "tar\\.bz", "tar\\.xz", "tgz", "tbz2",
                "tbz", "txz", "tar",
            )) +
            "))?$")
    # archive release directory parse
    ReleaseDirParse = re.compile("^[A-Za-z0-9][A-Za-z0-9_\\-\\.]*$")
    # build target parse
    TargetParse = re.compile("^([a-zA-Z0-9_][a-zA-Z0-9_\\-\\.]*"+
            "(\\/[a-zA-Z0-9_\\-\\.]+)*)(\\/\\*)?$")
    # map suffix to general source type
    SourceTypeMap = {
        "git": "git",
        "zip": "zip",
        "tar": "tar",
        "tar.gz": "tgz",
        "tgz":"tgz",
        "tar.bz": "tbz",
        "tar.bz2": "tbz",
        "tbz": "tbz",
        "tbz2": "tbz",
        "tar.xz": "txz",
        "txz": "txz",
        "hg": "hg",
    }

    #
    def __init__(me, projpath, projname, cfg):
        me.layer = "base"
        me.project = projname
        me.projpath = projpath
        me.target_pack = None
        me.target_build = None
        me.target_install = None
        me._apply_config(cfg)

    # get temporary directory
    def gettemp(me, t):
        return t.joinpath(me.project)

    # apply config file
    def _apply_config(me, cfg):
        # parameter check and fixed
        if "layer" in cfg:
            me.layer = cfg["layer"]
        srctype_tag = cfg["source_type"] if "source_type" in cfg else "auto"
        if srctype_tag in me.SourceTypeMap:
            srctype = me.SourceTypeMap[srctype_tag]
        elif srctype_tag == "auto":
            srctype = "auto"
        else:
            raise ScanError("dlpackage invalid \"source_type\" name")
        if not hasattr(me, "_src_" + srctype) and srctype != "auto":
            raise ScanError("dlpackage invalid package source")
        url_mch = me.PackParse.match(cfg["package_url"])
        if not url_mch:
            raise ScanError("dlpackage unmatched URL")
        release_dir = cfg["release_dir"] if "release_dir" in cfg else None
        if release_dir and not me.ReleaseDirParse.match(release_dir):
            raise ScanError(
                    "dlpackage invalid release_dir - %s" % release_dir)
        buildtarg_mch = me.TargetParse.match(cfg["build_distance"])
        if not buildtarg_mch:
            raise ScanError(
                    "dlpackage invalid build_distance - %s" % \
                            cfg["build_distance"])
        build_target = buildtarg_mch.group(1)
        build_target_p = buildtarg_mch.group(0)
        install_prefix = cfg["install_prefix"]
        # generate package download target
        packdown = getattr(me, "_src_" + srctype)(
                url_mch, cfg["package_url"], release_dir)
        me.target_pack = (
                packdown[0],
                packdown[1],
                lambda d, tmp: [str(tmp.joinpath(".keep"))],
            )
        # generate package local build target
        if "build_scripts" in cfg:
            bscr_cmd, bscr_dep = me._build_scr(
                    packdown[0], cfg["build_scripts"])
            me.target_build = (
                    build_target,
                    bscr_cmd,
                    bscr_dep,
                )
        elif build_target != packdown[0]: # simple case
            me.target_build = (
                    build_target,
                    lambda d, tmp: [
                        "cd %s && touch -c -m %s" % (d, build_target)
                    ],
                    lambda d, tmp: [str(d.joinpath(packdown[0]))],
                )
        # generate package install target
        proj_keepfile = "%s/proj_%s.keep" % (
                MakefileSupport.KeepFileDir, me.project)
        me.target_install = (
                proj_keepfile,
                lambda d, t: [
                    "cp -rpf %s %s" % (
                        me.gettemp(t).joinpath(build_target_p),
                        d.joinpath(install_prefix),
                        ),
                    "echo package-proj install at `date`>%s" % \
                            d.joinpath(proj_keepfile),
                ],
                lambda d, t: [
                    me.gettemp(t).joinpath(build_target)
                ],
            )

    # import sub-project build script
    def _build_scr(me, package, scr_cfg):
        if type(scr_cfg) == list:
            buildscr = scr_cfg
        else:
            buildscr = [scr_cfg]
        pathscr = [me.projpath.joinpath(s) for s in buildscr]
        # check file
        def export_build(d, tmp):
            scr_enter = None
            for p in pathscr:
                if not p.is_file():
                    if not scr_enter:
                        raise ScanError(
                                "sub-project build script not exists",
                                str(p))
                    common_warn("sub-project file not exists", str(p))
                    continue
                yield "cp -p %s %s" % (p, d.joinpath(p.name))
                if not scr_enter:
                    scr_enter = p.name
            yield "cd %s && ./%s" % (d, scr_enter)
        def export_depend(d, tmp):
            yield str(d.joinpath(package))
            for p in pathscr:
                if not p.is_file():
                    continue
                yield str(p)
        return export_build, export_depend

    # generate project makefile script
    #def _proj_make(me, dlinfo, cfg):
    #    def cmd_export(d, tmp):
    #        if "build_scripts" in cfg:
    #            buildscr = cfg

    # make source SCM
    def _dsrc_scm(me, urlmatch, url, newdir, scmcmd):
        scheme = urlmatch.group(2)
        if scheme == "ftp" :
            raise ScanError("sub-project unsupported URL scheme")
        target = newdir if newdir else urlmatch.group(5)
        def cmd_export(d, tmp):
            yield "mkdir -p %s" % d
            yield "rm -rf %s" % d.joinpath("*")
            yield from scmcmd(d)
            yield "cd %s && touch -c -m %s" % (d, target)
        return (target, cmd_export, None)

    # make archive files 
    def _dsrc_archiv(me, urlmatch, url, newdir, unarccmd):
        scheme = urlmatch.group(2)
        if not scheme:
            raise ScanError("sub-project required URL scheme")
        target = newdir if newdir else urlmatch.group(5)
        archiv = urlmatch.group(5) + (urlmatch.group(6) or "")
        def cmd_export(d, tmp):
            yield "mkdir -p %s" % d
            yield "curl -L \"%s\" > \"%s\"" % (
                    url.replace("\"", "\\\""),
                    str(d.joinpath(archiv)).replace("\"", "\\\"")
                )
            if newdir:
                yield "mkdir %s" % d.joinpath(newdir)
            yield from unarccmd(d, archiv)
            yield "cd %s && touch -c -m %s" % (d, target)
        return (target, cmd_export, None)

    # make tarball files
    def _dsrc_tarball(me, urlmatch, url, newdir, opt):
        def cmd_export(d, arch):
            if newdir:
                yield "mkdir -p %s" % d.joinpath(newdir)
                yield "cd %s && tar x%sf %s -C %s" % (d, opt, arch, newdir)
            else:
                yield "cd %s && tar x%sf %s" % (d, opt, arch)
        return me._dsrc_archiv(urlmatch, url, newdir, cmd_export)

    # auto source parse from URL
    def _src_auto(me, urlmatch, url, newdir):
        if urlmatch.group(7) in me.SourceTypeMap:
            swsrc = me.SourceTypeMap[urlmatch.group(7)]
            scheme = urlmatch.group(2)
            if scheme == "http" or scheme == "ftp":
                common_warn("sub-project insecure source \"%s\"" % scheme)
            return getattr(me, "_src_" + swsrc)(urlmatch, url, newdir)
        raise ScanError("sub-proj can not parse package type from URL")

    # source git
    def _src_git(me, urlmatch, url, newdir):
        def cmd_exp(d):
            if not newdir:
                yield "cd %s && git clone --depth=1 %s" % (d, url)
            else:
                yield "cd %s && git clone --depth=1 %s %s" % (d, url, newdir)
        return me._dsrc_scm(urlmatch, url, newdir, cmd_exp)

    # source mecurial
    def _src_hg(me, urlmatch, url, newdir):
        def cmd_exp(d):
            if not newdir:
                yield "cd %s && hg clone %s" % (d, url)
            else:
                yield "cd %s && hg clone %s %s" % (d, url, newdir)
        return me._dsrc_scm(urlmatch, url, newdir, cmd_exp)

    # source zip archive
    def _src_zip(me, urlmatch, url, newdir):
        def cmd_export(d, arch):
            if newdir:
                yield "cd %s && unzip %s -d %s" % (d, arch, newdir)
            else:
                yield "cd %s && unzip %s" % (d, arch)
        return me._dsrc_archiv(urlmatch, url, newdir, cmd_export)

    # source tarball with gzip
    def _src_tgz(me, urlmatch, url, newdir):
        return me._dsrc_tarball(urlmatch, url, newdir, "z")

    # source tarball with bzip2
    def _src_tbz(me, urlmatch, url, newdir):
        return me._dsrc_tarball(urlmatch, url, newdir, "j")

    # source tarball with lzma
    def _src_txz(me, urlmatch, url, newdir):
        return me._dsrc_tarball(urlmatch, url, newdir, "J")

    # source pure tar
    def _src_tar(me, urlmatch, url, newdir):
        return me._dsrc_tarball(urlmatch, url, newdir, "")
#}}}

# sub-project file scan and makefile support{{{
class SubProjSupport(object):
    def __init__(me, cfg, path, name):
        me.layer = cfg["layer"] if "layer" in cfg else "base"
        me.basepath = path
        me._config= cfg
        me.projname = name
        if type(cfg["build_exec"]) == str:
            exe_cmd = [cfg["build_exec"]]
        else:
            exe_cmd = cfg["build_exec"]
        me.exe_cmd = [path.joinpath(bdscr) for bdscr in exe_cmd]
        if "clean_exec" in cfg:
            if type(cfg["clean_exec"]) == str:
                exe_cmd = [cfg["clean_exec"]]
            else:
                exe_cmd = cfg["clean_exec"]
            me.clean_cmd = [path.joinpath(bdscr) for bdscr in exe_cmd]
        else:
            me.clean_cmd = []
        me._files = list(me.iter_depend(cfg["sources"], path))
        me.upd_env()

    # depend files iterator
    def iter_depend(me, parse, path):
        if type(parse) == str:
            parse = [parse]
        for p in parse:
            for f in common_file_scaner(path, p):
                yield f

    # update source file list to environment object
    def upd_env(me):
        for i in me._files:
            PENV.add_additdepend(SourceItem(
                "subproj", me.layer, str(i), (me.projname, "depend")))
        for i in me.exe_cmd:
            PENV.add_additdepend(SourceItem(
                "subproj", me.layer, str(i), (me.projname, "execute")))

    # depend file iterator
    def depend_iter(me):
        for i in me._files: yield i
        #for i in me.exe_cmd: yield i

    # build command iterator
    def build_iter(me, dist_path, dist_file):
        reldist = os.path.relpath(str(dist_path), str(me.basepath))
        for cmd in me.exe_cmd:
            scr = cmd.relative_to(me.basepath)
            yield "cd %s && DIST_PATH=%s %s" % (
                    str(me.basepath), reldist, scr)
        yield "echo package-proj install at `date`>%s" % \
                str(dist_path.joinpath(dist_file))

    # check sub-project supported clean command
    def support_clean(me):
        return (me.clean_cmd and True) or False

    # clean command
    def clean_iter(me):
        for cmd in me.clean_cmd:
            scr = cmd.relative_to(me.basepath)
            yield "cd %s && %s" % (str(me.basepath), scr)

    # to string
    def __str__(me):
        return "<Subproject> %s - %s, %s" % (me.projname,
                str(me.basepath), str(me._config))
#}}}

# imagetool script supports {{{
class ImgtoolSupport(object):
    Execname = "docker"

    # class factory
    @classmethod
    def try_create(c, env):
        if not env.container or "container_tag" not in env:
            common_warn("\"container_tag\" not defined in PATH")
            return None
        cntpath = pathlib.Path(env.container)
        bflt = lambda l: l != "debug" if env.base_container else\
                lambda l: l != "debug" and l != "base"
        flt_cnt = lambda l: bflt(l) and \
                cntpath.joinpath(l).joinpath("Dockerfile").is_file()
        layers = filter(flt_cnt, env.layer_names())
        if not layers:
            common_warn("no container been found")
            return None
        scrname = env["image_script"] if "image_script" in env else "imgtool"
        return c(layers, cntpath, scrname, env)

    #
    def __init__(me, layers, path, scrname, env):
        me._env = env
        me._cntall = {l:path.joinpath(l) for l in layers}
        me._layers = layers
        me._tag = env["container_tag"]
        if "docker_host" in me._env: # remote support
            me._remote = me._gen_remote()
        else:
            me._remote = None
        me._scrname = scrname

    # get script name
    def script_name(me):
        return me._scrname

    # get image tag
    def img_tag(me, layer):
        if layer == "base":
            return me._tag + "-base"
        return "%s:%s" % (me._tag, layer)

    # get content tag
    def cnt_tag(me, layer):
        return "c-%s-%s" % (me._tag, layer)

    # script head
    def _gen_head(me):
        return "\n".join((
            "#!/bin/sh",
            "# create at %s" % time.strftime(
                "%h %d, %Y %H:%M:%S UTC",time.gmtime()),
            "# _scaner.py automation",
        ))

    # remote enable
    def _gen_remote(me):
        def cmd_talker():
            yield "# enable remote docker server"
            yield "function enable_remote(){"
            yield "  export DOCKER_HOST=\"%s\"" % me._env["docker_host"]
            if "docker_cert_path" in me._env:
                yield "  export DOCKER_CERT_PATH=\"%s\"" % \
                        me._env["docker_cert_path"]
                yield "  DOCKER=\"$DOCKER --tlsverify\""
            yield "}"
        return "\n".join(cmd_talker())

    # image builder
    def _gen_builder_iter(me):
        # select builder
        def selector():
            yield "# select build tag"
            yield "function img_build(){"
            yield "  case $1 in"
            for l in me._cntall.keys():
                yield "    \"%s\") img_build_%s\n      ;;" % (l,l)
            yield "    *) echo \"unknown build target\""
            yield "      ;;"
            yield "  esac"
            yield "}"
        # per-layer builder
        def images(layer, path):
            yield "# build image - %s" % layer
            yield "function img_build_%s(){" % layer
            if layer != "base":
                yield "  %s %s" % ("make", layer)
                yield "  ret=$?; if [[ $ret != 0 ]]; then exit $ret; fi"
            yield "  $DOCKER build %s -t %s" % (path, me.img_tag(layer))
            yield "}"
        # per-layer remove
        def remove_selector():
            yield "# select to remove image"
            yield "function img_remove(){"
            yield "  case $1 in"
            for l in me._cntall.keys():
                yield "    \"%s\") $DOCKER rmi %s" % (l, me.img_tag(l))
                yield"      ;;"
            yield "    *) echo \"unknown build target\""
            yield "      ;;"
            yield "  esac"
            yield "}"
        #
        for l, p in me._cntall.items():
            yield "\n".join(images(l, p))
        yield "\n".join(selector())
        yield "\n".join(remove_selector())

    # debug script
    def _gen_debug(me):
        # container config
        def create_cmd():
            param = [
                "$DOCKER",
                "run",
                "-it",
                "--name",
                me.cnt_tag("debug")
            ]
            if "debug_net_adapt" in me._env:
                param.append("--network %s" % me._env["debug_net_adapt"])
            if "debug_ports_map" in me._env:
                for p in filter(
                        lambda p: p, me._env["debug_ports_map"].split(";")):
                    param.append("-p %s" % p)
            param.append("-v")
            param.append("`pwd`/%s:/home/deploy" % me._env.debug_path)
            param.append(me.img_tag("base"))
            return " ".join(param)
        # export commands
        def cmt_talker():
            yield "# debug operations"
            yield "function cnt_debug(){"
            yield "  case $1 in"
            yield "    \"new\")"
            yield "      make"
            yield "      ret=$?; if [[ $ret != 0 ]]; then exit $ret; fi"
            yield "      %s" % create_cmd()
            yield "      ;;"
            yield "    \"stop\") $DOCKER stop %s" % me.cnt_tag("debug")
            yield "      ;;"
            yield "    \"start\")"
            yield "      make"
            yield "      ret=$?; if [[ $ret != 0 ]]; then exit $ret; fi"
            yield "      $DOCKER start -ai %s" % me.cnt_tag("debug")
            yield "      ;;"
            yield "    \"remove\") $DOCKER rm %s" % me.cnt_tag("debug")
            yield "      ;;"
            yield "    *) echo \"Invalid debug operation\""
            yield "      ;;"
            yield "  esac"
            yield "}"
        return "\n".join(cmt_talker())

    # help document
    def _gen_help(me):
        layers = ",".join(me._cntall.keys())
        def cmd_talker():
            yield "# help document"
            yield "function doc_help(){"
            yield "  echo \"\""
            yield "  echo \"%s help document\"" % me._scrname
            if me._remote:
                yield "  echo \"usage: %s [-r] command parameters...\"" % me._scrname
            else:
                yield "  echo \"usage: %s command parameters...\"" % me._scrname
            yield "  echo \"\""
            yield "  echo \"current support build target: %s\"" % layers
            if me._remote:
                yield "  echo \"use \\\"-r\\\" tag to enable remote docker server\""
            yield "  echo \"\""
            yield "  echo \"  build  <target>   build image\""
            yield "  echo \"  remove <target>   remove image\""
            yield "  echo \"  debug new         create debug container, run immeditly\""
            yield "  echo \"  debug start       start and attach to debug container\""
            yield "  echo \"  debug stop        manually stop debug container\""
            yield "  echo \"  debug rm          remove debug container\""
            yield "  echo \"\""
            yield "}"
        return "\n".join(cmd_talker())

    # script index
    def _gen_index_iter(me):
        # avaliable sub-commands
        def avaliable_selector():
            yield "# index"
            yield "function command_selector(){"
            yield "  case $1 in"
            yield "    \"build\") img_build $2"
            yield "      ;;"
            yield "    \"remove\") img_remove $2"
            yield "      ;;"
            yield "    \"debug\") cnt_debug $2"
            yield "      ;;"
            yield "    *) doc_help"
            yield "      ;;"
            yield "  esac"
            yield "}"
        # script main
        def main_selector():
            if me._remote:
                yield "# check remote enable"
                yield "if [ $1 == \"-r\" ]"
                yield "then"
                yield "  enable_remote"
                yield "  command_selector $2 $3"
                yield "else"
                yield "  command_selector $1 $2"
                yield "fi"
            else:
                yield "command_selector $1 $2"
        #
        yield "\n".join(avaliable_selector())
        yield "\n".join(main_selector())

    # output script
    def __iter__(me):
        yield me._gen_head()
        yield "DOCKER=\"%s\"" % me.Execname
        if me._remote:
            yield me._remote
        yield from me._gen_builder_iter()
        yield me._gen_debug()
        yield me._gen_help()
        yield from me._gen_index_iter()

#}}}

#}}}

# all plugins
_all_pitem = {}

# parser decorator
def pitem(f):
    pexp = PNAME(f.__name__)
    if not pexp:
        raise ScanError("invalid parser function :%s" % f.__name__)
    prority = int(pexp.group(1) or 0)
    _all_pitem[pexp.group(2)] = (prority, f)
    return f

# plugins {{{
# set debug container mount path
@pitem
def p_debug(p):
    PENV.debug_path = p
    return []

# set distance path
@pitem
def p_dist(p):
    PENV.dist_path = p
    return []

# set crossover files root path
@pitem
def p1_cross(p):
    pobj = pathlib.Path(p)
    if not pobj.is_dir():
        common_warn("\"%s\" is not a avaliable path for crossover scaner" % p)
        return[]
    for layer in PENV.layer_names():
        layerpath = pobj.joinpath(layer)
        if layerpath.is_dir():
            PENV.add_layer_dir(layer, layerpath)
    return []

# specify root path to resource scan
@pitem
def p_root(p):
    pobj = pathlib.Path(p)
    if not pobj.is_dir():
        common_warn("\"%s\" is not a avaliable path for scaner" % p)
        return []
    PENV.add_layer_dir("base", pobj)
    return []

# containers directory
@pitem
def p_container(p):
    pobj = pathlib.Path(p)
    if not pobj.is_dir():
        common_warn("\"%s\" container path not found" % p)
        return []
    PENV.container = p
    cnt_parse = re.compile("[a-zA-Z0-9_]+").match
    for pech in pobj.iterdir():
        if pech.is_dir() and cnt_parse(pech.name) and\
                pech.joinpath("Dockerfile").is_file():
            if pech.name == "base":
                PENV.base_container = pech
            elif pech.name == "debug":
                common_warn(
                        "ignore container path \"debug\". it's invalid layer")
            else:
                PENV.add_layer(pech.name)
    return []

# prepare directory name
@pitem
def p_dir(p):
    pobj = pathlib.Path(p)
    return [SourceItem(
                "prepare",
                "base",
                p,
                ("directory", pobj),
            )]

# temporary directory
@pitem
def p_temp(p):
    PENV.temp_path = p
    return []

# download packages
@pitem
def p1_dlpackage(p):
    pobj = pathlib.Path(p)
    if not pobj.is_dir():
        common_warn("invalid download packages script directory: %s" % p)
    ret = []
    for d in filter(
            lambda p: p.suffix == ".proj" and p.is_file(), pobj.iterdir()):
        cfgobj = LiteConfig(d)
        if "package_url" not in cfgobj:
            raise 
        if cfgobj.isempty() or "package_url" not in cfgobj or \
                "build_distance" not in cfgobj or \
                "install_prefix" not in cfgobj:
            common_warn("invalid download packages file %s" % d)
            continue
        projname = d.name[:-len(d.suffix)]
        ret.append(SourceItem(
            "dlpackage",
            cfgobj["layer"] if "layer" in cfgobj else "base",
            projname,
            (cfgobj, pobj),
            ))
    return ret

# sub-projects
@pitem
def p1_subproj(p):
    pobj = pathlib.Path(p)
    if not pobj.is_dir():
        common_warn("invalid subproject directory %s" % p)
    ret = []
    for d in filter(
            lambda p: p.is_dir() and SUBPROJ_NAME(p.name) and \
                    p.joinpath("build.proj").is_file(),
            pobj.iterdir()):
        cfgobj = LiteConfig(d.joinpath("build.proj"))
        projname = d.name
        ret.append(SourceItem(
            "subproj",
            cfgobj["layer"] if "layer" in cfgobj else "base",
            projname,
            (SubProjSupport(cfgobj, d, projname), ),
            ))
    return ret

#}}}

# scaner logic {{{
# load "PATH" config file
def load_path_conf(env):
    # create config error
    def create_error(index, *arg):
        if arg:
            title = arg[0]
            subarg = arg[1:]
        else:
            title = "-"
            subarg = tuple()
        return ConfigError("[at line %d] %s" % (index, title), *subarg)

    # reverse escaped variable value
    def rev_varb(s, addit):
        if s and s[0] == '"':
            if addit:
                s = s + "\n" + "\n".join(addit)
            if not VARB_CNT_PARSE.match(s):
                raise Exception(
                        "invalid variable values in \"PATH\":", s, *addit)
            return "\\".join(
                    (ss.replace("\\\"", "\"") for ss in s[1:-1].split("\\\\"))
                    ).split("\n")
        elif addit:
            if s:
                return [s] + addit
            if len(addit) > 1:
                return addit
            return addit[0]
        return s
    
    # make pre-process function
    def make_preproc(path ,s):
        if s[1:] not in _all_pitem:
            return common_error(
                    "unavailable pre-process plugin named [%s]" % s)
        proir, proc = _all_pitem[s[1:]]
        return ("preproc", (proir ,lambda: proc(path)))
    
    # make file iterator
    def make_file_iter(path, fiter):
        wplist = [p_wildcard(f) for f in fiter]
        if not wplist:
            return None
        # directory iter
        def eachdir(basepath, pobj):
            enabled_path = False
            for itm in pobj.iterdir():
                if itm.is_file() and reduce(
                        lambda a,b: a or b, 
                        map(lambda p: p(itm.name),wplist)):
                    # enable directory
                    if not enabled_path:
                        enabled_path = True
                        yield ("directory", basepath, pobj)
                    # files
                    yield ("file", basepath, itm)
                elif itm.is_dir() and PAVAIL_PATH(itm.name[0]):
                    # directory
                    yield from eachdir(basepath, itm)
        # exxport iterator
        def export(basepath):
            cur_path = basepath.joinpath(path)
            if not cur_path.is_dir():
                return
            yield from eachdir(basepath, cur_path)
        return ("dir", export)

    # parse a variable
    def var_parse(ln):
        mch = VARB_PARSE.match(ln[0])
        if mch:
            return [("var", (mch.group(1), rev_varb(mch.group(2), ln[1:])))]
        return None
    
    # parse a directory operation
    def dir_parse(ln):
        mch = LN_PARSE.match(ln[0])
        def match_iter():
            p_path = mch.group(2)
            head_parse = mch.group(8)
            if head_parse and ln[1:]:
                pline = head_parse + ";" +";".join(ln[1:])
            elif ln[1:]:
                pline = ";".join(ln[1:])
            else:
                pline = head_parse
            mch_val = LN_SUB_PARSE.match(pline)
            if not mch_val:
                raise Exception(
                        "invalid directory pattern in \"PATH\":", *ln)
            all_parse = mch_val.group(3).split(";")
            # add pre-process tag
            for i in filter(lambda s: s[0] == "@", all_parse):
                yield make_preproc(p_path, i)
            # add general item
            yield make_file_iter(
                    p_path, filter(lambda s: s[0] != "@", all_parse))
        if mch:
            return match_iter()
        return None

    # parse config line
    def line_parse(lns):
        def try_parse(lns_p):
            try:
                return var_parse(lns_p) or dir_parse(lns_p)
            except Exception as e:
                raise create_error(index - 1, *e.args)
        indent = None
        mtln = None
        index = 0
        for ln in map(lambda ln:ln.rstrip(), lns):
            index = index + 1
            ln_eff = ln.strip()
            if not ln_eff or ln_eff[0] == "#": # skip comment
                continue
            if ln[0] == " " or ln[0] == "\t": # sub-parse
                if not mtln:
                    raise create_error(index, 
                            "Invalid config line in \"PATH\":", ln)
                if not indent:
                    indent = ln[:len(ln) - len(ln_eff)]
                elif ln[:len(ln) - len(ln_eff)] != indent:
                    raise create_error(index,
                            "inconsistent indent in \"PATH\":", ln)
                mtln.append(ln_eff)
            elif mtln: # headline parse
                lniter = try_parse(mtln)
                if not lniter:
                    raise create_error(index - 1, 
                            "parse \"PATH\" error at line:", *mtln)
                yield from lniter
                indent = None
                mtln = [ln_eff]
            else:
                mtln = [ln_eff]
        # last parse
        if mtln:
            lniter = try_parse(mtln)
            if not lniter:
                raise create_error(index - 1,
                        "parse \"PATH\" error at line:", *mtln)
            yield from lniter

    all_ln = open("PATH","r+").read().split("\n")
    for t in filter(lambda s:s, (i for i in line_parse(all_ln))):
        env.add_task(t)

# run file scan
def scan_files(path_list, layer):
    for ppath in path_list:
        for pscan in PENV.scan_dir:
            for pitm in pscan(ppath):
                PENV.add_sources(SourceItem(
                    "source",
                    layer,
                    str(pitm[2].relative_to(pitm[1])),
                    pitm,
                ))
#}}}

# check scan keep file
def check_keepfile(env):
    cnt = env.dump_source().encode("utf-8")
    keepobj = pathlib.Path(_scan_files_record)
    if keepobj.exists():
        if not keepobj.is_file():
            raise ScanError("invalid keep file \"%s\"" % _scan_files_record)
        with open(_scan_files_record, "rb") as fp:
            hfile = hashlib.sha256(fp.read()).hexdigest()
        hcnt = hashlib.sha256(cnt).hexdigest()
        if hfile == hcnt:
            return False
    open(_scan_files_record, "wb+").write(cnt)
    return True

# main function
def main():
    # file generate{{{
    # write makefile
    def write_makefile():
        filename = PENV["makefile"] if "makefile" in PENV else\
                "Makefile"
        mkfile = MakefileSupport(PENV)
        open(filename, "w+").write("\n\n".join(mkfile))
    def write_imgscript():
        imgscr = ImgtoolSupport.try_create(PENV)
        if not imgscr:
            common_warn("skip create image builder script")
            return
        open(imgscr.script_name(), "w+").write("\n\n".join(imgscr))
        pathlib.Path(imgscr.script_name()).chmod(0o750)
    #}}}
    # read path config
    if not os.path.isfile("PATH"):
        common_error("\"PATH\" file is not exists")
    try:
        load_path_conf(PENV)
        for proc in PENV.preproc_iter():
            for itm in proc():
                PENV.add_sources(itm)
        for layer in PENV.layer_names():
            scan_files(PENV.layer(layer), layer)
        if not check_keepfile(PENV):
            print("no change")
            return
        write_makefile()
        write_imgscript()
    except Exception as e:
        common_error(str(e))
        #raise e

main()
