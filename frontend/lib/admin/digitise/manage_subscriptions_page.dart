import 'package:flutter/material.dart';
import 'dart:convert';
import '../../utils/api_client.dart';

class AdminFeaturesPage extends StatefulWidget {
  @override
  _AdminFeaturesPageState createState() => _AdminFeaturesPageState();
}

class _AdminFeaturesPageState extends State<AdminFeaturesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Manage Features',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Color(0xFF00B4D8),
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'Plans', icon: Icon(Icons.card_membership)),
            Tab(text: 'Benefits', icon: Icon(Icons.star)),
            Tab(text: 'FAQs', icon: Icon(Icons.help_outline)),
            Tab(text: 'Subscriptions', icon: Icon(Icons.subscriptions)),
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
                height: 150,
                color: const Color(0xFF00B4D8),
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
                color: const Color(0xFF00B4D8),
              ),
            ),
          ),
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: [
                SubscriptionPlansTab(),
                PremiumBenefitsTab(),
                FaqsTab(),
                ManageSubscriptionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Models
class SubscriptionPlan {
  final String id;
  final String name;
  final double price;
  final int duration;
  final List<String> features;
  final bool isAvailable;
  final String? offer;
  final int discount;
  final int free;

  SubscriptionPlan(
      {required this.id,
      required this.name,
      required this.price,
      required this.duration,
      required this.features,
      required this.isAvailable,
      this.offer,
      required this.discount,
      required this.free});

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['_id'],
      name: json['name'],
      price: json['price'].toDouble(),
      duration: json['duration'],
      features: List<String>.from(json['features']),
      isAvailable: json['isAvailable'],
      offer: json['offer'],
      discount: json['discount'] ?? 0,
      free: json['free'] ?? 0,
    );
  }
}

class PremiumBenefit {
  final String id;
  final String text;

  PremiumBenefit({required this.id, required this.text});

  factory PremiumBenefit.fromJson(Map<String, dynamic> json) {
    return PremiumBenefit(
      id: json['_id'],
      text: json['text'],
    );
  }
}

class Faq {
  final String id;
  final String question;
  final String answer;

  Faq({required this.id, required this.question, required this.answer});

  factory Faq.fromJson(Map<String, dynamic> json) {
    return Faq(
      id: json['_id'],
      question: json['question'],
      answer: json['answer'],
    );
  }
}

void showStylishSnackBar(BuildContext context, String message,
    {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Container(
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
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isError ? Color(0xFFFFEBEE) : Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle,
                color: isError ? Colors.red : Colors.green,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 3),
    ),
  );
}

// Subscription Plans Tab
class SubscriptionPlansTab extends StatefulWidget {
  @override
  _SubscriptionPlansTabState createState() => _SubscriptionPlansTabState();
}

class _SubscriptionPlansTabState extends State<SubscriptionPlansTab> {
  List<SubscriptionPlan> _plans = [];
  Map<String, bool> _isToggling = {};

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  Color _getCardColor(int index) {
    final colors = [
      Color(0xFFFFF4E6),
      Color(0xFFE8F5E9),
      Color(0xFFFCE4EC),
      Color(0xFFE3F2FD),
      Color(0xFFFFF9C4),
      Color(0xFFF3E5F5),
    ];
    return colors[index % colors.length];
  }

