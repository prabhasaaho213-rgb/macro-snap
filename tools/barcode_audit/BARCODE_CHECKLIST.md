# Barcode database verification

54 bundled entries. The only trustworthy source for these Indian SKUs
is the nutrition panel on the pack: Open Food Facts had usable data for ~1 of
54 when this was written, so nothing here can be verified from a desk.

For each row: photograph the panel, read the per-100 g column, and fill in
`kcal / P / C / F`. Then either fix the number in
`lib/services/barcode_db.dart` or delete the entry if the barcode does not match
the pack in your hand. Re-run `node tools/barcode_audit/check_off.js <barcode>`
for individual products — it prints any OFF data it can find and flags a barcode
that OFF maps to a different brand.

| # | Barcode | Brand | Product | Stored kcal | P | C | F | Panel kcal | P | C | F | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 8901063010138 | Parle | Marie Gold Biscuits | 445 | 6 | 73 | 14 |  |  |  |  |  |
| 2 | 8901063030037 | Parle | Parle-G Biscuits | 450 | 6.2 | 76 | 13 |  |  |  |  |  |
| 3 | 8901063014631 | Parle | Hide & Seek Biscuits | 490 | 5 | 68 | 22 |  |  |  |  |  |
| 4 | 8901063048193 | Parle | Monaco Biscuits | 445 | 7 | 70 | 15 |  |  |  |  |  |
| 5 | 8901058003014 | Cadbury | Oreo Cookies | 480 | 5 | 68 | 21 |  |  |  |  |  |
| 6 | 8901073030139 | Britannia | Good Day Biscuits | 490 | 5.5 | 66 | 23 |  |  |  |  |  |
| 7 | 8901073020239 | Britannia | Tiger Biscuits | 450 | 6 | 74 | 14 |  |  |  |  |  |
| 8 | 8901063080032 | PepsiCo | Lays Classic Salted | 540 | 5 | 53 | 34 |  |  |  |  |  |
| 9 | 8901063080025 | PepsiCo | Lays Indian Magic Masala | 540 | 5 | 53 | 34 |  |  |  |  |  |
| 10 | 8901063080049 | PepsiCo | Kurkure Masala Munch | 530 | 5.5 | 55 | 32 |  |  |  |  |  |
| 11 | 8901063000030 | PepsiCo | Pringles Original | 530 | 4 | 49 | 35 |  |  |  |  |  |
| 12 | 8901058001089 | PepsiCo | Cheetos Puffs | 510 | 5 | 56 | 29 |  |  |  |  |  |
| 13 | 8901719102080 | Haldiram | Haldirams Aloo Bhujia | 520 | 12 | 48 | 31 |  |  |  |  |  |
| 14 | 8901719101427 | Haldiram | Haldirams Bhelpuri | 480 | 8 | 58 | 24 |  |  |  |  |  |
| 15 | 8902080315010 | Amul | Amul Butter | 720 | 0 | 0 | 81 |  |  |  |  |  |
| 16 | 8902080316215 | Amul | Amul Cheese Slices | 350 | 22 | 3 | 28 |  |  |  |  |  |
| 17 | 8902080318158 | Amul | Amul Masti Dahi (Curd) | 65 | 3.5 | 7 | 2.5 |  |  |  |  |  |
| 18 | 8902080312019 | Amul | Amul Taaza Milk | 65 | 3.2 | 5 | 3.5 |  |  |  |  |  |
| 19 | 8902080312026 | Amul | Amul Gold Milk | 80 | 3.5 | 5 | 5 |  |  |  |  |  |
| 20 | 8902080318011 | Amul | Amul Lassi | 70 | 2 | 10 | 2.5 |  |  |  |  |  |
| 21 | 8904068004018 | Mother Dairy | Mother Dairy Dahi | 60 | 3 | 6 | 2.5 |  |  |  |  |  |
| 22 | 8904068002014 | Mother Dairy | Mother Dairy Toned Milk | 65 | 3.2 | 5 | 3.5 |  |  |  |  |  |
| 23 | 8902080006383 | Cadbury | Cadbury Bournvita | 380 | 5 | 82 | 3 |  |  |  |  |  |
| 24 | 8901058004066 | Cadbury | Cadbury Drinking Chocolate | 400 | 5 | 78 | 6 |  |  |  |  |  |
| 25 | 8901058030010 | Coca-Cola | Coca-Cola 250ml | 42 | 0 | 10.6 | 0 |  |  |  |  |  |
| 26 | 8901058030027 | Coca-Cola | Sprite 250ml | 42 | 0 | 10.5 | 0 |  |  |  |  |  |
| 27 | 8901058030034 | Coca-Cola | Thums Up 250ml | 45 | 0 | 11.2 | 0 |  |  |  |  |  |
| 28 | 8901760102990 | Red Bull | Red Bull 250ml | 45 | 0 | 11 | 0 |  |  |  |  |  |
| 29 | 8901058070016 | Coca-Cola | Maaza Mango Drink | 48 | 0 | 12 | 0 |  |  |  |  |  |
| 30 | 8901719120015 | Nestle | Maggi 2-Minute Noodles Masala | 375 | 8 | 60 | 11 |  |  |  |  |  |
| 31 | 8901719120022 | Nestle | Maggi 2-Minute Noodles Chicken | 375 | 8.5 | 60 | 11 |  |  |  |  |  |
| 32 | 8901719120077 | Nestle | Maggi Atta Noodles | 355 | 9 | 65 | 7 |  |  |  |  |  |
| 33 | 8901719120039 | ITC | Yippee Noodles Masala | 370 | 7.5 | 62 | 10 |  |  |  |  |  |
| 34 | 8901719120046 | ITC | Yippee Noodles Chicken | 370 | 8 | 62 | 10 |  |  |  |  |  |
| 35 | 8901058001096 | Kissan | Kissan Tomato Ketchup | 110 | 1 | 26 | 0.1 |  |  |  |  |  |
| 36 | 8901719120305 | Nestle | Maggi Hot & Sweet Sauce | 130 | 0.5 | 28 | 1 |  |  |  |  |  |
| 37 | 8901719120107 | Nestle | Maggi Chilli Sauce | 95 | 1 | 20 | 0.5 |  |  |  |  |  |
| 38 | 8901035070018 | Ferrero | Nutella Hazelnut Spread | 540 | 6 | 58 | 31 |  |  |  |  |  |
| 39 | 8901058050018 | Kellogg | Kellogggs Corn Flakes | 380 | 7 | 85 | 1 |  |  |  |  |  |
| 40 | 8901058050025 | Kellogg | Kellogggs Muesli Fruit & Nut | 370 | 8 | 70 | 6 |  |  |  |  |  |
| 41 | 8901058050032 | Kellogg | Kellogggs Oats | 370 | 13 | 65 | 7 |  |  |  |  |  |
| 42 | 8901035010113 | PepsiCo | Quaker Oats | 370 | 12 | 66 | 7 |  |  |  |  |  |
| 43 | 8901058080015 | Danone | Protinex Chocolate Bar | 420 | 20 | 55 | 14 |  |  |  |  |  |
| 44 | 8901058080022 | Danone | Protinex Berry Bar | 400 | 18 | 55 | 12 |  |  |  |  |  |
| 45 | 8901073030085 | Britannia | Britannia NutriChoice Protein Bar | 410 | 15 | 50 | 16 |  |  |  |  |  |
| 46 | 8901719120206 | MTR | MTR Sambar Rice Mix | 350 | 8 | 70 | 4 |  |  |  |  |  |
| 47 | 8901719120213 | MTR | MTR Puliyogare Mix | 360 | 7 | 72 | 5 |  |  |  |  |  |
| 48 | 8901719120220 | MTR | MTR Masala Dosa Mix | 340 | 9 | 68 | 4 |  |  |  |  |  |
| 49 | 8901719120237 | MTR | MTR Rava Idli Mix | 345 | 8 | 70 | 3 |  |  |  |  |  |
| 50 | 8901719120244 | MTR | MTR Upma Mix | 350 | 8 | 69 | 4 |  |  |  |  |  |
| 51 | 8901058000051 | Tata | Taj Mahal Tea | 0 | 0 | 0 | 0 |  |  |  |  |  |
| 52 | 8901058000068 | Tata | Tata Tea Gold | 0 | 0 | 0 | 0 |  |  |  |  |  |
| 53 | 8901058002017 | Hindustan Unilever | Bru Instant Coffee | 2 | 0.2 | 0.3 | 0 |  |  |  |  |  |
| 54 | 8901058002031 | Nestle | Nescafe Classic | 2 | 0.2 | 0.3 | 0 |  |  |  |  |  |

