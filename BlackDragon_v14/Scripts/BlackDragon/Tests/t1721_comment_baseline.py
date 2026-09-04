"""Reverse only owner-authorized T17.21 comment edits for frozen older hashes."""
import json
from pathlib import Path
REPO=Path(__file__).resolve().parents[4]
MANIFEST=json.loads((REPO/'BlackDragon_v14/docs/vibecode/T17_21_comments/comment_changes.json').read_text())
def before_comments(path,text):
    for edit in reversed(MANIFEST['replacements']):
        if edit['path'] != path: continue
        if text.count(edit['new']) != 1:
            raise AssertionError('T17.21 exact authorized edit missing/ambiguous: '+path)
        text=text.replace(edit['new'],edit['old'],1)
    return text