  Future<void> _fetchPlans() async {
    final response = await ApiClient.get('/api/admin/subscription-plans');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _plans = data.map((item) => SubscriptionPlan.fromJson(item)).toList();
      });
    } else {
      // Handle error
    }
  }

  Future<void> _togglePlanAvailability(
      SubscriptionPlan plan, bool isAvailable) async {
    setState(() {
      _isToggling[plan.id] = true;
    });

    try {
      final response = await ApiClient.put(
          '/api/admin/subscription-plans/${plan.id}',
          body: {
            'name': plan.name,
            'price': plan.price,
            'duration': plan.duration,
            'features': plan.features,
            'isAvailable': isAvailable,
          });

      if (response.statusCode == 200) {
        _fetchPlans();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Plan availability updated successfully')),
        );
      } else {
        // handle error
      }
    } catch (e) {
      showStylishSnackBar(context, 'An error occurred: $e', isError: true);
    } finally {
      if (mounted)
        setState(() {
          _isToggling[plan.id] = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _plans.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 80, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    'Nothing here',
                    style: TextStyle(
                        fontSize: 20,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add your first subscription plan',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _plans.length,
              itemBuilder: (context, index) {
                final plan = _plans[index];
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: _getCardColor(index),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      plan.name,
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '₹${plan.price} for ${plan.duration} days',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                              _isToggling[plan.id] ?? false
                                  ? SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Switch(
                                      value: plan.isAvailable,
                                      onChanged: (value) {
                                        _togglePlanAvailability(plan, value);
                                      },
                                      activeColor: Colors.green,
                                    ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                icon:
                                    Icon(Icons.edit, color: Color(0xFF00B4D8)),
                                onPressed: () => _showPlanDialog(plan: plan),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deletePlan(plan.id),
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
      floatingActionButton: Container(
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
            color: Color(0xFF00B4D8),
            borderRadius: BorderRadius.circular(28),
          ),
          child: FloatingActionButton.extended(
            onPressed: () => _showPlanDialog(),
            icon: Icon(Icons.add),
            label: Text('Add Plan'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
    );
  }

  void _showPlanDialog({SubscriptionPlan? plan}) {
    showDialog(
      context: context,
      builder: (context) {
        return PlanDialog(plan: plan, onSave: _fetchPlans);
      },
    );
  }

  Future<void> _deletePlan(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              color: Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
                SizedBox(height: 16),
                Text(
                  'Delete Plan',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete this plan?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child:
                          Text('Delete', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true) {
      final response =
          await ApiClient.delete('/api/admin/subscription-plans/$id');
      if (response.statusCode == 200) {
        _fetchPlans();
        showStylishSnackBar(context, 'Plan deleted successfully');
      } else {
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        showStylishSnackBar(
            context, body?['message'] ?? 'Failed to delete plan',
            isError: true);
      }
    }
  }
}

class PlanDialog extends StatefulWidget {
  final SubscriptionPlan? plan;
  final VoidCallback onSave;

  PlanDialog({this.plan, required this.onSave});

  @override
  _PlanDialogState createState() => _PlanDialogState();
}

class _PlanDialogState extends State<PlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late double _price;
  late int _duration;
  late List<String> _features;
  late int _discount;
  late int _free;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _name = widget.plan?.name ?? '';
    _price = widget.plan?.price ?? 0.0;
    _duration = widget.plan?.duration ?? 0;
    _features = widget.plan?.features ?? [];
    _discount = widget.plan?.discount ?? 0;
    _free = widget.plan?.free ?? 0;
  }

  Widget _buildStylishTextField({
    required String label,
    required String initialValue,
    required FormFieldValidator<String> validator,
    required FormFieldSetter<String> onSaved,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextFormField(
          initialValue: initialValue,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xFFFCE4EC),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.plan == null ? 'Add Plan' : 'Edit Plan',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  _buildStylishTextField(
                    label: 'Plan Name',
                    initialValue: _name,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a name' : null,
                    onSaved: (value) => _name = value!,
                  ),
                  _buildStylishTextField(
                    label: 'Price (₹)',
                    initialValue: _price.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a price' : null,
                    onSaved: (value) => _price = double.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: 'Duration (days)',
                    initialValue: _duration.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a duration' : null,
                    onSaved: (value) => _duration = int.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: 'Discount (%)',
                    initialValue: _discount.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a discount' : null,
                    onSaved: (value) => _discount = int.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: 'Free Days',
                    initialValue: _free.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter free days' : null,
                    onSaved: (value) => _free = int.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: 'Features (comma separated)',
                    initialValue: _features.join(', '),
                    maxLines: 3,
                    validator: (value) => null,
                    onSaved: (value) => _features = value!
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel'),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _savePlan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF00B4D8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Save',
                                style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _savePlan() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isSaving = true;
      });
      try {
        final body = {
          'name': _name,
          'price': _price,
          'duration': _duration,
          'features': _features,
          'discount': _discount,
          'free': _free,
        };
        final response = widget.plan == null
            ? await ApiClient.post('/api/admin/subscription-plans', body: body)
            : await ApiClient.put(
                '/api/admin/subscription-plans/${widget.plan!.id}',
                body: body);

        if (response.statusCode == 201 || response.statusCode == 200) {
          widget.onSave();
          Navigator.of(context).pop();
          showStylishSnackBar(context, 'Plan saved successfully');
        } else {
          final respBody =
              response.body.isNotEmpty ? json.decode(response.body) : null;
          showStylishSnackBar(
              context, respBody?['message'] ?? 'Failed to save plan',
              isError: true);
        }
      } catch (e) {
        showStylishSnackBar(context, 'An error occurred: $e', isError: true);
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }
}

// Premium Benefits Tab
class PremiumBenefitsTab extends StatefulWidget {
  @override
  _PremiumBenefitsTabState createState() => _PremiumBenefitsTabState();
}

class _PremiumBenefitsTabState extends State<PremiumBenefitsTab> {
  List<PremiumBenefit> _benefits = [];

  @override
  void initState() {
    super.initState();
    _fetchBenefits();
  }

  Color _getCardColor(int index) {
    final colors = [
      Color(0xFFFFF4E6),
      Color(0xFFE8F5E9),
      Color(0xFFFCE4EC),
      Color(0xFFE3F2FD),
      Color(0xFFFFF9C4),
      Color(0xFFF3E5F5),
    ];
    return colors[index % colors.length];
  }

  Future<void> _fetchBenefits() async {
    final response = await ApiClient.get('/api/admin/premium-benefits');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _benefits = data.map((item) => PremiumBenefit.fromJson(item)).toList();
      });
    } else {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _benefits.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 80, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    'Nothing here',
                    style: TextStyle(
                        fontSize: 20,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add your first premium benefit',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _benefits.length,
              itemBuilder: (context, index) {
                final benefit = _benefits[index];
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: _getCardColor(index),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.check_circle,
                          color: Color(0xFF00B4D8), size: 32),
                      title: Text(benefit.text,
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, color: Color(0xFF00B4D8)),
                            onPressed: () =>
                                _showBenefitDialog(benefit: benefit),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteBenefit(benefit.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: Container(
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
            color: Color(0xFF00B4D8),
            borderRadius: BorderRadius.circular(28),
          ),
          child: FloatingActionButton.extended(
            onPressed: () => _showBenefitDialog(),
            icon: Icon(Icons.add),
            label: Text('Add Benefit'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
    );
  }

  void _showBenefitDialog({PremiumBenefit? benefit}) {
    showDialog(
      context: context,
      builder: (context) {
        return BenefitDialog(benefit: benefit, onSave: _fetchBenefits);
      },
    );
  }

  Future<void> _deleteBenefit(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              color: Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
                SizedBox(height: 16),
                Text(
                  'Delete Benefit',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete this benefit?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child:
                          Text('Delete', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final response =
          await ApiClient.delete('/api/admin/premium-benefits/$id');
      if (response.statusCode == 200) {
        _fetchBenefits();
        showStylishSnackBar(context, 'Benefit deleted successfully');
      } else {
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        showStylishSnackBar(
            context, body?['message'] ?? 'Failed to delete benefit',
            isError: true);
      }
    }
  }
}

class BenefitDialog extends StatefulWidget {
  final PremiumBenefit? benefit;
  final VoidCallback onSave;

  BenefitDialog({this.benefit, required this.onSave});

  @override
  _BenefitDialogState createState() => _BenefitDialogState();
}

class _BenefitDialogState extends State<BenefitDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _text;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _text = widget.benefit?.text ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.benefit == null ? 'Add Benefit' : 'Edit Benefit',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Container(
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextFormField(
                        initialValue: _text,
                        decoration: InputDecoration(
                          labelText: 'Benefit Text',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        maxLines: 3,
                        validator: (value) =>
                            value!.isEmpty ? 'Please enter benefit text' : null,
                        onSaved: (value) => _text = value!,
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel'),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveBenefit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF00B4D8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Save',
                                style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveBenefit() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isSaving = true;
      });
      try {
        final body = {'text': _text};
        final response = widget.benefit == null
            ? await ApiClient.post('/api/admin/premium-benefits', body: body)
            : await ApiClient.put(
                '/api/admin/premium-benefits/${widget.benefit!.id}',
                body: body);

        if (response.statusCode == 201 || response.statusCode == 200) {
          widget.onSave();
          Navigator.of(context).pop();
          showStylishSnackBar(context, 'Benefit saved successfully');
        } else {
          final respBody =
              response.body.isNotEmpty ? json.decode(response.body) : null;
          showStylishSnackBar(
              context, respBody?['message'] ?? 'Failed to save benefit',
              isError: true);
        }
      } catch (e) {
        showStylishSnackBar(context, 'An error occurred: $e', isError: true);
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }
}

// FAQs Tab
class FaqsTab extends StatefulWidget {
  @override
  _FaqsTabState createState() => _FaqsTabState();
}

class _FaqsTabState extends State<FaqsTab> {
  List<Faq> _faqs = [];

  @override
  void initState() {
    super.initState();
    _fetchFaqs();
  }

  Color _getCardColor(int index) {
    final colors = [
      Color(0xFFFFF4E6),
      Color(0xFFE8F5E9),
      Color(0xFFFCE4EC),
      Color(0xFFE3F2FD),
      Color(0xFFFFF9C4),
      Color(0xFFF3E5F5),
    ];
    return colors[index % colors.length];
  }

  Future<void> _fetchFaqs() async {
    final response = await ApiClient.get('/api/admin/faqs');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _faqs = data.map((item) => Faq.fromJson(item)).toList();
      });
    } else {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _faqs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 80, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    'Nothing here',
                    style: TextStyle(
                        fontSize: 20,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add your first FAQ',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _faqs.length,
              itemBuilder: (context, index) {
                final faq = _faqs[index];
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: _getCardColor(index),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        ExpansionTile(
                          leading: Icon(Icons.help_outline,
                              color: Color(0xFF00B4D8), size: 28),
                          title: Text(
                            faq.question,
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Text(
                                faq.answer,
                                style: TextStyle(
                                    color: Colors.grey[700], fontSize: 14),
                              ),
                            ),
                          ],
                          tilePadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon:
                                    Icon(Icons.edit, color: Color(0xFF00B4D8)),
                                onPressed: () => _showFaqDialog(faq: faq),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteFaq(faq.id),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: Container(
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
            color: Color(0xFF00B4D8),
            borderRadius: BorderRadius.circular(28),
          ),
          child: FloatingActionButton.extended(
            onPressed: () => _showFaqDialog(),
            icon: Icon(Icons.add),
            label: Text('Add FAQ'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
    );
  }

  void _showFaqDialog({Faq? faq}) {
    showDialog(
      context: context,
      builder: (context) {
        return FaqDialog(faq: faq, onSave: _fetchFaqs);
      },
    );
  }

  Future<void> _deleteFaq(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              color: Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
                SizedBox(height: 16),
                Text(
                  'Delete FAQ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete this FAQ?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child:
                          Text('Delete', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final response = await ApiClient.delete('/api/admin/faqs/$id');
      if (response.statusCode == 200) {
        _fetchFaqs();
        showStylishSnackBar(context, 'FAQ deleted successfully');
      } else {
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        showStylishSnackBar(context, body?['message'] ?? 'Failed to delete FAQ',
            isError: true);
      }
    }
  }
}

class FaqDialog extends StatefulWidget {
  final Faq? faq;
  final VoidCallback onSave;

  FaqDialog({this.faq, required this.onSave});

  @override
  _FaqDialogState createState() => _FaqDialogState();
}

class _FaqDialogState extends State<FaqDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _question;
  late String _answer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _question = widget.faq?.question ?? '';
    _answer = widget.faq?.answer ?? '';
  }

  Widget _buildStylishTextField({
    required String label,
    required String initialValue,
    required FormFieldValidator<String> validator,
    required FormFieldSetter<String> onSaved,
    int maxLines = 1,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextFormField(
          initialValue: initialValue,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          maxLines: maxLines,
          validator: validator,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.faq == null ? 'Add FAQ' : 'Edit FAQ',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  _buildStylishTextField(
                    label: 'Question',
                    initialValue: _question,
                    maxLines: 2,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a question' : null,
                    onSaved: (value) => _question = value!,
                  ),
                  _buildStylishTextField(
                    label: 'Answer',
                    initialValue: _answer,
                    maxLines: 4,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter an answer' : null,
                    onSaved: (value) => _answer = value!,
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel'),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveFaq,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF00B4D8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Save',
                                style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveFaq() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isSaving = true;
      });
      try {
        final body = {'question': _question, 'answer': _answer};
        final response = widget.faq == null
            ? await ApiClient.post('/api/admin/faqs', body: body)
            : await ApiClient.put('/api/admin/faqs/${widget.faq!.id}',
                body: body);

        if (response.statusCode == 201 || response.statusCode == 200) {
          widget.onSave();
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('FAQ saved successfully')),
          );
        } else {
          final respBody =
              response.body.isNotEmpty ? json.decode(response.body) : null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Failed to save FAQ: ${respBody?['message'] ?? response.body}')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $e')),
        );
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }
}

// Wave Clippers
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

class ManageSubscriptionsTab extends StatefulWidget {
  @override
  _ManageSubscriptionsTabState createState() => _ManageSubscriptionsTabState();
}

class _ManageSubscriptionsTabState extends State<ManageSubscriptionsTab> {
  List<dynamic> _subscriptions = [];
  bool _searched = false;
  TextEditingController _searchController = TextEditingController();

  Widget _buildOverviewChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF0077B5),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
  }

  void _fetchSubscriptions({String? searchQuery}) async {
    setState(() {
      _searched = true;
    });
    try {
      String path = '/api/admin/subscriptions';
      if (searchQuery != null && searchQuery.isNotEmpty) {
        path += '?search=${Uri.encodeComponent(searchQuery)}';
      }
      final response = await ApiClient.get(path);
      if (response.statusCode == 200) {
        setState(() {
          _subscriptions = json.decode(response.body);
        });
      } else if (response.statusCode == 404) {
        final responseBody =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        showStylishSnackBar(context, responseBody?['message'] ?? 'Not found',
            isError: true);
        setState(() {
          _subscriptions = [];
        });
      } else {
        // Handle other errors
      }
    } catch (e) {
      // network / parsing error
    }
  }

  void _showEditSubscriptionDialog(dynamic subscription) {
    showDialog(
      context: context,
      builder: (context) {
        return EditSubscriptionDialog(
            subscription: subscription,
            onSave: () =>
                _fetchSubscriptions(searchQuery: _searchController.text));
      },
    );
  }

  Future<void> _deactivateSubscription(String subscriptionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              color: Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
                SizedBox(height: 16),
                Text(
                  'Deactivate Subscription',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'Are you sure you want to deactivate this subscription?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text('Deactivate',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final response = await ApiClient.put(
        '/api/admin/subscriptions/$subscriptionId/deactivate',
        body: {},
      );
      if (response.statusCode == 200) {
        _fetchSubscriptions(searchQuery: _searchController.text);
      } else {
        // Handle error
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Colors.orange, Colors.white, Colors.green],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name or email',
                        border: InputBorder.none,
                        prefixIcon:
                            Icon(Icons.search, color: Color(0xFF00B4D8)),
                      ),
                      onSubmitted: (value) {
                        _fetchSubscriptions(searchQuery: value);
                      },
                    ),
                  ),
                ),
                SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    _searchController.clear();
                    _fetchSubscriptions();
                  },
                  child: Text('View All Active Subscriptions'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildOverviewChip('Active', '${_subscriptions.length}'),
                    _buildOverviewChip(
                      'Free',
                      '${_subscriptions.where((s) => s['free'] == true).length}',
                    ),
                    _buildOverviewChip(
                      'Paid',
                      '${_subscriptions.where((s) => s['free'] != true).length}',
                    ),
                    _buildOverviewChip(
                      'Revenue',
                      '${_subscriptions.fold<num>(0, (sum, s) => sum + ((s['price'] ?? 0) as num))}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: !_searched
                ? Center(
                    child: Text('Search for a subscription to begin.'),
                  )
                : _subscriptions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox,
                                size: 80, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              'No subscriptions found',
                              style: TextStyle(
                                  fontSize: 20,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _subscriptions.length,
                        itemBuilder: (context, index) {
                          final sub = _subscriptions[index];
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.orange,
                                  Colors.white,
                                  Colors.green
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _getCardColor(index),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: ListTile(
                                title: Text(sub['user']?['name'] ?? 'No name',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                subtitle:
                                    Text(sub['user']?['email'] ?? 'No email'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit,
                                          color: Color(0xFF00B4D8)),
                                      onPressed: () {
                                        _showEditSubscriptionDialog(sub);
                                      },
                                    ),
                                    IconButton(
                                      icon:
                                          Icon(Icons.cancel, color: Colors.red),
                                      onPressed: () {
                                        _deactivateSubscription(sub['_id']);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Color _getCardColor(int index) {
    final colors = [
      Color(0xFFFFF4E6),
      Color(0xFFE8F5E9),
      Color(0xFFFCE4EC),
      Color(0xFFE3F2FD),
      Color(0xFFFFF9C4),
      Color(0xFFF3E5F5),
    ];
    return colors[index % colors.length];
  }
}

class EditSubscriptionDialog extends StatefulWidget {
  final dynamic subscription;
  final VoidCallback onSave;

  EditSubscriptionDialog({required this.subscription, required this.onSave});

  @override
  _EditSubscriptionDialogState createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<EditSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _subscriptionPlan;
  late int _duration;
  late double _price;
  late int _discount;
  late int _free;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _subscriptionPlan = widget.subscription['subscriptionPlan'];
    _duration = widget.subscription['duration'];
    _price = widget.subscription['price'].toDouble();
    _discount = widget.subscription['discount'];
    _free = widget.subscription['free'];
    _endDate = DateTime.parse(widget.subscription['endDate']);
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Widget _buildStylishTextField({
    required String label,
    required String initialValue,
    required FormFieldValidator<String> validator,
    required FormFieldSetter<String> onSaved,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextFormField(
          initialValue: initialValue,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xFFFCE4EC),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit Subscription',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  _buildStylishTextField(
                    label: 'Subscription Plan',
                    initialValue: _subscriptionPlan,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a plan name' : null,
                    onSaved: (value) => _subscriptionPlan = value!,
                  ),
                  _buildStylishTextField(
                    label: 'Duration (days)',
                    initialValue: _duration.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a duration' : null,
                    onSaved: (value) => _duration = int.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: 'Price',
                    initialValue: _price.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a price' : null,
                    onSaved: (value) => _price = double.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: 'Discount (%)',
                    initialValue: _discount.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a discount' : null,
                    onSaved: (value) => _discount = int.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: 'Free Days',
                    initialValue: _free.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter free days' : null,
                    onSaved: (value) => _free = int.parse(value!),
                  ),
                  SizedBox(height: 16),
                  Text('End Date',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Container(
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Text(
                            '${_endDate.toLocal().toString().substring(0, 10)}'),
                        trailing: Icon(Icons.calendar_today,
                            color: Color(0xFF00B4D8)),
                        onTap: () => _selectEndDate(context),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel'),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saveSubscription,
                        child: Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _saveSubscription() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final response = await ApiClient.put(
        '/api/admin/subscriptions/${widget.subscription['_id']}',
        body: {
          'subscriptionPlan': _subscriptionPlan,
          'duration': _duration,
          'price': _price,
          'discount': _discount,
          'free': _free,
          'endDate': _endDate.toIso8601String(),
        },
      );
      if (response.statusCode == 200) {
        widget.onSave();
        Navigator.of(context).pop();
      } else {
        // Handle error
      }
    }
  }
}
