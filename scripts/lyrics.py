#!/usr/bin/env python3
import os
import re
import json
import sys
import socket

MPD_HOST = os.environ.get('MPD_HOST', 'localhost')
MPD_PORT = int(os.environ.get('MPD_PORT', '6600'))


def mpd_command(commands):
    """Execute a list of commands against MPD over a raw socket."""
    try:
        with socket.create_connection((MPD_HOST, MPD_PORT), timeout=1) as sock:
            f = sock.makefile('rwb')
            greeting = f.readline()
            if not greeting.startswith(b'OK MPD'):
                return []
            
            if len(commands) == 1:
                f.write(commands[0].encode('utf-8') + b'\n')
            else:
                f.write(b'command_list_begin\n')
                for cmd in commands:
                    f.write(cmd.encode('utf-8') + b'\n')
                f.write(b'command_list_end\n')
            f.flush()

            lines = []
            while True:
                line = f.readline()
                if not line:
                    break
                text = line.decode('utf-8', errors='ignore').rstrip('\r\n')
                if text.startswith('OK') or text.startswith('ACK'):
                    break
                lines.append(text)
            return lines
    except OSError:
        return []


def get_music_dir():
    """Retrieve music directory from mpd.conf or fallback to standard path."""
    mpd_conf = os.path.expanduser('~/.config/mpd/mpd.conf')
    if os.path.isfile(mpd_conf):
        try:
            with open(mpd_conf, 'r', encoding='utf-8') as f:
                for line in f:
                    line_str = line.strip()
                    if line_str.startswith('music_directory'):
                        m = re.search(r'\"([^\"]+)\"', line_str)
                        if m:
                            return os.path.expanduser(m.group(1))
        except Exception:
            pass
    
    fallback = os.path.expanduser('~/Music/susamn-music-collection')
    if os.path.isdir(fallback):
        return fallback
    return os.path.expanduser('~/Music')


def get_mpd_info():
    """Query current MPD status and current song."""
    raw_lines = mpd_command(['status', 'currentsong'])
    fields = {}
    for line in raw_lines:
        key, sep, value = line.partition(':')
        if sep:
            fields[key.strip()] = value.strip()

    state = fields.get('state', 'stop')
    if state not in ('play', 'pause'):
        return 'stopped', 0.0, 0.0, '', '', ''

    try:
        elapsed = float(fields.get('elapsed', 0.0) or 0.0)
    except ValueError:
        elapsed = 0.0

    try:
        duration = float(fields.get('duration', 0.0) or 0.0)
    except ValueError:
        duration = 0.0

    file_rel = fields.get('file', '')
    title = fields.get('Title', '')
    artist = fields.get('Artist', '')
    if not title and file_rel:
        title = os.path.splitext(os.path.basename(file_rel))[0]

    return ('playing' if state == 'play' else 'paused'), elapsed, duration, file_rel, title, artist


def parse_lrc(filepath):
    """Parse .lrc file into sorted [{ 'time': float, 'text': str }] array."""
    lines = []
    tag_re = re.compile(r'\[(\d+):(\d+(?:\.\d+)?)\]')
    offset_re = re.compile(r'\[offset:\s*([+-]?\d+)\]', re.IGNORECASE)
    offset_ms = 0.0

    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue
                
                # Check for global offset tag [offset:+/-ms]
                offset_match = offset_re.match(line)
                if offset_match:
                    try:
                        offset_ms = float(offset_match.group(1))
                    except ValueError:
                        pass
                    continue

                tags = tag_re.findall(line)
                if not tags:
                    continue

                text = tag_re.sub('', line).strip()
                for mm, ss in tags:
                    try:
                        t = float(mm) * 60.0 + float(ss) + (offset_ms / 1000.0)
                        if t < 0:
                            t = 0.0
                        lines.append({'time': round(t, 2), 'text': text})
                    except ValueError:
                        continue
    except Exception:
        return []

    lines.sort(key=lambda x: x['time'])
    return lines


def parse_txt(filepath):
    """Parse .txt file into a list of line strings."""
    lines = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for raw_line in f:
                lines.append(raw_line.rstrip('\r\n'))
    except Exception:
        return []
    return lines


def resolve_lyrics(file_rel, music_dir):
    """Check for same-name .lrc or .txt in the song directory."""
    if not file_rel:
        return 'none', []

    full_path = os.path.join(music_dir, file_rel)
    stem, _ = os.path.splitext(full_path)

    lrc_path = stem + '.lrc'
    if os.path.isfile(lrc_path):
        lrc_lines = parse_lrc(lrc_path)
        if lrc_lines:
            return 'synced', lrc_lines

    txt_path = stem + '.txt'
    if os.path.isfile(txt_path):
        txt_lines = parse_txt(txt_path)
        if txt_lines:
            return 'plain', txt_lines

    return 'none', []


def handle_seek(target_sec):
    """Seek current song to target_sec."""
    try:
        sec = float(target_sec)
        mpd_command([f'seekcur {sec}'])
    except ValueError:
        pass


def main():
    if len(sys.argv) > 2 and sys.argv[1] == 'seek':
        handle_seek(sys.argv[2])
        sys.exit(0)

    state, elapsed, duration, file_rel, title, artist = get_mpd_info()

    if state == 'stopped' or not file_rel:
        print(json.dumps({
            'state': 'stopped',
            'title': title or '',
            'artist': artist or '',
            'type': 'none',
            'elapsed': 0.0,
            'duration': 0.0,
            'lines': []
        }))
        sys.exit(0)

    music_dir = get_music_dir()
    lyrics_type, lines = resolve_lyrics(file_rel, music_dir)

    print(json.dumps({
        'state': state,
        'title': title,
        'artist': artist,
        'file': file_rel,
        'type': lyrics_type,
        'elapsed': elapsed,
        'duration': duration,
        'lines': lines
    }, ensure_ascii=False))


if __name__ == '__main__':
    main()

