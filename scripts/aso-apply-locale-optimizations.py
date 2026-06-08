#!/usr/bin/env python3
"""Apply optimized native keywords/subtitles for all fastlane metadata locales (go pipeline).

Dedupes keywords against each locale's name + subtitle (Apple indexes all three;
repeats waste the 100-char keyword field — see ASC ASO Assist).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

# Native keyword fields (≤100 chars). Strategy: headache/migraine/tracker + watch/widget/diary + pain/cluster/export/trigger + health/doctor/symptom/log
KEYWORDS: dict[str, str] = {
    # en-* base lists omit terms already in name/subtitle (dedupe applied again at write time)
    "en-US": "watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,healthkit,tension,chronic,episode,csv,siri",
    "en-GB": "watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,healthkit,tension,chronic,episode,csv,siri",
    "en-AU": "watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,healthkit,tension,chronic,episode,csv,siri",
    "en-CA": "watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,healthkit,tension,chronic,episode,csv,siri",
    "de-DE": "kopfschmerz,migräne,tracker,uhr,widget,tagebuch,schmerz,cluster,export,auslöser,gesundheit,arzt,symptom,log",
    "fr-FR": "migraine,céphalée,tracker,montre,widget,journal,douleur,cluster,export,déclencheur,santé,médecin,symptôme,log",
    "fr-CA": "migraine,mal,tête,tracker,montre,widget,journal,douleur,cluster,export,déclencheur,santé,médecin,symptôme,log",
    "es-ES": "migraña,cefalea,tracker,reloj,widget,diario,dolor,cluster,exportar,desencadenante,salud,médico,síntoma,log",
    "es-MX": "migraña,cefalea,tracker,reloj,widget,diario,dolor,cluster,exportar,desencadenante,salud,médico,síntoma,log",
    "ca": "migranya,cefalea,tracker,rellotge,widget,diari,dolor,cluster,exportar,desencadenant,salut,metge,símptoma,log",
    "it": "emicrania,cefalea,tracker,orologio,widget,diario,dolore,cluster,esporta,trigger,salute,medico,sintomo,log",
    "pt-BR": "enxaqueca,dor,cabeça,tracker,relógio,widget,diário,cluster,exportar,gatilho,saúde,médico,sintoma,log",
    "pt-PT": "enxaqueca,cefaleia,tracker,relógio,widget,diário,dor,cluster,exportar,gatilho,saúde,médico,sintoma,log",
    "nl-NL": "hoofdpijn,migraine,tracker,horloge,widget,dagboek,pijn,cluster,export,trigger,gezondheid,arts,symptoom,log",
    "pl": "ból,głowy,migrena,tracker,zegarek,widget,dziennik,klaster,eksport,wyzwalacz,zdrowie,lekarz,objaw,log",
    "sv": "huvudvärk,migrän,tracker,klocka,widget,dagbok,smärta,cluster,export,trigger,hälsa,läkare,symptom,log",
    "da": "hovedpine,migræne,tracker,ur,widget,dagbog,smerte,cluster,eksport,trigger,sundhed,læge,symptom,log",
    "no": "hodepine,migrene,tracker,klokke,widget,dagbok,smerte,cluster,eksport,trigger,helse,lege,symptom,log",
    "fi": "päänsärky,migreeni,tracker,kello,widget,päiväkirja,kipu,cluster,vienti,laukaisin,terveys,lääkäri,oire,log",
    "cs": "bolest,hlav,migréna,tracker,hodinky,widget,deník,cluster,export,spouštěč,zdraví,lékař,příznak,log",
    "sk": "bolesť,hlav,migréna,tracker,hodinky,widget,denník,cluster,export,spúšťač,zdravie,lekár,príznak,log",
    "hu": "fejfájás,migrén,tracker,óra,widget,napló,fájdalom,cluster,export,kiváltó,egészség,orvos,tünet,log",
    "ro": "durere,cap,migrenă,tracker,ceas,widget,jurnal,cluster,export,declanșator,sănătate,medic,simptom,log",
    "hr": "glavobolja,migrena,tracker,sat,widget,dnevnik,bol,cluster,izvoz,okidač,zdravlje,doktor,simptom,log",
    "el": "πονοκέφαλος,ημικρανία,tracker,ρολόι,widget,ημερολόγιο,πόνος,cluster,εξαγωγή,εναυσμα,υγεία,γιατρός,σύμπτωμα,log",
    "tr": "baş,ağrısı,migren,tracker,saat,widget,günlük,ağrı,cluster,dışa,aktar,tetik,sağlık,doktor,semptom,log",
    "ru": "головная,боль,мигрень,tracker,часы,widget,дневник,боль,cluster,экспорт,триггер,здоровье,врач,симптом,log",
    "uk": "головний,біль,мігрень,tracker,годинник,widget,щоденник,біль,cluster,експорт,тригер,здоров'я,лікар,симптом,log",
    "ja": "頭痛,片頭痛,トラッカー,ウォッチ,ウィジェット,日記,痛み,群発,エクスポート,トリガー,健康,医師,症状,ログ",
    "ko": "두통,편두통,트래커,워치,위젯,일기,통증,군발,보내기,유발,건강,의사,증상,로그",
    "zh-Hans": "头痛,偏头痛,追踪,手表,小组件,日记,疼痛,丛集,导出,诱因,健康,医生,症状,记录",
    "zh-Hant": "頭痛,偏頭痛,追蹤,手錶,小工具,日記,疼痛,叢發,匯出,誘因,健康,醫師,症狀,記錄",
    "ar-SA": "صداع,شقيقة,متتبع,ساعة,ودجت,يوميات,ألم,عنقودي,تصدير,محفز,صحة,طبيب,عرض,سجل",
    "he": "כאב,ראש,מיגרנה,מעקב,שעון,ווידג'ט,יומן,כאב,אשכול,ייצוא,מעורר,בריאות,רופא,תסמין,לוג",
    "hi": "सिरदर्द,माइग्रेन,ट्रैकर,घड़ी,विजेट,डायरी,दर्द,क्लस्टर,निर्यात,ट्रिगर,स्वास्थ्य,डॉक्टर,लक्षण,लॉग",
    "th": "ปวดหัว,ไมเกรน,ติดตาม,นาฬิกา,วิดเจ็ต,ไดอารี่,ปวด,คลัสเตอร์,ส่งออก,ทริกเกอร์,สุขภาพ,หมอ,อาการ,บันทึก",
    "vi": "dau,dau dau,migraine,theo doi,dong ho,widget,nhat ky,cum,xuat,kich hoat,suc khoe,bac si,trieu chung,log",
    "id": "sakit,kepala,migrain,pelacak,jam,widget,diari,nyeri,cluster,ekspor,pemicu,kesehatan,dokter,gejala,log",
    "ms": "sakit,kepala,migrain,penjejak,jam,widget,diari,kesakitan,kelompok,eksport,pencetus,kesihatan,doktor,gejala,log",
    "bn-BD": "মাথাব্যথা,মাইগ্রেন,ট্র্যাকার,ঘড়ি,উইজেট,ডায়েরি,ব্যথা,ক্লাস্টার,রপ্তানি,ট্রিগার,স্বাস্থ্য,ডাক্তার,লক্ষণ,লগ",
    "gu-IN": "માથાનો,dard,માઇગ્રેન,ટ્રેકર,ઘડિયાળ,વિજેટ,ડાયરી,દર્દ,ક્લસ્ટર,નિકાસ,ટ્રિગર,સ્વાસ્થ્ય,ડોક્ટર,લક્ષણ,લોગ",
    "kn-IN": "ತಲೆನೋವು,ಮೈಗ್ರೇನ್,ಟ್ರ್ಯಾಕರ್,ಗಡಿಯಾರ,ವಿಜೆಟ್,ದಿನಚರಿ,ನೋವು,ಕ್ಲಸ್ಟರ್,ರಫ್ತು,ಟ್ರಿಗರ್,ಆರೋಗ್ಯ,ವೈದ್ಯ,ಲಕ್ಷಣ,ಲಾಗ್",
    "ml-IN": "തലവേദന,മൈഗ്രേൻ,ട്രാക്കർ,വാച്ച്,വിജറ്റ്,ഡയറി,വേദന,ക്ലസ്റ്റർ,എക്സ്പോർട്ട്,ട്രിഗർ,ആരോഗ്യം,ഡോക്ടർ,ലക്ഷണം,ലോഗ്",
    "mr-IN": "डोकेदुखी,माइग्रेन,ट्रॅकर,घड्याळ,विजेट,डायरी,वेदना,क्लस्टर,निर्यात,ट्रिगर,आरोग्य,डॉक्टर,लक्षण,लॉग",
    "or-IN": "ମୁଣ୍ଡବିନାଶ,ମାଇଗ୍ରେନ,ଟ୍ରାକର,ଘଣ୍ଟା,ୱିଜେଟ,ଡାଇରି,ଯନ୍ତ୍ରଣା,କ୍ଲଷ୍ଟର,ରପ୍ତାନି,ଟ୍ରିଗର,ସ୍ୱାସ୍ଥ୍ୟ,ଡାକ୍ତର,ଲକ୍ଷଣ,ଲଗ୍",
    "pa-IN": "ਸਿਰਦਰਦ,ਮਾਈਗ੍ਰੇਨ,ਟਰੈਕਰ,ਘੜੀ,ਵਿਜੇਟ,ਡਾਇਰੀ,ਦਰਦ,ਕਲਸਟਰ,ਨਿਰਯਾਤ,ਟਰਿਗਰ,ਸਿਹਤ,ਡਾਕਟਰ,ਲੱਛਣ,ਲੌਗ",
    "ta-IN": "தலைவலி,மைக்ரேன்,ட்ராக்கர்,கடிகாரம்,விட்ஜெட்,நாள்,பதிவு,வலி,க்ளஸ்டர்,ஏற்றுமதி,தூண்டி,ஆரோக்கியம்,மருத்துவர்,அறிகுறி,பதிவு",
    "te-IN": "తలనొప్పి,మైగ్రేన్,ట్రాకర్,గడియారం,విడ్జెట్,డైరీ,నొప్పి,క్లస్టర్,ఎగుమతి,ట్రిగర్,ఆరోగ్యం,డాక్టర్,లక్షణం,లాగ్",
    "ur-PK": "سر,درد,مائیگرین,ٹریکر,گھڑی,وجیٹ,ڈائری,درد,کلسٹر,برآمد,ٹرگر,صحت,ڈاکٹر,علامت,لاگ",
    "sl-SI": "glavobol,migrena,tracker,ura,widget,dnevnik,bolečina,cluster,izvoz,sprožilec,zdravje,zdravnik,simptom,log",
}

SUBTITLES: dict[str, str] = {
    "en-US": "Migraine & Headache Log",
    "en-GB": "Migraine & Headache Log",
    "en-AU": "Migraine & Headache Log",
    "en-CA": "Migraine & Headache Log",
    "de-DE": "Migräne-Tagebuch & Tracker",
    "fr-FR": "Journal migraine & céphalée",
    "fr-CA": "Journal migraine & maux de tête",
    "es-ES": "Diario migraña y cefalea",
    "es-MX": "Diario migraña y cefalea",
    "ca": "Diari migranya i cefalea",
    "it": "Diario emicrania e cefalea",
    "pt-BR": "Diário enxaqueca e dor",
    "pt-PT": "Diário enxaqueca e cefaleia",
    "nl-NL": "Migraine & hoofdpijn log",
    "pl": "Dziennik migreny i bólu",
    "ja": "片頭痛・頭痛ワンタップログ",
    "ko": "두통·편두통 원탭 일기",
    "zh-Hans": "偏头痛头痛一键日记",
    "zh-Hant": "偏頭痛頭痛一鍵日記",
}


def indexed_terms(name: str, subtitle: str) -> set[str]:
    """Tokens already credited via App Store name + subtitle."""
    text = f"{name} {subtitle}".lower()
    terms: set[str] = set()
    for w in re.findall(r"[a-z0-9]+", text, flags=re.I):
        if len(w) >= 2:
            terms.add(w)
    return terms


def dedupe_keywords(name: str, subtitle: str, keywords_csv: str) -> str:
    """Drop keywords already present in name/subtitle (ASC ASO Assist rule)."""
    indexed = indexed_terms(name, subtitle)
    kept: list[str] = []
    for raw in keywords_csv.replace(" ", "").split(","):
        kw = raw.strip().lower()
        if not kw:
            continue
        if kw in indexed:
            continue
        # e.g. "tracker" in name, "migraine" in subtitle
        if any(kw == t or (len(kw) >= 4 and kw in t) or (len(t) >= 4 and t in kw) for t in indexed):
            continue
        kept.append(kw)
    return ",".join(kept)


def trim_keywords(s: str, limit: int = 100) -> str:
    s = s.replace(" ", "")
    if len(s) <= limit:
        return s
    parts = s.split(",")
    while parts and len(",".join(parts)) > limit:
        parts.pop()
    return ",".join(parts)


def trim_subtitle(s: str, limit: int = 30) -> str:
    return s[:limit] if len(s) > limit else s


def main() -> None:
    report: dict[str, dict] = {}
    for loc_dir in sorted(META.iterdir()):
        if not loc_dir.is_dir() or loc_dir.name == "review_information":
            continue
        loc = loc_dir.name
        if loc not in KEYWORDS:
            continue
        kw_path = loc_dir / "keywords.txt"
        sub_path = loc_dir / "subtitle.txt"
        old_kw = kw_path.read_text(encoding="utf-8").strip() if kw_path.exists() else ""
        old_sub = sub_path.read_text(encoding="utf-8").strip() if sub_path.exists() else ""
        name = (loc_dir / "name.txt").read_text(encoding="utf-8").strip() if (loc_dir / "name.txt").exists() else ""
        sub_for_dedupe = SUBTITLES.get(loc, old_sub)
        raw_kw = KEYWORDS[loc]
        new_kw = trim_keywords(dedupe_keywords(name, sub_for_dedupe, raw_kw))
        kw_path.write_text(new_kw + "\n", encoding="utf-8")
        new_sub = old_sub
        if loc in SUBTITLES:
            new_sub = trim_subtitle(SUBTITLES[loc])
            sub_path.write_text(new_sub + "\n", encoding="utf-8")
        report[loc] = {
            "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw)},
            "subtitle": {"old": old_sub, "new": new_sub} if loc in SUBTITLES else {},
        }
    out = ROOT / "scripts" / "aso-locale-optimization-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"Updated {len(report)} locales → {out}")


if __name__ == "__main__":
    main()
