#!/usr/bin/env python3
"""MCP server wrapping Crawl4AI: URL → clean markdown for LLM consumption."""

import asyncio
from fastmcp import FastMCP

mcp = FastMCP("crawl4ai")


@mcp.tool()
async def fetch_url(url: str, remove_images: bool = True) -> str:
    """Fetch a URL and return clean LLM-optimized markdown. Much cheaper than raw HTML."""
    from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode
    from crawl4ai.content_filter_strategy import PruningContentFilter
    from crawl4ai.markdown_generation_strategy import DefaultMarkdownGenerator

    browser_cfg = BrowserConfig(headless=True, verbose=False)
    md_gen = DefaultMarkdownGenerator(
        content_filter=PruningContentFilter(threshold=0.48, threshold_type="fixed"),
        options={"ignore_links": False, "skip_internal_links": True},
    )
    run_cfg = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        markdown_generator=md_gen,
        exclude_external_images=remove_images,
    )

    async with AsyncWebCrawler(config=browser_cfg) as crawler:
        result = await crawler.arun(url=url, config=run_cfg)

    if not result.success:
        return f"Error fetching {url}: {result.error_message}"

    md = result.markdown.fit_markdown or result.markdown.raw_markdown
    return md.strip()


@mcp.tool()
async def fetch_doc(path: str) -> str:
    """Convert a local PDF/DOCX/PPTX/HTML file to clean markdown using docling."""
    try:
        from docling.document_converter import DocumentConverter
    except ImportError:
        return ("docling не установлен. Переустанови с флагом: bash install.sh --with-docling "
                "(тянет torch, ~2 ГБ).")

    converter = DocumentConverter()
    result = converter.convert(path)
    return result.document.export_to_markdown()


if __name__ == "__main__":
    mcp.run(transport="stdio")
