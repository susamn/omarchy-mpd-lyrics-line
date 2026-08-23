#!/usr/bin/env python3
import subprocess, os, re, glob, json, sys

def normalize(s):
    return re.sub(r'[^a-zA-Z0-9]', '', s).lower()

def get_mpd_info():
    try:
        status_out = subprocess.check_output(['mpc', 'status'], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return None, 0.0, '', '', ''

    state = 'stopped'
    if '[playing]' in status_out:
        state = 'playing'
    elif '[paused]' in status_out:
        state = 'paused'
    else:
        return 'stopped', 0.0, '', '', ''

    # Get precise elapsed seconds
    elapsed = 0.0
    time_match = re.search(r'\[(?:playing|paused)\]\s+#\d+/\d+\s+(\d+):(\d+)(?::(\d+))?', status_out)
    if time_match:
        parts = [int(p) for p in time_match.groups() if p is not None]
        if len(parts) == 3:
            elapsed = float(parts[0] * 3600 + parts[1] * 60 + parts[2])
        elif len(parts) == 2:
            elapsed = float(parts[0] * 60 + parts[1])

    try:
        file_rel = subprocess.check_output(['mpc', 'current', '-f', '%file%'], text=True, stderr=subprocess.DEVNULL).strip()
        title = subprocess.check_output(['mpc', 'current', '-f', '%title%'], text=True, stderr=subprocess.DEVNULL).strip()
        artist = subprocess.check_output(['mpc', 'current', '-f', '%artist%'], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        file_rel, title, artist = '', '', ''

    if not title and file_rel:
        title = os.path.splitext(os.path.basename(file_rel))[0]

    return state, elapsed, file_rel, title, artist

def parse_lrc(filepath):
    lines = []
    tag_re = re.compile(r'\[(\d+):(\d+(?:\.\d+)?)\]')
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                tags = tag_re.findall(line)
                if not tags:
                    continue
                text = tag_re.sub('', line).strip()
                for mm, ss in tags:
                    t = float(mm) * 60.0 + float(ss)
                    lines.append((t, text))
    except Exception:
        pass
    lines.sort(key=lambda x: x[0])
    return lines

def find_lrc(file_rel):
    if not file_rel:
        return None

    music_dirs = [
        os.path.expanduser('~/Music'),
        os.path.expanduser('~/Music/music-metadata/lyrics'),
        os.path.expanduser('~/Music/susamn-music-collection')
    ]
    mpd_conf = os.path.expanduser('~/.config/mpd/mpd.conf')
    if os.path.isfile(mpd_conf):
        try:
            with open(mpd_conf, 'r') as f:
                for line in f:
                    if line.strip().startswith('music_directory'):
                        m = re.search(r'\"([^\"]+)\"', line)
                        if m:
                            music_dirs.insert(0, os.path.expanduser(m.group(1)))
        except Exception:
            pass

    base_dir = os.path.dirname(file_rel)
    base_name = os.path.splitext(os.path.basename(file_rel))[0]
    norm_target = normalize(base_name)

    for mdir in music_dirs:
        target_dir = os.path.join(mdir, base_dir)
        if os.path.isdir(target_dir):
            for f in os.listdir(target_dir):
                if f.lower().endswith('.lrc'):
                    if normalize(os.path.splitext(f)[0]) == norm_target:
                        return os.path.join(target_dir, f)
        if os.path.isdir(mdir):
            for f in os.listdir(mdir):
                if f.lower().endswith('.lrc'):
                    if normalize(os.path.splitext(f)[0]) == norm_target:
                        return os.path.join(mdir, f)
    return None

def fallback_mpdtui():
    env = os.environ.copy()
    env["PATH"] = f"/home/linuxbrew/.linuxbrew/bin:{os.path.expanduser('~/.local/bin')}:{os.path.expanduser('~/workspace/tools/mpdtui')}:/usr/local/bin:/usr/bin:/bin:" + env.get("PATH", "")
    try:
        out = subprocess.check_output(['mpdtui', '-lyrics-line'], text=True, stderr=subprocess.DEVNULL, env=env)
        raw = out.splitlines()
        while len(raw) < 4:
            raw.append('')
        # mpdtui gives [above1, current, below1, below2] -> adapt to 5 lines: ["", above1, current, below1, below2]
        return ["", raw[0], raw[1], raw[2], raw[3]]
    except Exception:
        return ["", "", "", "", ""]

state, elapsed, file_rel, title, artist = get_mpd_info()

if not state or state == 'stopped' or not title:
    print(json.dumps({
        'state': 'stopped',
        'title': '',
        'artist': '',
        'lines': ['', '', '', '', ''],
        'hasLyrics': False
    }))
    sys.exit(0)

lrc_path = find_lrc(file_rel)
window = ['', '', '', '', '']
has_lyrics = False

if lrc_path:
    parsed_lines = parse_lrc(lrc_path)
    if parsed_lines:
        idx = -1
        for i, (t, txt) in enumerate(parsed_lines):
            if t <= elapsed:
                idx = i
            else:
                break
        
        # Build 5-line window: [idx-2, idx-1, idx, idx+1, idx+2]
        for slot, offset in enumerate([-2, -1, 0, 1, 2]):
            target_idx = idx + offset
            if 0 <= target_idx < len(parsed_lines):
                window[slot] = parsed_lines[target_idx][1]
            else:
                window[slot] = ''
        
        has_lyrics = any(line != '' for line in window)

if not has_lyrics:
    window = fallback_mpdtui()
    has_lyrics = any(line != '' for line in window)

print(json.dumps({
    'state': state,
    'title': title,
    'artist': artist,
    'lines': window,
    'hasLyrics': has_lyrics
}))
