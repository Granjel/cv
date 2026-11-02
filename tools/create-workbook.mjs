// Run with the bundled artifact-tool runtime. ARTIFACT_NODE_MODULES may point
// to its node_modules directory when a local junction is unavailable.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
const require = createRequire(process.env.ARTIFACT_NODE_MODULES
  ? path.join(process.env.ARTIFACT_NODE_MODULES, '_loader.cjs') : import.meta.url);
const { Workbook, SpreadsheetFile } = await import(pathToFileURL(require.resolve('@oai/artifact-tool')));
const exists = await fs.access('outputs/cva/datos-cv.xlsx').then(()=>true,()=>false);
if (exists && !process.argv.includes('--force')) {
  throw new Error('El libro ya existe. No se ha modificado. Usa --force solo para reconstruir el ejemplo.');
}
const data = JSON.parse(await fs.readFile('tools/workbook-data.json', 'utf8'));
const wb = Workbook.create();
const guide = wb.worksheets.add('Guia');
const notes = [
  ['CVA AEI · datos en español e inglés', ''],
  ['Paso', 'Qué hacer'],
  ['1. Sustituye los ejemplos', 'Todas las filas iniciales son ficticias. Reemplázalas con tus datos.'],
  ['2. Completa Perfil', 'valor es común a ambos idiomas; es/en contienen las traducciones. Usa solo una opción.'],
  ['3. Añade tus méritos', 'Una fila por mérito. Conserva los nombres de pestañas y encabezados.'],
  ['4. Selecciona el contenido', 'incluir_cva = SI o TRUE para incluir; NO o FALSE para excluir.'],
  ['5. Escribe el resumen', 'En Textos, clave resumen. Puedes usar saltos de línea dentro de la celda.'],
  ['6. Desactiva los ejemplos', 'En Perfil, cambia datos_de_ejemplo a FALSE cuando todos los datos sean tuyos.'],
  ['7. Guarda y genera', 'python cva.py --idioma ambos'],
  ['Idiomas', 'Los campos _es/_en se traducen. Los títulos originales, DOI y nombres oficiales se conservan.'],
  ['Fechas', 'Usa fechas reales de Excel. La fecha final de un puesto actual puede quedar vacía.'],
  ['Autores', 'Separa cada autor con punto y coma (;), conservando el orden de firma.'],
  ['Más de ocho autores', 'Indica posicion_autor y los autores de correspondencia, separados por punto y coma.'],
  ['Tipos de publicación', 'articulo, libro, capitulo, datos o software.'],
  ['Tipos de transferencia', 'contrato, patente u otro.'],
  ['Interrupciones', 'En Experiencia, completa el motivo y los meses de interrupción.'],
  ['Orden de salida', 'Cronológico inverso por fecha (inicio en proyectos y experiencia).'],
  ['Selección', 'Máximo 10 entradas en cada apartado C. No se eliminan méritos automáticamente.'],
  ['Datos personales', 'Este libro contiene información personal. Guárdalo y compártelo con el cuidado habitual.'],
  ['Referencia oficial', 'https://www.aei.gob.es/en/announcements/announcements-finder/ayudas-contratos-juan-cierva-2026/convocatoria'],
];
guide.getRange(`A1:B${notes.length}`).values = notes;
guide.getRange(`A1:B${notes.length}`).format.font = { name: 'Arial', size: 11 };
guide.getRange('A1').format.font = { name: 'Arial', size: 15, bold: true };
guide.getRange('A1:B1').format.rowHeight = 28;
guide.getRange(`A2:A${notes.length}`).format.columnWidth = 34;
guide.getRange(`B2:B${notes.length}`).format.columnWidth = 115;
guide.getRange(`A2:B${notes.length}`).format.rowHeight = 32;
guide.getRange('A2:B2').format = {fill:'#24374B',font:{color:'#FFFFFF',bold:true}};
guide.showGridLines = false;
guide.tabColor = '#24374B';
for (const [name, {headers, rows}] of Object.entries(data)) {
  const s = wb.worksheets.add(name);
  s.showGridLines = false;
  const typed = rows.map(row => row.map((v,i) =>
    ['fecha','inicio','fin'].includes(headers[i]) && v ? new Date(v+'T00:00:00Z') : v));
  s.getRangeByIndexes(0,0,rows.length+1,headers.length).values = [headers,...typed];
  const area = s.getRangeByIndexes(0,0,Math.max(rows.length+1,12),headers.length);
  area.format.font = {name:'Arial',size:11};
  area.format.columnWidth = 24;
  area.format.rowHeight = 30;
  area.format.verticalAlignment = 'center';
  s.getRangeByIndexes(0,0,1,headers.length).format = {
    fill:'#24374B',font:{name:'Arial',size:11,bold:true,color:'#FFFFFF'},
    wrapText:true,rowHeight:42,horizontalAlignment:'center'
  };
  s.freezePanes.freezeRows(1);
  s.freezePanes.freezeColumns(1);
  s.getRangeByIndexes(1,0,Math.max(rows.length,11),1).format.columnWidth = 26;
  for (let i=0;i<headers.length;i++) {
    const h=headers[i], col=s.getRangeByIndexes(1,i,Math.max(rows.length,11),1);
    if (['fecha','inicio','fin'].includes(h)) {col.setNumberFormat('yyyy-mm-dd');col.format.columnWidth=16;}
    else if (['importe','posicion_autor','meses_interrupcion'].includes(h)) col.setNumberFormat('#,##0');
    else if (h!=='incluir_cva') col.setNumberFormat('@');
    if (h==='incluir_cva') {
      col.format.columnWidth=15;
      s.getRangeByIndexes(1,i,999,1).dataValidation = {rule:{type:'list',values:['TRUE','FALSE','SI','NO']}};
    }
    if (h.endsWith('_es')||h.endsWith('_en')||['es','en','titulo','autores','institucion','universidad','revista_editorial','congreso'].includes(h)) {
      col.format.columnWidth = name==='Textos'?90:42;
      col.format.wrapText=true;
      col.format.verticalAlignment='top';
    }
  }
  s.getRangeByIndexes(1,0,rows.length,headers.length).format.rowHeight = name==='Textos'?130:70;
  if(name==='Perfil') {
    s.getRange('A2:D18').format.rowHeight=36;
    s.getRange('A2:A18').format.font={bold:true,color:'#24374B'};
    s.getRange('B2:D18').format.columnWidth=42;
    s.getRange('B2:D18').format.wrapText=true;
    s.getRange('B18').format.fill='#FFF2CC';
  }
}
wb.recalculate();
await fs.mkdir('tmp/previews',{recursive:true});
for (const name of ['Guia',...Object.keys(data)]) {
  const range=name==='Guia'?'A1:B20': name==='Perfil'?'A1:D18':name==='Textos'?'A1:C2':`A1:${String.fromCharCode(64+data[name].headers.length)}2`;
  const preview=await wb.render({sheetName:name,range,scale:1,format:'png'});
  await fs.writeFile(`tmp/previews/${name}.png`,new Uint8Array(await preview.arrayBuffer()));
}
console.log((await wb.inspect({kind:'sheet',include:'id,name',maxChars:2500})).ndjson);
const output=await SpreadsheetFile.exportXlsx(wb);
await fs.mkdir('outputs/cva',{recursive:true});
await output.save('outputs/cva/datos-cv.xlsx');
console.log('Creado outputs/cva/datos-cv.xlsx');
