import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).parent / "scripts" / "fetch_content.py"
SPEC = importlib.util.spec_from_file_location("fetch_content", SCRIPT)
fetch_content = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fetch_content)


SAMPLE_METADATA = {
    "stable-diffusion/demo.ipynb": {
        "title": "Text-to-Image Generation with Stable Diffusion and OpenVINO",
        "path": "stable-diffusion/demo.ipynb",
        "links": {
            "github": "https://github.com/openvinotoolkit/openvino_notebooks/blob/latest/notebooks/stable-diffusion/demo.ipynb",
            "docs": None,
        },
        "tags": {
            "categories": ["Model Demos", "AI Trends"],
            "tasks": ["Text-to-Image"],
            "libraries": ["Diffusers", "OpenVINO GenAI"],
            "other": ["Stable Diffusion"],
        },
    },
    "yolo/demo.ipynb": {
        "title": "Object Detection with YOLO and OpenVINO",
        "path": "yolo/demo.ipynb",
        "links": {},
        "tags": {
            "categories": ["Model Demos"],
            "tasks": ["Object Detection"],
            "libraries": ["Ultralytics"],
            "other": [],
        },
    },
}


class SelectorMetadataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items = fetch_content.parse_notebooks_selector_metadata(SAMPLE_METADATA)

    def test_preserves_official_tags_and_content_links(self):
        item = self.items[0]
        self.assertEqual(item["tasks"], ["Text-to-Image"])
        self.assertEqual(item["categories"], ["Model Demos", "AI Trends"])
        self.assertTrue(item["raw_url"].endswith("notebooks/stable-diffusion/demo.ipynb"))
        self.assertEqual(item["source"], "openvino-notebooks-selector")

    def test_filters_by_exact_task_and_category(self):
        result = fetch_content.filter_notebooks(
            self.items, task="text-to-image", category="model demos"
        )
        self.assertEqual([item["slug"] for item in result], ["stable-diffusion"])

    def test_chinese_text_to_image_query_uses_navigation_taxonomy(self):
        result = fetch_content.filter_notebooks(self.items, query="文生图")
        self.assertEqual([item["slug"] for item in result], ["stable-diffusion"])

    def test_free_text_search_and_limit(self):
        result = fetch_content.filter_notebooks(self.items, query="OpenVINO", limit=1)
        self.assertEqual(len(result), 1)


if __name__ == "__main__":
    unittest.main()
