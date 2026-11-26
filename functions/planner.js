const guidelines = require('./kkm.json');
const groups = new Set(['Karbohidrat','Protein','Sayur-sayuran','Buah-buahan','Produk Tenusu','Bahan Masakan']);
const keys = ['energy','protein','calcium','iron'];
const tags = value => Array.isArray(value) && value.length <= 40 &&
  value.every(x => typeof x === 'string' && x.trim() && x.length <= 80)
  ? value.map(x => x.trim().toLowerCase()) : null;
const allergyGroups = [
  ['telur','egg','eggs'], ['susu','milk','tenusu','dairy','whey','kasein'],
  ['gandum','wheat','gluten'], ['soya','soy','soybeans'],
  ['ikan','fish'], ['kerang','shellfish','udang','ketam','moluska','sotong'],
  ['kacang tanah','peanut','peanuts'], ['kacang pokok','tree nuts','badam','gajus','walnut'],
  ['bijan','sesame'],
];
function allergensOf(value) {
  const list = tags(value);
  if (!list) return null;
  const normalized = list.map(tag => allergyGroups.find(group => group.includes(tag))?.[0]);
  return normalized.some(tag => !tag) ? null : [...new Set(normalized)].sort();
}
const label = (value, limit = 240) =>
  typeof value === 'string' && value.trim().length <= limit ? value.trim() : '';
function ageAt(birth, day) {
  if (typeof birth !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(birth) ||
      Number.isNaN(Date.parse(birth)) || new Date(birth).toISOString().slice(0,10) !== birth ||
      birth > day) return null;
  const [y,m,d] = day.split('-').map(Number);
  const [by,bm,bd] = birth.split('-').map(Number);
  return (y - by) * 12 + m - bm - (d < Math.min(bd, new Date(Date.UTC(y,m,0)).getUTCDate()) ? 1 : 0);
}
function guidelineFor(age) {
  const match = guidelines.find(g => age !== null && age >= g.min && age <= g.max);
  if (!match) return undefined;
  return {...match, source:'Rujukan Ilustrasi Contoh Menu Sehari Bagi Bayi & Kanak-kanak Kecil'};
}
function candidate(id, recipe, age, guideline, allergies) {
  const r = recipe.mealPlanning;
  if (!r || r.reviewed !== true || !Number.isInteger(r.minAgeMonths) ||
    !Number.isInteger(r.maxAgeMonths) || age < r.minAgeMonths || age > r.maxAgeMonths ||
    r.texture !== guideline.texture || !Array.isArray(r.slots) ||
    !label(recipe.name) || !label(r.serving) || !Array.isArray(r.ingredients) ||
    !r.ingredients.length || r.ingredients.length > 30 || !Array.isArray(recipe.steps) ||
    !recipe.steps.length || !recipe.steps.every(x => label(x, 700))) return null;
  const allergens = allergensOf(r.allergens);
  if (!allergens || allergens.some(x => allergies.includes(x))) return null;
  const ingredients = r.ingredients.map(i => ({
    name: label(i?.name), group: i?.group, quantity: i?.quantity, unit: label(i?.unit, 40),
  }));
  if (ingredients.some(i => !i.name || !groups.has(i.group) ||
    (i.quantity != null && (!Number.isFinite(i.quantity) || i.quantity <= 0 || !i.unit)))) return null;
  const source = label(r.nutrientSource);
  const nutrition = {};
  for (const key of keys) {
    const amount = r.verifiedNutritionPerServing?.[key];
    if (source && Number.isFinite(amount) && amount >= 0) nutrition[key] = amount;
  }
  return {
    recipeId: id, name: label(recipe.name), portion: label(r.serving), nutrition, nutrientSource: source,
    ingredients: ingredients.map(i => i.name),
    shopping: ingredients.map(i => ({...i, quantity: i.quantity ?? null})),
    steps: recipe.steps.slice(0,20),
    slots: r.slots.filter(slot => guideline.slots.includes(slot)),
    benefits: label(r.benefits), imageUrl: label(r.imageUrl, 2048),
  };
}
function validatedMeals(response, slots, candidates, excluded) {
  if (!Array.isArray(response?.meals) || response.meals.length !== slots.length) throw Error('Invalid meal count');
  const used = new Set(excluded);
  return slots.map(slot => {
    const choices = response.meals.filter(m => m?.slot === slot);
    const option = choices.length === 1 && candidates.find(c => c.recipeId === choices[0].recipeId);
    if (!option || used.has(option.recipeId) || !option.slots.includes(slot)) throw Error('Invalid recipe selection');
    used.add(option.recipeId);
    const {slots: allowed, ...meal} = option;
    return {...meal, slot, id: 'ai-' + slot + '-' + meal.recipeId,
      reason: 'Dipilih daripada resipi yang disemak untuk umur, tekstur dan waktu makan ini.'};
  });
}
module.exports = {ageAt, guidelineFor, candidate, validatedMeals, tags, allergensOf};
