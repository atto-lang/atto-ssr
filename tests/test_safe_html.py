import unittest
from reference.safe_html import EscapingError, escape_html_text, render_text_nodes, safe_attribute


class SafeHtmlTest(unittest.TestCase):
    def test_text_and_attribute_escape(self):
        self.assertEqual(escape_html_text('<script>"x"&</script>'),
                         '&lt;script&gt;&quot;x&quot;&amp;&lt;/script&gt;')
        self.assertEqual(safe_attribute("data-value", '" onclick="evil()'),
                         ' data-value="&quot; onclick=&quot;evil()"')
        self.assertEqual(render_text_nodes(["hello ", "<world>"]),
                         "hello &lt;world&gt;")

    def test_reject_url_and_event_attributes(self):
        for name in ["onclick", "style", "href", "src", "srcdoc", "onload"]:
            with self.assertRaises(EscapingError):
                safe_attribute(name, "javascript:alert(1)")

    def test_reject_invalid_and_ambiguous_values(self):
        for invalid in ["\x00", "\ud800", "x" * 4097]:
            with self.assertRaises(EscapingError):
                escape_html_text(invalid)
        with self.assertRaises(EscapingError):
            safe_attribute("title", "a\nb")


if __name__ == "__main__":
    unittest.main()
