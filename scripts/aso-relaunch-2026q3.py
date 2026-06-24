#!/usr/bin/env python3
"""2026-Q3 relaunch: migraine into the NAME across all locales, new symptom/diary/log
subtitle, keyword fields re-deduped against the new name+subtitle and backfilled.

Strategy (validated on en-US via Astro):
  Name     = [Headache] & [Migraine] [Tracker]   (migraine promoted to highest-weight field)
  Subtitle = One-tap + Symptom + Diary + Log      (high-pop terms moved out of the keyword field)
  Keywords = preserve each locale's researched terms, drop any now covered by name/subtitle,
             backfill freed slots with validated localized terms (barometric pressure / forecast /
             relief / aura / cluster / tension / trigger / pain / simple / track).

Names/subtitles reuse the native medical vocabulary already present in this repo.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

NAME_LIMIT = 30
SUB_LIMIT = 30
KW_LIMIT = 100

NEW_NAMES: dict[str, str] = {
    "en-US": "Headache & Migraine Tracker",
    "en-GB": "Headache & Migraine Tracker",
    "en-AU": "Headache & Migraine Tracker",
    "en-CA": "Headache & Migraine Tracker",
    "de-DE": "Kopfschmerz & Migräne Tracker",
    "fr-FR": "Suivi Migraine & Céphalées",
    "fr-CA": "Suivi Migraine & Maux de Tête",
    "es-ES": "Registro Migraña y Cefalea",
    "es-MX": "Registro Migraña y Cefalea",
    "ca": "Registre Migranya i Cefalea",
    "it": "Tracker Emicrania e Cefalea",
    "pt-BR": "Rastreador Enxaqueca e Dor",
    "pt-PT": "Registo Enxaqueca e Cefaleia",
    "nl-NL": "Hoofdpijn & Migraine Tracker",
    "pl": "Migrena i Ból Głowy Tracker",
    "sv": "Huvudvärk & Migrän Tracker",
    "da": "Hovedpine & Migræne Tracker",
    "no": "Hodepine & Migrene Tracker",
    "fi": "Päänsärky & Migreeni Seuranta",
    "cs": "Bolest Hlavy a Migréna Tracker",
    "sk": "Bolesť Hlavy a Migréna Tracker",
    "hu": "Fejfájás & Migrén Követő",
    "ro": "Jurnal Migrenă & Durere Cap",
    "hr": "Glavobolja i Migrena Tracker",
    "el": "Πονοκέφαλος & Ημικρανία",
    "tr": "Baş Ağrısı & Migren Takip",
    "ru": "Дневник головной боли, мигрени",
    "uk": "Трекер Мігрені й Болю Голови",
    "ja": "頭痛・片頭痛トラッカー",
    "ko": "두통·편두통 기록기",
    "zh-Hans": "头痛偏头痛追踪记录",
    "zh-Hant": "頭痛偏頭痛追蹤記錄",
    "ar-SA": "متتبع الصداع والشقيقة",
    "he": "מעקב כאב ראש ומיגרנה",
    "hi": "सिरदर्द और माइग्रेन ट्रैकर",
    "th": "ติดตามปวดหัวและไมเกรน",
    "vi": "Nhật ký Đau đầu & Migraine",
    "id": "Pelacak Sakit Kepala Migrain",
    "ms": "Penjejak Sakit Kepala Migrain",
    "bn-BD": "মাথাব্যথা ও মাইগ্রেন ট্র্যাকার",
    "gu-IN": "માથાનો દુખાવો અને માઇગ્રેન",
    "kn-IN": "ತಲೆನೋವು ಮೈಗ್ರೇನ್ ಟ್ರ್ಯಾಕರ್",
    "ml-IN": "തലവേദന മൈഗ്രേൻ ട്രാക്കർ",
    "mr-IN": "डोकेदुखी आणि माइग्रेन ट्रॅकर",
    "or-IN": "ମୁଣ୍ଡବିନାଶ ଓ ମାଇଗ୍ରେନ ଟ୍ରାକର",
    "pa-IN": "ਸਿਰਦਰਦ ਤੇ ਮਾਈਗ੍ਰੇਨ ਟਰੈਕਰ",
    "ta-IN": "தலைவலி மைக்ரேன் ட்ராக்கர்",
    "te-IN": "తలనొప్పి మైగ్రేన్ ట్రాకర్",
    "ur-PK": "سر درد اور مائیگرین ٹریکر",
    "sl-SI": "Sledilnik Glavobola Migrene",
}

NEW_SUBTITLES: dict[str, str] = {
    "en-US": "One Tap Easy Symptom Diary Log",
    "en-GB": "One Tap Easy Symptom Diary Log",
    "en-AU": "One Tap Easy Symptom Diary Log",
    "en-CA": "One Tap Easy Symptom Diary Log",
    "de-DE": "Symptom-Tagebuch, ein Tipp",
    "fr-FR": "Journal symptômes, un geste",
    "fr-CA": "Journal symptômes, un geste",
    "es-ES": "Diario de síntomas, un toque",
    "es-MX": "Diario de síntomas, un toque",
    "ca": "Diari de símptomes, un toc",
    "it": "Diario sintomi con un tocco",
    "pt-BR": "Diário de sintomas num toque",
    "pt-PT": "Diário de sintomas num toque",
    "nl-NL": "Symptomen dagboek, één tik",
    "pl": "Dziennik objawów jednym gestem",
    "sv": "Symtomdagbok med ett tryck",
    "da": "Symptomdagbog med ét tryk",
    "no": "Symptomdagbok med ett trykk",
    "fi": "Oirepäiväkirja, yksi napautus",
    "cs": "Deník příznaků jedním ťukem",
    "sk": "Denník príznakov jedným ťukom",
    "hu": "Tünetnapló egy érintéssel",
    "ro": "Jurnal simptome, o atingere",
    "hr": "Dnevnik simptoma, jedan dodir",
    "el": "Ημερολόγιο συμπτωμάτων",
    "tr": "Tek dokunuşla semptom günlüğü",
    "ru": "Дневник симптомов, 1 касание",
    "uk": "Щоденник симптомів, 1 дотик",
    "ja": "症状を1タップで記録・日記",
    "ko": "증상 원탭 기록·일기",
    "zh-Hans": "一键记录症状日记",
    "zh-Hant": "一鍵記錄症狀日記",
    "ar-SA": "يوميات الأعراض بلمسة واحدة",
    "he": "יומן תסמינים בנגיעה אחת",
    "hi": "एक टैप में लक्षण डायरी",
    "th": "บันทึกอาการแตะเดียว",
    "vi": "Nhật ký triệu chứng một chạm",
    "id": "Catat gejala dengan satu ketuk",
    "ms": "Catat gejala satu ketikan",
    "bn-BD": "এক ট্যাপে উপসর্গ ডায়েরি",
    "gu-IN": "એક ટેપમાં લક્ષણ ડાયરી",
    "kn-IN": "ಒಂದು ಟ್ಯಾಪ್‌ನಲ್ಲಿ ಲಕ್ಷಣ ದಿನಚರಿ",
    "ml-IN": "ഒറ്റ ടാപ്പിൽ ലക്ഷണ ഡയറി",
    "mr-IN": "एका टॅपमध्ये लक्षण डायरी",
    "or-IN": "ଏକ ଟ୍ୟାପରେ ଲକ୍ଷଣ ଡାଇରି",
    "pa-IN": "ਇੱਕ ਟੈਪ ਵਿੱਚ ਲੱਛਣ ਡਾਇਰੀ",
    "ta-IN": "ஒரு தட்டில் அறிகுறி டைரி",
    "te-IN": "ఒక్క ట్యాప్‌లో లక్షణ డైరీ",
    "ur-PK": "ایک ٹیپ میں علامات ڈائری",
    "sl-SI": "Dnevnik simptomov z dotikom",
}

# Explicit keyword fields where auto-dedupe can't be trusted:
#   en-* : keep "track" (auto-dedupe would strip it as a substring of "tracker")
#   CJK  : names have no word boundaries, so substring dedupe can't strip in-name terms
KW_FULL: dict[str, str] = {
    "en-US": "simple,track,pal,buddy,barometric,pressure,cluster,tension,trigger,pain,relief,forecast,chronic,aura",
    "en-GB": "simple,track,pal,buddy,barometric,pressure,cluster,tension,trigger,pain,relief,forecast,chronic,aura",
    "en-AU": "simple,track,pal,buddy,barometric,pressure,cluster,tension,trigger,pain,relief,forecast,chronic,aura",
    "en-CA": "simple,track,pal,buddy,barometric,pressure,cluster,tension,trigger,pain,relief,forecast,chronic,aura",
    "ja": "気圧,天気,予報,緩和,前兆,群発,緊張,トリガー,痛み,簡単,健康,医師",
    "ko": "기압,날씨,예보,완화,전조,군발,긴장,유발,통증,간단,건강,트래커",
    "zh-Hans": "气压,天气,预报,缓解,先兆,丛集,紧张,诱因,疼痛,简单,健康,医生",
    "zh-Hant": "氣壓,天氣,預報,緩解,先兆,叢發,緊張,誘因,疼痛,簡單,健康,醫師",
}

# Validated localized terms to backfill freed keyword slots (priority order, left→right).
# en-* gets the full Astro-validated set incl. English brand terms (pal=Pressure Pal, buddy=Migraine Buddy).
KW_ADDS: dict[str, list[str]] = {
    "en-US": ["simple", "track", "pal", "buddy", "barometric", "pressure", "cluster", "tension", "trigger", "pain", "relief", "forecast", "chronic", "aura"],
    "en-GB": ["simple", "track", "pal", "buddy", "barometric", "pressure", "cluster", "tension", "trigger", "pain", "relief", "forecast", "chronic", "aura"],
    "en-AU": ["simple", "track", "pal", "buddy", "barometric", "pressure", "cluster", "tension", "trigger", "pain", "relief", "forecast", "chronic", "aura"],
    "en-CA": ["simple", "track", "pal", "buddy", "barometric", "pressure", "cluster", "tension", "trigger", "pain", "relief", "forecast", "chronic", "aura"],
    "de-DE": ["luftdruck", "wetter", "vorhersage", "linderung", "aura", "cluster", "spannung", "auslöser", "schmerz", "einfach"],
    "fr-FR": ["pression", "météo", "prévision", "soulagement", "aura", "cluster", "tension", "déclencheur", "douleur", "simple"],
    "fr-CA": ["pression", "météo", "prévision", "soulagement", "aura", "cluster", "tension", "déclencheur", "douleur", "simple"],
    "es-ES": ["presión", "tiempo", "pronóstico", "alivio", "aura", "cluster", "tensión", "desencadenante", "dolor", "simple"],
    "es-MX": ["presión", "clima", "pronóstico", "alivio", "aura", "cluster", "tensión", "desencadenante", "dolor", "simple"],
    "ca": ["pressió", "temps", "previsió", "alleujament", "aura", "cluster", "tensió", "desencadenant", "dolor", "simple"],
    "it": ["pressione", "meteo", "previsione", "sollievo", "aura", "cluster", "tensione", "trigger", "dolore", "semplice"],
    "pt-BR": ["pressão", "clima", "previsão", "alívio", "aura", "cluster", "tensão", "gatilho", "dor", "simples"],
    "pt-PT": ["pressão", "tempo", "previsão", "alívio", "aura", "cluster", "tensão", "gatilho", "dor", "simples"],
    "nl-NL": ["luchtdruk", "weer", "voorspelling", "verlichting", "aura", "cluster", "spanning", "trigger", "pijn", "eenvoudig"],
    "pl": ["ciśnienie", "pogoda", "prognoza", "ulga", "aura", "klaster", "napięcie", "wyzwalacz", "ból", "prosty"],
    "sv": ["lufttryck", "väder", "prognos", "lindring", "aura", "cluster", "spänning", "trigger", "smärta", "enkel"],
    "da": ["lufttryk", "vejr", "varsel", "lindring", "aura", "cluster", "spænding", "trigger", "smerte", "enkel"],
    "no": ["lufttrykk", "vær", "varsel", "lindring", "aura", "cluster", "spenning", "trigger", "smerte", "enkel"],
    "fi": ["ilmanpaine", "sää", "ennuste", "helpotus", "aura", "cluster", "jännitys", "laukaisin", "kipu", "helppo"],
    "cs": ["tlak", "počasí", "předpověď", "úleva", "aura", "cluster", "tenzní", "spouštěč", "bolest", "jednoduchý"],
    "sk": ["tlak", "počasie", "predpoveď", "úľava", "aura", "cluster", "tenzný", "spúšťač", "bolesť", "jednoduchý"],
    "hu": ["légnyomás", "időjárás", "előrejelzés", "enyhülés", "aura", "cluster", "feszültség", "kiváltó", "fájdalom", "egyszerű"],
    "ro": ["presiune", "vreme", "prognoză", "ameliorare", "aura", "cluster", "tensiune", "declanșator", "durere", "simplu"],
    "hr": ["tlak", "vrijeme", "prognoza", "olakšanje", "aura", "cluster", "tenzijska", "okidač", "bol", "jednostavno"],
    "el": ["πίεση", "καιρός", "πρόγνωση", "ανακούφιση", "aura", "cluster", "τάση", "έναυσμα", "πόνος", "απλό"],
    "tr": ["basınç", "hava", "tahmin", "rahatlama", "aura", "küme", "gerilim", "tetik", "ağrı", "basit"],
    "ru": ["давление", "погода", "прогноз", "облегчение", "аура", "кластер", "напряжение", "триггер", "боль", "простой"],
    "uk": ["тиск", "погода", "прогноз", "полегшення", "аура", "кластер", "напруга", "тригер", "біль", "простий"],
    "ja": ["気圧", "天気", "予報", "緩和", "前兆", "群発", "緊張", "トリガー", "痛み", "簡単"],
    "ko": ["기압", "날씨", "예보", "완화", "전조", "군발", "긴장", "유발", "통증", "간단"],
    "zh-Hans": ["气压", "天气", "预报", "缓解", "先兆", "丛集", "紧张", "诱因", "疼痛", "简单"],
    "zh-Hant": ["氣壓", "天氣", "預報", "緩解", "先兆", "叢發", "緊張", "誘因", "疼痛", "簡單"],
    "ar-SA": ["ضغط", "طقس", "توقعات", "تخفيف", "هالة", "عنقودي", "توتر", "محفز", "ألم", "بسيط"],
    "he": ["לחץ", "מזג", "תחזית", "הקלה", "הילה", "אשכול", "מתח", "מעורר", "כאב", "פשוט"],
    "hi": ["दबाव", "मौसम", "पूर्वानुमान", "राहत", "ऑरा", "क्लस्टर", "तनाव", "ट्रिगर", "दर्द", "सरल"],
    "th": ["ความกดอากาศ", "อากาศ", "พยากรณ์", "บรรเทา", "ออรา", "คลัสเตอร์", "ตึงเครียด", "ทริกเกอร์", "ปวด", "ง่าย"],
    "vi": ["áp suất", "thời tiết", "dự báo", "giảm đau", "aura", "cụm", "căng thẳng", "kích hoạt", "đau", "đơn giản"],
    "id": ["tekanan", "cuaca", "prakiraan", "pereda", "aura", "cluster", "tegang", "pemicu", "nyeri", "mudah"],
    "ms": ["tekanan", "cuaca", "ramalan", "pelega", "aura", "kelompok", "tegang", "pencetus", "sakit", "mudah"],
    "bn-BD": ["চাপ", "আবহাওয়া", "পূর্বাভাস", "উপশম", "অরা", "ক্লাস্টার", "টেনশন", "ট্রিগার", "ব্যথা", "সহজ"],
    "gu-IN": ["દબાણ", "હવામાન", "આગાહી", "રાહત", "ઓરા", "ક્લસ્ટર", "તણાવ", "ટ્રિગર", "દર્દ", "સરળ"],
    "kn-IN": ["ಒತ್ತಡ", "ಹವಾಮಾನ", "ಮುನ್ಸೂಚನೆ", "ಶಮನ", "ಅರಾ", "ಕ್ಲಸ್ಟರ್", "ಒತ್ತಡ", "ಟ್ರಿಗರ್", "ನೋವು", "ಸರಳ"],
    "ml-IN": ["മർദ്ദം", "കാലാവസ്ഥ", "പ്രവചനം", "ആശ്വാസം", "ഓറ", "ക്ലസ്റ്റർ", "പിരിമുറുക്കം", "ട്രിഗർ", "വേദന", "ലളിതം"],
    "mr-IN": ["दाब", "हवामान", "अंदाज", "आराम", "ऑरा", "क्लस्टर", "ताण", "ट्रिगर", "वेदना", "सोपे"],
    "or-IN": ["ଚାପ", "ପାଣିପାଗ", "ପୂର୍ବାନୁମାନ", "ଆରାମ", "ଅରା", "କ୍ଲଷ୍ଟର", "ଚାପ", "ଟ୍ରିଗର", "ଯନ୍ତ୍ରଣା", "ସରଳ"],
    "pa-IN": ["ਦਬਾਅ", "ਮੌਸਮ", "ਭਵਿੱਖਬਾਣੀ", "ਰਾਹਤ", "ਆਰਾ", "ਕਲਸਟਰ", "ਤਣਾਅ", "ਟਰਿਗਰ", "ਦਰਦ", "ਸਧਾਰਨ"],
    "ta-IN": ["அழுத்தம்", "வானிலை", "முன்னறிவிப்பு", "நிவாரணம்", "ஒளி", "கொத்து", "இறுக்கம்", "தூண்டி", "வலி", "எளிய"],
    "te-IN": ["ఒత్తిడి", "వాతావరణం", "సూచన", "ఉపశమనం", "ఆరా", "క్లస్టర్", "ఒత్తిడి", "ట్రిగర్", "నొప్పి", "సరళ"],
    "ur-PK": ["دباؤ", "موسم", "پیشگوئی", "آرام", "ہالہ", "کلسٹر", "تناؤ", "ٹرگر", "درد", "آسان"],
    "sl-SI": ["tlak", "vreme", "napoved", "olajšanje", "avra", "cluster", "napetost", "sprožilec", "bolečina", "preprosto"],
}


def indexed_terms(name: str, subtitle: str) -> set[str]:
    text = f"{name} {subtitle}".lower()
    terms: set[str] = set()
    for w in re.findall(r"[^\s,]+", text):
        w = w.strip("·-&,.:;()").lower()
        if len(w) >= 2:
            terms.add(w)
    return terms


def is_dupe(kw: str, indexed: set[str]) -> bool:
    kw = kw.lower()
    if kw in indexed:
        return True
    for t in indexed:
        if kw == t:
            return True
        if len(kw) >= 4 and kw in t:
            return True
        if len(t) >= 4 and t in kw:
            return True
    return False


def build_keywords(loc: str, name: str, subtitle: str, existing_csv: str) -> str:
    if loc in KW_FULL:
        return KW_FULL[loc]
    indexed = indexed_terms(name, subtitle)
    out: list[str] = []
    seen: set[str] = set()

    def add(term: str) -> None:
        t = term.strip()
        tl = t.lower()
        if not t or tl in seen:
            return
        if is_dupe(t, indexed):
            return
        candidate = ",".join(out + [t])
        if len(candidate) > KW_LIMIT:
            return
        out.append(t)
        seen.add(tl)

    # 1. preserve existing researched terms (re-deduped against the new name+subtitle)
    for raw in existing_csv.replace(" ", "").split(","):
        add(raw)
    # 2. backfill freed slots with validated localized terms
    for term in KW_ADDS.get(loc, []):
        add(term)
    return ",".join(out)


def main() -> None:
    report: dict[str, dict] = {}
    problems: list[str] = []
    for loc in sorted(NEW_NAMES):
        d = META / loc
        if not d.is_dir():
            problems.append(f"{loc}: missing metadata dir")
            continue
        name = NEW_NAMES[loc]
        sub = NEW_SUBTITLES[loc]
        if len(name) > NAME_LIMIT:
            problems.append(f"{loc}: NAME {len(name)}>30 :: {name}")
        if len(sub) > SUB_LIMIT:
            problems.append(f"{loc}: SUBTITLE {len(sub)}>30 :: {sub}")
        old_name = (d / "name.txt").read_text(encoding="utf-8").strip() if (d / "name.txt").exists() else ""
        old_sub = (d / "subtitle.txt").read_text(encoding="utf-8").strip() if (d / "subtitle.txt").exists() else ""
        old_kw = (d / "keywords.txt").read_text(encoding="utf-8").strip() if (d / "keywords.txt").exists() else ""
        new_kw = build_keywords(loc, name, sub, old_kw)
        (d / "name.txt").write_text(name + "\n", encoding="utf-8")
        (d / "subtitle.txt").write_text(sub + "\n", encoding="utf-8")
        (d / "keywords.txt").write_text(new_kw + "\n", encoding="utf-8")
        report[loc] = {
            "name": {"old": old_name, "new": name, "len": len(name)},
            "subtitle": {"old": old_sub, "new": sub, "len": len(sub)},
            "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw)},
        }
    out = ROOT / "scripts" / "aso-relaunch-2026q3-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Updated {len(report)} locales -> {out}")
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  " + p)
    else:
        print("All names/subtitles within limits.")


if __name__ == "__main__":
    main()
