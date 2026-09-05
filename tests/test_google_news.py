from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock

import httpx

from src.models import GoogleNewsConfig
from src.scrapers.google_news import GoogleNewsScraper


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _feed(items_xml: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <title>Google News</title>
      {items_xml}
    </channel></rss>
    """


def _item(
    title: str,
    link: str,
    pub: str = "Sat, 27 Jun 2026 12:00:00 GMT",
    source: str | None = "Publisher",
) -> str:
    source_tag = f"<source>{source}</source>" if source is not None else ""
    return f"""
      <item>
        <title>{title}</title>
        <link>{link}</link>
        <guid>{link}</guid>
        <pubDate>{pub}</pubDate>
        <description>Summary text</description>
        {source_tag}
      </item>
    """


def _mock_client(text: str) -> AsyncMock:
    client = AsyncMock()
    feed_response = MagicMock()
    feed_response.text = text
    feed_response.raise_for_status.return_value = None

    async def get(url: str, **_kwargs: object) -> MagicMock:
        if url == GoogleNewsScraper.BASE_URL:
            return feed_response
        response = MagicMock()
        response.url = url
        return response

    client.get.side_effect = get
    return client


def _mock_client_with_redirect(
    feed_text: str, link: str, resolved_url: str | Exception
) -> AsyncMock:
    return _mock_client_with_redirects(feed_text, {link: resolved_url})


def _mock_client_with_redirects(
    feed_text: str, resolutions: dict[str, str | Exception]
) -> AsyncMock:
    client = AsyncMock()
    feed_response = MagicMock()
    feed_response.text = feed_text
    feed_response.raise_for_status.return_value = None

    async def get(url: str, **kwargs: object) -> MagicMock:
        if url == GoogleNewsScraper.BASE_URL:
            assert kwargs["follow_redirects"] is True
            return feed_response
        assert kwargs == {"follow_redirects": True}
        resolved_url = resolutions[url]
        if isinstance(resolved_url, Exception):
            raise resolved_url
        redirect_response = MagicMock()
        redirect_response.url = resolved_url
        return redirect_response

    client.get.side_effect = get
    return client


def test_short_window_uses_when_operator() -> None:
    client = _mock_client(_feed(_item("Foo - Publisher", "https://example.com/a")))
    config = GoogleNewsConfig(enabled=True, query="ai")
    scraper = GoogleNewsScraper(config, client)

    since = _now() - timedelta(hours=24)
    asyncio.run(scraper.fetch(since))

    feed_call = next(
        call for call in client.get.call_args_list if "params" in call.kwargs
    )
    q = feed_call.kwargs["params"]["q"]
    assert "when:" in q
    assert q.endswith("h")
    assert q.startswith("ai ")


def test_long_window_uses_after_operator() -> None:
    client = _mock_client(_feed(_item("Foo - Publisher", "https://example.com/a")))
    config = GoogleNewsConfig(enabled=True, query="ai")
    scraper = GoogleNewsScraper(config, client)

    since = _now() - timedelta(days=30)
    asyncio.run(scraper.fetch(since))

    feed_call = next(
        call for call in client.get.call_args_list if "params" in call.kwargs
    )
    q = feed_call.kwargs["params"]["q"]
    assert "after:" in q
    assert "when:" not in q


def test_ceid_defaults_when_unset() -> None:
    client = _mock_client(_feed(_item("Foo - Publisher", "https://example.com/a")))
    config = GoogleNewsConfig(enabled=True, query="ai", language="en", country="US")
    scraper = GoogleNewsScraper(config, client)

    asyncio.run(scraper.fetch(_now() - timedelta(hours=6)))

    feed_call = next(
        call for call in client.get.call_args_list if "params" in call.kwargs
    )
    params = feed_call.kwargs["params"]
    assert params["ceid"] == "US:en"
    assert params["hl"] == "en"
    assert params["gl"] == "US"


def test_parses_feed_into_content_items() -> None:
    items_xml = _item(
        "Headline One - Publisher",
        "https://example.com/a",
        pub="Sat, 27 Jun 2026 12:00:00 GMT",
    ) + _item(
        "Headline Two - Other",
        "https://example.com/b",
        pub="Sat, 27 Jun 2026 13:00:00 GMT",
        source="Other",
    )
    client = _mock_client(_feed(items_xml))
    config = GoogleNewsConfig(
        enabled=True, query="ai", profile="google-news-profile"
    )
    scraper = GoogleNewsScraper(config, client)

    items = asyncio.run(scraper.fetch(_now() - timedelta(days=365)))

    assert len(items) == 2
    first = items[0]
    assert first.title == "Headline One - Publisher"
    assert str(first.url) == "https://example.com/a"
    assert first.published_at == datetime(2026, 6, 27, 12, 0, 0, tzinfo=timezone.utc)
    assert first.id.startswith("google_news:article:")
    assert first.metadata["gn_query"] == "ai"
    assert first.metadata["source_name"] == "Publisher"
    assert first.profile == "google-news-profile"


def test_disabled_config_returns_empty() -> None:
    client = _mock_client(_feed(_item("Foo", "https://example.com/a")))
    config = GoogleNewsConfig(enabled=False, query="ai")
    scraper = GoogleNewsScraper(config, client)

    assert asyncio.run(scraper.fetch(_now())) == []


def test_empty_query_returns_empty() -> None:
    client = _mock_client(_feed(_item("Foo", "https://example.com/a")))
    config = GoogleNewsConfig(enabled=True, query="   ")
    scraper = GoogleNewsScraper(config, client)

    assert asyncio.run(scraper.fetch(_now())) == []


def test_http_error_returns_empty() -> None:
    client = AsyncMock()
    client.get.side_effect = httpx.HTTPError("boom")
    config = GoogleNewsConfig(enabled=True, query="ai")
    scraper = GoogleNewsScraper(config, client)

    assert asyncio.run(scraper.fetch(_now())) == []


def test_empty_feed_returns_empty() -> None:
    client = _mock_client(_feed(""))
    config = GoogleNewsConfig(enabled=True, query="ai")
    scraper = GoogleNewsScraper(config, client)

    assert asyncio.run(scraper.fetch(_now())) == []


def test_entry_missing_link_or_title_is_skipped() -> None:
    items_xml = (
        _item("", "https://example.com/no-title")  # missing title
        + "<item><title>No link</title><pubDate>Sat, 27 Jun 2026 12:00:00 GMT</pubDate></item>"
        + _item("Good - Publisher", "https://example.com/good")
    )
    client = _mock_client(_feed(items_xml))
    config = GoogleNewsConfig(enabled=True, query="ai")
    scraper = GoogleNewsScraper(config, client)

    items = asyncio.run(scraper.fetch(_now() - timedelta(days=365)))

    assert len(items) == 1
    assert str(items[0].url) == "https://example.com/good"


def test_max_results_cap() -> None:
    items_xml = "".join(
        _item(f"Item {i} - Pub", f"https://example.com/{i}") for i in range(5)
    )
    client = _mock_client(_feed(items_xml))
    config = GoogleNewsConfig(enabled=True, query="ai", max_results=2)
    scraper = GoogleNewsScraper(config, client)

    items = asyncio.run(scraper.fetch(_now() - timedelta(days=365)))

    assert len(items) == 2


def test_google_news_resolves_redirect_to_publisher_url() -> None:
    link = "https://news.google.com/rss/articles/x"
    publisher_url = "https://publisher.example/story"
    client = _mock_client_with_redirect(
        _feed(_item("Headline - Publisher", link)), link, publisher_url
    )
    config = GoogleNewsConfig(enabled=True, query="ai")

    items = asyncio.run(GoogleNewsScraper(config, client).fetch(_now()))

    assert len(items) == 1
    assert str(items[0].url) == publisher_url
    assert items[0].metadata["source_name"] == "Publisher"
    assert client.get.call_args_list[-1].kwargs == {"follow_redirects": True}


def test_google_news_skips_unresolved_google_redirect() -> None:
    link = "https://news.google.com/rss/articles/x"
    client = _mock_client_with_redirect(
        _feed(_item("Headline - Publisher", link)), link, link
    )
    config = GoogleNewsConfig(enabled=True, query="ai")

    assert asyncio.run(GoogleNewsScraper(config, client).fetch(_now())) == []


def test_google_news_skips_trailing_dot_google_redirect() -> None:
    link = "https://news.google.com/rss/articles/x"
    client = _mock_client_with_redirect(
        _feed(_item("Headline - Publisher", link)), link, "https://news.google.com./rss/articles/x"
    )
    config = GoogleNewsConfig(enabled=True, query="ai")

    assert asyncio.run(GoogleNewsScraper(config, client).fetch(_now())) == []


def test_google_news_skips_non_https_publisher_url() -> None:
    link = "https://news.google.com/rss/articles/x"
    client = _mock_client_with_redirect(
        _feed(_item("Headline - Publisher", link)), link, "http://publisher.example/story"
    )
    config = GoogleNewsConfig(enabled=True, query="ai")

    assert asyncio.run(GoogleNewsScraper(config, client).fetch(_now())) == []


def test_google_news_skips_failed_entry_and_keeps_later_publisher() -> None:
    failed_link = "https://news.google.com/rss/articles/fail"
    good_link = "https://news.google.com/rss/articles/good"
    client = _mock_client_with_redirects(
        _feed(
            _item("Failed - Publisher", failed_link)
            + _item("Good - Publisher", good_link)
        ),
        {
            failed_link: httpx.HTTPError("resolution failed"),
            good_link: "https://publisher.example/story",
        },
    )
    config = GoogleNewsConfig(enabled=True, query="ai")

    items = asyncio.run(GoogleNewsScraper(config, client).fetch(_now()))

    assert [str(item.url) for item in items] == ["https://publisher.example/story"]


def test_google_news_skips_redirect_loop_without_aborting() -> None:
    loop_link = "https://news.google.com/rss/articles/loop"
    good_link = "https://news.google.com/rss/articles/good"
    client = _mock_client_with_redirects(
        _feed(_item("Loop - Publisher", loop_link) + _item("Good - Publisher", good_link)),
        {
            loop_link: httpx.TooManyRedirects("redirect loop"),
            good_link: "https://publisher.example/story",
        },
    )
    config = GoogleNewsConfig(enabled=True, query="ai")

    items = asyncio.run(GoogleNewsScraper(config, client).fetch(_now()))

    assert [str(item.url) for item in items] == ["https://publisher.example/story"]
