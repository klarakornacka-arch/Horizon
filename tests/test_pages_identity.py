from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "docs" / "_config.yml"
FEED_ZH_PATH = ROOT / "docs" / "feed-zh.xml"


def read_top_level_scalar(config: str, key: str) -> str:
    matches = re.findall(rf"(?m)^{re.escape(key)}:\s*(.+?)\s*(?:#.*)?$", config)
    assert len(matches) == 1, f"expected one top-level {key} value"
    return matches[0].strip().strip('"\'')


def test_pages_identity_and_chinese_feed_use_fork_canonical_url() -> None:
    config = CONFIG_PATH.read_text(encoding="utf-8")
    feed = FEED_ZH_PATH.read_text(encoding="utf-8")

    title = read_top_level_scalar(config, "title")
    description = read_top_level_scalar(config, "description")
    url = read_top_level_scalar(config, "url")
    baseurl = read_top_level_scalar(config, "baseurl")

    assert title == "AI 设计师成长雷达"
    assert description == "面向 AI 创作者的每日前沿情报与选题简报"
    assert url == "https://klarakornacka-arch.github.io"
    assert baseurl == "/Horizon"
    assert f"{url}{baseurl}/" == "https://klarakornacka-arch.github.io/Horizon/"

    assert "{{ site.title }}" in feed
    assert "{{ '/feed-zh.xml' | absolute_url }}" in feed
    assert feed.count("{{ '/' | absolute_url }}") == 2
    assert feed.count("{{ post.url | absolute_url }}") == 2

    active_pages_files = [CONFIG_PATH, *sorted((ROOT / "docs").glob("feed*.xml"))]
    for path in active_pages_files:
        content = path.read_text(encoding="utf-8")
        assert "thysrael.github.io" not in content
