#!/usr/bin/env python3
"""从开源榜项目页读取 Star 快照并生成 README 可显示的 SVG 图表。"""

from __future__ import annotations

import html
import json
import re
import urllib.request
from datetime import date
from pathlib import Path
from xml.sax.saxutils import escape


SOURCE_URL = "https://kaiyuanbang.cn/zh-cn/repo/zzyoxml-md3music.html"
OUTPUT = Path("assets/star-trend.svg")
USER_AGENT = "md3music-star-trend-updater/1.0"


def fetch_points() -> list[dict[str, int | str | None]]:
    request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        page = response.read().decode("utf-8")

    match = re.search(
        r'<script[^>]+id="ornav-star-trend-data"[^>]*>(.*?)</script>',
        page,
        re.DOTALL,
    )
    if not match:
        raise RuntimeError("未找到开源榜 Star 趋势数据")

    points = json.loads(html.unescape(match.group(1)))
    if not isinstance(points, list) or not points:
        raise RuntimeError("开源榜 Star 趋势数据为空")

    normalized: list[dict[str, int | str | None]] = []
    for point in points[-90:]:
        point_date = str(point.get("date", ""))
        stars = int(point.get("stars", 0))
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", point_date) or stars < 0:
            raise RuntimeError(f"无效的 Star 趋势数据：{point!r}")
        normalized.append(
            {
                "date": point_date,
                "stars": stars,
                "daily_growth": point.get("daily_growth"),
            }
        )
    return normalized


def make_svg(points: list[dict[str, int | str | None]]) -> str:
    width, height = 960, 360
    left, right, top, bottom = 72, 28, 52, 70
    plot_width = width - left - right
    plot_height = height - top - bottom
    values = [int(point["stars"]) for point in points]
    low, high = min(values), max(values)
    padding = max(5, (high - low) * 0.08)
    y_min, y_max = max(0, low - padding), high + padding

    def x(index: int) -> float:
        return left if len(points) == 1 else left + index * plot_width / (len(points) - 1)

    def y(value: int) -> float:
        return top + (y_max - value) * plot_height / (y_max - y_min or 1)

    line_points = " ".join(f"{x(i):.1f},{y(value):.1f}" for i, value in enumerate(values))
    area_points = (
        f"{left:.1f},{top + plot_height:.1f} {line_points} "
        f"{x(len(points) - 1):.1f},{top + plot_height:.1f}"
    )
    grid = []
    for step in range(5):
        value = y_min + (y_max - y_min) * step / 4
        y_pos = y(int(value))
        grid.append(
            f'<line x1="{left}" y1="{y_pos:.1f}" x2="{width - right}" '
            f'y2="{y_pos:.1f}" stroke="#d9e2f0" stroke-dasharray="4 6"/>'
            f'<text x="{left - 12}" y="{y_pos + 4:.1f}" text-anchor="end">'
            f"{round(value):,}</text>"
        )

    labels = []
    label_step = max(1, (len(points) - 1) // 6)
    for index, point in enumerate(points):
        if index == 0 or index == len(points) - 1 or index % label_step == 0:
            labels.append(
                f'<text x="{x(index):.1f}" y="{height - 28}" text-anchor="middle">'
                f'{escape(str(point["date"])[5:])}</text>'
            )

    first = values[0]
    last = values[-1]
    delta = last - first
    latest_date = str(points[-1]["date"])
    generated = date.today().isoformat()
    delta_text = f"+{delta}" if delta >= 0 else str(delta)

    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
  <title id="title">MD3Music 最近 90 天 GitHub Star 趋势</title>
  <desc id="desc">截至 {latest_date}，当前 {last:,} Stars，90 天首尾变化 {delta_text}。</desc>
  <a href="{SOURCE_URL}">
    <rect width="{width}" height="{height}" rx="18" fill="#f7faff"/>
    <text x="{left}" y="30" fill="#172b4d" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif" font-size="20" font-weight="700">MD3Music · GitHub Star 趋势</text>
    <text x="{width - right}" y="30" text-anchor="end" fill="#526581" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif" font-size="14">最近 90 天 · {last:,} Stars</text>
    <g fill="none" stroke-width="1">{"".join(grid)}</g>
    <polygon points="{area_points}" fill="#2f80ed" fill-opacity=".12"/>
    <polyline points="{line_points}" fill="none" stroke="#1769e0" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="{x(len(points) - 1):.1f}" cy="{y(last):.1f}" r="5" fill="#1769e0"/>
    <g fill="#526581" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif" font-size="12">{"".join(labels)}</g>
    <text x="{width - right}" y="{height - 8}" text-anchor="end" fill="#8091aa" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif" font-size="11">数据源：开源榜 · 更新 {generated}</text>
  </a>
</svg>
'''


def main() -> None:
    points = fetch_points()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(make_svg(points), encoding="utf-8", newline="\n")
    print(f"updated {OUTPUT} with {len(points)} snapshots through {points[-1]['date']}")


if __name__ == "__main__":
    main()
