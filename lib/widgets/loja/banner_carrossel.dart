import 'package:flutter/material.dart';

class BannerCarrossel extends StatelessWidget {
  final List<Map<String, dynamic>> banners;
  final PageController controller;
  final int currentIndex;
  final Function(int) onPageChanged;
  final Color corTextoBanner;

  const BannerCarrossel({
    super.key,
    required this.banners,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
    required this.corTextoBanner,
  });

  @override
  Widget build(BuildContext context) {
    if (banners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            PageView.builder(
              controller: controller,
              onPageChanged: onPageChanged,
              itemCount: banners.length,
              itemBuilder: (context, index) {
                final banner = banners[index];
                
                if (banner.containsKey('url')) {
                  return _buildBannerComImagem(
                    banner['url'] as String,
                    banner['texto'] as String? ?? '',
                    banner['link'] as String?,
                    corTextoBanner,
                  );
                }
                
                return _buildBannerPromocionalCarrossel(
                  banner['texto'] as String,
                  banner['cor'] as Color,
                );
              },
            ),
            if (banners.length > 1)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    banners.length,
                    (index) => GestureDetector(
                      onTap: () {
                        if (controller.hasClients) {
                          onPageChanged(index);
                          controller.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: currentIndex == index ? 32 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: currentIndex == index
                              ? Colors.white
                              : Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerComImagem(String url, String texto, String? link, Color corTexto) {
    return GestureDetector(
      onTap: link != null && link.isNotEmpty ? () {} : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.grey[200],
                child: const Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[200],
                child: const Center(child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey)),
              );
            },
          ),
          if (texto.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
                child: Text(
                  texto,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    height: 1.2,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBannerPromocionalCarrossel(String texto, Color cor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cor, cor.withOpacity(0.8)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
