import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

// Model for Gift Card
class GiftCard {
  final String id;
  final String name;
  final int value;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;

  GiftCard({
    required this.id,
    required this.name,
    required this.value,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
  });

  factory GiftCard.fromJson(Map<String, dynamic> json) {
    return GiftCard(
      id: json['_id'],
      name: json['name'],
      value: json['value'],
      createdBy: json['createdBy'] is Map ? json['createdBy']['_id'] : json['createdBy'],
      createdByName: json['createdBy'] is Map ? json['createdBy']['name'] : 'N/A',
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

// Tab for viewing all gift cards
class ViewGiftCardsTab extends StatefulWidget {
  const ViewGiftCardsTab({Key? key}) : super(key: key);

  @override
  _ViewGiftCardsTabState createState() => _ViewGiftCardsTabState();
}

class _ViewGiftCardsTabState extends State<ViewGiftCardsTab> {
  List<GiftCard> _allGiftCards = [];
  List<GiftCard> _filteredGiftCards = [];
  bool _isLoading = true;
  String? _currentAdminId;
  bool _isCurrentAdminSuperAdmin = false;
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = 'createdAt_desc';

  @override
  void initState() {
    super.initState();
    _fetchGiftCards();
    _getCurrentAdminId();
    _searchController.addListener(() {
      _filterAndSortCards();
    });
  }

  @override
  void dispose(){
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentAdminId() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.user != null && session.isAdmin) {
      if(mounted){
        setState(() {
          _currentAdminId = session.user!['_id'];
          _isCurrentAdminSuperAdmin = session.user!['isSuperAdmin'] == true;
        });
      }
    }
  }

  Future<void> _fetchGiftCards() async {
    if(mounted){
      setState(() {
      _isLoading = true;
    });
    }
    
    try {
      final response = await ApiClient.get('/api/admin/giftcards');
      if(response.statusCode == 200){
        final List<dynamic> data = json.decode(response.body);
        if(mounted){
          setState(() {
            _allGiftCards = data.map((item) => GiftCard.fromJson(item)).toList();
            _filterAndSortCards();
            _isLoading = false;
          });
        }
      } else {
        if(mounted){
          setState(() {
            _isLoading = false;
          });
        }
        if (!mounted) return;
        showStylishSnackBar(context, AppLocalizations.of(context).t('failed_to_fetch_gift_cards'), isError: true);
      }
    } catch (e) {
      if(mounted){
        setState(() {
        _isLoading = false;
      });
      }
      if (!mounted) return;
      showStylishSnackBar(context, '${AppLocalizations.of(context).t('an_error_occurred')}: $e', isError: true);
    }
  }
  
  void _filterAndSortCards() {
    List<GiftCard> temp = _allGiftCards;

    // Search
    String query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      temp = temp.where((card) {
        return card.name.toLowerCase().contains(query) ||
               card.createdByName.toLowerCase().contains(query);
      }).toList();
    }

    // Sort
    temp.sort((a, b) {
      switch (_sortBy) {
        case 'name_asc':
          return a.name.compareTo(b.name);
        case 'name_desc':
          return b.name.compareTo(a.name);
        case 'value_asc':
          return a.value.compareTo(b.value);
        case 'value_desc':
          return b.value.compareTo(a.value);
        case 'createdAt_asc':
          return a.createdAt.compareTo(b.createdAt);
        case 'createdAt_desc':
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    });

    if(mounted){
      setState(() {
        _filteredGiftCards = temp;
      });
    }
  }

  Widget _buildOverviewChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.cyan,
        ),
      ),
    );
  }

  void _showSortOptions() {
    final t = AppLocalizations.of(context).t;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20)
        ),
        child: SingleChildScrollView(
          child: Wrap(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(t('sort_by'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppThemeColors.primaryText(context))),
              ),
              _buildSortOption(t('date_newest_first'), 'createdAt_desc', Icons.arrow_downward),
              _buildSortOption(t('date_oldest_first'), 'createdAt_asc', Icons.arrow_upward),
              _buildSortOption(t('name_a_z'), 'name_asc', Icons.sort_by_alpha),
              _buildSortOption(t('name_z_a'), 'name_desc', Icons.sort_by_alpha),
              _buildSortOption(t('value_high_low'), 'value_desc', Icons.trending_up),
              _buildSortOption(t('value_low_high'), 'value_asc', Icons.trending_down),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption(String title, String value, IconData icon) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        margin: EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: _sortBy == value
              ? AppThemeColors.tinted(context, light: const Color(0xFFE3F2FD), dark: const Color(0xFF1B3A4A))
              : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(13)
        ),
        child: ListTile(
          leading: Icon(icon, color: _sortBy == value ? AppColors.cyan : AppThemeColors.secondaryText(context)),
          title: Text(title, style: TextStyle(fontWeight: _sortBy == value ? FontWeight.bold : FontWeight.normal, color: AppThemeColors.primaryText(context))),
          onTap: () => _setSortBy(value),
        ),
      ),
    );
  }

  void _setSortBy(String sort) {
    Navigator.of(context).pop();
    setState(() {
      _sortBy = sort;
      _filterAndSortCards();
    });
  }

  void _showEditDialog(GiftCard giftCard) {
    final t = AppLocalizations.of(context).t;
    final _nameController = TextEditingController(text: giftCard.name);
    final _valueController = TextEditingController(text: giftCard.value.toString());
    final _formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(16),
          child: Container(
            padding: EdgeInsets.all(3), // Border width
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(dialogContext,
                    light: const Color(0xFFFCE4EC), dark: const Color(0xFF3A2230)), // Light pink
                borderRadius: BorderRadius.circular(17),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('edit_gift_card'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(dialogContext))),
                    SizedBox(height: 24),
                    _buildStylishEditTextField(
                      controller: _nameController,
                      label: t('gift_card_name'),
                      validator: (value) => value!.isEmpty ? t('please_enter_a_name') : null,
                    ),
                    SizedBox(height: 16),
                    _buildStylishEditTextField(
                      controller: _valueController,
                      label: t('lenden_coins_value'),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) return t('please_enter_a_value');
                        if (int.tryParse(value) == null) return t('enter_a_valid_number');
                        return null;
                      },
                    ),
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text(t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(dialogContext))),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              Navigator.of(dialogContext).pop();
                              await _updateGiftCard(giftCard.id, _nameController.text, int.parse(_valueController.text));
                            }
                          },
                          child: Text(t('save')),
                           style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStylishEditTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    FormFieldValidator<String>? validator,
  }) {
    return Container(
      padding: EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: InputBorder.none,
            filled: true,
            fillColor: AppThemeColors.cardBg(context),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          keyboardType: keyboardType,
          validator: validator,
        ),
      ),
    );
  }

  Future<void> _updateGiftCard(String id, String name, int value) async {
    try {
      final response = await ApiClient.put(
        '/api/admin/giftcards/$id',
        body: {'name': name, 'value': value},
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        showStylishSnackBar(context, AppLocalizations.of(context).t('gift_card_updated_successfully'));
        _fetchGiftCards();
      } else {
        final body = json.decode(response.body);
        if (!mounted) return;
        showStylishSnackBar(context, '${AppLocalizations.of(context).t('failed_to_update_gift_card')}: ${body['message']}', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      showStylishSnackBar(context, '${AppLocalizations.of(context).t('an_error_occurred')}: $e', isError: true);
    }
  }

  Future<void> _deleteGiftCard(String id) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(16),
          child: Container(
            padding: EdgeInsets.all(3), // Border width
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(dialogContext,
                    light: Colors.yellow[100]!, dark: const Color(0xFF3A3420)),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('delete_gift_card'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(dialogContext))),
                  SizedBox(height: 16),
                  Text(t('delete_gift_card_confirm'), style: TextStyle(color: AppThemeColors.primaryText(dialogContext), fontSize: 16)),
                  SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: Text(t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(dialogContext))),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(t('delete')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      try {
        final response = await ApiClient.delete('/api/admin/giftcards/$id');
        if (response.statusCode == 200) {
          if (!mounted) return;
          showStylishSnackBar(context, AppLocalizations.of(context).t('gift_card_deleted_successfully'));
          _fetchGiftCards();
        } else {
          final body = json.decode(response.body);
          if (!mounted) return;
          showStylishSnackBar(context, '${AppLocalizations.of(context).t('failed_to_delete_gift_card')}: ${body['message']}', isError: true);
        }
      } catch (e) {
        if (!mounted) return;
        showStylishSnackBar(context, '${AppLocalizations.of(context).t('an_error_occurred')}: $e', isError: true);
      }
    }
  }

  Color _getGiftCardColor(int index) {
    final lightColors = [
      Color(0xFFFFF4E6), // Cream
      Color(0xFFE8F5E9), // Light green
      Color(0xFFFCE4EC), // Light pink
      Color(0xFFE3F2FD), // Light blue
      Color(0xFFFFF9C4), // Light yellow
      Color(0xFFF3E5F5), // Light purple
    ];
    final darkColors = [
      Color(0xFF3A3120), // Cream (dark)
      Color(0xFF1E3324), // Light green (dark)
      Color(0xFF3A2230), // Light pink (dark)
      Color(0xFF1B3A4A), // Light blue (dark)
      Color(0xFF3A3420), // Light yellow (dark)
      Color(0xFF332A3A), // Light purple (dark)
    ];
    return AppThemeColors.isDark(context)
        ? darkColors[index % darkColors.length]
        : lightColors[index % lightColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: _buildStylishSearchBar(),
              ),
              _buildStylishSortButton(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildOverviewChip(t('cards_label'), '${_allGiftCards.length}'),
              _buildOverviewChip(t('visible_label'), '${_filteredGiftCards.length}'),
              _buildOverviewChip(
                t('total_value_label'),
                '${_allGiftCards.fold<int>(0, (sum, card) => sum + card.value)}',
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : _filteredGiftCards.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 80, color: AppThemeColors.mutedText(context)),
                          SizedBox(height: 16),
                          Text(
                            t('no_gift_cards_found'),
                            style: TextStyle(fontSize: 20, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _searchController.text.isNotEmpty ? t('try_a_different_search') : t('create_first_gift_card_hint'),
                            style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchGiftCards,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _filteredGiftCards.length,
                        itemBuilder: (context, index) {
                          final giftCard = _filteredGiftCards[index];
                          final bool canEdit =
                              _isCurrentAdminSuperAdmin ||
                              giftCard.createdBy == _currentAdminId;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                colors: [Colors.orange, Colors.white, Colors.green],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Card(
                              color: _getGiftCardColor(index),
                              elevation: 0,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      giftCard.name,
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      '${t('value_label')}: ${giftCard.value} ${t('lenden_coins_label')}',
                                      style: TextStyle(fontSize: 16, color: Colors.green.shade700),
                                    ),
                                    SizedBox(height: 12),
                                    Divider(),
                                    SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${t('created_by_label')} ${giftCard.createdByName}',
                                              style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              '${t('created_at_label')} ${DateFormat.yMMMd().format(giftCard.createdAt)}',
                                              style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
                                            ),
                                          ],
                                        ),
                                        if (canEdit)
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: Icon(Icons.edit, color: AppColors.cyan),
                                                onPressed: () => _showEditDialog(giftCard),
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.delete, color: Colors.red),
                                                onPressed: () => _deleteGiftCard(giftCard.id),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildStylishSearchBar() {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: EdgeInsets.all(8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(13),
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(color: AppThemeColors.primaryText(context)),
          decoration: InputDecoration(
            hintText: t('search_by_name_or_creator'),
            prefixIcon: Icon(Icons.search),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15)
          ),
        ),
      ),
    );
  }

  Widget _buildStylishSortButton() {
    return Container(
      margin: EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
        ),
      ),
      child: Container(
         decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(13),
        ),
        child: IconButton(
          icon: Icon(Icons.sort, color: AppThemeColors.primaryText(context)),
          onPressed: _showSortOptions,
        ),
      ),
    );
  }
}

