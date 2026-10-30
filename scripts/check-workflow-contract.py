#!/usr/bin/env python3
"""Fail closed on workflow API/reference drift; update hashes only after doc review."""
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parent.parent
manifest = root / 'Sources/sloppy/Resources/Skills/workflow/references/contract-sources.sha256.json'
changed = [name for name, digest in json.loads(manifest.read_text()).items()
           if hashlib.sha256((root / name).read_bytes()).hexdigest() != digest]
if changed:
    raise SystemExit('Workflow contract drift: review references/api.md and examples before rebaselining: ' + ', '.join(changed))
print('Workflow contract drift check passed')
