import 'package:flutter/material.dart';
import 'dart:convert';
import 'user_edit_page.dart';
import '../../utils/api_client.dart';

class UserDetailsPage extends StatefulWidget {
  final Map<String, dynamic> user;

  const UserDetailsPage({super.key, required this.user});

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  Map<String, dynamic>? _userStats;
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _userActivity = [];
  final TextEditingController _adminNoteController = TextEditingController();
  final TextEditingController _suspensionReasonController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadUserDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _adminNoteController.dispose();
    _suspensionReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadUserDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response =
          await ApiClient.get('/api/admin/users/${widget.user['_id']}/details');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          if (data['user'] is Map) {
            widget.user.addAll(Map<String, dynamic>.from(data['user']));
          }
          _userStats = data['stats'];
          _recentTransactions =
              List<Map<String, dynamic>>.from(data['recentTransactions'] ?? []);
          _userActivity =
              List<Map<String, dynamic>>.from(data['userActivity'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading user details: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleUserStatus() async {
    final currentStatus = widget.user['isActive'] ?? false;

    try {
      final response = await ApiClient.patch(
          '/api/admin/users/${widget.user['_id']}/status',
          body: {'isActive': !currentStatus});

      if (response.statusCode == 200) {
        setState(() {
          widget.user['isActive'] = !currentStatus;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'User ${!currentStatus ? 'activated' : 'deactivated'} successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isActive = user['isActive'] ?? false;
    final isVerified = user['isVerified'] ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: Text(
          user['name'] ?? 'User Details',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserEditPage(user: user),
                ),
              ).then((_) => _loadUserDetails());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // User Profile Header
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Profile Image and Basic Info
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: const Color(0xFF00B4D8),
                            child: _buildProfileImage(user),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user['name'] ?? 'Unknown User',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user['email'] ?? 'No email',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '@${user['username'] ?? 'unknown'}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF00B4D8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Status Indicators
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isActive ? Colors.green : Colors.red,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isActive ? Icons.check_circle : Icons.block,
                                    color: isActive ? Colors.green : Colors.red,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          isActive ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: isVerified
                                    ? Colors.blue.withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      isVerified ? Colors.blue : Colors.orange,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isVerified ? Icons.verified : Icons.pending,
                                    color: isVerified
                                        ? Colors.blue
                                        : Colors.orange,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isVerified ? 'Verified' : 'Pending',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isVerified
                                          ? Colors.blue
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _toggleUserStatus,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isActive ? Colors.red : Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                isActive ? 'Deactivate' : 'Activate',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: isVerified
                                ? OutlinedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              UserEditPage(user: user),
                                        ),
                                      ).then((_) => _loadUserDetails());
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: Color(0xFF00B4D8)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      'Edit User',
                                      style:
                                          TextStyle(color: Color(0xFF00B4D8)),
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: _reviewPendingUser,
                                    icon: const Icon(Icons.fact_check_rounded),
                                    label: const Text('Review Pending'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                          ),
                          if (!isVerified) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          UserEditPage(user: user),
                                    ),
                                  ).then((_) => _loadUserDetails());
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Color(0xFF00B4D8)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'Edit User',
                                  style: TextStyle(color: Color(0xFF00B4D8)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Tab Bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF00B4D8),
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: const Color(0xFF00B4D8),
                    tabs: const [
                      Tab(text: 'Profile'),
                      Tab(text: 'Stats'),
                      Tab(text: 'Transactions'),
                      Tab(text: 'Activity'),
                    ],
                  ),
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildProfileTab(),
                      _buildStatsTab(),
                      _buildTransactionsTab(),
                      _buildActivityTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileTab() {
    final user = widget.user;
    final adminNotes =
        List<Map<String, dynamic>>.from(user['adminNotes'] ?? const []);
    final suspendedUntil = DateTime.tryParse('${user['suspendedUntil'] ?? ''}');
    final isSuspended =
        suspendedUntil != null && suspendedUntil.isAfter(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildInfoSection('Personal Information', [
            _buildInfoTile('Full Name', user['name'] ?? 'Not provided'),
            _buildInfoTile('Username', '@${user['username'] ?? 'unknown'}'),
            _buildInfoTile('Email', user['email'] ?? 'Not provided'),
            _buildInfoTile('Phone', user['phone'] ?? 'Not provided'),
            _buildInfoTile('Gender', user['gender'] ?? 'Not specified'),
            _buildInfoTile(
                'Date of Birth', user['dateOfBirth'] ?? 'Not provided'),
            _buildInfoTile('Address', user['address'] ?? 'Not provided'),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('Account Information', [
            _buildInfoTile('User ID', user['_id'] ?? 'Unknown'),
            _buildInfoTile('Account Type', user['role'] ?? 'User'),
            _buildInfoTile('Joined Date', _formatDate(user['createdAt'])),
            _buildInfoTile(
                'Last Activity', _formatDate(_userStats?['lastActivity'])),
            _buildInfoTile('Alternative Email', user['altEmail'] ?? 'Not set'),
            _buildInfoTile(
              'LenDen Coins',
              (_userStats?['lenDenCoins'] ?? user['lenDenCoins'] ?? 0)
                  .toString(),
            ),
            _buildInfoTile(
              'Subscription',
              (_userStats?['activeSubscription'] is Map)
                  ? ((_userStats?['activeSubscription']['plan'] ??
                          'Active plan')
                      .toString())
                  : 'Not active',
            ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('Account Status', [
            _buildInfoTile('Account Status',
                widget.user['isActive'] == true ? 'Active' : 'Inactive'),
            _buildInfoTile('Email Verified',
                widget.user['isVerified'] == true ? 'Yes' : 'No'),
            _buildInfoTile('Phone Verified',
                widget.user['phoneVerified'] == true ? 'Yes' : 'No'),
            _buildInfoTile(
                'Two-Factor Auth',
                widget.user['twoFactorEnabled'] == true
                    ? 'Enabled'
                    : 'Disabled'),
            _buildInfoTile(
              'Suspension',
              isSuspended
                  ? 'Until ${_formatDate(user['suspendedUntil'])}'
                  : 'Not suspended',
            ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('Admin Controls', [
            TextField(
              controller: _suspensionReasonController,
              decoration: InputDecoration(
                labelText: 'Suspension Reason',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _updateSuspension(clear: false),
                    icon: const Icon(Icons.lock_clock_outlined),
                    label: const Text('Suspend'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _updateSuspension(clear: true),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Clear'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _forceLogoutUser,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'Force Logout User',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('Internal Admin Notes', [
            TextField(
              controller: _adminNoteController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Add internal note',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _addAdminNote,
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Save Note'),
              ),
            ),
            if (adminNotes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No internal notes added yet.'),
              ),
            ...adminNotes.take(5).map(
              (note) => Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (note['noteText'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'By ${(note['admin'] is Map ? note['admin']['email'] : 'Admin') ?? 'Admin'}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDate(note['createdAt']),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    if (_userStats == null) {
      return const Center(
        child: Text('No statistics available'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                      'Total Transactions',
                      _userStats!['totalTransactions']?.toString() ?? '0',
                      Icons.receipt)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildStatCard(
                      'Total Amount',
                      '\$${_userStats!['totalAmount']?.toString() ?? '0'}',
                      Icons.attach_money)),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                      'Secure',
                      _userStats!['secureTransactions']?.toString() ?? '0',
                      Icons.shield_outlined)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildStatCard(
                      'Quick',
                      _userStats!['quickTransactions']?.toString() ?? '0',
                      Icons.flash_on_rounded)),
            ],
          ),

          const SizedBox(height: 16),

          // Detailed Stats
          _buildInfoSection('Transaction Statistics', [
            _buildInfoTile('Successful Transactions',
                _userStats!['successfulTransactions']?.toString() ?? '0'),
            _buildInfoTile('Pending / Uncleared',
                _userStats!['pendingTransactions']?.toString() ?? '0'),
            _buildInfoTile('Average Transaction',
                _formatCurrency(_userStats!['averageTransaction'])),
            _buildInfoTile('Largest Transaction',
                _formatCurrency(_userStats!['largestTransaction'])),
          ]),

          const SizedBox(height: 16),

          _buildInfoSection('Activity Statistics', [
            _buildInfoTile(
                'Groups Joined', _userStats!['totalGroups']?.toString() ?? '0'),
            _buildInfoTile('Groups Created',
                _userStats!['groupsCreated']?.toString() ?? '0'),
            _buildInfoTile(
                'Friends', _userStats!['totalFriends']?.toString() ?? '0'),
            _buildInfoTile(
                'Days Active', _userStats!['daysActive']?.toString() ?? '0'),
            _buildInfoTile(
                'Last Activity', _formatDate(_userStats!['lastActivity'])),
            _buildInfoTile(
                'Login Count', _userStats!['loginCount']?.toString() ?? '0'),
          ]),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return _recentTransactions.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No transactions found',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _recentTransactions.length,
            itemBuilder: (context, index) {
              final transaction = _recentTransactions[index];
              return _buildTransactionCard(transaction);
            },
          );
  }

  Widget _buildActivityTab() {
    return _userActivity.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No activity found',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _userActivity.length,
            itemBuilder: (context, index) {
              final activity = _userActivity[index];
              return _buildActivityCard(activity);
            },
          );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00B4D8),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF00B4D8), size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final amount = transaction['amount'];
    final date = transaction['createdAt'] ?? transaction['date'];
    final status = (transaction['status'] ?? 'unknown').toString();
    final source = (transaction['source'] ?? 'secure').toString();
    final counterpart = (transaction['counterpart'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00B4D8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.receipt,
              color: const Color(0xFF00B4D8),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${source == 'quick' ? 'Quick' : 'Secure'} Transaction',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Amount: ${_formatCurrency(amount, transaction['currency'])}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                if (counterpart.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Counterpart: $counterpart',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Date: ${_formatDate(date)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${status.replaceAll('_', ' ').capitalize()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(status),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Not available';
    try {
      final dateTime = DateTime.parse(date.toString()).toLocal();
      final twoDigits = (int n) => n.toString().padLeft(2, '0');
      return '${twoDigits(dateTime.day)}/${twoDigits(dateTime.month)}/${dateTime.year} ${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
    } catch (e) {
      return date.toString();
    }
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final action = (activity['action'] ?? 'activity').toString();
    final timestamp = activity['timestamp'];
    final when = _formatDate(timestamp);
    final title = (activity['title'] ?? _getActivityTitle(action)).toString();
    final description = (activity['description'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              blurRadius: 6,
              offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00B4D8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getActivityIcon(action),
              color: const Color(0xFF00B4D8),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 4),
              Text(when,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
        ],
      ),
    );
  }

  IconData _getActivityIcon(String action) {
    switch (action) {
      case 'user_registration':
        return Icons.person_add;
      case 'user_login':
        return Icons.login;
      case 'user_logout':
        return Icons.logout;
      case 'profile_update':
        return Icons.edit;
      case 'password_change':
        return Icons.lock;
      default:
        return Icons.info;
    }
  }

  String _getActivityTitle(String action) {
    switch (action) {
      case 'user_registration':
        return 'New user registered';
      case 'user_login':
        return 'User logged in';
      case 'user_logout':
        return 'User logged out';
      case 'profile_update':
        return 'Profile updated';
      case 'password_change':
        return 'Password changed';
      default:
        return 'Activity logged';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'successful':
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'partially_paid':
        return Colors.deepOrange;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _addAdminNote() async {
    final text = _adminNoteController.text.trim();
    if (text.isEmpty) return;

    try {
      final response = await ApiClient.post(
        '/api/admin/users/${widget.user['_id']}/notes',
        body: {'noteText': text},
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          final notes = List<Map<String, dynamic>>.from(
            widget.user['adminNotes'] ?? const [],
          );
          notes.insert(0, Map<String, dynamic>.from(data['note']));
          widget.user['adminNotes'] = notes;
        });
        _adminNoteController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Internal note added successfully')),
        );
      } else {
        throw Exception((data['message'] ?? 'Failed to add note').toString());
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _updateSuspension({required bool clear}) async {
    try {
      DateTime? selectedUntil;
      if (!clear) {
        final pickedDate = await showDatePicker(
          context: context,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (pickedDate == null) return;
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );
        if (pickedTime == null) return;
        selectedUntil = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
      }

      final response = await ApiClient.patch(
        '/api/admin/users/${widget.user['_id']}/suspension',
        body: clear
            ? {'clearSuspension': true}
            : {
                'suspendedUntil': selectedUntil?.toIso8601String(),
                'suspensionReason': _suspensionReasonController.text.trim(),
              },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          widget.user.addAll(Map<String, dynamic>.from(data['user']));
        });
        _suspensionReasonController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((data['message'] ?? 'Suspension updated').toString())),
        );
      } else {
        throw Exception((data['message'] ?? 'Failed to update suspension').toString());
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _forceLogoutUser() async {
    try {
      final response = await ApiClient.post(
        '/api/admin/users/${widget.user['_id']}/force-logout',
        body: const {},
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          widget.user.addAll(Map<String, dynamic>.from(data['user']));
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((data['message'] ?? 'User logged out').toString())),
        );
      } else {
        throw Exception((data['message'] ?? 'Failed to force logout').toString());
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _reviewPendingUser() async {
    try {
      final response = await ApiClient.patch(
        '/api/admin/users/${widget.user['_id']}/review-pending',
        body: const {},
      );
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          widget.user['isVerified'] = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (data['message'] ?? 'Pending user marked as verified')
                          .toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        throw Exception(
          (data['message'] ?? 'Failed to review pending user').toString(),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatCurrency(dynamic value, [dynamic currency]) {
    final amount = (value is num) ? value.toDouble() : double.tryParse('$value');
    if (amount == null) {
      return currency == null || '$currency'.isEmpty ? '$value' : '$currency $value';
    }
    final code = (currency ?? '').toString().trim();
    final formatted = amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2);
    return code.isEmpty ? '\$$formatted' : '$formatted $code';
  }

  Widget _buildProfileImage(Map<String, dynamic> user) {
    final imageUrl = user['profileImage'] ?? '';

    if (imageUrl.isEmpty) {
      return const Icon(
        Icons.person,
        size: 40,
        color: Colors.white,
      );
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.error,
            size: 40,
            color: Colors.red,
          );
        },
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
