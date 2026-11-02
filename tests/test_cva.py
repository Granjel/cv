import copy
from datetime import datetime
from pathlib import Path
import tempfile
import unittest

from pypdf import PdfWriter

import cva


class WorkbookFlow(unittest.TestCase):
    def setUp(self):
        self.tables = cva.read_excel(cva.ROOT / "outputs/cva/datos-cv.xlsx")

    def prepare(self, lang="es"):
        return cva.prepare(self.tables, lang, demo=True)

    def test_both_languages_from_one_workbook(self):
        es, en = self.prepare(), self.prepare("en")
        self.assertEqual(es["perfil"]["nombre"], en["perfil"]["nombre"])
        self.assertIn("Investigador", es["perfil"]["puesto"])
        self.assertIn("researcher", en["perfil"]["puesto"])

    def test_example_requires_explicit_demo(self):
        with self.assertRaisesRegex(cva.DataError, "ejemplos ficticios"):
            cva.prepare(self.tables, "es")

    def test_new_row_is_included_without_template_changes(self):
        row = copy.deepcopy(self.tables["Publicaciones"][0])
        row.update(id="pub_nueva", fecha=datetime(2026, 3, 1), titulo="NEW PUBLICATION")
        self.tables["Publicaciones"].append(row)
        entries = self.prepare()["publicaciones"]
        self.assertEqual(len(entries), 2)
        self.assertIn("NEW PUBLICATION", entries[0])

    def test_unselected_incomplete_row_is_excluded(self):
        self.tables["Proyectos"].append({"id":"draft", "incluir_cva":"NO", "_context":"Proyectos, fila 3"})
        self.assertEqual(len(self.prepare()["proyectos"]), 1)

    def test_missing_translation_stops_only_requested_language(self):
        self.tables["Proyectos"][0]["rol_en"] = ""
        self.prepare("es")
        with self.assertRaisesRegex(cva.DataError, "rol_en"):
            self.prepare("en")

    def test_optional_translation_cannot_silently_disappear(self):
        self.tables["Publicaciones"][0]["contribucion_en"] = ""
        with self.assertRaisesRegex(cva.DataError, "contribucion_en"):
            self.prepare("en")

    def test_summary_boundary(self):
        self.tables["Textos"][0]["es"] = "a" * 5000
        self.assertEqual(len(self.prepare()["resumen"]), 5000)
        self.tables["Textos"][0]["es"] += "b"
        with self.assertRaisesRegex(cva.DataError, "5001"):
            self.prepare()

    def test_ten_contributions_boundary(self):
        original = self.tables["Congresos"][0]
        self.tables["Congresos"] = [dict(original,id=f"cong_{i}") for i in range(10)]
        self.assertEqual(len(self.prepare()["congresos"]), 10)
        self.tables["Congresos"].append(dict(original,id="cong_11"))
        with self.assertRaisesRegex(cva.DataError, "máximo es 10"):
            self.prepare()

    def test_many_authors(self):
        row = self.tables["Publicaciones"][0]
        row.update(autores="; ".join(f"Author {i}" for i in range(1,11)),posicion_autor=5,correspondencia="Author 5; Author 10")
        entry = self.prepare()["publicaciones"][0]
        self.assertIn("Author 1; Author 2; Author 3; …; Author 10", entry)
        self.assertIn("(5/10)", entry)
        row["posicion_autor"] = 11
        with self.assertRaisesRegex(cva.DataError, "fuera de la lista"):
            self.prepare()

    def test_interruption_includes_duration(self):
        row=self.tables["Experiencia"][0]
        row.update(motivo_es="Permiso",motivo_en="Leave",meses_interrupcion=6)
        self.assertIn("Permiso (6 meses)",self.prepare()["experiencia"][0]["detalle"])
        self.assertIn("Leave (6 months)",self.prepare("en")["experiencia"][0]["detalle"])

    def test_reversed_dates_rejected(self):
        self.tables["Proyectos"][0]["fin"]="2020-01-01"
        with self.assertRaisesRegex(cva.DataError,"fin es anterior"):
            self.prepare()

    def test_original_titles_preserved(self):
        self.tables["Publicaciones"][0]["titulo"]="Título original # [literal]"
        for lang in ("es","en"):
            self.assertIn("Título original # [literal]",self.prepare(lang)["publicaciones"][0])

    def test_typst_special_characters_are_literal_strings(self):
        self.tables["Textos"][0]["es"]='#panic("not code") [texto] $math$'
        self.assertEqual(self.prepare()["resumen"], '#panic("not code") [texto] $math$')

    def test_real_zero_funding_is_preserved(self):
        self.tables["Proyectos"][0]["importe"] = 0
        self.assertIn("0,00 EUR", self.prepare()["proyectos"][0])

    def test_four_page_limit_rejects_five(self):
        (cva.ROOT/"build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cva.ROOT/"build") as folder:
            pdf = Path(folder)/"five-pages.pdf"
            writer=PdfWriter()
            for _ in range(5):
                writer.add_blank_page(width=595.28,height=841.89)
            writer.write(pdf)
            with self.assertRaisesRegex(cva.DataError,"5 páginas"):
                cva.check_pdf(pdf)


if __name__ == "__main__":
    unittest.main()
