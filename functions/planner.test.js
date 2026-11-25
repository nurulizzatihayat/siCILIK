const test = require('node:test');
const assert = require('node:assert/strict');
const { ageAt, guidelineFor, allergensOf, candidate, validatedMeals } = require('./planner');

const age = ageAt('2022-10-25', '2026-11-25');
const guide = guidelineFor(age);
const recipe = slot => ({
  name: 'Resipi ujian',
  steps: ['Langkah ujian'],
  mealPlanning: {
    reviewed: true,
    minAgeMonths: 48,
    maxAgeMonths: 83,
    texture: guide.texture,
    slots: [slot],
    allergens: ['eggs'],
    ingredients: [{name:'Beras', group:'Karbohidrat', quantity:50, unit:'g'}],
    serving: '1 hidangan',
    nutrientSource: 'Sumber ujian',
    verifiedNutritionPerServing: {energy:100, protein:8, calcium:-1},
  },
});

test('retrieves the six-slot guideline for a child aged 49 months', () => {
  assert.equal(age, 49);
  assert.deepEqual(guide.pages, [8, 9, 10, 11]);
  assert.equal(guide.slots.length, 6);
  assert.equal(guidelineFor(5), undefined);
});

test('rejects incompatible age, textures, and allergy aliases', () => {
  assert.equal(candidate('1', recipe('breakfast'), 47, guide, []), null);
  assert.equal(candidate('1', recipe('breakfast'), age, guide, allergensOf(['telur'])), null);
  assert.equal(allergensOf(['bahan yang tidak dikenali']), null);
  const wrongTexture = recipe('breakfast');
  wrongTexture.mealPlanning.texture = 'puri';
  assert.equal(candidate('1', wrongTexture, age, guide, []), null);
});

test('passes only checked recipes and facts into the saved plan', () => {
  const options = guide.slots.map(slot => candidate(slot, recipe(slot), age, guide, []));
  const meals = guide.slots.map(slot => ({slot, recipeId:slot, energy:9999}));
  const plan = validatedMeals({meals}, guide.slots, options, []);
  assert.equal(plan.length, 6);
  assert.deepEqual(plan[0].nutrition, {energy:100, protein:8});
  assert.equal(plan[0].energy, undefined);
  assert.throws(() => validatedMeals({meals:[{slot:'lunch',recipeId:'fake'}]}, ['lunch'], options, []));
  assert.throws(() => validatedMeals({meals:[{slot:'lunch',recipeId:'lunch'}]}, ['lunch'], options, ['lunch']));
});
