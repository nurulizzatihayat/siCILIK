
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --------------------------------------------------
// COLORS
// --------------------------------------------------

const Color recipeOrange = Color(0xFFE45B64);
const Color recipeAmber = Color.fromARGB(255, 255, 159, 165);
const Color recipePanel = Color(0xFFF4F6FB);
const Color recipeChip = Color(0xFFEEF1F8);
const Color recipeText = Color(0xFF1F2430);
const Color recipeMuted = Color(0xFF8A94A6);

// --------------------------------------------------
// RECIPE MODEL
// --------------------------------------------------

class Recipe {
  final String id;
  final String name;
  final String description;
  final String emoji;
  final Color color;
  final List<String> ingredients;
  final List<String> steps;
  final String? servingSize;
  final String? ageSuitability;
  final int? minAgeMonths;
  final int? maxAgeMonths;
  final Map<String, dynamic>? nutrition;
  final List<String> advantages;
  final List<String> tips;
  final List<String> equipment;

  const Recipe({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.color,
    required this.ingredients,
    required this.steps,
    this.servingSize,
    this.ageSuitability,
    this.minAgeMonths,
    this.maxAgeMonths,
    this.nutrition,
    this.advantages = const [],
    this.tips = const [],
    this.equipment = const [],
  });

  factory Recipe.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? {};

    List<String> readStringList(dynamic value) {
      if (value is List) {
        return value.map((item) => item.toString()).toList();
      }
      return [];
    }

    return Recipe(
      id: document.id,
      name: data['name']?.toString() ?? 'Untitled Recipe',
      description: data['description']?.toString() ?? '',
      emoji: data['emoji']?.toString() ?? '🍲',
      color: const Color(0xFFE8E5FA),
      ingredients: readStringList(data['ingredients']),
      steps: readStringList(data['steps']),
      servingSize:
          data['yield']?.toString() ?? data['servingSize']?.toString(),
      ageSuitability: data['ageSuitability']?.toString(),
      minAgeMonths: data['minAgeMonths'] is int ? data['minAgeMonths'] as int : null,
      maxAgeMonths: data['maxAgeMonths'] is int ? data['maxAgeMonths'] as int : null,
      nutrition: data['nutrition'] is Map
          ? Map<String, dynamic>.from(data['nutrition'])
          : null,
      advantages: readStringList(data['advantages']),
      tips: readStringList(data['tips']),
      equipment: readStringList(data['equipment']),
    );
  }
}

// --------------------------------------------------
// RECIPES PAGE
// --------------------------------------------------

class RecipesPage extends StatefulWidget {
  // true = show only favourite recipes
  // false = show all recipes
  final bool showFavoritesOnly;

  const RecipesPage({
    super.key,
    this.showFavoritesOnly = false,
  });

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  String _searchText = '';

  Set<String> _favourites = {};
  bool _loadingFavourites = true;

  @override
  void initState() {
    super.initState();
    _loadFavourites();
  }

  // --------------------------------------------------
  // LOAD FAVOURITES
  // --------------------------------------------------

  Future<void> _loadFavourites() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _favourites = {};
        _loadingFavourites = false;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favourites')
          .get();

      if (!mounted) return;

      setState(() {
        _favourites = snapshot.docs.map((doc) => doc.id).toSet();
        _loadingFavourites = false;
      });

