import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/api/api_client.dart';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  Map<String, dynamic>? _user;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchProfile();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _user = user);
  }

  Future<void> _fetchProfile() async {
    try {
      final response = await ApiClient.dio.get('/users/me');
      if (response.statusCode == 200) {
        final userData = response.data['data'] ?? response.data;
        await AuthStorage.saveUser(userData);
        if (mounted) setState(() => _user = userData);
      }
    } catch (e) {
      // Ignorer l'erreur pour l'instant si l'utilisateur peut toujours se déconnecter
    }
  }

  Future<void> _handleLogout() async {
    await AuthStorage.clear();
    if (mounted) context.go('/phone');
  }

  Future<void> _handleDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Supprimer mon compte ?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Cette action est irréversible. Toutes vos données seront effacées.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
             onPressed: () => Navigator.pop(context, true),
             child: const Text('Supprimer', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      await ApiClient.dio.delete('/users/me');
    } catch (e) {
      // Si on échoue à appeler l'API, on avertit l'utilisateur, mais on peut quand même le déconnecter
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e', style: const TextStyle(color: Colors.white))),
        );
      }
    } finally {
      await AuthStorage.clear();
      if (mounted) context.go('/phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon compte', style: TextStyle(fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/client/home'),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Profil Info
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: const Icon(Icons.person, size: 50, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _user?['name'] ?? _user?['firstName'] ?? 'Client',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _user?['phone'] ?? '',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                  const SizedBox(height: 40),

                  // Menu
                  _buildMenuItem(
                    icon: Icons.list_alt,
                    title: 'Mes commandes',
                    onTap: () {
                      // context.push('/orders/my');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bientôt disponible')),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMenuItem(
                    icon: Icons.logout,
                    title: 'Déconnexion',
                    onTap: _handleLogout,
                  ),
                  const SizedBox(height: 12),
                  _buildMenuItem(
                    icon: Icons.delete_forever,
                    title: 'Supprimer mon compte',
                    titleColor: AppColors.error,
                    iconColor: AppColors.error,
                    onTap: _handleDeleteAccount,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color titleColor = AppColors.textPrimary,
    Color iconColor = AppColors.primary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: titleColor, fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
