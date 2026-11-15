#!/usr/bin/env node
// Diffs lib/services/barcode_db.dart against Open Food Facts.
//
//   node tools/barcode_audit/check_off.js            # every entry
//   node tools/barcode_audit/check_off.js 8901063010138 8901719120077
//
// It reads the Dart file directly, so there is no second copy of the data to
// drift. Coverage for Indian SKUs is thin: expect "not on OFF" for most rows,
// which means the pack in your hand is the only source of truth.
const fs = require('fs');

const src = fs.readFileSync('lib/services/barcode_db.dart', 'utf8');
const re =
  /BarcodeFood\(\s*barcode:\s*'([^']+)',\s*name:\s*'([^']*)',\s*brand:\s*'([^']*)',\s*caloriesPer100g:\s*(\d+),\s*proteinPer100g:\s*([\d.]+),\s*carbsPer100g:\s*([\d.]+),\s*fatsPer100g:\s*([\d.]+),/g;
const all = [...src.matchAll(re)].map((m) => ({
  barcode: m[1], name: m[2], brand: m[3],
  kcal: +m[4], protein: +m[5], carbs: +m[6], fat: +m[7],
}));

const wanted = process.argv.slice(2);
const items = wanted.length ? all.filter((i) => wanted.includes(i.barcode)) : all;
if (!items.length) {
  console.error('No matching entries. Parsed ' + all.length + ' rows.');
  process.exit(1);
}

(async () => {
  let found = 0, missing = 0, differs = 0;
  for (const it of items) {
    let off = null;
    try {
      const res = await fetch(
        'https://world.openfoodfacts.org/api/v2/product/' + it.barcode + '.json' +
          '?fields=product_name,brands,nutriments',
        { headers: { 'User-Agent': 'MacroSnap-barcode-audit/1.0' } },
      );
      const json = await res.json();
      if (json.status === 1 && json.product) {
        const n = json.product.nutriments || {};
        off = {
          name: json.product.product_name,
          kcal: n['energy-kcal_100g'],
          protein: n.proteins_100g,
          carbs: n.carbohydrates_100g,
          fat: n.fat_100g,
        };
      }
    } catch (e) {
      console.log(`${it.barcode}  request failed: ${e.message}`);
      missing++;
      continue;
    }
    if (!off || off.kcal == null) {
      missing++;
      console.log(`${it.barcode}  ${it.brand} ${it.name}  — not on OFF (pack only)`);
    } else {
      found++;
      const d = [];
      if (Math.abs(off.kcal - it.kcal) / it.kcal > 0.1) d.push(`kcal ${it.kcal} → ${Math.round(off.kcal)}`);
      if (off.protein != null && Math.abs(off.protein - it.protein) > 1.5) d.push(`P ${it.protein} → ${off.protein.toFixed(1)}`);
      if (off.carbs != null && Math.abs(off.carbs - it.carbs) > 2) d.push(`C ${it.carbs} → ${off.carbs.toFixed(1)}`);
      if (off.fat != null && Math.abs(off.fat - it.fat) > 1.5) d.push(`F ${it.fat} → ${off.fat.toFixed(1)}`);
      if (d.length) differs++;
      const label = `${it.barcode}  ${it.brand} ${it.name}`;
      console.log(d.length ? `${label}  DIFFERS: ${d.join(', ')}` : `${label}  matches OFF`);
      if (!off.name || !off.name.toLowerCase().includes(it.brand.toLowerCase().slice(0, 5))) {
        console.log(`    ⚠ OFF calls this "${off.name}" — check the barcode is the right product`);
      }
    }
    await new Promise((r) => setTimeout(r, 1100)); // OFF asks for ≤1 request/second
  }
  console.log(`\n${items.length} checked · ${found} on OFF · ${differs} differ · ${missing} unverifiable`);
  process.exit(differs ? 2 : 0);
})();
