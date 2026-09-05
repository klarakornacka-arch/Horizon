import json
from pathlib import Path
from unittest.mock import AsyncMock

from src.models import Config


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "data" / "config.github.json"
PROFILE_IDS = [
    "ai-blogger",
    "ai-blogger-tools",
    "ai-blogger-dev",
    "ai-blogger-business",
    "ai-blogger-growth",
]

EXPECTED_PROFILES = {
    "ai-blogger": "AI 行业与模型热点",
    "ai-blogger-tools": "AI 设计工具与工作流",
    "ai-blogger-dev": "设计思维与品牌审美",
    "ai-blogger-business": "自媒体选题与商业机会",
    "ai-blogger-growth": "小白成长与当日行动",
}

REQUIRED_BLOCKS = [
    {"id": "summary", "type": "section", "tools": [], "primary": True},
    {"id": "selection_rationale", "type": "section", "tools": []},
    {"id": "aesthetic_review", "type": "section", "tools": []},
    {"id": "design_thinking", "type": "section", "tools": []},
    {"id": "business_lens", "type": "section", "tools": []},
    {"id": "creator_angle", "type": "section", "tools": []},
    {"id": "today_action", "type": "section", "tools": []},
]

EVIDENCE_HEADINGS = [
    "入选依据", "审美点评", "设计思维", "商业视角", "创作角度", "今日行动"
]


def load_config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def test_cloud_config_is_safe_and_bounded():
    raw = CONFIG.read_text(encoding="utf-8")
    config = json.loads(raw)
    runtime_config = Config.model_validate(config)
    assert "sk-" not in raw
    assert runtime_config.ai.languages == ["zh"]
    assert runtime_config.digest.max_items == 15
    assert runtime_config.processing.default_profile == "ai-blogger"
    assert config["digest"]["profile_order"] == PROFILE_IDS


def test_github_runtime_uses_deepseek_v4_flash():
    config = json.loads((ROOT / "data" / "config.github.json").read_text(encoding="utf-8"))
    assert config["ai"]["provider"] == "deepseek"
    assert config["ai"]["model"] == "deepseek-v4-flash"
    assert config["ai"]["api_key_env"] == "DEEPSEEK_API_KEY"


def test_five_category_limits_total_fifteen():
    groups = load_config()["digest"]["category_groups"]
    assert groups == {
        "models": {
            "name": "AI 行业与模型热点",
            "limit": 4,
            "categories": ["model-industry"],
        },
        "tools": {
            "name": "AI 设计工具与工作流",
            "limit": 3,
            "categories": ["ai-tools", "dev-open-source"],
        },
        "design": {
            "name": "设计思维与品牌审美",
            "limit": 3,
            "categories": ["design-brand", "design-thinking"],
        },
        "business": {
            "name": "自媒体选题与商业机会",
            "limit": 3,
            "categories": ["ai-business", "creator-business"],
        },
        "growth": {
            "name": "小白成长与当日行动",
            "limit": 2,
            "categories": ["designer-growth"],
        },
    }
    assert sum(group["limit"] for group in groups.values()) == 15
    assert load_config()["digest"]["max_items"] == 15


def test_profile_settings_apply_the_required_threshold_and_deduplication():
    profile_settings = load_config()["processing"]["profile_settings"]
    assert set(profile_settings) == set(PROFILE_IDS)
    for profile_id in PROFILE_IDS:
        assert profile_settings[profile_id] == {
            "threshold": 7.0,
            "topic_dedup": True,
        }


def test_out_of_scope_sources_are_disabled():
    sources = load_config()["sources"]
    assert sources["twitter"]["enabled"] is False
    assert sources["telegram"]["enabled"] is False
    assert sources["openbb"]["enabled"] is False
    assert load_config()["email"]["enabled"] is False
    assert load_config()["webhook"]["enabled"] is False


def test_sources_include_chinese_rss_and_only_smokeable_reddit_communities():
    sources = load_config()["sources"]
    assert not any("news.google.com/rss/search" in source["url"] for source in sources["rss"])
    assert sources["google_news"]["enabled"] is True
    assert sources["google_news"]["language"] == "en"
    assert "ArtificialIntelligence" not in {
        subreddit["subreddit"] for subreddit in sources["reddit"]["subreddits"]
    }


