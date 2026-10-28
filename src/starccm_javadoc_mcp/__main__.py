"""Run the CLI when invoked via python -m starccm_javadoc_mcp."""

import sys
from .cli import main

if __name__ == "__main__":
    sys.exit(main())
