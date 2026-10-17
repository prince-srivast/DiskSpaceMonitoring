#!/usr/bin/env python3
"""Render CloudWatch dashboard widgets for linked account/Region pairs."""

import argparse
import copy
import json
import re
from pathlib import Path


ACCOUNT_ID = re.compile(r"^[0-9]{12}$")
REGION = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)+$")
MAX_WIDGETS = 500


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", required=True, type=Path, help="JSON file listing linked accounts and Regions")
    parser.add_argument(
        "--template",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "cloudwatch" / "dashboard-template.json",
    )
    parser.add_argument("--output", required=True, type=Path, help="Destination dashboard body JSON")
    args = parser.parse_args()

    sources = json.loads(args.sources.read_text(encoding="utf-8"))
    template = json.loads(args.template.read_text(encoding="utf-8"))
    if not isinstance(sources, list) or not sources:
        parser.error("sources must be a non-empty JSON array")
    if not template.get("widgets") or len(template["widgets"]) < 2:
        parser.error("template must contain an introductory text widget and a metric widget")

    intro = copy.deepcopy(template["widgets"][0])
    metric_template = template["widgets"][1]
    widgets = [intro]
    seen = set()
    for source in sources:
        if not isinstance(source, dict):
            parser.error("each source entry must be an object")
        account_id = source.get("account_id")
        regions = source.get("regions")
        if not isinstance(account_id, str) or not ACCOUNT_ID.fullmatch(account_id):
            parser.error(f"invalid account_id: {account_id!r}")
        if not isinstance(regions, list) or not regions:
            parser.error(f"account {account_id} must have a non-empty regions list")
        for region in regions:
            if not isinstance(region, str) or not REGION.fullmatch(region):
                parser.error(f"invalid Region for account {account_id}: {region!r}")
            key = (account_id, region)
            if key in seen:
                parser.error(f"duplicate account/Region pair: {account_id}/{region}")
            seen.add(key)
            widget = copy.deepcopy(metric_template)
            widget["x"] = 0
            widget["y"] = 2 + 8 * (len(seen) - 1)
            widget["properties"]["accountId"] = account_id
            widget["properties"]["region"] = region
            widget["properties"]["title"] = f"Disk utilization — {account_id} / {region}"
            widgets.append(widget)
            if len(widgets) > MAX_WIDGETS:
                parser.error(
                    f"dashboard exceeds {MAX_WIDGETS} widgets; render separate dashboards for account/Region groups"
                )

    args.output.write_text(json.dumps({"widgets": widgets}, indent=2) + "\n", encoding="utf-8")
    print(f"Rendered {len(seen)} account/Region metric widget(s) to {args.output}")


if __name__ == "__main__":
    main()
