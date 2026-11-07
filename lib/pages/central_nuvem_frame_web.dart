import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const String _viewType = 'exodo-central-nuvem-iframe';

bool _registrado = false;

Widget buildCentralNuvemFrame(String url, {Key? key}) {
  if (!_registrado) {
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = web.HTMLIFrameElement()
        ..src = url
        ..title = 'Painel operacional da Nuvem Êxodo'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#0f172a'
        ..setAttribute('loading', 'eager')
        ..setAttribute('referrerpolicy', 'no-referrer');
      return frame;
    });
    _registrado = true;
  }
  return HtmlElementView(key: key, viewType: _viewType);
}
