#!/usr/bin/env python3
"""Summarize the paired benchmark using actual provider usage, never schema estimates."""
import argparse
import json
from pathlib import Path
import statistics
from collections import defaultdict


def route_ok(turn):
    names = [c.get('tool') for c in turn['tool_calls']]
    expected = 'mcp.list_tools' if turn['arm'] == 'listing' else 'system.search_tools'
    forbidden = 'system.search_tools' if turn['arm'] == 'listing' else 'mcp.list_tools'
    return forbidden not in names and (turn['turn'] != 0 or expected in names)


def fmt(value):
    return f'{value:,.0f}'.replace(',', ' ')


def summarize(path):
    report = json.loads(path.read_text())
    rows = report['turns']
    sessions = defaultdict(list)
    for row in rows:
        sessions[(row['catalog_size'], row['arm'], row['trial'])].append(row)
    groups = defaultdict(list)
    for (size, arm, trial), turns in sessions.items():
        if len(turns) != 2:
            continue
        groups[(size, arm)].append({
            'trial': trial, 'input': sum(t['prompt_tokens'] for t in turns),
            'output': sum(t['completion_tokens'] for t in turns),
            'cached': sum(t['cached_tokens'] for t in turns),
            'uncached': sum(t['prompt_tokens'] - t['cached_tokens'] for t in turns),
            'requests': sum(t['provider_requests'] for t in turns),
            'seconds': sum(t['wall_seconds'] for t in turns),
            'success': all(t['success'] for t in turns), 'route_ok': all(route_ok(t) for t in turns),
        })
    stats = []
    for (size, arm), runs in sorted(groups.items()):
        row = {'size': size, 'arm': arm, 'workflows': len(runs)}
        for field in ['input', 'output', 'cached', 'uncached', 'requests', 'seconds']:
            row[field + '_median'] = statistics.median(r[field] for r in runs)
            row[field + '_sum'] = sum(r[field] for r in runs)
            row[field + '_mean'] = statistics.mean(r[field] for r in runs)
        row['cached_share'] = row['cached_sum'] / row['input_sum']
        row['successes'] = sum(r['success'] for r in runs)
        row['protocol_compliant'] = sum(r['route_ok'] for r in runs)
        stats.append(row)
    result = {'model': report['model'], 'turns': len(rows), 'successes': sum(t['success'] for t in rows),
              'strategy_compliant_turns': sum(route_ok(t) for t in rows),
              'all_provider_usage_present': all(t['provider_usage_present'] for t in rows),
              'requests': sum(t['provider_requests'] for t in rows), 'groups': stats,
              'workflows': [{'catalog_size': k[0], 'arm': k[1], **r} for k, runs in groups.items() for r in runs]}
    path.with_name('summary.json').write_text(json.dumps(result, indent=2))
    lines = [
        '# Live tool-discovery measurement', '',
        f"Model: `{report['model']}` through Sloppy's existing OpenAI Codex OAuth provider (`chatgpt.com`).",
        f"Started: `{report['started_at']}`. Finished: `{report.get('finished_at', 'in progress')}`.", '',
        f"Verified MCP task outcomes: **{result['successes']}/{result['turns']}**. "
        f"Strategy compliance: **{result['strategy_compliant_turns']}/{result['turns']}**. "
        f"Observed model requests: **{result['requests']}**.", '',
        '## Two-task workflows', '',
        f"Each cell is the arithmetic mean of {report['trials']} paired repetitions (rounded). Each workflow contains a new-session task and a different task in the same conversation. All extra queries remain in these averages; medians and individual workflows are also saved in summary.json.", '',
        '| MCP tools | Strategy | Input tokens | Cache-read tokens | Uncached input | Requests | Wall time |',
        '| ---: | --- | ---: | ---: | ---: | ---: | ---: |',
    ]
    for s in stats:
        lines.append(f"| {s['size']} | {s['arm']} | {fmt(s['input_mean'])} | {fmt(s['cached_mean'])} | {fmt(s['uncached_mean'])} | {s['requests_mean']:.2f} | {s['seconds_mean']:.2f} s |")
    lines += ['', 'Paired input-token changes (search / listing - 1):', '']
    for size in sorted({r['catalog_size'] for r in rows}):
        by = {r['arm']: r for r in stats if r['size'] == size}
        if set(by) != {'listing', 'search'}:
            continue
        delta = by['search']['input_mean'] / by['listing']['input_mean'] - 1
        uncached_delta = by['search']['uncached_mean'] / by['listing']['uncached_mean'] - 1
        seconds_delta = by['search']['seconds_mean'] / by['listing']['seconds_mean'] - 1
        lines.append(f"- {size} tools: input **{delta:+.1%}**, uncached input **{uncached_delta:+.1%}**, wall time **{seconds_delta:+.1%}** (ratios of means).")
    lines += ['', '## Individual tasks', '',
              '| MCP tools | Task position | Strategy | Input, median | Requests, median | Wall time, median |',
              '| ---: | --- | --- | ---: | ---: | ---: |']
    for size in sorted({r['catalog_size'] for r in rows}):
        for position in [0, 1]:
            for arm in ['listing', 'search']:
                selected = [r for r in rows if (r['catalog_size'], r['turn'], r['arm']) == (size, position, arm)]
                if selected:
                    lines.append(f"| {size} | {'first' if position == 0 else 'next, same session'} | {arm} | {fmt(statistics.median(r['prompt_tokens'] for r in selected))} | {statistics.median(r['provider_requests'] for r in selected):g} | {statistics.median(r['wall_seconds'] for r in selected):.2f} s |")
    empty_results = sum(
        1 for turn in rows for event in turn['events']
        if event.get('toolResult', {}).get('tool') == 'system.search_tools'
        and event.get('toolResult', {}).get('data', {}).get('metrics', {}).get('matchedTools') == 0
    )
    lines += ['', '## Observations', '',
        f'- {empty_results} empty targeted-search results required query refinement; these attempts are included in the totals.',
        '- Query refinement costs are visible in the raw tool-call arguments and every extra model request remains in the averages.',
        '- Compare input, cached input, request counts and latency separately. Fewer tokens do not guarantee lower wall time when discovery adds model rounds.',
        '- Listing can reuse all returned schemas on a later task; targeted search may need to acquire another schema. The second-task measurements include this difference.',
        '- These results support keeping the discovery strategy conditional on catalog size and workflow. Two catalog sizes do not identify a universal crossover threshold.',
        '', '## Method and limits', '',
        '- Real model inference and the actual built Sloppy Core, `system.search_tools`, `mcp.list_tools`, and `mcp.call_tool`; MCP data itself is synthetic and read-only.',
        '- Catalog sizes 16 and 128; three task families (stock, incident status, artifact digest); three repetitions, two tasks per conversation, both strategies. Arm order alternates across pairs.',
        '- Both arms use the same three native tool definitions and permission scope. This isolates the catalog-acquisition strategy; installation overhead of the extra native search definition is not measured.',
        '- The second task uses a different tool. Listing may reuse all previously returned schemas. Search may need another discovery request. All extra requests and retained context are included.',
        '- MCP connection and metadata discovery are prepared during agent policy setup before timed turns. Server startup is excluded from both arms.',
        '- Token counts come from `usage_requests` populated from provider response usage, not `TokenPressureEstimator`, character counts, or the discovery baseline estimate.',
        '- [OpenAI usage/cache semantics](https://developers.openai.com/api/docs/guides/prompt-caching): cache-read share is summed cached input divided by summed input. The report does not convert subscription usage to dollars. Cache-write counts are not interpreted because the current OAuth usage path does not expose their availability.',
        '- A first task is not guaranteed to be cache-cold; native prompt prefixes can already be cached. The observed cache counts are reported, not an assumed warm/cold state.',
        '- `usage_requests.complete` describes local attribution completeness (including `previous_response_id`); a false value does not mean provider totals are missing. Provider total availability is checked independently.',
        '- Older binaries marked successful Responses requests as failed when `error:null` was present (`UsageWireDecoder.swift`, error-field presence check). This has been fixed for new requests; historical raw flags are retained. Task success here requires a typed, validated MCP receipt with matching target and exact arguments; no model-text success heuristic is used.',
        '- Three repetitions per configuration are exploratory evidence, not a statistically established threshold or a production-wide latency guarantee.',
        '- No user documents, production MCP calls, or changes to the running user Core configuration. The temporary OAuth copy has no refresh token and is deleted when the isolated Core stops.', '',
        'Raw per-request records, calls and session events: [raw-results.json](raw-results.json). Machine-readable aggregates: [summary.json](summary.json).',
    ]
    path.with_name('README.md').write_text('\n'.join(lines) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    summarize(parser.parse_args().results)
