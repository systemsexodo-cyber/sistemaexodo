import 'package:flutter/material.dart';
import 'widgets/sync_status_widget.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const CustomAppBar({super.key, required this.title, this.actions, this.bottom});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;
    return AppBar(
      title: Text(
        title,
        overflow: TextOverflow.ellipsis,
      ),
      centerTitle: isMobile ? false : true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      bottom: bottom,
      actions: [
        const SyncStatusWidget(),
        if (actions != null) ...actions!,
      ],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));
}
