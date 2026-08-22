import json
from pathlib import Path

from src.models import Config


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "data" / "config.github.json"
PROFILE_IDS = [
    "ai-blogger",
    "ai-blogger-tools",
    "ai-blogger-dev",
    "ai-blogger-business",
]


def load_config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def test_cloud_config_is_safe_and_bounded():
    raw = CONFIG.read_text(encoding="utf-8")
    config = json.loads(raw)
    runtime_config = Config.model_validate(config)
    assert "sk-" not in raw
    assert runtime_config.ai.provider.value == "openai"
    assert runtime_config.ai.model == "gpt-5.6-luna"
    assert runtime_config.ai.api_key_env == "OPENAI_API_KEY"
    assert runtime_config.ai.languages == ["zh"]
    assert runtime_config.digest.max_items == 15
    assert runtime_config.processing.default_profile == "ai-blogger"
    assert config["digest"]["profile_order"] == PROFILE_IDS


def test_four_category_limits_total_fifteen():
    groups = load_config()["digest"]["category_groups"]
    assert {key: value["limit"] for key, value in groups.items()} == {
        "models": 4,
        "tools": 4,
        "dev": 4,
        "business": 3,
    }


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
    assert any(
        source["name"] == "Google 新闻（中文 AI）"
        and "hl=zh-CN" in source["url"]
        and "ceid=CN:zh-Hans" in source["url"]
        for source in sources["rss"]
    )
    assert "ArtificialIntelligence" not in {
        subreddit["subreddit"] for subreddit in sources["reddit"]["subreddits"]
    }


def test_profiles_have_expected_contract():
    for profile_id in PROFILE_IDS:
        folder = ROOT / "profiles" / profile_id
        manifest = json.loads((folder / "profile.json").read_text(encoding="utf-8"))
        assert manifest["id"] == profile_id
        assert manifest["match"] == "match.md"
        assert manifest["analysis"] == "analysis.md"
        assert manifest["enrichment"]["prompt"] == "enrichment.md"
        assert manifest["enrichment"]["blocks"] == [
            {
                "id": "summary",
                "type": "section",
                "tools": [],
                "primary": True,
            },
            {
                "id": "why_it_matters",
                "type": "section",
                "tools": ["web_search"],
            },
            {
                "id": "creator_angles",
                "type": "section",
                "tools": [],
            },
            {
                "id": "community_discussion",
                "type": "section",
                "tools": [],
                "optional": True,
            },
        ]
        assert (folder / "match.md").read_text(encoding="utf-8").strip()
        assert "0-2" in (folder / "analysis.md").read_text(encoding="utf-8")
        assert "creator_angles" in (folder / "enrichment.md").read_text(
            encoding="utf-8"
        )


def test_daily_workflow_is_enabled_and_minimal():
    workflow = ROOT / ".github" / "workflows" / "daily-summary.yml"
    text = workflow.read_text(encoding="utf-8")
    assert "0 11 * * *" in text
    assert "OPENAI_API_KEY" in text
    assert "prepare_creator_brief.py" in text
    assert "DEEPSEEK_API_KEY" not in text
    assert "ANTHROPIC_API_KEY" not in text
    assert "HORIZON_WEBHOOK_URL" not in text


def test_daily_workflow_validates_the_canonical_chinese_post():
    workflow = ROOT / ".github" / "workflows" / "daily-summary.yml"
    text = workflow.read_text(encoding="utf-8")
    assert 'post="docs/_posts/$DATE-summary-zh.md"' in text
    assert 'test -f "$post"' in text
    assert "matches=$(grep -c '^## 今日优先选题 Top 3[[:space:]]*$' \"$post\" || true)" in text
    assert 'test "$matches" -eq 1' in text
