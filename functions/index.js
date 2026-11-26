const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, FieldPath} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret, defineString} = require('firebase-functions/params');
const {randomUUID, createHash} = require('node:crypto');
const {ageAt, guidelineFor, candidate, validatedMeals, tags, allergensOf} = require('./planner');

initializeApp();
const db = getFirestore();
const key = defineSecret('GEMINI_API_KEY');
const model = defineString('GEMINI_MODEL');
const intakeHash = value => createHash('sha256').update(JSON.stringify(value ?? {})).digest('hex');

exports.generateNutritionPlan = onCall({secrets:[key], region:'asia-southeast1', timeoutSeconds:60,
  maxInstances:5}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sila log masuk semula.');
  const {childId, day, mode, slot} = request.data ?? {};
  if (typeof childId !== 'string' || typeof day !== 'string' ||
      !/^[a-zA-Z0-9_-]{1,128}$/.test(childId) || !/^\d{4}-\d{2}-\d{2}$/.test(day) ||
      !['generate','regenerate','replace','analyse'].includes(mode) ||
      Number.isNaN(Date.parse(day)) || new Date(day).toISOString().slice(0,10) !== day) {
    throw new HttpsError('invalid-argument', 'Maklumat permintaan tidak sah.');
  }

  const user = db.collection('users').doc(request.auth.uid);
  const child = user.collection('growth_children').doc(childId);
  const target = child.collection('nutrition_days').doc(day);
  const lock = user.collection('nutrition_controls').doc('generation');
  const lease = randomUUID();
  const profile = (await child.get()).data();
  if (!profile) throw new HttpsError('not-found', 'Profil anak tidak dijumpai.');
  const age = ageAt(profile.birth, day);
  const guide = guidelineFor(age);
  const allergies = allergensOf(profile.foodAllergies);
  const allergySnapshot = tags(profile.foodAllergies)?.sort();
  if (!guide) throw new HttpsError('failed-precondition', 'Tiada panduan KKM untuk umur ini.');
  if (!allergies) throw new HttpsError('failed-precondition', 'Sahkan alahan anak. Gunakan label yang disokong seperti telur, susu, gandum, soya, ikan, kerang, kacang tanah, kacang pokok atau bijan.');
  if (mode === 'replace' && !guide.slots.includes(slot)) {
    throw new HttpsError('invalid-argument', 'Waktu makan tidak sah.');
  }

  const state = await db.runTransaction(async tx => {
    const [saved, control] = await Promise.all([tx.get(target), tx.get(lock)]);
    const old = saved.data()?.generatedPlan;
    if (mode === 'generate' && old &&
        JSON.stringify(old.allergySnapshot) === JSON.stringify(allergySnapshot)) return {cached:true};
    if (mode === 'analyse' && saved.data()?.nutritionAnalysis &&
        saved.data().nutritionAnalysis.input === intakeHash(saved.data().intake) &&
        JSON.stringify(saved.data().nutritionAnalysis.allergySnapshot) === JSON.stringify(allergySnapshot)) return {cached:true};
    if (mode === 'replace' && !old?.meals?.some(m => m.slot === slot)) {
      throw new HttpsError('failed-precondition', 'Jana pelan dahulu.');
    }
    if ((control.data()?.lockedUntil ?? 0) > Date.now()) {
      throw new HttpsError('resource-exhausted', 'Tunggu sehingga permintaan sebelumnya selesai.');
    }
    tx.set(lock, {lease, lockedUntil:Date.now() + 65000});
    return {old, intake:saved.data()?.intake ?? {}, intakeUpdatedAt:saved.data()?.intakeUpdatedAt ?? null};
  });
  if (state.cached) return {saved:true, cached:true};

  try {
    const catalog = (await db.collection('recipes').where('mealPlanning.reviewed','==',true).limit(100).get())
      .docs.map(doc => candidate(doc.id,doc.data(),age,guide,allergies))
      .filter(x => x && x.slots.length);
    if (mode === 'analyse') {
      if (!Object.keys(state.intake).length) {
        throw new HttpsError('failed-precondition', 'Catat makanan yang dimakan dahulu.');
      }
      const counts = {energy:[], protein:[], calcium:[], iron:[]};
      for (const entry of Object.values(state.intake)) {
        for (const name of Object.keys(counts)) counts[name].push(entry?.nutrition?.[name]);
      }
      const recorded = Object.fromEntries(Object.entries(counts).map(([name, amounts]) =>
        [name, amounts.length && amounts.every(n => Number.isFinite(n) && n >= 0)
          ? amounts.reduce((sum,n) => sum + n, 0) : null]));
      if (Object.values(recorded).every(value => value == null)) {
        throw new HttpsError('failed-precondition', 'Nilai nutrien dalam catatan belum mencukupi untuk dianalisis.');
      }
      const result = await generate({
        task:'Pilih satu nutrien yang mempunyai rekod, satu kumpulan makanan dalam panduan dan sehingga tiga ID resipi alternatif daripada senarai. Beri JSON sahaja. Jangan diagnosis, beri sasaran atau cadangkan rawatan.',
        guide, recorded, candidates:catalog.map(o => ({id:o.recipeId, name:o.name, groups:o.shopping.map(i => i.group)})),
      }, {type:'OBJECT', properties:{ focus:{type:'STRING'}, group:{type:'STRING'},
        recipeIds:{type:'ARRAY',items:{type:'STRING'}} }, required:['focus','group','recipeIds']});
      if (!Object.hasOwn(recorded,result?.focus) || recorded[result.focus] == null ||
          !guide.groups.includes(result.group) || !Array.isArray(result.recipeIds) ||
          result.recipeIds.length > 3 || new Set(result.recipeIds).size !== result.recipeIds.length ||
          result.recipeIds.some(id => !catalog.some(recipe => recipe.recipeId === id))) throw Error('Invalid analysis');
      const alternatives = result.recipeIds.map(id => {
        const recipe = catalog.find(o => o.recipeId === id);
        return {id, name:recipe.name};
      });
      await db.runTransaction(async tx => {
        const [fresh, guard] = await Promise.all([tx.get(target), tx.get(lock)]);
        if (guard.data()?.lease !== lease || intakeHash(fresh.data()?.intake) !== intakeHash(state.intake)) {
          throw new HttpsError('aborted', 'Catatan berubah. Cuba analisis semula.');
        }
        tx.set(target, {nutritionAnalysis:{
          input:intakeHash(state.intake), intakeUpdatedAt:state.intakeUpdatedAt,
          focus:result.focus, group:result.group, alternatives, allergySnapshot,
        }},{merge:true});
      });
      return {saved:true};
    }

    const mealSlots = mode === 'replace' ? [slot] : guide.slots;
    const previous = (await child.collection('nutrition_days').where(FieldPath.documentId(),'<',day)
      .orderBy(FieldPath.documentId(),'desc').limit(5).get()).docs
      .flatMap(doc => doc.data().generatedPlan?.meals?.map(m => m.recipeId) ?? []);
    const excluded = mode === 'replace' ? state.old.meals.map(m => m.recipeId) : [];
    const options = catalog.filter(x => !excluded.includes(x.recipeId));
    if (mealSlots.some(s => !options.some(o => o.slots.includes(s)))) {
      throw new HttpsError('failed-precondition', 'Resipi yang telah disemak belum mencukupi untuk waktu makan ini.');
    }
    const catalogIngredients = new Set(options.flatMap(o => o.ingredients.map(i => i.toLowerCase())));
    const catalogNames = new Set(options.map(o => o.name.toLowerCase()));
    const favorites = (tags(profile.foodPreferences) ?? []).filter(x => catalogNames.has(x) || catalogIngredients.has(x));
    const available = (tags(profile.availableIngredients) ?? []).filter(x => catalogIngredients.has(x));
    const response = await generate({
      task:'Pilih satu ID resipi berbeza bagi setiap waktu. Guna ID daripada senarai sahaja. Utamakan bahan tersedia, citarasa dan variasi. Jangan cipta hidangan, sukatan, diagnosis atau nilai nutrien.',
      guide, ageMonths:age, mealSlots,
      preferences:favorites,
      availableIngredients:available,
      recentRecipeIds:[...new Set([...previous, ...(state.old?.meals?.map(m=>m.recipeId) ?? [])])],
      candidates:options.map(o => ({id:o.recipeId, slots:o.slots, name:o.name, ingredients:o.ingredients})),
    }, {type:'OBJECT', properties:{meals:{type:'ARRAY', items:{type:'OBJECT',
      properties:{slot:{type:'STRING'},recipeId:{type:'STRING'}},required:['slot','recipeId']}}},required:['meals']});
    const newMeals = validatedMeals(response,mealSlots,options,excluded);
    for (const meal of newMeals) {
      const ingredients = meal.ingredients.map(ingredient => ingredient.toLowerCase());
      if (favorites.includes(meal.name.toLowerCase()) || ingredients.some(item => favorites.includes(item))) {
        meal.reason += ' Hidangan ini sepadan dengan pilihan makanan yang direkodkan.';
      } else if (ingredients.every(item => available.includes(item))) {
        meal.reason += ' Semua bahan hidangan ini ada dalam senarai bahan tersedia.';
      }
    }
    if (mode === 'regenerate' && state.old &&
        newMeals.every(meal => state.old.meals.some(old =>
          old.slot === meal.slot && old.recipeId === meal.recipeId))) {
      throw new HttpsError('failed-precondition', 'AI belum menemui gabungan lain. Cuba tukar satu hidangan.');
    }
    const meals = mode === 'replace'
      ? state.old.meals.map(m => m.slot === slot ? newMeals[0] : m) : newMeals;
    await db.runTransaction(async tx => {
      const [guard, fresh] = await Promise.all([tx.get(lock), tx.get(child)]);
      if (guard.data()?.lease !== lease ||
          JSON.stringify(allergensOf(fresh.data()?.foodAllergies)) !== JSON.stringify(allergies) ||
          fresh.data()?.birth !== profile.birth) {
        throw new HttpsError('aborted', 'Profil anak berubah. Cuba lagi.');
      }
      tx.set(target,{generatedPlan:{meals,allergySnapshot,referencePages:guide.pages,category:guide.category,
        texture:guide.texture,updatedAt:FieldValue.serverTimestamp()}},{merge:true});
    });
    return {saved:true};
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('unavailable', 'AI tidak dapat melengkapkan permintaan. Menu rujukan masih tersedia.');
  } finally {
    await db.runTransaction(async tx => {
      const current = await tx.get(lock);
      if (current.data()?.lease === lease) tx.set(lock,{lease,lockedUntil:Date.now()+3000});
    });
  }
});

async function generate(input, schema) {
  const response = await fetch('https://generativelanguage.googleapis.com/v1beta/models/' +
    encodeURIComponent(model.value()) + ':generateContent', {
      method:'POST', signal:AbortSignal.timeout(35000),
      headers:{'Content-Type':'application/json','x-goog-api-key':key.value()},
      body:JSON.stringify({contents:[{parts:[{text:JSON.stringify(input)}]}],
        generationConfig:{responseMimeType:'application/json',responseSchema:schema}}),
    });
  if (!response.ok) throw Error('AI request failed');
  const data = await response.json();
  return JSON.parse(data.candidates?.[0]?.content?.parts?.map(p => p.text ?? '').join('') ?? '');
}
