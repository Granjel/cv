"""Generate an AEI CVA from a bilingual Excel workbook and a Typst template."""
from __future__ import annotations

import argparse
from datetime import date, datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from openpyxl import load_workbook
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent
SCHEMA = json.loads((ROOT / "tools/workbook-data.json").read_text(encoding="utf-8"))
CONTRIBUTIONS = ("Publicaciones", "Congresos", "Proyectos", "Transferencia")


class DataError(ValueError):
    pass


def text(value):
    if value is None:
        return ""
    if isinstance(value, (date, datetime)):
        return value.strftime("%Y-%m-%d")
    return str(value).strip()


def boolean(value, context):
    if isinstance(value, bool):
        return value
    normalized = text(value).casefold()
    if normalized in ("true", "si", "sí", "1"):
        return True
    if normalized in ("false", "no", "0"):
        return False
    raise DataError(f"{context}: usa SI/NO o TRUE/FALSE.")


def iso(value, context, optional=False):
    value = text(value)
    if not value and optional:
        return ""
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError:
        raise DataError(f"{context}: se necesita una fecha de Excel o AAAA-MM-DD.") from None


def required(row, key, context):
    value = text(row.get(key))
    if not value:
        raise DataError(f"{context}: falta {key}.")
    return value


def localized(row, key, lang, context, mandatory=False):
    value = text(row.get(f"{key}_{lang}"))
    other = text(row.get(f"{key}_{'en' if lang == 'es' else 'es'}"))
    if not value and (mandatory or other):
        raise DataError(f"{context}: falta la traducción {key}_{lang}.")
    return value


def read_excel(filename):
    # Read formulas themselves: cached formula values can be absent or stale.
    wb = load_workbook(filename, read_only=True, data_only=False)
    result = {}
    try:
        for name, schema in SCHEMA.items():
            if name not in wb.sheetnames:
                raise DataError(f"Falta la pestaña {name}.")
            raw = wb[name].iter_rows(values_only=True)
            headers = [text(v) for v in next(raw, ())]
            if len(headers) != len(set(headers)):
                raise DataError(f"{name}: hay encabezados duplicados.")
            missing = set(schema["headers"]) - set(headers)
            if missing:
                raise DataError(f"{name}: faltan columnas {', '.join(sorted(missing))}.")
            rows = []
            seen = set()
            key = "campo" if name == "Perfil" else "clave" if name == "Textos" else "id"
            for number, values in enumerate(raw, start=2):
                row = dict(zip(headers, values))
                if not any(text(row.get(h)) for h in schema["headers"]):
                    continue
                context = f"{name}, fila {number}"
                if any(isinstance(v, str) and v.startswith("=") for v in values if v is not None):
                    raise DataError(f"{context}: usa valores, no fórmulas, en los datos del CVA.")
                identifier = required(row, key, context)
                if identifier in seen:
                    raise DataError(f"{context}: {key} duplicado: {identifier}.")
                seen.add(identifier)
                row["_context"] = context
                rows.append(row)
            result[name] = rows
    finally:
        wb.close()
    return result


def selected(tables, name):
    rows = [r for r in tables[name] if boolean(r["incluir_cva"], r["_context"])]
    if name in CONTRIBUTIONS and len(rows) > 10:
        raise DataError(f"{name}: has seleccionado {len(rows)} entradas; el máximo es 10.")
    date_key = "inicio" if name in ("Experiencia", "Proyectos") else "fecha"
    for row in rows:
        row[date_key] = iso(row[date_key], row["_context"] + ": " + date_key)
        if "fin" in row:
            row["fin"] = iso(row["fin"], row["_context"] + ": fin", optional=True)
            if row["fin"] and row["fin"] < row[date_key]:
                raise DataError(f"{row['_context']}: fin es anterior a {date_key}.")
    return sorted(rows, key=lambda r: (r[date_key], text(r["id"])), reverse=True)


