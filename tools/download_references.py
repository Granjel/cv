from pathlib import Path
import urllib.request
BASE="https://www.aei.gob.es/sites/default/files/convocatory_info/assistants/2026-09/"
for name,remote in [("modelo-es.docx","1.CVA%202026%20plantilla.docx"),("modelo-en.docx","3.CVA%202026%20template.docx"),("instrucciones.pdf","2.CVA%202026%20instrucciones.pdf")]:
    with urllib.request.urlopen(BASE+remote,timeout=30) as r:
        Path("references",name).write_bytes(r.read())
    print(name)
