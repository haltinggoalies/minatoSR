"""Downloads Prydwen's endgame team data into cache/ for make_recommend.py (Beta 4.7 / PearlSR copy of the 4.6
server's scripts/recommend_teams/fetch_prydwen.py).

    python fetch_prydwen.py

- Pure Fiction / Apocalyptic Shadow: the current rotation's top teams per node, read from the page
  (https://www.prydwen.gg/star-rail/pure-fiction, /apocalyptic-shadow).
- Anomaly Arbitration: one file per season from the analytics API (/api/star-rail/analytics?phaseId=N).
  AA_SEASON_PHASES maps our season (ChallengePeakGroupConfig ID) to Prydwen's phase ID, the last update of that
  season; the script prints the phases Prydwen has, so a new season can be added here.
"""
import html
import json
import os
import re
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'cache')
BASE = 'https://www.prydwen.gg'
# Prydwen answers 403 without a browser user agent.
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36'

# Season 10 (4.6 "Return to Roots") and 11 (4.7) have no Prydwen data yet (2026-10-01: phase IDs above 63 answer
# 404); add "10: <phaseId>" once the page lists a 4.6.x phase, make_recommend.py then uses it instead of game8.
AA_SEASON_PHASES = {4: 8, 5: 16, 6: 28, 7: 43, 8: 55, 9: 63}
STARWARD_PAGES = ['pure-fiction', 'apocalyptic-shadow']


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=60) as rsp:
        return rsp.read().decode('utf-8')


def node_teams(page_html):
    """{'Node 1': [{rank, rate, slugs}], ...} from the page's team usage section."""
    seg = page_html[page_html.find('teams-details'):]
    nodes = {}
    for m in re.finditer(r'<h5>([^<]{1,40})</h5>(.*?)(?=<h5>|$)', seg, re.S):
        if not m.group(1).startswith('Node'):
            continue
        teams = []
        row_re = (r'<p class="rank">Rank <!-- -->(\d+)</p><p class="usage">App\. rate: <!-- -->([\d.]+)<!-- -->%</p>'
                  r'(.*?)(?=<div class="team-row">|$)')
        for row in re.finditer(row_re, m.group(2), re.S):
            slugs = re.findall(r'<a href="/star-rail/characters/([^"]+)"><div class="avatar', row.group(3))[:4]
            teams.append({'rank': int(row.group(1)), 'rate': float(row.group(2)), 'slugs': slugs})
        nodes.setdefault(m.group(1), teams)
    title = re.search(r'Team usage \(([^)]+)\)', html.unescape(page_html))
    return {'rotation': title.group(1) if title else '', 'nodes': nodes}


def main():
    os.makedirs(os.path.join(CACHE, 'aa'), exist_ok=True)

    for page in STARWARD_PAGES:
        data = node_teams(get(f'{BASE}/star-rail/{page}'))
        json.dump(data, open(os.path.join(CACHE, f'{page}.json'), 'w', encoding='utf-8'), ensure_ascii=False)
        print(page, data['rotation'], {n: len(t) for n, t in data['nodes'].items()})

    for season, phase_id in AA_SEASON_PHASES.items():
        text = get(f'{BASE}/api/star-rail/analytics?phaseId={phase_id}')
        data = json.loads(text)
        open(os.path.join(CACHE, 'aa', f'season{season}.json'), 'w', encoding='utf-8').write(text)
        print('AA season', season, data['phase']['phase'], data['phase']['displayName'],
              {g: len(t) for g, t in data['teams'].items()})
        time.sleep(1)

    # The phases Prydwen has, for adding a new season to AA_SEASON_PHASES.
    page = get(f'{BASE}/star-rail/anomaly-arbitration')
    for m in re.finditer(r'\\"id\\":(\d+),\\"phase\\":\\"([\d.]+)\\",\\"displayPhase\\":\\"([^\\]+)\\"', page):
        print('  Prydwen AA phase', m.group(1), m.group(2), m.group(3))

    # Phase IDs count up across all modes (MoC/PF/AS/AA); also ask the API for the ones after our last season, in
    # case the page has not listed them yet.
    for phase_id in range(max(AA_SEASON_PHASES.values()) + 1, max(AA_SEASON_PHASES.values()) + 17):
        try:
            phase = json.loads(get(f'{BASE}/api/star-rail/analytics?phaseId={phase_id}'))['phase']
        except urllib.error.HTTPError:
            continue
        print('  Prydwen phase', phase_id, phase.get('phase'), phase.get('displayName'), phase.get('mode'))
        time.sleep(0.5)


if __name__ == '__main__':
    main()
