"""prepare_appcasts.py for a release that reaches every Mac at once.

org-ci runs the appcast script it's given with a fixed environment, so Release
picks this entry point instead of passing a flag.
"""

from prepare_appcasts import main

if __name__ == "__main__":
    main(staged=False)
