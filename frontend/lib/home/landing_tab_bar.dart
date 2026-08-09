import 'package:flutter/material.dart';
import '../utils/responsive.dart';

class LandingTabBar extends StatefulWidget {
  const LandingTabBar({super.key});

  @override
  State<LandingTabBar> createState() => _LandingTabBarState();
}

class _LandingTabBarState extends State<LandingTabBar> {
  int _selected = 0;
  static const _tabs = ['QUICK', 'SECURE', 'GROUPS'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_tabs.length, (i) {
        final selected = i == _selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selected = i),
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _tabs[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.black87 : Colors.black45,
                    fontSize: context.sp(12),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: context.sh(5)),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: selected ? Colors.black87 : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
