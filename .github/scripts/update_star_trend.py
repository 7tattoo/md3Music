#!/usr/bin/env python3
"""通过 GitHub API 获取 Star 数，维护本地历史快照，并生成 README 可显示的 SVG 图表。"""

from __future__ import annotations

import json
import urllib.request
from datetime import date
from pathlib import Path
from xml.sax.saxutils import escape

# ==== 配置 ====
REPO = "zzyoxml/md3Music"
HISTORY = Path("assets/star-history.json")   # 本地历史快照
OUTPUT = Path("assets/star-trend.svg")       # 输出图表
USER_AGENT = "md3music-star-trend-updater/1.0"
MAX_DAYS = 90                                # 只保留最近 90 天
# =============


def fetch_stars() -> int:
    """通过 GitHub API 获取当前 Star 数。"""
    url = f"https://api.github.com/repos/{REPO}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    stars = int(data["stargazers_count"])
    if stars < 0:
        raise RuntimeError(f"无效的 Star 数：{stars}")
    return stars


def load_history() -> list[dict]:
    """加载本地历史快照。"""
    if not HISTORY.exists():
        return []
    try:
        data = json.loads(HISTORY.read_text(encoding="utf-8"))
        if isinstance(data, list):
            return data
    except Exception:
        pass
    return []


def save_history(history: list[dict]) -> None:
    HISTORY.parent.mkdir(parents=True, exist_ok=True)
    HISTORY.write_text(
        json.dumps(history, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )


def update_history(history: list[dict], stars: int) -> list[dict]:
    """把今天的星数追加进去，同一天则覆盖，并裁剪到最近 MAX_DAYS 天。"""
    today = date.today().isoformat()
    history = [p for p in history if p.get("date") != today]
    history.append({"date": today, "stars": stars})
    history.sort(key=lambda p: p["date"])
    return history[-MAX_DAYS:]


def make_svg(points: list[dict]) -> str:
    width, height = 960, 360
    left, right, top, bottom = 72, 28, 52, 70
    plot_width = width - left - right
    plot_height = height - top - bottom

    values = [int(p["stars"]) for p in points]
    low, high = min(values), max(values)
    padding = max(5, (high - low) * 0.08)
    y_min, y_max = max(0, low - padding), high + padding

    def x(index: int) -> float:
        return left if len(points) == 1 else left + index * plot_width / (len(points) - 1)

    def y(value: int) -> float:
        return top + (y_max - value) * plot_height / (y_max - y_min or 1)

    line_points = " ".join(
        f"{x(i):.1f},{y(v):.1f}" for i, v in enumerate(values)
    )
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
  <a href="https://github.com/{REPO}">
    <rect width="{width}" height="{height}" rx="18" fill="#f7faff"/>
    <text x="{left}" y="30" fill="#172b4d" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif" font-size="20" font-weight="700">MD3Music · GitHub Star 趋势</text>
    <text x="{width - right}" y="30" text-anchor="end" fill="#526581" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif" font-size="14">最近 90 天 · {last:,} Stars</text>
    <g fill="none" stroke-width="1">{"".join(grid)}</g>
    <polygon points="{area_points}" fill="#2f80ed" fill-opacity=".12"/>
    <polyline points="{line_points}" fill="none" stroke="#1769e0" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="{x(len(points) - 1):.1f}" cy="{y(last):.1f}" r="5" fill="#1769e0"/>
    <g fill="#526581" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif" font-size="12">{"".join(labels)}</g>
    <text x="{width - right}" y="{height - 8}" text-anchor="end" fill="#8091aa" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif" font-size="11">数据源：GitHub API · 更新 {generated}</text>
  </a>
</svg>
'''


def main() -> None:
    stars = fetch_stars()
    history = load_history()
    history = update_history(history, stars)
    save_history(history)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(make_svg(history), encoding="utf-8", newline="\n")
    print(f"updated {OUTPUT} with {len(history)} snapshots through {history[-1]['date']}, stars={stars}")


if __name__ == "__main__":
    main()