// Tab for adding a new gift card
class AddGiftCardTab extends StatefulWidget {
  final TabController tabController;
  final VoidCallback onViewGiftCards;
  AddGiftCardTab({required this.tabController, required this.onViewGiftCards});

  @override
  _AddGiftCardTabState createState() => _AddGiftCardTabState();
}

class _AddGiftCardTabState extends State<AddGiftCardTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();
  bool _isSaving = false;

  Future<void> _createGiftCard() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSaving = true;
      });

      try {
        final response = await ApiClient.post(
          '/api/admin/giftcards',
          body: {
            'name': _nameController.text,
            'value': int.parse(_valueController.text),
          },
        );

        if (response.statusCode == 201) {
          if (!mounted) return;
          showStylishSnackBar(context, AppLocalizations.of(context).t('gift_card_created_successfully'));
          _nameController.clear();
          _valueController.clear();
          widget.onViewGiftCards();
          widget.tabController.animateTo(1);
        } else {
          final body = json.decode(response.body);
          if (!mounted) return;
          showStylishSnackBar(context, '${AppLocalizations.of(context).t('failed_to_create_gift_card')}: ${body['message']}', isError: true);
        }
      } catch (e) {
        if (!mounted) return;
        showStylishSnackBar(context, '${AppLocalizations.of(context).t('an_error_occurred')}: $e', isError: true);
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStylishTextField(
                controller: _nameController,
                label: t('gift_card_name'),
                validator: (value) => value!.isEmpty ? t('please_enter_a_name') : null,
              ),
              SizedBox(height: 16),
              _buildStylishTextField(
                controller: _valueController,
                label: t('lenden_coins_value'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value!.isEmpty) {
                    return t('please_enter_a_value');
                  }
                  if (int.tryParse(value) == null) {
                    return t('please_enter_a_valid_number');
                  }
                  return null;
                },
              ),
              SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    colors: [Colors.orange, Colors.white, Colors.green],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: EdgeInsets.all(2),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _createGiftCard,
                    child: _isSaving
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(t('create_gift_card'), style: TextStyle(color: Colors.white, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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

  Widget _buildStylishTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    FormFieldValidator<String>? validator,
  }) {
    return Container(
      padding: EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: AppThemeColors.cardBg(context),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          keyboardType: keyboardType,
          validator: validator,
        ),
      ),
    );
  }
}