## Groups

- **Amul** — 6: Amul Butter, Amul Cheese Slices, Amul Masti Dahi (Curd), Amul Taaza Milk, Amul Gold Milk, Amul Lassi
- **Britannia** — 3: Good Day Biscuits, Tiger Biscuits, Britannia NutriChoice Protein Bar
- **Cadbury** — 3: Oreo Cookies, Cadbury Bournvita, Cadbury Drinking Chocolate
- **Coca-Cola** — 4: Coca-Cola 250ml, Sprite 250ml, Thums Up 250ml, Maaza Mango Drink
- **Danone** — 2: Protinex Chocolate Bar, Protinex Berry Bar
- **Ferrero** — 1: Nutella Hazelnut Spread
- **Haldiram** — 2: Haldirams Aloo Bhujia, Haldirams Bhelpuri
- **Hindustan Unilever** — 1: Bru Instant Coffee
- **ITC** — 2: Yippee Noodles Masala, Yippee Noodles Chicken
- **Kellogg** — 3: Kellogggs Corn Flakes, Kellogggs Muesli Fruit & Nut, Kellogggs Oats
- **Kissan** — 1: Kissan Tomato Ketchup
- **MTR** — 5: MTR Sambar Rice Mix, MTR Puliyogare Mix, MTR Masala Dosa Mix, MTR Rava Idli Mix, MTR Upma Mix
- **Mother Dairy** — 2: Mother Dairy Dahi, Mother Dairy Toned Milk
- **Nestle** — 6: Maggi 2-Minute Noodles Masala, Maggi 2-Minute Noodles Chicken, Maggi Atta Noodles, Maggi Hot & Sweet Sauce, Maggi Chilli Sauce, Nescafe Classic
- **Parle** — 4: Marie Gold Biscuits, Parle-G Biscuits, Hide & Seek Biscuits, Monaco Biscuits
- **PepsiCo** — 6: Lays Classic Salted, Lays Indian Magic Masala, Kurkure Masala Munch, Pringles Original, Cheetos Puffs, Quaker Oats
- **Red Bull** — 1: Red Bull 250ml
- **Tata** — 2: Taj Mahal Tea, Tata Tea Gold
