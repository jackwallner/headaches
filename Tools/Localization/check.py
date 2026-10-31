#!/usr/bin/env python3
"""Checks the shared string catalogs against the Swift source.

Run from the repo root: python3 Tools/Localization/check.py

Fails (exit 1) when
  * a localizable literal in the source has no catalog key,
  * a catalog key is missing a language, or
  * a translation's format specifiers do not match its key.

Literals count as localizable when they are the first argument of a SwiftUI
text API (Text, Button, Label, Section, navigationTitle, alert, ...) or of
String(localized:). Interpolations are compared loosely (%@ and %lld match
each other), because the type of an interpolated expression is not visible
without the compiler.
"""
import json
import os
import plistlib
import re
import sys

ROOT = os.getcwd()
DIRS = ['HeadacheLogger', 'HeadacheLoggerWidget', 'HeadacheLoggerWatch', 'SharedHeadache', 'HeadacheLoggerTests']
CATALOGS = ['SharedHeadache/Localizable.xcstrings', 'HeadacheLogger/InfoPlist.xcstrings']
LANGS = ['de', 'ja', 'es', 'it', 'pl', 'hu', 'fi', 'nb', 'da', 'ru', 'pt-PT', 'uk', 'fr']
INTEGER_INTERPOLATIONS = {
    'count', 'rawValue', 'savingsPercent', 'result.imported', 'result.overwritten',
    'result.skipped', 'result.errors', 'signal.totalDays', 'signal.headacheConditionDays',
    'signal.conditionDays', 'currentStep + 1', 'HeadacheQuizQuestions.all.count',
    'InsightsEngine.minimumSampleSize', 'ProactiveAlertsEngine.personalSignalMinimumSampleSize',
    'filteredEvents.count', 'events.count', 'best.conditionDays', 'prefs.airQualityThreshold',
    'one', 'few', 'many', 'code', 'hours', 'subset', 'ratePct', 'overallPct', 'pct', 'share',
}
UI_FUNCS = {'Text', 'Button', 'Label', 'Section', 'Toggle', 'TextField', 'navigationTitle', 'accessibilityLabel',
            'alert', 'DatePicker', 'Stepper', 'Link', 'configurationDisplayName', 'description', 'eyebrow',
            'confirmationDialog', 'Picker', 'LocalizedStringKey', 'accessibilityHint', 'SecureField',
            'LocalizedStringResource', 'IntentDescription', 'IntentDialog'}
IGNORED = {'0'}


def parse_literal(src, i):
    """src[i] == '"'. Returns (end_index_after, segments) where segments are ('lit', str) or ('interp', expr)."""
    assert src[i] == '"'
    if src.startswith('"""', i):
        j = src.index('"""', i + 3)
        return j + 3, None
    i += 1
    segs = []; buf = ''
    while True:
        c = src[i]
        if c == '"':
            if buf: segs.append(('lit', buf))
            return i + 1, segs
        if c == '\\':
            n = src[i + 1]
            if n == '(':
                if buf: segs.append(('lit', buf)); buf = ''
                depth = 1; j = i + 2; expr = ''
                while depth:
                    ch = src[j]
                    if ch == '"':
                        k, _ = parse_literal(src, j)
                        expr += src[j:k]; j = k; continue
                    if ch == '(': depth += 1
                    elif ch == ')':
                        depth -= 1
                        if depth == 0: break
                    expr += ch; j += 1
                segs.append(('interp', expr.strip()))
                i = j + 1; continue
            if n == 'u':
                j = src.index('}', i)
                buf += chr(int(src[i + 3:j], 16)); i = j + 1; continue
            escapes = {'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f', '"': '"', '\\': '\\', "'": "'", '0': '\0'}
            if n == 'u':
                j = src.index('}', i)
                buf += chr(int(src[i + 3:j], 16)); i = j + 1; continue
            buf += escapes.get(n, n)
            i += 2; continue
        buf += c; i += 1

def scan(path):
    src = open(path).read()
    out = []
    stack = []  # (funcname, argtext_since_last_comma, argindex)
    i = 0; n = len(src)
    line = 1
    while i < n:
        c = src[i]
        if c == '\n': line += 1
        if src.startswith('//', i):
            j = src.find('\n', i); i = n if j < 0 else j; continue
        if src.startswith('/*', i):
            j = src.index('*/', i); line += src[i:j].count('\n'); i = j + 2; continue
        if c == '"':
            end, segs = parse_literal(src, i)
            if segs is not None and stack:
                fn, argtxt, idx = stack[-1]
                ctx = None
                if fn == 'String' and argtxt.strip().startswith('localized:'):
                    ctx = 'String'
                elif fn in UI_FUNCS and idx == 0 and not re.match(r'\s*[a-zA-Z_]+\s*:', argtxt):
                    ctx = fn
                elif fn in UI_FUNCS and idx == 0 and re.match(r'\s*titleKey\s*:', argtxt):
                    ctx = fn
                if ctx:
                    out.append((line, ctx, segs))
            line += src[i:end].count('\n')
            if stack:
                f, a, k = stack[-1]; stack[-1] = (f, a + src[i:end], k)
            i = end; continue
        if c == '(':
            m = re.search(r'([A-Za-z_][A-Za-z_0-9]*)\s*$', src[max(0, i - 60):i])
            stack.append((m.group(1) if m else '', '', 0)); i += 1; continue
        if c == ')':
            if stack: stack.pop()
            i += 1; continue
        if c == ',' and stack:
            f, a, k = stack[-1]; stack[-1] = (f, '', k + 1); i += 1; continue
        if stack:
            f, a, k = stack[-1]; stack[-1] = (f, a + c, k)
        i += 1
    return out