def number(value, context, integer=False):
    try:
        n = float(value)
    except (TypeError, ValueError):
        raise DataError(f"{context}: se necesita un número.") from None
    if not (0 <= n < float("inf")) or (integer and not n.is_integer()):
        raise DataError(f"{context}: se necesita un número no negativo" + (" entero." if integer else "."))
    return int(n) if integer else n


def amount(row, lang):
    if row.get("importe") is None or text(row.get("importe")) == "":
        raise DataError(f"{row['_context']}: falta importe.")
    n = number(row["importe"], row["_context"] + ": importe")
    display = f"{n:,.2f}"
    if lang == "es":
        display = display.translate(str.maketrans(",.", ".,"))
    return display + " " + required(row, "moneda", row["_context"])


def authors(row):
    context = row["_context"]
    names = [n.strip() for n in required(row, "autores", context).split(";") if n.strip()]
    if len(names) <= 8:
        return "; ".join(names)
    pos = number(row.get("posicion_autor"), context + ": posicion_autor", integer=True)
    if not 1 <= pos <= len(names):
        raise DataError(f"{context}: posicion_autor está fuera de la lista de autores.")
    correspondence = required(row, "correspondencia", context)
    if any(n.strip() not in names for n in correspondence.split(";")):
        raise DataError(f"{context}: un autor de correspondencia no aparece en autores.")
    return "; ".join(names[:3] + ["…", names[-1]]) + f". AC: {correspondence}. ({pos}/{len(names)})"


def sentences(parts):
    result = ""
    for part in filter(None, parts):
        result += (" " if result.endswith((".", "!", "?")) else ". " if result else "") + part
    return result


