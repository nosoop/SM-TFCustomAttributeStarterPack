# vim: set sts=2 ts=8 sw=2 tw=99 et:
import sys
from ambuild2 import run

# Simple extensions do not need to modify this file.

builder = run.PrepareBuild(sourcePath = sys.path[0])

builder.options.add_option('--spcomp-dir', type=str, dest='spcomp_dir', default=None,
                           help='SourcePawn compiler / scripting directory')

builder.Configure()
