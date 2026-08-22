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


def test_out_of_scope_sources_are_disabled():
    sources = load_config()["sources"]
    assert sources["twitter"]["enabled"] is False
    assert sources["telegram"]["enabled"] is False
    assert sources["openbb"]["enabled"] is False
    assert load_config()["email"]["enabled"] is False
    assert load_config()["webhook"]["enabled"] is False


def test_profiles_have_expected_contract():
    for profile_id in PROFILE_IDS:
        folder = ROOT / "profiles" / profile_id
        manifest = json.loads((folder / "profile.json").read_text(encoding="utf-8"))
        assert manifest["id"] == profile_id
        assert manifest["match"] == "match.md"
        assert manifest["analysis"] == "analysis.md"
        assert manifest["enrichment"]["prompt"] == "enrichment.md"
        assert [block["id"] for block in manifest["enrichment"]["blocks"]] == [
            "summary",
            "why_it_matters",
            "creator_angles",
            "community_discussion",
        ]
        assert (folder / "match.md").read_text(encoding="utf-8").strip()
        assert "0-2" in (folder / "analysis.md").read_text(encoding="utf-8")
        assert "creator_angles" in (folder / "enrichment.md").read_text(
            encoding="utf-8"
        )