def test_google_news_config_routes_to_dedicated_scraper():
    from src.models import Config
    from src.scrapers.google_news import GoogleNewsScraper

    config = Config.model_validate(load_config())
    assert isinstance(GoogleNewsScraper(config.sources.google_news, AsyncMock()), GoogleNewsScraper)


def test_verified_design_and_creator_rss_sources_are_configured():
    sources = {
        source["url"]: {"category": source["category"], "profile": source["profile"]}
        for source in load_config()["sources"]["rss"]
    }
    assert {
        "https://www.nngroup.com/feed/rss/": {
            "category": "designer-growth",
            "profile": "ai-blogger-growth",
        },
        "https://www.designboom.com/feed/": {
            "category": "design-brand",
            "profile": "auto",
        },
        "https://www.creativeboom.com/feed/": {
            "category": "design-brand",
            "profile": "auto",
        },
        "https://www.ycombinator.com/blog/rss": {
            "category": "creator-business",
            "profile": "auto",
        },
    }.items() <= sources.items()


def test_profiles_have_expected_contract():
    for profile_id in PROFILE_IDS:
        folder = ROOT / "profiles" / profile_id
        manifest = json.loads((folder / "profile.json").read_text(encoding="utf-8"))
        assert manifest["id"] == profile_id
        assert manifest["display_names"]["zh"] == EXPECTED_PROFILES[profile_id]
        assert manifest["match"] == "match.md"
        assert manifest["analysis"] == "analysis.md"
        assert manifest["enrichment"]["prompt"] == "enrichment.md"
        assert manifest["enrichment"]["blocks"] == REQUIRED_BLOCKS
        assert (folder / "match.md").read_text(encoding="utf-8").strip()
        assert "0-2" in (folder / "analysis.md").read_text(encoding="utf-8")
        enrichment = (folder / "enrichment.md").read_text(encoding="utf-8")
        assert "事实与判断必须分开" in enrichment
        assert "不得编造" in enrichment
        assert "20–40 分钟" in enrichment
        for heading in EVIDENCE_HEADINGS:
            assert heading in enrichment


def test_daily_workflow_is_enabled_and_minimal():
    text = (ROOT / ".github" / "workflows" / "daily-summary.yml").read_text(encoding="utf-8")
    assert "0 11 * * *" in text
    assert "DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}" in text
    assert "OPENAI_API_KEY" not in text
    assert "prepare_creator_brief.py" in text


def test_daily_workflow_validates_the_canonical_chinese_post():
    workflow = ROOT / ".github" / "workflows" / "daily-summary.yml"
    text = workflow.read_text(encoding="utf-8")
    assert 'post="docs/_posts/$DATE-summary-zh.md"' in text
    assert 'test -f "$post"' in text
    assert "growth_matches=$(grep -c '^## 今日成长行动[[:space:]]*$' \"$post\" || true)" in text
    assert 'test "$growth_matches" -eq 1' in text
    assert "matches=$(grep -c '^## 今日优先创作与实践 Top 3[[:space:]]*$' \"$post\" || true)" in text
    assert 'test "$matches" -eq 1' in text


def test_active_gh_pages_workflows_share_a_serialized_deploy_contract():
    workflows = {
        "daily": (ROOT / ".github" / "workflows" / "daily-summary.yml").read_text(
            encoding="utf-8"
        ),
        "docs": (ROOT / ".github" / "workflows" / "deploy-docs.yml").read_text(
            encoding="utf-8"
        ),
    }
    concurrency = "concurrency:\n  group: gh-pages-deploy\n  cancel-in-progress: false"
    for text in workflows.values():
        assert concurrency in text
        assert text.count("permissions:") == 1
        assert "    permissions:\n      contents: write" in text
        assert "uses: peaceiris/actions-gh-pages@v4" in text
        assert "publish_dir: ./docs" in text
        assert "publish_branch: gh-pages" in text

    daily = workflows["daily"]
    assert "workflow_dispatch:" in daily
    assert daily.index('post="docs/_posts/$DATE-summary-zh.md"') < daily.index(
        "uses: peaceiris/actions-gh-pages@v4"
    )
