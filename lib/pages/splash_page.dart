import 'package:flutter/material.dart';
import '../services/home_data_service.dart';
import '../theme/app_colors.dart';
import 'tab_home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeInAnim;
  late Animation<double> _fadeOutAnim;

  bool _dataReady = false;
  bool _minTimeElapsed = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeInAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _fadeOutAnim = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );

    _fadeController.forward();

    _loadData();

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() => _minTimeElapsed = true);
        _tryNavigate();
      }
    });
  }

  Future<void> _loadData() async {
    await HomeData.load();
    if (mounted) {
      setState(() => _dataReady = true);
      _tryNavigate();
    }
  }

  void _tryNavigate() {
    if (_dataReady && _minTimeElapsed && !_exiting) {
      _exiting = true;
      // Fade out then navigate
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const TabHomePage(),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (_, anim, __, child) {
                return FadeTransition(opacity: anim, child: child);
              },
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bodyBg,
      body: Center(
        child: AnimatedBuilder(
          animation: _fadeController,
          builder: (context, _) {
            final opacity = _exiting
                ? _fadeOutAnim.value.clamp(0.0, 1.0)
                : _fadeInAnim.value.clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ZFB',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'AI 角色对话',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.subText,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.subText.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
