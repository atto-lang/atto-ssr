"""Limited HTML text and safe-attribute escaping reference (host-only)."""
from html import escape
import re

_SAFE_NAME = re.compile("(?:title|alt|id|class|role|data-[a-z][a-z0-9_-]*|aria-[a-z][a-z0-9_-]*)", re.ASCII)


class EscapingError(ValueError):
    pass


def _text(value, *, max_length=4096):
    if type(value) is not str or len(value) > max_length:
        raise EscapingError("value must be a bounded string")
    if any(ord(ch) < 32 and ch not in "\t\n\r" for ch in value):
        raise EscapingError("disallowed control character")
    if any(0xD800 <= ord(ch) <= 0xDFFF for ch in value):
        raise EscapingError("unpaired surrogate")
    return value


def escape_html_text(value):
    """Only for HTML text nodes, not script/style, URLs or raw HTML."""
    return escape(_text(value), quote=True)


def safe_attribute(name, value):
    """Emit a quoted, escaped non-URL attribute with a restricted allowlist."""
    if type(name) is not str or not _SAFE_NAME.fullmatch(name):
        raise EscapingError("attribute name not in safe allowlist")
    raw = _text(value)
    if "\n" in raw or "\r" in raw or "\t" in raw:
        raise EscapingError("attribute cannot contain control whitespace")
    return ' ' + name + '="' + escape(raw, quote=True) + '"'


def render_text_nodes(parts):
    """Concatenate escaped untrusted text nodes; returns text, not a template."""
    if type(parts) not in (list, tuple) or len(parts) > 1024:
        raise EscapingError("too many text nodes")
    return "".join(escape_html_text(part) for part in parts)