def prepare(tables, lang, demo=False):
    profile_rows = {r["campo"]: r for r in tables["Perfil"]}
    example = profile_rows.get("datos_de_ejemplo")
    if example is None:
        raise DataError("Perfil: falta datos_de_ejemplo.")
    is_example = boolean(example.get("valor"), "Perfil: datos_de_ejemplo")
    if is_example and not demo:
        raise DataError("El libro contiene ejemplos ficticios. Usa --demo para probarlo. Sustitúyelos y cambia datos_de_ejemplo a FALSE para generar tu CVA.")
    profile = {}
    for key in [r[0] for r in SCHEMA["Perfil"]["rows"] if r[0] != "datos_de_ejemplo"]:
        if key not in profile_rows:
            raise DataError(f"Perfil: falta el campo {key}.")
        row = profile_rows[key]
        common = text(row.get("valor"))
        if common and (text(row.get("es")) or text(row.get("en"))):
            raise DataError(f"Perfil: {key}: usa valor o es/en, sin combinar ambas opciones.")
        value = common or text(row.get(lang))
        if not value and key != "web":
            raise DataError(f"Perfil: falta {key} para el idioma {lang}.")
        profile[key] = value
    for key in ("fecha_cva", "fecha_nacimiento", "fecha_inicio"):
        profile[key] = iso(profile[key], "Perfil: " + key)
    if not re.fullmatch(r"\d{4}-\d{4}-\d{4}-\d{3}[\dX]", profile["orcid"]):
        raise DataError("Perfil: ORCID debe tener el formato 0000-0000-0000-0000.")
    texts = {r["clave"]: r for r in tables["Textos"]}
    summary = required(texts.get("resumen", {}), lang, "Textos: resumen")
    if len(summary) > 5000:
        raise DataError(f"El resumen {lang} tiene {len(summary)} caracteres; el máximo es 5000.")
    data = {"idioma": lang, "demo": bool(demo or is_example), "perfil": profile, "resumen": summary}
    es = lang == "es"
    for name in ("Experiencia", "Formacion", *CONTRIBUTIONS):
        entries = []
        for row in selected(tables, name):
            ctx = row["_context"]
            req = lambda k: required(row, k, ctx)
            loc = lambda k, mandatory=False: localized(row, k, lang, ctx, mandatory)
            if name == "Experiencia":
                reason = loc("motivo")
                months = ""
                if reason or text(row.get("meses_interrupcion")):
                    reason = loc("motivo", True)
                    m = number(row.get("meses_interrupcion"), ctx + ": meses_interrupcion", integer=True)
                    months = f" ({m} {'meses' if es else 'months'})"
                entries.append({"periodo": row["inicio"] + " / " + (row["fin"] or ("actualidad" if es else "present")), "detalle": ". ".join(filter(None, [loc("puesto",True),req("institucion"),loc("pais",True),reason+months]))})
            elif name == "Formacion":
                entries.append({"titulo":loc("titulo",True), "universidad":req("universidad") + " / " + loc("pais",True), "anio":row["fecha"][:4]})
            elif name == "Publicaciones":
                kind = req("tipo")
                if kind not in ("articulo", "libro", "capitulo", "datos", "software"):
                    raise DataError(f"{ctx}: tipo de publicación desconocido: {kind}.")
                parts = [authors(row),row["fecha"][:4],req("titulo"),req("revista_editorial")]
                parts += [text(row.get("volumen")),text(row.get("paginas"))]
                if kind in ("libro","capitulo"):
                    parts += ["ISBN: " + req("isbn")]
                if text(row.get("doi")):
                    doi = text(row["doi"]).removeprefix("https://doi.org/").removeprefix("doi:").strip()
                    if not re.fullmatch(r"10\.\d{4,9}/\S+", doi):
                        raise DataError(f"{ctx}: DOI no válido.")
                    parts += ["https://doi.org/"+doi]
                parts += [loc("contribucion")]
                entries.append(sentences(parts))
            elif name == "Congresos":
                entries.append(sentences([req("autores"),req("titulo"),loc("modalidad",True),req("congreso"),row["fecha"],req("lugar")]))
            elif name == "Proyectos":
                entries.append(sentences([req("referencia"),req("titulo"),req("financiador"),req("convocatoria"),"IP: "+req("ip")+" ("+req("institucion_ip")+")",row["inicio"]+" / "+(row["fin"] or ("actualidad" if es else "present")),amount(row,lang),loc("rol",True),loc("estado",True),loc("contribucion",True)]))
            else:
                kind = req("tipo")
                if kind not in ("contrato","patente","otro"):
                    raise DataError(f"{ctx}: tipo de transferencia desconocido.")
                parts = [req("autores"),req("referencia"),req("titulo"),row["fecha"]]
                if kind == "patente":
                    parts += [req("paises_prioridad"),req("titular"),loc("explotacion",True),text(row.get("empresas"))]
                elif kind == "contrato":
                    parts += [req("entidad"),"IP: "+req("ip")+" ("+req("institucion_ip")+")",req("fin"),amount(row,lang)]
                parts += [loc("descripcion",True)]
                entries.append(sentences(parts))
        data[name.lower()] = entries
    return data


def check_pdf(filename):
    reader = PdfReader(filename)
    if not 1 <= len(reader.pages) <= 4:
        raise DataError(f"El PDF tiene {len(reader.pages)} páginas; el máximo es 4.")
    if filename.stat().st_size > 4_000_000:
        raise DataError("El PDF supera los 4 MB.")
    if "/Collection" in reader.trailer["/Root"]:
        raise DataError("No se admiten carteras PDF.")
    for page in reader.pages:
        width, height = float(page.mediabox.width),float(page.mediabox.height)
        if abs(width-595.28)>1 or abs(height-841.89)>1:
            raise DataError("El PDF no tiene tamaño A4.")
        def visitor(content, cm, tm, font, size):
            if content.strip() and size < 10.99:
                raise DataError(f"Texto de {size} puntos; el mínimo es 11.")
            if content.strip() and font and not any(n in str(font.get('/BaseFont','')) for n in ('Arial','Calibri','TimesNewRoman','Times-New-Roman')):
                raise DataError("El PDF contiene una fuente ajena a Arial, Calibri o Times New Roman.")
        page.extract_text(visitor_text=visitor)
    return {"paginas": len(reader.pages), "bytes": filename.stat().st_size}