      debugPrint('Loaded ${_favourites.length} favourites.');
    } catch (e) {
      debugPrint('Error loading favourites: $e');

      if (!mounted) return;

      setState(() {
        _loadingFavourites = false;
      });
    }
  }

  // --------------------------------------------------
  // ADD OR REMOVE FAVOURITE
  // --------------------------------------------------

  Future<void> _toggleFavourite(String recipeId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sila log masuk untuk menyimpan resipi kegemaran.',
          ),
        ),
      );
      return;
    }

    final favouriteRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favourites')
        .doc(recipeId);

    final isFavourite = _favourites.contains(recipeId);

    try {
      if (isFavourite) {
        await favouriteRef.delete();

        if (!mounted) return;

        setState(() {
          _favourites.remove(recipeId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resipi dibuang daripada kegemaran.'),
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        await favouriteRef.set({
          'recipeId': recipeId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;

        setState(() {
          _favourites.add(recipeId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resipi disimpan ke kegemaran! ♡'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating favourite: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak berjaya mengemas kini kegemaran.'),
        ),
      );
    }
  }

  // --------------------------------------------------
  // BUILD PAGE
  // --------------------------------------------------

  
@override
Widget build(BuildContext context) {
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: recipeOrange,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Container(
                  width: double.infinity,
                  color: recipePanel,
                  child: Column(
                    children: [
                      _buildSearchBar(),
                      Expanded(
                        child: _buildRecipeList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


  // --------------------------------------------------
  // HEADER
  // --------------------------------------------------

  Widget _buildHeader() {
    final isFavoritesPage = widget.showFavoritesOnly;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(
              isFavoritesPage
                  ? Icons.favorite_rounded
                  : Icons.restaurant_menu_rounded,
              color: recipeOrange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFavoritesPage
                      ? 'Resipi Kegemaran'
                      : 'Resipi Sihat',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  isFavoritesPage
                      ? 'Koleksi resipi kegemaran anda'
                      : 'Resipi sihat untuk kesihatan anak anda',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // SEARCH BAR
  // --------------------------------------------------

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchText = value;
          });
        },
        decoration: InputDecoration(
          hintText: 'Cari resipi atau bahan...',
          hintStyle: const TextStyle(
            color: recipeMuted,
            fontSize: 14,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: recipeMuted,
          ),
          filled: true,
          fillColor: recipeChip,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: recipeOrange,
              width: 1.3,
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // FIRESTORE RECIPE LIST + FAVOURITE FILTER
  // --------------------------------------------------

  Widget _buildRecipeList() {
    // Wait until favourites are loaded before filtering.
    if (_loadingFavourites) {
      return const Center(
        child: CircularProgressIndicator(
          color: recipeOrange,
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('recipes')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('RECIPE FIRESTORE ERROR: ${snapshot.error}');

          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Unable to load recipes. Please check your connection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: recipeMuted),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: recipeOrange,
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'Tiada resipi tersedia buat masa ini.',
              style: TextStyle(color: recipeMuted),
            ),
          );
        }

        final recipes = snapshot.data!.docs
            .map((doc) => Recipe.fromFirestore(doc))
            .toList();

        // Sort by numeric Firestore document ID.
        recipes.sort((a, b) {
          final idA = int.tryParse(a.id) ?? 0;
          final idB = int.tryParse(b.id) ?? 0;
          return idA.compareTo(idB);
        });

        // First filter by favourites if this is the favourite page.
        final favouriteFilteredRecipes = widget.showFavoritesOnly
            ? recipes
                .where((recipe) => _favourites.contains(recipe.id))
                .toList()
            : recipes;

        // Then apply the search filter.
        final query = _searchText.toLowerCase().trim();

        final filteredRecipes = favouriteFilteredRecipes.where((recipe) {
          return query.isEmpty ||
              recipe.name.toLowerCase().contains(query) ||
              recipe.description.toLowerCase().contains(query) ||
              recipe.ingredients.any(
                (ingredient) =>
                    ingredient.toLowerCase().contains(query),
              ) ||
              recipe.advantages.any(
                (advantage) =>
                    advantage.toLowerCase().contains(query),
              );
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              widget.showFavoritesOnly
                  ? '${filteredRecipes.length} resipi kegemaran'
                  : '${filteredRecipes.length} resepi',
              style: const TextStyle(
                color: recipeMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),

            if (filteredRecipes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 48,
                  horizontal: 20,
                ),
                child: Column(
                  children: [
                    Icon(
                      widget.showFavoritesOnly
                          ? Icons.favorite_border_rounded
                          : Icons.search_off_rounded,
                      size: 48,
                      color: recipeMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.showFavoritesOnly
                          ? 'Anda belum mempunyai resipi kegemaran. Tekan ikon hati pada resipi untuk menyimpannya ♡'
                          : 'Tiada resipi ditemui. Cuba carian lain ♡',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: recipeMuted,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final recipe in filteredRecipes)
                RecipeCard(
                  recipe: recipe,
                  isFavourite: _favourites.contains(recipe.id),
                  onFavouriteTap: () => _toggleFavourite(recipe.id),
                ),
          ],
        );
      },
    );
  }
}

// --------------------------------------------------
// RECIPE CARD
// --------------------------------------------------

class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final bool isFavourite;
  final VoidCallback onFavouriteTap;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.isFavourite,
    required this.onFavouriteTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: recipeChip,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Resipi #${recipe.id}',
                  style: const TextStyle(
                    color: recipeOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: isFavourite
                    ? 'Buang dari kegemaran'
                    : 'Tambah ke kegemaran',
                onPressed: onFavouriteTap,
                icon: Icon(
                  isFavourite
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: isFavourite
                      ? Colors.redAccent
                      : recipeMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 104,
                  height: 100,
                  color: recipe.color,
                  alignment: Alignment.center,
                  child: Text(
                    recipe.emoji,
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: const TextStyle(
                        color: recipeText,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (recipe.description.isNotEmpty)
                      Text(
                        recipe.description,
                        style: const TextStyle(
                          color: recipeMuted,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    if (recipe.ageSuitability != null &&
                        recipe.ageSuitability!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        recipe.ageSuitability!,
                        style: const TextStyle(
                          color: recipeOrange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: recipeOrange,
                side: const BorderSide(color: recipeAmber),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecipeDetailPage(
                      recipe: recipe,
                    ),
                  ),
                );
              },
              child: const Text(
                'Lihat resipi  →',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// RECIPE DETAIL PAGE
// --------------------------------------------------

class RecipeDetailPage extends StatelessWidget {
  final Recipe recipe;

  const RecipeDetailPage({
    super.key,
    required this.recipe,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: recipeOrange,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Maklumat Resipi',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Container(
                  color: recipePanel,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                    children: [
                      // RECIPE IMAGE / EMOJI
                      Container(
                        height: 190,
                        decoration: BoxDecoration(
                          color: recipe.color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          recipe.emoji,
                          style: const TextStyle(fontSize: 88),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // RECIPE NAME
                      Text(
                        recipe.name,
                        style: const TextStyle(
                          color: recipeText,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (recipe.description.isNotEmpty)
                        Text(
                          recipe.description,
                          style: const TextStyle(
                            color: recipeMuted,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),

                      // ADDITIONAL INFORMATION
                      if (recipe.servingSize != null ||
                          recipe.ageSuitability != null) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (recipe.servingSize != null)
                              _InfoChip(
                                icon: Icons.restaurant,
                                text: recipe.servingSize!,
                              ),
                            if (recipe.ageSuitability != null)
                              _InfoChip(
                                icon: Icons.child_care,
                                text: recipe.ageSuitability!,
                              ),
                          ],
                        ),
                      ],

                      // INGREDIENTS
                      const SizedBox(height: 24),
                      const Text(
                        'Bahan-bahan',
                        style: TextStyle(
                          color: recipeText,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (recipe.ingredients.isEmpty)
                        const Text(
                          'Maklumat bahan tidak tersedia.',
                          style: TextStyle(color: recipeMuted),
                        )
                      else
                        ...recipe.ingredients.map(
                          (ingredient) => Padding(
                            padding: const EdgeInsets.only(bottom: 11),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: recipeOrange,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    ingredient,
                                    style: const TextStyle(
                                      color: recipeText,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // PREPARATION STEPS
                      const SizedBox(height: 18),
                      const Text(
                        'Mari kita buat!',
                        style: TextStyle(
                          color: recipeText,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (recipe.steps.isEmpty)
                        const Text(
                          'Langkah penyediaan tidak tersedia.',
                          style: TextStyle(color: recipeMuted),
                        )
                      else
                        ...List.generate(
                          recipe.steps.length,
                          (index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: recipeAmber,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 5),
                                      child: Text(
                                        recipe.steps[index],
                                        style: const TextStyle(
                                          color: recipeText,
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      // EQUIPMENT
                      if (recipe.equipment.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _DetailSection(
                          title: 'Peralatan',
                          items: recipe.equipment,
                          icon: Icons.kitchen_outlined,
                        ),
                      ],

                      // ADVANTAGES
                      if (recipe.advantages.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _DetailSection(
                          title: 'Kebaikan Resipi',
                          items: recipe.advantages,
                          icon: Icons.favorite_border,
                        ),
                      ],

                      // TIPS
                      if (recipe.tips.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _DetailSection(
                          title: 'Tips Penyediaan',
                          items: recipe.tips,
                          icon: Icons.lightbulb_outline,
                        ),
                      ],

                      // NUTRITION
                      if (recipe.nutrition != null &&
                          recipe.nutrition!.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Maklumat Nutrisi',
                          style: TextStyle(
                            color: recipeText,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...recipe.nutrition!.entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(
                                      color: recipeText,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Text(
                                  entry.value.toString(),
                                  style: const TextStyle(
                                    color: recipeOrange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // EXTRA IMAGES FOR FIRST FOUR RECIPES
                      if (recipe.id == '1') ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/recipe/Perbezaan Harga Sosej.png',
                            width: double.infinity,
                            height: 540,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],

                      if (recipe.id == '2') ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/recipe/Perbezaan Harga Keledek.png',
                            width: double.infinity,
                            height: 540,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],

                      if (recipe.id == '3') ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/recipe/Perbezaan Harga Nuget.png',
                            width: double.infinity,
                            height: 540,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],

                      if (recipe.id == '4') ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/recipe/Perbezaan Harga Bingsu.png',
                            width: double.infinity,
                            height: 540,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      const Text(
                        'Nikmati makanan anda! ♡',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: recipeOrange,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------
// INFORMATION CHIP
// --------------------------------------------------

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        icon,
        size: 16,
        color: recipeOrange,
      ),
      label: Text(text),
      backgroundColor: Colors.white,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      labelStyle: const TextStyle(
        color: recipeText,
        fontSize: 12,
      ),
    );
  }
}

// --------------------------------------------------
// DETAIL SECTION
// --------------------------------------------------

class _DetailSection extends StatelessWidget {
  final String title;
  final List<String> items;
  final IconData icon;

  const _DetailSection({
    required this.title,
    required this.items,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: recipeText,
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: recipeOrange,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: recipeText,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
