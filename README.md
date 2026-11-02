# CVA AEI desde Excel y Typst

Un solo libro Excel contiene los datos comunes y las traducciones al español y al inglés. El generador selecciona los méritos, los ordena por fecha y compone los PDF con Typst. La conexión con Google Sheets queda para una fase posterior.

## Empezar

1. Abre **[outputs/cva/datos-cv.xlsx](outputs/cva/datos-cv.xlsx)**. La pestaña `Guia` explica cómo rellenarlo. Sus entradas iniciales son **ejemplos ficticios**, no datos del solicitante.
2. Reemplaza los ejemplos y añade filas con tus méritos. Conserva los nombres de las pestañas y columnas. Puedes reordenar las columnas.
3. En `Perfil`, cambia `datos_de_ejemplo` a `FALSE` cuando hayas sustituido todos los ejemplos.
4. Instala Python 3.10 o posterior, [Typst](https://typst.app/open-source/) y las dependencias:

   ```console
   python -m pip install -r requirements.txt
   ```

5. Guarda el Excel y ejecuta, desde esta carpeta:

   ```console
   python cva.py --idioma ambos
   ```

Los documentos se guardan como `output/cva-es.pdf` y `output/cva-en.pdf`. También puedes generar un idioma con `--idioma es` o `--idioma en`. Si Typst no está en PATH, indica `--typst "C:\Program Files\Typst\typst.exe"`.

Para probar el libro inicial sin sustituir sus ejemplos:

```console
python cva.py --demo
```

Produce `output/cva-ejemplo-es.pdf` y `output/cva-ejemplo-en.pdf`, marcados como ejemplos. Para validar sin generar PDF: `python cva.py --demo --check`. Puedes usar otro archivo con `--excel "ruta/al/libro.xlsx"` y otra carpeta de destino con `--output "ruta"`.

## Cómo mantener los datos

| Pestaña | Contenido |
| --- | --- |
| Perfil | Datos personales y situación actual. `valor` es común; `es` y `en` son alternativas traducidas. |
| Experiencia | Puestos anteriores e interrupciones, con motivo y duración. |
| Formacion | Una fila por titulación. |
| Publicaciones | Autores completos en orden, título original, revista/editorial, fecha, volumen, páginas, DOI e ISBN cuando proceda. |
| Congresos | Contribuciones, modalidad, autores, congreso, fecha y lugar. |
| Proyectos | Financiación, IP y afiliación, fechas, participación y contribución personal. |
| Transferencia | Contratos, patentes y otras actividades de transferencia. |
| Textos | Resumen narrativo, en una celda por idioma. Admite varios párrafos. |

- Usa un `id` único por entrada. Añadir una fila no requiere editar el código ni la plantilla.
- `incluir_cva`: `SI`/`TRUE` incluye y `NO`/`FALSE` excluye. La comprobación de campos completos y traducciones se aplica a las entradas seleccionadas. Los identificadores siguen siendo obligatorios en las entradas excluidas.
- Los campos `_es` y `_en` se traducen. Los títulos originales y nombres oficiales se comparten. En `Perfil`, rellena `valor` **o** las dos traducciones, sin mezclar ambos métodos.
- Las fechas de las tablas son fechas reales de Excel. En `Perfil`, los valores heterogéneos de la columna `valor` son texto: escribe las fechas como `AAAA-MM-DD`.
- Separa autores con punto y coma. Para publicaciones con más de ocho autores, el generador presenta los tres primeros, el último, los de correspondencia y tu posición sobre el total. Introduce la lista completa, `posicion_autor` y `correspondencia`.
- `Publicaciones.tipo`: `articulo`, `libro`, `capitulo`, `datos` o `software`. Para libros/capítulos se exige ISBN.
- `Transferencia.tipo`: `contrato`, `patente` u `otro`. Cada tipo comprueba sus campos específicos. En patentes describe la explotación y las empresas que la realizan, cuando corresponda.
- Las celdas de datos deben contener valores. Las fórmulas se rechazan para evitar generar documentos con resultados guardados que estén desactualizados.
- Las entradas se ordenan por fecha descendente; en experiencia y proyectos se usa la fecha inicial. `incluir_cva` controla la selección, sin imponer un orden manual.

## Formato y comprobaciones

La plantilla reproduce los apartados A, A.1, A.2, A.3, B y C.1–C.4 de los modelos AEI de Juan de la Cierva 2026. Usa A4, Arial de 11 puntos, márgenes laterales de 2,5 cm y superior/inferior de 1,5 cm. Conserva las tablas de datos personales y trayectoria, adaptando sus anchuras al contenido.

Antes de guardar un PDF se comprueban:

- Campos necesarios y traducciones del idioma elegido.
- Fechas válidas e intervalos coherentes.
- Hasta 5.000 caracteres del resumen, incluidos espacios, y hasta diez entradas por apartado C.
- PDF de hasta cuatro páginas y 4.000.000 bytes, tamaño A4, fuentes admitidas y texto de al menos 11 puntos.

Un exceso produce un error: el proceso no recorta texto ni elimina méritos. Los dos idiomas se validan antes de generar resultados. La revisión visual del contenido real sigue siendo necesaria, especialmente tras añadir textos largos. La plantilla es una implementación local del modelo; no es un formato generado ni certificado por FECYT.

Cada generación conserva en `build/snapshots/` una copia del Excel, los datos JSON utilizados, la plantilla, el script, los PDF y la versión de Typst. La carpeta está excluida de Git. Los archivos de entrada y salida contienen datos personales.

## Referencias oficiales

- [Convocatoria AEI Juan de la Cierva 2026](https://www.aei.gob.es/en/announcements/announcements-finder/ayudas-contratos-juan-cierva-2026/convocatoria).
- [Modelo en español](https://www.aei.gob.es/sites/default/files/convocatory_info/assistants/2026-09/1.CVA%202026%20plantilla.docx).
- [Modelo en inglés](https://www.aei.gob.es/sites/default/files/convocatory_info/assistants/2026-09/3.CVA%202026%20template.docx).
- [Instrucciones](https://www.aei.gob.es/sites/default/files/convocatory_info/assistants/2026-09/2.CVA%202026%20instrucciones.pdf).

Se conservan copias en `references/`. Consultadas el 2 de noviembre de 2026. Los ejemplos de colaboradores podrán orientar ajustes de presentación posteriores.

## Desarrollo

```console
python -m unittest discover -s tests -v
```

`tools/workbook-data.json` describe el libro inicial; `tools/create-workbook.mjs` permite reconstruirlo mediante `@oai/artifact-tool` en el runtime de autoría de Codex. No se necesitan Node ni esa biblioteca para mantener el Excel o generar el CVA. No vuelvas a ejecutar el creador sobre un libro ya rellenado: reconstruye el archivo de ejemplo.