def source_key(segments):
    has_interpolation = any(kind == 'interp' for kind, _ in segments)
    pieces = []
    for kind, value in segments:
        if kind == 'lit':
            pieces.append(value.replace('%', '%%') if has_interpolation else value)
        else:
            pieces.append('%lld' if value.strip() in INTEGER_INTERPOLATIONS else '%@')
    return ''.join(pieces)


def loose(key):
    return re.sub(r'%(\d+\$)?(lld|@)', '%*', key)


def specs(value, subs=None):
    found = []
    auto = 0
    for m in re.finditer(r'%(?:(\d+)\$)?(lld|@|%)|%#@(\w+)@', value):
        if m.group(2) == '%':
            continue
        if m.group(3):
            found.append((subs[m.group(3)]['argNum'], 'lld'))
            continue
        if m.group(1):
            pos = int(m.group(1))
        else:
            auto += 1
            pos = auto
        found.append((pos, m.group(2)))
    return sorted(set(found))


def main():
    problems = []
    catalogs = {}
    for catalog_path in CATALOGS:
        catalogs[catalog_path] = json.load(open(os.path.join(ROOT, catalog_path)))['strings']

    source_catalog = catalogs['SharedHeadache/Localizable.xcstrings']
    for directory in DIRS:
        for dirpath, _, files in os.walk(os.path.join(ROOT, directory)):
            for name in files:
                if not name.endswith('.swift'):
                    continue
                path = os.path.join(dirpath, name)
                for line, _, segs in scan(path):
                    key = source_key(segs)
                    if key.strip() and key not in IGNORED and key not in source_catalog:
                        problems.append(f'{os.path.relpath(path, ROOT)}:{line}: no exact catalog key for "{key}"')

    key_count = 0
    for catalog_path, catalog in catalogs.items():
        key_count += len(catalog)
        for key, entry in catalog.items():
            localizations = entry.get('localizations', {})
            for language in ['en'] + LANGS:
                localization = localizations.get(language)
                if localization is None:
                    problems.append(f'"{key}" [{language}]: missing language in {catalog_path}')
                    continue
                want = specs(key)
                value = localization.get('stringUnit', {}).get('value', '')
                substitutions = localization.get('substitutions', {})
                if specs(value, substitutions) != want:
                    problems.append(f'"{key}" [{language}]: format specifiers differ in "{value}"')
                for substitution in substitutions.values():
                    plural = substitution.get('variations', {}).get('plural', {})
                    if not plural:
                        continue
                    required = {'other'} if language == 'ja' else {'one', 'other'}
                    if language in {'ru', 'uk', 'pl'}:
                        required |= {'few', 'many'}
                    missing = required - set(plural)
                    if missing:
                        problems.append(f'"{key}" [{language}]: missing plural categories {sorted(missing)}')
                    for category, form in plural.items():
                        plural_value = form.get('stringUnit', {}).get('value', '')
                        if '%arg' not in plural_value:
                            problems.append(f'"{key}" [{language}]: plural form {category} is missing its count')

    with open(os.path.join(ROOT, 'HeadacheLogger/Info.plist'), 'rb') as source_plist:
        info_values = plistlib.load(source_plist)
    info_catalog = catalogs['HeadacheLogger/InfoPlist.xcstrings']
    for key in ('NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription',
                'NSLocationWhenInUseUsageDescription', 'NSMotionUsageDescription'):
        if key not in info_catalog:
            problems.append(f'InfoPlist.xcstrings is missing {key}')
            continue
        english = info_catalog[key].get('localizations', {}).get('en', {}).get('stringUnit', {}).get('value')
        if english != info_values.get(key):
            problems.append(f'InfoPlist.xcstrings English value for {key} differs from Info.plist')

    expected_localizations = set(['en'] + LANGS)
    for plist_path in ('HeadacheLogger/Info.plist', 'HeadacheLoggerWidget/Info.plist',
                       'HeadacheLoggerWatch/Info.plist'):
        with open(os.path.join(ROOT, plist_path), 'rb') as source_plist:
            values = plistlib.load(source_plist)
        missing = expected_localizations - set(values.get('CFBundleLocalizations', []))
        if missing:
            problems.append(f'{plist_path}: CFBundleLocalizations missing {sorted(missing)}')

    for problem in problems:
        print(problem)
    print(f'{key_count} keys, {len(LANGS)} languages, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