def build(excel, languages, demo=False, check=False, typst="typst", output=None):
    source = excel.read_bytes()
    tables = read_excel(excel)
    # Validate every requested language before producing any output.
    documents = {lang:prepare(tables,lang,demo) for lang in languages}
    if check:
        return {lang:{"resumen_caracteres":len(doc["resumen"])} for lang,doc in documents.items()}
    executable = shutil.which(typst)
    if not executable:
        raise DataError("No se encuentra Typst. Instálalo o usa --typst RUTA_AL_EJECUTABLE.")
    fonts = subprocess.run([executable,"fonts"],capture_output=True,text=True,check=True).stdout
    if "Arial" not in fonts.splitlines():
        raise DataError("No se encuentra la fuente Arial. Instálala antes de generar el CVA.")
    (ROOT/"build").mkdir(exist_ok=True)
    destination = output or ROOT/"output"
    with tempfile.TemporaryDirectory(dir=ROOT/"build") as work:
        folder = Path(work)
        results = {}
        for lang,document in documents.items():
            payload = folder/f"cva-{lang}.json"
            payload.write_text(json.dumps(document,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
            pdf = folder/f"cva{'-ejemplo' if demo else ''}-{lang}.pdf"
            result = subprocess.run([executable,"compile","--root",str(ROOT),"--input",f"data={payload.relative_to(ROOT).as_posix()}",str(ROOT/"cva.typ"),str(pdf)],capture_output=True,text=True,encoding="utf-8")
            if result.returncode or result.stderr.strip():
                raise DataError("Typst: "+result.stderr.strip())
            results[lang] = check_pdf(pdf)
        # Keep the exact source and generated data together for reproducibility.
        fingerprint = hashlib.sha256(source + b"".join(p.read_bytes() for p in sorted(folder.glob('*.json')))).hexdigest()[:12]
        run_dir = ROOT/"build"/"snapshots"/(datetime.now().strftime("%Y%m%d-%H%M%S")+"-"+fingerprint)
        run_dir.mkdir(parents=True,exist_ok=True)
        (run_dir/"datos-cv.xlsx").write_bytes(source)
        shutil.copy2(ROOT/"cva.typ",run_dir/"cva.typ")
        shutil.copy2(ROOT/"cva.py",run_dir/"cva.py")
        destination.mkdir(parents=True,exist_ok=True)
        for p in folder.iterdir():
            shutil.copy2(p,run_dir/p.name)
            if p.suffix == ".pdf":
                shutil.copy2(p,destination/p.name)
        manifest = {"fuente_sha256":hashlib.sha256(source).hexdigest(),"idiomas":results,"demo":demo,"typst":subprocess.run([executable,'--version'],capture_output=True,text=True,check=True).stdout.strip()}
        (run_dir/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
        return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--excel",type=Path,default=ROOT/"outputs/cva/datos-cv.xlsx")
    parser.add_argument("--idioma",choices=("es","en","ambos"),default="ambos")
    parser.add_argument("--demo",action="store_true",help="Permite datos ficticios y marca el PDF como ejemplo.")
    parser.add_argument("--check",action="store_true",help="Valida datos sin generar PDF.")
    parser.add_argument("--typst",default="typst")
    parser.add_argument("--output",type=Path)
    args = parser.parse_args()
    try:
        results=build(args.excel,["es","en"] if args.idioma=="ambos" else [args.idioma],args.demo,args.check,args.typst,args.output)
    except (DataError,OSError,subprocess.SubprocessError) as e:
        print(f"Error: {e}",file=sys.stderr)
        return 1
    for lang,info in results.items():
        print(f"{lang}: " + ", ".join(f"{k}={v}" for k,v in info.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