// Main page for managing gift cards
class ManageGiftCardsPage extends StatefulWidget {
  @override
  _ManageGiftCardsPageState createState() => _ManageGiftCardsPageState();
}

class _ManageGiftCardsPageState extends State<ManageGiftCardsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_ViewGiftCardsTabState> _viewGiftCardsTabKey = GlobalKey<_ViewGiftCardsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(t('manage_gift_cards'),
            style: TextStyle(color: AppThemeColors.iconOnWave(context), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.iconOnWave(context)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppThemeColors.iconOnWave(context),
          unselectedLabelColor: AppThemeColors.iconOnWave(context).withValues(alpha: 0.7),
          indicatorColor: AppColors.cyan,
          indicatorWeight: 3,
          tabs: [
            Tab(text: t('add_gift_card_tab'), icon: Icon(Icons.add_card)),
            Tab(text: t('view_gift_cards_tab'), icon: Icon(Icons.card_giftcard)),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipPath(
              clipper: BottomWaveClipper(),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.13,
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: [
                AddGiftCardTab(tabController: _tabController, onViewGiftCards: () {
                  _viewGiftCardsTabKey.currentState?._fetchGiftCards();
                }),
                ViewGiftCardsTab(key: _viewGiftCardsTabKey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// Reusing wave clippers from admin_features_page.dart
class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.35);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.5,
        size.width * 0.5, size.height * 0.35);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.2, size.width, size.height * 0.35);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.6,
        size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.75, 0, size.width, size.height * 0.4);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
