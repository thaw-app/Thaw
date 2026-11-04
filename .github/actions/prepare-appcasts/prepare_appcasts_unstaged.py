"""prepare_appcasts.py for a release that reaches every Mac at once.

org-ci runs the appcast script it's given with a fixed environment, so Release
picks this entry point instead of passing a flag.
"""

import sys
from pathlib import Path

# org-ci runs the script with python3 -I, which leaves its own directory off sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from prepare_appcasts import main  # noqa: E402

if __name__ == "__main__":
    main(staged=False)
