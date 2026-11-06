#!/usr/bin/env python3
"""Replace captures and CoreText headers in finished screenshot frames."""
from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

from common import config, destinations, erase_header, header_job, headline, paste_screen, raw_path, read_json, source


def extra_job(frame: dict, extra: dict, text: str, locale: str) -> dict:
    x, y, width, height = extra['box']
    return {
        'text': text,
        'locale': locale,
        'font': extra['font'],
        'color': extra['color'],
        'box': [width, height],
        'maxSize': extra.get('max_size', round(height * 0.82)),
        'minSize': extra.get('min_size', 1),
        'align': extra.get('align', 'center'),
    }


def fill_extra(canvas: Image.Image, extra: dict) -> None:
    color = extra.get('fill_color')
    if color is None:
        return
    x, y, width, height = extra['box']
    radius = extra.get('fill_radius', height / 2)
    ImageDraw.Draw(canvas).rounded_rectangle(
        (x, y, x + width - 1, y + height - 1), radius=radius, fill=tuple(color)
    )


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--raw-root', type=Path, required=True)
    p.add_argument('--headers', type=Path, required=True)
    p.add_argument('--locale', required=True)
    p.add_argument('--out', type=Path, required=True, help='output root; writes ROOT/LOCALE/SET/file.png')
    p.add_argument('--set', dest='set_key')
    args = p.parse_args()
    data, headers = config(args.config), read_json(args.headers)[args.locale]
    sets = data['sets'] if args.set_key is None else {args.set_key: data['sets'][args.set_key]}
    plans = []
    for key, group in sets.items():
        frames = group['frames']
        jobs = [header_job(f, headers[f['file']], args.locale) for f in frames]
        results = headline(jobs)
        size = min(r['size'] for r in results)
        cause = frames[min(range(len(results)), key=lambda i: results[i]['size'])]
        for f, result in zip(frames, results):
            if not result['fits'] or size < f['min_size']:
                raise ValueError(f"{key}/{cause['file']}: size {size:g} below required minimum; text={headers[cause['file']]!r}")
            for target in destinations(f):
                if not raw_path(args.raw_root, args.locale, key, target['raw']).is_file():
                    raise ValueError(f"missing raw {key}/{target['raw']}")
        extras_by_file = {}
        for frame in frames:
            extras = []
            for extra in frame.get('extra_text', []):
                text_key = f"{frame['file']}#{extra['key']}"
                if not headers.get(text_key, '').strip():
                    raise ValueError(f"missing extra text {args.locale}/{text_key}")
                job = extra_job(frame, extra, headers[text_key], args.locale)
                result = headline([job])[0]
                if not result['fits'] or result['size'] < job['minSize']:
                    raise ValueError(f"{text_key}: text does not fit its box; text={headers[text_key]!r}")
                extras.append((extra, job))
            extras_by_file[frame['file']] = extras
        plans.append((key, group, jobs, size, extras_by_file))
    with tempfile.TemporaryDirectory() as tmp:
        for key, group, jobs, size, extras_by_file in plans:
            frames = group['frames']
            for i, job in enumerate(jobs):
                job.update(size=size, out=str(Path(tmp) / f'header-{key}-{i}.png'))
            extras = []
            for i, frame in enumerate(frames):
                for j, (extra, job) in enumerate(extras_by_file[frame['file']]):
                    job['out'] = str(Path(tmp) / f'extra-{key}-{i}-{j}.png')
                    extras.append(job)
            rendered = headline(jobs + extras)
            if not all(r['fits'] for r in rendered):
                raise ValueError(f'{key}: header or extra text does not fit')
            output = args.out / args.locale / key
            output.mkdir(parents=True, exist_ok=True)
            for frame, job in zip(frames, jobs):
                with Image.open(source(data, frame['base'])) as im:
                    canvas = im.convert('RGB')
                if canvas.size != tuple(group['canvas']):
                    raise ValueError(f"{frame['file']}: base size differs from canvas")
                plate = None
                if frame.get('plate'):
                    with Image.open(source(data, frame['plate'])) as im:
                        plate = im.convert('RGB')
                erase_header(canvas, frame['header_box'], plate)
                for target in destinations(frame):
                    with Image.open(raw_path(args.raw_root, args.locale, key, target['raw'])) as raw:
                        paste_screen(canvas, raw, target['rect'], target.get('radius', 0))
                for extra, extra_render in extras_by_file[frame['file']]:
                    fill_extra(canvas, extra)
                with Image.open(job['out']) as overlay:
                    canvas.paste(overlay, tuple(frame['header_box'][:2]), overlay)
                for extra, extra_render in extras_by_file[frame['file']]:
                    with Image.open(extra_render['out']) as overlay:
                        canvas.paste(overlay, tuple(extra['box'][:2]), overlay)
                canvas.save(output / frame['file'], format='PNG', optimize=True)
            print(f'{args.locale}/{key}: {len(frames)} frames size={size:g}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(f'reskin: {error}', file=sys.stderr)
        sys.exit(1)
