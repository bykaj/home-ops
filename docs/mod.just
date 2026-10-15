set default-list
set default-script
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('Serve the docs site locally with live reload')]
serve:
    zensical serve -f "{{ source_directory() }}/zensical.toml"

[doc('Build the docs site strictly, like CI')]
build:
    zensical build --clean --strict -f "{{ source_directory() }}/zensical.toml"

[doc('Regenerate the app tables in the docs (--check to verify only)')]
apps *args:
    uv run --script "{{ source_directory() }}/../scripts/docs-applications.py" {{ args }}
